# Day 0 — setup before anyone writes code

Complete this in order. Steps 1–5 are done **once by the repo owner**; step 6
is done by **each of the four** on their own laptop. Budget 60–90 minutes total.

Nobody starts their phase until step 7 passes.

---

## Roles (decide this first, 2 minutes)

Write the names in this table and commit it. No ambiguity later.

| Dev | Name | Owns | Phases |
|-----|------|------|--------|
| A | | `infra/` | 2 |
| B | | `app/`, `build/` | 3 |
| C | | `policy/`, `security/`, `scripts/` | 5, 6 |
| D | | `.github/`, `tests/audit/` | 4, 7 |

Dev A also owns the AWS account and the bill. Dev D is the repo admin.

Dev D has the heaviest single workload (the pipeline), so A, B and C should
expect to help on Cosign day — see the week table in `docs/TEAM.md`.

---

## Step 1 — Create the GitHub organization (Dev D)

Free, and it makes the project read as a team effort.

1. Go to <https://github.com/organizations/plan> and choose **Free**
2. Organization name: something neutral and technical, e.g. `zerotrust-labs`
   (not anyone's personal name)
3. Contact email: any team member's
4. Skip the "invite members" screen for now — done in step 3

---

## Step 2 — Fix the branch name and push the repo (Dev D)

The pipeline and the OIDC trust policy both target `main`. If the branch is
called `master`, nothing will trigger and AWS will reject the token.

```bash
cd "path/to/zt-devsecops-pipeline"

git branch -m master main          # rename if needed
git branch --show-current          # must print: main

rm -rf scripts/__pycache__         # leftover build artifact
git add -A && git commit -m "chore: cleanup" || true

# Create the repo INSIDE the org, private for now
gh repo create <ORG>/zt-devsecops-pipeline \
  --private --source=. --remote=origin --push

gh repo view <ORG>/zt-devsecops-pipeline --web
```

Keep it private until the pipeline is green. A public repo with a red badge is
worse than no repo.

---

## Step 3 — Invite the team (Dev D)

```bash
gh api -X PUT orgs/<ORG>/memberships/<devA-username> -f role=member
gh api -X PUT orgs/<ORG>/memberships/<devB-username> -f role=member
gh api -X PUT orgs/<ORG>/memberships/<devC-username> -f role=member

# Write access to the repo (not admin) -- Dev D already owns it
for u in <devA-username> <devB-username> <devC-username>; do
  gh api -X PUT repos/<ORG>/zt-devsecops-pipeline/collaborators/$u -f permission=push
done
```

Each person accepts the invite from their email or <https://github.com/settings/organizations>.

---

## Step 4 — Protect `main` (Dev D)

Nobody pushes to `main` directly. Every change is a PR reviewed by someone else.
This is how each of you learns the parts you didn't build.

```bash
gh api -X PUT repos/<ORG>/zt-devsecops-pipeline/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -f "required_pull_request_reviews[required_approving_review_count]=1" \
  -F "enforce_admins=false" \
  -F "required_status_checks=null" \
  -F "restrictions=null"
```

Then enable Code Scanning so SARIF uploads have somewhere to land:

**Settings → Code security and analysis → Code scanning → Set up → Default**

---

## Step 5 — AWS account and billing guardrail (Dev A)

Do this **before** any `terraform apply`. Expected cost is $1–3/month, almost
entirely the KMS key, but the alarm protects you from a mistake.

```bash
# Confirm you are in the right account
aws sts get-caller-identity

# $5/month budget alarm — will never fire if things are healthy
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws budgets create-budget --account-id "$ACCOUNT" --budget '{
  "BudgetName":"zt-devsecops",
  "BudgetLimit":{"Amount":"5","Unit":"USD"},
  "TimeUnit":"MONTHLY","BudgetType":"COST"
}'
```

Also create the Terraform state backend now (it cannot be managed by Terraform
itself — chicken and egg):

```bash
export AWS_REGION=us-east-1
export TF_BUCKET="zt-devsecops-tfstate-$(aws sts get-caller-identity --query Account --output text)"

aws s3api create-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION"
aws s3api put-bucket-versioning --bucket "$TF_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
aws s3api put-public-access-block --bucket "$TF_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table --table-name zt-devsecops-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$AWS_REGION"

echo "TF_BUCKET=$TF_BUCKET"   # share this string with the team
```

**Teardown reminder:** when the project is done and screenshots are captured,
run `terraform destroy`. Put a calendar reminder in now.

---

## Step 6 — Every person sets up their laptop (all four)

### 6a. Install the toolchain

```bash
# macOS
brew install git go terraform awscli gh jq opa conftest trivy syft cosign hadolint
brew install --cask docker      # then launch Docker Desktop once
```

```powershell
# Windows (PowerShell) -- core tools
winget install --exact --id Git.Git
winget install --exact --id GoLang.Go
winget install --exact --id Hashicorp.Terraform
winget install --exact --id Amazon.AWSCLI
winget install --exact --id GitHub.cli
winget install --exact --id jqlang.jq
winget install --exact --id Docker.DockerDesktop
```

```powershell
# Windows (PowerShell, as Administrator) -- security tools via Chocolatey
choco install opa trivy cosign hadolint -y
```

Conftest and Syft are not in Chocolatey — download the Windows binaries from
their GitHub releases pages and put them on your PATH. Full instructions with
copy-paste commands are in `docs/IMPLEMENTATION-GUIDE.pdf`, section 2.2.

**Windows users:** the three scripts in `tests/audit/` are bash scripts. Run
them in **Git Bash** (installs with Git for Windows), not PowerShell.

### 6b. Verify every tool answers

```bash
for t in go terraform aws gh docker opa conftest trivy syft cosign hadolint jq; do
  printf "%-12s " "$t"; command -v "$t" >/dev/null && $t version 2>/dev/null | head -1 || echo "MISSING"
done
```

Anything reporting MISSING must be fixed before you start.

### 6c. Authenticate

```bash
gh auth login          # choose HTTPS, authenticate via browser
gh auth status
```

Only Dev A needs AWS credentials (`aws configure` or `aws sso login`).

### 6d. Clone the shared repo — do not fork

```bash
git clone https://github.com/<ORG>/zt-devsecops-pipeline.git
cd zt-devsecops-pipeline
```

---

## Step 7 — Smoke test (all four, together)

Run these before anyone starts their phase. If they all pass, the codebase is
sound on your machine and any later failure is your change, not the baseline.

```bash
# 1. Go builds and tests pass  (generates go.sum the first time)
cd app && go mod tidy && go vet ./... && go test ./... -race -count=1 && cd ..

# 2. Policy tests pass — expect 11 PASS
opa test policy/ -v

# 3. Dockerfile is clean
docker run --rm -i hadolint/hadolint hadolint \
  --config build/.hadolint.yaml - < build/Dockerfile

# 4. Image builds and runs as non-root
docker build -f build/Dockerfile -t zt-go-microservice:dev .
docker inspect zt-go-microservice:dev --format 'User={{.Config.User}}'
# MUST print: User=65532:65532

# 5. Terraform is valid (Dev A only, no apply yet)
cd infra && terraform init -backend=false && terraform validate && cd ..
```

**Expected:** 3 Go tests pass, 11 OPA tests pass, Hadolint silent, `User=65532:65532`,
Terraform valid.

---

## Step 8 — One-time code edit (Dev B, then PR)

The Go module path is a placeholder. Fix it once, for everyone:

```bash
git checkout -b chore/set-module-path

# macOS
grep -rl 'your-github-org' app/ | xargs sed -i '' 's|your-github-org|<ORG>|g'
# Linux
# grep -rl 'your-github-org' app/ | xargs sed -i 's|your-github-org|<ORG>|g'

cd app && go mod tidy && go test ./... && cd ..
git add -A && git commit -m "chore: set Go module path to the org"
git push -u origin chore/set-module-path && gh pr create --fill
```

Someone else reviews and merges. That's your first PR — practise the workflow
on something harmless.

---

## Step 9 — Agree the working rules (5 minutes, all four)

1. **Only edit files in your own folder.** Cross-folder change → PR to the owner.
2. **Branch naming:** `feature/<dev>-<what>`, e.g. `feature/devA-oidc-role`.
3. **Never commit to `main`.** Branch protection enforces it anyway.
4. **Never commit secrets.** No `.tfvars`, no keys, no tokens. `.gitignore`
   covers the usual suspects — do not override it.
5. **Daily 10-minute standup:** what I finished, what I'm blocked on.
6. **Dev A announces immediately** when `AWS_ROLE_ARN` and `ECR_REPOSITORY` are
   published — Dev D is blocked until then.
7. **A, B and C stay free on Cosign day** (day 4) to help Dev D.

---

## Definition of "ready to start"

- [ ] Org created, repo pushed, branch is `main`
- [ ] All four are org members with Write access
- [ ] Branch protection on, Code Scanning enabled
- [ ] AWS budget alarm created, state backend created
- [ ] All four pass the step 7 smoke test locally
- [ ] Module path PR merged
- [ ] Roles table filled in and committed
- [ ] Working rules agreed

When every box is ticked, go to `docs/TEAM.md` and start day 1.

---

## Fast fixes for likely Day 0 problems

| Symptom | Fix |
|---------|-----|
| `gh: command not found` | `brew install gh` (macOS) or see cli.github.com |
| `docker: Cannot connect to the Docker daemon` | Launch Docker Desktop and wait for it to be running |
| `go: go.mod file not found` | You are in the wrong directory — `cd app` first |
| `opa test` finds no tests | Run from the repo root, not inside `policy/` |
| Docker build fails on `go.sum` | Dev B has not run `go mod tidy` and committed `go.sum` |
| `terraform init` fails on backend | Use `-backend=false` for validation; the real init needs `TF_BUCKET` |
| Workflow does not trigger on push | Branch is `master`, not `main` — see step 2 |
