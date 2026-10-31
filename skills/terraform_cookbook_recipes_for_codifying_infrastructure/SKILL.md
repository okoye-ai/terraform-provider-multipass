---
name: terraform_cookbook_recipes_for_codifying_infrastructure
description: "Knowledge base from \"Terraform Cookbook: Recipes for Codifying Infrastructure\" by Kerim Satirli and Taylor Dolezal (O'Reilly, 2024). Use when applying the authors' recipes for Terraform validation and policy as code, string/function patterns, modules and provider auth, Kubernetes/Helm/Nomad workloads, secrets management, state management and recovery, imports, workspaces, blue-green and real-world IaC deployments."
---

<!-- argument-hint: [topic, recipe name, or chapter number] -->

# Terraform Cookbook: Recipes for Codifying Infrastructure
**Authors**: Kerim Satirli & Taylor Dolezal | **Pages**: ~282 | **Chapters**: 10 (~117 recipes) | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load the core toolkit below
- **With a topic** — ask about `validation`, `secrets`, `state recovery`, `imports`, etc.; I read the relevant chapter first
- **With a chapter** — ask for `ch05`; I load that chapter file
- **Browse** — ask "what chapters do you have?"

The skill covers the book only. Note: the book's recipes are written to work with both Terraform and OpenTofu; examples mostly use AWS.

---

## Core Toolkit — how the authors decide

**1. Use Terraform when the decision is hard to undo by hand.** Its home turf: many resources, multiple environments, multiple providers, automated CI/CD deploys. Skip it (or go lighter) for a single server (Ansible/Puppet), single-vendor footprints (CloudFormation/ARM), or PaaS. "Snowflake" systems usually benefit from being codified anyway when the org has an IaC mindset.

**2. The Validation Ladder — layer cheap checks under expensive ones.**
`fmt` → `validate` → `terraform console` (REPL for expressions) → **TFLint** (provider-specific: bad instance types, AMIs) → **TFSec** (security smells) → variable **`validation` blocks** (reject bad input at plan time, with a readable `error_message`) → resource **`lifecycle.postcondition`** (guarantees about resulting state) → **OPA/Sentinel** policy as code (org rules) → **GitHub Actions** runs the whole ladder on every PR. *Use ch02 for the syntax and CI wiring.*

**3. Sanitize user input at the boundary; say why it failed.** `trimspace` (edges) / `chomp` (trailing newlines, esp. after `file()`) / `trimprefix`–`trimsuffix` / `regex`–`replace`, then a `validation` block with an explicit message. Absent data is not an error: guard with `try(actual, fallback)` and `can(expr)`. *ch03.*

**4. Secrets live outside the state, or die — tiering:** dynamic Vault secrets (short TTL) > Vault KV / password-manager bridging > `TF_VAR_` env vars in CI > plaintext (never). Always `sensitive = true`, always a rotation + audit story, inject as late as possible. Never hardcode Vault tokens. *ch07.*

**5. Contain the blast radius structurally, not vigilantly.** One module per isolated unit; **separate workspace/state per environment**; least-privilege IAM; feature resources gated by `count = var.enable_x ? 1 : 0`; small, frequent applies; `-target` only in emergencies; plan output is part of PR review. *ch02 recipe 2.11; ch06 for HCP Terraform enforcement.*

**6. Prefer automated state mechanisms over state surgery.** Backend + state locking + versioned state history + workspace isolation first; restore a bad state from the States tab (HCP Terraform) rather than hand-editing; `terraform state rm` only cautiously, with team notice. Drift: re-apply or `import` the real resource. *ch06.10, ch09.4.*

**7. Modules are contracts, providers are identities.** A module = main/variables/outputs/docs (terraform-docs) + tests; consume public Registry modules pinned by `source` + `version`. Same provider, several targets → provider **aliases**; auth preference: role assumption / Vault > env vars > static keys; private registries need explicit `credentials`. Feed providers healthy endpoints via `http` data source + `jsondecode` + ternary. *ch04, ch06.*

**8. Separate cluster deployment from cluster configuration.** Provisioning the K8s cluster and managing what runs on it have different lifecycles and tools. Scheduling surfaces: `kubernetes_manifest` (HCL), Helm provider (charts, monitoring), Nomad; convert existing YAML with `k2tf` / `jsondecode`–`yamldecode`. *ch05.*

**9. Import before you delete anything.** Existing infrastructure enters Terraform through config-driven imports, then reconciles and validates — the safe retirement path for snowflake systems. *ch08.6.*

**10. Zero-downtime means two of everything, briefly.** Blue-green via conditional counts/weights behind a load balancer (or ALB target-group flip); flip traffic, watch, retire blue. Multi-region HA: aliased providers + global traffic steering. *ch8.10, ch10.2/10.4.*

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-getting-started.md) | Getting Started with Terraform | When to (not) use Terraform, providers/modules, version constraints, VCS repo strategy, backend table |
| [ch02](chapters/ch02-terraform-basics.md) | Terraform Basics | Validation ladder (TFLint/TFSec/OPA), preconditions/postconditions, CI pipeline, blast-radius limitation |
| [ch03](chapters/ch03-syntax-patterns.md) | Terraform Syntax Patterns | Input sanitization, regex/prefix manipulation, cidrsubnet, can/try, validation errors, cross-state sharing |
| [ch04](chapters/ch04-modules-and-providers.md) | Terraform Modules and Providers | Module authoring contract, provider credential ladder, aliases, service-health-aware config, Consul KV |
| [ch05](chapters/ch05-container-management.md) | Container Management | Deployment vs configuration, YAML vs HCL scheduling, k2tf, NetworkPolicies, Helm + Prometheus/Grafana, Nomad |
| [ch06](chapters/ch06-hcp-terraform-enterprise.md) | HCP Terraform and Terraform Enterprise | Workspace setup, VCS/GitOps integration, Sentinel policy sets, cost gates, remote operations, state recovery |
| [ch07](chapters/ch07-secrets-management.md) | Consuming and Managing Secrets | Secrets tiering, Vault KV, dynamic secrets, K8s secrets, rotation/audit, CI/CD secret injection |
| [ch08](chapters/ch08-configuration-management.md) | Configuration Management | user_data bootstrap, Ansible bridge, imports, workspaces, templates, dependencies, blue-green |
| [ch09](chapters/ch09-advanced-techniques.md) | Advanced Terraform Techniques | CI/CD module pipelines, advanced state management, for_each/for/setproduct, monitoring as IaC, debugging toolkit |
| [ch10](chapters/ch10-real-world-use-cases.md) | Real-World Use Cases | Multi-env workspaces, HA multi-region, EKS-as-code, blue-green ALB flip, RDS migrations, Lambda+API Gateway, GitOps, Spot, multicloud monitoring, DR |

## Topic Index

- **Aliases (providers)** → ch04, ch10
- **Blue-green deployment** → ch08, ch10
- **can / try** → ch03
- **CIDR / subnets** → ch03
- **CloudFormation vs Terraform / when to use** → ch01
- **Consul KV (dynamic config)** → ch04, ch08
- **Cost management** → ch06, ch10
- **Docker** → ch01, ch05
- **Drift / debugging (TF_LOG, plan -json)** → ch06, ch09
- **DynamoDB/backend state** → ch01
- **EKS / Kubernetes** → ch04, ch05, ch10
- **fmt / validate** → ch02
- **for_each / count / conditional resources** → ch02, ch08, ch09
- **GitOps** → ch01, ch06, ch10
- **Helm** → ch05
- **HCP Terraform (Terraform Cloud/Enterprise)** → ch01, ch06
- **Imports (existing infra)** → ch08
- **Monitoring (AMP/Grafana, Datadog)** → ch05, ch09, ch10
- **NetworkPolicies** → ch05
- **Nomad** → ch05
- **OpenTofu** → ch01
- **OPA / Sentinel (policy as code)** → ch02, ch06, ch09
- **Provider authentication** → ch04
- **Provider version constraints** → ch01, ch02
- **Regular expressions** → ch03
- **Secrets / Vault / sensitive data** → ch07
- **State (locking, recovery, remote state, sharing)** → ch01, ch02, ch03, ch06, ch09
- **Templates (templatefile, terraform-docs, Ansible)** → ch02, ch03, ch08
- **TFLint / TFSec** → ch02
- **terraform console** → ch01, ch02
- **Upgrades (0.x → 1.x, providers)** → ch01, ch02
- **Vault (dynamic secrets, KV)** → ch07
- **Web application architecture (HA, serverless)** → ch10
- **Workspaces (multi-environment)** → ch08, ch09, ch10

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — techniques & design patterns
- [cheatsheet.md](cheatsheet.md) — quick reference: decision rules, tables, smells

---

## Scope & Limits

This skill covers the book content only (recipes are synthesized summaries, not the book's text; the full code lives at github.com/terraform-cookbook/recipes). For resource-attribute reference, use the official Terraform docs; combine with project-specific tooling for hands-on work.