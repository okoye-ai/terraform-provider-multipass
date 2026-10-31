---
name: terraform_up_and_running
description: "Knowledge base from \"Terraform: Up and Running, 3rd Ed.\" by Yevgeniy Brikman. Use when applying Brikman's frameworks for Terraform state management, module design, loops and conditionals, secrets management, multi-provider/multi-account setups, production-grade infrastructure checklists, Terratest testing, and team CI/CD workflows for IaC."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform: Up and Running, 3rd Edition (Writing Infrastructure as Code)
**Author**: Yevgeniy Brikman | **Pages**: ~460 | **Chapters**: 10 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load the core frameworks below for reference
- **With a topic** — ask about "state isolation", "for_each", "secrets", or another indexed topic; I find and read the relevant chapter
- **With a chapter** — ask for `ch05`; I load that specific chapter summary
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic below, I will read the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

**The premise (ch01):** Terraform's goal is fluency in infrastructure via code. DevOps = culture, automation, measurement, sharing (CAMS); this book covers the automation half through Terraform.

**IaC five tool categories (ch01)** — pick one provisioning tool, then compose:
1. Ad hoc scripts → 2. Config management (Ansible/Chef/Puppet) → 3. Server templating (Packer/Docker/Vagrant) → 4. Orchestration (Kubernetes/ECS/Nomad) → 5. **Provisioning (Terraform/CloudFormation/Pulumi)**. Use Terraform when you need to *create* servers/DBs/LBs/networks; combine with the others (Terraform+Ansible, Terraform+Packer, Terraform+Packer+Docker+K8s).

**Key Terraform workflow (all chapters):** write config → `terraform plan` (read the diff!) → `terraform apply`. Everything is declarative end-state; the tool diffs config against state.

**Golden Rule of Terraform (ch10):** *"The main branch of the live repository should be a 1:1 representation of what's actually deployed in production."* Live repo (what's deployed per env) is separate from the modules repo (reusable, versioned, semver-tagged code).

**State discipline (ch03):** state maps config → real-world IDs. Rules:
- Remote backend + locking (S3 + DynamoDB `LockID`) as soon as anyone else touches the code — never Git, never local-disk.
- Isolate: **workspaces for experiments only; folder-per-environment×component for real isolation; separate AWS accounts per env for production.**
- Never reuse a backend `key` across modules; one shared bucket+table per account.
- Consuming other components: `terraform_remote_state` read-only data source (or Terragrunt dependencies).

**Module design (ch04, ch08):** modules are like functions — inputs (variables) are the API, outputs are returns, locals are private internals.
- Extract to a module the moment you copy-paste config between environments.
- Provider blocks live **only in root modules**; reusable modules are never applied directly.
- **"Large modules should be considered harmful"** (>few hundred lines): split by domain (networking/, services/, data-storage/).
- Production-grade = small + composable + **testable (every module has `examples/`, every example has tests)** + **releasable (pin everything)**.
- Validation in layers: `validation` blocks → `precondition` → `postcondition` → Terratest/OPA.

**Loops & conditionals (ch05):** the author's canonical split —
- `count = cond ? 1 : 0` for 0-or-1 conditional switches; **`for_each` for all other loops** (stable identity, per-item config; wrap lists in `toset()`); `for` expressions for transformations; `dynamic` for inline-block loops; `%{ for }`/`%{ if }` string directives for templates.
- `count`/`for_each` accept only plan-time-known values (never another resource's attributes).
- Refactors: `moved` block (Terraform 1.1+) or `terraform state mv`; success = plan shows *no changes*. Import any out-of-band infra that breaks apply.

**Zero-downtime deployment (ch05):** prefer native mechanisms (ASG `instance_refresh`, ECS deployment %, Kubernetes RollingUpdate) over the create_before_destroy + min_elb_capacity glue pattern, which resets ASGs to min_size on every deploy. A `-/+` in plan output = forces replacement = downtime; find it before applying.

**Secrets management (ch06):** secrets passed to resources land **in plain text in state and plan files** — encrypted backend + access control is mandatory regardless of technique.
- Infrastructure secrets are reversible (AES); customer secrets one-way (bcrypt). Each secret tool handles exactly one type.
- Machine auth: CI in-cloud → IAM role; CI out-of-cloud + OIDC → OIDC (scope `token.actions.githubusercontent.com:sub` per repo!); otherwise stored credentials as last resort.
- Resource secrets by need: env vars (testing, $0) → encrypted files in VCS (sops/KMS) → centralized stores (Vault / Secrets Manager, rotation + audit).

**Versioning & providers (ch07, ch08):** pin all three layers — Terraform core (exact in prod), providers (`~> 4.0` + committed `.terraform.lock.hcl`), modules (semver tags via `?ref=`). Declare `required_providers` always. Multiple copies of a provider = `alias` + `configuration_aliases`, injected by the root via `providers = {}`; otherwise default to separate module per region/account/cloud (blast-radius isolation).

**Testing (ch09):** follow the test pyramid, grow it incrementally, and pick tools per layer:
- Static analysis (validate/tfsec/tflint/Terrascan — free, no auth) > plan testing (OPA/Sentinel/Checkov) > server testing (InSpec/goss) > Terratest unit (~4–5 min) > integration (10–15 min) > E2E (use a persistent test env past ~600 resources).
- Terratest hygiene: `defer terraform.Destroy` (declared BEFORE InitAndApply), namespaced unique resource names, retries (terraform 3×/5 s, HTTP 10×/10 s, `go test -timeout 30m`), test stages with `SKIP_` env vars.

**Team workflow (ch10):** always run plan before apply; always test in pre-prod (IaC has **no auto-rollback**); shared envs deploy from a **single branch**; plan-as-PR (Atlantis/TFC) with ≥1 approver; drift detection = random `terraform plan` in live-repo folders — **"no changes"** is the gold standard; infra code is never auto-deployed to prod like app code.

**Production reality check (ch08):** bet-your-company infra takes long — no matter the tool (managed service 1–2 wks; stateless app 2–4 wks; stateful cluster 2–4 mo; whole architecture 6–36 mo). Plan accordingly; don't skip checklist items (security, metrics, logs, backups, tests...).

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-why-terraform.md) | Why Terraform | IaC five tool categories, immutable infrastructure, tool-selection trade-offs |
| [ch02](chapters/ch02-getting-started.md) | Getting Started with Terraform | init/plan/apply workflow, declare-and-reference, ASG+ALB wiring |
| [ch03](chapters/ch03-managing-state.md) | How to Manage Terraform State | Remote backends, state locking, bulkhead isolation, remote-state wiring |
| [ch04](chapters/ch04-reusable-modules.md) | Reusable Infrastructure with Modules | Module API (inputs/outputs/locals), versioned modules, inline-block gotcha |
| [ch05](chapters/ch05-loops-conditionals-gotchas.md) | Tips & Tricks: Loops, If-Statements, Deployment, Gotchas | count vs for_each, dynamic blocks, zero-downtime, moved blocks |
| [ch06](chapters/ch06-managing-secrets.md) | Managing Secrets with Terraform | Secret taxonomy, machine-auth decision tree, encrypted files vs secret stores |
| [ch07](chapters/ch07-multiple-providers.md) | Working with Multiple Providers | Aliases & configuration_aliases, multi-account, EKS+Kubernetes |
| [ch08](chapters/ch08-production-grade-code.md) | Production-Grade Terraform Code | Production checklist, small/composable/testable/releasable modules, layered validation |
| [ch09](chapters/ch09-testing-terraform-code.md) | How to Test Terraform Code | Test pyramid, Terratest workflow, static/plan/server testing tools |
| [ch10](chapters/ch10-terraform-as-team.md) | How to Use Terraform as a Team | Golden Rule, live vs modules repo, plan-as-PR CI/CD, drift detection |

## Topic Index

- **ALB / ASG / load balancers** → ch02, ch05
- **Anti-patterns, common gotchas** → ch02, ch04, ch05, ch07, ch09, ch10
- **Backend / remote backend / locking** → ch03
- **CI/CD for infrastructure** → ch09, ch10
- **conditionals / if-statements** → ch05
- **count / for_each / for expressions** → ch05
- **create_before_destroy / zero-downtime** → ch02, ch05
- **data sources** → ch02, ch07
- **dependency injection (tests)** → ch09
- **drift / out-of-band changes** → ch05, ch10
- **escape hatches / provisioners** → ch08
- **examples / testing workflow** → ch08, ch09
- **IAM roles / OIDC / instance profiles** → ch06, ch07
- **import / moved block / refactoring** → ch05
- **input variables / outputs / locals** → ch02, ch04, ch08
- **inline blocks** → ch04
- **instance refresh / rollout strategies** → ch05, ch10
- **Kubernetes / EKS / Docker** → ch07, ch09
- **locks / state locking** → ch03
- **modules, reusable** → ch04, ch07, ch08
- **multi-account / multi-region** → ch07
- **plan testing / OPA / Sentinel** → ch09, ch10
- **production-grade checklist** → ch08
- **provider aliases / configuration_aliases** → ch07
- **provider versioning / lock file** → ch07, ch08
- **secrets / KMS / Vault / sops / sensitive** → ch03, ch06
- **static analysis / tfsec / tflint** → ch09
- **state file / state isolation** → ch03, ch06
- **team adoption / code review / style** → ch10
- **templatefile / string directives** → ch03, ch05
- **Terratest / test stages / retries** → ch09
- **test pyramid** → ch09
- **version pinning / semantic versioning** → ch04, ch08
- **workspaces** → ch03, ch10
- **zero-downtime deployment** → ch05

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — all techniques and patterns with when/how/trade-offs
- [cheatsheet.md](cheatsheet.md) — decision tables, thresholds, and the book's core rules

---

## Scope & Limits

This skill covers the book's content (Terraform 1.x era, 3rd edition, 2022) only. For hands-on implementation in your codebase, combine with project-specific tooling and current provider docs. Note the book predates the OpenTofu fork and Terraform's license change — check `terraform_in_depth` or `terraform_at_scale` skills for OpenTofu/enterprise-scale coverage.