# Chapter 4: Terraform Modules and Reusable Infrastructure

## Core Idea
Modules turn one proven resource pattern into a parameterized unit with a strict contract: inputs (variables) for what consumers choose, locals for internal derived values, outputs for what consumers get; pin modules to version tags so upgrades are deliberate.

## Frameworks Introduced
- **Module Contract (inputs / locals / outputs)**: the three-part anatomy of every well-formed module
  - Inputs (`variables.tf`): what the consumer supplies; carry type constraints and descriptions, defaults for optional parameters. Never set values the consumer shouldn't control.
  - Locals: internal named computations (naming patterns, merges, derived tags) hidden from consumers — the module's private logic layer
  - Outputs (`outputs.tf`): the narrow, documented surface exposing resource IDs/IPs — add new outputs without breaking old consumers
- **Nested Module Composition**: parent module orchestrates child submodules
  - When to use: infrastructure big enough that one file would hold hundreds of resource blocks
  - How: parent (e.g. `azure_network`) defines VNet, calls child (`./modules/azure_subnet`) passing its own computed values down; root config references only the parent
- **Semantic Versioning + Git tags for modules**: tag releases (`v1.2.1`), reference `?ref=v1.2.1`; patch = bug fix, minor = additive, major (`v2.0.0`) = potential compatibility break; each environment upgrades on its own schedule

## Key Concepts
- **Module source forms**: local path (`"./modules/azure_vnet"`), git URL with subdir and ref (`git::https://github.com/org/repo.git//azure_vnet?ref=v1.2.1`), registries
- **Module README convention**: document inputs, outputs, and example calls — the module's user manual
- **Blueprint locality of benefit**: every environment derived from one library means fixes/tags/security roll out by bumping the shared ref, local deltas stay small
- **Local naming pattern**: `locals { vm_name_combined = "${var.project_prefix}-${var.environment_name}-vm" }` used by multiple resources

## Code Examples
```hcl
# Module definition (modules/azure_vnet/): main.tf + variables.tf + outputs.tf
resource "azurerm_virtual_network" "demo_vnet" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
}
output "vnet_id" {
  description = "ID of the created virtual network"
  value       = azurerm_virtual_network.demo_vnet.id
}

# Root configuration consumes it:
module "my_vnet" {
  source              = "./modules/azure_vnet"
  resource_group_name = "shared-resources"
  location            = "EastUS"
  vnet_name           = "vnet-production"
}

# Parent orchestrates child, passing computed values down:
module "subnet_module" {
  source                = "./modules/azure_subnet"
  vnet_name             = azurerm_virtual_network.parent_vnet.name
  subnet_address_prefix = var.subnet_address_prefix
}
```
- **What it demonstrates**: the module boundary — child consumes inputs, exposes outputs; parent composes children

## Worked Example
First module end-to-end (`azure_vnet_module/`):
1. `variables.tf`: `resource_group_name` (string, required), `location` (string, required), `vnet_name` (default `"default-vnet"`), `address_space` (default `["10.0.0.0/16"]`)
2. `main.tf`: create `azurerm_resource_group` from inputs, then `azurerm_virtual_network` referencing the RG's name
3. `outputs.tf`: expose `vnet_id`
4. Root call: `module "my_network" { source = "./azure_vnet_module" resource_group_name = "rg-shared" location = "EastUS" vnet_name = "vnet-staging" }`
5. Second environment: same module, `vnet_name = "vnet-prod"` — no code copied. Consume outputs later as `module.my_vnet.vnet_id`.

## Anti-patterns
- **One giant root file with hundreds of resource blocks**: unmaintainable, unshareable — decompose into focused submodules
- **Unpinned module sources**: referencing a mutable branch (or bare git main) means untested code sneaks into prod on the next `init`; always `?ref=<tag>`
- **Locals that belong to consumers, or inputs that belong to consumers**: locals are internal computation; inputs are consumer choices — blurring the boundary leaks implementation details across the module boundary
- **Environment-specific forks of a module**: per-environment copies drift exactly the way reusability exists to prevent; parameterize instead

## Key Takeaways
1. Write a module when the same pattern appears a second time — inputs carry the variation, code stays singular
2. Every module gets a README documenting inputs, outputs, and a sample invocation
3. Pin modules to semantic version tags; consumers opt in to upgrades deliberately by bumping `ref`
4. Outputs are deliberate contract design, not an afterthought — only expose what downstream configurations should couple to
5. Nest modules hierarchically (network → subnet, compute, storage) mirroring the architecture rather than by file convenience
6. Tag `v2.0.0` whenever a change might break consumers — the version bump is the communication channel

## Connects To
- **Ch 3**: inputs/outputs parameterize the variable techniques from config-language essentials
- **Ch 5**: modules + state: module changes manifest as state changes
- **Ch 10**: custom module authorship and registry-grade practices