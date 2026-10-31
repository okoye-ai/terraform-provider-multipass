# Glossary — Terraform at Scale (Robert Glenn)

Terms are ordered alphabetically. "(Ch N)" points to the chapter that develops the term. "TF" is the book's collective shorthand for Terraform + OpenTofu.

**Atomic state** — every TF state is a priori ignorant of all others; cross-state links only exist outside the state triplet. (Ch 6)

**Balanced-state math** — target state depth ≤ 2·log_x(n), shortest/longest depth spread ≤ log_x(n); prefer breadth over depth with a high leaf-to-state-node ratio. (Ch 6)

**Blast radius** — the entire state tree is the unit of impact; one broken apply can affect everything in that state. (Ch 6)

**Bundled solution** — a nested-module use case bundling compute instance configs, specialized appliances, or per-domain networking; gated by two tests: mismatching frequencies of code changes and unbalanced resource relationships. (Ch 5)

**Cascading change** — an upstream apply forcing downstream applies; worst case an apply cycle where the upstream must change twice. (Ch 6)

**Concept triage** — the Good Parts-style bucketing of software-engineering ideas into unique-to-IaC / borrowed / irrelevant-or-diminished. (Ch 1)

**Defense in depth** — a 7-layer control stack (account-wide → scoped → L7 → IDS/IPS → IAM → CSP proxy → L4) with diminishing returns and a multi-layer update tax. (Ch 9)

**Domino effect** — cascading update automation from upstream applies to downstream projects; dependency tracking evolves spreadsheet → relational DB → automated triggers. (Ch 7)

**Ephemeral environments** — on-demand build/teardown environments with mandatory expiry tagging; teardown speed is a security and cost requirement. (Ch 7)

**Field-order standard** — the canonical HCL block layout: for_each/count → provider → one-line fields → multiline fields → plain nested blocks → dynamic{} → depends_on → lifecycle{}. (Ch 4)

**Forever Forward** — forward-only recovery doctrine: TF has no rollback; undo by writing a new corrective change forward, never by rewriting state or Git history. (Ch 11)

**Four Common Scenarios** — organizational scaling (one-to-many split), reducing duplication (module extraction + state split), merger/acquisition (second provider block), organizational change management (many-to-many). (Ch 6)

**Implicit-First Dependency Rule** — prefer reference attributes over `depends_on`; gratuitous `depends_on` risks evaluation cycles. (Ch 4)

**Input precedence ladder** — TF variable resolution: env vars → terraform.tfvars → *.auto.tfvars (lexical) → -var-file/-var flags. (Ch 6)

**Local Equilibrium** — the realistic target state at scale: low friction, total coverage, quick incident response, within forecasted budget — not a fixed finish line. (Ch 12)

**Logical states** — see Atomic state; balanced states align by domain and lifecycle (Conway's Law). (Ch 6)

**MVI (Minimum Viable Infrastructure)** — the author's adaptation of Eric Ries' MVP to IaC; the feedback loop is the crucial element commonly dropped. (Ch 12)

**The Messy Middle** — convention variance growth at scale; countered by refactoring debt mechanisms: clean-up sprints, improve-what-you-touch, refactor bounties. (Ch 3)

**Nightmare Scenarios** — the technical-IaC-debt catalogue: Friday revert from manual changes, stuck state lock, count misuse, policy-vs-policy gridlock, destroyed state/backend. (Ch 1)

**No Pets** — cloud resources are livestock, not pets; the KPI shifts from time-to-remediate to time-to-replace. (Ch 7, ch 11)

**Plan-then-apply duality** — tf plan is essentially immutable per run, with blind spots: it won't detect existing resources and may miss name/ID collisions. (Ch 1)

**State address** — resource address = module path + each.key/count.index; explains primitive-unique set requirement for for_each and lexicographic map-key determinism. (Ch 4)

**State of States** — org-wide registry of TF projects/states linked to stable tagged Git commits and pipeline run outputs for auditability; previous stable only is potentially valid. (Ch 7)

**State Triplet** — the codebase + state object in the backend + running instances; all remediation must close all three legs; valid as truth only immediately after a successful apply. (Ch 6, ch 12)

**Strangler Fig pattern (IaC-adapted)** — monolith → multiple projects via one prioritized domain extraction at a time, validated against imported state; unique-attribute caveat solved by composite naming conventions. (Ch 8, ch 1)

**State Reproduction Swap** — greenfield code + parallel backend states + tf import, accepted when "same inputs → same outputs" (validated via custom outputs, tf output, tf state list). (Ch 8)

**SRP policy-binding rule** — a policy binding is "responsible to one, and only one, group of users and stakeholders"; same stakeholders → shared policy, distinct stakeholders → duplicated policies. (Ch 9)

**Three-locus balance** — logic placement decision: internal to / operating upon / external to the TF codebase; externalized logic runs in pipeline execution contexts. (Ch 3)

**Unity element pattern** — ('', 0, false) sentinels for conditional resources via count/ternary `condition ? 1 : 0`. (Ch 2)

**Validation block precedence** — variable validation{} > precondition{}; resource postcondition{} > output precondition{}, anchored on evaluation order (plan-time / conditional / apply-only). (Ch 10)

**Wildcard job** — protected, temporary, governed free-form command execution via the automation platform's service identity; viable in GHA/GitLab, not TFE/HCP Terraform. (Ch 6, ch 7)