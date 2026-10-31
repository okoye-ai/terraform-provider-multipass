---
name: terraform_introduction
description: "Knowledge base from \"Introduction to Terraform\" by Bobby Iliev. Use when applying Iliev's frameworks for Terraform fundamentals (providers, resources, HCL), state management and backends, modules, Terraform Cloud, import of existing infrastructure, CI/CD pipelines, secrets with Vault, Sentinel compliance, Ansible integration, serverless/Kubernetes provisioning, and troubleshooting."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Introduction to Terraform
**Author**: Bobby Iliev | **Pages**: ~126 | **Chapters**: 21 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `state locking`, `import`, `modules`, `Sentinel`, or another indexed topic; I find and read the relevant chapter
- **With chapter** — ask for `ch06`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

- **Declarative desired state**: you describe *what* you want (`resource` blocks); Terraform figures out the *how*. Contrast with procedural tools like Ansible — when writing configs, never encode steps, encode end states. (ch02)
- **The imperative loop**: `terraform init → plan → apply (→ destroy)`. `plan` is always the review gate before real infrastructure changes; in CI it becomes `plan -out=tfplan` applied explicitly. (ch04, ch16)
- **State as the map of reality**: `terraform.tfstate` maps code to real resources; answer "what exists, what are its attributes, what depends on it" from state. Rule: never manually edit it; keep it remote + locked for any team use. (ch06, ch12)
- **Remote state upgrade**: local state only for solo testing. Team/production → backend (S3, GCS, Terraform Cloud) with locking + versioning. (ch06, ch12)
- **Module-as-function**: inputs (variables) → resources → outputs. Extract anything reused; standard layout `main.tf` / `variables.tf` / `outputs.tf`, version-pinned via Git tags, sources from local path, Git hosts, or the Registry. (ch07)
- **Providers as API bridges**: one provider block per platform; resources addressable as `<provider>_<resource>.<name>`; multiple providers in one config wire attributes across clouds (e.g. droplet IP → Route53 record). (ch04, ch13)
- **Environment-as-input**: one config, many environments — `.tfvars` per environment selected with `-var-file`, plus conditionals (`environment == "production" ? t3.large : t3.micro`) and a `count = cond ? 1 : 0` existence toggle. Keep repetition out with `locals` and `dynamic` blocks. (ch09, ch10)
- **Secrets never in plaintext**: input variables with runtime values or a secrets manager (Vault provider + `vault_generic_secret` data source). State can contain sensitive attributes — encrypt at rest and in transit. (ch09, ch17, ch18)
- **Import protocol**: adopting existing resources = write the config block first, then `terraform import <address> <id>`. For non-importable resources: transition to a new managed resource (safer) vs recreate (only when identity can't move, e.g. fixed IP). (ch11)
- **Sentinel policy-as-code bouncer**: Sentinel rules inspect `tfplan` and block non-compliant runs before apply — e.g. the mandatory-Environment-tag policy. (ch17)
- **Terraform provisions, Ansible configures**: bridge with provisioners — `local-exec` to run playbooks from your machine against the new host (wire `ipv4_address` into the inventory), `remote-exec` for self-configuration. (ch20)
- **Testing ladder**: `validate` (syntax) → `plan` (preview) → Terratest for full infrastructure tests; pin Terraform versions in CI and cache plugins for constrained environments. (ch21)

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-iac-foundations.md) | Introduction to IaC | IaC recipe model, tool landscape (Terraform/Ansible/Chef/Puppet) |
| [ch02](chapters/ch02-introduction-to-terraform.md) | Introduction to Terraform | Declarative state, immutable infra, masterless, TFC vs OSS |
| [ch03](chapters/ch03-installation-and-setup.md) | Installation and Setup | Install-per-OS table, install→verify ritual |
| [ch04](chapters/ch04-terraform-basics.md) | Terraform Basics | Providers, resources & addressing, init/plan/apply/destroy |
| [ch05](chapters/ch05-hcl-configuration-language.md) | HCL Basics | Blocks, arguments, variables & outputs |
| [ch06](chapters/ch06-terraform-state.md) | Terraform State | State mapping, local vs remote, locking, backend block |
| [ch07](chapters/ch07-modules.md) | Modules | Module-as-function, sources, versioning, standard layout |
| [ch08](chapters/ch08-terraform-cloud.md) | Terraform Cloud | Workspace workflow, TFC vs OSS decision, Sentinel/registry |
| [ch09](chapters/ch09-best-practices.md) | Best Practices | Canonical layout, naming, tfvars-per-environment, secret hygiene, fmt/lint |
| [ch10](chapters/ch10-intermediate-language-features.md) | Intermediate Language Features | Functions table, dynamic blocks, conditionals, locals worked example |
| [ch11](chapters/ch11-importing-infrastructure.md) | Importing Infrastructure | Import protocol, non-importable decision tree, state export |
| [ch12](chapters/ch12-advanced-state-management.md) | Advanced State Management | Versioning, conflict locking, corruption triad, state import/export |
| [ch13](chapters/ch13-multiple-providers.md) | Multiple Providers | Multi-provider blocks, cross-provider wiring, use cases |
| [ch14](chapters/ch14-serverless.md) | Serverless | Lambda+IAM pairing, GCP/Azure function stacks |
| [ch15](chapters/ch15-container-orchestration.md) | Container Orchestration | K8s provider objects, DOKS clusters, version slugs |
| [ch16](chapters/ch16-ci-cd.md) | CI/CD | Jenkins stages, GitHub Actions workflow, saved plan / auto-approve |
| [ch17](chapters/ch17-security-compliance.md) | Security & Compliance | Vault data sources, Sentinel tag policy, compliance as code |
| [ch18](chapters/ch18-secrets-with-vault.md) | Secrets with Vault | Provider config, write/read/consume secret loop |
| [ch19](chapters/ch19-troubleshooting-debugging.md) | Troubleshooting | TF_LOG recipe, debug ladder, common-error playbook |
| [ch20](chapters/ch20-terraform-with-ansible.md) | Terraform with Ansible | Provisioners, local-exec vs remote-exec, division of roles |
| [ch21](chapters/ch21-advanced-topics-conclusion.md) | Advanced Topics | Testing ladder, multi-cloud, plugin cache |

## Topic Index

- **Ansible integration / provisioners** → ch20
- **Backend / remote state** → ch06, ch12
- **CI/CD (Jenkins, GitHub Actions)** → ch16
- **Conditional expressions** → ch10
- **Debugging / logging (TF_LOG, console)** → ch19
- **Dynamic blocks** → ch10
- **Functions (length, concat, join, format...)** → ch10
- **HCL syntax (blocks, arguments, comments)** → ch05
- **Import / existing infrastructure** → ch11
- **Installation** → ch03
- **IaC concepts & tool comparison** → ch01, ch02
- **Kubernetes / DOKS** → ch15
- **Lambda / serverless (AWS, GCP, Azure)** → ch14
- **Locals** → ch10
- **Modules** → ch07, ch09
- **Multiple providers / multi-cloud** → ch13, ch21
- **Outputs** → ch05
- **Policy as code / Sentinel** → ch17
- **Providers / resources** → ch04
- **Secrets management** → ch09, ch17, ch18
- **Sentinel** → ch17
- **State (locking, versioning, conflicts, export)** → ch06, ch12
- **Terraform Cloud** → ch08
- **`.tfvars` / environments** → ch09
- **Variables** → ch05, ch09
- **Vault** → ch18

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions and chapter refs
- [patterns.md](patterns.md) — all concrete techniques with when/how/trade-offs
- [cheatsheet.md](cheatsheet.md) — lifecycle loop, decision rules, error→fix table

---

## Scope & Limits

This skill covers the book content only. For hands-on implementation in your codebase,
combine with project-specific tools. For topics beyond this book, check related skills
or ask the agent directly.