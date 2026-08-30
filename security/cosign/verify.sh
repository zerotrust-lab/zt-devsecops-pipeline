#!/usr/bin/env bash
# Deploy-time verification. Refuses to deploy anything not signed by OUR
# workflow identity. Call this immediately before a rollout.
#
# Usage: GITHUB_REPOSITORY=org/repo ./security/cosign/verify.sh <registry>@sha256:...
set -euo pipefail

IMAGE_DIGEST="${1:?usage: verify.sh <registry>@sha256:...}"
REPO="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY=org/repo}"
EXPECTED_IDENTITY="https://github.com/${REPO}/.github/workflows/devsecops-pipeline.yaml@refs/heads/main"
ISSUER="https://token.actions.githubusercontent.com"

echo ">> Verifying signature identity for ${IMAGE_DIGEST}..."
cosign verify "$IMAGE_DIGEST" \
  --certificate-identity "$EXPECTED_IDENTITY" \
  --certificate-oidc-issuer "$ISSUER" > /dev/null

echo ">> Verifying SBOM attestation is present and signed..."
cosign verify-attestation "$IMAGE_DIGEST" --type cyclonedx \
  --certificate-identity "$EXPECTED_IDENTITY" \
  --certificate-oidc-issuer "$ISSUER" > /dev/null

echo ">> All supply-chain checks passed -- safe to deploy."
