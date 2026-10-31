# Chapter 2: Getting Started with Terraform

## Core Idea
Set up a working Terraform environment (install, cloud credentials, provider block) and drive the core CLI loop — `init → validate → fmt → plan → apply → show → destroy` — on an Azure resource group and virtual network.

## Frameworks Introduced
- **The Core Command Loop**: the daily Terraform workflow
  - When to use: every change to infrastructure, no exceptions
  - How: `terraform init` (download providers, configure backend) → `validate` (syntax/structure) → `fmt` (canonical style) → `plan` (preview + / ~ / - diff) → `apply` (execute + update state) → `show` (inspect state) → `destroy` (teardown)
- **Credential Separation Pattern**: secrets live outside HCL
  - When to use: any provider that needs credentials (azurerm here, but the pattern is universal)
  - How: declare empty `variable` blocks in `variables.tf`; supply values via `terraform.tfvars` (git-ignored) or `TF_VAR_<name>` environment variables; never hard-code secrets in `main.tf`
- **Pinned Provider Versions**: `version = "=3.0.0"` in `required_providers` guarantees byte-identical provider behavior across machines and pipelines

## Key Concepts
- **`required_providers` block**: pins provider source and version so `init` is deterministic
- **Service principal**: dedicated Azure identity (appId = client_id, password = client_secret, tenant) created via `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/<id>"`; the standard non-interactive auth for Terraform
- **`features {}` block**: required by recent azurerm providers even when empty
- **`plan -out=file`**: save the plan to a file and `apply` that same file so nothing changes between review and execution — essential in pipelines
- **`TF_LOG=DEBUG`**: environment variable for verbose plan/apply diagnostics
- **`TF_WORKSPACE`**: environment variable for switching between dev/test/prod workspaces (separate state files)
- **HCL building blocks**: block (type + label + braces) → arguments (key = value) → expressions (references like `azurerm_resource_group.example_rg.location`)

## Code Examples
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}
resource "azurerm_resource_group" "hello_rg" {
  name     = "myFirstRG"
  location = "EastUS"
}
# The vnet REFERENCES the resource group's attributes — if the RG moves or
# renames, the vnet follows automatically with no manual edits.
resource "azurerm_virtual_network" "hello_vnet" {
  name                = "myFirstVNet"
  location            = azurerm_resource_group.hello_rg.location
  resource_group_name = azurerm_resource_group.hello_rg.name
  address_space       = ["10.0.0.0/16"]
}
```
- **What it demonstrates**: provider setup + attribute references that create dependency relationships implicitly

## Reference Tables
| Command | Purpose | Notes |
|---|---|---|
| `terraform init` | Download provider plugins, set up backend | Creates `.terraform/`; warns on version-constraint mismatch |
| `terraform validate` | Check HCL syntax and references | Catches misspelled block types / undefined variables |
| `terraform fmt` | Canonical formatting | Run as a pre-commit hook; kills whitespace debates in review |
| `terraform plan` | Preview + / ~ / - changes | `-out=` to pin the reviewed plan |
| `terraform apply` | Execute changes, update state | Apply a saved plan file to guarantee what was reviewed is what runs |
| `terraform show` | Dump current state | Pipe to grep/less; `terraform state show <res>` for one resource |
| `terraform destroy` | Plan-then-delete all managed resources | For ephemeral/test environments |

| Color/code in plan output | Meaning |
|---|---|
| `+` (green) | resource will be created |
| `~` (tilde) | attribute modified in place |
| `-` (red) | resource destroyed |

## Worked Example
Full first-project flow with Azure:
1. Create the service principal: `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/YOUR_SUBSCRIPTION_ID"` → yields appId/password/tenant.
2. Project layout: `terraform-demo/{main.tf, variables.tf, terraform.tfvars}`
3. `variables.tf`: `variable "azure_subscription_id" {}` (+ client_id, client_secret, tenant_id)
4. `terraform.tfvars` (in `.gitignore`): the four credential values
5. `terraform init` → downloads azurerm provider from the registry into `.terraform/`
6. `terraform plan` → shows `+ azurerm_resource_group.demo_rg`
7. `terraform apply` → confirm "yes" → Azure API creates the group → state updated
8. Verify in Azure Portal; `terraform destroy` to tear down cleanly

## Key Takeaways
1. Never put the provider's version unpinned — `"=3.0.0"`-style pinning makes teams and pipelines deterministic
2. Credentials belong in `terraform.tfvars` (git-ignored) or `TF_VAR_*` env vars, never in committed code
3. Reference other resources' attributes instead of repeating values — relationships and dependencies follow automatically
4. In pipelines, always `plan -out=` then `apply <file>` so the reviewed plan is exactly what deploys
5. `terraform destroy` doesn't remove resources Terraform doesn't track (never imported) — untracked resources survive
6. Errors on apply usually stem from wrong appId/password/tenant pairs or insufficient RBAC privileges

## Connects To
- **Ch 3**: variables/interpolation introduced here get full treatment (conditionals, loops)
- **Ch 5**: "state updated" here becomes the whole discipline of state management
- **Ch 6**: provisioners, hinted at in Ch 1, extend this lifecycle