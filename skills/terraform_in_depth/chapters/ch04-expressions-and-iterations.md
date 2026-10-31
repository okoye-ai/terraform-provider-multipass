# Chapter 4: Expressions and iterations

## Core Idea
Terraform iterates and branches not with loops but with meta parameters (`count`, `for_each`), data-transforming `for` expressions, and dynamic blocks — and because Terraform is declarative, functions exist only to transform data, never to take action.

## Frameworks Introduced
- **Module research process** (figure 4.1): Change Desired -> Research -> Plan Changes -> Implement Module / Test Locally -> Publish
  - When to use: any time you are asked to add a capability to a module you have not built before.
  - How: read the service documentation (e.g. EC2), look up the Terraform provider resources/features, then search blogs, Stack Overflow, Reddit, and tutorials. Research expands recursively as you discover new concepts (tags -> name tags -> IAM -> Systems Manager).
- **Function categories (the standard library)**: Numeric, String, Collection, Encoding, Filesystem, Date and time, Hash and cryptography, IP network functions, Type conversion
  - When to use: whenever configuration values must be computed at plan time rather than hardcoded.
  - How: only the built-in standard library existed until Terraform/OpenTofu v1.8, when providers gained the ability to ship their own functions.
- **Pure vs. impure functions**: pure functions return the same value for the same inputs (2+2 is always 4); impure functions (e.g. `uuid()`, `timestamp()`) return different results each call.
  - When to use the model: diagnosing code that shows changes immediately after every apply.
  - How: if an impure function is part of a resource's configuration, "the second the Terraform apply is run, the workspace is already out of date" — replace the function with a resource from the `random` or `time` providers.
- **Two forms of iteration** (section 4.8): (1) creating multiple resources at once — `count` and `for_each` meta parameters; (2) transforming groups of data — the `for` expression.
  - When to use: at most one of `count`/`for_each` may appear on a block; using both errors.

## Key Concepts
- **count meta parameter**: takes an integer and creates that many copies of a resource or module block, exposing `count.index` (zero-based) inside the block.
- **for_each meta parameter**: takes an object, map, or set (never a bare list — convert with `toset`) and exposes `each.key`/`each.value` so every created instance gets its own configuration.
- **for expression**: runs a transformation on every item in a group and returns a new list `[for x in l : ...]` or object `{ for x in l : k => ... }`, with optional `if` filtering and `...` grouping mode.
- **Grouping mode**: an ellipsis after a for-expression's value (`key => value...`) lets the same key repeat so results accumulate into lists across iterations.
- **Splat expression**: `var.items[*].id` — removes "a lot of boilerplate around a fairly common operation"; also turns a single value into a one-item list (`var.security_group_id[*]`).
- **Conditional expression (Terraform's ternary)**: `condition ? true_value : false_value` — Terraform's only branching operator; its toggle idiom is `count = var.enabled ? 1 : 0`.
- **Dynamic block**: `dynamic "<subblock>" { for_each = ... content { ... } }` generates zero-or-more subblocks; confusingly, its iterator keyword is named after the block itself (e.g. `ingress.value`), not `each`.
- **try / can**: `try(expr, default)` returns the first argument that does not error; `can(expr)` converts an error into a boolean and is meant almost exclusively for `validation` blocks.
- **sensitive / nonsensitive functions**: return a *new* value with the sensitivity flag changed — declarative languages cannot mutate a variable in place.
- **templatefile function**: takes a template path plus a map of variables and evaluates interpolations/directives (`${...}`, `%{ if }`, `%{ for }`) to produce configuration strings.

## Mental Models
- Use **count-as-toggle** when a module feature is on/off: accept a `bool` variable and convert true/false into 1/0 via ternary passed to `count` — "a much nicer interface for users for resources that can only be turned on and off."
- Think of **plan-time knowledge** as a hard boundary: `count` and `for_each` values must be known at the start of the plan; resource attributes and impure functions cannot feed them.
- Think of **modules as a fiction in the graph**: module boundaries disappear under the hood, so resource in module B can be created before resources in module A it does not actually depend on.
- Prefer **native encoding over templates**: where Terraform natively understands a format (JSON, YAML, IAM policy documents), use `jsonencode`/`yamlencode`/validating data sources — hand-built template strings are "ugly and error prone."
- Remember **equality checks do not type-convert**: `"15" == 15` is false; explicitly cast (`tonumber`/`tostring`) or compare values whose types you control.

## Anti-patterns
- **Using `uuid()` or `timestamp()` in resource configuration**: every plan detects a change (`tags = { id = uuid() }` will "have a new value every plan"); use the `random`/`time` provider resources instead.
- **Using the deprecated `template_file` resource**: no longer maintained and will likely be removed; replace with `templatefile` whenever you see it in old modules.
- **Building JSON/YAML/IAM policies with string templates**: produces malformed data; store the data as an object in code and encode it, or use a validating data source.
- **Batching plans via resource targeting to dodge the plan-time limit** — "a horrible practice": it bootstraps modules that cannot run normally; refactor instead.
- **Using `can` outside validation blocks**: if you want error tolerance elsewhere, you want `try`; and never use either to hide a real error.
- **Relying on implicit operator precedence**: `confusing = 2 + 4 / 5 * var.multiple ? 4 : 9 - 7` is legal but unreadable — add parentheses even when they don't change logic.
- **Using `nonsensitive` to unmark values** without documented justification: you may leak values that belong out of logs; needing `sensitive` may mean the variable itself should have been flagged.

## Code Examples
- **What it demonstrates**: expanding an instance module in one step — whole-number validation, unique names via `count.index`, merged tags, and Systems Manager toggled by a boolean.

```hcl
variable "instance_count" {
  type        = number
  default     = 0
  validation {
    condition     = can(parseint(tostring(var.instance_count), 10))
    error_message = "The instance count must be a whole number."
  }
  validation {
    condition     = var.instance_count >= 0
    error_message = "The instance count can not be negative."
  }
}

resource "aws_instance" "hello_world" {
  count                = var.instance_count
  ami                  = data.aws_ami.ubuntu.id
  subnet_id            = var.subnet_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.main.name
  tags = merge(var.tags, { Name = "${var.name_prefix}-${count.index}" })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  count      = var.enable_systems_manager ? 1 : 0
  role       = aws_iam_role.main.name
  policy_arn = data.aws_iam_policy.ssm_arn.arn
}
```

- **What it demonstrates**: dynamic blocks — "the most confusing syntax in all of Terraform" — generating `ingress` subblocks from a variable and mixing with a static block.

```hcl
resource "aws_security_group" "main" {
  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  dynamic "ingress" {
    for_each = var.security_group_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

## Reference Tables
**Operators** (tables 4.1-4.3): `+ - * / %` arithmetic; `== != < <= > >=` comparison; `||`, `&&`, `!` boolean. Order of operations: `!`/unary `-`, then `* / %`, then `+ -`, then `< > <= >=`, then `== !=`, then `&&`, then `||`.

**for-expression shape decision table**:
| Bounds | Returns | Value expression needs |
|---|---|---|
| `[ ... ]` | list | just the value |
| `{ ... }` | object | `key => value` (the `=>` operator) |
| `{ key => v... }` | object of collections | grouping mode — keys may repeat |

**Capture groups by function** (4.5.1-4.5.2):
| Function | No groups | Unnamed groups | Named groups | No match |
|---|---|---|---|---|
| `regex` | matched string | list of substrings | map keyed by group name | **error** |
| `regexall` | list of strings | list of lists | list of maps | empty list (no error) |

**Quick facts**: variable files hold only literal key=value data (no functions); `.tfvars`=HCL, `.tfvars.json`=JSON, `*.auto.tfvars`/`terraform.tfvars` auto-load. Regex is **Golang syntax** (set Regex101 to Go). `replace` treats a pattern as regex only when wrapped in slashes (named groups become `$name` in the replacement). `templatestring` (OpenTofu, then Terraform 1.9) renders a template held in a string; `file`/`templatefile` pair with `path.module`, `path.root`, `path.cwd`. Note: the ternary "evaluates both return results even though only one is going to be used" — use `try` when one branch might not exist.

## Worked Example
The chapter's through-line evolves the instance module via the research process — each feature request required research first (names -> AWS tags; permissions -> IAM; access -> Systems Manager):

1. **Name and tags**: research showed AWS console names are just the `Name` tag, so the module adds `tags = merge(var.tags, { Name = "${var.name_prefix}-instance" })` and a `name_prefix` variable — a prefix rather than a dedicated name, to accommodate launching multiple instances.
2. **Multiple instances**: moves `count` *inside* the module (`count = var.instance_count`) with `Name = "${var.name_prefix}-${count.index}"`. Putting `count` on the calling module block instead (listing 4.3) duplicates *every* resource in the module.
3. **Roles**: IAM needs two resources per instance — `aws_iam_role` and `aws_iam_instance_profile` (best practice: name the profile the same as the role) — with an `assume_role_policy` built from `data "aws_iam_policy_document"` granting only `ec2.amazonaws.com` the `sts:AssumeRole` action. Policies stay out of the module: it outputs the role so users attach their own policies.
4. **Systems Manager**: an `aws_iam_policy` data source pulls the AWS-managed SSM policy, attached with `count = var.enable_systems_manager ? 1 : 0`.
5. **Result** (listing 4.8): a consumer instantiates five servers with one module block — `instance_count = 5`, `enable_systems_manager = true`, arbitrary tags — and "these upgrades will roll out to everyone using the module."

## Key Takeaways
1. Research before coding: read the provider docs and search the ecosystem first; the answer is often a tag, a data source, or a managed policy you didn't know existed.
2. Use `count = bool ? 1 : 0` for optional features and for switching between two submodules (NAT instance vs. NAT gateway) — then swap the module outputs with a ternary too.
3. Prefer `for_each` (object/map/set) when instances differ in configuration; use `count` when they only differ by index; convert lists with `toset`.
4. If a plan shows changes immediately after every apply, hunt for impure functions and replace them with `random`/`time` provider resources.
5. Never hand-build JSON/YAML/IAM documents in templates — use `jsonencode`, `yamlencode`, or validating data sources.
6. When `count`/`for_each` fails on resource-derived values, push configuration into a local and iterate with `count.index` (e.g. `element(var.subnet_ids, count.index)`) rather than batching plans with targeting.

## Connects To
- **Ch 3**: this chapter expands the variables-and-modules module built there; `name_prefix` replaces a dedicated name for multi-instance reuse.
- **Ch 5**: the plan-time knowledge boundary for `count`/`for_each` is explained by how Terraform builds its resource graph.
- **Ch 6**: the `random` and `time` providers introduced as impure-function fixes are state-only providers; `random_password` is used to dissect state.
- **Declarative purity**: external concept — declarative languages forbid side effects; any non-deterministic value in configuration is perpetual drift by construction.
