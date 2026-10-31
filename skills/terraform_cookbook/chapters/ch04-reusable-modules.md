# Chapter 4: Building Reusable Configurations with Terraform Modules

## Core Idea
Modules turn monolithic Terraform scripts into DRY, reusable units: encapsulate one concern (network, compute, storage) per module, expose its knobs as input variables, return what callers need as outputs, and pin versions so teams share code safely.

## Frameworks Introduced
- **Root module / child module pattern**: every Terraform configuration has at least one root module; child modules group related resources and are called from the root.
  - When to use: always — split any config that mixes concerns (VNet + VMs + storage in one file).
  - How: break a monolithic `main.tf` into `modules/network`, `modules/compute`, `modules/storage`; each child gets `main.tf`, `variables.tf`, `outputs.tf`; the root calls them with `module` blocks and wires outputs into sibling inputs.
- **Module call contract (inputs in, outputs out)**: "When you call a module, you pass in variables just like ingredients. The module executes and returns outputs."
  - When to use: any time you reference a module from a parent.
  - How: pass named arguments on the `module` block that match `variable` declarations in the child; the child exposes `output` blocks consumed as `module.<name>.<output>`.
- **Module composition/chaining**: one module's output becomes another module's input.
  - When to use: infrastructure dependencies (e.g., compute needs a subnet created by the network module).
  - How: output the resource ID (`subnet_id`) from the producer module, pass `module.network.subnet_id` into the consumer module — Terraform tracks the dependency automatically.
- **One module, many environments via variable files**: define the module once, feed it `dev.tfvars` / `prod.tfvars` with `-var-file=`.
  - When to use: per-environment settings (tier, replication type) with identical code.
  - How: `terraform apply -var-file="prod.tfvars"`.
- **Module lifecycle workflow**: team developers write and test the module → push to Git with semantic version tags → CI/CD validates quality → tagged release is published to the Terraform Registry, plus a README with usage examples.

## Key Concepts
- **Module**: a container grouping resources commonly used together — input variables, resource declarations, output values, and optional further child modules.
- **Root module**: the top-level configuration Terraform runs; every configuration has one.
- **Input variable (`variable`)**: typed, described declaration in the child module that validates values passed from the parent; keeps modules free of hardcoded values.
- **Output value (`output`)**: a value the child module returns to the parent (e.g., `vnet_id`), referenced as `module.<name>.<output>`.
- **Module source**: where a module is fetched from — local path, Git repo, or Terraform Registry.
- **Version pinning**: constraining a registry module to an exact/compatible version and upgrading deliberately with `terraform init -upgrade` — prevents accidental breaking-change adoption.
- **`count` meta-argument on modules**: instantiates the same module N times with `count.index` varying parameters (e.g., per-environment VNets `dev`, `qa`, `prod`).
- **`terraform.tfvars`**: file supplying values for root variables; per-environment variants (`dev.tfvars`, `prod.tfvars`) select configurations.
- **Refactoring**: splitting one monolithic `main.tf` into single-responsibility modules to gain reuse, readability, and scalability.

## Recipes in this chapter
- **Recipe 19: Using a Terraform Registry module** — deploy an Azure VNet with the public `Azure/network/azurerm` module; two-step deploy: create the resource group first, then apply the module inside it (`version = "3.5.0"`).
- **Recipe 20: Creating a local module** — extract a Linux VM (NIC + VM + SSH key) into `./modules/vm` with `main.tf`/`variables.tf`/`outputs.tf` and call it from a root config that owns RG/VNet/subnet.
- **Recipe 21: Module version pinning** — pin `Azure/compute/azurerm` to `5.3.0` and upgrade safely (`version = "5.3.1"` + `terraform init -upgrade`); use targeted applies to create foundational network resources before the VM module.
- **Recipe 22: Linking modules together** — network module outputs `subnet_id`, compute module consumes it as an input; Terraform automatically respects the dependency.
- **Recipe 23: Multiple module instances** — one network module block with `count = length(local.envs)` deploys three VNets (`dev`, `qa`, `prod`) with per-index address spaces `["10.${count.index}.0.0/16"]`.
- **Recipe 24: Reusing modules for different environments** — one storage module deployed twice via `dev.tfvars` (Standard/LRS) and `prod.tfvars` (Premium/GRS), with a `random_string` suffix for globally unique account names.

## Anti-patterns
- **Monolithic single-file configuration**: one `main.tf` doing VNet + VMs + storage becomes hard to maintain and impossible to reuse across projects/environments.
- **Hardcoded values inside modules**: prevents reuse; route anything caller-specific through `variables.tf`.
- **Unpinned registry module versions**: `terraform init` upgrades can pull in breaking changes; always set `version =` on registry sources.
- **Ignoring preconditions of registry modules**: e.g., the Azure network module expects the resource group to already exist — deploy it in a first step, not inside the module call.
- **Modules with vague names and no README**: unclear modules/variables confuse consumers; include self-documenting naming and an example-usage README.

## Code Examples
```hcl
module "vnet" {
  source              = "./modules/network"      # Local path to the child module
  resource_group_name = var.rg_name              # Passing input variables
  location            = var.location
  address_space       = ["10.0.0.0/16"]
  subnet_names        = ["subnet1"]
}
```
- **What it demonstrates**: the anatomy of a module call — source + named input arguments.

```hcl
module "network" {
  source          = "./modules/network"
  vnet_name       = "linked-vnet"
  address_space   = ["10.10.0.0/16"]
  rg_name         = azurerm_resource_group.rg.name
  location        = azurerm_resource_group.rg.location
}

module "compute" {
  source     = "./modules/compute"
  subnet_id  = module.network.subnet_id   # output of one module feeds the next
}
```
- **What it demonstrates**: module chaining via outputs; Terraform auto-orders network before compute.

```hcl
module "vnet" {
  count         = length(local.envs)
  source        = "./modules/network"
  env           = local.envs[count.index]
  address_space = ["10.${count.index}.0.0/16"]
}
```
- **What it demonstrates**: multiplying one module across environments with `count` + `count.index`.

## Reference Tables
**Table 4.1 — Module sources:**

| Source type | Example | Description |
|---|---|---|
| Local path | `./modules/network` | Module stored in your local project folder |
| Git repository | `git::https://github.com/example/vm.git?ref=v1.2.0` | Fetches module at a specific version (tag/commit) |
| Registry | `Azure/network/azurerm` (+ `version = "3.0.0"`) | Official/community modules from registry.terraform.io |

**Table 4.2 — Golden rules for module reusability and maintainability:**

| Best practice | Purpose and impact |
|---|---|
| Keep modules small and focused | Easier to understand, test, maintain (e.g., a module for just the network) |
| Avoid hardcoded values | Use variables.tf so it's configurable from outside |
| Use clear naming | Modules and variables become self-documenting |
| Include a README with examples | Others adopt your module quickly |
| Use version control and tagging | Stability, rollback, team-wide consistency |

## Worked Example
**Chef's Special — three-tier architecture module kit** (`chef-special-threetier/`): compose three purpose-built modules into one root configuration in `westeurope`.

1. **Appetizer — network module**: one `azurerm_virtual_network` on `10.0.0.0/16` plus three explicit subnets — `web` (10.0.1.0/24), `app` (10.0.2.0/24), `db` (10.0.3.0/24). The db subnet carries a `delegation` block to `Microsoft.DBforPostgreSQL/flexibleServers`. Outputs `web_subnet_id`, `app_subnet_id`, `db_subnet_id`, `vnet_id`.
2. **Main course — compute module**: `azurerm_public_ip` (Static/Standard) + `azurerm_lb` + `azurerm_lb_backend_address_pool` + NICs and VMs under `count = var.vm_count` (default 2, `Standard_B1s`, Ubuntu 22.04), each NIC linked via `azurerm_network_interface_backend_address_pool_association`. LB distribution: NIC 0 → VM 0, NIC 1 → VM 1.
3. **Dessert — database module**: `azurerm_private_dns_zone` (`privatelink.postgres.database.azure.com`) + VNet DNS link + `azurerm_postgresql_flexible_server` (version 13, default SKU `B_Standard_B1ms`, storage 32768 MB) with `public_network_access_enabled = false`, placed in the delegated db subnet with a private DNS zone. Output `db_fqdn` only.
4. **Root wiring**: `random_string` suffix guarantees a unique PostgreSQL name `${var.db_name_prefix}${random_string.db_suffix.result}`; sensitive DB credentials arrive via `terraform.tfvars`.
5. **Execution**: `terraform init` → `terraform plan -var-file="terraform.tfvars"` → `terraform apply -auto-approve -var-file="terraform.tfvars"`; verify a server named like `pgflexdbxxxxx` plus all three tiers in the portal.

## Key Takeaways
1. Split every config that mixes concerns into single-responsibility modules; the file tree `modules/<area>/{main,variables,outputs}.tf` is the expected shape.
2. Registry modules are the fastest path but read their contract first — many (like `Azure/network/azurerm`) require the resource group to already exist.
3. Chain modules with outputs, not with `depends_on`: passing `module.network.subnet_id` into compute encodes the dependency naturally.
4. Pin every registry module version and upgrade by deliberate edit + `terraform init -upgrade`, not by blank sources.
5. Use `count` + `count.index` to stamp the same module out per environment when instances vary only by parameters; use per-environment `-var-file`s when values differ wholesale.
6. Prefer remote sources (`git::…?ref=<tag>`, registry) over local paths for team-shared modules, and gate them with semver tags + CI validation.

## Connects To
- **Ch 3 (state/variables foundations)**: variables and tfvars feeding modules are the mechanism for per-environment reuse.
- **Ch 5 (compute instances)**: the compute module pattern here (NICs, VMs, load balancer) is exactly what Ch 5 provisions at resource level with VMSS, cloud-init, and cross-cloud examples.
- **Ch 6+ (networking/security, CI/CD)**: the module lifecycle (Git tags → CI validation → published release) is the delivery pipeline for shared infrastructure code.