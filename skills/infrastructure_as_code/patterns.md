# Patterns & Techniques — Infrastructure as Code (Rosemary Wang)

## Module Patterns (Ch 3)
**When to use**: grouping resources into reusable, testable units.
- **Singleton** — exactly one instance, rarely changed (organizations, billing accounts, base networks). Trade-off: configuration changes here risk the whole system; wrap changes in reliability practices (Ch 9).
- **Composite** — group related resources into a hierarchy managed as one unit (e.g. network = subnets + gateways + routes). Trade-off: convenient automation, but bigger blast radius than small modules.
- **Factory** — inputs in → resource with specific configuration out (e.g. ServerFactoryModule(name, network)). Standardize opinions here; minimize transformations (more logic = more tests).
- **Prototype** — exports static default configuration (tags, labels) without creating resources; used for tagging strategy.
- **Builder** — takes inputs and decides *which* resources to create; can compose factory modules (e.g. DatabaseModule building network + server + load balancer). In IaC tools, builder conditionals map to `count`/conditionals.
- **Factory modules with CRUD functions** — for legacy/tool-less infrastructure, write create/read/update/delete functions per resource; test each for idempotency.

**Choosing**: reach for Factory + Prototype first (lowest effort, most reuse); Builder when resource selection varies by input; Composite for hierarchical grouping; Singleton for one-of-a-kind shared resources.

## Dependency Patterns (Ch 4)
**When to use**: decoupling modules so each can change in isolation.
- **Dependency injection** — the default: high-level resource calls the low-level one and parses its structure for the values it needs.
- **Facade** — expose one or two outputs from a low-level module behind a simplified interface. Start here; effort is minimal but doesn't scale past a few consumers. Prune facade outputs regularly.
- **Adapter** — transforms metadata from one resource/provider into another's format. Best when many high-level modules depend on one low-level module, or across providers. Highest effort, best scalability and change isolation.
- **Mediator** — organizes dependencies among many modules and decides create/update order. Most IaC tools (Terraform's dependency graph) implement this — prefer the tool's built-in mediator over hand-rolling one.
- **Abstraction scope rule**: variable/attribute interpolation intra-module; module outputs between modules; tool state or provider API across tools or teams.
- **Unidirectional relationships**: keep dependencies one-way (high-level → low-level); watch for circular dependencies between high-level resources.

## Writing & Hygiene (Ch 2)
**When to use**: every file, every commit.
- Parametrize everything; decide variable vs. constant by security/impact, not frequency.
- Secrets: reference a secrets manager; never inline. Lint + format in CI.
- Naming: `<environment>-<type>-<purpose>`; commit messages explain *why*.
- Brownfield migration: inventory → choose base infrastructure first (accounts → networks → compute → orchestration → deployments → queues → DNS/LB/firewalls → alerts → SaaS) → import/greenfield per component.

## Testing (Ch 6)
**When to use**: before merging any change.
- **Infrastructure testing cycle**: define config → static analysis (lint, policy) → apply → dynamic analysis (tests against running infra).
- **Unit tests**: module outputs, naming, tagging, secret-handling — run in seconds, no cloud.
- **Contract tests**: verify a module's exposed interface (outputs stay stable for consumers).
- **Integration tests**: apply modules/config to a testing environment; use create-and-delete for high-level modules and in-place updates on persistent environments for low-level (network/DNS).
- **End-to-end + smoke + continuous (monitoring) tests**: verify the deployed system.
- Filter for useful tests: do these tests tell me whether the system works? Do they run reliably enough?

## Delivery & Branching (Ch 7)
**When to use**: scaling the team.
- Map change type to delivery: standard/emergency → continuous deployment (tests only, commit-message bypass allowed for emergencies with audit); new/major → continuous delivery with manual approval.
- **Trunk-based** for small teams comfortable with small changes; **feature-based** for larger teams, riskier environments, or slower release cadence. Apply to production frequently — small changes, small blast radius.

## Security & Compliance (Ch 8)
**When to use**: every pipeline.
- 4-item security checklist: least privilege, protect secrets, tag everything, policy as code.
- Enforcement levels: hard mandatory (pre-production block), soft mandatory (manual exception review), advisory (async report).
- Expect 5–6 policy engines in a mature posture; keep policy tests in a shared repository.

## Making Changes (Ch 9)
**When to use**: significant production changes.
- **Blue-green deployment** (5 steps: deploy green → point high-level dependencies at green → canary → regression window → delete blue). Use when rollback is slow/uncertain, dependencies are unmappable, or downtime is unacceptable; skip for quickly reversible changes (IAM, tags).
- **Canary**: start ~10% traffic, regression window between increments, reach 100%, hold 1–2 weeks.
- **Stateful infrastructure migration**: write-both → write-green → read-green → delete-blue; migration automation lives in the pipeline, not the IaC.
- Plan-level compliance test: assert the plan contains no `delete` on critical resources.

## Refactoring (Ch 10)
**When to use**: breaking up monolithic configurations.
- Refactor in dependency order: independent high-level first, dependent high-level next, low-level last.
- Workflow per resource group: copy to new module → `terraform import` → verify zero-change dry run → `terraform state rm` from the monolith (state removal = ownership handover).
- Gate risky refactors with feature flags (default off, removed after) or rolling updates.

## Fixing Failures (Ch 11)
**When to use**: production is broken.
- Stabilize first, diagnose second. Repair order: roll forward the revert → reconcile drift → fix environment differences → re-implement the original change with least privilege.
- Troubleshooting checklist: check drift → check unexpected dependencies → check differences between environments (a prod-only failure that passed testing almost always means the environments differ).

## Cost (Ch 12)
**When to use**: every quarter — and in tests.
- Automate cost estimation from IaC (billing catalog × usage, 730-hour months) as a soft-mandatory assertion; budget tests guide, they don't hard-block.
- Cut waste: stop untagged/unused, schedule start/stop, right-size/spot, autoscale with a capped max, expiration tags, on-demand environments, co-located data transfer.

## Managing Tools (Ch 13)
**When to use**: adopting/upgrading/replacing tooling.
- Assess open source: functionality → security (no secret output, no third-party endpoints, passes your compliance tests) → life cycle (active maintainers, license; pin + mirror internally).
- Upgrade: ≤2 versions per jump through backward-compatible steps; in-place if backward compatible or scripted; breaking changes → new folder/state (blue-green tool state), low-level resources first.
- Event-driven IaC: module runtime must outpace event frequency; GitOps is the subset whose event is drift.