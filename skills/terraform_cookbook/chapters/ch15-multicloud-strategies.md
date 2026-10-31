# Chapter 15: Multi-cloud Deployment Strategies with Terraform

## Core Idea
Terraform unifies Azure, GCP, and AWS provisioning with one declarative workflow — multiple provider blocks with aliases, per-cloud authentication patterns, wrapper modules that pass providers down, and orchestration via Terragrunt or workspaces — so multi-cloud becomes repeatable code instead of fragmented consoles.

## Frameworks Introduced
- **Multiple providers + aliasing**: declare `azurerm`, `google`, `aws` independently in one root; alias instances (`alias = "east"` / `"west"` with different `subscription_id`s) for multi-account or multi-region targets; reference them via the `provider` meta-argument.
  - When to use: one module must target several clouds, accounts, or regions simultaneously.
  - How: descriptive alias names (dev, prod, us-west) + `terraform validate` to avoid misallocated resources.
- **Per-cloud authentication matrix**: Azure = Service Principal env vars (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`), Managed Identity, or OIDC federation via HCP Terraform; GCP = service-account JSON key (`credentials = file(...)`), Application Default Credentials (`gcloud auth application-default login`), OIDC; AWS = env vars (`AWS_ACCESS_KEY_ID`...) / `AWS_PROFILE`, IAM roles with OIDC, Vault-backed dynamic credentials.
  - When to use: pick basic methods for local dev, dynamic short-lived credentials (OIDC/Vault/secret managers) for enterprise.
- **Cloud-agnostic vs provider-specific modules**: agnostic modules abstract shared patterns (VMs, networking, DNS) via `count`, `for_each`, dynamic blocks — only where real cross-provider equivalence exists; when services diverge (storage account vs S3), use `modules/aws/`, `modules/azure/`, `modules/gcp/` trees with consistent input/output interfaces.
  - How: wrapper module declares its own `required_providers` and conditionally calls the cloud-specific submodule; root passes providers down with the `providers` meta-argument; provider config stays in the root only.
- **Cross-cloud coordination set**: site-to-site VPN (Azure Virtual Network Gateway ↔ Google Cloud VPN), federated Kubernetes with Consul, remote state data sources passing subnet IDs/IPs between clouds, global DNS (Route 53 latency/geo routing, Azure alias records, Cloud DNS + global traffic services), shared CI/CD targeting any provider from the same config.
- **Terragrunt orchestration**: DRY backend/provider config via `generate` blocks, one unit per cloud with isolated state, single command `terragrunt run --all apply` (legacy: `run-all apply`).

## Key Concepts
- **Provider aliasing**: multiple configurations of the same provider distinguished by `alias`; critical for the same module to hit different clouds or subscriptions in one plan.
- **Application Default Credentials (ADC)**: GCP's environment-based auth; the recommended method for local development and CI, avoiding embedded key files.
- **OIDC federation**: dynamic short-lived tokens per Terraform run (GitHub Actions → Azure, HCP Terraform) instead of long-lived client secrets; reduces theft risk and improves auditability.
- **Vault-backed credentials**: HashiCorp Vault or cloud secret stores (Secrets Manager / Key Vault / Secret Manager) issuing rotated, policy-driven credentials fetched via Terraform data sources at runtime.
- **Active-active deployment**: workloads live in multiple clouds with global load balancing / DNS steering to the healthy/nearest origin; Traffic Manager with Performance routing + HTTPS probes over Azure + external (Cloud Run) endpoints.
- **Workspace-per-cloud pattern**: one configuration where `terraform.workspace` ("azure"/"gcp") selects the resource set via `locals`/`count`; each workspace holds independent state (S3 backend: `workspace_key_prefix = "env"` → `env/<workspace>/...tfstate`).
- **State splitting at scale**: separate remote state with locking/encryption/versioning per cloud; Terragrunt or Terramate to manage many small units; workspaces only for minor variation, never heavy conditional logic sharing one backend.
- **GatewaySubnet**: Azure's mandatory subnet name (≥ /27 for most SKUs) for VPN gateway deployment.
- **Storage Transfer Service SAS**: GCS transfer job authenticating to Azure via container-level Shared Access Signature (Read + List), the option the Terraform resource currently supports (vs federated identity/Secret Manager).

## Recipes in this chapter
- **Recipe 85: Dual-cloud hello world** — one `terraform apply` creates a Linux VM on Azure and one on GCP; providers declared at root, auth via `az login` + `gcloud auth application-default login`.
- **Recipe 86: Cross-cloud networking** — Azure Virtual Network Gateway (IPsec, GatewaySubnet) ↔ Google Classic VPN with static routes and forwarding rules for ESP/UDP 500/4500; sensitive `psk` variable. Lab pattern — production prefers HA VPN with BGP and Azure active-active.
- **Recipe 87: Multi-cloud module reuse** — wrapper module `modules/web_server` conditionally calls `azure/` and `gcp/` submodules; root passes aliased providers via `providers` meta-argument; NGINX installed via `custom_data` + `base64encode()` on Azure and `metadata_startup_script` on GCP.
- **Recipe 88: Active-active multi-cloud deployment** — Azure Linux Web App + GCP Cloud Run v2 (with `roles/run.invoker` to `allUsers`) fronted by an Azure Traffic Manager profile (Performance routing, HTTPS probes on `/`); Traffic Manager fails over between Azure and external endpoints by probe status.
- **Recipe 89: Orchestrating multi-cloud with Terragrunt** — `live/azure/app` and `live/gcp/app` units each with a `terragrunt.hcl` pointing at the module and `generate "provider"` blocks so modules stay provider-agnostic; `terragrunt run --all apply` deploys both; pre-create the Azure storage account for state (auto-creation covers only S3/GCS).
- **Recipe 90: Multi-cloud with Terraform workspaces** — `terraform.workspace` drives `contains(["azure","gcp"], terraform.workspace)` local; `try(azurerm_resource_group.rg[0].name, null)` outputs make cloud-specific resources null when inactive; backend blocks cannot interpolate variables.

## Anti-patterns
- **Monolithic single-`main.tf` root**: mixed resources become unreadable and fragile — split modules per concern (compute, networking, storage, security).
- **One module creating all environments together**: no boundaries; use independent per-environment modules/state.
- **Hard-coded values and broad resource groups**: parameterize inputs with meaningful defaults instead.
- **Pretending provider-agnostic abstraction where none exists**: Terraform does not translate resource types; fake equivalence (storage account ≡ S3) produces unmaintainable conditionals.
- **Workspace misuse**: heavy conditional logic across environments sharing one backend co-mingles state — use separate configurations for significant differences.
- **Ambiguous provider alias names**: lead to resources landing in the wrong subscription/region; use descriptive aliases and validate.
- **Shared/co-mingled state across clouds**: prevents blast-radius isolation; isolate state per cloud for security and recovery.
- **Embedding provider blocks in child modules**: causes unpredictable per-module provider behavior; provider settings belong in the root.
- **Uncontrolled drift in multi-cloud**: miscalculated plans can unintentionally destroy resources; monitor via scheduled plan checks.

## Code Examples
```terraform
# Root: multi-provider with aliases (providers stay in the root only)
provider "azurerm" {
  alias           = "east"
  features        = {}
  subscription_id = var.az_sub_east
}
provider "azurerm" {
  alias           = "west"
  features        = {}
  subscription_id = var.az_sub_west
}

# Passing providers into a wrapper module (Recipe 87)
module "web_azure" {
  source    = "./modules/web_server/azure"
  providers = { azurerm = azurerm.east }
}
```
- **What it demonstrates**: alias + `providers` meta-argument, the supported pattern for centralizing provider configuration while keeping child modules portable.

```terraform
# Terragrunt unit: live/gcp/app/terragrunt.hcl
terraform {
  source = "../../../modules/gcp-app"
}
# Generate the provider for Google so modules remain provider-agnostic
generate "provider" {
  path      = "provider.google.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
EOF
}
```
- **What it demonstrates**: Terragrunt's `generate` block injecting provider config at runtime, keeping the module provider-free (Recipe 89).

Workspace toggle (Recipe 90):
```terraform
locals {
  target_cloud = contains(["azure", "gcp"], terraform.workspace) ? terraform.workspace : "azure"
}
output "azure_resource_group" {
  value       = try(azurerm_resource_group.rg[0].name, null)
  description = "Azure RG name when in the 'azure' workspace"
}
```

Secret fetch at runtime (AWS Secrets Manager):
```terraform
data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = "prod/db"
}
resource "aws_db_instance" "db" {
  username = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["username"]
  password = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["password"]
}
```

## Reference Tables
**Authentication methods across multi-clouds (Table 15.1)**

| Cloud | Basic method | Enterprise optional practice |
|---|---|---|
| Azure | Service principals, CLI login | Managed identity, Vault, OIDC federation |
| GCP | Service Account Key, ADC | Dynamic credentials via HCP Terraform OIDC |
| AWS | Environment variables, AWS profile | IAM roles with OIDC, Vault-based credential retrieval |
| Overall | Static credentials | Vault-managed secrets, Zero Trust identity, policy as code, auditable/revocable credentials |

**Anti-pattern vs best practice (Table 15.2)**

| Pattern type | Anti-pattern (Monolithic) | Best practice (Modular & sustainable) |
|---|---|---|
| Directory layout | All logic in one `main.tf` | Separate modules for compute, networking, storage, security |
| Resource scope | Single module creates all environments | Independent dev/staging/prod modules with clear boundaries |
| Reusability | Hard-coded values, broad resource groups | Parameterized inputs with meaningful defaults |
| Sustainability | Redundant per-environment resources | Shared services (DNS, identity, logging) in common modules |

**Multi-cloud use case triggers**: active-active (availability/latency), backup & failover (DR standby), best-of-breed services (Azure identity, GCP AI/Analytics, AWS scale), data sovereignty/compliance (EU/US/APAC residency), cloud bursting for seasonal spikes, hybrid on-prem extension (VPN/firewall managed in Terraform).

## Worked Example
Chef's Special — **cross-cloud ML pipeline** (`chef_special_ml_pipeline`; Appetizer → Main course → Dessert):
1. **Appetizer (Azure setup, `main_azure.tf`)**: `random_string` suffix → RG `rg-ml-<suffix>` → Storage account + Container Registry + Key Vault + Application Insights (Azure ML workspace dependencies) → Azure ML workspace → small compute cluster for preprocessing; Blob container `raw` holds raw data.
2. **Main course (GCP setup, `main_gcp.tf`)**: `google_storage_bucket` `ml-processed-<suffix>-<project>` with `force_destroy = true` and `uniform_bucket_level_access = true`; a Compute Engine VM with a T4 GPU attached via `guest_accelerator` for training (use Deep Learning VM images to preinstall ML frameworks, or install NVIDIA drivers manually).
3. **Dessert (Azure → GCS transfer, `transfer.tf`)**: `google_storage_transfer_job "azure_to_gcs"` pulls from the Azure Blob container into GCS, authenticated with a container SAS token (`var.azure_container_sas_token`, starts `?sv=`, minimum Read + List on container and objects), `status = "ENABLED"`.

Flow: `az login` + `gcloud auth application-default login` → `terraform init` → `terraform apply -auto-approve` → the transfer job copies data → verify objects in the GCS bucket → run training on the GPU VM reading `gs://<bucket>`. Verification checklist: Azure ML workspace with all four dependencies exists; GCS bucket initially empty; GPU VM running with driver installed (check `/var/log/syslog`, `/var/tmp/train.log`); transfer job enabled in console or state. Scaling path: replace the single VM with GPU instance groups or Vertex AI custom jobs/pipelines; use Secret Manager or federated identity over SAS where possible, and keep Terraform state isolated per cloud.

## Key Takeaways
1. Declare all providers at the root, alias them descriptively, and pass them into modules with the `providers` meta-argument — never embed provider blocks in child modules.
2. Match the auth method to context: ADC/env vars/profiles for local dev; OIDC federation, Managed Identity, or Vault for pipelines — eliminating long-lived static credentials.
3. Be aggressively provider-specific where services genuinely differ (storage account vs S3); wrap per-cloud implementations in a wrapper module exposing consistent inputs/outputs.
4. Isolate Terraform state per cloud (locking + encryption + versioning); scale with Terragrunt (`terragrunt run --all apply`) rather than mega-configs, and reserve workspaces for minor variation only.
5. Wire cross-cloud traffic with managed primitives: Traffic Manager (Performance routing + HTTPS probes) can health-check Azure and external endpoints alike, failing over automatically.
6. Coordinate dependencies across clouds through remote state data sources (subnets, IPs) and centralize DNS, identity, and CDN as shared, referenced infrastructure.
7. Run policy as code (OPA/Checkov/Terrascan/tfsec) before any multi-cloud apply — more providers means more naming, aliasing, and drift risk.

## Connects To
- **Ch 13**: vault secrets, least-privilege identities, OIDC, policy as code, and state isolation are exactly the security practices this chapter applies per cloud.
- **Ch 14**: multi-provider configs multiply authentication and drift error classes — use the per-cloud auth debug sequence there.
- **Ch 4**: wrapper/provider-injection patterns extend module composition to multi-provider trees.
- **Ch 16**: Terragrunt-style orchestration and shared services converge with HCP Terraform's remote state, VCS integration, and private module registry for team-scale delivery.