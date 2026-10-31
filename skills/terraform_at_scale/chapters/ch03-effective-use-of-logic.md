# Chapter 3: Effective Use of Logic

## Core Idea

HCL is primarily a configuration language with functional-programming-style logic bolted on. Treat logic in Terraform as a bounded budget: the general recommendation is to externalize complex logic to ancillary tooling (Python/JavaScript in your automation context) rather than jamming it into HCL, but also never to retreat so far that logic scatters into pipeline YAML, Dockerfiles, and undocumented manual procedures. The goal is balance among logic internal to (`locals`, expressions), operating upon (preprocessing inputs / postprocessing outputs), and external to the Terraform codebase. Prefer named, decomposable local values over inline expressions; prefer deterministic construction of strings over runtime parsing of values; and scrutinize every "clever" function use for a simpler alternative before it becomes canon.

## Frameworks Introduced

- **The three-locus balance**: classify each piece of logic as internal to the codebase (HCL expressions/functions), operating upon it (tooling that generates variable inputs or interprets apply outputs), or external to it (CDK-style drivers, scripts, separate workloads). Choose the locus by testability — script logic can be debugged; HCL cannot.
- **Manual-process triage (three dimensions)**: rank manual procedures by *regularity* (how often), *protraction* (person-hours), and *time sensitivity* (risk grows with elapsed time). Encode anything hitting all three first, then the pairwise intersections; beyond that, the ordering dimension (single-dimension sweeps vs. tiered across all) is an organization-specific policy decision that needs material commitment from all responsible parties.
- **The Messy Middle**: early adoption = low variation (few teams, collective development); scale = many teams producing divergent conventions, with the best techniques often born in the most complex, most abstracted teams — not the central platform group. Counteract with standards, refactoring of deviations before they become canon, and debt mechanisms: clean-up sprints, improve-what-you-touch policies, refactor bounties.
- **Operator disposition ladder** (evaluation order, with per-tier guidance): `!`/`-` (reserve for flipping output values passed between blocks, and for enforcing the fixed `{1|0}` order in ternary-with-count standards) → `*`, `/`, `%` (magnitude conversion and uniform spreading) → `+`/`-` (sparse; only computed or well-defined offsets) → `>`, `>=`, `<`, `<=`, `==`, `!=`, `&&`, `||` (use freely in logic expressions).
- **for-expression output-type rule**: bracket syntax declares the output type — `[]` yields a list, `{}` yields a map. Use `{}` (map) output when constructing input for `for_each` (guarantees consistent construction order, Ch. 4); use `[]` (list) output when constructing module output values (more readable and more compressed) — or splat, where no filtering is needed.
- **Temporary-symbol conventions**: one symbol = the element's value; a second symbol makes the first the index/key and the second the value. Publish internal guidelines for *when* to use one vs. two symbols and *how* to name them (`k`/`v`, or expressive names describing key semantics and value purpose).
- **Ternary-as-guard pattern**: `POSSIBLY_NULL ? length(POSSIBLY_NULL) : 0` protects downstream fields from nulls — but use sparingly; heavy reliance on it signals an unwillingness to adopt variable validation, `try()`/`can()`, and the `optional` modifier.
- **regex skepticism rule**: apply "a great deal of skepticism" to any `regex()`/`regexall()` use; prefer `regexall()` (always returns a list, `[]` on no match) over `regex()` (returns string, list, or map — with named capture groups a map — requiring branching handling logic), but prefer a dedicated resource attribute or tag over regex entirely.

## Key Concepts

- **Functional style in HCL**: function results are not stored by default — inner-call results are consumed by the outer call and forgotten. Since HCL must also assign values to `resource{}`/`module{}` fields, use `locals{}` as the persistent store for intermediate calculation results.
- **`for` vs. `for_each`**: the `for` expression iterates *configuration metadata* (variables, outputs, locals) to marshal data; `for_each`/`count` iterate *configuration elements* (`resource{}`/`module{}` blocks). They are commonly co-located but address separate components — neither requires the other (Example 3-3 disproves the "kneejerk" coupling).
- **The `if` clause**: the `if` keyword does not branch execution paths; it only *filters* the result collection of a `for` expression. Multiple distinct filters of the same input become distinct if clauses in distinct named locals.
- **String interpolation vs. directives**: interpolation composes strings from parts (best for names/IDs/descriptions/tags, reducing the input-variable footprint under naming/tagging standards); directives (`%{ if }…%{ else }…%{ endif }`, `~` whitespace stripping) embed logic in the template. Prefer ternary + interpolation over directives: directives win only when the strings are long and highly similar; for short, divergent outcomes ("yes"/"no") use a ternary.
- **Splat expressions**: shorthand for extracting one field across a created collection; appropriate especially in module outputs feeding another module's input (subnets → one cluster per subnet), or human-readable reporting outputs. Limitation: splats cannot filter — for that, use a `for` expression with an `if` clause.
- **Encoding ≠ encryption**: nothing base64-encoded is secure in any way.
- **`can()` vs. `try()`**: both wrap error-prone expressions, but `can()` returns a Boolean and per TF docs is "intended only for simple tests in variable validation rules"; prefer `try()` elsewhere, and wrap only the narrow failing sub-expression rather than the whole complex expression.
- **Sensitivity functions**: `sensitive()` after value creation gives no guarantee of earlier protection — set sensitivity on the variable/output definitions; `nonsensitive()` is valid only where you derived a nonsensitive value from a sensitive one; `issensitive()` is a smell — investigate why the designation isn't already established at the definition site.
- **Time functions trap**: `timestamp()` evaluates freshly at apply (not in plan) and returns different values per invocation — pair with `ignore_changes`; `plantimestamp()` is the plan-time analogue for `check{}` assert conditions. Still, manage certificates, expiring policies, and other time-limited data outside Terraform.

## Mental Models

- **Each HCL function is a nested shell pipeline** (for the sysadmin): outer command with subcommands evaluated first and fed in as argument values. Or **a nested method chain** (for the OOP developer): chaining becomes nesting, inner result becomes outer argument. Neither nests comfortably; name every stage in `locals` instead.
- **The hammer problem**: mastering HCL logic tempts teams to shove all complexity into it ("a quagmire of configuration"); draconian rejection of it produces repetitive codebases or a wilderness of state trees. Both failures are real; aim between them.
- **Cloud consoles as memory, not oracle**: wizard-driven configurations work but conceal background components (e.g., a boot disk auto-created with a compute instance). Use system access logs to discover what a wizard actually created, then render every discovered component as a tracked resource in HCL.
- **Manual-first as specification**: manual configuration in exploratory phases teaches you the component inventory before you codify it — a legitimate stepping stone, not a destination.

## Anti-patterns

- **Excessive inline logic**: logic as a direct field assignment, especially `for/in` expressions inline outside `for_each` assignments. Why it fails: unreadable puzzles of text, undebuggable, unnameable, and referencing multiple variables compounds the problem. Fix: move to `locals{}` with meaningful names. (Note: evaluation of an expression during apply is delayed until all referenced resources are computed — inline references also entangle ordering.)
- **Implicit type conversion**: extracting numbers from strings like `myinstance_m32_d120` and assigning them to memory/disk-size fields. Why it fails: silently produces wrong types (e.g., alphanumeric residue) that may survive `plan` and only explode at apply. Fix: explicit `tostring()`/`tonumber()`/`tobool()` casts.
- **Ternary-null-guard sprawl**: sprinkling `possibly_null ? x : 0` guards everywhere. Why it fails: syntactically expensive, unsightly, and it substitutes for validation, nullable fields, and `optional` modifiers that modern TF provides — often a marker that a codebase is developmentally "stuck in an earlier version."
- **String-directive overuse**: `%{ if }` directives for short, divergent outputs. Why it fails: the template length makes the condition incomprehensible; a ternary + interpolation is simpler.
- **`nonsensitive()` indiscriminately applied**: suggests severe misapplication and can leak sensitive data into plain-text plan/apply logs.
- **Filesystem functions for run-time inputs**: `file()`/`fileexists()` for secrets or scripts — files must exist before Terraform acts, which breaks idempotence and fails hard when missing. Fix: templates/machine images for scripts; secret managers read directly by the platform; never a sensitive file on the TFC runner.
- **Complex length()-driven logic**: e.g., triggering quota-increase requests from resource counts in HCL. Why it fails: better handled as a follow-up automation step or an asynchronously approved workload with traceability and governance.
- **Unrestrained new-style expression mixing** (`count` pushed beyond `{0|1}` conditional format; conflating local values with variable defaults): each instance is cheap to fix but they congregate into patterns that hide mysterious, possibly nondeterministic behavior.

## Code Examples

Conditional resource creation with a fixed ternary order and negation (Example 3-1):

```hcl
resource "google_compute_firewall" "https" {
  count = !(var.http_only) ? 1 : 0

  name    = var.https_firewall_name
  network = var.vpc_network

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}
```

**What it demonstrates**: imposing a standard that ternary-with-`count` always reads `1 : 0` in a fixed order, using `!` when creation-depends-on-false — negation as style enforcement, not logic.

Modulo-based uniform spreading across three regions (Example 3-2):

```hcl
locals {
  three_supported_regions = slice(data.google_compute_regions.available.names, 0, 3)
}

resource "google_compute_instance" "instances" {
  for_each = { for idx, vm in var.vm_instance :
    vm.name => merge(vm, { index = idx }) }

  name         = each.value.name
  machine_type = each.value.machine_type
  zone         = local.three_supported_regions[each.value.index % 3]
}
```

**What it demonstrates**: map-form `for` output feeding `for_each`, `merge()` augmenting the element with its own index, and `%` spreading instances uniformly across a bounded region list.

All string construction centralized in `locals` (Example 3-9, abridged):

```hcl
locals {
  augmented_vms_map = {
    for vm in var.vms_map : vm => merge(
      vm,
      {
        name = join("-", [
          "vm",
          "${vm.app_id}",
          "${slice(vm.machine_type, 0, 2)}",
          "${slice(vm.zone, 0, 6)}"
        ])
        description = "Dedicated ${vm.machine_type} vm for app ${vm.app_id}"
      }
    )
  }
}

resource "google_compute_instance" "vms_collection" {
  for_each = local.augmented_vms_map

  name         = each.value.name
  description  = each.value.description
  zone         = each.value.zone
  machine_type = each.value.machine_type
}
```

**What it demonstrates**: the "locals-first" alternative to inline interpolation — a single augmentation pass over input data, leaving the `resource{}` block field-assignments only, so intricate naming logic stays readable and traceable.

Safe vs. unsafe `try()` placement (Example 3-21):

```hcl
try(tostring(local.raw_value.name), null)
# This might not always be safe

tostring(try(local.raw_value.name, null))
# This is much safer
```

**What it demonstrates**: wrap only the failing attribute reference, not the whole expression — the TF-docs guidance that `try()` belongs around simple attribute references and type-conversion calls.

## Reference Tables

HCL function dispositions (this chapter's verdicts):

| Function(s) | Disposition |
|---|---|
| `concat()`, `merge()`, `distinct()` | Core — combine/mask configuration from multiple sources; `merge()` masks by last-position-wins; wrap `concat()` in `distinct()` for set-like behavior |
| `keys()`/`values()`, `zipmap()`, `matchkeys()` | Useful for map↔list reshaping; prefer `for` + `if` over `matchkeys` for readability |
| `setintersection()`, `setunion()`, `setsubtract()`, `setproduct()` | Niche — set theory on module outputs; `setproduct()` only for "one resource per combination" factories |
| `transpose()` | Niche — flip map-of-lists inside out (VPCs-by-region from regions-per-VPC) |
| `compact()`, `flatten()`, `sort()`, `reverse()` | Cleanup of iteration/`splat` results and human-facing outputs |
| `element()`, `lookup()` | Safer than bracket notation: `element()` wraps mod-length; `lookup()` supplies a key-miss default (mostly for inconsistent third-party outputs) |
| `alltrue()`, `anytrue()`, `contains()` | Aggregate indicators for module outputs |
| `range()`, `chunklist()`, `coalesce()`, `coalescelist()`, `one()`, `slice()`, `index()` | Suspect — prefer external logic; `slice()` exception: bounding provider data sources (regions/AZs) |
| `length()` | Strings: only in variable validation (min) / with `substr()` (max). Collections: aggregate metrics as outputs |
| `substr()` | Capping interpolated name lengths against platform/policy limits — but only when inputs come from resource/module outputs, not root-module variables |
| `strcontains()`, `startswith()`, `endswith()`, `regex()`, `regexall()` | Limited/skeptical — prefer a tag or dedicated attribute |
| `toset()` | Workhorse — dedupe and normalize third-party output for `for_each` |
| `tolist()`, `tomap()` | Marshaling only (implicit conversion; neither preserves order) |
| `tostring()`, `tonumber()`, `tobool()` | Prefer over `"${x}"` interpolation for casts; all error on non-primitive input |
| `parseint()` | Non-decimal bases (2–62); hex/binary from attributes |
| `can()` / `try()` | `can()`: variable-validation rules only; `try()`: everything else |
| `sensitive()` / `nonsensitive()` / `issensitive()` | Ideally never necessary — set sensitivity at definitions; each is a last resort |
| `rsadecrypt()` | Only decryption exists in HCL — so encrypt (and by symmetry decrypt) outside TF |
| `cidrhost()`, `cidrnetmask()`, `cidrsubnet()`, `cidrsubnets()` | Policy-driven host IPs, CIDR→mask, block subdivision; externally tracked by network team except for factory-pattern network replication |
| `formatdate()`, `timestamp()`, `plantimestamp()`, `timeadd()`, `timecmp()` | Format conversion and expiry assertions — but time-limited/sensitive data belongs outside TF |

## Worked Example

The subnet-factory module chain (Examples 3-12 and 3-20): a `network` module takes `vpc_name` and a regions list, creates VPCs and subnetworks, and exposes one splat output — `output "subnet_names" { value = google_compute_subnetwork.snets[*].name }`. The root module then creates one GKE cluster per subnet with no collection plumbing of its own:

```hcl
module "network" {
  source  = "../network"
  vpc_name = "vpc-tas-3-2"
  regions  = ["us-central1", "us-east1", "us-west1"]
}

module "gke" {
  for_each    = module.network.subnet_names
  source      = "../cluster"
  subnet_name = each.value
}
```

The point: the producer module does the collection work once via splat, and the consumer module iterates with `for_each` directly — no nested `for` expression in between. Where a duplicate-prone value like regions is needed instead, the consumer normalizes it at the boundary: `for_each = toset(module.network.subnets[*].region)`, which both dedupes and sidesteps ordering instability (neither `tolist()` nor `toset()` preserves order).

## Key Takeaways

- Put logic in `locals{}` with expressive names; allow inline interpolation only by explicit standard (e.g., name/description fields inside `for_each` blocks) — and never inline `for` expressions outside `for_each` assignments.
- Respect the ternary-with-`count` convention: always `? 1 : 0`, negating the boolean rather than flipping the branch order.
- Don't nest `for` expressions — one named local per expression; don't reflexively pair `for` with `for_each`; the `if` clause is a filter, not a branch.
- Construct strings deterministically from root-module inputs + variable validation when you can; reach for `substr()`/`length()` only when values arrive from resources or third-party modules.
- Convert types explicitly; prefer `regexall()` over `regex()` if you must regex at all; prefer `try()` (narrowly placed) over `can()` everywhere except variable validation.
- Externalize what HCL does poorly: heavy string cleaning, encryption, secret handling, certificates, CIDR planning, timestamp-driven lifecycles. If a procedure is regular, protracted, and tedious, encode it; if a value can't be idempotently reproduced at plan time, it probably shouldn't be in Terraform.
- Budget your refactor debt deliberately (clean-up sprints, improve-what-you-touch, refactor bounties) and fix deviations from standards before they become canon.

## Connects To

- **Ch. 2** — variable validation condition expressions (`length()`, `can()`) and the `optional` modifier as the sanctioned alternative to ternary null-guarding.
- **Ch. 4** — why map-form `for` output yields consistent resource construction order, `local` values and outputs in depth, the `ephemeral` keyword, and sensitive outputs.
- **Ch. 6** — evolving module variable/output types safely (add new typed variables; deprecate rather than mutate) and third-party module quality practices that determine how much boundary-casting your code must do.
- **Ch. 7** — cross-project dependencies and cascading changes (why some manual procedures stay manual), wildcard jobs, `.tfvars` sharing across teams, and the one-off operations that violate Terraform's idempotent model.