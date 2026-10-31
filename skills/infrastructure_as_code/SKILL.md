---
name: infrastructure_as_code
description: "Knowledge base from \"Infrastructure as Code: Patterns and Practices with Examples in Python and Terraform\" by Rosemary Wang. Use when applying Wang's frameworks for IaC principles (RICE), module and dependency patterns, structuring/sharing modules, infrastructure testing, continuous delivery for infrastructure, security and compliance as code, blue-green/canary changes, refactoring and fixing infrastructure, cloud cost management, and IaC tool management."
---

<!-- argument-hint: [topic, framework/pattern name, or chapter number] -->

# Infrastructure as Code: Patterns and Practices with Examples in Python and Terraform
**Author**: Rosemary Wang | **Pages**: ~402 | **Chapters**: 13 | **Generated**: 2026-10-30

## How to Use This Skill

- **Without arguments** — load core frameworks for reference
- **With a topic** — ask about `drift`, `blue-green deployment`, `module patterns`, `policy as code`, or another indexed topic; I find and read the relevant chapter
- **With a chapter** — ask for `ch06`; I load that specific chapter
- **Browse** — ask "what chapters do you have?" to see the full index

When you ask about a topic not covered in Core Frameworks below, I will read
the relevant chapter file before answering.

---

## Core Frameworks & Mental Models

### RICE — the four IaC principles (Ch 1)
Wang's mnemonic for auditing whether code deserves the label "infrastructure as code":
- **Reproducibility** — the same configuration reproduces the environment. Minimize **configuration drift** (deviation between version control and actual state). If you must fix something, fix it in code, not the console.
- **Idempotency** — stricter than "repeatable": running automation again yields the *same end state* without side effects on the resource.
- **Composability** — assemble any combination of resources and update each without affecting the others. Build with modules as building blocks.
- **Evolvability** — the configuration accommodates growth; don't optimize too early or unnecessarily.

### Infrastructure is software — the toolchain life cycle (Ch 1)
IaC applies DevOps practices (version control, CI/CD, code as documentation) to infrastructure. Tools form a pipeline: **configuration management** (Ansible, Chef, Puppet) → **image building** (Packer) → **provisioning** (Terraform). Provisioning is the spine; prefer declarative over imperative tools.

### Module patterns — five GoF-inspired patterns (Ch 3)
- **Singleton**: one instance of rarely changed, shared infrastructure (organizations, base networks). Risk: it's the highest blast radius config in the system.
- **Composite**: group resources into a hierarchy managed as one unit.
- **Factory**: inputs in → resource with specific configuration out. Standardize opinions here.
- **Prototype**: exports static defaults (tags, labels), creates no resources.
- **Builder**: decides *which* resources to create; composes factory modules.
Decision tree: multiple resources? → Builder or Composite; one resource from inputs → Factory; static defaults → Prototype; one-of kind, rarely changed → Singleton. Start with Factory + Prototype — lowest effort, most reuse. Keep modules small: fewer resources = faster provisioning, smaller blast radius.

### Dependency patterns — decoupling modules (Ch 4)
Core principle stack: **inversion of control** (the high-level resource calls the low-level one for attributes) + **dependency inversion** (use an abstraction of low-level metadata) = **dependency injection** (parse the low-level resource's object structure).
Escalate abstraction as the system grows, by shape:
- **Facade** — simplified interface over one low-level module serving a few high-level consumers. Lowest effort; doesn't scale. Start with 1–2 outputs and prune regularly.
- **Adapter** — transforms metadata between formats; best for many high-level dependents or cross-provider resources. Highest effort; best scalability and change isolation.
- **Mediator** — orchestrates dependencies among many modules; most IaC tools (Terraform's graph) already do this — prefer the tool's built-in mediator.
Abstraction scope: variable interpolation intra-module · module outputs between modules · tool state or provider API across tools.

### Test in the infrastructure testing cycle (Ch 6)
Define config → **static analysis** (lint, policy) → apply → **dynamic analysis** (tests against running infra). Pyramid: many **unit** tests (module outputs, naming, secrets — seconds, no cloud) → **contract** tests (the module's output interface stays stable) → **integration** tests (apply to a testing environment) → **end-to-end/smoke**. Strategy by pattern: factory/builder/prototype modules get unit→contract→integration; configuration (environments) gets unit→integration→e2e. Low-level modules (network, DNS): persistent environment, test in-place updates. High-level: create-and-delete. Filter: do these tests tell me whether the system works? Do they run reliably?

### Continuous delivery for infrastructure, branching, GitOps (Ch 7)
Map **change type** to delivery: standard/emergency → continuous deployment (tests are the gate; emergencies get a commit-message bypass with audit); new/major → continuous delivery with manual approval. Branching: **trunk-based** = merge small changes to main several times a day (small blast radius); **feature-based** when team size, risk, or release cadence demands review-heavy flow. Peer review asks: is it correct, secure, reproducible? GitOps: version control as source of truth; automation reacts to commits and drift (Ch 13) — GitOps is a subset of event-driven IaC whose event is drift.

### Security & compliance as code (Ch 8)
Four-item delivery-pipeline checklist: least privilege (role factory modules), protect secrets (secrets manager, never in version control or state), tag everything (service/team + team email + environment), **policy as code** (compliance tests run against IaC before apply). Enforcement levels: **hard mandatory** (block pre-production), **soft mandatory** (manual exception review), **advisory** (async). No single policy engine covers everything — plan for 5–6 (OPA, Sentinel, CFN Guard, InSpec, Kyverno...). Policy tests live in a shared repository.

### Making significant changes (Ch 9)
Pre-change checklist, then pick deployment pattern by reversibility: **blue-green** (deploy green → repoint high-level dependencies → canary → regression window → delete blue) when rollback is slow/uncertain, dependencies unmappable, or downtime unacceptable; **skip** blue-green for quickly reversible changes (IAM, tags). **Canary**: ~10% initial traffic, regression window between increments, hold 100% for 1–2 weeks; load-balance traffic weights in a separate config (known-good default). **Stateful infrastructure**: write-both → write-green → read-green → delete-blue; migration automation lives in the pipeline, not the IaC. Guard with a plan-level compliance test asserting no `delete` on critical resources.

### Refactor, fix, cost, tools (Ch 10–13)
- **Refactoring (Ch 10)**: order = independent high-level → dependent high-level → low-level. Per group: copy → `terraform import` → verify zero-change dry run → `terraform state rm` (ownership handover). Stage with feature flags (default off) or rolling updates.
- **Fixing failures (Ch 11)**: stabilize first, diagnose second. **Rolling forward** = deploy a new working state (immutability means rollback doesn't exist). Repair order: revert via git → reconcile drift → fix environment differences → re-implement the change with least privilege. Prod-only failure despite passing tests = environments differ.
- **Cost (Ch 12)**: tag and break down the bill before optimizing. Automate **cost estimation** (billing catalog × usage, 730-hr month) as soft-mandatory tests — they guide, never hard-block. Cut waste: stop untagged/unused (confirm first), schedule start/stop, right-size/spot, cap autoscaling max, expiration tags (pipeline run = lease renewal), on-demand environments, co-locate data transfer.
- **Managing tools (Ch 13)**: assess open source → functionality, then security make-or-break (no secret output, no third-party endpoints, passes compliance in isolation), then life cycle (active maintainers, license; pin and mirror internally). Upgrade ≤2 versions at a time via backward-compatible steps; breaking changes → new folder = new tool state (blue-green for tools), low-level resources first.

---

## Chapter Index

| # | Title | Key Frameworks |
|---|-------|----------------|
| [ch01](chapters/ch01-introducing-infrastructure-as-code.md) | Introducing infrastructure as code | RICE principles, CAMS, tool life cycle, blast radius, drift |
| [ch02](chapters/ch02-writing-infrastructure-as-code.md) | Writing infrastructure as code | Immutability, brownfield migration, code hygiene, secrets |
| [ch03](chapters/ch03-patterns-for-infrastructure-modules.md) | Patterns for infrastructure modules | Singleton, Composite, Factory, Prototype, Builder |
| [ch04](chapters/ch04-patterns-for-infrastructure-dependencies.md) | Patterns for infrastructure dependencies | Dependency injection, Facade, Adapter, Mediator |
| [ch05](chapters/ch05-structuring-and-sharing-modules.md) | Structuring and sharing modules | Repo structures, semantic versioning, releasing, opinionated defaults |
| [ch06](chapters/ch06-testing.md) | Testing | Testing cycle, test pyramid, unit/contract/integration/e2e |
| [ch07](chapters/ch07-continuous-delivery-and-branching-models.md) | Continuous delivery and branching models | CI/CD for IaC, trunk-based vs feature-based, GitOps |
| [ch08](chapters/ch08-security-and-compliance.md) | Security and compliance | Least privilege, tagging strategy, policy as code, enforcement levels |
| [ch09](chapters/ch09-making-changes.md) | Making changes | Blue-green deployment, canary, stateful migration |
| [ch10](chapters/ch10-refactoring.md) | Refactoring | Monolith breakdown, state import/removal, feature flags, rolling updates |
| [ch11](chapters/ch11-fixing-failures.md) | Fixing failures | Rolling forward, troubleshooting checklist, drift reconciliation |
| [ch12](chapters/ch12-cost-of-cloud-computing.md) | Cost of cloud computing | Cost drivers, cost estimation, cloud waste reduction |
| [ch13](chapters/ch13-managing-tools.md) | Managing tools | Open source assessment, upgrade checklist, event-driven IaC |

## Topic Index

- **adapter pattern** → ch04
- **blue-green deployment** → ch09, ch13
- **blast radius** → ch01, ch03, ch04, ch09, ch10
- **branching models** → ch07
- **brownfield migration** → ch02
- **builder pattern** → ch03
- **canary deployment** → ch09
- **composability** → ch01, ch03, ch04
- **configuration drift** → ch01, ch02, ch06, ch11
- **continuous delivery/deployment** → ch07
- **cost estimation** → ch12
- **dependency injection / inversion** → ch04, ch10
- **dry run / terraform plan** → ch01, ch06, ch09, ch10, ch12
- **event-driven IaC** → ch13
- **facade pattern** → ch04
- **factory module** → ch03
- **feature flags** → ch10
- **feature-based vs trunk-based development** → ch07
- **GitOps** → ch07, ch13
- **idempotency** → ch01, ch03, ch06, ch10
- **least privilege** → ch08, ch11
- **mediator pattern** → ch04
- **module versioning / pinning** → ch05, ch13
- **monorepo vs multi-repo** → ch05
- **policy as code / policy engines** → ch08
- **prototype pattern** → ch03, ch08
- **refactoring IaC / monolith breakdown** → ch10
- **repositories / repo structure** → ch05
- **rolling forward** → ch11
- **rolling update** → ch10, ch13
- **RICE principles** → ch01
- **secrets / secrets manager** → ch02, ch08
- **semantic versioning** → ch05
- **singleton pattern** → ch03, ch09
- **state import / state removal** → ch10
- **static vs dynamic analysis** → ch06, ch08
- **tagging strategy** → ch08, ch12
- **test pyramid / testing types** → ch06
- **tool upgrades / tool replacement** → ch13
- **versioning** → ch05

## Supporting Files

- [glossary.md](glossary.md) — all key terms with definitions
- [patterns.md](patterns.md) — all techniques and design patterns
- [cheatsheet.md](cheatsheet.md) — quick reference tables and decision guides

---

## Scope & Limits

This skill covers the book content only. For hands-on implementation in your codebase,
combine with project-specific tools. For topics beyond this book, check related skills
or ask the agent directly.