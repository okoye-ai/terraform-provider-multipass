# Chapter 9: Best Practices

## Core Idea
Good Terraform hygiene is structural, not stylistic: a fixed file layout, consistent naming, per-environment `.tfvars`, no plaintext secrets, and `fmt`/`lint` in the workflow.

## Frameworks Introduced
- **Canonical file layout**: `main.tf` (entry point/resources), `variables.tf` (inputs), `outputs.tf` (outputs), `modules/` subdirectory per module
  - When to use: any project longer than a spike; makes projects navigable and team-reviewable
- **Environment-per-tfvars pattern**: one `.tfvars` per environment (`production.tfvars`, `staging.tfvars`), selected via `-var-file` — same config, duplicated environments, no code duplication
- **Never plaintext secrets**: secrets enter config only via input variables (values supplied at runtime) or fetched live from a secrets manager (Vault, AWS Secrets Manager, Azure Key Vault)
  - Why it works: the secret value never lives in config or on your machine

## Key Concepts
- **Naming conventions**: snake_case for files, variables, outputs, resources; prefix names with resource type (`vm_instance`, `db_subnet`); descriptive names over clever ones. Consistency matters more than which convention.
- **Formatting (`terraform fmt`)**: canonicalizes style automatically — also keeps Git diffs free of whitespace noise
- **Linting (`tflint`)**: catches errors before you run, can enforce cost/usage policies

## Anti-patterns
- **Hardcoding secrets into configs or state**: the critical fail-safe rule — never plaintext secrets in `.tf` files.
- **One-off naming per developer**: team code must read like one person wrote it.
- **Skipping `fmt` before commit**: creates noisy diffs that hide substantive changes.

## Code Examples *(technical)*
```hcl
terraform apply -var-file="production.tfvars"
```

```
.
├── main.tf
├── variables.tf
├── outputs.tf
└── modules/
    ├── compute/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── networking/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```
- **What it demonstrates**: the recommended project structure and environment selection at apply time.

## Key Takeaways
1. `main.tf` / `variables.tf` / `outputs.tf` / `modules/` — adopt the layout, gain free navigability.
2. `-var-file` is how one codebase serves many environments.
3. Secrets: input variables with runtime values, or a secrets manager. Never plaintext.
4. `terraform fmt` + `tflint` belong in every workflow, catch errors before apply.

## Connects To
- **Ch 7**: modules directory layout is the building block of the project structure
- **Ch 17 & 18**: the secrets-manager path is expanded with Vault