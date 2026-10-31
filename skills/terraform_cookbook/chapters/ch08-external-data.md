# Chapter 8: Using Terraform with External Data

## Core Idea
Terraform can consume and produce context beyond its `.tf` files: built-in data sources read existing cloud state, the `external` data source runs any script that emits JSON, external files/env vars drive configuration, and `local-exec` provisioners trigger post-provision actions — chosen by a decision matrix, not by default.

## Frameworks Introduced
- **Decision matrix for external data integration (Table 8.1)**: match the mechanism to where the data lives.
  - When to use: deciding how to get external values into (or out of) a Terraform run.
  - How: Built-in data sources when provider APIs expose the data (preferred: trackable); external data source for custom scripts/APIs (must only fetch/compute, never provision); external input files/CLI vars for human-maintained config; local-exec/remote-exec for actions outside Terraform's tracking; terraform_remote_state for outputs from another Terraform config.
- **JSON-on-stdout protocol (external data source)**: Terraform runs your `program`, passes a JSON query on stdin, and expects a JSON object on stdout whose string keys/values land in `data.external.<name>.result`; non-zero exit or malformed JSON errors the run.
  - When to use: in-house APIs without a provider, on-the-fly generation (keys, passwords), parsing file formats Terraform can't (e.g., YAML until scripted), bridging to other tools for read-only info.
  - How: keep the script fast, stateless, and idempotent — it executes on every plan and apply.
- **null_resource + triggers pattern**: attach provisioners / side-effect commands to a do-nothing resource whose `triggers` map keys off real resource attributes, so the command reruns only when those values change.
  - When to use: post-deploy logging, notifications, hand-off to config management after resource creation.
  - How: set `triggers = { key = resource.attribute }`, put `provisioner "local-exec"` inside; changing a trigger value forces re-execution.
- **Prefer interpolation vs. environment argument in local-exec**: interpolate `${resource.attr}` for simple values; pass an `environment` map for complex values to avoid shell injection.
  - How: `environment = { VM_IP = self.public_ip_address }`, then reference `$VM_IP` in the command.

## Key Concepts
- **Data source**: read-only information retrieved from outside the current configuration via a `data` block — it never creates or modifies infrastructure, and lookups happen automatically before dependents are created (errors at plan time if not found).
- **Input variables vs. data sources**: variables are values you supply for parameterization; data sources are looked up automatically — prefer lookup when the info can be fetched (latest SKU, account ID) rather than typed in.
- **`data.external.<name>.result`**: the string-keyed string-valued map produced by an external program; all values are strings, so numeric results need `tonumber()` and arrays must be JSON-serialized and re-decoded with `jsondecode()`.
- **`.tfvars` files / `TF_VAR_<NAME>`**: external variable-definition files (`-var-file="dev.tfvars"`) and `TF_VAR_`-prefixed env vars let CI/CD inject config without touching code.
- **`file()` + `jsondecode()`**: built-in combination to ingest a structured JSON file as a native Terraform list/map; YAML needs `yamldecode()` or an external script (no native YAML parsing otherwise).
- **local-exec vs. remote-exec**: `local-exec` runs on the machine where Terraform runs (orchestrator side — notifications, Ansible, pipeline triggers); `remote-exec` SSHes/WinRMs into the created resource to bootstrap it; both run only once on creation.
- **`terraform_remote_state` data source**: read another configuration's outputs from its backend (`backend = "local"` with a path, or `"azurerm"` with storage account/container/key); creates coupling — the consumer silently trusts the base's state.
- **Provisioners as last resort**: HashiCorp guidance — prefer cloud-init, VM extensions, or an external config management tool; a failed provisioner marks the resource errored but does NOT roll back created resources (`on_failure = continue` is a careful last resort).
- **`triggers` re-run semantics**: provisioners run on create by default; triggers on a `null_resource` prevent duplicate side effects on unchanged applies and force reruns when values change.

## Recipes in this chapter
- **Recipe 43: Retrieving cloud data** — use an `azurerm_resource_group` data source to look up an existing RG and deploy a storage account into it.
- **Recipe 44: External API call for configuration** — `data "external"` with `curl` against ipify to auto-allow only your current IP in an NSG SSH rule.
- **Recipe 45: Generating config from external file** — `jsondecode(file(...))` over an environments.json drives `for_each`-created, tagged resource groups per environment.
- **Recipe 46: Passing data to an external script** — `null_resource` + `local-exec` appends storage-account deployment info to `deploy_log.txt`, interpolating resource attributes.
- **Recipe 47: Terraform remote state as data** — a consumer config reads a base config's `../base/terraform.tfstate` outputs to place its storage account; azurerm-backend variant shown.
- **Recipe 48: Orchestrating with external orchestration tools** — full VNet/NSG/VM stack with `remote-exec` (install Apache over SSH) plus `local-exec` logging, then curl verification.
(Note: chapter prose sometimes cites "Recipe 47, Retrieving cloud data" / "Recipe 46" inconsistently with the actual numbering above — trust the recipe headings.)

## Anti-patterns
- **Using the external data source as a first resort**: HashiCorp suggests it only when no better option exists — it executes on every plan/apply, can't detect external changes by itself (needs re-runs, tainting, or `triggers` on a null_resource), and risks exposing secrets (use `sensitive` outputs).
- **Using the external data source to provision**: it should only fetch or compute data, never change infrastructure.
- **Provisioner commands that are not idempotent**: local-exec side effects are untracked by state; guard scripts (e.g., "did I already send this notification?") or use `triggers` to avoid duplicate actions on re-apply.
- **Relying on provisioners for ongoing configuration**: they run once at creation, fail without rollback, and won't rerun without recreation or taint — delegate large-scale config to Ansible/cloud-init.
- **Hardcoding references to pre-existing resources**: brittle when the RG name or AMI ID changes — look them up with data sources instead.
- **Storing sensitive data in plain external files**: review file changes like code and prefer Vault or `sensitive` markings.
- **Permanent `-target` / heavy CLI-fallback reliance in local-exec**: undermines Terraform's dependency management and leaves CLI-caused changes untracked.

## Code Examples
```hcl
data "external" "config_api" {
  program = ["curl", "-s", "https://api.example.com/infra-config"]
  # This API returns JSON like {"vm_count": "3", "vm_size": "Standard_D2s"}
}
resource "azurerm_virtual_machine_scale_set" "app" {
  count = tonumber(data.external.config_api.result.vm_count)
  # ... use vm_size etc from the external data ...
}
```
- **What it demonstrates**: any JSON-emitting program (even bare `curl`) becomes a data source; string results are converted with `tonumber()`.

```hcl
locals {
  env_config = jsondecode(file("${path.module}/environments.json"))
  env_map    = { for env in local.env_config : env.name => env }
}
resource "azurerm_resource_group" "env" {
  for_each = local.env_map
  name     = "${each.key}-rg"
  location = var.location
  tags = {
    Owner       = each.value.owner
    CostCenter  = each.value.cost_center
    Environment = each.key
  }
}
```
- **What it demonstrates**: driving `for_each` from a team-maintained JSON file — add an entry, next apply creates its RG with no Terraform code change; keyed by name (not `count` index) so removals destroy the right resource.

## Reference Tables
Table 8.1 — Choosing the right method for external data integration:

| Method | Usage | Examples | Notes |
|---|---|---|---|
| Built-in data sources | Data available via cloud/provider APIs | VPC/subnet IDs, latest AMIs, Azure images, AWS SSM params | Preferred: simple, native, fully trackable |
| External data source | Data from a custom script/system Terraform can't reach | Internal APIs, computing values, non-standard files | Fetch/compute only; never provision |
| External input files or CLI vars | Static, human-maintained config outside Terraform | JSON/YAML environment configs edited by teams | Ideal for config-driven, team-friendly workflows |
| local-exec / remote-exec | Actions must run outside Terraform's resource management | Notifying tools, Ansible, logging, triggering pipelines | Side effects untracked; make idempotent; local-exec runs where Terraform runs |
| terraform_remote_state | Consuming outputs from another Terraform config | Network IDs, shared secrets, foundational-infra outputs | Cross-project linking; creates coupling; needs state access |

## Worked Example
Chef's Special — data-driven deployment in three courses (`chapter8\chef-special-data-driven`):
1. **Appetizer — Fetching dynamic deployment configuration** (`modules/config`): `data "external" "deployment_config"` runs `python config-fetcher.py`, which emits `{"region": "uksouth", "environments": "[\"dev\",\"test\",\"prod\"]", "allowed_ips": "..."}` — the script JSON-serializes arrays because the external source only accepts string values. Locals decode: `region = data.external.deployment_config.result["region"]`, `environments = jsondecode(...result["environments"])`, etc.
2. **Main course — Environment provisioning** (`modules/infra`): `resource "azurerm_virtual_network" "vnets" { for_each = toset(var.environments) ... }` with address space computed as `["10.${100 + index(var.environments, each.key)}.0.0/16"]`; subnets `for_each = azurerm_virtual_network.vnets` on a /24 one octet-octet deeper; outputs a subnet-ID map.
3. **Dessert — Root orchestration** (`deployment/`): root module wires `module "config"` and `module "infra"` (passing `region`, `environments`, `rg_name = "chef-special-rg"`), writes `local_file "notification"` with `jsonencode({ status = "success" })`, and a notify module's `null_resource.local-exec` PowerShell call emits `output.json`.
Verification: three VNets/subnets (vnet-dev, vnet-test, vnet-prod) plus the notify output file — the whole deployment shaped by an external Python "CMDB".

## Key Takeaways
1. Use a data source before a variable whenever the value can be looked up — plan-time errors if it's missing are a safeguard, not a nuisance.
2. Wrap external scripts/APIs in `data "external"` only when no provider exists, and keep the program fast, stateless, and string-typed; serialize arrays as JSON text.
3. Prefer `file()`/`jsondecode()` over the external data source for on-disk static files — no process spawn, simpler.
4. Use `null_resource` + `triggers` to both order and throttle local-exec side effects; interpolate attributes for simple values, `environment` for shell-sensitive ones.
5. `terraform_remote_state` cleanly splits team-owned configs but couples consumers to the base's state — share only necessary, non-sensitive outputs.
6. A failed provisioner never rolls back created resources; design provisioner actions to be repeatable and rerunnable.
7. Provisioners are a last resort: cloud-init, VM extensions, or a dedicated config-management tool handle ongoing configuration better.

## Connects To
- **Ch 7 (state/backends)**: `terraform_remote_state` consuming another config's outputs depends on where state lives (local vs azurerm backend shown here).
- **Ch 9 (Scaling)**: external files driving `for_each` here is the same mechanism Ch 9 uses for multi-region/multi-environment replication; remote-exec/local-exec orchestration in Recipe 48 sets up the blue-green lifecycle patterns next.