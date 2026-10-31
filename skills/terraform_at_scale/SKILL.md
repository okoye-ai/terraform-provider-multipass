---
name: terraform_at_scale
description: "Knowledge base from \"Terraform at Scale: Patterns, Practices, and Pitfalls of Enterprise Terraform and OpenTofu Development\" by Robert Glenn (O'Reilly, 2026). Use when applying Glenn's frameworks for Terraform/OpenTofu at enterprise scale: state architecture and splitting, modules and distribution, input variables and validation, automation platforms, org structure and policy/IAM, validation at scale, and recovery/migration patterns."
---

<!-- argument-hint: [topic, framework name, or chapter number] -->

# Terraform at Scale
**Author**: Robert Glenn | **Pages**: ~500 | **Chapters**: 12 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `for_each`, `state splitting`, `IAM bindings`, `modules`, or any indexed topic; I find and read the relevant chapter before answering
- **With chapter** — ask for `ch06`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

**The book's collective shorthand: "TF" = Terraform + OpenTofu.** The book covers both as one practice, split from the perspective of running them at enterprise scale.

- **Three-component model of IaC** — code + execution + **point-in-time stored state**. State is TF's distinguishing third component and its unit of truth: valid only immediately after a successful apply. The **State Triplet** (codebase, state object in backend, running instances) must be closed as a whole in any remediation. *(ch01, ch06, ch12)*

- **Plan-then-apply duality** — tf plan is essentially immutable per run but blind: it won't detect pre-existing resources and may miss name/ID collisions. Anything applied to TF-managed resources outside TF is technical debt; don't mix TF with other provisioning processes. *(ch01)*

- **for_each-Over-Count Rule** — all iteration goes through `for_each`; `count` exists only for the conditional-block pattern `count = condition ? 1 : 0`. Count-index reordering causes wholesale recreation; state addresses embed `each.key`, which is why for_each keys must be primitive-unique. *(ch04)*

- **Implicit-First Dependency Rule** — prefer reference attributes over `depends_on`; gratuitous depends_on risks evaluation cycles. Only make hidden dependencies explicit. *(ch04)*

- **Balanced-state math** — states aligned by domain and lifecycle (Conway's Law), breadth over depth, depth ≤ 2·log_x(n). Split heuristics: distinct operating teams, resource lifecycle divergence, long-running validation queues. The **State Reproduction Swap** and **Strangler Fig** patterns handle monolith breaking; the import→confirm→state rm→confirm skeleton reconciles the triplet without provisioning. *(ch06, ch08)*

- **Modules as Protected Interfaces** — nested vs. nesting vs. leaf/logic modules, gated by **Mismatching Frequencies of Code Changes** and **Unbalanced Resource Relationships** tests. Distribute internally via Git (for humans) + private registry (for the automation identity only); SemVer with a deprecation formula (≥6-month deprecation, max 3 versions, up to 2 supported). *(ch05)*

- **Validation as defense-in-depth** — `validation{}` (plan-time), `precondition{}` (plan-or-apply), `postcondition{}` (apply-only): variable validation > precondition; resource postcondition > output precondition. Encode the Pareto-most-costly failures as issues escape; `can()` only in validation, `try()` only around the risky sub-expression. *(ch03, ch10)*

- **Seven classes of validation at scale** — internal I/O, data sources, static analysis, behavior analysis (tf test, Terratest), externalized I/O, CSP auditing, TF-driven checks against the state triplet. Govern custom controls (3 gap types + 2 relaxation types) in a core repo + long-running fork. *(ch10)*

- **Organizational policy is policy-as-code's twin** — SRP binding rule ("responsible to one, and only one, group of stakeholders"); IAM union semantics vs. firewall intersection semantics ("Deny always wins"); authoritative vs. nonauthoritative bindings never mixed in one state; defense-in-depth's 7 layers with diminishing returns. *(ch09)*

- **Automating at enterprise scale** — low-tier shell-script pipelines → primary platform (RBAC/ABAC, pipeline DSL) → self-service infrastructure (~80% Pareto coverage) → supervised autonomous IaC. **Wildcard jobs** (GHA/GitLab only) are the governed escape hatch; **State of States** gives org-wide provenance; ephemeral environments enforce livestock thinking. *(ch07)*

- **Forever Forward** — TF has no rollback. Recovery writes a new corrective change forward: `git revert`-style inverse commits, `tf state mv`/`import`/`rm` followed by no-change plans. Time-to-replace, not time-to-remediate, is the KPI (livestock, not pets). *(ch11)*

- **Local Equilibrium & MVI** — success is a moving local state of low friction, full coverage, fast incident response, and forecasted budget; Minimum Viable Infrastructure keeps the Build-Measure-Learn loop alive. Maturity models (CMM/OMM-based, CNMM verticals) measure — never indict. *(ch12)*

- **Common Misconceptions to carry forever** — TF does not monitor drift, discover existing infra, fill security gaps, roll keys, prevent foolishness, or abstract CSP differences. *(ch01)*

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-bad-form.md) | Bad 'Form! | Three-component model, concept triage, Common Misconceptions, technical-IaC-debt framework |
| [ch02](chapters/ch02-input-variables.md) | Input Variables | Seven ways to set variables, variable{} fields, unity element pattern, validation as defense-in-depth, type() workflow |
| [ch03](chapters/ch03-effective-use-of-logic.md) | Effective Use of Logic | Three-locus balance, Messy Middle, for-expressions, can()/try() split, function disposition table |
| [ch04](chapters/ch04-built-in-fields.md) | Built-In Fields | Implicit-First Dependency Rule, for_each state addresses, field-order standard, lifecycle{} selection, removed{} |
| [ch05](chapters/ch05-developing-modules.md) | Developing Modules | Module taxonomy, bundled solutions, SemVer distribution, deprecation formula, logic modules |
| [ch06](chapters/ch06-optimizing-state.md) | Optimizing State | State Triplet, balanced-state math, five approaches, four scenarios, input precedence ladder |
| [ch07](chapters/ch07-automating-at-enterprise-scale.md) | Automating at Enterprise Scale | Three-tier practices ladder, wildcard jobs, State of States, ephemeral environments, autonomous IaC |
| [ch08](chapters/ch08-evolving-projects-into-enterprise.md) | Evolving Projects Into Enterprise | Signals for Change, Strangler Fig, State Reproduction Swap, M&A patterns, vibe-coding TF |
| [ch09](chapters/ch09-org-structures-and-policy.md) | Organization Structures and Policy Constraints | SRP bindings, IAM semantics, defense in depth, four network edges, HIPAA/GDPR/Zero Trust patterns |
| [ch10](chapters/ch10-validating-at-scale.md) | Validating at Scale | Eight validation categories, block precedence convention, Terratest/tf test, policy logic modules |
| [ch11](chapters/ch11-forever-forward.md) | Forever Forward | Forward-only recovery, livestock KPI, everything-is-production, merge strategies, module extraction |
| [ch12](chapters/ch12-last-thoughts.md) | Last Thoughts | Local Equilibrium, MVI loop, TF maturity model, splitting heuristics, TF vs. alternatives |

## Topic Index

- **`any` type / type scaffolding** → ch02
- **Automation platforms (GHA/GitLab/TFE/HCP)** → ch07
- **Backend configuration / key variation** → ch06
- **Balanced states / state math** → ch06
- **`count` vs `for_each`** → ch04, ch11
- **Debt (technical IaC debt)** → ch01, ch06
- **depends_on vs implicit references** → ch04
- **Drift / never-clean plans** → ch01, ch06
- **Ephemeral environments** → ch07, ch11
- **Forever Forward recovery** → ch11
- **Git branching / merge strategy for TF** → ch11
- **HIPAA / GDPR / Zero Trust** → ch09
- **IAM bindings (authoritative/nonauthoritative)** → ch09
- **Locals** → ch04, ch02
- **Maturity models (CMM, CNMM)** → ch12
- **Mergers & acquisitions / ecosystem migration** → ch06, ch08
- **Meteorite / Logic modules** → ch05, ch10
- **MVI / Minimum Viable Infrastructure** → ch12
- **Modules: nested / leaf / logic / bundled** → ch05
- **`namespace` / field-order standard** → ch04
- **Policy constraints / SRP** → ch09
- **Preventative Measures (reviews, static analysis, hooks)** → ch10, ch11
- **`regexall` / `try` / `can`** → ch03, ch10
- **Self-service infrastructure** → ch07
- **SemVer / module versioning / deprecation** → ch05
- **State splitting / project splitting** → ch06, ch08, ch12
- **State Triplet** → ch06, ch12
- **Strangler Fig / State Reproduction Swap** → ch08
- **Terratest / tf test** → ch10
- **Validation blocks (validation/precondition/postcondition)** → ch02, ch10
- **Variables: type constructors, defaults, sensitive/ephemeral** → ch02
- **Vibe coding / AI-generated TF** → ch07, ch08
- **Wildcard jobs** → ch06, ch07, ch11

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — all techniques and design patterns
- [cheatsheet.md](cheatsheet.md) — quick reference decision rules and tables

---

## Scope & Limits

This skill covers the book content only. For hands-on implementation in your codebase,
combine with project-specific tools. For topics beyond this book, check related skills
or ask the agent directly. 39 source images (figures/screenshots) were not read.
Note: the Index section of the print book was not included in extraction.