# Cheatsheet — Terraform at Scale: Decision Rules

## Core decision rules

- **Iterating N things?** Always `for_each`. `count` ONLY for `condition ? 1 : 0` (zero-or-one conditional). Count-index reordering destroys resources. (Ch 4, 11)
- **Singularity test (Ch 11)**: Is a singleton intrinsic (one per project/service, data-source-of-truth) → `count`. Could it ever replicate per region/project/env → `for_each` with an empty collection for zero. Small overengineering beats state surgery.
- **Dependency between resources?** Use a reference attribute first; `depends_on` only for genuinely hidden dependencies. (Ch 4)
- **Hardcoding a value?** Never via variable `default` (pseudo-hardcode) — use a local value. (Ch 2)
- **Composite/complex input?** Flatten into locals rather than expose a verbatim composite; bundle into a composite object only if it feeds a `for_each`/`count` collection. (Ch 2)
- **Type placeholder debt**: `any` is a development scaffold only; run `type()` in `terraform console` to fully specify, convert, and track leftover `any` as tech debt. (Ch 2)
- **Variable definition minimum**: `description` + `type` — never an empty `variable{}` block. (Ch 2)
- **Validation split (Ch 10)**: can() only inside variable `validation{}`; try() elsewhere, wrapping only the risky sub-expression. regex skepticism: prefer `regexall()` + attributes/tags; validation{} is plan-time, precondition{} plan-or-apply, postcondition{} apply-only.
- **State value lifetime**: state is truth only immediately after a successful apply. Everything else drift. (Ch 1, 6)
- **Anything applied to TF-managed resources outside TF = technical debt.** Don't mix TF with ClickOps or other provisioners. (Ch 1)
- **Never rewrite history** (Git or state). Undo = new corrective change forward. (Ch 11)

## If you see this — you're probably in trouble

| Tell | Likely problem | First move |
|---|---|---|
| Plan always shows changes (never-clean/no-op apply pain) | CSP identifier-format drift, over-broad field construction, unprotected .tfvars | Use most-specific field construction; `ignore_changes`; static-locals.tf |
| Tightly coupled projects (apply A → B → A) | Dependency cycle, no one-way flow | Reorganize states so dependencies flow one direction |
| Locked-state queue delays | State too big / too many cooks | Split by domain+lifecycle; cap concurrent operators |
| Merge conflicts everywhere | Monolith; conventions diverging | Signals for Change → plan split (Ch 8) |
| Halfway-applied states | Disconnected sibling resources | Make dependency explicit via attribute, else `depends_on` |
| Sed/awk edits into module `source` fields | Version drift | Registry + SemVer + `tf init -upgrade` |
| Modules that read resource attributes | Circular dependency | Convert to input-only logic module |

## Scale/split decision tree (when to split a project into states)

1. **Distinct operating teams / locked-state delays?** → split (org scaling, one-to-many).
2. **Resource lifecycle divergence?** (create/destroy frequency differs) → extract that domain.
3. **Long-running validations in queue** (>50% of runs blocked on one conditional chunk)? → extract `count`-conditional resources into their own state.
4. **`for_each` at nesting level conflicts?** Cookie-cutter stack replication → `for_each` in the outer module; fixed set + variable tail → resource block.
5. **M&A / new CSP / disproportional expansion (evident signals)?** → strangler fig or state reproduction swap, one domain at a time.

## Numbers the author commits to

- **Module deprecation**: deprecated version lives ≥ 6 months (9–12 better); max **3** versions available; up to **2** supported simultaneously.
- **Self-service Pareto**: ~80% of provisioning via self-service forms; exceptions tracked and fed back into standards.
- **Balanced-state depth**: ≤ 2·log_x(n); shortest-to-longest depth spread ≤ log_x(n); breadth over depth.
- **Variable resolution order**: env vars → terraform.tfvars → *.auto.tfvars (lexical) → -var-file → -var.
- **IAM discipline**: never mix authoritative/nonauthoritative binding types in one state; foundational authoritative baseline + downstream additive layers.
- **GDPR beats**: 72-hour breach reporting; 30-day data-subject-request SLA. HIPAA: sign the BAA **last**.

## Framework choice quick table

| Situation | Reach for |
|---|---|
| Recovery after bad apply | Forever Forward (new corrective change; state mv/import/rm + wildcard job) |
| Splitting a monolith | Strangler Fig (>2 projects) / State Reproduction Swap (greenfield) |
| Absorbing an acquired ecosystem | Oversight team from both sides → 11-step POC→Pilot→Roll out→Assess→Deprecate wave |
| Publishing internal modules | Git + private registry; SemVer; deprecation formula above |
| Environment separation | Backend key variation → distinct .tfvars → graduated env config → versioned env modules → wildcard jobs |
| Enforcement of naming/labels | Input-only logic modules (not review discipline) |
| Testing | tf test (plan/apply modes) + Terratest (no-provision suites; defer destroy) |
| Maturity assessment | TF Maturity Model (CMM/OMM-based; no partial levels); CNMM least-mature-aspect scoring |