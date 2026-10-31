# Cheatsheet — Infrastructure as Code (Rosemary Wang)

Decision rules and thresholds. Chapters in ( ).

## The Four IaC Principles — RICE (Ch 1)
Audit anything claiming to be IaC with four questions:
| Principle | Ask |
|---|---|
| Reproducibility | Can this same configuration recreate the environment from scratch? |
| Idempotency | What happens if I rerun it right now? Same end state, no side effects? |
| Composability | Can I mix and match this with other modules and update one without breaking others? |
| Evolvability | Can it grow/scale without rewriting or breaking other systems? |

## Module & Dependency Pattern Selection
**Choosing a module pattern (Ch 3):** One instance, rarely changes → **Singleton**. Grouping into hierarchy → **Composite**. Configure one resource type from inputs → **Factory**. Static defaults (tags/labels), creates nothing → **Prototype**. Decides *which* resources to create → **Builder**. Start with Factory + Prototype.

**Choosing a dependency pattern (Ch 4):** Depends on relationship shape —
| Shape | Pattern |
|---|---|
| One low-level → few high-level consumers | Facade (start with 1–2 outputs) |
| Many high-level depend on one low-level, or cross-provider | Adapter |
| Dependencies among many modules/tools | Mediator (prefer the tool's built-in one) |
Effort/scale trade-off: facade = lowest effort, doesn't scale · adapter = highest effort, best scalability + isolation.

**Modularize when answers differ** (Ch 3): shared? business domain? environment? team? tool? must change independently? → separate module. Keep modules small (fewer resources = faster provisioning, smaller blast radius).

**Change type → delivery approach** (Ch 7):
| Change | Approach | Manual approval? |
|---|---|---|
| Standard | Continuous deployment | No (tests are the gate) |
| Emergency | Continuous deployment + commit-message bypass | Post-hoc audit |
| New / major | Continuous delivery | Yes (CAB) |

**Branching model** (Ch 7): trunk-based if small changes merge several times a day; feature-based if team size, release cadence, or environment risk demands it.

## Hygiene Rules (Ch 2, 8)
- Variable vs. constant: decide by security and impact, not frequency — prefer constants.
- Secrets: always from a secrets manager, passed as variables. Never in version control, never in tool state.
- Name `<environment>-<type>-<purpose>`; commit messages state *why*.
- Least privilege via role factory modules; authoritative IAM bindings over member bindings.
- Tags minimum: service/team + team email + environment (dash-case, within provider limits).
- Policy enforcement: hard mandatory pre-production · soft mandatory via exception review · advisory async. Expect 5–6 policy engines, not one.

## Change Management Thresholds (Ch 9, 10, 11)
- **Blue-green when**: rollback is slow/uncertain, dependencies unmappable, or downtime unacceptable. **Skip when**: change is quickly reversible (IAM, tags).
- **Canary**: default ~10% initial traffic; hold regression window between increments; hold 100% for 1–2 weeks.
- **Feature flags**: default off; remove after the change lands.
- **Refactoring order**: independent high-level first → dependent high-level → low-level last. Per group: copy → import → verify zero-change dry run → `state rm`.
- **Failure repair order**: roll forward the revert → reconcile drift → fix environment differences → re-do original change (least privilege). Stabilize first, diagnose second.
- A prod-only failure that passed testing = the environments differ.
- Plan-level guard: assert the plan contains no `delete` on critical resources.

## Cost Rules (Ch 12)
- Break the bill down by tag/service/environment before optimizing anything.
- Budget/cost tests: soft mandatory — guide decisions, never hard-block production.
- 730-hour month when estimating. Cap autoscaling max. Pipeline run = expiration-tag lease renewal.
- Confirm metrics + dependencies before deleting "unused" resources — never delete untagged resources immediately.
- Favor co-located / private networking; data transfer is a hidden driver.

## Tool Management (Ch 13)
- Security make-or-break for open source: no secret output, no third-party endpoints, passes compliance tests in isolation.
- Upgrade ≤2 versions at a time, through backward-compatible steps; pin tools, plugins, and modules; mirror internally.
- Breaking tool changes → new folder = new tool state (blue-green), low-level resources first; import-capable replacement if the tool supports import.

## Tells & Smells
- Ran `terraform apply` twice and got different results → not idempotent.
- Console change you can't see in version control → drift; fix it in code.
- Manual steps every deployment → automate next, not someday.
- Everything in one config + one state file → monolith; plan the Ch 10 refactor.
- Reference to "latest" module version → pin the tag.