# Chapter 8: Evolving Projects Into Enterprise

## Core Idea
Every TF adoption converges on the same failure mode: a single root module accretes components until the team drowns in merge conflicts, locked states, and elaborate review procedures — or the panic moment arrives around a major release or sensitive-data exposure. The author's prescription: track the split-indicating signals from day one (even informally, quarterly), socialize the *inevitable* deconstruction with stakeholders early so it is neither deprioritized nor budgeted out, and refactor deliberately rather than haphazardly — a panicked split "almost certainly results in an even more tumultuous ordeal." The end state should be root modules aligned to the organization's responsibility hierarchy, per Melvin Conway, better supporting the org's real communication channels. Crucially: because TF state can absorb resources via import, you can radically restructure code *without provisioning new cloud resources*, drastically reducing risk.

## Frameworks Introduced
- **Signals for Change** — indicator taxonomy grouped by measurability, reviewed quarterly and escalated when trending upward (see Key Concepts).
- **Evolutionary Patterns** — three named refactoring patterns; "the best approach is a strategic combination," and never default to a pattern merely out of familiarity:
  1. **Building on Top of Base Infrastructure** — greenfield project established atop existing infrastructure. Ideal for new platforms/stacks; works smoothly only if the prior environment is already well componentized and layered.
  2. **Strangler Fig** — ported from the classic monolith-to-services pattern, broken into layers/domains. Most appropriate when breaking down a single project into **more than two** TF projects; each domain identified, prioritized, with a dedicated validation exercise so the team gives each new project full focus.
  3. **State Reproduction Swap** — when no existing project is expected to survive a reorg (e.g., imposing a domain hierarchy on a flat sprawl, or an M&A). Create a fully greenfield code setup, establish parallel backends, `tf import` the existing resources, and validate: exact same inputs must produce the same outputs up to state addresses. Fix that as a basic acceptance criterion, then optimize KPIs freely.
- **M&A: Combine vs. Absorb** — two consolidation scenarios: one ecosystem absorbing the other (most common, straightforward) vs. cherry-picking elements from both (extremely hard unless done as a *third, somewhat greenfield* ecosystem; in practice a hybrid — one ecosystem designated the foundation, slowly incorporating chosen tools). Always evaluate **both** codebases with representatives from both sides, and reorganize each to aligned layers/domains *before* combining to de-risk the merge.
- **Change Management for Infrastructure Support** — four end configurations (see Anti-patterns/Key Concepts): centralized domain-oriented teams; centralized + distributed project-oriented teams; diminished-central with autonomous regional support + product-embedded engineers; center of excellence.
- **CSP Migration Reality Note** — a wholesale CSP-to-CSP migration is never a flip of a switch; it resembles the "extending to another CSP" effort plus it.

## Key Concepts
- **Measurable, easy-to-track indicators** (per single root module/state, both `.tf` and `.tfvars*` files):
  - Lines of code — arbitrary alone; combined with resource count, expresses growth/sprawl and emergent domains.
  - Number of resources (total tracked by one state).
  - Number of child modules at root — cross-referenced with activity levels to expose incongruent lifecycles.
  - Frequency and aggregate duration of **locked-state delays** — state locking is a valuable fail-safe, but with multiple teams contributing it points to a glaring need to split one project per team; apply queues break down when an apply dies ungracefully and the lock isn't released.
  - Number of distinct operating teams — if >1: split projects by team, shift responsibility to one team, or combine the teams.
- **Evident factors**: mergers and acquisitions; transitioning from on-prem to a CSP (new architecture, relinquished appliance control — "an identity crisis in the culture of your technology business unit"); extending to another CSP; adopting a new infrastructure or data platform (greenfield ops mechanism, dependencies codified via workflow triggers); significant disproportional expansion of a state branch (an emergent domain deserving its own project).
- **Indirect/subjective indicators**: dependency graph shape; non-normalized development activity (long tails — where action concentrates vs. goes inert); frequency of merge conflicts (especially between two distinct teams); material cost of making an update (labor + consumption + subscriptions); team velocity (downward trend = growing cost of change); engineer stress/burnout and attrition.
- **Multi-team resolution logic**: if teams must remain distinct and responsibilities intact → split into correspondingly distinct projects. To consolidate responsibility into one team → establish a request system so previously responsible teams stay accountable for constructing/maintaining. Partially shared engineers may be the most effective friction reducer.
- **Strangler Fig caveats**: unique resource attributes (CSP identifiers) complicate coexistence — establish naming conventions combining non-unique fields (name + locality + tags) into a unique identity, with a mechanism verifying the combination. Validation differs from microservices: cloud services allow coarse-grained, direct resource-attribute comparison rather than driving traffic through the whole system.
- **State Reproduction Swap validation mechanics**: custom outputs for all resources; compare with `tf output` / `tf state list`; KPIs also on dependency tightness (tight = deterministic rigidity, loose = autonomy), lifecycle separation, access-permission separation, and end-to-end change time.
- **Outside help rule**: consultants and contract teams must never be silos — embed internal members, shuffle internal members into third-party teams when there are cross-divide dependencies, but let the contract team otherwise behave independently with reporting/monitoring for line of sight. Treat internal review of their work as a **certification exercise** on a regular schedule (not just offboarding), so drift is caught early.
- **Support-team configuration guidance**: whichever model, the team *accountable* for infrastructure must be the one *implementing* it via TF — embed TF engineers in domain teams or have teams answer directly to them. A **center of excellence** can be a distributed tap-in of individuals rather than a centralized group, but it demands real buy-in: scheduled meetings/workshops, dedicated documentation assets, accessible repositories, and even internal conferences with travel.

## Mental Models
- **Conway alignment as the goal** — refactoring root modules is ultimately about matching TF structure to the org's responsibility hierarchy and communication channels (cited twice: for the general journey and for post-acquisition influence of Company B's channels reshaping Company A's systems).
- **Signals as a tracked ledger, not a fire alarm** — start recording from adoption, review quarterly (e.g., rough aggregates of merge conflicts and approval friction), and escalate only when trends bend upward. Include the future-split caveat in the IaC adoption conversation itself.
- **State as the risk-neutralizer** — for both Strangler Fig and State Reproduction Swap, the leap is the same: don't recreate infrastructure; import it. The new codebase operates the identical resources, and plan/apply output becomes the validation surface. "Resources with identical attributes... will operate in largely the same way" makes refactoring far more verifiable than rewriting application logic.
- **Vibe coding meets TF** — TF is unusually compatible with code generation because "TF itself is the OS binary" merely interpreting structured input: as long as code looks consistent, it will likely be interpreted correctly. Risk shifts to duplicates clashing with existing resources — so move scrutiny to the **plan phase**, ensure identity-producing fields are computed in advance (not at apply) and are available to validate for uniqueness, and use system prompts to enforce book conventions (logic in `locals{}`, all important info in outputs, no inline interpolation, no untyped variables, validation on complex variables).
- **Warped Pareto Principle of vibe coding** — 80%+ of the work can land in ~1% of the time, which implies the remaining 20% takes 99%: use generators for prototyping and sweeping changes, do small/simple changes by hand (also token-budget rationing), and always refactor generated code for human intelligibility since you may lose the generator (licensing or security posture).
- **Dormant institutional risk** — post-consolidation, the most insidious issues "lie dormant for months and are deeply seeded in complex, esoteric institutional rationale," so keep redundant responsibilities staffed early, train rather than cut (including management/business education), and never reduce personnel before friction is smoothed.
- **Stabilize before the next systemic change** — after a big integration, teams need time to converge on a working velocity; otherwise no failure can be attributed to the correct change.

## Anti-patterns
- **Multiple teams operating one TF project** — competing interests produce merge conflicts and disproportional activity; the fix is structural (split, consolidate, or merge teams), not procedural.
- **Haphazard, panicked deconstruction** — splitting without time, exposure, and stakeholder visibility "almost certainly results in an even more tumultuous ordeal."
- **Reverting after a well-intentioned split** — new structure brings new friction (more hands on levers, more stakeholders); the urge to revert causes churn; instead fix friction points as they arise, with sustained decision-maker buy-in.
- **Letting a preferred pattern become a default** — "develop a preference for a specific one" or reusing previously successful techniques out of familiarity; estimate two or more approaches for how each scales.
- **Accountability/implementation split** — a team accountable for infrastructure it cannot implement via TF; always embed or answer directly to domain teams.
- **Siloing consultants or contract teams** — isolates institutional knowledge, forces redundant discovery, and blocks buy-in; equally, over-tethering contract teams to internal direction destroys their autonomy.
- **Accepting contractor output without scrutiny** — parallels Chapter 7's unscrutinized AI-agent caution; review both code and resulting resources.
- **Constructing future infrastructure too early in an acquisition** — workloads will change or die during the multi-wave migration; placeholder components become waste. Initiate support components "soon before they become necessary" as a preliminary step per workload.
- **Skipping the POC/pilot and rolling straight out** — running the real integration in the true ecosystem without a sandboxed probe trades short speed for unknown snags surfacing at scale.
- **Forgetting teardown** — cloud resources stick around; make a tear-down step part of the acceptance criteria of any validation exercise (and of POCs explicitly).
- **Rotating rollout leadership** — different people leading different rollouts kills momentum and re-invites previously overcome impediments; keep the same person/small group across the whole effort.
- **Uncommunicated deprecation** — silently removing old services becomes corporate whack-a-mole as uninformed stakeholders escalate complaints; socialize deprecation across multiple channels and give deleted workloads a dated removal.

## Code Examples
Example 8-1 — small-scale web-based product as a single TF project (excerpt, GCP):

```hcl
resource "google_compute_network" "main" {
  name                    = "main-vpc"
  auto_create_subnetworks = false
}

resource "google_vpc_access_connector" "serverless" {
  name          = "app-serverless-conn"
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = var.serverless_cidr
}

resource "google_sql_database_instance" "main" {
  name             = "main-db"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-custom-1-3840"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }
  }
}
```
**What it demonstrates**: the pre-split starting point — networks, App Engine, and private Cloud SQL bound into one root module — which later gets segmented into domains and split per environment (the author's "expanding from a web app to an entire organization" case study).

Example 8-2 — expanding the project to additional environments via var files:

```hcl
# Example execution: tf plan -var-file=environments/dev.tfvars
# dev.tfvars
project_id      = "tas-8-2-dev"
subnet_cidr     = "10.10.0.0/16"
serverless_cidr = "10.8.0.0/28"
db_name         = "appdb-dev"

# Example execution: tf plan -var-file=environments/prod.tfvars
# prod.tfvars
project_id      = "tas-8-2-prod"
subnet_cidr     = "10.10.0.0/16"  # CIDRs can be the same in dev and prod
serverless_cidr = "10.8.0.0/28"
db_name         = "appdb-prod"
```
**What it demonstrates**: the first multi-environment step — one root module parameterized per environment through var files (dev/prod can reuse CIDRs because isolation comes from the project), before infrastructure is segmented into separate projects per domain.

## Reference Tables
- **Points of contention when combining two peer ecosystems** (Company C vs. Company D): Network intrusion (layered IDS/DMZ edge inspection + trust/untrust vs. total-block IPS with a more direct path — each side may view the other as risky); Compute runtime (serverless managed scaling vs. managed Kubernetes — note serverless ultimately rides containers, and cloud-native is more portable); Overlapping database solutions (align by licensing, externalize solution-specific features as services); Automation platform (GitHub Actions vs. GitLab — differences in parallel steps and process integration force eventual consolidation); Open source posture (legal decides, engineering de-risks — e.g., Rocky Linux in place of RHEL for nonproduction to save per-node licensing); Preferred CSP (missing or subtly non-like-for-like analog services cause lingering resentment).
- **Data-solution hallmarks** (Tip box): flat data joined by common identifier → relational (MySQL/PostgreSQL/Cloud SQL); hierarchical JSON-like structure → NoSQL, or middleware denormalizing into relational; big single-key blobs (images/video/media) → document/managed storage bucket.

## Worked Example
**Absorbing an acquired software ecosystem (Companies A and B).** Setup: A absorbs B; A has the larger codebase, more modern ecosystem, and mature processes — so A's ecosystem absorbs B's. A runs container-based platforms (simplifying rehost: any OS becomes a container image), B uses a different CSP, and integration proceeds workload-by-workload. The recommended 11-step approach: (1) optional POC — A personnel embed part-time into a stable, low-update B team/workload, in isolation, with teardown in the acceptance criteria; (2) construct infrastructure for the first round of production-ready workloads; (3) pilot the happy path — record what worked, produce assets; (4) roll out to all team-workload combinations resembling the pilot (phased by team); (5) assess, officially deprecate via multiple channels, then tear down after an appropriate dwell; (6) build infrastructure for the next workload class; (7) pilot a harder migration with a representative stable workload; (8) roll out that class (more aggressive now, managed by a dedicated role); (9) assess, deprecate, delete; (10) repeat 6–9 per remaining class; (11) stabilize before any further systemic change. Sequencing rules surfaced along the way: don't build all of B's infrastructure up front (workloads move or die mid-effort); the pilot validates on early preproduction environments before later ones exist; keep one leader across all rollouts; give an internal counterpart explicit authority to cut red tape for external help. Outcome: a single ecosystem resembling A's, achieved "on the order of one year," after which top-down team consolidation and Conway-effects from B's communication channels reshape the combined company's systems.

## Key Takeaways
- Track split-indicating signals from day one — even roughly — and bake the eventual-split caveat into IaC adoption conversations; a smooth split is earned by early stakeholder exposure, not discovered in a crisis.
- Escalate on trends, not noise: quarterly review of measurable indicators (LOC, resource count, child modules, locked-state delay frequency and duration, team count) plus subjective ones (merge conflicts, cost-per-change, velocity, attrition).
- Know the three patterns and when each fits: greenfield atop existing base (new platforms), Strangler Fig (>2 resulting projects, one validated domain at a time), State Reproduction Swap (nothing survives; import everything, validate identical outputs as acceptance criteria).
- TF state makes radical code refactors low-risk: import existing resources so plan/apply validates the new structure without provisioning anything.
- For multiple teams on one project, the decision is structural: split per team, consolidate via request system, or merge teams — don't layer process on a shared state.
- In M&A, always evaluate both codebases with both sides present, realign each to matching layers/domains before combining, and prefer absorb-over-cherry-pick (or a deliberate third greenfield ecosystem) unless evidence favors otherwise.
- Organize support so accountable teams implement their infrastructure in TF; a distributed center of excellence is often better than a centralized gate.
- When hiring help, embed internal members for knowledge transfer and line of sight, but grant contract teams autonomy plus robust reporting — and certify their output on a schedule.
- Migrate in POC → pilot → rollout-by-class waves, deprecate loudly, delete on a dated schedule, and stabilize between systemic changes; keep the same rollout leader throughout.

## Connects To
- **Chapter 7** (environments and delivery): repeatedly referenced — multi-environment expansion, ephemeral environments, chaos-test environments, workflow-trigger dependencies between workspaces, and the AI-agent scrutiny caveat.
- **Chapter 9** (Organization Structures and Policy Constraints): the next chapter drills into management hierarchy, written and unwritten policy traditions, regulatory constraints, hierarchical network controls and topologies, access control policies, and third-party tooling access.
- **Melvin Conway** (org-structure thesis): the recurring yardstick for whether a post-refactor root module layout actually fits the organization.