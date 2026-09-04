# Team execution plan

Zero-Trust DevSecOps Pipeline · team of 4

Follow `docs/DAY0-SETUP.md` first. Once every box there is ticked, start day 1
below. Detailed code, explanations, and dual-OS commands are in
`docs/IMPLEMENTATION-GUIDE.pdf`.

---

## Ground rules

1. **Own your folders.** Only edit files inside your assigned folders. If you
   need a change elsewhere, open a PR and tag the owner. This avoids merge
   conflicts, especially in the pipeline YAML.
2. **Branch per task.** `feature/<name>-<what>`. Never commit to `main`.
3. **Green before you push.** Run your own local check (listed in your section).
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

**Critical path:** Dev A blocks Dev D. Terraform must finish first.
**Parallel:** A, B and C all start immediately on day 1. Dev D studies and
rehearses the gates locally until Dev A publishes the AWS variables.

Dev A owns the AWS account and the bill. Dev D is the repository admin.

---

## Dev A — Cloud & identity (`infra/`)

You build the trust foundation. Dev D is blocked until you publish two values.

### Tasks
- [ ] Confirm the state backend exists (created in Day 0 step 5)
- [ ] `terraform init` with `-backend-config`
- [ ] `terraform plan -out=tfplan`, review every resource, then `apply`
- [ ] Verify the OIDC trust `sub` is scoped to your repo AND branch
- [ ] Verify ECR shows `imageTagMutability: IMMUTABLE`
- [ ] **Publish** `AWS_ROLE_ARN` and `ECR_REPOSITORY` as GitHub repo **Variables**
- [ ] **Tell Dev D immediately** — they are blocked until this moment
- [ ] Later: run `terraform destroy` once screenshots are captured

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
- [ ] Run `go mod tidy` and **commit `go.sum`** (the Docker build fails without it)
- [ ] Get `go vet` and `go test -race` green
- [ ] Build the image; verify `/healthz`, `/`, `/metrics` respond
- [ ] **Prove non-root:** `docker inspect` shows `User=65532:65532`
- [ ] **Prove no shell:** attempting `/bin/sh` in the image fails
- [ ] Get Hadolint clean

### Local check
```bash
cd app && go mod tidy && go vet ./... && go test ./... -race -count=1 && cd ..
docker build -f build/Dockerfile -t zt-go-microservice:dev .
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

You write the rules the pipeline enforces, and make the findings visible. No
cloud access needed.

### Phase 5 — OPA policy
- [ ] Get all **11** Rego unit tests passing
- [ ] Confirm the compliant fixture passes, the non-compliant one fails
- [ ] Understand the fail-closed presence rules and why they exist
- [ ] Review Trivy thresholds; keep `.trivyignore` empty unless justified
- [ ] Support Dev D when the Gate 6 policy step first runs

### Phase 6 — Findings dashboard
- [ ] Enable Code Scanning so SARIF uploads land
- [ ] Test `scripts/parse_scan_results.py` against the repo
- [ ] Confirm the weekly summary workflow runs via `workflow_dispatch`

### Local check
```bash
opa test policy/ -v                     # expect 11 tests, all pass
conftest test policy/tests/fixtures/compliant.json --policy policy/ --all-namespaces
conftest test policy/tests/fixtures/noncompliant.json --policy policy/ --all-namespaces

export GH_TOKEN=$(gh auth token)
python3 scripts/parse_scan_results.py --repo <ORG>/zt-devsecops-pipeline
```

### Must be able to explain
- The `deny` pattern and how Conftest turns it into a build gate
- Why policies need unit tests
- The Rego "undefined" gotcha: why `undefined != true` fails open, and how the
  presence rules fix it
- What SARIF is and why standardising on it matters

---

## Dev D — Pipeline & audit (`.github/`, `tests/audit/`)

You integrate everyone's work, then attack it. Largest single workload — start
studying on day 1 even though you are partly blocked.

### While waiting on Dev A (day 1)
- [ ] Read `devsecops-pipeline.yaml` line by line; understand every `needs:`
- [ ] Run each gate manually on your laptop (guide section 3.7)
- [ ] Practise `cosign sign` / `cosign verify` on a local test image

### Phase 4 — Pipeline (day 2–4, once the AWS variables exist)
- [ ] Gates 1–2 green
- [ ] Gate 3 green (build + push to ECR + Trivy)
- [ ] Gates 4–5 green (SBOM + keyless signing) — budget a full day for Cosign
- [ ] Fix `EXPECTED_IDENTITY` to match your real workflow path and ref
- [ ] Gate 6 green (OPA policy gate)

### Phase 7 — Audit suite (day 5)
- [ ] `01_vulnerable_dep.sh` → pipeline RED at Gate 3
- [ ] `02_root_container.sh` → blocked at Gates 2 and 6
- [ ] `03_unsigned_image.sh` → `cosign verify` fails
- [ ] Clean up: `rm app/zz_audit_vuln.go build/Dockerfile.insecure`, delete branches

### Local check
```bash
gh run watch                             # follow a live run
gh run view --log-failed                 # debug a red gate
GITHUB_REPOSITORY=<ORG>/zt-devsecops-pipeline \
  ./security/cosign/verify.sh <ecr-uri>@sha256:<digest>
```

### Must be able to explain
- How keyless signing works (OIDC → Fulcio → ephemeral key → Rekor)
- Why every gate after build references the image by digest, not tag
- Signature vs attestation, and why you need both
- Why you red-team your own pipeline

---

## Suggested week

| Day | Dev A (Cloud) | Dev B (App) | Dev C (Policy) | Dev D (Pipeline) |
|-----|---------------|-------------|----------------|------------------|
| 1 | Backend check + `terraform plan` | Go app, tests, module path PR | Rego tests green (11) | Study pipeline, rehearse gates |
| 2 | `apply`, **publish Variables** | Image + non-root proof | Trivy config, Code Scanning | Gates 1–2 green |
| 3 | Support D on IAM issues | Hadolint clean, README | Summary script | Gates 3–4 green |
| 4 | Docs, cost review | Docs, screenshots | Support Gate 6 policy step | Gates 5–6 green (Cosign day) |
| 5 | Teardown plan | Screenshots | Verify each attack trips the right gate | Run all 3 audit tests |

If a day slips, the usual culprit is Cosign identity matching on day 4. Keep
A, B and C free that day to help.

---

## Definition of done

- [ ] A push to `main` produces an all-green run of all 6 gates
- [ ] A signed image with an SBOM attestation exists in ECR
- [ ] `cosign verify` succeeds against that image by digest
- [ ] All 3 audit tests turn the pipeline RED as expected
- [ ] GitHub Security tab shows findings from Semgrep, Hadolint, and Trivy
- [ ] README has the architecture diagram and screenshots
- [ ] Each of the 4 can explain every phase, not just their own
- [ ] `terraform destroy` run after screenshots (stop the billing)
- [ ] LinkedIn post published (`docs/linkedin-post.md`)

---

## Screenshots to capture

1. The all-green pipeline run (all 6 gates)
2. A red run from an audit test, side by side with the green one
3. `cosign verify` output showing the three checks passing
4. The GitHub Security tab with findings
5. The ECR repo showing the image + signature + attestation artifacts

---

## Common blockers

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `sub` doesn't match repo/branch | Dev A checks `allowed_branches` and `github_org` in tfvars |
| Docker build fails on `go.sum` | `go mod tidy` never committed | Dev B runs it and commits `go.sum` |
| `cosign verify` fails on a signed image | `EXPECTED_IDENTITY` mismatch | Must match workflow path + ref exactly |
| Cannot push tag to ECR | Tags are immutable | Use the commit SHA; never re-push a tag |
| Gates 3–6 skipped on a PR | Intentional (`if: github.event_name == 'push'`) | Signing runs on merge to `main` |
| Workflow does not trigger | Branch is `master` | `git branch -m master main` |
| `.sh` scripts won't run on Windows | They are bash scripts | Run them in Git Bash |
