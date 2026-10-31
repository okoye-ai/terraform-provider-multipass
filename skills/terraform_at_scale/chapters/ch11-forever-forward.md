# Chapter 11: Forever Forward

## Core Idea
TF has no rollback or revert command — every apply lands on top of all prior state changes, so remediation must always move history forward. "Forever forward" (alternative title: "Falling Forward") means state changes and Git history evolve together: when applied TF work was wrong, fix it with a *new* forward change (a `git revert`-style inverse commit plus corrective state surgery or a patch apply), never by rewriting either history. This chapter is the field guide for getting out of predicaments: named patterns for recurring failure modes, source-control hygiene that keeps the blame narrative legible, four end-to-end state-restructuring walkthroughs, and the CLI levers for surgical intervention. There is no foolproof solution — the goal is making the chance of painting yourself into a corner statistically insignificant.

## Frameworks Introduced
- **Forever Forward / Falling Forward**: never undo applied state or rewrite Git history; correct with inverse commits (`git revert` creates a new commit, preserving history) and forward fixes. Comprehend state history via Git, not the state backend.
- **No Pets (pets vs livestock)**: pre-cloud, the availability KPI was *time-to-remediate* a defective pet machine; cloud machines are rented, remote, and cannot be power-cycled — the KPI becomes *time-to-replace*.
- **Everything Is Production**: IaaS+PaaS administered entirely by the CSP, so even sandboxes host live, costly, infiltratable resources. Make them safe (no public access, private IPs only, GCP IAP for private remote access) yet flexible; add weekly resets and segment every environment so experimental workloads can't break out.
- **Getting Unstuck loop**: massive fragile project → systemic change needed (split projects/backends) → the "right way" is too costly/risky → hacky workaround, maybe by a departed colleague → it works until it doesn't → repeat. Quick workarounds framed as temporary stay indefinitely.
- **Module consolidation factors**: compare duplicates by expressiveness, compliance adherence, maintainability (readability + toolchain + procedure) — not a popularity/seniority contest. If all are equally lacking, build a net-new module; the owning team likely didn't author any of them anyway.
- **Preventative Measures lineup**: live code reviews (group activity, gamified for participation), static code analysis, policy as code, tests (can evaluate live resources; pair with logic modules for true unit tests), Git pre-commit hooks (`tf fmt`, `tf validate`), IaC platform observability. What matters most is a culture of discipline pursuing these earnestly and pragmatically.

## Key Concepts
**Common problems and their fixes**
- `count` on a list: can't deprovision a middle instance without shifting later indices; migrate with `tf state mv` rewriting count addresses to `for_each` addresses.
- Interdependent projects (A uses B's outputs, B uses A's): apply A, B, A. Fix: reorganize so dependencies flow one direction only.
- Disconnected resources → first apply halfway-applied, second succeeds: make the dependency specific via attribute reference, else `depends_on`.
- Halfway-applied state (plan clean, apply always fails midway): short play — cut the errant config, push working changes through, re-add isolated and fix; long play — validation expressions, data sources, `tf test`/Terratest.
- Never-clean states (plan wants to "update" a composite field to a less specific construction): use the most specific field construction available, or `lifecycle { ignore_changes }`.

**Parameterization hierarchy** — provider-documented field defaults for corporate-mandated settings; module variable defaults for true majority defaults (not for values that must never change); local values for parameterized-but-fixed values; logic modules to return static values operators of the root module can't modify. Avoid inline logic in `resource{}` field assignments — abstract into `locals{}`/logic modules with names that self-document construction. Avoid sed/awk placeholder replacement of config files (inelegant, produces massive files, repeats on every policy change): prefer one config + per-environment `.tfvars` + per-environment backend key/prefix.

**for_each placement in nested modules**: in the `module{}` block when replicating a whole cookie-cutter stack; in the `resource{}` block when the module bundles a fixed set plus a variable count of one resource type. Inverting later is tedious and risky. When `count`-ternary conditionals reach critical mass, package them into a nested module — if purely downstream and a significant share of state, extract to a dedicated TF project so optional configuration becomes domain-oriented.

**Source control hygiene**
- Branch names should encode the full purpose (~250 chars available). Bad: `feature/TAS-11-123` (ticket only), `bug-fix/robert-4-23` (name + ambiguous date), `feature/does-x` (omits a separate bundled change — misleads root-cause review). Commit messages: complete sentences detailing *every* change. The 50/72 rule is a GitHub/GitLab rendering convention, beyond this scope.
- If scope outgrows the branch name: branch off with the accurate name, `git branch -D` the old one (and `git push <remote> :<branch>` if it was pushed). `git commit --amend` only *before* pushing; after push needs `--force` — extreme cases only.
- **Merge strategies**: merge commit (preserves original hashes + a marker commit naming the merged branch; best for pinpointing when an issue was introduced — prefer for proprietary common-branch work); rebase (fine, but rewrites commit *dates* to merge time, confusing recall on long branches); squash (loses all evolution — reserve for condensing WIP to a release branch, stripping sensitive info, OSS-for-company). Squash shines on local exploratory WIP: keep a WIP branch unpushed, squash into the real feature branch when a compliant solution emerges.
- **`git stash`**: unstaged changes on a local LIFO stack. Trap: `git stash pop` can conflict and has no `--abort` — `git reset --hard HEAD` (discarding other uncommitted work), re-pull, pop again. A conflicted pop leaves the entry on the stack; hand-resolved conflicts need `git stash drop`.
- Resolve merge conflicts in a **new local branch**, never on the conflicting branch — a botched resolution merge can't be cancelled after acceptance with `git merge --abort`.

**Over-trusting branching strategies**: an SDLC's tolerances don't transfer to IaC — dev can't prove prod (broader config, more regions, retention, recovery objectives; a feature unsupported in one region surfaces only in the environment containing it). Never maintain one long-running branch per environment: it invites per-env hotfixes that must merge everywhere. Release from a common branch; handle isolated single-environment corrections with a **wildcard job** targeting one environment + one branch.

**Getting unstuck plays**
- *Duplicate modules*: rational origins (feature gap, feature avoidance, local-module policy, sensitivity separation); DRY cost = updating every copy per new policy. Invest in a **module registry early** (TFE/HCP have one built in) even with a single team.
- *Remote module needs an update*: (1) PR upstream — may be rejected as out of scope; (2) fork as module source — needs credentials (SSH key may violate policy), manual sync; (3) **local bolt-on module** — wraps the leaf module, passes inputs through, creates the missing resource; no credentials or read access needed, but requires resource-by-resource state moves into the bolt-on.
- *Unexpected change in an advanced environment*: either drift to revert (investigate access logs — human operator → IAM fix; service identity → audit its platform config) or a change to preserve. If preserved: wildcard job applies a narrow patch branch to only the affected environment, then merge it back into the previously released branch and let normal environment-by-environment progression run — the patch is a no-op for earlier environments and reconciles via commit history (don't squash).
- *Environment conflicts* (same config, multiple states — works in dev, breaks in test/prod): artificial conflicts get a stopgap pattern; real ones need a different solution — remove the configuration and follow normal feature branching, not an environment patch.

## Mental Models
- Git and TF history are one timeline: reverting in TF must be mirrored by a forward Git commit; deleting a state-moved commit destroys your ability to reconcile state.
- Availability is built from redundancy and replacement speed, not repair speed.
- State surgery is expected maintenance, not failure: `tf state mv`/`import`/`rm` are the standard forward corrections whenever resource addresses change.
- Technical debt enters when a rushed fix is rubber-stamped: no one wants to touch the traumatic code, workarounds accrete, and reconstructing context weeks later takes overinflated effort. Worse than one bad commit is the *deterioration of discipline* it triggers — a lapse in rigor that compounds over a few sprints and corrupts the historical record (a quarter's worth of illegible commits is, in the author's words, "a descension into madness").
- Validate every restructuring with symmetric evidence: after a move, plan must report matching create-destroy pairs (pre-move) then *zero* changes (post-move).

## Anti-patterns
- **`count` for lists of resources**: middle deprovisioning shifts indices and destroys siblings. Fix: `for_each` + state moves; reserve `count` for Booleans (0/1) where singularity is intrinsic.
- **Multiple long-running environment branches**: per-env hotfixes must merge everywhere; conflicts with the one true configuration. Fix: common release branch + wildcard jobs.
- **`-target`**: skips the rest of the resource graph, leaving partial state. Rare extreme cases only, from a wildcard job, immediately followed by a full proper apply.
- **sed/awk placeholder replacement of config files**: inelegant, bloated, repeats on every policy change.
- **`git commit --amend` after push** (history rewrite) and **squash-merging routine work** (loses the paper trail root-cause work needs).
- **Module variable defaults used as invariants**: they're overridable; use locals or logic modules.
- **Rubber-stamped emergency releases** (fix team + tired approval team): function-only review, quality "deprioritized by authority figures" — unaccounted technical debt.

## Code Examples
Migrating extracted resources to their module addresses, after the plan confirms matching create-destroy pairs:

```hcl
tf state mv google_compute_disk.region_one \
  module.compute.google_compute_disk.region_one
tf state mv google_compute_network.default \
  module.network.google_compute_network.default
tf state mv google_storage_bucket.default \
  local_main.google_storage_bucket.default
```
**What it demonstrates**: Step 11 of "Extracting Resources Into a Module" — run as one shell script via a wildcard job (not by hand) to avoid miskeys; addresses are read off the symmetric destroy/create plan pairs from the preceding step.

Enumerating existing resource IDs for import without matching up plan output by hand:

```hcl
tf show -json | jq -r '
  .values.root_module.resources[]
  | select(.values.id != null)
  | "\(.address) \(.values.id)"
'
# google_compute_network.dev projects/tas-11-dev/global/networks/tas-11-dev-vpc
```
**What it demonstrates**: the discovery step in "Making a Reusable TF Project From a Static One" — produce `address ID` pairs from the old combined state, then feed them to per-environment imports (`tf -chdir=env/dev import google_compute_network.default projects/tas-11-dev/...`), genericizing addresses (the environment distinction lives in the per-env state, not the resource address).

Related one-liners: transfer default-workspace state to a named local workspace with `tf workspace select default; tf state pull > default_backup.tfstate; tf workspace select dev; tf state push default_backup.tfstate` — `tf workspace new` creates an *empty* state, so a plan would recreate everything; and a faster alternative to importing when splitting states is `terraform state pull > terraform.tfstate`, copying the file into each env subdir, then re-initializing so the backend moves to the remote location.

## Reference Tables
Merge strategy selection for pull/merge requests:

| Strategy | History effect | Use when |
|---|---|---|
| Merge commit | Original hashes preserved + marker commit naming the merged branch | Default on common branches with proprietary code; best for pinpointing when issues were introduced |
| Rebase and merge | New hashes; commit *dates* rewritten to merge time | Fine with good branch names/messages; use deliberately |
| Squash and merge | All commits reduced to one combined commit | Release-branch WIP condensation, stripping sensitive changes, OSS-for-company work, local exploratory WIP |

## Worked Example
**Extracting resources into an internally shared remote module** (the flagship 13-step walkthrough; GCP compute + network + storage stack, `tas-11` project):

1. Identify **primary resources** to standardize vs **secondary** dependencies; include secondaries referenced only by primaries; lean on domain analysis otherwise → resolves to a network module and a compute module.
2. New Git repo per remote module; restrict write, open read (release branches/tags for some consumers).
3. Feature branch in the root project's repo.
4. Cut resources into the modules; add variables/outputs crossing each boundary; *keep* the old variables/outputs in the root (so `.tfvars` still validates); replace cut `resource{}` blocks with `module{}` blocks referencing `tas-module-registry.com/tas-11/{network,compute}/google`. (If ongoing main-branch work interferes, defer removals until Step 10.)
5. Extract the rest (bucket + IAM bindings) into a local module `./modules/main` to avoid mixing `resource{}` and `module{}` blocks in the root.
6. Port or extract validation steps so coverage survives.
7. Add a `.terraformignore` (state files, PEMs/keys, editor files, logs, `*.tftest.hcl`).
8. Publish to the registry — from a wildcard job, not your workstation.
9. Build release automation so repo and registry versions stay in parity.
10. `tf plan` in a wildcard job: expect equal counts of creates and destroys in exactly matching pairs (`google_compute_network.default` destroyed "not in configuration" alongside `module.network.google_compute_network.default` created) — this yields the state addresses, surfaces missing components, and proves the module fetches from the registry.
11. Run the `tf state mv` script in a wildcard job.
12. `tf plan` again → "No changes. Your infrastructure matches the configuration."; pilot validations here.
13. Open the merge request; pipeline should report no changes and pass validations — initiative complete.

## Key Takeaways
- Never rewrite applied state or Git history; every correction is a forward-moving change.
- Availability = replaceability. Design redundant, discardable infrastructure (livestock), not curated pets; treat every environment, even sandboxes, as production — segment and reset them.
- Keep the blame narrative legible: descriptive branch names, sentence-length commit messages covering *all* changes, merge commits on common branches, conflicts resolved on a throwaway local branch.
- Don't map SDLC branching onto IaC: one common release branch; isolated environment corrections go through wildcard jobs.
- State surgery (`state mv`, `import`, `state rm`, backend re-init, `state pull`/`push`) is the routine machinery of reorganization — script it, run it in wildcard jobs, and prove every step with a zero-change plan on both sides of the change.
- Prevent module duplication with a registry invested in early; consolidate on expressiveness/compliance/maintainability, not popularity.
- The parameterization ladder beats string munging: provider defaults → variable defaults → locals → logic modules.
- Misc levers: `.terraformignore` before publishing; `tf console` for expression prototyping; `-lock-timeout` under the platform job timeout; `-replace` instead of hacks; avoid `-target`; tune `-parallelism` within CSP rate limits.

## Connects To
Ch4 (count/for_each semantics and state-address migration), Ch5 (nested modules and for_each placement — Example 5-6), Ch6 (wildcard jobs: the standing mechanism for out-of-band single-environment operations and state scripts), Ch10 (branch names, commit messages, branching strategies). The four walkthroughs operationalize the state techniques of the state chapter and the registry/automation practices threaded through the book; the final chapter closes with philosophy and further effective-feature examples.