# Team execution plan

Zero-Trust DevSecOps Pipeline · team of 4

Everything below assumes you are working in this repo and following
`docs/build-guide.pdf` for the detailed code and explanations.

---

## Ground rules

1. **Own your folder.** Only edit files inside your assigned folders. If you
   need a change elsewhere, open a PR and tag the owner. This avoids merge
   conflicts, especially in the pipeline YAML.
2. **Branch per task.** `feature/<name>-<what>`. Never commit to `main` directly.
3. **Green before you push.** Run your own local check (listed in your section)
   before pushing.
4. **Teach your piece.** At the end, each person explains their phase to the
   other three. Interviewers ask about the whole pipeline, not just your part.

---

## Who owns what

| Dev | Role | Folders | Phases |
|-----|------|---------|--------|
| A | Cloud & identity | `infra/` | 2 |
| B | App & container | `app/`, `build/` | 3 |
| C | Policy & findings | `policy/`, `security/`, `scripts/` | 5, 6 |
| D | Pipeline & audit | `.github/`, `tests/audit/` | 4, 7 |

**Critical path:** A blocks D. A must finish first.
**Parallel:** A, B, C can all start on day 1 independently.

---

## Dev A — Cloud & identity (`infra/`)

You build the trust foundation. Everyone else waits on your two outputs.

### Tasks
- [ ] Bootstrap the Terraform backend by hand (S3 bucket + DynamoDB lock table)
- [ ] `terraform init` with `-backend-config`
- [ ] `terraform plan -out=tfplan`, review every resource, then `apply`
- [ ] Confirm the OIDC trust policy `sub` is scoped to your repo AND branch
- [ ] Confirm ECR shows `imageTagMutability: IMMUTABLE`
- [ ] **Publish** `AWS_ROLE_ARN` and `ECR_REPOSITORY` as GitHub repo **Variables**
- [ ] Tell Dev D the moment those Variables exist

### Local check
```bash
cd infra
terraform fmt -check && terraform validate && terraform plan
aws iam get-role --role-name zt-devsecops-github-actions \
  --query 'Role.AssumeRolePolicyDocument' | jq .
```

### Must be able to explain
- How GitHub Actions authenticates to AWS with zero stored secrets
- Why the `sub` condition is the most security-critical line in the repo
- Why immutable tags matter and how they complement Cosign

---

## Dev B — App & container (`app/`, `build/`)

You build what the pipeline protects. No cloud access needed.

### Tasks
- [ ] Replace `your-github-org` in `app/go.mod`, `app/main.go`, `app/main_test.go`
- [ ] Run `go mod tidy` to generate `go.sum` (required — the build fails without it)
- [ ] Get `go vet` and `go test -race` green
- [ ] Build the image and verify the endpoints respond
- [ ] **Prove non-root:** `docker inspect ... --format '{{.Config.User}}'` → `65532:65532`
- [ ] **Prove no shell:** attempting `/bin/sh` in the image must fail
- [ ] Get Hadolint clean against `build/Dockerfile`

### Local check
```bash
cd app && go mod tidy && go vet ./... && go test ./... -race -count=1
cd .. && docker build -f build/Dockerfile -t zt-go-microservice:dev .
docker inspect zt-go-microservice:dev --format 'User={{.Config.User}}'
docker run --rm -i hadolint/hadolint hadolint \
  --config build/.hadolint.yaml - < build/Dockerfile
```

### Must be able to explain
- Multi-stage builds and how they cut the CVE count
- Why distroless + UID 65532 is defense in depth
- How health checks and debugging work with no shell in the image

---

## Dev C — Policy & findings (`policy/`, `security/`, `scripts/`)

You write the rules the pipeline enforces. No cloud access needed.

### Tasks
- [ ] Get all **11** Rego unit tests passing (`opa test policy/ -v`)
- [ ] Confirm the compliant fixture passes and the non-compliant fixture fails
- [ ] Understand the fail-closed presence rules (see the hardening section in the guide)
- [ ] Review Trivy severity thresholds; keep `.trivyignore` empty unless justified
- [ ] Enable Code Scanning in repo settings so SARIF uploads land
- [ ] Test `scripts/parse_scan_results.py` against the repo

### Local check
```bash
opa test policy/ -v                     # expect 11 tests, all pass
conftest test policy/tests/fixtures/compliant.json --policy policy/ --all-namespaces
conftest test policy/tests/fixtures/noncompliant.json --policy policy/ --all-namespaces
export GH_TOKEN=$(gh auth token)
python scripts/parse_scan_results.py --repo <org>/zt-devsecops-pipeline
```

### Must be able to explain
- The `deny` pattern and how Conftest turns it into a build gate
- Why policies need unit tests
- The Rego "undefined" gotcha: why `undefined != true` fails open, and how the
  presence rules fix it

---

## Dev D — Pipeline & audit (`.github/`, `tests/audit/`)

You integrate everyone's work and then attack it. Partly blocked on Dev A.

### Tasks
**While waiting on Dev A:**
- [ ] Read `devsecops-pipeline.yaml` line by line; understand every `needs:`
- [ ] Run each gate manually on your laptop (commands in the guide, Phase 4)
- [ ] Practise `cosign sign` / `cosign verify` on a local test image

**Once Dev A publishes the Variables:**
- [ ] Push and get Gates 1–2 green
- [ ] Get Gate 3 green (build + push to ECR + Trivy)
- [ ] Get Gates 4–5 green (SBOM + keyless signing) — budget a full day for Cosign
- [ ] Fix `EXPECTED_IDENTITY` to match your real workflow path and ref
- [ ] Get Gate 6 green (OPA policy gate)

**Then the audit suite (Phase 7):**
- [ ] `01_vulnerable_dep.sh` → pipeline must go RED at Gate 3
- [ ] `02_root_container.sh` → must be blocked at Gates 2 and 6
- [ ] `03_unsigned_image.sh` → `cosign verify` must fail
- [ ] Clean up: `rm app/zz_audit_vuln.go`, delete audit branches

### Local check
```bash
gh run watch                             # follow a live run
gh run view --log-failed                 # debug a red gate
```

### Must be able to explain
- How keyless signing works (OIDC → Fulcio → ephemeral key → Rekor)
- Why every gate after build references the image by digest, not tag
- Signature vs attestation, and why you need both

---

## Suggested week

| Day | A | B | C | D |
|-----|---|---|---|---|
| 1 | Backend + `terraform plan` | Go app + tests | Rego + tests | Study pipeline, run gates manually |
| 2 | `apply`, publish Variables | Image + non-root proof | Trivy config, Code Scanning | Gates 1–2 green |
| 3 | Support D on IAM issues | README, screenshots | Support D on policy gate | Gates 3–4 green |
| 4 | Docs | Docs | Review audit results | Gates 5–6 green (Cosign day) |
| 5 | — | — | Verify each attack trips the right gate | Run all 3 audit tests |

---

## Definition of done

- [ ] A push to `main` produces an all-green run of all 6 gates
- [ ] A signed image with an SBOM attestation exists in ECR
- [ ] `cosign verify` succeeds against that image by digest
- [ ] All 3 audit tests turn the pipeline RED as expected
- [ ] GitHub Security tab shows findings from Semgrep, Hadolint, and Trivy
- [ ] README has the architecture diagram and screenshots
- [ ] Every team member can explain every phase
- [ ] LinkedIn post published (`docs/linkedin-post.md`)

---

## Screenshots to capture for the portfolio

1. The all-green pipeline run (all 6 gates)
2. A red run from an audit test, side by side with the green one
3. `cosign verify` output showing the three checks passing
4. The GitHub Security tab with findings
5. The ECR repo showing the image + signature + attestation artifacts

---

## Common blockers

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `sub` doesn't match repo/branch | Check `allowed_branches` and `github_org` in tfvars |
| Docker build fails on `go.sum` | `go mod tidy` never run | Dev B runs it and commits `go.sum` |
| `cosign verify` fails on a signed image | `EXPECTED_IDENTITY` string mismatch | Must match workflow path + ref exactly |
| Cannot push tag to ECR | Tags are immutable | Use the commit SHA; never re-push a tag |
| Gates 3–6 skipped on a PR | Intentional (`if: github.event_name == 'push'`) | Signing runs on merge to `main` |
