// Package main implements a minimal, production-grade HTTP microservice
// exposing liveness (/healthz), Prometheus metrics (/metrics), and a
// business endpoint (/). Designed to run as a non-root user inside a
// distroless container with no shell.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/your-github-org/zt-devsecops-pipeline/app/internal/handlers"
)

const (
	defaultAddr     = ":8080"
	readTimeout     = 5 * time.Second
	writeTimeout    = 10 * time.Second
	idleTimeout     = 120 * time.Second
	shutdownTimeout = 15 * time.Second
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	addr := defaultAddr
	if v := os.Getenv("LISTEN_ADDR"); v != "" {
		addr = v
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handlers.Healthz)
	mux.Handle("/metrics", handlers.Metrics())
	mux.HandleFunc("/", handlers.Root)

	srv := &http.Server{
		Addr:              addr,
		Handler:           handlers.WithObservability(logger, mux),
		ReadTimeout:       readTimeout,
		ReadHeaderTimeout: readTimeout, // mitigates Slowloris-style attacks
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}

	// Run the server in a goroutine so main can wait for shutdown signals.
	go func() {
		logger.Info("server starting", "addr", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	// Graceful shutdown on SIGINT/SIGTERM (orchestrators send SIGTERM).
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logger.Info("shutdown signal received")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}
	logger.Info("server stopped cleanly")
}
