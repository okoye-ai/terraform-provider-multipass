# Chapter 3: Terraform variables and modules

## Core Idea
A Terraform module is a function: input variables are its arguments, output variables are its return values, and locals are its internal variables — and typing + validating those inputs is what turns a script into a trustworthy reusable component.

## Frameworks Introduced
- **Module-as-function model**: inputs -> internal logic -> outputs, with strict scope boundaries.
  - When to use: when deciding where any value belongs.
  - How: only input variables enter a module; only outputs leave it; locals exist only inside. `var.name`, `local.name`, and `module.<name>.<output>` are the three access paths.
- **Module flavors**: **root** (the entry point where `init`/`apply` run; the only place `provider` blocks may live), **shared** (pulled from Git or a module registry), and **submodules** (bundled inside a parent under `modules/`).
  - How: submodules follow the same structure as any module; nesting submodules inside submodules is bad practice — it raises project complexity for no gain.
- **Module file structure** (convention, not requirement): see Reference Tables (table 3.1).
- **Type constraints** on inputs: `string`, `number`, `bool`, `list(T)`, `set(T)`, `tuple([T,...])`, `object({...})`, `map(T)`, `any`, plus `null` (not usable as a constraint).
  - When to use: always — untyped variables are allowed, but types "are a sign of high-quality code" and produce errors the moment wrong data arrives.
- **The validation subblock**: repeatable `validation { condition = <bool expr>; error_message = "..." }` inside a `variable` block.
  - When to use: to catch misconfigurations before a slow plan/apply cycle, since some errors never appear at plan time at all.
  - How: since Terraform 1.9 the condition may reference other inputs/attributes (it must include the variable being tested); error messages require at least one full English sentence.
- **Sensitive values**: `sensitive = true` marks a value so Terraform won't display/log it — and the flag travels with the value into anything derived from it.
  - When to use: every password, API key, or credential input; and any output whose value derives from a sensitive value (otherwise Terraform errors assuming an accidental exposure).

## Key Concepts
- **Input variable (`variable` block)**: defines a module parameter; arguments are `description`, `type`, `default`, `sensitive`, `nullable` (default true), and `validation` subblocks.
- **Output (`output` block)`: returns data from a module; arguments are `description`, `value`, `sensitive`, `depends_on` (edge case — e.g., don't return the instance until its firewall attachment finishes).
- **Locals (`locals` block)**: label-less, repeatable block whose arguments each define one module-scoped constant; duplicate local names (even across separate blocks) are an error, and locals may reference other locals but never circularly.
- **Variables are constants**: all Terraform variables can be set only once per run — declarative execution follows the dependency graph, not code order, so there is no meaningful "later" to reassign in.
- **null**: the type/value of "not set"; the idiomatic default for optional inputs, letting code distinguish "unset" from any real value.
- **Map vs. object**: same syntax, two differences — maps enforce one type for all values and accept an arbitrary number of unspecified keys (ideal for `tags`), while objects enforce the declared key structure (extra keys are dropped) and allow per-key types.
- **List vs. set vs. tuple**: list = ordered, homogeneous, any length; set = unordered, no duplicates; tuple = fixed length, each element may have its own declared type.
- **Module registry**: hosts module versions from Git tags (public Terraform registry ~12,000 modules); vet for update cadence, backward-compatibility commitment, maintainer, and code quality.

## Mental Models
- Use the **module-as-function mapping** (inputs = arguments, outputs = return values, locals = function-local variables) whenever deciding where a value belongs.
- Use **"all variables are constants"** to unlearn imperative habits: transform data with locals and expressions instead of reassignment.
- Use **portability as the refactor criterion**: any hardcoded value a user might want to change (subnet, instance type) should become an input; any value users must learn after creation (ID, IP, ARN) should become an output.
- Use **null as the sentinel for "unset"**: `default = null` makes an input optional without inventing a fake default, and `var.x != null` tests whether the user provided it.

## Anti-patterns
- **Leaving inputs untyped**: any-type inputs move errors to the provider or worse, runtime behavior; typed inputs fail fast with messages naming what was expected and received.
- **Overly complex nested object inputs**: deep object-in-object types are hard to follow and modify — break them into multiple simpler inputs.
- **`list(any)` as a routine choice**: all elements of a list must share one type anyway, so `list(any)` mostly hides intent; prefer concrete subtypes like `list(string)`.
- **Forgetting `sensitive` on derived outputs**: Terraform treats an unsensitized output of a sensitive value as an accidental exposure error.
- **Duplicate local names across blocks**: even in different `locals` blocks or files, it's an error — locals are one flat namespace.
- **Assuming `sensitive` hides data from state**: sensitive only suppresses display/logging; the value still lands in state (see ch6 for state security).

## Code Examples
- **What it demonstrates**: typed, documented, defaulted, and custom-validated inputs — the blueprint for a quality module's `variables.tf`.
```hcl
variable "instance_type" {
  type        = string
  description = "The type of instance to launch."
  default     = "t3.micro"   # a default makes the input optional
}

variable "subnet_id" {
  type        = string
  description = "The ID of the Subnet to launch the instance into."

  validation {
    condition     = length(regexall("^subnet-[\\d|\\w]+$", var.subnet_id)) == 1
    error_message = "The subnet_id must match the pattern ^subnet-[\\d|\\w]+$"
  }
}
```

- **What it demonstrates**: stacking multiple validation blocks (range checks + an integer check via `can(parseint(...))`).
```hcl
variable "my_integer" {
  description = "An integer between 0 and 10 inclusive."
  type        = number
  validation {
    condition     = var.my_integer <= 10
    error_message = "The value must not be greater than 10."
  }
  validation {
    condition     = var.my_integer >= 0
    error_message = "The value must not be less than 0."
  }
  validation {
    condition     = can(parseint(tostring(var.my_integer), 10))
    error_message = "The value must be an integer."
  }
}
```

- **What it demonstrates**: consuming a published module's outputs in another resource (module outputs are accessed as block attributes, no keyword needed).
```hcl
module "my_instance" {
  source    = "github.com/YOU_USERNAME/terraform-aws-in-depth//modules/ec2_instance"
  subnet_id = var.subnet_id
  instance_type = "t3.large"
}
resource "aws_vpc_security_group_ingress_rule" "allow_access" {
  security_group_id = aws_security_group.allow_instance_access.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "${module.my_instance.aws_instance_ip}/32"
}
```

## Reference Tables
**Module file layout (table 3.1):**

| File | Purpose |
|---|---|
| variables.tf | All module inputs |
| outputs.tf | All module outputs |
| main.tf | Main entry point; simple modules may define only resources here |
| *.tf | Additional resource definitions, named by project |
| README.md | Documentation, pulled into any module registry the module is published to |
| modules/ | Submodules, each following this same structure |
| templates/ | Templates used by the module |
| examples/ | Example usage |

**Type cheat sheet (chapter 3 sections 3.6.1-3.6.10):**

| Type | Constraint | Distinguishing rules |
|---|---|---|
| string | string | Unicode text; supports interpolation `"${var.prefix}-service"` |
| number | number | One type for ints and floats (no int/float split — validate integers separately) |
| bool | bool | true/false |
| list | list(T) | Ordered, homogeneous, arbitrary length |
| set | set(T) | Unordered, no duplicates |
| tuple | tuple([T1, T2, ...]) | Fixed length, per-element types |
| object | object({key = T, ...}) | Declared keys (extras dropped), per-key types, `optional(T, "default")` support, nestable |
| map | map(T) | Arbitrary keys, one type for all values — the fit for `tags` |
| null | (not a constraint) | Value meaning "not set"; idiomatic default for optional inputs |
| any | any (also implicit default) | No restriction; inside list/map all elements must still share one type |

## Worked Example
Section 3.8 refactors the chapter 2 Hello World script into a reusable EC2 module, driven by three gaps: users must choose the subnet (custom VPCs), choose the instance type (different workloads), and receive the instance's ID/IP afterwards. Steps: (1) `providers.tf` — keep the `terraform { required_providers }` block, delete the `provider` block (root-only). (2) `variables.tf` — `instance_type` (string, default `"t3.micro"`) and `subnet_id` (string + regex validation, listing above). (3) `main.tf` — the resource now maps `var.ami`-style inputs instead of data lookups. (4) `outputs.tf` — `aws_instance_arn`, `aws_instance_ip`, and the whole `aws_instance` resource. (5) Test from an `examples/` folder as a new root module: its own `required_providers` + `region` variable + `provider "aws"`, data lookups for the default VPC/subnets, then `module "test_instance" { source = "../"; subnet_id = data.aws_subnets.default.ids[0] }` and a root output of the module's ARN. (6) Publish: repo named `terraform-PROVIDER-NAME` (`terraform-aws-in-depth`), consumed via source `github.com/YOU/terraform-aws-in-depth//modules/ec2_instance` (double slash selects the submodule folder).

## Key Takeaways
1. Design inputs like a function signature: type every variable, document everything, give defaults to optional inputs and no default to required ones.
2. Validate inputs with `validation` blocks early — plan/apply cycles are slow and some errors only surface at apply; deep validation with descriptive messages is a hallmark trait of a great module.
3. Expose module internals as outputs deliberately; compose larger systems by chaining module outputs into other modules' inputs.
4. Default sensitive inputs to `sensitive = true` and remember the value still lives in state.
5. Keep providers at the root; a reusable module only declares `required_providers`.
6. Name module repos `terraform-PROVIDER-NAME` and test them via an `examples/` root workspace using a relative `source = "../"`.
7. When an object type constraint grows deep, split the input into several simple inputs instead.

## Connects To
- **Ch 2**: the module block's `source`/`version`/`providers` meta arguments used to call these modules.
- **Ch 4**: functions and expressions — needed to write richer validation conditions and local transforms.
- **Ch 5**: locals cannot have circular dependencies — same DAG rules as resources.
- **Ch 6**: sensitive values stored in state; backend security.
- **Ch 8**: publishing/distribution nuances for modules; `for_each` over inputs.
- **Ch 9**: testing the module (this chapter does the manual `examples/` smoke test).
- **terraform-docs / README.md**: `description` fields on inputs and outputs are picked up by external tooling to auto-generate documentation.
