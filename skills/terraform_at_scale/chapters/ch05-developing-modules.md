# Chapter 5: Developing Modules

## Core Idea
In Terraform, *everything* is a module — expressions and blocks live inside module scope, so module design is inseparable from project design. The chapter gives a taxonomy of module types (root, nested, nesting, leaf, mixed, unitary, remote, local, logic), criteria for when nesting helps and when it does not, a controlled refactoring procedure, distribution/versioning/deprecation strategy, and a deliberately modest set of "best available practices" — because, per Conway's Law, each organization produces a unique TF corpus and true universal best practices are rare. Use modules to make resource groupings, lifecycles, ownership, and access boundaries explicit; avoid structural half-measures (mixed resource/module blocks, singleton modules, string-replacement hacks).

## Frameworks Introduced
- **Module type taxonomy** (9 named types): Root (command target, root of TF state; only modules reading `.tfvars`/env/CLI inputs and defining backend), Nested (referenced via `module{}` `source`), Nesting/outer/referencing (has `module{}` blocks), Leaf/terminating (no `module{}` blocks; only `resource{}`/`data{}`), Mixed (both `resource{}` and `module{}` — avoid; a mostly-nesting module with a bolt-on `resource{}` is a "bolt-on module"), Unitary (one `resource{}` block = singleton module; one `module{}` block = wrapper module), Remote (source managed in a different repo than referrer), Local (same repo), Logic module (records no resources to state — only `variable{}`, `output{}`, optional `locals{}`).
- **Logic module pattern**: extract fragile/complex expressions (interpolated names, multi-clause validations, labels) out of the root `locals{}` block into a no-resource module, giving a strict scoping boundary with its own access controls, review rigor, and software lifecycle.
- **When NOT to nest**: (1) differences in resource *update frequencies* (state-level separation doesn't come from nesting), (2) few already-related resources, (3) mixing resources and modules, (4) singleton modules.
- **Bundled Solution Use Case** families for nesting: compute instance configurations (disk + SA + NICs standardized), specialized appliances (isolate esoteric/exceptional config; prefer forking a generic module over over-parameterizing it), networking (VPC/subnet/routing vs firewalls vs DNS as separate nested modules), mismatching frequencies of *code* changes (extreme case only; use dedicated repos), unbalanced resource relationships (split by interconnectedness; same source reused with distinct inputs).
- **Local-module rule of thumb** — go local only if one or more: only one team develops TF; fairly specialized use case; uncommon/experimental resources; extraordinarily specialized or singular resources.
- **Module composition vs embedded modules**: HashiCorp recommends flat composition (root references only leaf modules) + inversion of control; author's extension — treat third-party modules as opaque/terminating, keep composition strict only for internal/local modules.
- **Versioning schema**: SemVer mandatory on registries (extended SemVer for `-beta`, `-rc.1` prereleases and `+build` metadata); tags + release-channel branches (e.g. `v1`/`v2` long-running branches) in Git; prefix/filesystem versioning in buckets (major per prefix, minors within, patches replacing); HTTP/S sources = any schema you can build.
- **Deprecation formula**: deprecated ≥ 6 months (9–12 if too short); never more than three available modules, up to two supported; scale the heuristic to release cadence; communicate on shared channels with consumers.
- **Two-channel distribution pattern** (internal): developers get read access to Git repos for transparency and WIP validation; automation identity gets read access *only* to ready-to-use copies in a private artifact registry — so `source` in automation always points at the registry.

## Key Concepts
- Root modules are not special except as command targets and state roots: they can themselves be referenced as nested modules. If a state-carrying root module M1 is referenced by M2, M2's plan ignores M1's state and attribute collisions surface only at apply — tie dual-purpose use to documented business justification, or prefer a **wrapper root module** that wraps the standalone version (making it purely nested).
- Nesting modules behave as *organization agents*: they pass inputs/outputs between children and must re-expose nested outputs; leaf modules are explicit about the resources they manage and must expose all useful info via outputs.
- The only meaningful local/remote distinction: local modules share a source-control history (and lifecycle/versioning/access control) with their referrer; remote modules do not. Access control is the main remote-module challenge; prefer deliberate "referrer beware" or "referenced beware" policy, never carelessness.
- Refactoring to nested modules (local or remote) has **no impact on resource lifecycle** — lifecycle separation is state work (Chapter 6), but state addresses may need updating (`tf state mv` territory).
- Nested module decision made at development time: refactor artifact of a tailored use case, greenfield with architectural oversight, or shared capability — each suggests a different home.
- `source` is a **static field** — no variables or expressions; per-referrer version pinning conflicts with reused root modules serving multiple states (a genuine no-good-practices zone).
- All remote-module consumers hit the local module cache at `tf init`; use `terraform init -upgrade` at lifecycle checkpoints, especially for bucket/HTTP/constraint-based sources.
- Git `ref` param selects branch/tag; `//` delimits repo from nested submodule path (before the param map for Git, after the file extension for ZIPs).
- Modules are protected interfaces: read/write access can be restricted per module; exposing a branch exposes its whole commit history; publish only ready branches/tags and put caution clauses in terms of use; public registry publication requires public GitHub source plus a license.
- Internal-only info leaks through module inputs: a Boolean named `include_management_nic` profiles your architecture.

## Mental Models
- **Module tree = TF state tree**: root → nesting → nested → leaf, terminating at resources; nesting levels add state-address complexity.
- **Conway's Law as design law**: "organizations…produce [system] designs which are copies of [their own] communication structures" — your TF corpus will mirror your org chart; adding departments is easier to absorb than reassigning resource ownership, which may require dismantling projects.
- **Composition as dependency injection**: modules pass information in DI fashion; third-party modules are opaque systems terminating in their own way.
- **All cloud infrastructure is production**: there is no dev environment for IaC — dev app environments run on well-defined, secured, cost-effective resources, so minimize uncertainty (validations, preconditions/postconditions) everywhere.
- Two different update-speed axes: *code* change frequency justifies module separation; *resource update* frequency never does (that is state work).
- Prefer robustness over velocity concessions: anti-patterns accrete from repeated small concessions, not deliberate design, and become "untouchable arcana."

## Anti-patterns
- **Mixed modules** (`resource{}` + `module{}` in one module): creates confusing relationships between TF state levels. Partial extraction ("one nested module, rest stays in root") isn't worth it — extract as its own root module with its own lifecycle, isolate shared-lifecycle resources in their own `.tf` file, or justify full grouping instead.
- **Singleton modules** (one `resource{}` block): little value; a lone unrelated resource is itself an oddity. If regular across the codebase, relax the no-mixing policy deliberately with documented guardrails/approval — keep singletons a rarely granted exception for highly specialized components.
- **Bolt-on modules**: nesting modules with a small number of `resource{}` blocks added on — generally avoid.
- **Git-repo sourcing of internal remote modules** (esp. OpenTofu without a registry): authentication forces user-or-SSH-key tying, key rotation, ownership questions; prefer a Registry-API-compatible implementation and treat Git as tech-debt workaround.
- **sed/awk string replacement on static fields** (e.g. `[VERSION_REFERENCE]` → `?ref=v2.0.1` before plan): nearly untestable, relies on developer discipline, heavy documentation overhead — avoid; deploying from a different branch is slightly less unsavory.
- **Overusing super-bundle/embedded modules**: inefficient reuse, fragile leaf modules that never get consumed directly, excessively complex nested input data schemas. Require documented business justification and usage instructions so the pattern isn't mimicked thoughtlessly.
- **Data gymnastics in composition**: deconstructing/reconstructing/conditionally injecting one leaf module's outputs into another's inputs is the signal to consider an embedded (super-bundle) module instead.
- **Local module leakage**: local modules referenced by other nesting modules silently become remote, creating two agendas for one module; deviation risk grows inversely (perhaps exponentially) with coordination.
- **Overengineering the local/remote decision**: folding hypothetical future problems into architecture decisions.
- **Outdated documentation**: wrong docs are worse than none; with RAG tooling, currency and completeness are productivity drivers, organization is less critical. Best documentation is the code itself.
- **Async-only PR reviews**: invite rubber-stamp reviews.

## Code Examples
Logic module (no resources; keeps root `locals{}` bounded and intelligible):
```hcl
#-----------------------------------------------------------------------
# logic module in ./modules/local
#-----------------------------------------------------------------------
output "safe_name" {
  description = "Safe name constructed from the inputs."
  value       = local.safe_name
}
 
output "safe_labels" {
  description = "Safe labels constructed from the inputs and a timestamp."
  value       = local.safe_labels
}
 
locals {
  safe_name   = "${var.business_unit}-${var.app_code}-${var.region}"
  safe_labels = {
    app_code      = var.app_code
    business_unit = var.business_unit
    region        = var.region
    modified_at   = lower(formatdate("MMM-DD-YYYY-hh_mm", timestamp()))
                    # for example, 'jan-02-2018-23_12'
                    # note, this will always result in a diff
  }
}
```
**What it demonstrates**: a logic module abstracting fragile expressions (naming convention enforcement, label construction with a timestamp that "will always result in a diff") away from resource definitions — enabling separate access controls, review rigor, and lifecycle; consumed as `module.local.safe_name`.

Refactor before/after (for_each moves *outside* the nested module):
```hcl
#-----------------------------------------------------------------------
# After - Root Module
#-----------------------------------------------------------------------
module "nested" {
  for_each = { for stack in var.stack_data : stack.app_name => stack }
  source   = "./modules/nested"
 
  network_id   = var.network_id
  app_name     = each.value.app_name
  region       = each.value.region
  zone         = each.value.zone
  machine_type = var.machine_type
  os_image     = var.os_image
}
 
#-----------------------------------------------------------------------
# After - Nested Module
#-----------------------------------------------------------------------
resource "google_compute_subnetwork" "default" {
  network = var.network_id
  name    = "${var.app_name}-snet"
  region  = var.region
}
```
**What it demonstrates**: the big-bang refactor pattern — repeated `resource{}` blocks with `for_each` collapse into a single nested module whose per-instance inputs become plain variables; the fully-replicated collection puts `for_each` in the *outer* module's `module{}` block (and that `for_each`/`moved` readdressing implies state updates — Chapter 6).

Module reference forms (registry, Git, bucket):
```hcl
module "private_registry_version" {
  source  = "app.terraform.io/tas/private_module/aws"
  version = ">= v1.0.1-alpha, < v1.2.0"
}
 
module "git_repository_nested_version" {
  source = "git::ssh://mydomain.com/git/private_module//modules/nested"
}
 
module "bucket_zip_nested" {
  source = "s3::https://s3.amazonaws.com/tas/c5/module.zip//modules/nested"
}
```
**What it demonstrates**: `source`/`version` semantics per location; `//` placement for subdirectory modules (before the param map for Git, after `.zip` for buckets); constraints select the newest matching version.

What to avoid (string replacement before plan):
```hcl
#!/bin/bash
...
sed -i 's@[VERSION_REFERENCE]@?ref=v2.0.1@g' main.tf
tf plan
```
**What it demonstrates**: the anti-pattern of retrofitted variability in static fields via `sed`/`awk` string replacement — hard to validate, discipline-dependent, documentation-heavy.

## Reference Tables
| Module type | Definition | Guidance |
|---|---|---|
| Root | Target of a TF command; root of TF state; reads `.tfvars`/env/CLI; defines backend | Only it may be a command target; can be nested with strong justification |
| Nested | Referenced via `module{}` source | Build from related `resource{}` groups |
| Nesting (outer) | Has `module{}` blocks | Passes info between children; must re-expose child outputs |
| Leaf (terminating) | No `module{}` blocks | Explicit resources; expose all useful info via outputs |
| Mixed | Both `resource{}` + `module{}` | Avoid ("bolt-on") |
| Unitary — singleton (`resource`) / wrapper (`module`) | One block only | Singleton: rare exception; wrapper: valid as a standardized approach |
| Local | Same repo as referrer | Shares changeset history/versioning/access control |
| Remote | Separate repo/registry/bucket/HTTP | Main challenge is access control; expose only to intended audience |
| Logic | Only `variable{}`/`output{}`/`locals{}`; nothing in state | Extract fragile logic; own lifecycle + review bar |

Module-source cheat sheet: relative filepath (local), `registry/host/namespace/name/provider` + optional `version` field with constraints (registries; public registry may omit base URL), `git::ssh://...?ref=&lt;branch-or-tag&gt;` (Git; also supports shallow clone via `depth = 1` in HCP docs), `s3::https://.../module.zip` (bucket), HTTP/S GET params (any schema), `//` for subdirectory modules (Git: before param map; ZIP: after extension).

SemVer on registries: `X.Y.Z`, extended `-beta`/`-rc.1` prerelease suffixes, `+build` metadata (`+2515807` truncated commit, `+4820571396` GHA run ID); no `version` field = latest published.

Deprecation formula: ≥6-month deprecated flag (9–12 if cadence is slower); ≤3 available modules, ≤2 supported; consider staggering so newest and oldest overlap for consumer grace periods; decide external schedules around the release of the second major version.

## Worked Example
The chapter's fullest worked example is the **network-stack decomposition refactor** (Examples 5-7 and surrounding guidance):
1. **Starting point**: one root module containing `google_compute_subnetwork`, `google_compute_instance`, and `google_service_account` blocks, all sharing `for_each = { for stack in var.stack_data : stack.app_name => stack }` — resources tightly coupled into per-stack combinations.
2. **Segmentation decisions**: group by service area, then purpose-oriented subgroups; decide whether `for_each` lives inside or outside the module; consider reusing one source with distinct inputs where logic distinctions merit explicitness (e.g. `server_iam_identities` vs `cluster_iam_identities` both sourced from `./modules/iam_identities` with different `identity_data`).
3. **Mechanics**: move `resource{}` blocks to a subdirectory; copy the `variable{}` definitions they rely on; add a `module{}` block wiring `network_id`, `app_name`, `region`, `zone`, `machine_type`, `os_image`; the nested module's per-instance resources become singular (names like `"${var.app_name}-snet"` replace `each.value.app_name`). Repeat per collection, all at once — big-bang, to avoid mid-state mixed modules and drawn-out merge conflicts.
4. **Validation/local-first**: apply or at least review a plan while modules are still local; only then extract the directory to its own repo or an artifact registry. Update state addresses if TF can't infer the readdressing (`moved`/state work, Chapter 6).
5. **Reuse outcome**: the same `./modules/stack` source is instantiated per app and environment (`app_1_dev`, `app_1_prod`, `app_2_dev`, `app_2_prod`), with the stack module bundling a `google_storage_bucket`, `google_compute_network`, and `google_service_account` per app — replicas of the stack from different variable assignments, optionally enforcing RHEL for prod and Rocky Linux for non-prod via validated `os_image`.

## Key Takeaways
- Prefer leaf modules fed by flat composition; keep nesting shallow ("only one level of child modules" for modules you control) and treat third-party modules as opaque, terminating at their own boundary.
- Segment modules by logical domain relationship imbalance, bundled solutions (compute configs, specialized appliances, network layers), and extreme *code*-lifecycle divergence — never by resource update frequency.
- Refactor all the way, big-bang, local-first; never leave mixed modules behind; put `for_each` in the outer module for fully replicated collections.
- Distribute modules through at least two channels (Git for transparency + registry/bucket for automation-consumable releases) and keep automation identities from reading anything but ready-to-use copies; be consistent org-wide, not per-team.
- Version with SemVer + release-channel branches; adopt an org-wide constraint schema; run `terraform init -upgrade` at lifecycle checkpoints; plan deprecation with an explicit schedule formula before internal consumption saturates.
- Default to transparency: read access to TF code repositories for all engineering; write access only for owning teams; automation identities never have write access to managed services.
- Review code live, with the team, every time; audit non-reviewed modules periodically; keep documentation current above all (RAG-era priority).
- Concessions stack: string replacement and similar workarounds appear months in, become untouchable arcana, and sap productivity — redesign instead.

## Connects To
- **Chapter 4**: reused root modules with different input variable assignments (which complicates per-state version pinning).
- **Chapter 6**: TF state's tree-like structure produced by nested modules; state readdressing (`moved`) when refactoring; separating lifecycles via state manipulation rather than nesting.
- Later chapters: environment/workspace-per-root-module reuse, automation platforms and the two-channel module distribution they enable, governance, and RAG-era documentation practices.