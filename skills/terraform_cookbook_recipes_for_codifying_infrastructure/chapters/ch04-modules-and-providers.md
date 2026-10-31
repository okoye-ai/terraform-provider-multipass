# Chapter 4: Terraform Modules and Providers

## Core Idea
Modules are Terraform's functions — self-contained packages that encapsulate a collection of related resources for reuse — while providers are the API adapters that create, read, update, and delete those resources; this chapter covers consuming public and private modules, authoring your own, automating quality with GitHub Actions, and configuring provider authentication, dynamic Consul KV configuration, remote-state consumption, and multi-instance provider aliases.

## Frameworks Introduced
- **Public Module Adoption (Terraform Registry)**: assemble proven infrastructure from a registry module instead of hand-writing resources.
  - When to use: standing up standard stacks (e.g., an EKS cluster) where a maintained public module exists.
  - How: search "terraform-aws-modules eks" on the Terraform Registry, read the documented required inputs and outputs, add the necessary variables (Kubernetes version, ASG capacity, log types), then call `module "eks" { source = "terraform-aws-modules/eks/aws"; version = "20.24.0"; ... }` and run `terraform init` to download dependencies and create the lockfile. Always pin `version`.
- **Automated Linting with GitHub Actions (+ Super-Linter)**: style and correctness feedback loops on every change.
  - When to use: any Terraform repository, ideally from day one, so issues never reach main.
  - How: two workflows in `.github/workflows/` — `superlinter.yml` runs `github/super-linter:v4` on pull requests with `VALIDATE_TERRAFORM/YAML/JSON/MD: true`; `terraform.yml` runs `terraform fmt -check -recursive`, `terraform init`, and `terraform validate` via `hashicorp/setup-terraform` on pushes to main and PRs. These complement — not replace — code review.
- **Provider Credential Ladder**: a set of authentication options for providers, from vars to vaults.
  - When to use: any `provider` block; sensitive values must never be hardcoded.
  - How: prefer, in order of robustness — environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), a shared credentials file (`~/.aws/credentials` with `profile`), IAM roles on EC2, AWS Vault for development, HashiCorp Vault for dynamically generated credentials. Marking variables `sensitive` and passing via un-committed `.tfvars` works but is the least recommended for production.
- **Private Module Registry Auth (HCP Terraform token)**: authenticate Terraform CLI to a private registry.
  - When to use: consuming modules like `source = "app.terraform.io/my-org/my-module"`.
  - How: either a `credentials` block in the CLI config (`~/.terraformrc`, or `%APPDATA%\terraform.rc` on Windows) with `credentials "app.terraform.io" { token = "your-api-token" }`, or set `TERRAFORM_CONFIG` to point at a separate credentials file. Never commit the token; scope tokens to least privilege (read-only for module reads), rotate regularly, and inject them securely in CI/CD.
- **Module Authoring Contract (main.tf / variables.tf / outputs.tf)**: the canonical module layout.
  - When to use: every reusable module.
  - How: `main.tf` defines resources; `variables.tf` defines typed inputs (defaults where sensible); `outputs.tf` returns identifiers (instance ID, public IP) the caller needs; add a `README.md` documenting purpose/inputs/outputs, version modules shared across teams, and ship a `tests/` directory with `example_usage.tf` that exercises the module. Keep each module focused on one task or one related resource group.
- **GitHub-as-Code (secrets and repositories)**: manage `github_actions_secret` and `github_repository` resources through the GitHub provider.
  - When to use: organizations that need many standardized repos and reproducible CI secrets.
  - How: configure `provider "github" { token = var.github_token; owner = var.github_owner }` with the token marked `sensitive`; define secrets with `resource "github_actions_secret"` (`secret_name`, `plaintext_value`); define repos with `github_repository` (visibility, `auto_init`, a `template` block for standardization, topics, and merge-strategy flags). Terraform applies idempotently and imports pre-existing repos into state. Secret plaintext values land in state — use remote state with encryption.
- **Consul KV Dynamic Configuration**: externalize frequently-changing values into Consul's key-value store.
  - When to use: passing dependencies across Terraform states, or consuming configuration other processes update without editing Terraform code.
  - How: write with `resource "consul_key_prefix"` (`path_prefix = "terraform/vpc/"`, `subkeys = { id = aws_vpc.main.id }`); read with `data "consul_keys"` (`key { name; path }`) and consume `data.consul_keys.vpc.var.vpc_id`. Namespace keys with a path prefix; secure with ACLs and encryption. Remember the trade-off: state tracks resource dependencies; Consul KV is for dynamic, shared configuration.
- **Service-Health-Aware Provider Configuration**: select endpoints by live health status.
  - When to use: multiple service endpoints and you want Terraform to use only healthy ones, or failover between them.
  - How: `data "http"` queries Consul's health API (`/v1/health/service/my-service`); `jsondecode(data.http...body)[0]` parses it; a ternary picks the service address when `Status == "passing"` else a fallback address; that local feeds the provider's `endpoint`. The check runs once during plan/apply — no continuous monitoring; add real error handling and HTTPS for production.
- **Remote State Consumption (`terraform_remote_state`)**: read another configuration's state outputs, read-only.
  - When to use: layered infrastructure — networking, compute, database as separate states that reference each other — or cross-team sharing without coupling configurations.
  - How: store state in an accessible backend (S3 here: `bucket`/`key`/`region`), declare `data "terraform_remote_state" "network" { backend = "s3"; config = {...} }`, and consume `data.terraform_remote_state.network.outputs.subnet_id`. Access is read-only; it creates implicit dependencies and adds retrieval overhead for large states.
- **Multiple Identical Providers (aliases)**: one provider type, several configurations.
  - When to use: managing resources in multiple regions or accounts within a single configuration.
  - How: leave the first `provider "aws"` block as the default (used when no provider is referenced); add `provider "aws" { alias = "east"; region = "us-east-1" }` and set `provider = aws.east` on the resources that need it. Watch region-specific AMIs, clear resource naming for each region, and whether one shared state fits the setup — for complex multiregion setups, separate configurations or workspaces may serve better.

## Key Concepts
- **Module**: a self-contained package of Terraform configurations managed as a group; encapsulates reusable components like a function in a traditional language, except it manages a collection of resources rather than performing computation.
- **Provider**: the plugin responsible for understanding an external API's interactions and exposing its resources (AWS, GCP, Azure, GitHub, Datadog, and many others).
- **`source` + `version`**: the module block arguments that locate a module and pin its version — pinning is what makes registry module use reproducible.
- **`sensitive = true`**: variable/output flag preventing values from appearing in console output or logs.
- **credentials block**: `credentials "app.terraform.io" { token = "..." }` in the CLI configuration file (`~/.terraformrc`) used to authenticate to a private registry.
- **`TERRAFORM_CONFIG`**: environment variable pointing Terraform at a separate credentials file — the alternative to placing tokens in `~/.terraformrc`.
- **`github_actions_secret`**: resource defining an Actions secret (`repository`, `secret_name`, `plaintext_value`) in a GitHub repository.
- **`consul_key_prefix` / `consul_keys`**: the write resource and read data source for Consul KV, used to persist configuration outside Terraform state.
- **`jsondecode` / `data "http"`**: the pair used to fetch and parse an API response (e.g., Consul health checks) into Terraform values.
- **`alias` / `provider = aws.east`**: the declaration and reference that create and select non-default provider instances.
- **KMS key (`aws_kms_key`)**: used in the EKS recipe with `cluster_encryption_config` to encrypt Kubernetes secrets.
- **`data "aws_eks_cluster"` / `data "aws_eks_cluster_auth"`**: data sources that fetch the cluster endpoint/CA and a token so the `kubernetes` provider can authenticate to EKS.

## Mental Models
- Think of a module as a function: inputs are variables, the return value is outputs, and the body manages a collection of resources instead of computing a result.
- Use cloud-native data sources first, remote state second, Consul KV third — each hop outward from Terraform's own state trades directness for dynamism and adds an external dependency.
- Think of provider authentication as a ladder: hardcoded values at the bottom (never), sensitive variables next, environment variables and shared credential files above, IAM roles and vault-managed dynamic credentials at the top.
- Treat a health-checked `provider` config as a point-in-time gate, not a watchdog — it approves the endpoint at plan/apply time, then steps away.

## Anti-patterns
- **Using Terraform for configuration management or app deployment on the EKS cluster**: keep cluster authentication/instantiation separate from configuring applications running on it — mixing them makes maintenance and upgrades harder.
- **Hardcoding credentials in provider blocks**: `access_key`/`secret_key` literals end up in plain text in code; use environment variables, credential files, IAM roles, or vaults.
- **Committing API tokens or `.tfvars` with real secret values**: the HCP Terraform token and GitHub token are sensitive; never commit or share them insecurely.
- **Storing GitHub secret plaintext in unencrypted local state**: `github_actions_secret` puts plaintext values into state; require remote state with encryption.
- **Un-namespaced Consul keys**: without a `path_prefix` like `terraform/vpc/`, keys collide once Consul serves multiple purposes.
- **Shipping a health-check or remote-state read without error handling**: empty responses, unavailable Consul, or a missing output will fail the run — add fallbacks, HTTPS + auth, and `try(..., null)` guards.
- **Sharing whole states because you can**: maintain separation of concerns; expose only the outputs other configurations need, since remote state is read-only but creates implicit coupling.

## Code Examples
```hcl
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.ca.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.24.0"
  cluster_name    = var.project_name
  cluster_version = var.cluster_version
  subnets         = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  cluster_encryption_config = [
    {
      provider_key_arn = aws_kms_key.eks.arn
      resources        = ["secrets"]
    }
  ]
}
```
- **What it demonstrates**: public-module adoption — pinned `source`/`version`, wiring the VPC and KMS modules' outputs in, and authenticating the `kubernetes` provider from the freshly created cluster's data sources.

```hcl
# ~/.terraformrc  (or %APPDATA%\terraform.rc on Windows)
credentials "app.terraform.io" {
  token = "your-api-token"
}

module "vpc" {
  source  = "app.terraform.io/my-company/vpc/aws"
  version = "1.0.0"

  vpc_cidr = "10.0.0.0/16"
  azs      = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
```
- **What it demonstrates**: private module registry authentication via a credentials block, and referencing a private module by its registry address (the alternative is `export TERRAFORM_CONFIG=/path/to/terraform.rc`).

```hcl
provider "aws" {
  region = "us-west-2"
}

provider "aws" {
  alias  = "east"
  region = "us-east-1"
}

resource "aws_instance" "east_server" {
  provider      = aws.east
  ami           = "ami-0747bdcabd34c712a"
  instance_type = "t2.micro"
}
```
- **What it demonstrates**: provider aliases — a default instance plus an aliased one selected per resource with `provider = aws.east`.

```hcl
provider "consul" {
  address = "localhost:8500"
  scheme  = "http"
}

resource "consul_key_prefix" "vpc" {
  path_prefix = "terraform/vpc/"

  subkeys = {
    "id" = aws_vpc.main.id
  }
}

data "consul_keys" "vpc" {
  key {
    name = "vpc_id"
    path = "terraform/vpc/id"
  }
}

resource "aws_subnet" "example" {
  vpc_id     = data.consul_keys.vpc.var.vpc_id
  cidr_block = "10.0.1.0/24"
}
```
- **What it demonstrates**: Consul KV as dynamic configuration — write with `consul_key_prefix`, read with `consul_keys`, and consume across configurations without editing Terraform code.

## Reference Tables
**Provider credential options (Recipe 4.3):**

| Method | How | Best for |
|---|---|---|
| Sensitive variables + `.tfvars` | `access_key = var.aws_access_key`, values passed via CLI or un-committed `.tfvars` | quick local use; not recommended for production |
| Environment variables | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | automation and local parity |
| Shared credentials file | `shared_credentials_file = "~/.aws/credentials"` + `profile = "dev"` | machines already using AWS CLI |
| IAM role | assigned to the EC2 instance Terraform runs on | workloads inside AWS |
| AWS Vault / HashiCorp Vault | secure credential storage; Vault can dynamically generate AWS credentials | dev tooling / production secrets |

**Consul KV vs. Terraform state (Recipe 4.8):**

| | Terraform state | Consul KV |
|---|---|---|
| Designed for | tracking resource dependencies | dynamic, shared configuration |
| Change dynamics | changes with Terraform runs | updates in Consul reflect in runs without code changes |
| Sharing | via `terraform_remote_state` (read-only outputs) | any process can read/write |
| Caveat | sensitive values readable by anyone with state access | external dependency on a reliable, secured cluster |

## Worked Example
Recipe 4.1 — standing up an EKS cluster from the public registry module. Step 1: add `variables.tf` inputs — `cluster_version` ("1.30"), `cluster_instance_type` ("m5.large"), `cluster_asg_desired_capacity` (3), `cluster_asg_max_size` (5), `cluster_enabled_log_types` ("api", "audit", "authenticator", "controllerManager", "scheduler"), and `cluster_write_kubeconfig` (false). Step 2: add `kms.tf` with `resource "aws_kms_key" "eks"` (`deletion_window_in_days = 7`, `enable_key_rotation = true`) for encrypting Kubernetes secrets. Step 3: call `module "eks"` from `terraform-aws-modules/eks/aws` at version 20.24.0, passing the VPC module's `private_subnets` and `vpc_id`, encrypting `secrets` with the KMS key's ARN, and defining one worker group from the ASG variables. Step 4: wire the `kubernetes` provider through `data "aws_eks_cluster"` (endpoint, base64-decoded CA) and `data "aws_eks_cluster_auth"` (token). Step 5: `terraform init` downloads dependencies and creates the Terraform lockfile; `terraform destroy` tears it down after experimenting. Guardrails: review created resources and costs before applying outside a sandbox, review the Registry listing's documented inputs, outputs, and dependencies before calling a module, and keep application configuration off this configuration entirely.

## Key Takeaways
1. Pin module `version` every time, and read a Registry module's documented inputs and outputs before calling it — the listing is the contract.
2. Stand up linting (Super-Linter on PRs, `terraform fmt -check -recursive` / `terraform init` / `terraform validate` on main) when you create the repository, not after the first incident.
3. Choose credentials by run context: IAM roles in AWS, shared profiles on dev boxes, Vault for dynamic generation — and never hardcode or commit secrets.
4. Author modules as main.tf / variables.tf / outputs.tf, plus README.md and a `tests/` example; keep each module focused on one task and expose outputs for everything a caller will need.
5. Namespace Consul KV keys under a `path_prefix` and treat Consul as dynamic shared config, not a state replacement — state tracks dependencies, KV externalizes values that change often.
6. Remember `terraform_remote_state` is read-only and creates implicit dependencies: store state in a locked, encrypted, access-controlled backend and expose only the outputs others need.
7. Use provider `alias` for multi-region/multi-account in one configuration, but know all those resources share one state — split configurations or use workspaces when that coupling is wrong.
8. Provider authentication for EKS is two data sources (`aws_eks_cluster` + `aws_eks_cluster_auth`) feeding `host`, `cluster_ca_certificate`, and `token` into the `kubernetes` provider — don't hand-assemble those values.

## Connects To
- **Ch 3 (Syntax Patterns)**: validation blocks, `try(...)`, and template rendering are what make a module's inputs safe and its outputs consumable.
- **Ch 5 (Container Management)**: the EKS cluster created here (and its `kubernetes` provider auth) is the target platform for the container recipes that follow.
- **Ch 3.14 (Cross-state sharing)**: Recipe 4.10 is the same `terraform_remote_state` pattern applied to providers; 4.8 offers Consul KV as the dynamic alternative.
- **HCP Terraform private module registry**: module sources of the form `app.terraform.io/<org>/<name>` authenticate through `credentials` blocks or `TERRAFORM_CONFIG` — consult your registry's docs if it is not HCP Terraform.
- **GitHub Actions / Super-Linter**: the CI backbone for the chapter's "lint early" doctrine; extend `VALIDATE_*` env flags to cover more file types.