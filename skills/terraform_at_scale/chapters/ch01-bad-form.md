# Chapter 1: Bad 'Form!

## Core Idea
Before teaching how to write TF (the book's collective shorthand for Terraform and OpenTofu), establish *when*, *why*, and *what to avoid* — a deliberate echo of Crockford's *JavaScript: The Good Parts*. The opening scenario is the book's motivating nightmare: an organization runs TF successfully for months or years, then no one can push a change — automation jobs fail or report unexpected drift, all feature work is blocked, and after days of swarming the fix turns out to be a single line of configuration nobody remembers ("Oh, yeah, here's the commit where it was removed..."). The book's stated goal is practices that lead toward success and away from frustration, not a set of "industry best practices" — the author suspects **IaC is more of an art than a science** and there are few genuinely "best" practices in all situations.

The book's cardinal refrain, repeated throughout: **don't mix TF with other processes.** Its corollary: *nearly anything you do outside of TF to resources maintained by TF is technical debt*, because the modification must be reconciled in TF before the project can progress. If the only outcome is that the organization never manually edits TF-managed resources (CLI or browser console), the author considers the book a total success.

## Frameworks Introduced
- **The Good Parts framing**: distinguish concepts *unique(ish) to IaC*, concepts *borrowed* from general software (with shifted implications), and concepts *irrelevant or diminished* in IaC. Use the third list to push back when software-world instincts get applied to TF.
- **Concept triage for IaC** (irrelevant/diminished): no entry point or main function (commands target a directory, and TF derives ordering itself in plan), performance (invest in IAM, automation, and abstractions first — but dozens-of-minutes jobs mean something is wrong, e.g., tutorial constraints applied to real environments or bloated state), unit testing (HCL is a configuration language, not your code; prefer **custom validation expressions**; TF testing framework tests are secondary), integration testing (only live values truly verify; dummy-value test environments can still hide name collisions and cost far more than they return).
- **Technical IaC Debt lifecycle**: Nightmare Scenarios → Paying It Down → The Real Cost. Treat technical debt as an **existential threat** warranting consistent proactive *mitigation* — not a boogeyman, and not something requiring draconian pay-off-everything obsession.
- **Strangler-pattern-inspired migration** for TF: unlike modernizing a monolith into microservices, you go from one monolithic configuration to another — scaffolding out the updated organization of resources piece by piece and filling in the new, initially sparse structure (Chapters 6–7).

## Key Concepts
Unique(ish) to IaC:
- **Idempotency**: an applied configuration element is unchanged by subsequent `tf apply` runs. This is what lets TF detect drift or rebuild deleted/tainted components without recreating everything else.
- **TF plan**: a two-step workflow (plan, then apply). The plan is essentially immutable once constructed, "similar to a shell script" that runs start to finish in ordered fashion. Auto-approving plans is decidedly not recommended.
- **Stored state**: IaC has *three* components — the code, the execution, and the point-in-time state at execution. `tf apply` records changes in a JSON-encoded state file.
- **Backend**: the user-designated remote location (e.g., AWS S3) where the state file is stored.
- **Locked state**: a state lock prevents concurrent applies and race conditions; a forcibly cancelled `tf apply` leaves the project locked and effectively disabled until someone with permission releases it.
- **Provider vs CSP** (naming convention used book-wide): *CSP* is the platform hosting running resources (AWS, GCP); *provider* is the software TF uses to turn HCL into API calls against that CSP.
- Plan caveats: a `tf plan` will not ordinarily detect existing resources, may not expose CSP-limit violations like name/ID collisions, and many different HCL constructions can produce the identical execution plan.

Borrowed concepts with shifted implications:
- **Encapsulation**: modules are TF's encapsulation mechanism; a module is just a directory of `.tf` files referenced by CLI target or `source` meta-argument, so "module development is largely an exercise in effective source control."
- **Resource management**: the more components a project maintains, the larger the state object — cumbersome to traverse, potentially exhausting the CSP's API call limits, and a wider blast radius. Conversely, many small projects need scaling governance or suffer execution queues.
- **IAM**: TF itself needs a digital identity in each CSP it services; pair with access policies on the source control repositories to form a secured supply chain.
- **Standards and style**: HCL is strict in syntax but lenient on whitespace and ignores configuration order within/between blocks, so it enforces nothing — a consistent style standard (cf. Martin's *Clean Code*) is on you.

Features every scale-out project uses: **variables** (module inputs, with `description`, `type`, custom validation), **output values** (pass computed attributes out of a module, readable apply logs), **local values** (intermediary logic, complex data shapes for resource/module fields), **data sources** (fetch external resource data during plan; verify dependencies maintained outside this project), **modules** (primary encapsulation, nestable, directly targetable).

## Mental Models
- **Three-component model**: code + execution + state (unlike ordinary software's code + execution). Every IaC reasoning puzzle starts from the third component.
- **"TF will provision what you tell it to"** — a gift and a curse: it enables separation of concerns, but it is the root of every misconception below. Use it as the one-sentence answer to "why didn't Terraform catch this?"
- **Plan as execution script**: the plan is an immutable, ordered procedure, not a suggestion. If plan output reports a change, TF will try to execute it — which is exactly why never-clean builds are costly.
- **Debt triage by cadence**: (1) low-impact-but-obvious debt — fix immediately as it pops up; (2) steady-drip refactoring — long-form initiatives or scheduled after-N-sprints passes (e.g., collapse near-identical services into one `for_each` resource, bundle shared resources into a remotely developed module and migrate teams on a timeline); (3) wholesale replacement — reserved for out-of-hand repetition or bureaucratic redesigns, where the strangler approach and state manipulation come in.
- **Cost accounting beyond the ticket**: technical debt's real cost = technical fix time + solutions-architect/stakeholder review time (not a rubber stamp) + purely bureaucratic negotiation (meetings, timelines, budgets, team assignments). Plus silent accrual: muscle memory conditioned by 1,000+ line files breeds less active thought and costlier oversights.

## Anti-patterns
- **Mixing TF with other processes** (manual console or CLI edits to TF-managed resources): any such edit becomes debt the next `tf plan` will try to revert — the 4 p.m. Friday nightmare where an emergency fix for resource B reverts resource A, and staying late damages morale. Only discipline (absent tooling and policies) prevents it.
- **Auto-accepting plans**: the plan describes exactly what apply will do; skipping its review forfeits the tool's main safety mechanism.
- **Expecting TF to monitor/drift-correct**: the executable does not constantly inspect running services; drift detection and alerts are a product feature of HCP Terraform/TFE, not core TF.
- **Expecting TF to know your existing infrastructure**: it won't seek out other resources to detect name collisions or dependency implications.
- **Expecting TF to fill security gaps**: it cannot assess overexposed permissions or permissive firewalls. Note the inversion — security scanners often hand *you* HCL snippets; introduce them strategically, never paste them at the bottom of a random `.tf` file.
- **Expecting TF to roll encryption keys / manage time-bound secrets**: no time-limit tracking; use a purpose-built solution, not IaC.
- **Expecting TF to abstract away CSP differences**: providers are CSP-specific; VPC implementations across the big three diverge widely — multicloud migration is not copy/paste + find/replace of resource names.
- **`count` for N copies of a resource**: the only appropriate use of `count` is with a **ternary returning 0 or 1** to conditionally include a single resource. Reason: removing an item from a `count` list forces recreation of everything after it — only `tf state`/`tf import` surgery fixes it without recreation. The same trap hides in other convoluted iteration logic.
- **Test-coverage metrics for TF code**: unit/integration testing typical configuration has little value and the "real offender to engineering effort is test coverage" targets. Don't campaign against it either (lonely uphill battle); if asked for Terratest, comply — you'll at least grow Go experience.
- **Never-clean projects left unchecked**: a field-format mismatch (e.g., a subnetwork field accepting ID or URL at write time, but the CSP returning one canonical format on read) makes every plan report a change that no-ops on apply — and humans/automation follow through with unnecessary applies, wasting time and on-demand compute while breaking drift validation.
- **Tightly coupled projects**: two or more TF projects that change together; each update is a nuisance but the accrual eats budget contingency and morale. Spend the time to decouple.
- **Local terminal/shell operations past project infancy**: early on engineers run CSP and TF commands in shells; as projects mature this should fall out of favor and be disallowed in favor of task automation.

## Reference Tables

Concept triage:

| Bucket | Concepts |
|---|---|
| Unique(ish) to IaC | Idempotency, tf plan (two-step), stored state, backend, locked state, provider |
| Borrowed, shifted implications | Encapsulation (modules), resource management (state size vs. many projects), IAM (TF's digital identity + repo policies), standards/style |
| Irrelevant or diminished | Entry point/main function, performance optimization, unit testing, integration testing |

Basic toolchain roles:

| Role | Notes |
|---|---|
| Code editor | Edit HCL and related configuration |
| Terminal/shell | CLI + SCM commands; early-stage TF/CSP commands only |
| Source control | Git is "most recommended" purely for interoperability/market share |
| Task automation | Establish early; see OpenTofu vs HCP Terraform split below |
| CSP | One true root account per provider; view access to operate, elevated access only for local applies |

OpenTofu vs HCP Terraform/TFE:

| Aspect | HCP Terraform / TFE | OpenTofu |
|---|---|---|
| Task automation | Central web interface runs plan/apply | Repurpose your app-delivery platform; it must authenticate to the CSP and be authorized to administer resources |
| Workspace management | Built-in: same module, different input variables, common backend | Build your own; use workspaces only when environments vary little — significant variation (dev vs prod breadth/capacity) calls for other approaches (Chapters 7, 9) |

Book convention: a **TF project** = a TF module (filesystem directory) targeted by a TF command; treat it as synonymous with "workspace" except where workspace-specific considerations apply.

## Worked Example
**The never-clean project (field-identifier drift).** A subnetwork resource takes a VPC reference, and the provider accepts multiple identifier formats (`name`, `id`, generated URL) when the plan is first constructed. But on query, the CSP returns one specific format — so every subsequent plan reports a change to that field, which produces an update-in-plan but a **no-op apply** (the resource doesn't actually change). The project therefore *always* reports changes: every genuine change and every automated operator run triggers an unnecessary `tf apply`, wasting time and compute and undermining the never-clean build's usefulness as a drift detector.

The fix is one line: **use the exact format the `tf plan` output reports.** The chapter's lesson is the debt triage: this is a low-impact, obvious debt — address it the moment it pops up rather than letting the project run never-clean indefinitely, because never-clean builds "may hinder or complicate simple validation techniques for detecting drift or confirming updates" — precisely the mechanism behind the chapter's opening blocked-release nightmare.

## Key Takeaways
- The book's shorthand: **TF = Terraform + OpenTofu**; CLI rendered as `tf plan` / `tf apply` / `tf import`. Nearly all its concepts and techniques apply to both.
- Anchor every design decision in the three-component model: code, execution, state. State size, backend, and lock behavior drive chapters 7+.
- The supreme rule: don't mix TF with other processes. Any out-of-band change to TF-managed resources is debt owed back to TF.
- Pre-empt the six misconceptions nonpracticing architects bring: TF does not monitor/drift-correct, know your existing infrastructure, fill security gaps, roll keys, stop foolishness, or abstract CSP differences.
- Use `count` only with a 0-or-1 ternary; use `for_each` when you need many instances.
- Skip unit/integration testing of typical HCL; invest in validation via custom validation expressions first, TF testing framework second.
- Triage technical debt into fix-now / steady-drip / wholesale-replace, and prefer the strangler-pattern migration over big-bang rewrites when downtime is impossible.
- Treat technical debt's full cost as technical + review + bureaucratic, and treat its silent accrual (never-clean builds, tightly coupled projects) as compounding.
- Stand up the basic toolchain early — especially task automation — and retire local shell operations as the project matures.

## Connects To
- **Chapter 2** (Input Variables): type safety, input validation, and balancing consistency with maintainability — deep-dive on the "variables" feature introduced here.
- **Chapters 4 and 6**: local values and output values in effective use; the strangler-pattern module refactor explored in Chapter 6.
- **Chapter 7**: the debt-paydown epicenter — state manipulation with `tf state`/`tf import`, the wildcard job for stuck locks, backend recovery after state destruction, and the tooling/policies that enforce "no manual changes."
- **Chapters 3 and 6**: sensible abstractions (including the `count`/`for_each` guidance in Chapter 3) to apply before optimizing performance.
- **Chapter 9 / 10 / 12**: task automation pipelines, programmatic operation of TF, IAM, and the policy-based access controls that prevent backend deletion.
- **Chapter 11**: "don't run your company's environments using constraints you found in a tutorial" — real-world-vs-tutorial missteps.