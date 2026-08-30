# syntax=docker/dockerfile:1.7

########################  Stage 1: build  ########################
FROM golang:1.22-bookworm AS builder

WORKDIR /src

# Cache dependencies separately from source for faster rebuilds.
COPY app/go.mod app/go.sum ./
RUN go mod download && go mod verify

COPY app/ ./

# Build a fully static, stripped binary. CGO disabled => no libc dependency,
# so it runs on distroless/static. -trimpath removes local filesystem paths.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w -buildid=" -o /out/app .

########################  Stage 2: runtime  ######################
# distroless/static: no shell, no package manager, no libc -- minimal CVE surface.
# The :nonroot tag runs as UID 65532 by default.
FROM gcr.io/distroless/static-debian12:nonroot

# Redundant-but-explicit: declare the non-root user so intent is auditable
# and OPA/Trivy can read it from the image config.
USER 65532:65532

WORKDIR /app
COPY --from=builder --chown=65532:65532 /out/app /app/app

EXPOSE 8080

# Distroless has no shell, so ENTRYPOINT must be exec-form (no /bin/sh wrapper).
ENTRYPOINT ["/app/app"]
