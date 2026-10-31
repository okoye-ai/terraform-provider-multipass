# Chapter 9: Advanced Terraform Techniques

## Core Idea
Beyond first-resource Terraform lies a toolkit for scale: split monolithic configs into modules, drive them with workspaces and dynamic expressions, automate through CI/CD, harden state, and debug with visibility into state, plans, and provider behavior — so infrastructure stays maintainable as teams, environments, and cloud platforms multiply.

## Frameworks Introduced
- **Modular Terraform configurations**: break monolithic configs into focused child modules called from a root module.
  - When to use: infrastructure complexity makes single-file configs hard to maintain, reuse, or scale.
  - How: create a directory per module (e.g. `modules/network`); define input variables and outputs for each; call the children from the root module and pass variables between them (`module.network.subnet_ids[0]`).
- **Workspace-per-environment pattern**: manage dev/staging/production with one config and one workspace per environment.
  - When to use: code duplication from separate per-environment files; environments that are alike but sized differently.
  - How: `terraform workspace new development|staging|production`; `terraform workspace select <env>`; use `terraform.workspace` as a lookup key into a `locals` map of environment config, falling back to a `default` entry; tag resources with the workspace name.
- **Terraform CI/CD pipeline (GitHub Actions)**: plan on pull requests, apply only on push to main.
  - When to use: manual applies are error-prone in large collaborative environments.
  - How: chain steps — init → `terraform fmt -check` → `terraform validate` → `terraform plan -no-color` (gated `if: github.event_name == 'pull_request'`) → `terraform apply -auto-approve` (gated `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`); store cloud credentials as GitHub secrets; add approval processes for production, policy checks (e.g. OPA), and drift detection.
- **Advanced state management**: remote backend with locking, encryption, and deliberate state refactoring.
  - When to use: multiteam environments where state locking conflicts, sensitive data, and refactoring hurt productivity.
  - How: S3 backend with `encrypt = true`, a `kms_key_id`, and a DynamoDB lock table; mark secrets as `sensitive = true` (or use HashiCorp Vault); refactor with `terraform state mv` / `terraform state rm` / `terraform import`; enable bucket versioning and backups; use partial backend configuration to keep sensitive backend details out of version control; migrate backends with `terraform init -migrate-state`; split state into smaller files for very large infrastructures.
- **Dynamic resource creation with `for_each` + `for`**: compute a map of instance configurations in `locals`, then create resources keyed by environment.
  - When to use: many similar resources, conditional or data-driven creation, multicloud fleets.
  - How: build a `for` expression producing a map (env → {type, count}); feed it to `for_each`; set attributes via `each.value.*`; nest `for` expressions in outputs to produce structured data.
- **Multiple root modules with dynamic module generation**: fan out one shared deployment module across every environment × region combination.
  - When to use: large-scale, multienvironment, multiregion projects with many teams.
  - How: generate a deployments map with `setproduct(environments, regions)`; `module "deployments" { for_each = local.deployments }`; source shared modules from a centralized Git repo with version pinning (`git::https://...//network?ref=v1.2.0`); drive differences through variables like `vpc_cidrs`.
- **Monitoring as IaC (managed Prometheus + Grafana)**: provision Amazon Managed Service for Prometheus (AMP) and Amazon Managed Grafana, their IAM wiring, and VPC endpoints from Terraform.
  - When to use: self-hosted monitoring is too operationally heavy; observability should live beside the infra it watches.
  - How: create `aws_prometheus_workspace` and `aws_grafana_workspace`; grant Grafana `aps:QueryMetrics`-class IAM permissions on the AMP ARN; add an interface VPC endpoint (`aps-workspaces`) with a 443-only security group; feed metrics via Prometheus remote write or AWS Distro for OpenTelemetry; manage dashboards as code with the Grafana provider.
- **Layered security and compliance automation**: combine cloud-native auditing, IaC policy, and an external policy engine.
  - When to use: manual security review cannot keep up with change velocity; auditable compliance is required.
  - How: AWS Config recorder + delivery channel + managed rules (e.g. `S3_BUCKET_PUBLIC_READ_PROHIBITED`, `ENCRYPTED_VOLUMES`) with logs to S3 and notifications to SNS; HashiCorp Sentinel policies (separate `.sentinel` files, e.g. restricting EC2 instance types) for soft/hard enforcement; OPA via `opa eval --data policy.rego --input terraform.tfplan` in CI; add auto-remediation for noncompliant resources.
- **Advanced debugging toolkit**: a graduated procedure for tracing unexpected behavior.
  - When to use: unexplained behavior, resource conflicts, or hard-to-trace errors in multimodule projects.
  - How: export `TF_LOG=TRACE` and `TF_LOG_PATH`; inspect state (`terraform show`, `state list`, `state show`, `state pull | jq`); analyze plans as JSON (`terraform show -json tfplan | jq`); target single resources with `-target`; refresh to detect drift; test expressions in `terraform console`; set `TF_LOG_PROVIDER=DEBUG` for provider-level logs. Always back up state before manipulating it.

## Key Concepts
- **Module**: a reusable, independently testable and versionable package of Terraform config with defined inputs and outputs; abstracts implementation detail from the root module.
- **Workspace**: a named state scope so each environment gets its own state file while sharing one config; accessed in code as `terraform.workspace`.
- **`for_each`**: meta-argument that creates one resource instance per map/set key, giving stable addresses and fine-grained control (preferred over `count` for conditional creation).
- **`setproduct`**: function producing the Cartesian product of lists — the bridge for generating environment × region deployment matrices.
- **`cidrsubnet`**: function that automatically calculates unique CIDR blocks from a supernet, eliminating manual IP management.
- **Remote state backend with locking**: S3 (+ other cloud equivalents) with `encrypt`/KMS and a DynamoDB lock table to prevent concurrent modifications.
- **Partial backend configuration**: splitting backend config so sensitive details (bucket names, keys) are supplied separately, not committed.
- **State refactoring commands**: `terraform state mv` (move without recreate), `state rm` (unmanage), `import` (adopt existing resources), `init -migrate-state` (backend change).
- **Policy as code**: security/compliance rules (Sentinel, OPA) treated, versioned, and reviewed like any other code.
- **`-target` flag**: limits plan/apply to specified resources for focused debugging in large configurations.

## Mental Models
- Use child modules with version-pinned Git sources when more than one team or environment needs the same infrastructure pattern.
- Use a `terraform.workspace` lookup table (with a `default` key) when environments differ only in sizing, not in structure.
- Use `for_each` over a computed locals map when resource creation should be data-driven; treat address stability as a design constraint.
- Treat any state manipulation as surgery: back up first, verify with `terraform show`/`state list`, and check the plan as JSON before acting.

## Anti-patterns
- **Monolithic configurations**: hard to maintain, reuse, test, or scale as complexity grows — split into focused modules.
- **Separate config files per environment**: duplicates logic and drifts apart; use workspaces unless environments are highly disparate (multiple regions/accounts).
- **Using `count` for conditional resource creation**: harder to manage than `for_each` with a map; changes can cause unexpected resource re-creation.
- **Manual applies and untracked changes**: error-prone and unauditable; route changes through CI/CD with plan-on-PR, apply-on-main, and drift detection.
- **Unencrypted or locally held state, or raw secrets in state**: state leaks are a security risk; encrypt with KMS, mark variables `sensitive`, and move highly sensitive data to a secrets manager.
- **Complex expressions without testing**: unreadable and hard to debug; validate in `terraform console` before apply, and be cautious changing expressions that affect resource addresses.
- **Editing state without a backup**: destructive; always back up the state file first.

## Code Examples
```hcl
# Workspace-keyed environment config: one config, per-env sizing
locals {
  environment_config = {
    default    = { instance_type = "t3.micro",  instance_count = 1 }
    staging    = { instance_type = "t3.small",  instance_count = 2 }
    production = { instance_type = "t3.medium", instance_count = 3 }
  }
  config = lookup(local.environment_config, terraform.workspace,
                  local.environment_config["default"])
}

resource "aws_instance" "app_server" {
  count         = local.config.instance_count
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = local.config.instance_type
  tags          = {
    Name        = "AppServer-${terraform.workspace}-${count.index + 1}"
    Environment = terraform.workspace
  }
}
```
- **What it demonstrates**: workspace-per-environment pattern with a safe default fallback.

```hcl
# Fan out one shared module across every environment x region combination
locals {
  environments = ["dev", "stg", "prd"]
  regions      = ["us-west-2", "eu-west-1"]
  deployments = {
    for pair in setproduct(local.environments, local.regions) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], region = pair[1] }
  }
}

module "deployments" {
  source   = "./modules/deployment"
  for_each = local.deployments

  environment = each.value.env
  region      = each.value.region
  vpc_cidr    = var.vpc_cidrs[each.key]
}
```
- **What it demonstrates**: dynamic module generation with `setproduct` + `for_each` against a versioned shared-module repo.

```bash
export TF_LOG=TRACE
export TF_LOG_PATH=./terraform.log

terraform plan -out=tfplan
terraform show -json tfplan | jq                 # plan analysis
terraform state list && terraform state show aws_instance.example
terraform state pull | jq '.resources[] | select(.module == "module.example")'
terraform apply -target=aws_instance.example     # targeted debugging
terraform console                                # test expressions interactively
```
- **What it demonstrates**: the graduated debugging procedure — logging, state inspection, JSON plan analysis, and targeted operations.

## Reference Tables
None in this chapter. The chapter's decision guidance is prose: prefer `for_each` over `count`; prefer workspaces for alike environments and separate configs for disparate ones or multi-region/account setups; prefer managed monitoring (AMP/Managed Grafana) over self-hosted; for very large infrastructures, split state into smaller files to reduce blast radius.

## Worked Example
The chapter's largest worked example (9.8) builds managed observability end to end in one config: an AMP workspace (`aws_prometheus_workspace`) and an Amazon Managed Grafana workspace with SSO auth; an IAM role whose trust policy lets `grafana.amazonaws.com` assume it, plus an inline policy granting `aps:QueryMetrics`, `aps:GetLabels`, `aps:GetSeries`, and `aps:GetMetricMetadata` on the AMP workspace ARN; an interface VPC endpoint for `com.amazonaws.<region>.aps-workspaces` locked to port 443 from the VPC CIDR by a dedicated security group; and a short-lived Grafana API key (`seconds_to_live = 3600`) for integration. Outputs expose the `prometheus_endpoint` and `grafana_endpoint`. The extension path: add Prometheus remote write or ADOT collectors, manage dashboards in Terraform, and wire alerting rules to SNS — the same IaC pipeline that builds the infrastructure builds its instrument.

## Key Takeaways
1. Reach for modules the moment a config stops fitting in your head: one concern per module, clear variables/outputs, documented usage.
2. Workspaces give per-environment state isolation for free — but pair them with remote state and strict access controls on production.
3. Put format/validate/plan in CI on every pull request and let apply fire only on main; that single gate converts infra changes into reviewable, auditable code.
4. Encrypt and lock remote state, and learn `state mv`/`state rm`/`import` — refactoring without re-creating infrastructure is a normal operation, not an emergency.
5. Compute data in `locals` (for/of maps, `setproduct`, `flatten`, `cidrsubnet`) and keep resource blocks declarative and clean.
6. Source shared modules from a pinned-version Git repository so teams update infrastructure deliberately, like software.
7. Debug systematically: TF_LOG for the engine, `terraform show -json tfplan | jq` for intent, `terraform console` for expressions, `TF_LOG_PROVIDER=DEBUG` when the provider is the suspect.

## Connects To
- **Ch 10**: workspace-based multienvironment management here becomes the workspace-driven multi-env and GitOps pipeline recipes there; the CI/CD pattern becomes the real-world deployment recipes.
- **Terraform provider development / custom provider SDK**: the 9.7 recipe's dynamic-expression patterns show where a custom provider is the more natural abstraction when Terraform's expression language maxes out.
- **Policy as code (OPA / Sentinel)**: industry-standard gatekeeping for IaC, consumed here inside CI/CD pipelines.
- **Datadog/Prometheus-style monitoring integrations**: 9.8's AMP/Grafana pattern generalizes to any monitoring platform provisioned via its provider.
- **HashiCorp Vault**: external secrets management cited over `sensitive = true` for highly sensitive data.