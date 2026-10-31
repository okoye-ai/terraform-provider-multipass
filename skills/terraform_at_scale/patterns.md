# Patterns & Techniques — Terraform at Scale (Robert Glenn)

Format: **When to use** / **How** / **Trade-offs**. Chapter anchors in parentheses.

## Count-Ternary Conditional
**When to use**: You need zero-or-one of a resource/block based on a condition.
**How**: `count = condition ? 1 : 0` (unity element pattern: ternary evaluates to 0 or 1, never N).
**Trade-offs**: Singularity may be merely current-requirements-based (Ch 11) — a resource that could later replicate per project/region is better served by `for_each` with an empty collection for 0. The small overengineering price beats state surgery later. (Ch 2, 4, 11)

## for_each-Over-Count Rule
**When to use**: All N-way iteration, always.
**How**: Prefer `for_each` with a primitive-keyed set/map; where the value comes from a module output, reshape it into a unique-keyed map via a for expression first.
**Trade-offs**: Slightly more setup than `count`; in exchange, state addresses stay stable (`each.key` embedded), avoiding destructive index reordering. Place `for_each` in the outer module for stack replication, at the resource block for a fixed set plus a variable number of one type. (Ch 4, 6, 11)

## Implicit-First Dependency (no gratuitous depends_on)
**When to use**: Any two resources with a data dependency.
**How**: Reference the upstream attribute directly (e.g. `google_compute_network.vpc.name`); reserve `depends_on` for true hidden dependencies.
**Trade-offs**: Explicit-but-unnecessary `depends_on` risks evaluation cycles and obscures the real data flow. (Ch 4)

## Locals as Unwound Composition Chains
**When to use**: Complex expressions, third-party module output restructuring, composite-variable complexity.
**How**: Flatten composite inputs into named locals instead of passing verbatim structures; alias local values when upstream names are overlong; keep a `locals/` dir per the extended standard module structure.
**Trade-offs**: More lines of code, but self-documenting and reusable; never pseudo-hardcode via variable `default` — use locals. (Ch 2, 4, 5)

## Validation as Defense-in-Depth
**When to use**: Any variable that feeds policy-sensitive or format-sensitive fields.
**How**: `validation{}` (plan-phase gate) with `condition` + crafted `error_message` (why+what, link internal policy pages). Encode the Pareto-most-common failures first as issues escape; build complex composite conditions iteratively.
**Trade-offs**: Full coverage is unaffordable; validation{} is checked only at plan time — pair with precondition/postcondition for apply-time guarantees. (Ch 2, 10)

## One-Shot Big-Bang Nested-Module Refactor
**When to use**: A nested-module structure no longer serves changing requirements.
**How**: Perform the refactor in one prioritized sweep — put `for_each` in the outer module, not the nested — then validate against imported state.
**Trade-offs**: Concentrated risk vs. incremental strangler extraction for monoliths that need >2 resulting projects (Ch 5, 8)

## Strangler Fig State Migration
**When to use**: Breaking a monolithic TF project into multiple projects.
**How**: One domain extraction at a time: discover → `tf import` into new parallel backend → confirm → `tf state rm` (with `-dry-run`) → confirm → verify no-change plan. Solve unique-identifier collisions with composite naming conventions.
**Trade-offs**: Slow but risk-neutralized; imports refactor code without provisioning new resources. (Ch 6, 8)

## Backend Key Variation (environment separation)
**When to use**: Separating environments without duplicating code.
**How**: Parameterize the backend key per environment; feed values via `.tfvars` following the input precedence ladder; protect immutable values in a `static-locals.tf` (not protected .tfvars).
**Trade-offs**: Lightweight vs. versioned environment modules / graduated environment configuration for stronger separation. (Ch 6)

## State Triplet Reconciliation (import/confirm/remove skeleton)
**When to use**: Any remediation that touches resources, code, or state.
**How**: Close all three legs (codebase, state object, running instances): `tf import` + confirm, edit code, `tf state rm -dry-run` + confirm, verify a no-change plan.
**Trade-offs**: Deliberate ceremony — skipping a leg leaves a half-reconciled triplet that surfaces later as drift or surprise destroys. (Ch 6)

## Wildcard Jobs
**When to use**: State surgery, environment validation, and escape hatches that need free-form command execution with the platform service identity.
**How**: Protected, temporary, approved jobs in the automation platform (GHA/GitLab); operator impersonation + fresh clone.
**Trade-offs**: Powerful and auditable but not supported in TFE/HCP Terraform; must be RBAC/ABAC-gated and temporary. (Ch 6, 7, 11)

## Ephemeral Environments
**When to use**: Validating risky changes and any dev/test work at scale.
**How**: On-demand build with mandatory expiry tagging; validate non-singleton changes by temporarily introducing them in a nonproduction environment via wildcard job, then clean up through the workflow. Never assume anything passed in dev passes in prod.
**Trade-offs**: Cost of builds vs. security/cost risk of long-lived sandboxes; teardown speed is a requirement, not a nicety. (Ch 7, 11)

## Logic-Module Policy Enforcement
**When to use**: Enforcing naming/labeling/input standards through code rather than review discipline.
**How**: Input-only logic modules (and output-only variants) that wrap policy as code; quarantine fragile values like timestamps in a logic module. Avoid modules that read resource attributes — that creates circular dependencies.
**Trade-offs**: Slight indirection vs. consistent, testable enforcement. (Ch 5, 10)

## SemVer Module Distribution
**When to use**: Publishing internal remote modules.
**How**: Distribute via Git + private registry dual-channel (automation identity reads registry only); SemVer with prerelease/build metadata; Git tags/branches as release channels; deprecation schedule: deprecated ≥ 6 months, max three available versions, up to two supported.
**Trade-offs**: Version-management overhead vs. uncontrolled drift from Git-sourced internal modules (anti-pattern). (Ch 5)

## State of States + Domino Automation
**When to use**: Org-wide visibility and cascading change control.
**How**: Registry of projects/states tied to stable tagged Git commits and pipeline outputs; dependency tracking that graduates spreadsheet → relational DB → automated cascading triggers (GHA reusable workflows / GitLab trigger).
**Trade-offs**: Automation of cascades amplifies good structure and bad structure alike. (Ch 7)

## Tool-Migration Parity Check
**When to use**: Swapping static-analysis/policy tools (e.g. moving between TFLint/OPA/Checkov/Trivy).
**How**: Run the new tool in sandbox over the corpus, diff its report against the incumbent's, map gaps to capability-parity tasks; Rego-based tools port cheaply; custom controls are 5 kinds (3 gap types, 2 relaxation types) — govern in core-repo + long-running fork.
**Trade-offs**: Migration cost vs. stale tooling and unchecked false positives. (Ch 10)

## MVI with Feedback Loop
**When to use**: Standing up IaC for a new org/scale tier.
**How**: Minimum Viable Infrastructure — build the smallest usable platform, keep Build → Measure → Learn → Iterate running; the loop is the part most teams drop.
**Trade-offs**: Under-spec'd initial platform vs. big-bang over-engineering that misses real usage signals. (Ch 12)