# LinkedIn showcase post

Paste directly into LinkedIn. Post the architecture diagram as the image and put
the repo link in the FIRST COMMENT (links in the body suppress reach).

---

I built a Zero-Trust DevSecOps pipeline where no image reaches production without cryptographic proof of what it is, what's inside it, and who built it. Here's the architecture. 🔐👇

Most CI/CD pipelines run on implicit trust — if it came from CI, ship it. That assumption is exactly how software supply chain attacks (SolarWinds, Codecov, XZ) succeed. So my team of 4 rebuilt the pipeline on one principle: never trust, always verify — at every stage.

🏗 The architecture
→ Go microservice on distroless, running as non-root UID 65532
→ Zero static secrets — GitHub Actions authenticates to AWS via short-lived OIDC tokens
→ 6 sequential security gates: Semgrep (SAST) → Hadolint → Trivy (fail on CRITICAL/HIGH) → Syft (SBOM) → Cosign keyless signing → OPA/Conftest policy gate
→ Immutable ECR tags + digest-pinned references end-to-end
→ All findings aggregated as SARIF in the GitHub Security tab

🔏 The supply-chain core
→ Keyless signing with Cosign + Sigstore — no private key exists to steal; identity comes from OIDC, signatures logged in the public Rekor transparency log
→ SBOMs (SPDX + CycloneDX) generated for every build and attached as signed attestations
→ Policy-as-Code in Rego rejects any build that runs as root, uses an unapproved base image, is unsigned, or ships without an SBOM

✅ Outcomes
→ Zero long-lived secrets in CI — nothing to leak or rotate
→ Automated supply-chain verification — every artifact carries a verifiable SBOM + signature, checked again at deploy time by digest
→ Moving toward SLSA-aligned build provenance
→ We red-teamed our own pipeline: a vulnerable dependency, a root container, and an unsigned image — all three were blocked automatically ✅

A control you've never watched block something isn't a control — it's a hope. This one blocks.

Full architecture + code walkthrough in the comments. Happy to talk keyless signing with anyone building in this space.

#DevSecOps #Cybersecurity #GitHubActions #Cosign #Sigstore #OPA #AppSec #SupplyChainSecurity #SLSA #CloudSecurity #Golang #DevOps

---

## Posting tips
- Render the Mermaid diagram to PNG and attach it — visual posts get far more reach.
- Repo link goes in the first comment, not the body.
- All 4 team members repost with a one-line personal angle ("I owned the Terraform OIDC module...").
- Best window: Tue–Thu, 8–10am in your target recruiters' timezone.
