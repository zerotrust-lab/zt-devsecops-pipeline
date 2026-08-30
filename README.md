# Zero-Trust DevSecOps Pipeline

Software supply chain security and Policy-as-Code, end to end.

A production-grade CI/CD pipeline where no container image reaches the registry
without cryptographic proof of what it is, what is inside it, and who built it.

## Stack

| Layer | Tools |
|-------|-------|
| Cloud | AWS ECR (immutable tags), KMS, IAM OIDC |
| App | Go 1.22 on distroless, non-root UID 65532 |
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
opa test policy/ -v        # 11 tests

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

## Team

See `docs/TEAM.md` for the four-person split, daily checklist, and blockers.
