#!/usr/bin/env bash
# NEGATIVE TEST 3: attempt to verify an image that was never signed.
# SUCCESS = cosign verify FAILS and the deploy is refused.
set -euo pipefail

: "${ECR_REPOSITORY:?set ECR_REPOSITORY to your registry URI}"

echo ">> Building and pushing an image WITHOUT signing it..."
docker build -f build/Dockerfile -t "${ECR_REPOSITORY}:unsigned-audit" .
docker push "${ECR_REPOSITORY}:unsigned-audit"
DIGEST=$(docker inspect "${ECR_REPOSITORY}:unsigned-audit" --format '{{index .RepoDigests 0}}')

echo ">> Attempting cosign verify on the UNSIGNED image (must FAIL)..."
set +e
cosign verify "$DIGEST" \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
RESULT=$?
set -e

if [ "$RESULT" -ne 0 ]; then
  echo ">> CORRECT: cosign verify FAILED -- unsigned image rejected."
else
  echo "!! CONTROL BROKEN: unsigned image passed verification. Investigate." >&2
  exit 1
fi

cat <<MSG

EXPECTED RESULT
---------------
cosign reports "no matching signatures" and exits non-zero. Any deploy step
gating on cosign verify (see security/cosign/verify.sh) refuses this image.

CLEANUP:
  aws ecr batch-delete-image --repository-name "\${ECR_REPOSITORY##*/}" \\
    --image-ids imageTag=unsigned-audit
MSG
