#!/usr/bin/env bash
# NEGATIVE TEST 2: build an image that runs as root and confirm Hadolint
# (Gate 2) and OPA (Gate 6) block it. SUCCESS = the pipeline FAILS.
set -euo pipefail

BRANCH="audit/root-container-$(date +%s)"
git checkout -b "$BRANCH"

echo ">> Writing a deliberately insecure Dockerfile that runs as root..."
cat > build/Dockerfile.insecure <<'DOCKER'
FROM golang:1.22-bookworm AS builder
WORKDIR /src
COPY app/ ./
RUN CGO_ENABLED=0 go build -o /out/app .

FROM debian:12
COPY --from=builder /out/app /app/app
# NOTE: no USER directive -> runs as root (UID 0). This must be rejected.
ENTRYPOINT ["/app/app"]
DOCKER

echo ">> Auditing with Hadolint (Gate 2 preview)..."
docker run --rm -i hadolint/hadolint hadolint --failure-threshold warning \
  - < build/Dockerfile.insecure || echo ">> Hadolint flagged it (expected)."

echo ">> Building and generating OPA input to prove Gate 6 blocks it..."
docker build -f build/Dockerfile.insecure -t zt-audit:root .
USER_FIELD=$(docker image inspect zt-audit:root --format '{{.Config.User}}')

cat > /tmp/root_input.json <<JSON
{"image":{"user":"${USER_FIELD:-root}","digest":"latest","signed":false,"sbom_attested":false,"base_image":"debian:12"}}
JSON

echo ">> Running OPA policy against the root image (must DENY)..."
conftest test /tmp/root_input.json --policy policy/ --all-namespaces || \
  echo ">> OPA denied the root image (expected)."

git add build/Dockerfile.insecure
git commit -m "AUDIT: root-user container (expected to be BLOCKED)"
git push -u origin "$BRANCH"

cat <<'MSG'

EXPECTED RESULT
---------------
Gate 2 (Hadolint): missing-USER / DL3002 warnings -> non-zero.
Gate 6 (OPA): "image runs as root", plus unapproved base, non-digest,
              unsigned, and missing-SBOM denials -> conftest non-zero -> RED.

CLEANUP:
  rm build/Dockerfile.insecure && git checkout main
MSG
