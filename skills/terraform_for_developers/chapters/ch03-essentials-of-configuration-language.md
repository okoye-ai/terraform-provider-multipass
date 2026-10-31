# Chapter 3: Essentials of Terraform Configuration Language

## Core Idea
Master the four expression tools that make one HCL codebase serve many environments: parameterized variables, interpolation (`${}`), conditional expressions, and loops/dynamic blocks — so code adapts by adjusting data, never by duplicating resource blocks.

## Frameworks Introduced
- **Parameterization over Duplication**: variables as the substitute for per-environment code copies
  - When to use: any config reused across dev/test/staging/prod
  - How: declare `variable` blocks (with `type`, `description`, `default`) in `variables.tf`; override via `terraform.tfvars`, `TF_VAR_*` env vars, or `-var` flags at runtime
- **count vs for_each decision rule**
  - `count` → when making *N copies* of a nearly identical resource; differentiate via `count.index` (e.g. `"vm-${count.index}"`)
  - `for_each` → when resources differ by a *meaningful key* from a map or set (each keyed resource is addressable as `<type>.<name>["web"]`)
  - Why: count-based scaling adjusts by index position — removing one element shifts everything after it; for_each keys are stable across plan/replan
- **Dynamic Blocks for repeated sub-blocks**: when a resource *contains* repeating sub-structures (ingress rules, etc.), not repeated resources
  - How: `dynamic "<label>" { for_each = var.rules; content { ... <label>.value.attr ... } }`

## Key Concepts
- **Variable validation block**: runtime constraints on inputs (non-empty lists, numeric ranges) that return readable errors before partially-configured resources deploy
- **Variable precedence chain**: `.tfvars` file → `TF_VAR_*` env var → `-var` CLI flag → `default` value
- **Complex types**: `list(string)`, `map`, `object({...})` — objects bundle related settings into one variable
- **Interpolation**: `${...}` wraps expressions embedded in strings; standalone references since 1.0 may omit braces (`name = var.instance_name`)
- **Ternary conditional**: `condition ? true_val : false_val` — e.g. `count = var.environment == "prod" ? 3 : 1`
- **Random suffix pattern**: `random_id` resource + `"storageacct${random_id.rand.hex}"` for globally unique names

## Code Examples
```hcl
# Conditional instance sizing driven by a toggle
instance_type = var.enable_logging ? "t2.medium" : "t2.micro"

# Map-based region lookup
var.region_map[var.env_type]   # { dev = "EastUS", prod = "WestUS" }

# Function composition in interpolation
cidr_block = "${cidrsubnet(var.vpc_cidr, 2, 1)}"

# for_each over a map — resources differ by key AND value
# var.instances = { "web" = "t2.micro", "db" = "t2.small" }
resource "aws_instance" "app" {
  for_each     = var.instances
  instance_type = each.value
  # addressable as aws_instance.app["web"], ["db"]
}
```
- **What it demonstrates**: parametric configuration — behavior changes at plan time from data, not code edits

## Reference Tables
| Need | Tool | Addressing | Caveat |
|---|---|---|---|
| N near-identical copies | `count = var.n` | `resource.name[count.index]` | Removing mid-list item shifts later indices → replacement churn |
| Keyed/differing resources | `for_each = var.map` | `resource.name["key"]` | Keys must exist at plan time; keys are stable |
| Repeating sub-blocks inside one resource | `dynamic "label" { ... }` | n/a (part of parent) | Use for ingress/egress rules, policies — not for whole resources |

| Value source | Format |
|---|---|
| tfvars file | `location = "WestUS"` (git-ignored if secrets) |
| Environment | `TF_VAR_location=WestUS` |
| CLI | `-var "vm_count=3" -var "location=WestUS"` |
| In code | `default` in the variable block (last resort) |

## Worked Example
Multi-VM deployment scaled by variables: `variable "vm_count" { type = number; default = 2 }` and `variable "location" { default = "EastUS" }` drive
```hcl
resource "azurerm_virtual_machine" "demo_vms" {
  count               = var.vm_count
  name                = "demo-vm-${count.index}"
  location            = azurerm_resource_group.main_rg.location
  resource_group_name = azurerm_resource_group.main_rg.name
}
```
`terraform plan` proposes demo-vm-0 and demo-vm-1. The team wants three VMs in WestUS: change nothing but the data — `-var "vm_count=3" -var "location=WestUS"` — re-plan. Same code, new outcome.

## Anti-patterns
- **Terraform as "mini-program"**: chain too many functions/conditionals inside expressions and readability collapses; keep expressions simple, push heavy logic to modules or external scripts
- **Deeply nested ternaries**: hard to read — prefer maps (`region_map[env]`) for multi-branch lookups
- **Copy-pasted repeated blocks**: hand-written ingress rules duplicate, drift, and grow unwieldy — replace with a dynamic block driven by a variable
- **Hard-coded constants in resources**: every environment difference should be a variable reference, not a literal

## Key Takeaways
1. If you're duplicating a resource block to change a value, you needed a variable
2. Default to `for_each`; use `count` only when copies are truly identical — keys don't shift
3. Dynamic blocks exist for repeated sub-blocks (rules), `for_each`/`count` for whole resources — don't confuse them
4. Add `validation` blocks on important variables to fail fast with readable errors at plan time
5. `${}` is only required when interpolating *into a string*; plain references (`name = var.x`) don't need braces
6. Combine conditionals with booleans/locals for enable-or-disappear resources: `count = var.toggle && local.ok ? 2 : 0`

## Connects To
- **Ch 2**: credential variables pattern originates here
- **Ch 4**: inputs/outputs/locals formalize these expression patterns into module boundaries
- **Ch 9**: complex expressions gone wrong are a classic source of semantic errors