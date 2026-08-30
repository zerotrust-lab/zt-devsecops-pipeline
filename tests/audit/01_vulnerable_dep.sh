#!/usr/bin/env bash
# NEGATIVE TEST 1: introduce a known-vulnerable dependency that is ACTUALLY
# compiled into the binary, and confirm Gate 3 (Trivy) blocks the build.
# SUCCESS = the pipeline FAILS.
#
# Why the blank import: `go get <pkg>` alone is pruned by `go mod tidy` when the
# module is never imported, so it would never reach the image and Trivy (which
# scans the built binary) would see nothing. The blank import in package main
# forces x/net into the compiled binary -> into the image -> Trivy flags it.
set -euo pipefail

BRANCH="audit/vuln-dep-$(date +%s)"
git checkout -b "$BRANCH"

echo ">> Forcing a known-vulnerable dependency into the binary (x/net v0.17.0)..."
cat > app/zz_audit_vuln.go <<'GO'
package main

// AUDIT ARTIFACT: this blank import pulls a vulnerable golang.org/x/net into
// the compiled binary so the container scanner can detect it.
// Delete this file to return the service to a clean state.
import _ "golang.org/x/net/http2"
GO

( cd app && go get golang.org/x/net@v0.17.0 && go mod tidy )

git add app/go.mod app/go.sum app/zz_audit_vuln.go
git commit -m "AUDIT: introduce vulnerable dependency (expected to be BLOCKED)"
git push -u origin "$BRANCH"

cat <<'MSG'

EXPECTED RESULT
---------------
golang.org/x/net v0.17.0 carries HIGH advisories (e.g. CVE-2023-45288, the
HTTP/2 CONTINUATION flood, fixed in 0.23.0). Because it is compiled into the
binary, Trivy detects it and Gate 3 exits non-zero -> pipeline RED.

If the pipeline goes GREEN, THE CONTROL IS BROKEN -- check the severity
threshold and ignore-unfixed settings in Gate 3.

Local proof:
  docker build -f build/Dockerfile -t zt-audit:vuln .
  trivy image --severity CRITICAL,HIGH --exit-code 1 zt-audit:vuln   # must exit 1

CLEANUP:
  rm app/zz_audit_vuln.go && git checkout main
MSG
