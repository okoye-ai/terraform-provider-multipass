# Chapter 2: Getting Started with Terraform

## Core Idea
Getting productive with Terraform = install the CLI, understand HCL's building blocks (blocks, arguments, expressions), and internalize the core workflow: `init → write → fmt/validate → plan → apply → destroy`.

## Frameworks Introduced
- **The Terraform Workflow**: init → write → plan → apply, with `fmt`/`validate` as optional guardrails.
  - When to use: every change to every configuration — this loop is the book's reference work cycle.
  - How: `terraform init` (backend + plugins + modules + state setup) → write `.tf` files → `terraform fmt` (style) & `terraform validate` (syntax/schema check) → `terraform plan` (preview diff against current state) → `terraform apply` (execute, confirms unless `--auto-approve`) → `terraform destroy` (teardown, also confirms).
- **HCL Building Blocks**: blocks → arguments → expressions.
  - A **block** is a structural element starting with a type in `{}`: `terraform {}`, `provider "google" {}`, `resource "..." "..." {}`.
  - **Arguments** are key-value pairs configuring a block (`region = "us-central1"`).
  - **Expressions** assign values to arguments (`location = "US"`), including references like `var.zone`.

## Key Concepts
- **`terraform init`** does four jobs: initializes the **back end** (where state is stored — local or remote like GCS/Azure Storage/Terraform Cloud), downloads **provider plugins** (e.g. `hashicorp/google v5.38.0`), sets up **modules**, and configures **local state** (`terraform.tfstate`).
- **Dependency lock file**: pins provider versions between runs; `init` reuses them ("Reusing previous version of hashicorp/google").
- **`terraform validate`**: syntax + schema check that blocks the pipeline before plan/apply if broken.
- **`--auto-approve`**: skip interactive confirmation — discouraged for `destroy` to avoid unintentional deletions.
- **Plan action symbols**: `+` create, `~` modify, `-` destroy; "no changes" output is healthy.
- **Version pinning**: book uses Terraform 1.9 and provider `979`-versioned google provider 5.38.0; for production, pin specific versions, never `latest`.

## Mental Models
- Think of the working directory as the project root: init first, else every command reminds you to re-init (Terraform detects stale initialization).
- Think of HCL vs JSON/YAML as "structured config vs raw data serialization": HCL is built for blocks + hierarchy + better error messages, and it's the shared language of other HashiCorp tools (Vault, Nomad), so learning it transfers.
- Think of `plan` as the human-error firewall: it surfaces configuration drift and every +/~/- action before anything happens.
- Treat `destroy` as a review-first operation: read the plan, then consult the team/stakeholders before confirming — "there is no undo. Only 'yes' will be accepted."

## Code Examples
Minimal working configuration (`main.tf`):
```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.38.0"
    }
  }
}

provider "google" {
  project = "terraform-made-easy"  # replace to your project id
  region  = "us-central1"
  zone    = "us-central1-a"
}

resource "google_storage_bucket" "default" {
  name          = "ivys_bucket_a"  # give your unique bucket name
  location      = "US"
  storage_class = "STANDARD"
}
```
- **What it demonstrates**: the three-block skeleton every config starts from — terraform (provider pinning), provider (project/region/zone), resource.
Variables keep configs reusable:
```hcl
variable "region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "us-central1"
}
resource "google_compute_instance" "compute_instance" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
}
```
Outputs export values for later runs or external scripts:
```hcl
output "vpc_networks" {
  value = { for region, vpc in google_compute_network.vpc :
            region => vpc.self_link }
}
```
Modules are reusable units referenced from the root config:
```hcl
module "instance1" {
  source        = "./modules/compute_instance"
  instance_name = "instance-1"
  machine_type  = "e2-medium"
  zone          = "us-central1-a"
  tags          = ["web", "dev"]
}
```
Installation (macOS): `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`; Docker alternative: `docker run -i -t hashicorp/terraform:latest plan` (pin a version tag for production).

## Reference Tables
| Command | Purpose | Notes |
|---|---|---|
| `terraform init` | Initialize backend, download plugins/modules, set up state | Re-run after changing modules or backend config |
| `terraform fmt` | Canonical code style | Optional; improves readability/maintainability |
| `terraform validate` | Syntax + schema validation | Fails fast before plan/apply |
| `terraform plan` | Preview `+`/`~`/`-` actions vs. current state | Detects configuration drift |
| `terraform apply` | Execute the plan | Confirm with `yes` or `--auto-approve` |
| `terraform destroy` | Delete all managed resources | Review plan + team-check first; no undo |

| Install target | Method |
|---|---|
| macOS / Linux (Homebrew) | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| Ubuntu/Debian | HashiCorp apt repo (gpg key + `apt install terraform`) |
| CentOS/RHEL / Amazon Linux | HashiCorp yum repo (`yum-config-manager --add-repo ...`) |
| Windows | Manual binary zip from `releases.hashicorp.com` (386/AMD64) |
| Container | `docker pull hashicorp/terraform` |

## Worked Example
End-to-end loop for the storage bucket above:
1. `terraform init` → backend + `hashicorp/google v5.38.0` installed.
2. `terraform plan` → `Plan: 1 to add, 0 to change, 0 to destroy.` with every unknown attribute shown as `+ effective_labels = (known after apply)`.
3. `terraform apply --auto-approve` → `google_storage_bucket.default: Creation complete after 2s [id=ivys_bucket_a]` → `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`
4. `terraform destroy` → plan shows `Plan: 0 to add, 0 to change, 1 to destroy.` and every attribute rendered `- name → null`; interactive prompt requires typing `yes`; `Destruction complete! Resources: 1 destroyed.`
Note the book's own habit applied: destroy ran *without* `--auto-approve` precisely because the plan review + manual confirm is the safety layer.

## Anti-patterns
- **Pinning nothing**: using `latest` (image tag or provider version) across environments breaks consistency — always pin explicit versions.
- **`--auto-approve` on destroy**: skipping the confirmation prompt invites unintentional deletions; the book calls it out as "generally discouraged."
- **Skipping fmt/validate**: not mandatory, but they're cheap guardrails that stop malformed configs from reaching plan/apply.
- **Forgetting to re-init**: after changing backend or module configuration, `terraform init` must be re-run — other commands will only notice and remind you at their own runtime.

## Key Takeaways
1. The workflow loop is: init → write → fmt → validate → plan → apply (→ destroy). Make fmt/validate a habit, not an afterthought.
2. `init` is doing four real jobs (backend, plugins, modules, state) — re-run it whenever backend or module config changes.
3. Read plan symbols as a diff: `+` add, `~` change, `-` destroy; and treat "Plan: 1 to add, 0 to change, 0 to destroy" as the format you always read before confirming.
4. Variables make configs reusable; outputs hand values forward to later runs or external scripts; modules encapsulate reusable units.
5. Never `destroy` without reviewing the plan and checking with the team — "there is no undo."

## Connects To
- **Ch 1**: the workflow operationalizes declarative state + execution plans described there.
- **Ch 3**: variables/outputs/modules only get their full treatment here; state, remote backends, and workspaces deepen what `init` set up.