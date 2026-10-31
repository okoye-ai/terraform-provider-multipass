# Chapter 3: Functional programming

## Core Idea
Terraform is a functional language: variables are a function's arguments, locals are its temporary symbols, outputs are its return values — and logic is expressed with pure functions, for expressions, and templates, never procedural control flow.

## Frameworks Introduced
- **The Three Variable Analogies**: `variable` = function argument · `locals` = function local symbols · `output` = function return value
  - Use as the mental model for deciding where a value belongs in module design
- **Implicit vs Explicit Dependencies**: interpolating one resource's attribute into another creates an implicit dependency (preferred); `depends_on` declares an explicit one for relationships Terraform can't see
  - Rule: prefer implicit; if forced to use `depends_on` (e.g. an archive_file zip needing local_files written first), document why
- **Pure Function Discipline**: Terraform functions must be pure so plans converge; only `uuid()` and `timestamp()` are impure — avoid both (plans never converge → subtle bugs); get randomness via the **Random provider** (`random_shuffle`, `random_string`, ...) whose results are persisted in state
- **for Expressions** (lambda-like): `[for s in list : expr]` → list; `{for k,v in map : k => expr}` → object; optional `if` filter clause. Composable into higher-order functions, but composed for expressions hurt readability — don't overuse

## Key Concepts
- **Variable block arguments**: `default` (empty mandatory), `description`, `type` (primitives + list/set/map/object/tuple), `validation` (nested blocks with `condition`/`error_message`, unlimited in number)
- **tfvars files**: assign variable values in `*.tfvars` / `*.tfvars.json` — better than defaults because it doesn't harm reuse; referenced values are `var.<name>`
- **Type coercion**: any primitive converts to string (true→"true", 17→"17"); happens silently in interpolation — beware `17 == "17"` is false
- **templatefile(path, vars)**: ~100 built-in functions exist, no user-defined functions; templating scoped only to the passed-in vars map; templates use `${...}` like interpolation
- **count meta argument**: scales to N instances; address instances with `[N]` bracket notation; current index is `count.index`
- **element(list, i)**: treats the list as circular (no out-of-bounds) — the idiom for cycling N items across a K-slot template list
- **Dependent resource lists stay in sync**: when two resources both use `count`, index `[i]` must pair them (chained via `random_shuffle.random_nouns[count.index].result`)
- **fileset() / tolist()**: `fileset` returns a set (cast with `tolist()`), e.g. `tolist(fileset(path.module, "templates/*.txt"))`

## Code Examples
```hcl
# Higher-order for: uppercase every word in every list, save to a local
locals {
  uppercase_words = { for k, v in var.words : k => [for s in v : upper(s)] }
}

# Validation block on a variable
variable "words" {
  type = object({ nouns = list(string), /* ... */ })
  validation {
    condition     = length(var.words["nouns"]) >= 20
    error_message = "At least 20 nouns must be supplied."
  }
}

# Conditional-create idiom
count = var.shuffle_enabled ? 1 : 0

# Cycle K templates across N generated files with count.index
resource "local_file" "mad_libs" {
  count    = var.num_files
  filename = "madlibs/madlibs-${count.index}.txt"
  content  = templatefile(element(local.templates, count.index), {
    nouns = random_shuffle.random_nouns[count.index].result
  })
}

# Zip results; explicit dependency because archive_file has no sensible input to chain
data "archive_file" "mad_libs" {
  depends_on  = [local_file.mad_libs]
  type        = "zip"
  source_dir  = "${path.module}/madlibs"
  output_path = "${path.cwd}/madlibs.zip"
}
```
- **What it demonstrates**: the Mad Libs generator — the chapter's worked artifact for composing var → local (for) → resource (count) → templatefile → local_file → archive_file

## Reference Tables (Expression Reference, table 3.1)
| Expression | Purpose | Example |
|---|---|---|
| Conditional | pick one of two values on a boolean | `cond ? a : b` |
| Function call | transform/combine values | `max(a, b)` |
| for expression | one complex type → another | `[for s in var.list : upper(s)]` |
| Splat | shorthand gather of attribute | `var.list[*].id` ≡ `[for s in var.list : s.id]` |
| Dynamic block | repeatable nested blocks | `dynamic "ingress" { for_each = ... }` (ch7) |
| String interpolation | embed expressions in strings | `"Hello, ${var.name}!"` |
| Template directives | iterate/branch inside strings | `%{ for ip in var.list.*.ip } ... %{ endfor }` |

## Worked Example
The 100-story Mad Libs pipeline end-to-end: input variable of five word lists (tfvars) → for-expression local uppercasing → five count-scoped random_shuffle resources → fileset() discovering three templates → 100 local_file resources cycling templates via `element(..., count.index)` and indexing shuffles by `count.index` → archive_file zipping via `depends_on`. Result: "Apply complete! Resources: 600 added" (data sources aren't counted as added resources, and `terraform destroy` won't delete madlibs.zip because the data source implements no Delete()).

## Key Takeaways
1. Put logic in locals/expressions, configuration in variables, results in outputs — like function args/locals/returns.
2. Never use `uuid()` or `timestamp()`; use the Random provider for state-backed randomness.
3. `count` + `count.index` is the core scaling pattern; chain resource lists index-for-index.
4. Prefer implicit dependencies; explicit `depends_on` only when no attribute can chain, and document it.
5. Validation belongs in variable `validation` blocks — unlimited, fine-grained, fails fast with a good error.

## Connects To
- **Ch 4**: modules where variables/outputs become the module interface
- **Ch 7**: for_each (the keyed alternative to count) and dynamic blocks
- **Ch 13**: Random-provider-generated secrets require securing state and plan files