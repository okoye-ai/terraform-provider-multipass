# Chapter 4: Built-In Fields: Reference Attributes, Local Values, Meta-Arguments, and Outputs

## Core Idea
HCL is declarative value assignment, not procedural logic — so the craft of Terraform is choosing *where each value lives* (resource field, reference attribute, local value, output) and which meta-argument shapes the block. Reference attributes create implicit dependencies (Terraform's preferred form); locals decompose dense expressions into self-documenting named values; `for_each` iterates (prefer it) while `count` should be reserved almost exclusively for conditional blocks (0 or 1); `depends_on` is a last resort to be refactored away; lifecycle rules, preconditions/postconditions, and the `dynamic{}` block are tactical tools, not defaults. Standardize block field order and naming so configuration is legible to anyone.

## Frameworks Introduced
- **Implicit-over-explicit dependency rule**: establish dependencies via reference attributes (`google_compute_network.vpc.name`) so Terraform infers ordering; only fall back to `depends_on` where inference is impossible, and prefer refactoring module structure over adding it (a chain of "before/after refactor" examples).
- **The conditional-block pattern for `count`**: the only sanctioned use of count is `count = condition ? 1 : 0`, always combined with ternary guard expressions on downstream references — anything other than 0 or 1 invites nondeterministic destroy/recreate on reordering.
- **for-each-key-address model**: TF state addresses for `for_each` elements embed `each.key` (map key or set value), which is why sets must contain primitives (uniqueness guarantees distinct addresses) and why outputs of iterated resources must be reshaped into maps with unique keys before use as another `for_each`.
- **Two locals organization styles**: (1) group related values, downstream-after-referenced, with comment markers; (2) for large blocks, elevate "used by resources" values to the top and stack intermediate calculations in reverse order beneath them, so logic reads resource → component expressions.
- **Canonical block field order**: `for_each`/`count` → `provider` → one-line resource fields (identifying/placement and required fields first) → multiline collection fields → plain nested blocks → `dynamic{}` blocks → `depends_on` → `lifecycle{}`.
- **Self-documenting elements** (after Robert C. Martin's *Clean Code*): snake_case names (HashiCorp's recommendation) carry the purpose; decompose complex logic into individually named local values rather than comments, code words, or tribal knowledge. Alias pattern: build expressively long locals, reference a compactly named "final" local.
- **Clean TF / production-ready IaC**: treat all infrastructure code as production-ready regardless of environment; agile methodologies (scrum/XP/SAFe) are an anti-pattern for IaC because they prioritize working code over deliberate design — prefer **Kanban**.

## Key Concepts
- **Resource fields vs reference attributes**: fields are provider-defined inputs (mostly optional, with defaults) mapping to API parameters; reference attributes are informational values the CSP assigns (computed IDs, reformatted names/locations) readable via dot notation. They also include every resource field.
- **`output{}` block fields**: `value` (only required), `description` (strongly recommended, like variables), `sensitive` (hides from CLI; does *not* encrypt), `ephemeral` (not persisted in state; good for submodule→parent pass-through), `depends_on` (its only meta-argument), `precondition` (validation with `condition` + `error_message`).
- **Strategic outputs**: a module with no explicit outputs has none — define outputs for *every* module, including experimental ones; keep them in a dedicated `outputs.tf`, grouped by source resource/module, in module order. Construct them early so their stability exposes unexpected changes. Exposing a whole resource or submodule reference (`value = module.submodule`) hands all attributes to the caller. Root-module outputs should be shaped for downstream systems, with `precondition{}` enforcing the downstream format contract.
- Don't generate sensitive values in TF when a secret manager can own them; the legitimate case is values consumed by the platform running TF itself.
- **`locals{}` block**: module-scoped named key/value pairs; the right home for complex calculations, restructuring resource attributes and third-party module outputs, and hardcoding non-variable values that must stay pinned for third-party consumers (tip for internal/shared modules). One per module, in `locals.tf`, well named; locals may reference each other.
- **Meta-arguments**: `for_each` (iterate via `each.key`/`each.value`; map keys or primitive-set values), `count` (via `count.index`; clunky for optional blocks), `depends_on` (explicit unidirectional dependency), `lifecycle{}`, `provider` (selects provider config by alias; resources/data sources), `providers` (module-level).
- **`lifecycle{}` rules** (resource-only except validation): `create_before_destroy` (no-downtime resources designed to coexist, e.g. stateless load-balanced servers), `prevent_destroy` (high-blast-radius or sensitive resources; theoretically unnecessary if you read plans — often more symbolic than strategic), `ignore_changes` (let external systems own certain attributes, avoiding destructive replaces), `replace_triggered_by` (force recreation when listed fields change; immutable-resource deployment strategies). Reserve lifecycle rules for justified cases documented as policy (TDD / corporate wiki).
- **precondition{}/postcondition{}}**: available in resource `lifecycle{}`, data sources, and ephemeral blocks; evaluated before/after create-or-update. `postcondition` uniquely exposes the **`self` object** for checking the resource's own attributes — ideal for validating values TF doesn't manage (scripts, CSP-side changes).
- **`removed{}` block**: the `resource{}` block with the keyword swapped; its `lifecycle{ destroy = true|false }` is fixed at first apply after conversion — `true` destroys the resource (default when omitted), `false` only removes it from state (useful for handing resources between teams or controlled adoption). Changeable only before the first apply.
- **`dynamic{}` block**: renders a variable number of a repeatable nested block via `for_each` (or `count` for conditionally included singular blocks); creates a block-scoped object named after the block, scoped to its `content{}`, usable in nested `dynamic{}` for deeper iteration. Common in third-party modules; use sparingly, never to future-proof.

## Mental Models
- **Jungle-of-operators risk**: inline expressions accumulate into "dense jungles of operators, functions, and meta-arguments" — unwind every composition into named local values so a reader can follow the chain back to the most basic calculation elements.
- **State address as identity**: whether a resource exists stably is determined by its state address (module chain + resource + iteration key/index); this single fact explains set/primitive constraints on `for_each`, count's reorder fragility, and why count↔for_each migration is destructive.
- **Lifecycle rules as operator-facing boundary**: `lifecycle{}` belongs at the bottom of a block because it is the operators' purview — a boundary term over the resource, not part of its configuration.
- **Outputs as underutilized leverage**: their optional nature is why they're "one of the most underutilized features in all of TF" — the visibility benefit outweighs any overengineering risk; "you definitely want to implement outputs."

## Anti-patterns
- **Sharing input variables instead of referencing attributes**: two resources both fed `var.network_name` look correct but carry no dependency edge — Terraform may create the consumer first and fail. Fix by referencing `google_compute_network.vpc.name`.
- **`count` for multi-copy resources**: count indices are consecutive whole numbers with no way to remove arbitrary elements; a lexicographic reorder of the source list recreates *all* shifted resources. Use `for_each`; reserve count for 0/1 conditionals.
- **Referencing a splat of iterated-resource objects as another `for_each`** (`for_each = google_compute_instance.gce_nodes[*].network_interface`) — invalid: a list of non-primitives has no unique keys. Convert with a for expression into a map keyed by a unique identifier (e.g. `vm.instance_id`), also making state deterministic (lexicographic key order).
- **Blanket `depends_on`**: adds plan complexity and can cause evaluation cycles; refactor to implicit dependencies where possible.
- **`depends_on`-free conditional outputs without ternary guards**: optional count-style resources yield a list that may be empty — referencing them without `length(...) > 0 ? ... : ""` or splat spreads complexity everywhere.
- **Adding `local`s to the bottom of the block over time**: unrelated values shuffle together until the block is as opaque as inline expressions; adopt a stated grouping/ordering style guide.
- **Clever/hack logic in locals**: little benefit to preserving configuration that's hard to comprehend, however effective; decompose instead.
- **`dynamic{}` everywhere a nested block repeats**: a small static number of blocks is better served by individual blocks; dynamic blocks are overengineering when used to future-proof.
- **Multicloud resources in one TF state via `provider` aliases**: defeats the availability/recovery goals of multicloud; prefer separate states (and projects/repos) per CSP. Multi-CSP remote modules are usually team-specific — keep them local.
- **IaC development under scrum/XP/SAFe**: explicitly violates agile's "working code over comprehensive design" for infrastructure that must be deliberate and production-ready from day one.
- **Ad-hoc field placement and whitespace**: interspersed fields among nested blocks hide configuration; exceptions to house style must be documented and justified.
- **camelCase or kebab-case naming**: HashiCorp recommends snake_case; balance expressiveness with brevity (overly long names pollute block real estate — use the alias-local pattern).

## Code Examples

```hcl
resource "google_compute_instance" "gce_nodes" {
    for_each = var.node_names
    …
}
…
locals {
    vm_nics_map = { for vm in google_compute_instance.gce_nodes :
        vm.instance_id => vm.network_interface
    }
}
…
resource "google_dns_record_set" "vm_a_record" {
    for_each = local.vm_nics_map
    # VALID – each key is unique, includes all necessary information
```
**What it demonstrates**: reshaping the non-primitive output of an iterated resource into a uniquely keyed map so it can legally drive another `for_each` — the canonical fix for the "list of maps as for_each" error, with lexicographically ordered, deterministic state addresses.

```hcl
resource "google_dns_record_set" "a_record" {
  count = var.dns_domain != "" ? 1 : 0

  name         = var.dns_domain
  type         = "A"
  managed_zone = google_dns_managed_zone.special.name
}

output "dns_record_name" {
  value = (length(google_dns_record_set.a_record) > 0
  ? google_dns_record_set.a_record[0].name : "")
}
```
**What it demonstrates**: the sanctioned conditional-count pattern (0/1 ternary) in a remote module, plus the mandatory list-index guard ternary consumers need because the resource surfaces as a possibly-empty list.

## Reference Tables

**Meta-arguments and their use:**

| Meta-argument | Applies to | Use |
|---|---|---|
| `for_each` | resources, modules, dynamic blocks | Iteration; `each.key`/`each.value`; map or primitive-set values |
| `count` | resources, modules, dynamic blocks | Conditional blocks only (0 or 1, ternary); `count.index` |
| `depends_on` | resources, modules, outputs (list of refs) | Explicit dependency where inference is impossible |
| `lifecycle{}` | resources (rules), resources/data/ephemeral (conditions) | `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by`, `precondition{}`, `postcondition{}`, `destroy` (removed{} only) |
| `provider` | resources, data sources | Select provider config by alias |
| `providers` | modules | Declare available providers in a module |

**lifecycle rule selection:**

| Rule | Prefer when |
|---|---|
| `create_before_destroy` | No-downtime resources that safely coexist (stateless LB pools by tag/IP range) |
| `prevent_destroy` | Errant destroy causes major damage or exposes sensitive material |
| `ignore_changes` | External system mutates fields; change would force a recreate |
| `replace_triggered_by` | Field change means corruption, or immutable-resource deployments |

**Canonical block field order**: for_each/count → provider → one-line fields (required, identifying/placement first) → multiline collections → plain nested blocks → dynamic{} blocks → depends_on → lifecycle{}.

## Worked Example
Chapter 4's core refactor, run twice against the same GCP compute stack (VPC + instance + service account). *Before*: every resource reads `var.network_name` / `var.instance_name` etc. from shared tfvars (`network_name = "vpc-tas-4-1"`), and — in the depends_on variant — the instance bolts on `depends_on = [google_compute_network.vpc]` to force ordering. Both versions are fragile: shared-variable wiring carries no dependency edge (apply may fail when Terraform orders the instance first), and the explicit `depends_on` is unnecessary plan overhead. *After*: the instance's `network_interface { network = google_compute_network.vpc.name }` swaps the shared variable for the VPC's reference attribute, making the dependency implicit and the ordering guaranteed — no meta-argument needed. The lesson generalizes: when a reference attribute can express the relationship, refactor toward it and delete `depends_on`.

## Key Takeaways
- Prefer reference-attribute dependencies over `depends_on`; refactor organization rather than adding explicit edges.
- Implement outputs in every module (dedicated `outputs.tf`, grouped, ordered); expose whole resources/submodules where useful; use `precondition{}` to pin formats for downstream systems; mark genuinely secret values `sensitive` and ephemeral pass-through values `ephemeral` (it keeps them out of state).
- Keep one `locals.tf` with named, grouped, ordered locals; route all complex expressions through them; use locals to restructure third-party module outputs and to pin required constants for consumers.
- Use `for_each` for iteration (maps preferred; sets must be primitives); never use `count` for n>1 copies — only `? 1 : 0` conditionals, and avoid even those in root modules.
- Guard references to conditionally-created resources with ternaries or splat; reshape non-primitive collections into unique-keyed maps before iterating them.
- Apply lifecycle rules sparingly with published policy justification; use `postcondition{}`/`self` to validate TF-unmanaged attributes; remember `removed{}`'s `destroy` flag is fixed at first apply.
- Reach for `dynamic{}` only in genuinely variable nested-block scenarios (typical in remote modules), driven by map-shaped input variables with validation.
- Enforce a published field-order standard (meta-arguments → fields → blocks → depends_on → lifecycle), name everything snake_case and self-documentingly, and treat all TF code as production-ready — govern IaC with Kanban, not scrum.

## Connects To
- Ch2 (input variables) supplies the analogues this chapter leans on: `sensitive`/`ephemeral`/`description`/`validation` reappear on outputs; variable validation complements output `precondition{}`.
- Ch5 covers remote module development — why modules shouldn't mix `resource{}` and `module{}` blocks, `source` field submodule construction, and where `dynamic{}` blocks typically live.
- Ch6 explains TF state — the address model underlying `for_each` key requirements and count's fragility.
- Ch7 covers state surgery (`tf state rm`, `tf import`) for count↔for_each migrations and multi-state separation of concerns, plus multi-state/module-source arrangements.