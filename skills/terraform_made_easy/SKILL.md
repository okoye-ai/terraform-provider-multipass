---
name: terraform_made_easy
description: "Knowledge base from \"Terraform Made Easy: Provisioning, Managing and Automating Cloud Infrastructure with Terraform on Google Cloud\" by Ivy Wang (Apress, 2024). Use when applying Wang's frameworks for Terraform workflows and HCL, providers and modules, variables/outputs/tfvars, state and backends and workspaces, GCP provisioning (Cloud Storage, Compute Engine, VPC, Cloud SQL, service accounts, GKE), secrets and IAM security, remote state hardening, backups and DNS failover, and testing/CI-CD automation (TFLint, Checkov, Terratest, GitHub Actions/GitLab CI/Jenkins)."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform Made Easy
**Author**: Ivy Wang | **Pages**: ~234 | **Chapters**: 6 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `remote state`, `Cloud SQL`, `for_each`, or another indexed topic; I find and read the relevant chapter
- **With chapter** — ask for `ch04`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

**The Terraform Workflow (the book's spine)** — `init → write → fmt → validate → plan → apply → (destroy)`. `init` does four jobs: backend, provider plugins, modules, state setup — re-run it after changing backend or modules. Review a saved plan (`plan -out=plan.out` → `apply "plan.out"`) so apply executes exactly what was reviewed; symbols: `+` create, `~` modify, `-` destroy. `destroy` is a "review + team check" operation — no undo.

**Providers as bridges** — a provider connects Terraform to any API behind a versioned `required_providers` block (local name + source + version constraint). Registry tiers: **Official** (HashiCorp) > **Partner** (vendor) > **Community** (niche) > **Archived** (unmaintained, caution). Pin versions, never `latest` in production; cache plugins via `plugin_cache_dir` in `.terraformrc`.

**Variables & values plumbing** — variables are function arguments (typed + validated + described); outputs are return values; locals are function-local temporaries (use moderately). Values come from defaults → `tfvars` (`-var-file="dev.tfvars"` per environment) → `TF_VAR_*` env vars (for secrets). Undeclared vars: env silent / tfvars warning / CLI error — declare everything.

**Modules as contracts** — root → child modules; standard structure `main.tf` + `variables.tf` + `outputs.tf` + `providers.tf` + `README.md` (inputs/outputs table). Dependencies between modules = child output → parent input. Scale three ways: `count` (identical), `for_each` (individually addressable), modules (whole units repeated).

**Dependencies** — prefer implicit (attribute references); `depends_on` only where Terraform can't infer ordering; visualize with `terraform graph -type=plan | dot -Tpng > graph.png`.

**State discipline** — state maps real resources to config (`terraform.tfstate`: `version`, `terraform_version`, `serial`, `lineage`, `outputs`, `resources`). Local state = solo experimentation only; teams use remote backends (GCS/S3/Azure/Terraform Cloud) with state locking. Backend migration: edit config → `init` (yes) → re-`init` to verify. Harden the state bucket: versioning on, `force_destroy = false`, `public_access_prevention = "enforced"`, uniform access.

**Secrets split** — Terraform provisions secret infrastructure & policies; **Secret Manager holds secret data** (rotation, TTL/expire_time, audit logging are its job, not Terraform's). The three wrong ways: hard-coding, plain-text tfvars, unsecured state files. CMEK (KMS) when compliance requires your key lifecycle, GMEK otherwise. Feed pipelines via `TF_VAR_my_secret ← ${{ secrets.MY_SECRET }}`.

**Least privilege (IAM/RBAC)** — predefined service roles bound per resource (`_iam_member`), tightened with condition expressions; big ladders: BigQuery dataViewer→dataEditor→dataOwner, cloudsql viewer→editor→admin. Fetch members via data sources, never hard-code PII.

**Resilience stack** — backups (disk snapshots with timestamps, versioned buckets with lifecycle rules, Cloud SQL PITR with `start_time` + `retention_count`) *plus* failover (Cloud DNS records + health checks auto-routing to the secondary region) *plus* observability (audit-logs sink to BigQuery, alert policies with threshold/duration/channel).

**Testing ladder & CI/CD skeleton** — climb in order: `fmt` → `validate` → `plan` → TFLint (pre-commit) → Checkov (PR scan, custom Python policies) → Terratest/pytest (real infra; Terratest invariant: `defer terraform.Destroy`). CI: stages **validate → plan → apply**, apply restricted to main or behind manual approval, archive `plan.out`/state.

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-intro-to-iac-and-terraform.md) | Introduction to IaC and Terraform | IaC, declarative syntax, execution plans, provider ecosystem |
| [ch02](chapters/ch02-getting-started.md) | Getting Started with Terraform | Terraform workflow, HCL blocks/arguments/expressions, init→destroy commands |
| [ch03](chapters/ch03-key-concepts.md) | Key Concepts of Terraform | Registry provider tiers, variables/outputs/locals, modules, dependencies, state & locking |
| [ch04](chapters/ch04-provisioning-gcp.md) | Provisioning Infrastructure on GCP | count/for_each/modules, GCS remote state, VPC + firewalls, Cloud SQL hardening, service accounts, GKE |
| [ch05](chapters/ch05-secrets-security-resilience.md) | Managing Secrets, Enhancing Security, and Ensuring Resilience | Secret Manager split, GMEK/CMEK, IAM/RBAC + conditions, state hardening, DR & DNS failover |
| [ch06](chapters/ch06-testing-automation.md) | Testing and Automation | TFLint, Checkov, Terratest, pytest, CI/CD skeletons (Actions/GitLab/Jenkins) |

## Topic Index

- **Auth (service accounts, keys, credentials)** → ch04, ch05
- **Backend (local/remote, gcs)** → ch03, ch04
- **Backend migration** → ch03, ch04
- **Checkov** → ch06
- **Cloud SQL / MySQL / PostgreSQL** → ch04
- **CI/CD (GitHub Actions, GitLab CI, Jenkins)** → ch06
- **Compliance** → ch05, ch06
- **count** → ch03, ch04
- **Custom VPC / subnets / CIDR** → ch04
- **dependencies / depends_on** → ch03, ch04
- **DNS failover / disaster recovery** → ch05
- **Encryption (GMEK, CMEK, KMS)** → ch05
- **Event-driven pipeline (Cloud Functions, Pub/Sub, BigQuery)** → ch04
- **Firewalls & rules (locals table)** → ch04
- **GKE / Kubernetes** → ch03, ch04
- **HCL syntax (blocks, arguments, expressions)** → ch02
- **IAM / RBAC / least privilege** → ch05
- **Labels & tagging** → ch04, ch05
- **Monitoring & alerting / Cloud Audit Logs** → ch04, ch05
- **Modules (root/child/local/published/nested)** → ch02, ch03, ch04
- **for_each / loops** → ch03, ch04
- **Outputs** → ch03
- **Plan / execution plan** → ch01, ch02, ch04
- **Secret Manager / secrets** → ch05
- **State (file, locking, workspaces, force-unlock)** → ch03, ch04, ch05
- **tfvars / TF_VAR_ / environment variables** → ch03, ch05, ch06
- **Terraform Registry** → ch03
- **Terratest / pytest / testing** → ch06
- **TFLint** → ch06
- **Validation (fmt/validate)** → ch02, ch06
- **Variables (types, validation, sensitive, nullable)** → ch03
- **Verification with gcloud** → ch04
- **Workspaces** → ch03

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — all techniques and design patterns
- [cheatsheet.md](cheatsheet.md) — quick reference tables and decision guides

---

## Scope & Limits

This skill covers the book content only. For hands-on implementation in your codebase,
combine with project-specific tools. For topics beyond this book, check related skills
or ask the agent directly. The book targets Terraform ~1.9 with the Google provider
(5.38.0 in examples) and GCP as the reference platform; commands and APIs may have
evolved since publication.