# Chapter 19: Troubleshooting and Debugging Terraform

## Core Idea
Turn on logging (`TF_LOG`), prevent errors with `validate`/`plan`, and inspect reality through the state (`terraform show`) or expressions interactively (`terraform console`).

## Frameworks Introduced
- **Log-level recipe**: `export TF_LOG=DEBUG` (options TRACE/DEBUG/INFO/WARN/ERROR) + `export TF_LOG_PATH=./terraform.log`
  - When to use: anything unclear about what Terraform is actually doing; TRACE/DEBUG are verbose by design — use them when you need the detail
- **Debug escalation ladder**: 1) `terraform validate` + `terraform plan` to catch errors pre-apply; 2) isolate by commenting out config sections; 3) inspect state with `terraform show`; 4) evaluate expressions interactively with `terraform console`
- **Common-error playbook**: provider not initialized → run `terraform init`; invalid resource attributes → check against the resource type's docs; conflicts with unmanaged infrastructure → `terraform import` it or delete the conflicting resources

## Key Concepts
- **`TF_LOG` / `TF_LOG_PATH`**: verbosity control and output destination
- **`terraform validate`**: catches config errors (e.g. undefined/missing variable values) before apply
- **`terraform console`**: interactive expression evaluation — check what a variable/attribute actually resolves to

## Mental Models
- **Debug from the outside in**: validate the file → plan the change → inspect the state → interrogate expressions. Escalate only as far as needed.

## Code Examples *(technical)*
```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log

terraform validate
terraform console
> var.my_variable
```

## Key Takeaways
1. `validate` and `plan` are the two standing pre-flight checks — most errors should die there.
2. Comment-to-isolate is a legitimate debugging strategy for multi-resource configs.
3. If Terraform's behavior surprises you, compare your assumption against `terraform show` output.

## Connects To
- **Ch 12**: `terraform show` doubles as a state inspection tool
- **Ch 11**: infrastructure "conflicts" errors are resolved by import