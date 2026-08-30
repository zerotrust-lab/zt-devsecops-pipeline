package handlers

import (
	"encoding/json"
	"net/http"
	"time"
)

// healthResponse is the JSON body returned by the liveness probe.
type healthResponse struct {
	Status string `json:"status"`
	Time   string `json:"time"`
}

// Healthz is a liveness endpoint. It returns 200 as long as the process can
// serve requests. Keep it dependency-free so a slow database never makes the
// orchestrator kill a healthy process.
func Healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(healthResponse{
		Status: "ok",
		Time:   time.Now().UTC().Format(time.RFC3339),
	})
}

// Root is a minimal business endpoint standing in for real application logic.
func Root(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"service": "zero-trust-go-microservice",
		"message": "secured by supply-chain verification",
	})
}
