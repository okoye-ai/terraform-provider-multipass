# Chapter 5: Serverless made easy

## Core Idea
Serverless (pay-as-you-go + minimal operational overhead) deploys through Terraform exactly like any other infrastructure — and code organization should be resolved by sorting resources **by group first, then by size** (number of dependencies), not by dependencies alone.

## Frameworks Introduced
- **Sort by Group, Then by Size**: organize code by (1) grouping related resources together, (2) sorting within each group by dependency count, (3) ordering the groups along an overall trend of increasing size
  - When to use: any cohesive, small enough to live in one main.tf; dependencies alone leave too much ambiguity
  - Analogy: sorting marbles by size alone doesn't help you find a color — group by color first
- **Serverless Definition**: not a single technology but any suite with (1) pay-as-you-go billing and (2) minimal ops overhead; sits between PaaS and SaaS on the control/work spectrum (IaaS → FaaS → PaaS → SaaS)
- **Strangler Façade Migration**: migrate legacy IaC (ARM/CloudFormation) to Terraform by wrapping the legacy stack (`azurerm_template_deployment` / `aws_cloudformation_stack`) and incrementally moving resources out into native Terraform until the legacy template can be decommissioned
  - Use for: migrations under SLA where a big-bang rewrite is impossible
- **Three Bridge Uses of ARM** (or CloudFormation): (1) resources unsupported/badly implemented by the provider, (2) migrating legacy code, (3) generating configuration code — export a deployed Azure resource group to ARM, deploy it from Terraform as rapid prototyping
  - Caveat: exported templates aren't 1:1 with what's deployed; and in Winkler's view generated config code has "limited use at best" — modules are the recommended vehicle for code reuse

## Key Concepts
- **Resource group** (Azure): mandatory container per deployment; deleting it deletes everything inside — the Azure analogue of AWS tagging/projects. Give each Terraform deployment its own.
- **Globally unique namespace right-padding**: join the namespace with a 24-char `random_string` and `substr(...)` to 24 — Azure needs global (cross-account) uniqueness
- **Shim module**: a trick to ship a build artifact (zip) through the Terraform Registry inside a module — downloaded by `terraform init` along with *everything in the module*, so untrusted modules can even run malicious local-exec code; always skim module source
- **SAS token**: Azure shared access signature — presigned, time-boxed URL granting scoped read access to a private blob; used here as `WEBSITE_RUN_FROM_PACKAGE` (expiry must be far in the future since Functions keeps re-reading)
- **Run-from-package deployment**: set app setting `WEBSITE_RUN_FROM_PACKAGE` to the presigned zip URL, so a single `terraform apply` deploys the whole function app
- **Auth methods for azurerm**: Azure CLI (easiest, interactive), managed identity, service principal + cert, service principal + secret (the automation-grade ones)
- **azurewebsites.net URL**: `https://<namespace>.azurewebsites.net/` via Dynamic/Y1 plan (`https_only = true`)

## Code Examples
```hcl
# Bridge gap: deploy an ARM template from Terraform
resource "azurerm_template_deployment" "template_deployment" {
  name                = "terraform-ARM-deployment"
  resource_group_name = azurerm_resource_group.resource_group.name
  template_body       = file("${path.module}/templates/iot.json")
  deployment_mode     = "Incremental"
  parameters = { IotHubs_my_iot_hub_name = "ghetto-hub" }
}

# Globally-unique namespace via random padding
resource "random_string" "rand" { length = 24, special = false, upper = false }
locals { namespace = substr(join("-", [var.namespace, random_string.rand.result]), 0, 24) }

# Presigned package URL for WEBSITE_RUN_FROM_PACKAGE
locals {
  package_url = "https://${azurerm_storage_account.storage_account.name}.blob
    core.windows.net/${azurerm_storage_container.storage_container.name}/
    ${azurerm_storage_blob.storage_blob.name}${data.azurerm_storage_account_sas.storage_sas.sas}"
}
```
- **What it demonstrates**: the two-penny website: resource group → storage account/container → blob (via shim module) → app_service_plan + application_insights + function_app, in exactly that dependency order

## Key Takeaways
1. Small cohesive deployments shouldn't get nested modules — one file, sorted by group then size.
2. Rule of thumb: a few hundred lines max per Terraform file before building a mental map gets hard.
3. Never hardcode secrets in config; authenticate the provider via CLI (dev) or service principal (automation).
4. Local values can be declared next to the resources that use them, not just at the top of the file.
5. Use ARM/CloudFormation as an escape hatch sparingly — modern Terraform covers nearly every resource.

## Connects To
- **Ch 7**: local-exec provisioners (the non-best-practice way people hack static website hosting in Azure)
- **Ch 8**: this scenario was originally AWS — designed for the multi-cloud capstone
- **Ch 13**: secrets management for provider credentials and SAS/connection strings