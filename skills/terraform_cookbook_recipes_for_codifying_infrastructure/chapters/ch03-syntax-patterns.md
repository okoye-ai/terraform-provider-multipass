# Chapter 3: Terraform Syntax Patterns

## Core Idea
Terraform's built-in functions and expression patterns are the toolkit for turning raw, messy input into clean, validated, computable configuration — and for sequencing, templating, and cross-state data sharing that declarative HCL does not give you for free.

## Frameworks Introduced
- **Input Sanitization with `trimspace`/`chomp`**: clean user-supplied strings before they reach resources.
  - When to use: inputs arrive with stray leading/trailing whitespace or trailing newlines (especially content read from files).
  - How: define a raw `variable`, apply `trimspace(var.user_input)` to strip spaces from both ends (interior spaces untouched), and `chomp` to remove trailing newline characters; stage the result in a `locals` block and expose via `output`.
- **Prefix/Suffix Stripping with `trimprefix`/`trimsuffix`**: remove known affixes without a regex.
  - When to use: inputs or resource outputs carry a known tag like `prefix_` / `_suffix` that must be gone before further use.
  - How: declare the affixes as locals, then `trimprefix(var.user_input, local.prefix)` followed by `trimsuffix(..., local.suffix)` — compose the two in sequence.
- **Regex-Driven Replacement (`regex`, `regexall`, `replace`)**: pattern-match and transform strings.
  - When to use: input matches a shape you only know by pattern (SSN masking, token extraction, masking secrets in outputs).
  - How: `replace(input, regex("\\d{3}-\\d{2}-(\\d{4})", input), "XXX-XX-$1")`; double-escape `\\d` inside Terraform strings; `$1` references the first captured group; `replace` is global by default; use `regexall` when you need all matches.
- **Chained String Transformation**: several manipulations in one expression.
  - When to use: standardizing multi-rule formatting (upper-case, then substitute, then expand) in a single local.
  - How: nest functions — `replace(replace(upper(var.user_input), "WORLD", "TERRAFORM"), "!", "!!!")` — or pair `format("%s: %s", upper(replace(...)), replace(...))` to merge two transformed parts; keep deep nesting in check with intermediate locals.
- **CIDR Decomposition with `cidrsubnet`**: compute subnets arithmetically instead of hardcoding them.
  - When to use: dividing a base block (e.g., `10.0.0.0/16`) into N equal subnets for cloud network design.
  - How: `[for i in range(4) : cidrsubnet(local.base_cidr_block, 8, i)]` — prefix = starting CIDR, newbits = added prefix bits (/16 + 8 → /24), netnum = subnet index. Pair with `cidrhost(subnet, 1)` to get the first usable IP (gateways) inside each subnet.
- **Guarded File Access (`fileexists` + `file`)**: read local files without crashing on absence.
  - When to use: importing external data or verifying prerequisites on the machine running Terraform.
  - How: `fileexists(var.config_file_path) ? file(var.config_file_path) : "Default content"`; for many files, a `for` expression maps each path to content or a "File not found" fallback. Paths resolve relative to the directory where Terraform runs, not the `.tf` file.
- **Template Rendering (`template_file`, heredoc)**: generate config files/scripts from variables.
  - When to use: you need to emit a bash script, userdata blob, or config whose content depends on variable inputs.
  - How: `data "template_file"` with a `<<-EOF` heredoc `template` and a `vars` map; `${...}` interpolates inside the template, `$${...}` emits a literal `${`.
- **Variable Validation Blocks with Good Error Messages**: enforce input contracts at load time.
  - When to use: any module surface where bad input would create wrong (or insecure) infrastructure.
  - How: `validation { condition = <expr that must be true>; error_message = "..." }`; multiple validation blocks per variable are allowed; conditions may call any function — `contains([...], var.x)` for enums, `can(regex("^t[23]\\..*", var.instance_type))` for shapes, `can(cidrhost(var.vpc_cidr, 0))` for structural validity. Write messages that state what went wrong, show a valid example, and explain why the restriction exists.
- **Optimistic Data Retrieval with `can` and `try`**: read possibly-absent attributes without hard failure.
  - When to use: complex objects or external data where a key may be missing or in an unexpected format (e.g., optional security-rule attributes).
  - How: `can(expr)` returns true if the expression evaluates without error; `try(expr, fallback)` returns the fallback on error — e.g. `type = try(rule.type, "ingress")`, `cidr_blocks = can(rule.cidr_blocks) ? rule.cidr_blocks : null`.
- **Sequential Processing with `count.index`**: process ordered lists position-by-position.
  - When to use: position-dependent resources — subnets cycling across availability zones (`count.index % length(names)`), or chains of IAM role → instance profile → instance where index `i` links the resources created for app `i`.
  - How: `count = length(var.list)` and index every attribute with `[count.index]`; note list order is generally preserved but not guaranteed, and inserting/removing mid-list re-creates shifted resources. Prefer order-independent designs when possible.
- **Cross-State Data Sharing (`terraform_remote_state`)**: consume another configuration's outputs.
  - When to use: modular architectures or multi-environment setups that need a VPC ID/subnet ID from another state.
  - How: prefer cloud-native data sources (`data "aws_vpc"`) first; fall back to `data "terraform_remote_state"` with a backend config (e.g., S3 bucket/key/region), reading `data.terraform_remote_state.network.outputs.vpc_id`; wrap risky reads with `try(..., null)`.

## Key Concepts
- **`trimspace`**: removes all leading and trailing spaces (and newlines) from a string; interior spaces are untouched.
- **`chomp`**: removes newline characters from the end of a string — the natural companion to file-reading functions.
- **`trimprefix` / `trimsuffix`**: remove a known prefix or suffix string from a string, once, without regex.
- **`regex` vs `regexall`**: `regex` returns the first match's substrings; `regexall` returns all matches as a list.
- **`replace`**: substitutes substrings (including regex patterns) globally by default; no lazy matching or last-occurrence-only mode.
- **`title` / `upper` / `lower`**: case transforms — title-cases each word's first character, uppercases, lowercases; English/centric, not i18n-safe, and not always reversible.
- **`sort`**: sorts a list of strings in ascending, case-sensitive lexicographic (UTF-8) order; strings only, no custom rules or descending option.
- **`cidrsubnet(prefix, newbits, netnum)`**: computes a subnet CIDR by extending the prefix by `newbits` bits and selecting subnet `netnum`.
- **`cidrhost`**: returns a specific host IP (e.g., offset 1) within a CIDR — useful for gateway addresses.
- **`fileexists(path)` / `file(path)`**: tests for a local file's existence and reads its contents, respectively.
- **validation block**: per-variable rule with `condition` (must be true) and `error_message`; runs at configuration load, not only at apply.
- **`can` / `try`**: error-tolerant evaluation — `can` yields a boolean, `try` yields a value or supplied fallback.
- **`terraform_remote_state`**: read-only data source exposing another configuration's state outputs.
- **`sensitive`**: variable/output flag that keeps values out of console output and logs.

## Mental Models
- Think of validation blocks as gate guards at the module boundary: type constraints catch the wrong shape, `validation` catches the wrong value.
- Think of `try(expr, fallback)` as an optimistic read: assume the attribute exists, but have a safe default ready when it doesn't.
- Think of `cidrsubnet` as subnet arithmetic on demand — never hand-write a subnet table a loop can compute.
- Treat `count.index` as position, not identity: resources are tied to their index, so reordering a list is a destructive change.
- Reach for cloud-native data sources before `terraform_remote_state`: your state file is a sensitive surface, so don't read from it what the provider API can tell you directly.

## Anti-patterns
- **Naming or sizing resources from `sort(var.list)` directly in the resource body**: changing the input list renames or re-creates resources, causing unintended disruption; sort for display/consistency, not as a resource key.
- **Hardcoding subnet CIDR blocks**: manual calculations invite errors and resist resizing; compute with `cidrsubnet` and adjust `newbits`/loop count instead.
- **Deeply nested or undocumented regex in `replace`**: complex patterns (lazy matching, last-occurrence-only) make configuration unreadable — Terraform's `replace` is global-only, so preprocess data outside Terraform or layer multiple simple operations with comments.
- **Relying on complex `validation` regex alone for hard cases** (e.g., email addresses): edge cases leak through; move to external data sources, pipeline-side checks, or specialized services.
- **Using `try`/`can` to bury real errors**: they suppress failures you might need to see, which hurts debugging; use sensible, non-risky defaults or let Terraform fail fast.
- **Making configuration depend on local files as a data bus**: paths are relative to where Terraform runs, changes are not auto-detected (may force `-replace`/`terraform taint`), and portability suffers; use variables, data sources, and remote state instead.
- **Exposing sensitive outputs via remote state casually**: anyone who can read the state can read the data; secure, encrypt, and lock the backend first.

## Code Examples
```hcl
locals {
  prefix = "prefix_"
  suffix = "_suffix"

  clean_user_input = trimspace(var.user_input)
  without_prefix   = trimprefix(var.user_input, local.prefix)
  clean            = trimsuffix(local.without_prefix, local.suffix)

  masked_input = replace(var.user_input,
    regex("\\d{3}-\\d{2}-(\\d{4})", var.user_input),
    "XXX-XX-$1"
  )
}
```
- **What it demonstrates**: the cleaning pipeline — `trimspace`, `trimprefix`, `trimsuffix` chaining, plus regex capture-group masking with `replace` and `$1`.

```hcl
locals {
  base_cidr_block = "10.0.0.0/16"

  # Create four /24 subnets
  subnets = [for i in range(4) : cidrsubnet(local.base_cidr_block, 8, i)]

  first_ip_in_each_subnet = [for subnet in local.subnets : cidrhost(subnet, 1)]
}
```
- **What it demonstrates**: `cidrsubnet` decomposition of a /16 into four /24s and `cidrhost` for the first usable IP in each.

```hcl
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = split("/", var.vpc_cidr)[1] <= "24" && split("/", var.vpc_cidr)[1] >= "16"
    error_message = "VPC CIDR block must be between a /16 and /24."
  }
}
```
- **What it demonstrates**: multiple validation blocks per variable — structural validity via `can(cidrhost(...))` plus a size-range rule.

```hcl
resource "aws_security_group" "example" {
  name        = "example"
  description = "Example security group"

  dynamic "ingress" {
    for_each = var.security_rules
    content {
      type        = try(ingress.value.type, "ingress")
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = can(ingress.value.cidr_blocks) ? ingress.value.cidr_blocks : null
    }
  }
}
```
- **What it demonstrates**: `can`/`try` optimistic retrieval inside a `dynamic` block — defaulting `type` and nulling absent `cidr_blocks` without hard errors.

## Reference Tables
| Function | Input | Returns | Notes |
|---|---|---|---|
| `trimspace(str)` | string | string sans leading/trailing whitespace | interior spaces untouched |
| `chomp(str)` | string | string sans trailing newlines | pairs with file reads |
| `trimprefix(str, p)` | string, string | string without leading `p` | literal, not regex |
| `trimsuffix(str, s)` | string, string | string without trailing `s` | literal, not regex |
| `regex(pat, str)` | pattern, string | first match's substrings | errors if no match |
| `regexall(pat, str)` | pattern, string | list of all matches | never errors on zero matches |
| `replace(str, search, repl)` | 3 strings | string with substitutions | global by default; search may be regex |
| `title`/`upper`/`lower` | string | re-cased string | English-centric, not reversible |
| `sort(list)` | list of strings | ascending, case-sensitive list | strings only, no custom locales |
| `cidrsubnet(prefix, newbits, netnum)` | string, number, number | subnet CIDR string | newbits extends prefix; netnum selects |
| `cidrhost(prefix, hostnum)` | string, number | host IP in block | offset 1 = first usable IP |
| `fileexists(path)` / `file(path)` | string | bool / file contents | relative to Terraform's cwd |
| `can(expr)` | expression | true if evaluable without error | error suppression |
| `try(expr, fallback)` | expr + default | value or fallback | choose safe defaults |

## Worked Example
Recipe 3.7 — dividing `10.0.0.0/16` into /24 subnets. A /16 holds 65,536 addresses; adding 8 newbits yields /24s of 256 addresses each. With `subnets = [for i in range(4) : cidrsubnet("10.0.0.0/16", 8, i)]` the output is exactly `"10.0.0.0/24"`, `"10.0.1.0/24"`, `"10.0.2.0/24"`, `"10.0.3.0/24"` — the third octet comes straight from `netnum`. Scaling is a loop-count change; resizing subnets is a `newbits` change. The chapter then extends it: `first_ip_in_each_subnet = [for subnet in local.subnets : cidrhost(subnet, 1)]` yields `10.0.0.1`, `10.0.1.1`, `10.0.2.1`, `10.0.3.1` — the first usable IP in each block, suitable for gateway or other fixed-address resources. The recipe's caveats: size subnets for actual IP demand, avoid wasting address space with too many small blocks, and respect provider limits on subnets per VPC.

## Key Takeaways
1. Sanitize at the boundary: run every user-supplied string through `trimspace` (and `chomp` for file content) once, in a local, before it touches a resource.
2. Compute network layout, don't type it — `cidrsubnet` + a `for` loop over `range(n)` replaces hand-maintained subnet tables and makes resizing a one-parameter change.
3. Fail validation at load time with `validation` blocks; a good `error_message` says what's wrong, shows a valid example, and explains the restriction.
4. Use `can` for existence checks and `try` for defaults, but sparingly — both suppress errors that may be the bug you're hunting.
5. Sequence only where the dependency is positional: `count.index` links role/profile/instance per index, but shifting a list shifts (and may recreate) everything after it.
6. Prefer cloud-native data sources over `terraform_remote_state`; when you do consume remote state, read only a few outputs, secure the backend, and guard lookups with `try(..., null)`.
7. Template dynamic files with heredocs (`<<-EOF`) and remember `$${...}` to emit a literal `${...}` in rendered output.

## Connects To
- **Ch 2 (Code Quality)**: validation blocks are syntax-level checks; TFLint and `terraform fmt`/`validate` are repo-level checks — layer them.
- **Ch 4 (Modules and Providers)**: validation blocks, remote state outputs, and template rendering are the raw materials of well-behaved reusable modules.
- **Ch 3.14 → 4.8/4.10**: `terraform_remote_state` is the native way to share data across states; Consul KV is the externalized, dynamic alternative.
- **RFC 1918 / CIDR notation**: `cidrsubnet` mechanizes the prefix-extension math behind IPv4 CIDR blocks.
- **Regex (RE2 syntax)**: Terraform's `regex`/`regexall` use bounded RE2 patterns; captured-group references (`$1`) mirror most regex engines.