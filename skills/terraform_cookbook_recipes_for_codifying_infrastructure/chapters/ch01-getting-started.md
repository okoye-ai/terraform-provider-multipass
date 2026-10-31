# Chapter 1: Getting Started with Terraform

## Core Idea
Terraform is a declarative infrastructure-as-code tool — judge it into or out of your workflow by infrastructure complexity and provider spread, and adopt the standard workflow (install → provider/module declarations → version constraints → remote state → variables → consistent team conventions) from day one.

## Frameworks Introduced
- **When to Use Terraform**: fit test for declarative IaC
  - When to use: multiple environments (dev/staging/prod), complex many-resource infrastructure, infrastructure spanning multiple cloud providers or on-prem, automated deployment via CI/CD.
  - How: ask whether infrastructure is complex, multi-provider, or needs repeatable multi-environment deploys; if yes, Terraform pays off.
- **When Not to Use Terraform**: escalation-avoidance pattern
  - When to use: single-server setups, small single-cloud footprints, PaaS platforms (Netlify, Google App Engine), unique "snowflake" systems (research labs, legacy departments).
  - How: prefer Ansible/Puppet for simple config management, native tools (AWS CloudFormation, Azure Resource Manager) for single-cloud IaaS, the PaaS itself for platform deployments — but re-examine snowflake systems if the organization broadly runs IaC.
- **Provider Block Configuration**: declare-then-configure-then-consume
  - When to use: any time a resource needs a cloud or external API.
  - How: (1) choose provider on the Terraform Registry, (2) add a `provider` block to main.tf, (3) configure required settings (region, API keys, tokens), (4) use the provider's resources; then `terraform init`, `plan`, `apply`.
- **Prebuilt Module Consumption**: reuse before you build
  - When to use: standing up standard topologies (e.g., a VPC with CIDR, subnets, NAT gateway) from scratch.
  - How: declare `module "vpc" { source = "terraform-aws-modules/vpc/aws"; version = "3.19.0" ... }` with a pinned version and pass inputs (name, cidr, azs, private/public subnets, enable_nat_gateway, tags).
- **Remote State with HCP Terraform**: centralized, shared state backend
  - When to use: any team environment needing shared, secure, remote state access.
  - How: `terraform { cloud { organization = ...; workspaces { name = ... } } }`, then `terraform init -backend-config="token=<HCP Terraform API token>"`; alternatives are S3 (+DynamoDB locking), Azure Blob Storage, GCS, Consul — local state is not recommended for teams.
- **Provider Version Constraints**: pin the range, not the wild
  - When to use: every provider block, to guarantee reproducible IaC.
  - How: `version = "~> 5.0"` accepts 5.x and blocks 6.0+; exact pin (`"5.1.0"`) for strict control; commit the `.terraform.lock.hcl` dependency lock file and use `terraform init -upgrade` to move within constraints.
- **Step-by-Step Major Version Upgrade** (0.x → 1.x): measured ladder
  - When to use: legacy codebases on 0.15 or earlier.
  - How: back up state → reach the latest patch of the current major → move one minor at a time running `terraform 0.13upgrade`, reviewing each change line-by-line → verify with plan/apply → repeat per version; after 0.14/1.x, normal installs suffice. Post-1.0, lag no more than two minor versions (~9–12 months).
- **GitOps Repository Strategy**: version-controlled Terraform repos with enforced checks
  - When to use: teams managing infrastructure code in Git.
  - How: source modules at fixed git refs (`?ref=v1.0.0`), provision `github_repository` + `github_branch_protection` on `main` with required status checks (`ci/terraform-run`) so only validated Terraform merges.

## Key Concepts
- **Provider**: a Terraform plug-in that lets Terraform interact with a cloud service or external API; found in the Terraform Registry and configured through a `provider` block.
- **Module**: an encapsulated, reusable unit of Terraform code that takes input variables and emits output values (e.g., the VPC module).
- **terraform console**: an interactive HCL REPL that introspects and (for testing/debugging only) modifies state via `state.<module>.<resource>.<attribute>` — never for production changes.
- **HCP Terraform**: HashiCorp's managed remote backend (formerly Terraform Cloud) storing state centrally; configured via the `cloud { ... }` block with organization and workspace names.
- **Dependency lock file (`.terraform.lock.hcl`)**: a committed file created by `terraform init` recording the exact provider versions and hashes, guaranteeing identical provider installs across team members and environments.
- **required_version**: the `terraform` block directive that constrains acceptable Terraform CLI versions (e.g., `>= 1.0.0`) for a configuration.
- **Variable**: a declared, typed, sometimes-defaulted input (`variable "region" { type = string }`) that parameterizes code, referenced as `var.region` and overridable per apply (`terraform apply -var region=us-east-1`).
- **OpenTofu**: the open source fork of Terraform; installs and behaves nearly identically but uses the `tofu` command so both can coexist.
- **Version constraint (`~> 5.0`)**: a pessimistic constraint accepting any 5.x release while rejecting the next major (6.0+), enabling safe in-range upgrades.
- **Branch protection**: a VCS rule (via `github_branch_protection`) requiring CI status checks before merge — the automation gate for GitOps Terraform.

## Mental Models
- "Use Terraform when the infrastructure is complex, multi-provider, or repeated across environments; think of it as overkill for one server or a PaaS-only stack."
- "Think of providers as adapters between declarative HCL and external APIs; think of modules as pre-fabricated buildings on top of them."
- "Think of the `.terraform.lock.hcl` file as the provider-side sibling of `required_version`: one locks CLI capability, the other locks provider binary versions."
- "Treat every 0.x → 1.x upgrade as a ladder: back up, upgrade one rung, review, apply, repeat — never skip rungs."

## Anti-patterns
- **Hardcoding credentials in the provider block** (`access_key = "YOUR_ACCESS_KEY"`): shown only for illustration; embeds secrets in code — resolve from environment or a secrets system instead.
- **Editing state live in `terraform console` for production** (recipe 1.6 warning): manual state modification causes unexpected results and may put infrastructure at risk.
- **Keeping state on the local filesystem in a team**: recipe 1.7 explicitly flags local backend as not recommended for team environments.
- **Unconstrained provider versions**: without `version` constraints, accidental upgrades introduce breaking changes unpredictably.
- **Skipping the line-by-line review of `0.13upgrade` output**: upgrade commands are best-effort; unresolved cases leave commented TODOs that silently break apply if unreviewed.
- **Lagging more than two minor versions behind current Terraform** (~9–12 months): forfeits bug fixes and security enhancements.
- **Global, unscoped variables everywhere**: makes code hard to understand and maintain — scope variables to modules and pass values via inputs/outputs.

## Code Examples
<!-- Provider version constraint + pessimistic operator -->
```hcl
provider "aws" {
  version = "~> 5.0"
  region  = "us-west-2"
}
```
- **What it demonstrates**: the recommended constraint style — auto-upgrade inside 5.x, hard block at 6.0.

<!-- Prebuilt module consumption with pinned version -->
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
```
- **What it demonstrates**: whole-topology infrastructure (VPC, subnets, NAT gateway) from one pinned module call.

<!-- Docker provider deployment -->
```hcl
provider "docker" {}

resource "docker_container" "example" {
  name  = "example"
  image = "nginx"
  ports {
    internal = 80
    external = 8000
  }
}
```
- **What it demonstrates**: local Docker infrastructure as code — after `terraform init` and `terraform apply`, nginx serves at http://localhost:8000.

```bash
terraform init -backend-config="token=<HCP Terraform API token>"
```
- **What it demonstrates**: initializing the HCP Terraform remote backend with the token from User Settings → Tokens.

## Reference Tables
**Remote backend options (recipe 1.7):**

| Backend | Mechanism |
|---|---|
| Amazon S3 | State as a key in an S3 bucket, optional DynamoDB table for state locking |
| Azure Blob Storage | State in Azure Blob Storage accounts |
| Google Cloud Storage | State in a GCS bucket |
| Consul | State in the Consul Key/Value store |
| Local | State on the local filesystem — not recommended for teams |

**Consistent-code checklist (recipe 1.14):**

| Element | Practice |
|---|---|
| Version constraint | `required_version` in the `terraform` block pins CLI versions |
| Backend configuration | Remote backend (HCP Terraform / Terraform Enterprise) for centralized state |
| Provider configuration | Keep provider blocks consistent across environments and team members |
| Resource configuration | Consistent block structure and naming conventions for readable, maintainable code |

None else in this chapter.

## Worked Example
**Docker container deployment (recipe 1.11), end to end:**

1. Install Docker on the machine or Docker host (prerequisite — Terraform drives the Docker API but not the daemon install).
2. Add a `provider "docker" {}` block to initialize the Docker provider.
3. Declare the container: a `docker_container` resource named `example` running the `nginx` image, mapping host port 8000 to container port 80.
4. Run `terraform init` to download the Docker provider plug-in.
5. Run `terraform apply`; Terraform communicates with the Docker API to create the container and its networks/images.
6. Verify: open http://localhost:8000 — nginx inside the container answers on the mapped host port.
7. Because containers, images, and networks are now Terraform resources, any later change is version-controlled, planned, and reproducible by editing the code and re-applying rather than hand-configuring the host.

## Key Takeaways
1. Run the fit test first: Terraform earns its cost on complex, multi-provider, multi-environment infrastructure — single servers, small single-cloud estates, PaaS-deployed apps, and snowflake systems are legitimate "no."
2. Always pin provider versions with a pessimistic constraint (`~> 5.0`) and commit the `.terraform.lock.hcl` lock file; that combination, not luck, is what makes IaC reproducible.
3. Use remote state for any team (HCP Terraform via the `cloud { }` block, S3, GCS, Azure Blob, Consul) — never local state in a shared environment.
4. Reach for prebuilt Registry modules before writing your own; pin the module version and pass inputs.
5. Upgrade 0.x → 1.x one minor version at a time with state backups and line-by-line review of each upgrade command's output; post-1.0, lag no more than two minor versions.
6. Parameterize with typed variables (`var.region`, `-var` overrides) instead of hardcoding environment values, and keep variable scope local to modules.
7. Encode the GitOps gate: version-pinned module sources, a `github_repository` for the code, and branch protection requiring CI status checks before merge.
8. `terraform console` is an introspection and debugging seat, not a steering wheel — state editing there is for testing only.

## Connects To
- **Ch 2**: chapter 1 establishes what to standardize (versions, backends, repos); chapter 2 supplies the validation tooling (terraform fmt/validate, TFLint, TFSec, OPA) that makes those standards enforceable.
- **`terraform 0.13upgrade` / plan-apply verification**: the upgrade ladder relies on `terraform plan` as the change-review tool, a discipline chapter 1's GitOps recipe formalizes with required status checks.
- **GitOps / trunk-based development**: the version-controlled repo strategy applies standard VCS practices (PRs, status checks) to infrastructure change management.
- **AWS CloudFormation / Azure Resource Manager / Ansible / Puppet**: the explicitly named alternatives when Terraform's fit test fails.