# Chapter 10: Intermediate Terraform Language Features

## Core Idea
Four features unlock concise, DRY configs: built-in functions, dynamic blocks for repeatable nested structures, conditional expressions for environment-driven choices, and locals for shared named expressions.

## Frameworks Introduced
- **Locals for DRY**: define named expressions once (`local.<name>`), reuse everywhere
  - When to use: any value repeated in multiple places (common tags, subnet math)
- **Conditional sizing pattern**: `environment == "production" ? "t3.large" : "t3.micro"` — encode environment differences as conditionals instead of separate configs
- **Dynamic blocks for nested repetition**: construct repeatable nested blocks with `dynamic` + `for_each`/`count`

## Key Concepts
- **Functions**: `function(arg1, arg2)` — manipulate and transform data inline
- **Dynamic block**: generates nested blocks from a collection
- **Conditional expression**: `condition ? true_val : false_val`
- **Local values**: named expressions simplifying complex expressions, keeping config DRY

## Mental Models
- **Locals as your config's private definitions**: computed once, referenced cleanly, no repetition.
- **Conditionals as the config's branching**: same codebase, different environments — no forked files.

## Worked Example
A production/staging droplet that shares one config:
```hcl
locals {
  common_tags = {
    Owner       = "Networking Team"
    Environment = var.environment
  }
}

resource "aws_instance" "example" {
  count         = var.create_resources ? 1 : 0
  instance_type = var.environment == "production" ? "t3.large" : "t3.micro"

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key   = tag.key
      value = tag.value
    }
  }
}
```
Three features in five lines: flip existence by boolean, size by environment, iterate tags without hand-writing blocks.

## Reference Tables

| Function | Purpose | Example → Result |
|---|---|---|
| `length` | Count list/string elements | `length(["a","b","c"])` → 3 |
| `element` | List item at index | `element(["a","b","c"], 1)` → "b" |
| `concat` | Join lists | `concat(["a","b"],["c"])` → ["a","b","c"] |
| `join` | List → string with separator | `join(", ", ["a","b"])` → "a, b" |
| `format` | Formatted string | `format("Hello, %s!", "World")` → "Hello, World!" |
| `substr` | Substring | `substr("Hello, World!", 0, 5)` → "Hello" |
| `lower` / `upper` | Case change | `lower("Hi")` → "hi" |
| `jsonencode` | Value → JSON string | `jsonencode({"k":"v"})` → `{"k":"v"}` |

## Key Takeaways
1. Reach for `count = cond ? 1 : 0` to make resources optional.
2. `contains(var.availability_zones, "us-east-1a") ? 1 : 0` — conditionals work on any check.
3. Locals shine for composite values like `cidrsubnet`-derived AZ maps used in many places.

## Connects To
- **Ch 5**: functions/locals operate on the variables and outputs defined there
- **Ch 13**: cross-provider references use the same expression language