---
name: terraform_in_action
description: "Knowledge base from \"Terraform in Action\" by Scott Winkler. Use when applying Winkler's frameworks for infrastructure as code (IaC), HCL, Terraform resource lifecycle and state, modules, CI/CD automation pipelines for Terraform, zero-downtime and Blue/Green deployments, custom providers, secrets management and policy as code, or referencing the book's concepts."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform in Action
**Author**: Scott Winkler (Manning, ©2021) | **Pages**: ~410 | **Chapters**: 13 + 5 appendices | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `state`, `modules`, `provisioners`, or another indexed topic; I find and read the relevant chapter
- **With chapter** — ask for `ch05`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

**Terraform = a state-management engine that performs CRUD.** Everything follows
from the lifecycle model: every managed resource implements `Create()`, `Read()`,
`Update()`, `Delete()`; `Read()` runs at plan time, and the plan decision tree is
Create / Read / Update / Delete / No-op. Losing state = losing track of resources.

**A module is a function with side effects** — inputs are `variable`s, outputs are
`output` values, side effects are the resources it provisions; locals are the
function's temporary symbols. Wire modules by **bubbling up** child outputs to the
root and **trickling down** inputs to siblings — pass the minimum, keep 3–4 nesting
levels max. Use **flat modules** (one .tf file per independent component) for small
self-contained projects, nested for shared/large codebases.

**Two-stage deployment**: Terraform for *static* infrastructure (changes rarely),
CI/CD or Ansible for *dynamic* application code (changes constantly). The
ladder for application delivery: Docker/CI-CD pipeline (ch7), Nomad/federated
clusters (ch8), **Terraform + Ansible — "better together"** (ch9).

**Zero downtime without lifecycle tricks**: prefer Blue/Green with a feature flag —
two autoscaling environments over a shared base layer; deploy to the *idle* side,
flip `var.production` to cut over in seconds. Avoid `create_before_destroy`
("more trouble than it is worth"), keep `prevent_destroy`/`ignore_changes` for
special cases. Databases live in the base layer.

**Security stance — think like a hacker (ch13)**: state files are plaintext JSON;
only resources, data sources, and outputs store state. `sensitive = true` redacts
references, not values — round-trip tricks (local_file → data.local_file) bypass
it. Leak vectors: trace logs (signed creds for ~15 min), local-exec provisioners,
`data "external"` (arbitrary code at **plan** time), and the HTTP data source.
Counter-moves: env vars for provider config, git-ignored `secrets.tfvars`,
SECRET_ID + runtime fetch in apps, Vault/ASM dynamic secrets, Sentinel policy
as code between plan and apply.

**Provisioners are a last resort** (declared anti-pattern): Shell provider →
custom Go provider → null_resource hacks, in that order. `for_each` beats `count`;
`terraform plan` is a linter, *not* a dry run (data sources execute code at plan).
Automation = four-stage pipeline: Source → Plan → **Approve** → Apply, with
`CONFIRM_DESTROY` destroy runs and injected backend config.

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-getting-started-with-terraform.md) | Getting started with Terraform | Six characteristics; provisioning vs CM; data sources |
| [ch02](chapters/ch02-lifecycle-of-a-terraform-resource.md) | Life cycle of a Terraform resource | Plan decision tree; function hooks; drift correction |
| [ch03](chapters/ch03-functional-programming.md) | Functional programming | Var/locals/outputs analogies; for expressions; count |
| [ch04](chapters/ch04-multi-tiered-web-application-aws.md) | Multi-tiered web application in AWS | Modules as functions; bubble-up/trickle-down; build-vs-buy |
| [ch05](chapters/ch05-serverless-made-easy.md) | Serverless made easy | Sort by group then size; strangler façade; shim modules |
| [ch06](chapters/ch06-terraform-with-friends.md) | Terraform with friends | S3 backend anatomy; flat vs nested; workspaces |
| [ch07](chapters/ch07-cicd-pipelines-as-code.md) | CI/CD pipelines as code | Static vs dynamic infra; for_each; dynamic blocks; provisioners |
| [ch08](chapters/ch08-multi-cloud-mmorpg.md) | A multi-cloud MMORPG | Cluster federation; Raft quorum; managed services |
| [ch09](chapters/ch09-zero-downtime-deployments.md) | Zero-downtime deployments | Lifecycle flags; Blue/Green; Terraform + Ansible |
| [ch10](chapters/ch10-testing-and-refactoring.md) | Testing and refactoring | Module expansions; state migration (mv/rm/import); taint; terraform-exec |
| [ch11](chapters/ch11-writing-a-custom-provider.md) | Writing a custom provider | Provider anatomy; CRUD hooks; acceptance tests |
| [ch12](chapters/ch12-automating-terraform.md) | Automating Terraform | Four-stage pipeline; backend-in-env; env strategies |
| [ch13](chapters/ch13-secrets-management.md) | Security & secrets management | Leak-vector catalogue; static vs dynamic secrets; Sentinel |
| [appendices](chapters/ch-appendices.md) | Auth (AWS/Azure/GCP), Shell provider, Petstore data source | Provider setup; shell_script resources |

## Topic Index

- **Anti-patterns & provisioners** → ch07, ch09, ch11, ch13
- **Automation, CI/CD for Terraform** → ch12, ch07
- **Backend / remote state / locking** → ch02, ch06, ch13
- **Blue/Green, zero-downtime** → ch09
- **count, for_each, dynamic blocks** → ch03, ch07, ch10
- **Custom providers (Go)** → ch11, appendices
- **Data sources** → ch01, ch02, ch05, ch07, ch13
- **Dependencies (implicit/explicit)** → ch03, ch04, ch11
- **Modules & module design** → ch04, ch05, ch06, ch10
- **Multi-cloud & federation** → ch08
- **Plan/apply semantics** → ch01, ch02, ch07, ch12
- **Providers, authentication** → appendices, ch05, ch07, ch13
- **Refactoring & testing** → ch10, ch11
- **Sentinel / policy as code** → ch13, ch12
- **Serverless** → ch05, ch07, ch11
- **State migration, taint, import** → ch10
- **Workspaces & environments** → ch06, ch12
- **Secrets & security** → ch13 (catalogue), ch06, ch11

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — 14 reusable techniques with when/how/trade-offs
- [cheatsheet.md](cheatsheet.md) — decision rules, plan decision tree, leak tells, idioms

---

## Scope & Limits

This skill covers the book content only (Terraform ~0.15 / 2021 era; OpenTofu and
post-1.x native features like `moved` blocks or `terraform test` are not covered).
Extraction used pdftotext (Docling unavailable), so long code listings may appear
flattened — consult the book or the GitHub repo (terraform-in-action/manning-code)
for exact listings. For hands-on implementation in your codebase, combine with
project-specific tooling.