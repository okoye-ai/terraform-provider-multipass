---
name: terraform_for_developers
description: "Knowledge base from \"Terraform for Developers, Second Edition: Essentials of Infrastructure Automation and Provisioning\" by Kimiko Lee. Use when applying Lee's frameworks for Terraform CLI workflow, HCL variables/interpolation/conditionals/loops, modules and versioning, state management and drift, provisioners, Azure Key Vault secrets, cloud networking (VPC/VNet), troubleshooting and testing, Vault dynamic secrets, and AKS/Kubernetes provisioning."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform for Developers, 2nd Edition
**Author**: Kimiko Lee | **Pages**: ~236 | **Chapters**: 10 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `state`, `modules`, `provisioners`, or another indexed topic; I find and read the relevant chapter
- **With chapter** — ask for `ch05`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

**The core command loop** — every change goes `init → validate → fmt → plan → apply`. Review the plan's `+`/`~`/`-` diff before apply; in pipelines, `plan -out=file` then `apply <file>` so the reviewed plan is exactly what deploys.

**Declarative, state-tracked model** — declare the *desired end state* in HCL; Terraform builds a resource dependency graph and computes the minimal delta against `terraform.tfstate`, its authoritative record of real resources. The state file is sensitive and central — store one copy in a locked remote backend (Azure Blob/S3/GCS/Terraform Cloud) for anything shared.

**Parameterization over duplication** — environment differences are *data* (`terraform.tfvars`, `TF_VAR_*`, `-var`), never code copies. Variables carry type constraints, defaults, descriptions, and `validation` blocks. Interpolation (`"myapp-${var.env}-vm"`) splices runtime values; bare references (`name = var.x`) create dependency edges so resources cascade correctly.

**Loops decision rule** — `count` for N near-identical copies (addressed by `count.index`); `for_each` for keyed, differing resources (stable addresses `type.name["key"]`, no index-shift churn — prefer it); `dynamic` blocks for repeated *sub-blocks* inside one resource (e.g. ingress rules).

**Module contract** — inputs (typed variables; consumers pick) / locals (internal named computations) / outputs (the narrow documented surface). Pin shared modules to a semver git tag: `source = "git::https://...//module?ref=v1.2.1"` — mutable branches import untested code. Nest modules to mirror architecture (network → subnet).

**Provisioners as last resort** — `file`, `local-exec`, `remote-exec`, `null_resource` fill create-time gaps: upload a script then run it; re-run when a `triggers` value changes. Failed provisioners *taint* the resource (next run destroys/recreates), scripts must be idempotent, and they never re-run on updates — ongoing configuration belongs in cloud-init/custom-data or Ansible/Chef, not inline scripts.

**Secrets lifecycle** — generate → store in a vault → least-privilege access policies → distribute via pipeline injection → rotate with versioning → revoke/cleanup. In Terraform: store in Azure Key Vault, retrieve with `data "azurerm_key_vault_secret"`, never hard-code; escalate to HashiCorp Vault *dynamic* secrets so leaked credentials expire (Vault deletes the credential and its principal at lease end).

**Networking in layers** — VPC/VNet boundary (one `/16`) → disjoint subnets per tier (`/24` slices, public vs private) → route tables + gateways (IGW/NAT) via associations → security groups/NSGs as versioned rules → DNS zones → load balancers (LB → target group → listener → attachment). Use `cidrsubnet()` to derive subnet ranges; hand-typed overlapping CIDRs are the classic network failure.

**Error triage** — classify first: won't parse = *syntax*; plan rejects (undeclared reference, wrong type, CIDR outside parent) = *semantic*; apply fails (403 RBAC, 429 throttle, region unavailability, drift) = *runtime* — read the provider API error code before changing anything. Manage drift by `refresh → plan → decide`: apply to make reality match code, or revert the external change.

**Import procedure** — write an accurate resource block → get the real ID → `terraform import <addr> <id>` → the follow-up plan must show **"No changes"**.

**Four-layer test suite** — unit (Terratest, one module, `defer terraform.Destroy`) → integration (module wiring, outputs resolve) → validation (live behavior: `HttpGetWithRetry` for HTTP 200) → compliance (OPA Rego against `terraform show -json tfplan`; non-empty deny blocks the pipeline).

**Provider chaining for Kubernetes** — azurerm builds/reads the AKS cluster; feed its `kube_config` into `provider "kubernetes"`; manage namespaces, deployments, and services in the same codebase, from network to workload.

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-introduction-to-terraform-and-iac.md) | Introduction to Terraform and IaC | IaC Evolution Stack, Mutable vs Immutable, Plugin architecture |
| [ch02](chapters/ch02-getting-started-with-terraform.md) | Getting Started with Terraform | Core Command Loop, Credential Separation, Pinned Provider Versions |
| [ch03](chapters/ch03-essentials-of-configuration-language.md) | Essentials of Terraform Configuration Language | count vs for_each rule, Dynamic Blocks, Validation blocks |
| [ch04](chapters/ch04-modules-and-reusable-infrastructure.md) | Modules and Reusable Infrastructure | Module Contract, Nested Modules, Semver git-tag versioning |
| [ch05](chapters/ch05-state-management.md) | Terraform State Management | Local vs Remote rule, Drift Reconciliation Loop, State Migration Playbook |
| [ch06](chapters/ch06-provisioners-and-provisioning-resources.md) | Provisioners and Provisioning Resources | Four Provisioners, Tainted-resource lifecycle, Bootstrap-not-Manage |
| [ch07](chapters/ch07-working-with-secrets.md) | Working with Secrets | Secrets Lifecycle (6 stages), Key Vault integration pattern, Audit logging |
| [ch08](chapters/ch08-administering-networks-with-terraform.md) | Administering Networks | Network Stack Layers, LB wiring pattern, Network troubleshooting playbook |
| [ch09](chapters/ch09-advanced-topics-troubleshooting-testing.md) | Advanced Topics: Troubleshooting, Import, Testing | Three Error Categories, Import Procedure, Four-Layer Test Suite, Rego gates |
| [ch10](chapters/ch10-administering-terraform-as-expert.md) | Administering Terraform As Expert | Custom Module Method, Vault Dynamic Secrets, AKS + provider chaining |

## Topic Index

- **AKS / Kubernetes** → ch10
- **CIDR / subnets** → ch08
- **Compliance testing (OPA, tfsec)** → ch09
- **Conditionals (ternary)** → ch03
- **count vs for_each** → ch03
- **Data sources** → ch01, ch07, ch10
- **Destroy** → ch02
- **Drift** → ch05
- **Dynamic blocks** → ch03
- **Dynamic secrets (Vault)** → ch10
- **Errors (syntax/semantic/runtime)** → ch09
- **fmt / validate** → ch02
- **HCL basics** → ch02, ch03
- **Image metadata (AMI/managed image)** → ch10
- **Import** → ch09
- **Interpolation** → ch03
- **Key Vault** → ch07
- **KPIs / performance** → ch09
- **Load balancers** → ch08
- **Locals (modules)** → ch04
- **Modules** → ch04, ch10
- **Parallelism / throttling (429)** → ch09
- **Plan / apply workflow** → ch02
- **Provisioners (file, local-exec, remote-exec, null_resource)** → ch06
- **RBAC / service principal** → ch02, ch09
- **Remote state backends** → ch05
- **sensitive = true** → ch10
- **State locking / force-unlock** → ch05, ch09
- **State manipulation (rm/mv)** → ch05
- **Terratest (unit/integration/validation)** → ch09
- **Terraform install / Azure setup** → ch02
- **Versioning (providers, modules)** → ch02, ch04
- **Variables** → ch02, ch03
- **Workspaces** → ch01, ch02
- **VPC / VNet / routing** → ch08

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — all techniques and design patterns
- [cheatsheet.md](cheatsheet.md) — quick reference tables and decision guides

---

## Scope & Limits

This skill covers the book content only (Azure-flavored examples throughout). For hands-on implementation in your codebase, combine with project-specific tools. The book's inline examples use older provider/CLI versions (e.g. azurerm 3.0, Terraform 1.1) — verify current syntax against provider docs when applying. For topics beyond this book (OpenTofu, Terraform Cloud, sentinel/policy suites in depth), check related skills or ask the agent directly.