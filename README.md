# Zero-Trust DevSecOps Pipeline

Software supply chain security and Policy-as-Code, end to end.

A production-grade CI/CD pipeline where no container image reaches the registry
without cryptographic proof of what it is, what is inside it, and who built it.

## Stack

| Layer | Tools |
|-------|-------|
| Cloud | AWS ECR (immutable tags), KMS, IAM OIDC |
| App | Go 1.26 on distroless, non-root UID 65532 |
| SAST / lint | Semgrep, go vet, Hadolint |
| SCA / scan | Trivy (fail on CRITICAL/HIGH) |
| Supply chain | Syft (SBOM), Cosign keyless via Sigstore |
| Policy | OPA / Conftest (Rego) |
| Dashboard | GitHub Security tab (SARIF) |

## The six gates

1. **SAST & lint** - Semgrep + go vet + unit tests
2. **Dockerfile audit** - Hadolint
3. **Build & scan** - multi-arch buildx + Trivy, fails on CRITICAL/HIGH
4. **SBOM** - Syft, SPDX + CycloneDX
5. **Keyless signing** - Cosign + OIDC, signature logged in Rekor
6. **Policy gate** - OPA/Conftest blocks non-compliant images

Each gate must pass before the next begins. The only path to the registry runs
through the policy gate; the only path to production runs through digest-based
verification.

## Quick start

```bash
# 1. Provision AWS (Dev A)
cd infra
cp terraform.tfvars.example terraform.tfvars   # set github_org
terraform init -backend-config="bucket=$TF_BUCKET" -backend-config="region=$AWS_REGION"
terraform plan -out=tfplan && terraform apply tfplan
terraform output -raw github_actions_role_arn   # -> repo variable AWS_ROLE_ARN
terraform output -raw ecr_repository_url        # -> repo variable ECR_REPOSITORY

# 2. Prepare the app (Dev B)
cd ../app && go mod tidy && go test ./... -race

# 3. Validate policy (Dev C)
opa test policy/ --ignore '*.json' -v        # 11 tests

# 4. Push and watch (Dev D)
git push && gh run watch
```

## Before the first run

- Replace `your-github-org` in `app/go.mod`, `app/main.go`, `app/main_test.go`
- Run `go mod tidy` to generate `app/go.sum` (the Docker build requires it)
- Set the repo **Variables** `AWS_ROLE_ARN` and `ECR_REPOSITORY`
- Enable Code Scanning: Settings -> Code security -> Code scanning

## Layout

```
app/          Go microservice + tests
build/        Distroless Dockerfile + Hadolint config
infra/        Terraform: KMS, IAM OIDC, ECR
policy/       Rego policies + 11 unit tests
security/     Trivy config, deploy-time cosign verify
scripts/      Findings summary + optional DefectDojo bridge
tests/audit/  Three negative tests that must turn the pipeline RED
docs/         Architecture diagram, team plan, LinkedIn post
.github/      The 6-gate pipeline + weekly security summary
```

## Cost

Roughly $1-3/month, almost entirely the KMS key. ECR storage is within the free
tier for a ~15 MB image. Run `terraform destroy` when finished.

## App & Container

The Go microservice is built with a multi-stage Dockerfile: the first stage
compiles the binary with the full Go toolchain, and the second stage copies only
that binary into a `gcr.io/distroless/static-debian12` base, discarding
everything else. The final image has no shell and no package manager, and runs
as non-root UID 65532 — verified via `docker inspect` and enforced
independently by the OPA policy in `policy/container.rego`. Trivy scans
(`--severity CRITICAL,HIGH --ignore-unfixed`) return zero findings on both the
Debian base and the compiled Go binary.

## Team

Built by three engineers.

| Name | Owned | What that covered |
|------|-------|-------------------|
| **Samir Maji** | `infra/`, `.github/`, `tests/audit/` | AWS foundation and the pipeline. Terraform for KMS, ECR with immutable tags, and the IAM OIDC trust that lets GitHub Actions authenticate with zero stored credentials. Then the six-gate workflow itself, keyless Cosign signing, and the adversarial tests that prove the gates block real attacks. |
| **Ananthapadmanabhan** | `app/`, `build/` | The Go microservice and its container. Multi-stage build on a distroless base running as non-root UID 65532 — no shell, no package manager, minimal attack surface. Verified rather than assumed: the image is proven non-root and shell-less before it ships. |
| **Vipul** | `policy/`, `security/`, `scripts/` | Policy-as-Code and vulnerability management. Rego rules enforcing non-root execution, approved base images, digest pinning, signatures and SBOMs — with 11 unit tests, including fail-closed checks that catch missing fields rather than trusting the input. Plus Trivy thresholds and SARIF findings aggregation. |

### What the pipeline caught

During development Trivy blocked a build over **22 real vulnerabilities** —
21 HIGH and 1 CRITICAL (CVE-2025-68121, incorrect certificate validation during
TLS session resumption). The Debian base was clean at zero; every finding was in
the Go standard library statically linked into the binary. The fix was not a
package patch but a toolchain rebuild on a newer Go.

That is the project working as intended: a control that has actually stopped
something, not one we assume works.

