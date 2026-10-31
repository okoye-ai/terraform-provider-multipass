# Chapter 2: Input Variables

## Core Idea
Input variables are more than abstraction mechanisms for parameterizing Terraform configuration — they are a governance surface. A well-designed `variable {}` block encodes type constraints, defaults, validation logic, sensitivity, and nullability, giving module consumers an explicit contract surfaced at the *plan* phase rather than as apply-time failures. Because HCL admits many functionally equivalent constructions of the same execution plan, teams must impose conventions (type declarations, descriptions, validation) that make intent explicit — Terraform itself will not.

Use input variables early, not retroactively. For projects intended to be preserved, introduce variables at project inception, not after hardcoded values calcify.

## Frameworks Introduced
- **The seven ways to set variable values** (mix them; each has a distinct owner and volatility profile):
  1. **`.tfvars` files** — root module only; values the *module's own development team* controls and that may change.
  2. **Environment variables (`TF_VAR_name`)** — root module only; team-specific, platform-level config (region, subnetwork, project ID) owned by another team, rarely changing.
  3. **CLI `-var` flag** — custom automation-platform overrides, self-service configs, testing a module without a source-control edit.
  4. **Default values** — highly prevalent or effective-optional cases only.
  5. **Module fields** — the only way to pass information into a nested module (referenced via `module {}` `source`).
  6. **Workspace variables** (HCP Terraform/TFE) — type *Terraform* (like `-var`) or *Environment* (`TF_VAR_` prefix); can be marked sensitive directly in the UI, superseding the `variable {}` setting.
  7. **Variable sets** (HCP Terraform/TFE) — config shared across workspaces, e.g., org-level information; can be marked sensitive in the interface.

- **The seven optional fields of `variable {}`**: `description`, `type`, `default`, `validation {}` (nested block: `condition` + `error_message`, both required), `ephemeral`, `sensitive`, `nullable`. All fields are optional; none are required.

- **Defense-in-depth framing for `validation {}`**: conditions supplement genuine reviews and codified CSP policy, adding a control layer within one system (Terraform) that overlaps others (firewall policies, service perimeters). Accept diminishing returns — layering controls ad infinitum is Zeno's arrow: never reaching perfect coverage, not cost-effective, at risk of a zero-day in any one layer, and at risk of being *too strict* and blocking legitimate business practice (forcing exceptions to be carved afterward).

- **Type system taxonomy**: primitive types (string, number, bool) → type constructors (list(), set, map(), object(), tuple()) → the `any` placeholder.

## Key Concepts
- **Functionally equivalent HCL configurations**: omitting a field (letting it default) vs. explicitly setting it to the default produce equivalent execution plans; and two fields may appear differently in the plan yet produce equivalent results (e.g., a firewall `network` referencing a VPC by `.name` vs `.self_link`). Consequence: agree on conventions, constructions, and style — consider a Terraform style guide.
- **Variables enable reuse principles**: SRP, DRY, principle of least privilege — the same module produces different execution plans with different `.tfvars` values.
- **`ephemeral`** (HCP Terraform/TFE only): value not preserved in the TF state object. Best for informative values computed from environmental factors that may not be reproducible — avoids false drift reports. (See Chapter 7 on state.)
- **`sensitive`**: only suppresses CLI printing; not meaningful protection. Layer secret management, access control, encryption separately.
- **`nullable = false`**: strengthens the type by rejecting `null`, requiring a proper value (e.g., the type's unity element).
- **Unity elements** as conditional-resource control: `''` (empty string) for string, `0` for number, `[]`/`{}` for collections. Pair a variable against its unity element in a `count` meta-argument or ternary to make a resource conditional.
- **Minimum variable definition**: `description` + `type` should be present on every `variable {}` block. `validation {}` is valuable for tightly controlled/standardized formats but mandating it for *every* field errs toward overengineering. `default` only when effectively optional (set to the type's unity element) or a genuinely standard value exists. Use `ephemeral`/`sensitive` only where necessary.
- **Type declaration mirrors downstream consumers**: reflect the types of the provider/resource fields or nested module variables your variable feeds. Align variable construction with the meta-arguments that consume it — `count`/`for_each` need list, set, or map types — so the module avoids inline logic and extra `local` values.
- **`any` type**: equivalent to omitting `type` entirely. Appropriate only as an intermediate step while a type's shape is unstable; avoid nesting `any` inside larger type constructs. Note `map(any)` still requires all values to share one consistent type.
- **`type()` function**: available only in the `terraform console` shell. Print an `any`-typed value to see its fully specified type, then paste it directly into the `type` field (generalizing collection types if appropriate) — the fastest path from placeholder to fully specified type.
- **Validation timing**: `validation {}` conditions are checked at the *plan* phase, not apply. Running `terraform plan` in pull/merge requests catches out-of-policy values before code reaches a branch targeted for `terraform apply` — saving hours of build time and reverting headaches.
- **`error_message` best practices**: explain both *why* the value failed and *what* the variable expects. Use `join(" ", [...])` to compose messages; embed interpolated values (e.g., `"${var.special_s3_type ? "spc-" : "crp-"}"`) to state the exact expectation. For internal modules, link to an internal policy page; for CSP constraints, link to the public documentation (e.g., AWS bucket naming rules). Especially important when an intermediate module wraps a third-party module and obscures the underlying failure.
- **Pareto-Principle validation design**: with complex composite types, constraint complexity compounds per field and error messages must cover every failure mode. Aim to catch the most common or most costly problems, not all of them. Where constraints are not well defined, adopt an iterative quality strategy: encode a `validation {}` for each issue that escapes to apply, so it never gets that far again — rather than writing over-general or overly non-exhaustive conditions up front.

## Mental Models
- **Variable definition as API contract**: the `type` field is documentation that module consumers read instead of reverse-engineering the dependency chain. Declared types also make later shape changes granular and trackable.
- **Value-setting as ownership matrix**: assign each variable to the team that owns its volatility — dev team controls `.tfvars`; infra-ops controls env vars/CLI/workspace variables; defaults are curated in remote modules.

  A typical mature configuration mixes: project-specific `.tfvars` (possibly passed via CLI arg) + env vars/`-var`/workspace variables set by the infrastructure-operations team (e.g., target deployment environment) + defaults set in remote modules and curated by infra-ops.
- **Complexity placement choice for composite variables** (three-way decision):
  1. **Refactor into simple variables assembled in a `locals` block** (preferred) — build the object from primitive variables in HCL, pass `local.*` to the module.
  2. **Expose the complex variable all the way to the root module** — appears to merely shift the problem, but if it introduces no repeated information, it beats encoding excessive data manipulation in HCL.
  3. **Keep inline logic** in the module when the burden on operators is acceptable.

  Use option 2 over 1 when mirroring nested-module variables verbatim creates no duplication; otherwise prefer flattening into locals.
- **Validation as self-documentation**: a readable `condition` teaches engineers which values are appropriate, independent of any documentation.

## Anti-patterns
- **Empty `variable {}` blocks** (`variable "x" {}`): no required fields makes this legal, and it is probably *the most common* use of variables — and the laziest. Acceptable only as a placeholder at a variable's earliest development stage; never in configurations supporting organizational workloads. There is no good reason to maintain a variable without explicit type and sufficient description.
- **Overusing `any`**: in mature codebases there are very few good reasons, and under a type-required policy it becomes a workaround that undermines the policy. Never use `any` to hide or relax composite-variable complexity — even when input data comes from a software process you don't control. Prepare input data deterministically *outside* the module, in the correct shape, before supplying it. If `any` persists, treat it as tracked technical debt (pay down in scheduled work, not left for months); ideally have a policy that raises a noticeable — not log-buried — warning when `any` appears.
- **Overusing composite variable types**: bundling every field of a *unique* configuration (e.g., a one-off security appliance's instance settings: ami, instance_type, subnet_id, core_count, tags…) into one `object()` vastly reduces clarity. Bundle only when the variable feeds a collection (`for_each`), a conditional (`count`), when the nested module's variables are simple/flat, or when several nested modules share genuinely similar inputs. Otherwise mirror the nested module's variables as variables in the outer module.
- **Mixing essential and nonessential data in composite variables**: when a composite variable backs module fields that themselves have defaults, the composite's default must mirror each default — changing the module default now requires coordinated changes everywhere, and any `validation {}` conditions from the third-party module must be re-reflected (and compounded) in the referencing context.
- **Misusing `default` values**: do not use a `default` as a pseudo-hardcode — the value is still overwritable by any consumer, and there is no protection. Guarding it with git hooks (warning or blocking commits) becomes an arms race as new instances appear. Use a **local value** instead (Chapter 4). Also avoid defaults for highly varied or volatile values (e.g., a modifiable list of network tags): beyond overengineering, it invites less-astute consumers to overlook a variable that really must be set.
- **`tuple()` in general**: not worth using over `object()` except where a highly structured automated system marshals data directly into a fixed-length, mixed-type format and re-marshalling is too costly.
- **Draconian validation coverage**: requiring a `validation {}` block on every variable, or conditions that are overly general/non-exhaustive, adds complexity without coverage; validation expressions are hard to debug when incomplete.

## Code Examples
Unity element as conditional-resource control:

```hcl
variable "conditional_name_variable_ec2" {
  description = "set this to any valid string to create the EC2 resource"
  type        = string
  default     = ""
}

resource "aws_instance" "conditional_ec2_instance" {
  count = var.conditional_name_variable_ec2 == "" ? 0 : 1

  ami           = var.default_ami
  instance_type = "t2.micro"

  tags = {
    Name = var.conditional_name_variable_ec2
  }
}
```
**What it demonstrates**: pairing a string variable's unity element (`''`) with a ternary-driven `count` to make resource creation conditional — no boolean flag variable needed.

Pareto-style constraint encoding for a CSP + corporate standard:

```hcl
variable "s3_bucket" {
  description = "validation encodes CSP constraints and corporate standards"
  type        = string

  validation {
    condition = ((length(var.s3_bucket) > 2 && length(var.s3_bucket) < 64)
      && (length(regexall("^[a-z0-9-]+$", var.s3_bucket)) > 0)
      && (length(regexall("^[a-z0-9]", var.s3_bucket)) > 0)
      && (length(regexall("[a-z0-9]$", var.s3_bucket)) > 0)
      # some CSP constraints above, corporate constraints below
      && (length(regexall("\.", var.s3_bucket)) == 0)
      && (length(regexall("^(pub|prv)(-[a-z0-9]+)*$", var.s3_bucket)) > 0)
      && (length(regexall("^[a-z0-9]+-(na|eu|ap)(-[a-z0-9]+)*$", var.s3_bucket)) > 0)
      && (length(regexall("-", var.s3_bucket)) > 1)
      ...
    )
  }
}
```
**What it demonstrates**: stitching `regexall`-based sub-checks with `&&` to layer AWS naming rules (length, charset, boundary characters) above organization-specific standards (disallowed characters, an environment prefix, required region substring, minimum hyphenation) — validation as executable policy documentation.

Composite-type validation with per-field subexpressions:

```hcl
variable "ntwrk_info" {
  description = "Contains several configurations for a VPC"
  type = object({
    vpc_region = string
    acl_list   = list(map(string))
    ...
  })
  validation = {
    condition = ((contains(["us-east-2", "us-west-2"], var.ntwrk_info.vpc_region))
      && (length(var.ntwrk_info.acl_list) > 0 ?
          (var.ntwrk_info.acl_list[0]["direction"] == "ingress"
            || var.ntwrk_info.acl_list[0]["direction"] == "egress")
          && (var.ntwrk_info.acl_list[0]["action"] == "allow"
            || var.ntwrk_info.acl_list[0]["action"] == "deny"))
      : true)
    error_message = join(" ", [
      "The region must be 'us-east-2' or 'us-west-2' and each item in the",
      "acl_list should have the 'direction' and 'action' keys"
    ])
  }
}
```
**What it demonstrates**: conditional guard (`length(...) > 0 ? ... : true`) plus per-subfield checks on an `object()` variable, with an `error_message` built via `join(" ", [...])` that states both halves of the expectation.

Interpolated, self-explaining error message:

```hcl
validation {
  condition     = (var.special_s3_type ?
    (startswith(var.dependent_s3_bucket, "spc-"))
    : (startswith(var.dependent_s3_bucket, "crp-")))
  error_message = join(" ", [
    "since special_s3_type is ${var.special_s3_type}, dependent_s3_bucket must",
    "begin with \"${var.special_s3_type ? "spc-" : "crp-"}\""
  ])
}
```
**What it demonstrates**: cross-variable validation (a condition referencing *other* variables — use sparingly) plus a message that interpolates the controlling value to name the exact required prefix.

## Reference Tables
**Primitive types and their unity elements** (unity elements drive conditional-resource logic):

| Type | Accepts | Auto-conversion | Unity element |
|---|---|---|---|
| `string` | any string, incl. long; no encoding distinctions | number/bool → string representation | `''` |
| `number` | integers and rationals | string-encoded number → number | `0` |
| `bool` | true/false | `'true'`/`'false'` → boolean | — |

**Type constructors**:

| Constructor | Behavior | Notes |
|---|---|---|
| `list(T)` | uniform list of one type | ideal for `for/in` iteration |
| `set` | like list but values must be unique | |
| `map(T)` | string keys, uniform `T` values | pair with `for_each` for unique, non-sequential state keys |
| `object({...})` | explicit named keys, per-key types (nestable) | for bundling related heterogeneous data (disk block size + type) |
| `tuple(...)` | static length, differentiated per-index types | avoid except for machine-marshalled data |

**Fields of `variable {}` and when to use each**:

| Field | Effect | Use when |
|---|---|---|
| `description` | documents variable, phrased from end-user perspective | always (with `type`) |
| `type` | constrains assignable values; auto-converts primitives | always; mirror the consuming resource/module field type |
| `default` | used when unset in tfvars/CLI/module | rare/standard values or effective-optional (unity element) |
| `validation {}` | `condition` (bool expression) + `error_message` (string expression), both required | restricted/standardized values; third-party-consumed modules; org policy |
| `ephemeral` | value not kept in state (HCP Terraform/TFE only) | informative, environment-computed, non-reproducible values |
| `sensitive` | suppresses CLI printing only | pair with real secret management/access control/encryption |
| `nullable` | `false` rejects `null` values | strengthening an explicit type |

## Worked Example
Refactoring an overly complex variable construct (Chapter's central before/after sequence):

**Before** — a third-party module expects a nested object; the consuming module declares one giant `object()`-typed variable and passes it straight through:

```hcl
variable "complex_module_variable" {
  description = "This variable might be too complex"
  type = object({
    string_key     = string
    number_map_key = map(number)
    object_key     = object({
      number_sub_key     = number
      stringList_sub_key = list(string)
    })
  })
}

module "module_with_complex_variable" {
  source               = "third-party-module-tas-2-4"
  complex_module_field = var.complex_module_variable
}
```

The burden of constructing this value now falls on every operator of the module.

**After (preferred)** — flatten into primitive variables, assemble in `locals`, pass the local:

```hcl
locals {
  complex_module_local = {
    string_key     = var.string_key_var
    number_map_key = var.number_map_key_var
    object_key     = {
      number_sub_key      = var.number_sub_key_var
      string_list_sub_key = var.string_list_sub_key_var
    }
  }
}

module "module_with_complex_local_value" {
  source               = "third-party-module-tas-2-4"
  complex_module_field = local.complex_module_local
}
```
with individual `variable {}` blocks (`string_key_var : string`, `number_map_key_var : map(number)`, `number_sub_key_var : number`, `string_list_sub_key_var : list(string)`), each described and typed for the consumer.

**Third option** — if no information is repeated, pass the *same* complex type through: declare it identically at the root module and in the nested module, so the root supplies it verbatim and no data manipulation is encoded in HCL. The author judges this acceptable precisely because it avoids repetition — the composite shape travels untransformed from root to submodule.

## Key Takeaways
- Every `variable {}` block should carry `description` and `type` at minimum; all seven fields are optional, so nothing enforces this — treat it as a team convention.
- Match each variable's setting mechanism to ownership and volatility: `.tfvars` (dev team, changeable), `TF_VAR_` env vars (other team, platform-level, rare change), `-var` (automation/testing), module fields (nested-module inputs), workspace variables/variable sets (HCP Terraform/TFE).
- Prefer declared composite types over `any` and over no type at all; `object()` for related heterogeneous data, `map()`/`list()` to feed `for_each`/`count` directly, `tuple()` almost never.
- Convert any transient `any` placeholder into a fully specified type using `type()` from the `terraform console`, then track shape changes granularly.
- Validate at plan time: `validation {}` conditions fail before apply, so `terraform plan` in PRs blocks policy violations pre-commit. Encode one rule per escaped issue iteratively rather than writing exhaustive conditions up front.
- Write `error_message`s that say why the value failed and what is expected; link to internal policy pages or public CSP docs (e.g., S3 naming rules) via `join(" ", [...])`.
- Design validation with the Pareto Principle: compound complexity per object-field is undebuggable; catch the most common/costly failures, not every hypothetical one.
- Bundle fields into a composite variable only when they feed a collection or are shared across modules; one-off unique configurations should use simple, flat variables.
- Never hardcode via `default` — defaults are overwritable and their protection invites an arms race; use local values for fixed data.
- Functionally equivalent HCL plans mean style is the team's responsibility: omitting a field vs. setting its default, or referencing a resource by `.name` vs `.self_link`, are plan-equivalent — so pick one convention and enforce it.

## Connects To
- **Ch 1**: execution plans (immutable once constructed) and multiple HCL routes to the same plan; `.tfvars`/`.tfvars.json` evaluation.
- **Ch 3**: TF logic — functions, expressions, operations (the `regexall`, `startswith`, ternary, and `for/in` machinery used inside validation conditions).
- **Ch 4**: local values — the recommended replacement for pseudo-hardcoded defaults and for assembling complex objects from simple variables.
- **Ch 7**: the TF state object — which `ephemeral` variables are excluded from, and where false drift would otherwise appear.
- **Cross-cutting**: modules and `module {}` block `source` fields (remote/third-party modules, intermediate wrapping modules), `count`/`for_each` meta-arguments, HCP Terraform/TFE workspace variables and variable sets.