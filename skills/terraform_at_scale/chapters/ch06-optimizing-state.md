# Chapter 6: Optimizing State

## Core Idea
State is Terraform's "memory" — a point-in-time JSON tree of what the last apply configured — and every operational disease at scale (locks, drift, gridlock, bloat, team friction) traces back to how states are sized, shaped, and aligned with teams. Optimize for three properties: **balanced state trees**, **state atomicity** (each state is completely ignorant of every other state), and **alignment** of code modules to technical domain and lifecycle. Rebalancing is not optional: org growth, duplication, M&A, and reorgs all demand state surgery via `import` / `state rm`, performed as complete operations across the **state triplet** in a single sitting.

## Frameworks Introduced
- **State Triplet**: the three-way relationship between the codebase, the state object (in the state backend), and the actual running resource instances. Every mutation must reconcile all three legs; importing state only establishes the second leg — the code must match or the next apply deletes it.
- **State Backend → State Object → State Address**: backend = storage location and source of truth (registered at last apply); object = JSON tree (DAG treated as a rooted tree); address = dot-notation path from the root node.
- **State Dos and Don'ts**: the don'ts (one-off operations, `-target` overuse, tightly coupled states, uneven state, too many cooks, ClickOps) concretely cause the failures; the dos are "North Stars" — implementing the dos avoids all the don'ts.
- **Common State Problems taxonomy**: locked, broken, gridlocked, bloated, too many, unbalanced, never-clean states.
- **Five Common Approaches**: backend key variation, distinct variable files (input precedence), graduated environment configuration, versioned environment modules, wildcard jobs.
- **Four Common Scenarios** for state reorganization: organizational scaling (one-to-many split), reducing duplication (flat file → module bundle + state split), merger/acquisition, organizational change management (many-to-many reshuffle). All share the same skeleton: discover → import → confirm no changes → discover → `state rm` → confirm no changes.

## Key Concepts
- **State object**: records only what a `tf apply` configured, only at execution time. It is NOT a source of truth for your cloud estate — only immediately after a successful apply does it reflect reality with near certainty. It has zero awareness of resources codified in other codebases.
- **Graph-theory framing**: resources/data sources are leaf nodes; modules are internal nodes; the applied module is the **root module**. Valid JSON object = tree (cycles disallowed); every tree encodes as JSON — hence dot-notation state addresses.
- **Atomic states**: one apply produces exactly one state object; one state never detects changes made via CLI, console, API, or another state. Any cross-state connection must be built outside the state triplet. Encoding one resource in two states is a "necessary evil" at best.
- **Cascading change**: a `tf apply` in one upstream project requiring a nontrivial apply in a downstream project. Worst case is **mutual interdependency**, which turns the cascade into a cycle requiring an upstream project to be changed twice.
- **Balanced trees quantified**: keep no depth more than `2·log_x(n)` (x = average child branch count across nodes) and the difference between shortest and longest depth ≤ `log_x(n)`; ideally equal volume of child nodes per branch.
- **Breadth over depth**: a high ratio of leaf nodes (resources) to state nodes (module blocks) spends state data on running resources instead of structural metadata. But if an abstraction genuinely improves manageability, don't lament the extra memory.
- **Blast radius**: a broken or locked state's blast radius is the *entire state tree* — keep trees self-contained; use domain-driven chunking to bound size and atomicity.
- **Hot data references**: cross-state references via data blocks duplicate every relevant code change in both states; the balance between many hot data references and a bloated state is the key qualitative indicator of IaC maintainability.
- **Ephemeral environments**: persistent-backend ephemerals allow only one at a time; ephemeral-backend allow any number — a control-versus-flexibility trade-off. Compromise: one fixed ephemeral environment per team with cleanup expectation.
- **Input precedence** (for Approach 2), in order: environment variables → `terraform.tfvars` → `*.auto.tfvars` (lexical order) → `-var`/`-var-file` flags (in command order). Put `-var` last for highest precedence; never mix `.auto.tfvars` with `-var-file`.

## Mental Models
- **State as memory, not truth**: the state object is what TF *remembers*, not what is *real*; drift is the gap between the two and only surfaces when you tell TF to look.
- **The triplet as the unit of work**: never modify one leg alone — a `tf state rm` with unaltered code makes the next apply recreate (and possibly fail on a duplicate). Complete code removal, state removal, and instance destruction "all in the same sitting."
- **Conway's Law for state**: org changes (scaling teams, reorgs, M&A) should drive repository/state boundaries; states aligned to team responsibility remove coordination gates.
- **TF is the wrong tool for one-offs**: "this is like using a screwdriver to pry apart a hammer and using the hammer bits to screw in a nail" — the wrapper software you'd build around TF for non-idempotent ops could instead call the platform API/CLI/SDK directly.
- **Balance as risk containment**: uneven trees mean long, cascading troubleshoot paths and uneven activity distributions signaling unnatural coupling.

## Anti-patterns
- **One-off operations through TF.** Fire-and-forget ops violate idempotence and require costly guardrails (targeting abstractions, temporarily elevated access). Do them with the platform API/CLI instead. If you must, use a wildcard job with an allowlist of operations and a denylist of flags.
- **Overusing `-target`.** Bypassing the full state check to force a change through ignores the very drift that's breaking the state; overuse signals systemic issues needing refactoring, and regular use should be blocked by procedural/access policies. Reserve for emergencies only.
- **Tightly coupled states.** Splitting VPCs from their subnetworks into separate team-owned states makes every VPC add/remove/modify an ordered, cross-team change; mutual interdependency produces apply cycles. Fix: minimize cross-project dependencies, keep upstream changing slower than downstream, and avoid mutual loops.
- **Uneven state, from three specific practices**: (1) mixing `module` and `resource` blocks in the same module (resources are leaves; sibling-module depth is strictly greater — automatic imbalance); (2) mixing module types (complementary unit-bundles vs. onboarding packages invoked together) — hard to enforce with third-party modules; (3) mixing collection (`for_each`d) and non-collection nodes in the same module. Avoid `for_each` outside root modules entirely, with narrow exceptions. Don't fix imbalance with wrapper modules — split the module, possibly into multiple states.
- **Too many cooks.** Multiple teams on one repo plus locked/broken states compounds friction; divergent resource exposure/severity/frequency yields divergent resolution commitment. Fix: formalized knowledge transfer before role moves with strict deprecation and auto-expiring IAM access; formalized small-group refactor activities after reorgs.
- **ClickOps.** The antithesis of IaC: manual changes get reverted by the next apply, ops don't scale, and it concentrates risk on a few specialists' access ("a poor security posture" that undermines the compliance rationale). Mixed IaC+ClickOps costs more than the sum of both. Acceptable only for rapid prototyping / proof of architecture, then rebuild in TF.
- **Never-clean states.** Nondeterministic data sources feeding managed-resource fields break idempotence — even no-op applies compute fake changes. Overloaded-format fields that force replacement cause destroy-then-recreate every apply; fix by constructing the field format to match what the provider records.
- **Gridlocked states.** A failed rollback (e.g., a rollback-protected resource created during a failed apply) blocks every subsequent apply regardless of code state. Only escape: remove the resource another way or remove the code (leaving an untracked resource to later import).
- **Too many states.** Splitting by service type (VMs vs. their firewalls) or by product offering creates coupling and exception sprawl; if you're tracking states in a spreadsheet, you have this problem. Fold states sharing lifecycle/domain back together.
- **Leaving unused/unclean states behind.** Empty-but-persistent state files confuse audits; keeping nonempty stale states is worse. Ensure every surviving state file holds an empty object.
- **`.auto.tfvars` + `-var-file` mixing, and precommit "protection" on `.tfvars`.** Precedence supersedes file protections — a protected file can still be overridden by a later-precedence file. Encode immutable values as `local` values in a `static-locals.tf` (duplicate locals are rejected by TF) and protect that file. Pick one `.tfvars` encoding (HCL or JSON) and stick to it.

## Code Examples
**Backend key variation** — partial backend config completed at `tf init` time, so one repo serves multiple exclusive states:

```hcl
# state.tf — backend fields deliberately left empty
terraform {
  backend "gcs" {
    bucket = ""
    prefix = ""
  }
}

# state.config — passed via: tf init -backend-config=state.config
bucket  = "terraform-at-scale-book"
prefix  = "examples/6-3"
```
**What it demonstrates**: there is no intrinsic repo→backend binding; the `prefix` (GCS; `key` on AWS/Azure) is completed per execution, so each backend key yields a distinct, exclusive state object for parallel environments or per-workload copies. The author recommends storing backend configs in an external secure location (e.g., Vault) and downloading them before `init`. (Equivalent, per-workload pass: `-var-file=./workload/optional.tfvars -var-file=./workload/workload.tfvars` layered after `terraform.tfvars` for common values, with statics as locals in `static-locals.tf`.)

**Duplication refactored into a collection** — dozens of repeated subnet blocks collapse to one:

```hcl
resource "google_compute_network" "tas_6_vpc" {
  name                    = "vpc-terraform-at-scale-6"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "tas_6_snet" {
  for_each = { for snet in var.snet_configs : snet.name => snet }

  name          = each.value.name
  ip_cidr_range = each.value.cidr
  region        = each.value.region
  network       = google_compute_network.tas_6_vpc.id
}

variable "snet_configs" {
  description = "A list of subnet information."
  type = list(object({
    name   = string
    cidr   = string
    region = string
  }))
}
```
**What it demonstrates**: the "after" half of the before/after refactor — repeated near-identical resources plus their per-copy variables become one `for_each` block keyed by a stable name (never an ordering function) and a single typed object list. Pairs with `version = "0.1.0"` remote-module wrapping: applying a patch across all environments reduces to bumping one version string.

## Reference Tables
**Input assignment precedence (lowest → highest):**

| Mechanism | Notes |
|---|---|
| `TF_VAR_` environment variables | First checked, most fragile; use only for team-automation necessities with no default |
| `terraform.tfvars` | Auto-read from the working directory; home of common values (dept code, region, project ID) |
| `*.auto.tfvars` | Lexical order; keep at most one (`overrides.auto.tfvars`) alongside `terraform.tfvars`; never mix with `-var-file` |
| `-var-file` (in command order) | Use whenever var files live elsewhere or there are more than two files; enables structured layering |
| `-var` (after all `-var-file`s) | Highest precedence; hardest to static-analyze |

**Common state problems → causes → mitigation:**

| Problem | Signature cause | Mitigation |
|---|---|---|
| Locked | concurrent writes; aborted apply leaving the lock | Size/organize states so writes never overlap; manual unlock (delete lock file) + triplet reconciliation, with care |
| Broken | `for_each`/`count` misuse (count only for conditionals; never ordering-derived keys), ClickOps reversals, data-resource→managed-resource replacement chains, stale version constraints | Analyze all three triplet legs (state entry, code, provider UI) and correct discrepancies |
| Gridlocked | failed rollback blocked by a protected resource | Remove resource out-of-band or remove its code; import later |
| Bloated | monolithic state; huge plan time for tiny changes (DNS/firewall example) | Domain-driven chunking; breadth over depth; split hot cross-state references vs bloat deliberately |
| Too many | splitting by service type or product offering | Re-stitch by lifecycle/domain; prevention beats cure |
| Unbalanced | long buried module chains; high nesting-to-node cardinality ratio; few fast-changing + many rare resources together | Mindful abstraction, split by activity/lifecycle |
| Never-clean | nondeterministic data sources; overloaded field formats forcing replacement | Constrain data values; match field format to provider's recorded representation |

## Worked Example
**Scenario 1 — organizational scaling (NetSec/NetEng split).** A series-A startup kept all network config in one repo/state with one cross-functional team. Growth produces two owners: **NetSec** (perimeter: external load balancers, DNS zones, baseline DENY rules, VPC Service Controls) and **NetEng** (internal firewalls, routes, subnets for app teams, with some components overridable by app teams). The one-to-many split proceeds: (1) create the NetEng repo; (2) copy over its config; (3) run `tf plan` in the new repo to *discover imports*; (4) `tf import` each resource by the reported address; (5) re-run `tf plan` — **no changes reported** confirms imports; (6) run `tf plan` in the repurposed repo (now NetSec's) to *discover removals*; (7) `tf state rm` each reported resource (or a whole module at once); (8) re-run `tf plan` — **no changes reported** confirms removals. Each team then operates with its own cadence and lifecycle, coordinating loosely in a producer–consumer capacity. The same discover→import→confirm→remove→confirm skeleton recurs across Scenario 2 (flat module-bundle refactor with backend key variation, ending in `tf state rm $(terraform state list)` — always previewed with `-dry-run` first) and Scenario 4 (many-to-many reorg reworking *all* input states in sequence, with a "from→to" address map kept in a shared spreadsheet so nothing goes untracked).

## Key Takeaways
- The state triplet (code, state object, running instances) is the unit of consistency; every import, removal, or move must reconcile all three legs in one sitting, and a clean `tf plan` reporting *no changes* is the only acceptable confirmation of success.
- A state object is a point-in-time memory of one apply — never a source of truth; drift only surfaces on demand, and correction can mean recreation.
- States are atomic and mutually ignorant by default; treat cross-state data references as a maintainability cost you are explicitly accepting.
- Don'ts cluster around violating idempotence (one-offs, `-target` in pipelines, ClickOps) and coupling (tightly coupled states, uneven trees, too many cooks); the dos — balance, environment alignment, domain- and lifecycle-aligned modules, state hygiene — structurally prevent them.
- Keep blast radius small: a broken or locked state affects the whole tree, so chunk by domain to a reasonable size and prefer breadth (leaf-to-state node ratio) over depth.
- Make state-adjacent operations safe by construction: backend key variation for multi-state reuse, layered `.tfvars`/locals for layered config, versioned remote modules for environment graduation, and wildcard jobs (RBAC/ABAC-gated, operator-identified via impersonation, fresh repo clone each run) for surgical state work — so no one ever types into a shell by hand.
- Organizational events (scaling, M&A, reorgs) are expected and manageable: split/merge states with the discovery-based import/removal procedure, run everything through wildcard jobs under temporary permissions, and never walk away mid-procedure.

## Connects To
- Chapter 3 (use `count` only for conditionals; `for_each` with stable, non-ordering-derived keys — cited as the root cause of broken states).
- Chapter 4 (multiple provider configuration blocks — the M&A technique; local-values immutability via `static-locals.tf`; version constraints as a source of broken states).
- Chapter 5 (module types and the no-mixing rules that underpin state balance).
- "Building for Enhanced Maintainability and Balance": Approach 1 extends the backend field into multi-state reuse; Approach 4's remote modules are the mechanism for the environment-aligned-state dos.
- Chapter 7: applies this half of the book to enterprise-scale practice — automation, ephemeral environments, self-service and autohealing platforms.