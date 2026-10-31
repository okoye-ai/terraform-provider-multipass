---
name: terraform_cookbook
description: "Knowledge base from \"Terraform Cookbook: Hands-on enterprise recipes to automate, secure, and scale cloud infrastructure\" by Huzefa Husain. Use when applying Husain's 102 recipes and Chef's Special projects for Terraform IaC on Azure/AWS/GCP: provider setup, variables/state/outputs, modules, compute/networking/storage, external data, scaling, Kubernetes, testing/CI-CD, security, troubleshooting, multi-cloud, and Terraform Cloud collaboration."
---

<!-- argument-hint: [topic, recipe number, framework name, or chapter number] -->

# Terraform Cookbook: Hands-on enterprise recipes
**Author**: Huzefa Husain | **Publisher**: BPB Publications, 1st Ed. 2026 | **Chapters**: 17 | **Recipes**: 102 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load the core frameworks below for reference
- **With a topic** — e.g. `drift`, `modules`, `state lock`, `blue-green`, `Sentinel`; I find and read the relevant chapter
- **With a recipe** — e.g. `recipe 74` or `Sentinel policy`; I locate it in its chapter file
- **With a chapter** — e.g. `ch14`; I load that specific chapter
- **Browse** — ask "what chapters/recipes do you have?"

Every chapter file lists its recipes (original global numbers 1–102), preserves
the book's HCL syntax, and reconstructs one worked example (usually the
"Chef's Special" enterprise project).

---

## Core Frameworks & Mental Models

**The recipe → Chef's Special method.** The book teaches one capability at a
time via numbered recipes, then each chapter's "Chef's Special project"
combines them into an enterprise-grade build (Appetizer → Main course →
Dessert = setup → core workload → polish/verify). Use recipes when you need a
single capability; use the Chef's Special when you need the assembled,
production-shaped pattern.

**Plan-driven change.** Terraform replaces manual console edits with a
predictable loop: `init` → `validate` → `plan` (read it, always) → `apply` →
state tracks reality. Declarative config beats imperative scripts on
idempotence, diff visibility, and auditability — manual changes create drift
that plan exposes.

**State is the operating core.** State is the only source of truth for what
Terraform owns. Rules the book enforces: remote state with locking for any
team use; never commit `*.tfstate*`; refresh before big plans; import
already-existing resources (`terraform import`) instead of recreating; treat
state as sensitive data (it records secrets).

**Drift handler — detect, then decide who is right.** `terraform plan` shows
the divergence. Config correct → `apply` enforces it back. Manual change
wanted → `terraform apply -refresh-only` adopts it into state only. For
recurring drift: nightly `terraform plan -detailed-exitcode` as an alarm.

**Module design = inputs in, outputs out, version pinned.** Package standard
infrastructure (network, compute, database, monitoring) as modules consumed
with pinned versions (`version = "~> 1.3"`, git `ref`), composed by wiring one
module's outputs into the next module's inputs. Approved modules become the
organization's trusted building blocks.

**Composition toolbox — pick per situation.**
- `for_each` for individually addressable, named resources (survives reorder)
- `count` for identical clones / optional blocks (`count = var.enabled ? 1 : 0`)
- `dynamic` blocks kill copy-pasted nested blocks (NSG rules, backends)
- `locals` compute recurring expressions once (tags, naming, CIDRs)
- data sources read existing infra without adding dependency edges

**Security ladder.** Least privilege at the right scope (resource group, not
subscription Contributor); Managed Identity / short-lived tokens for
pipelines; secrets fetched from Key Vault/Vault at apply time, `sensitive =
true` on inputs and outputs; state and secrets never in Git (`.terraform/`,
`*.tfstate*`, secret-bearing `*.tfvars`, `crash.log` out; lock file policy —
commit or ignore, pick one).

**Policy as code before apply.** Sentinel (Terraform Cloud native; policies
import `tfplan`/`tfconfig`/`tfstate`) or OPA/Rego in CI. Enforcement levels:
advisory (warn) < soft-mandatory (overridable block) < hard-mandatory (no
override). Typical rules: mandatory tags, region allowlists, instance-size
caps, no public access to sensitive resources.

**CI quality gate ladder.** `terraform fmt` → `terraform validate` → TFLint →
Checkov → plan artifact on the PR → Terratest for critical modules → apply
from a saved plan file. Jenkins/GitHub Actions recipes covered in ch12.

**Error grammar.** Terraform errors name the type, then file:line:col, then a
hint — read them before searching the web. Lock errors mean a stranded or
active run; "already exists" means import or rename; "Cycle: a, b" means
break a circular reference (data source, module split, no gratuitous
`depends_on`); auth errors mean verify creds → check RBAC scope → test the
CLI outside Terraform. Deep diagnostics: `TF_LOG=DEBUG` + `TF_LOG_PATH` +
`terraform console`.

**Workspaces equation.** configurations × environments = workspaces. One
workspace per environment per component; align names with owning teams;
split state-heavy resources (databases, storage) from compute to shrink
blast radius.

**Multi-cloud discipline.** Portability via one root config per provider
rather than pretending one config fits all; shared modules and tagging
conventions; active-active deployment behind DNS; Terragrunt for DRY at
scale. Terraform Cloud adds remote runs, VCS-driven speculative plans on
PRs, private module registry, RBAC.

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-introduction-to-iac-with-terraform.md) | Introduction to IaC with Terraform | Three pillars (providers/resources/state), declarative vs imperative, plan-apply loop |
| [ch02](chapters/ch02-setup-and-first-real-world-config.md) | Setup & First Real-world Configuration | Per-cloud auth matrix, provider blocks, first VM recipes |
| [ch03](chapters/ch03-variables-state-and-outputs.md) | Variables, State, and Outputs | Variable precedence ladder, remote state migration, drift handler, import |
| [ch04](chapters/ch04-reusable-modules.md) | Reusable Modules | Module contract, source types, version pinning, module composition |
| [ch05](chapters/ch05-compute-instances.md) | Compute Instances | Five-part VM contract, SSH/cloud-init bootstrap, scale sets, load balancers |
| [ch06](chapters/ch06-networking-and-security.md) | Networking & Security Infrastructure | VNet/subnet segmentation, NSG layers, NAT, DNS/CDN, VNet peering |
| [ch07](chapters/ch07-storage-and-databases.md) | Storage & Databases | Blob static sites, managed disks, MySQL flexible + delegation, Cosmos DB, backup |
| [ch08](chapters/ch08-external-data.md) | External Data | External-data decision matrix, null_resource+triggers, remote state as data |
| [ch09](chapters/ch09-scaling-infrastructure.md) | Scaling Infrastructure | ASG/VMSS autoscaling, count vs for_each, multi-region, blue-green, large state |
| [ch10](chapters/ch10-advanced-techniques.md) | Advanced Configuration Techniques | for_each sets, conditionals, dynamic blocks, locals, null_resource scripts |
| [ch11](chapters/ch11-containers-and-kubernetes.md) | Containers & Kubernetes | AKS/GKE/EKS provisioning, Helm provider, Kubernetes ingress |
| [ch12](chapters/ch12-testing-and-cicd.md) | Testing & CI/CD | fmt/validate in CI, Terratest, Jenkins pipeline, TFLint, Checkov, plan-on-PR |
| [ch13](chapters/ch13-security-best-practices.md) | Security & Best Practices | Sensitive variables, Key Vault, Sentinel, version pinning, drift drills, team structure |
| [ch14](chapters/ch14-troubleshooting-errors.md) | Troubleshooting Terraform Errors | Error grammar, failed-apply recovery ladder, state locks, TF_LOG debugging |
| [ch15](chapters/ch15-multicloud-strategies.md) | Multi-cloud Deployment Strategies | Dual-cloud, cross-cloud networking, module reuse, active-active, Terragrunt |
| [ch16](chapters/ch16-terraform-cloud-workflows.md) | Collaborative Workflows with Terraform Cloud | Workspaces equation, VCS-driven runs, run lifecycle, Sentinel sets, private registry, RBAC |
| [ch17](chapters/ch17-capstone-enterprise-deployment.md) | Capstone Enterprise Deployment | Four pillars (HA/security/scalability/DR), multi-tier multi-zone build, monitoring as code |

## Topic Index

- **ASG / autoscaling** → ch09
- **Authentication / provider credentials** → ch02, ch13, ch14
- **Backend / remote state** → ch03, ch16, ch17
- **Blue-green** → ch09
- **CI/CD pipelines** → ch12
- **Conditional resources / count** → ch09, ch10
- **Data sources** → ch08, ch10
- **Dependency cycles** → ch14
- **Drift** → ch03, ch13
- **Dynamic blocks** → ch10
- **External scripts / null_resource** → ch08, ch10
- **for_each** → ch09, ch10
- **Helm / Kubernetes ingress** → ch11
- **Import existing resources** → ch03, ch14
- **Key Vault / secrets** → ch13, ch14, ch17
- **Load balancers** → ch05, ch06
- **Local values / locals** → ch10
- **Modules** → ch04, ch16, ch17
- **Multi-region** → ch09, ch15
- **NSG / network security** → ch06, ch17
- **Outputs** → ch03
- **Pipelines (Jenkins, GitHub Actions)** → ch12
- **Policy as code (Sentinel, OPA)** → ch13, ch16
- **Private module registry** → ch16
- **RBAC / least privilege** → ch13, ch16
- **Remote state as data** → ch08
- **Scaling / scale sets** → ch05, ch09
- **Sentinel enforcement levels** → ch16
- **State lock** → ch13, ch14
- **Stateful failure recovery / taint** → ch14
- **Storage accounts / blob / disks** → ch07
- **Terragrunt** → ch15, ch16
- **Terraform Cloud workspaces** → ch16
- **TF_LOG / debugging** → ch14
- **Version pinning (providers/modules)** → ch04, ch13
- **VPC/VNet/peering** → ch06, ch15
- **Windows VMs** → ch05

## Supporting Files

- [glossary.md](glossary.md) — key terms with definitions
- [patterns.md](patterns.md) — all techniques and design patterns with trade-offs
- [cheatsheet.md](cheatsheet.md) — decision tables and operator guides

---

## Scope & Limits

This skill covers the book's synthesized content only — 102 recipe summaries
and their decision rules, not raw book text. Note: 123 figures from the
source were not readable during extraction; chapter summaries rely on text
only. The book's complete code bundle lives at
https://github.com/bpbpublications/Terraform-Cookbook. Azure is the primary
provider in examples, with AWS/GCP cross-references. For provider-specific
syntax beyond the book, consult the provider docs directly.