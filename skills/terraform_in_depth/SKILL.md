---
name: terraform_in_depth
description: "Knowledge base from \"Terraform in Depth: Infrastructure as Code with Terraform and OpenTofu\" by Robert Hafner. Use when applying Hafner's frameworks for Terraform/OpenTofu HCL, modules and input validation, expressions and functions, planning and state management, CI/CD and GitOps for infrastructure, IaC testing and refactoring, or custom provider development."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform in Depth: Infrastructure as Code with Terraform and OpenTofu
**Author**: Robert Hafner | **Pages**: ~505 | **Chapters**: 12 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `state`, `modules`, `for_each`, `terratest`, or another indexed topic; find and read the relevant chapter
- **With chapter** — ask for `ch06`; the specific chapter file is loaded
- **Browse** — ask "what chapters do you have?" to see the full index

When a topic is not covered in Core Frameworks below, read the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

- **Module-as-function** (ch3): inputs = declared arguments, outputs = return values, locals = function-internal vars; only inputs enter, only outputs leave. Type every input — untyped inputs defer errors to provider/runtime.
- **Declarative ordering is inferred, not written** (ch1, ch5): reference an attribute instead of sequencing steps; Terraform builds a DAG — state is a snapshot of the resource graph. Plan output reads bottom-to-top as execution order.
- **Deployment flow** (ch1): Change desired → Init → Plan → Review → Apply; plan has three subphases (Refresh, Compare, Plan). Commit `.terraform.lock.hcl` for reproducible providers; always `plan -out` then apply the *file* so reviewed = executed.
- **State purposes** (ch6): real-world linkage, reduced complexity, performance, state-only resources. Backend requirements: Restrict access, Enable logging, Enable encryption, Configure backups, Configure locking. Local backend is dev-only. Untested backups are worthless.
- **State manipulation hierarchy** (ch6): code (`moved`/`removed` blocks) > CLI (`terraform state` ops) > manual JSON edit (last resort — back up, validate, diff, increment serial). `terraform state pull` a backup before any manipulation.
- **Drift response** (ch6): drift is a symptom of a deeper problem. Detect with `-refresh-only` → ask "what changed and why?" → categorize → codify intentional manual changes before running Terraform again. Machine errors (conflicting automated change, Terraform error) vs human errors (accidental, intentional).
- **Impure functions cause eternal drift** (ch4, ch6): `uuid()`/`timestamp()` in config = workspace out of date the moment you apply. Replace with state-only resources (`random_*`, `time_*`; these persist only in state and bridge locals into `replace_triggered_by`).
- **Three plan modes**: default / destroy / refresh-only (ch5). Plan pitfalls: circular dependencies, cascading changes, hidden dependencies, always-detected changes. `# forces replacement` in output → check the dependency chain or silence with `ignore_changes`.
- **Two-tier review filter** (ch7): machines (fmt, validate, lint, security scan) catch violations at PR; humans catch security, consistency, docs. CI = *regular integration to main*, not "tests before merge."
- **Scanner strategy** (ch7): run Checkov **and** Trivy (incomplete overlap, both free); default to Checkov YAML custom policies; OPA/Rego only if the team already knows Rego. Skip commercial scanners unless already licensed.
- **GitOps four principles** (ch8): Declarative, Versioned & immutable, Pulled automatically, Continuously reconciled ("continuous" ≠ instant). CD triad: CI safety nets + fully automated deployments + small deployments. Environment-as-root: thin wrapper pinning the module's *exact* version so upgrades require a PR.
- **Secret hierarchy** (ch8, ch5): eliminate via OIDC/machine identity → centralize in a secret manager and pass *paths* (values still land in state) → orchestrator settings last resort. Never secrets via `-var`, tfvars, or env.
- **IaC test flow** (ch9): Configure → Launch → Validate → Cleanup; group assertions per configuration. Test logic only, never pass-through attributes. Use `examples/` as tests. Variable renames via expand-and-contract; batch breaking majors ≤1/year, keep `moved` blocks.
- **Testing framework choice** (ch9): native testing framework (`.tftest.hcl`, v1.6+) for new teams/suites; Terratest when supporting a wide version span — native pins you to the lowest version you support. Always `random_string` names + raised timeouts in tests; never skip deletion.
- **Naming scheme** (ch10): names must be Unique, Human readable, Identifiable, Sortable. Root module hardcodes `${application}-${environment}`; each submodule layer appends one descriptor; only a module's primary resource uses `var.name` directly.
- **Provisioners are last resort** (ch10): every provisioner purpose has a better alternative — bake into images, configure at launch with Cloud-Init, use outputs + local provider. Provisioners add failure points, time, and unpredictability.
- **When Terraform isn't appropriate** (ch10): don't manage K8s workloads (use kubectl/Helm/ArgoCD), build container/machine images (slow, tight coupling), or deploy artifacts.
- **Interfaces-first provider design** (ch12): write the user-facing HCL example first, then resources/data sources/functions, then Go. On error, collect all Diagnostics instead of returning early. Never `log.Fatal` in a provider — it can corrupt state. Local dev via `dev_overrides` in `~/.terraformrc`.

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-brief-overview.md) | A brief overview of Terraform | IaC practices, core/providers/vendors stack, deployment flow, declarative vs imperative, OpenTofu/BSL fork |
| [ch02](chapters/ch02-hcl-components.md) | Terraform HCL components | Block anatomy, 12 block types, lifecycle arguments, import/moved/removed, provider aliases |
| [ch03](chapters/ch03-variables-and-modules.md) | Terraform variables and modules | Module-as-function, type constraints, validation blocks, sensitive propagation, module layout |
| [ch04](chapters/ch04-expressions-and-iterations.md) | Expressions and iterations | count/for_each vs for expression, impure functions, templatefile, try/can, dynamic blocks |
| [ch05](chapters/ch05-terraform-plan.md) | The Terraform plan | Resource graph/DAG, three plan modes, four plan pitfalls, variable precedence, -replace cascades |
| [ch06](chapters/ch06-state-management.md) | State management | State purposes, backend requirements, state manipulation hierarchy, drift categories, terraform_remote_state |
| [ch07](chapters/ch07-code-quality-and-ci.md) | Code quality and continuous integration | Two-tier review, quality toolchain (TFLint, Checkov, Trivy), policy tools, CI matrix |
| [ch08](chapters/ch08-continuous-delivery.md) | Continuous delivery and deployment | GitOps principles, semver, project structures, CD platform matrix, secret hierarchy |
| [ch09](chapters/ch09-testing-and-refactoring.md) | Testing and refactoring | IaC test flow, Terratest vs native testing framework, mocks, expand-and-contract refactoring |
| [ch10](chapters/ch10-advanced-topics.md) | Advanced Terraform topics | Naming scheme, network module patterns, provisioner decision matrix, checks, when-not-to-use |
| [ch11](chapters/ch11-alternative-interfaces.md) | Alternative interfaces | Machine-readable UI, JSON output/JSONL streaming, wrapping Terraform, CDKTF, tf.json |
| [ch12](chapters/ch12-terraform-providers.md) | Terraform providers | Plugin Framework, interfaces-first design, Diagnostics, dev_overrides, registry publishing |

## Topic Index

- **backends** → ch1, ch2, ch6, ch8
- **checks and conditions** → ch10
- **CI/CD pipelines** → ch7, ch8
- **count / for_each / for** → ch4, ch5
- **data sources** → ch2, ch3
- **dev_overrides** → ch12
- **drift** → ch6, ch8
- **dynamic blocks** → ch4
- **expressions and functions** → ch4
- **GitOps** → ch8
- **impure functions** → ch4, ch6
- **input variables / validation** → ch3, ch5
- **lifecycle arguments** → ch2, ch10
- **machine-readable output / JSON** → ch11
- **modules** → ch2, ch3, ch8, ch9
- **moved / removed / import blocks** → ch2, ch6, ch9
- **naming scheme** → ch10
- **network management** → ch10
- **plan pitfalls** → ch5
- **plan modes (destroy, refresh-only, speculative)** → ch5, ch7, ch8
- **policy-as-code (OPA, Sentinel, Checkov policies)** → ch7, ch8
- **provisioners** → ch10
- **providers (using)** → ch2, ch11
- **providers (building, Plugin Framework)** → ch12
- **regular expressions / templates** → ch4
- **replace_triggered_by** → ch2, ch4, ch6
- **secrets** → ch3, ch8
- **state** → ch1, ch5, ch6, ch8
- **state-only resources** → ch6
- **tags / tagging strategy** → ch10
- **testing (Terratest, .tftest.hcl, mocks)** → ch9
- **Terraform vs OpenTofu compatibility** → ch1, ch7, ch10
- **taint / force-unlock / deprecations** → ch5, ch6
- **variable precedence** → ch5
- **versioning / semver** → ch8
- **workspaces** → ch1, ch6
- **wrapping Terraform (SDK-less CLI wrapping)** → ch11

## Supporting Files

- [glossary.md](glossary.md) — key terms with definitions
- [patterns.md](patterns.md) — techniques and design patterns
- [cheatsheet.md](cheatsheet.md) — decision rules, thresholds, and tells

---

## Scope & Limits

This skill covers the book content only. For hands-on implementation in your codebase, combine with project-specific tools. For topics beyond this book, check related skills (e.g. `terraform_at_scale` for enterprise-scale organization/state/policy topics) or ask the agent directly.
