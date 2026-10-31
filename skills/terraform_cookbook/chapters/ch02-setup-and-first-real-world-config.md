# Chapter 2: Setting up Terraform and Your First Real-world Configuration

## Core Idea
Once Terraform is installed, real-world work reduces to three decisions: which provider to configure and how to authenticate to it (without ever hard-coding secrets), how to write the resource recipe, and running the lifecycle init → plan → apply (→ destroy) — the same choreography on Azure, AWS, and GCP.

## Frameworks Introduced
- **Providers-as-Vendors authentication model**:
  - When to use: wiring Terraform to any cloud provider (AWS, Azure, GCP covered here).
  - How: pick the credential mechanism per provider in this order of preference — environment variables / shared credential files / managed identities (cloud-hosted); never hard-code keys in the provider block. `terraform init` downloads the provider plugin; no provider-specific SDKs needed.
- **Terraform workflow as cooking stages** (init = preheat, plan = dress rehearsal, apply = cook, destroy = clean up):
  - When to use: every project, every change.
  - How: `terraform init` downloads providers and sets up the backend (run once per project, or whenever providers/modules change); `terraform plan` shows the itemized diff and is idempotent; `terraform apply` prompts for confirmation then makes real API calls and writes state; `terraform destroy` reverses everything Terraform manages.
- **Multi-cloud parity pattern** (Recipes 10–12):
  - When to use: proving Terraform's cloud-agnosticism or running the same workload class in multiple clouds.
  - How: mirror the Azure recipe in `aws_ec2.tf` / `gcp_vm.tf` — HCL structure stays uniform; only provider block, resource names, and platform nuances (service accounts, key pairs, security groups) change.

## Key Concepts
- **Provider**: the bridge/plugin between Terraform and a platform's real APIs; declared in a `provider "<name>"` block, downloaded by `terraform init`.
- **`features {}`**: an empty block REQUIRED inside every `provider "azurerm"` block — omitting it fails with a missing-required-field error.
- **Service principal (Azure)**: a bot-like app registration with client ID/secret/tenant ID, given Contributor role; the headless auth path for CI.
- **Service account (GCP)**: a robot user with IAM roles and a downloadable JSON key; the recommended Terraform auth for GCP.
- **AMI**: Amazon Machine Image — the base image for an EC2 VM; IDs are region-specific, so prefer dynamic lookup via the `aws_ami` data source.
- **`user_data`**: startup script injected into an instance at launch (e.g., install Apache on boot).
- **State file (`terraform.tfstate`)**: written by `terraform apply`; Terraform's memory of what it created — do not edit manually, and .gitignore it.
- **`terraform plan -out=plan.tfplan`**: saves a plan for later exact application — the CI pattern of plan → human approval → apply saved plan.
- **`-target <resource_address>`**: advanced flag to limit destroy/apply to a single resource.

## Recipes in this chapter
- **Recipe 7: Parameterizing configurations with input variables** — variables.tf with `rg_name`/`location`, overridden at CLI via `-var="rg_name=rg-prod"`.
- **Recipe 8: Defining and using output values** — expose resource group ID and location; read with `terraform output`.
- **Recipe 9: Managing remote state for team collaboration** — create an Azure Storage account + `tfstate` container, then a `backend "azurerm"` block keyed on `chapter2.tfstate`.
- **Recipe 10: Launching a basic Azure VM** — full stack: VNet, subnet, static Standard public IP, NIC, Ubuntu `Standard_B1s` VM.
- **Recipe 11: Launching an AWS EC2 instance** — security group with SSH/HTTP ingress + open egress, then a `t2.micro` instance; proves multi-cloud with small config deltas.
- **Recipe 12: Launching a GCP VM instance** — `google_compute_instance` with Debian boot disk on the default network; watch out: enable required GCP APIs first.

## Anti-patterns
- **Hard-coding `access_key`/`secret_key` in the provider block**: secrets end up in version control; prefer environment variables (`AWS_ACCESS_KEY_ID`, `ARM_*`, `GOOGLE_APPLICATION_CREDENTIALS`) or shared credential files.
- **Hard-coding AMI IDs**: each region has different IDs and old AMIs go away — use the `aws_ami` data source with `most_recent = true` for portability.
- **Running plan/apply before `terraform init`**: Terraform will refuse ("Run terraform init first"); a very common newbie mistake.
- **Azure PowerShell login for Terraform**: Terraform only piggybacks on `az login`, not Azure PowerShell logins.
- **Committing state to Git**: .gitignore `terraform.tfstate`, `.tfstate.backup`, and the `.terraform` folder — share code, not state.
- **Forgetting GCP API enablement**: creating a resource whose API is disabled in the project errors out (e.g., Compute Engine API for VMs).

## Code Examples
```hcl
# AWS EC2 with dynamic AMI lookup (the author's recommended pattern over hard-coded AMI IDs)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  tags = {
    Name = "ExampleWebServer"
  }
}
```
- **What it demonstrates**: always fetch the latest matching image per region instead of pinning region-specific AMI IDs.

```hcl
# Chef's Special: install Nginx via the Azure Custom Script VM extension
resource "azurerm_virtual_machine_extension" "nginx" {
  name                 = "nginx"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = <<SETTINGS
{
  "commandToExecute": "sudo apt-get update && sudo apt-get install -y nginx"
}
SETTINGS
}
output "public_ip_address" {
  description = "Public IP address of the web server"
  value       = azurerm_public_ip.pip.ip_address
}
```
- **What it demonstrates**: post-boot configuration through a VM extension plus an output that hands the URL to the operator (`http://<public-ip>` should show the Nginx welcome page).

## Reference Tables
Provider authentication options (AWS / Azure / GCP):

| Provider | Local / interactive | Automated / headless | Cloud-hosted |
|---|---|---|---|
| AWS | Env vars `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_DEFAULT_REGION`; shared creds file (~/.aws/credentials + profile) | Same env vars in CI | IAM instance role (no keys) |
| Azure | `az login` (Terraform piggybacks on CLI token; subscription from CLI context) | Service principal: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` | Managed identity on Azure VM / Cloud Shell |
| GCP | ADC via `gcloud auth application-default login` | `GOOGLE_APPLICATION_CREDENTIALS` pointing at service-account JSON | Service account attached to the GCP VM |

Required provider-block nuances: Azure needs `features {}`; GCP needs `project` (plus optional `region`/`zone`); AWS needs `region`. Workflow facts: plan shows `Plan: 1 to add, 0 to change, 0 to destroy`; apply prints resource IDs (e.g., `i-0123456789abcdef0`) and `Apply complete! Resources: 1 added…`; destroy leaves `terraform.tfstate.backup`.

## Worked Example
**Chef's Special: Ubuntu VM + Nginx web server on Azure (three courses).**
1. *Appetizer*: in `chapter2_chef_special/main.tf`, declare `provider "azurerm" { features {} }`, resource group `web-rg`, VNet `web-vnet` `10.0.0.0/16`, subnet `web-subnet` `10.0.1.0/24` (full code on GitHub).
2. *Main course*: add the `azurerm_virtual_machine_extension "nginx"` Custom Script block (code above) to install Nginx inside the VM, plus a `public_ip_address` output.
3. *Dessert*: `terraform init` → `terraform apply` → `terraform output` to get the IP → open `http://<public-ip>` in a browser and confirm the "Welcome to Nginx" page.
4. Prerequisites carried from Chapter 1: ARM_* env vars from the service principal, `az login` from PowerShell, an SSH key pair, and Terraform v1.11.4 / AzureRM 4.27.0.

## Key Takeaways
1. Configure provider auth via environment variables or CLI piggybacking — keep every secret out of `.tf` files and Git.
2. `azurerm` requires an empty `features {}` block; missing it is a guaranteed init failure.
3. Run the same lifecycle on all three clouds: init → plan → apply; the mental choreography transfers exactly even as resource types change.
4. Prefer data-source lookups (`aws_ami` with `most_recent = true`) over pinned region-specific identifiers.
5. Save plans in CI (`terraform plan -out=plan.tfplan`) to enforce approval-before-apply pipelines.
6. Use VM extensions (`CustomScript`) or `user_data` for first-boot software installation rather than manual SSH configuration.
7. Expose the values operators actually need (public IP, IDs) as outputs immediately — they are the interface between Terraform and everything downstream.

## Connects To
- **Ch 1**: reuses its install/first-provider groundwork and the service-principal/SSH-key setup from its Chef's Special.
- **Ch 3**: Recipes 7–9 (variables, outputs, remote state) are deliberately shallow here — Chapter 3 formalizes variable typing/precedence, output consumption patterns, and backend migrations in depth.