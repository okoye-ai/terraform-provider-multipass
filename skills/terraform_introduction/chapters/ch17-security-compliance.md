# Chapter 17: Security and Compliance with Terraform

## Core Idea
Never put sensitive data in config; fetch secrets from Vault (or similar) via data sources, and enforce compliance as code with Sentinel policies that block non-compliant plans.

## Frameworks Introduced
- **Never hardcode secrets**: use input variables or a secrets manager (Vault) — a rule with zero exceptions
  - How: the `vault_generic_secret` *data source* pulls the secret at apply time; Terraform only sees the resolved value
- **Sentinel policy-as-code**: embedded in HashiCorp Enterprise; a rule inspects `tfplan` and blocks the run if violated
  - When to use: enforce org rules like mandatory tagging before any apply

## Key Concepts
- **Data source (`data "vault_generic_secret"`)**: read-only pull of a secret from Vault
- **Sentinel rule**: logic-based policy over the plan; failing rule blocks the Terraform run
- **Compliance as code**: compliance rules defined and enforced through code, like infrastructure

## Mental Models
- **Sentinel as a bouncer on the plan**: the plan is checked at the door; non-compliant plans never reach apply.

## Worked Example
Mandatory-environment-tag Sentinel policy:
```hcl
import "tfplan"

main = rule {
  all tfplan.resources as _, resources {
    all resources as _, instances {
      instances.change.after.tags["Environment"] else false is string
    }
  }
}
```
Every resource must have an `Environment` tag whose value is a string (`else false` makes a missing tag fail) — otherwise the run is blocked.

Pulling a secret instead of hardcoding one:
```hcl
data "vault_generic_secret" "example" {
  path = "secret/example"
}

resource "example_resource" "example" {
  some_attribute = data.vault_generic_secret.example.data["example_attribute"]
}
```

## Key Takeaways
1. The secrets rule is absolute: input variables or a secrets manager — never plaintext in config or state.
2. Sentinel inspects the *plan* — policies fire before infrastructure changes.
3. Sentinel policies can be written in the Sentinel language or a subset of HCL.

## Connects To
- **Ch 18**: Vault's setup and store/read patterns in depth
- **Ch 16**: where in the pipeline these checks belong (pre-apply)