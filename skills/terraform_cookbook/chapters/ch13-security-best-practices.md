# Chapter 13: Security and Best Practices in Terraform

## Core Idea
Terraform's automation is only enterprise-ready when secrets never touch code or state in plain text, identity is least-privilege, compliance is enforced as policy before apply, state is centrally locked/backed up, versions are pinned, and drift is detected and reconciled on a schedule.

## Frameworks Introduced
- **Policy as Code (Sentinel / OPA)**: Compliance enforced against the plan before it reaches production.
  - When to use: every pipeline apply — mandatory tags, region allowlists, restricted SKUs, encryption/public-access rules.
  - How: write rules against `tfplan/v2` (Sentinel) or Rego evaluated on `terraform show -json tfplan` (OPA/conftest); set `enforcement_level = "hard-mandatory"` to block non-compliant applies.
- **Secure-by-default project structure**: `modules/` + `environments/` (dev/staging/prod, each with own state) + `global-variables/` (tags, naming, approved regions).
  - When to use: multiple teams sharing one infrastructure codebase.
  - How: modules stay generic (no provider blocks); environments call modules with env-specific variables; platform team owns `modules/*`, app teams PR only `environments/*` inputs.
- **Drift resolution decision rule**: two paths — if the manual change is intentional, update `.tf` to match and replan to no-changes; if not intended, re-apply to overwrite. Import pre-existing resources before refining HCL.
- **Least-privilege Terraform identity**: run pipelines under Managed Identity / Service Principal scoped to the resource group being managed, never Contributor/Owner at subscription level.
  - How: scope RBAC to managed resources; use short-lived tokens (OIDC/Vault) and rotate; restrict backend read/write to the CI identity only.
- **Promotion flow**: plan/apply in dev → PR promotes the same module versions and variables to staging → prod.

## Key Concepts
- **Sensitive variables**: variables marked `sensitive = true` are masked in CLI output, logs, and plan files — but marking does NOT keep them out of state; fetch at apply time from a vault instead.
- **State locking**: backend-held single-writer lock (Azure Blob lease mechanism) preventing concurrent applies from corrupting state; verified by the "Acquiring state lock..." message.
- **`.terraform.lock.hcl`**: checked-in lockfile capturing exact plugin versions so all runners resolve identical binaries; run `terraform init -lockfile=readonly` in CI to prevent pipeline modification.
- **`required_version` / `required_providers`**: toolchain pinning in the `terraform {}` block that makes plans fail fast on incompatible CLI/provider versions.
- **Drift**: divergence between real cloud resources and state from out-of-band portal/CLI changes; detected via scheduled `terraform plan`, `terraform refresh`, and cloud audit logs (Activity Logs, CloudTrail).
- **Backend access restriction**: only the Terraform automation identity should read/write state; prevents state manipulation that would misalign infrastructure definitions.
- **Secret at apply time**: pattern of retrieving secrets from Key Vault/Vault data sources rather than storing them in tfvars, code, or state.
- **`resource_provider_registrations`**: AzureRM v4 replacement for deprecated `skip_provider_registration`; use `"none"` plus pre-registered RPs when the identity cannot register providers.

## Recipes in this chapter
- **Recipe 73: Storing secrets in Azure Key Vault** — create an RBAC Key Vault and pull secrets at apply time so no password lands in .tf files or state; verify via `terraform show` masking. Watch for 403 Forbidden in the first 30–60s (RBAC propagation) — just re-run apply.
- **Recipe 74: Sentinel policy for Terraform** — enforce tagging/region rules with Sentinel; Option 1 tests locally in a Terraform Cloud CLI workspace, Option 2 links centralized policy sets to GitHub so Sentinel blocks non-compliant PRs before merge.
- **Recipe 75: State locking demonstration** — prove single-writer semantics by running two parallel applies against an azurerm backend; second job waits ("Acquiring state lock") up to `-lock-timeout=10m`. OIDC identity needs Storage Blob Data Contributor on the state account or leases fail.
- **Recipe 76: Structuring Terraform code for teams** — full enterprise repo layout with per-environment state keys, secrets via Key Vault sources, promotion flow, and verification checklist (destroying dev does not touch prod; module folders contain no provider configuration).
- **Recipe 77: Enforcing provider and Terraform versions** — pin via `required_version >= 1.11.0, < 2.0.0` and commit the lockfile; include a negative test (set an incompatible constraint to see the "Unsupported Terraform Core version" error).
- **Recipe 78: Handling resource drift** — simulate drift by hand-editing a storage account tag/public-network setting in the portal, detect with `terraform plan`, resolve via Path A (accept: update code) or Path B (overwrite: apply).

## Anti-patterns
- **Committing `terraform.tfvars` or state files to Git**: leaks credentials and internal resource details; use .gitignore and treat state as sensitive.
- **Assuming `sensitive = true` protects state**: sensitivity masks display only; state still records attributes — use vault data sources for real secrets.
- **Subscription-level Contributor/Owner rights for pipelines**: huge blast radius if compromised; scope to the resource group actually managed.
- **Hardcoding secrets in `.tf` variables or pipeline client secrets**: prefer OIDC federation (no stored secret) and runtime vault retrieval.
- **Leaving `skip_provider_registration = true` on AzureRM v4**: deprecated and warning-producing; use `resource_provider_registrations`.
- **Unplanned provider/CLI upgrades**: untested provider behavior changes cause production outages; upgrade in staging first and review upgrade guides.
- **Ignoring drift**: causes noisy plans, security gaps, billing discrepancies, and unexpected resource recreation.
- **`number` argument on `random_string`**: deprecated; use `numeric = true` only.

## Code Examples
```terraform
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.76.0"
    }
  }
}
```
- **What it demonstrates**: variable sensitivity masking plus CLI/provider pinning — the two baseline guardrails of every recipe.

```hcl
# Sentinel policy rules (tags-policy.sentinel)
import "tfplan/v2" as tfplan

# Allowed Azure regions
allowed_regions = ["eastus", "uksouth"]

# sentinel.hcl
policy "tags-policy" {
  source            = "./tags-policy.sentinel"
  enforcement_level = "hard-mandatory"   # Block applies if fail
}
```
- **What it demonstrates**: Sentinel policy set with `hard-mandatory` enforcement that blocks plans violating the region allowlist.

Local OPA gate on a plan:
```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test -p policy plan.json
```

## Reference Tables
| Concern | Practice | Tooling |
|---|---|---|
| Secrets | Retrieve at apply time; never in .tf/state | Azure Key Vault, HashiCorp Vault |
| Identity | Least privilege at RG scope; rotation | Managed Identity, OIDC, Vault short-lived tokens |
| Compliance | Block non-compliant plans pre-apply | Sentinel (TFC/TFE), OPA (Rego, CI/CD) |
| State | Remote backend, locking, backups | Azure Storage (blob leases), TFC, S3 versioning |
| Versions | Pin CLI + providers, commit lockfile | `required_version`, `required_providers`, `.terraform.lock.hcl` |
| Drift | Scheduled detection, audit monitoring | `terraform plan` automation, `refresh`, Activity Logs/CloudTrail |

Typical enterprise policy rules: mandatory tags (`cost_center`, `application_id`, `environment`); storage accounts encrypted with public access disabled.

## Worked Example
Chef's Special — **secure-by-default Azure landing zone** (`chef-special-secure-blueprint`, three courses):
1. **Appetizer (modules)**: `network/` module creates the RG, VNet, app subnet and NSG with no public IP on the NIC; `compute/` builds a private Linux VM whose managed identity is wired into the Key Vault role assignment; `secrets/` deploys the RBAC Key Vault. A cloud-init template (`cloudinit.tpl`, installs curl/jq) fetches the secret at boot — only the secret *URI* passes through Terraform, so state/logs/outputs never contain the value.
2. **Main course (OPA policy)**: Rego files `allowed.rego`, `common.rego`, `tags.rego`, `storage.rego` are tested locally: `terraform plan -out=tfplan` → `terraform show -json tfplan > plan.json` → `conftest test -p policy plan.json`; any deny rule fails the test and blocks apply.
3. **Dessert (GitHub pipeline)**: `.github/workflows/secure-blueprint.yml` runs the same plan+conftest gate on pull requests and fails the PR if tags are missing or the region is not approved; then `terraform apply tfplan` from the saved plan.

Verification checklist: RG `*-rg` exists; VM shows only a private address; NSG denies Internet inbound; Key Vault holds `db-password`; `/opt/kv/db-password` exists on the VM with mode 0600; PRs fail on missing tags or unapproved location. Tips: assign VM identity only `Key Vault Secrets User` at vault scope; retry cloud-init if RBAC propagation delays the first boot; replace broad AzureCloud egress allows with service tags in strict environments.

## Key Takeaways
1. Fetch secrets at apply time from a vault; `sensitive = true` masks output but does not remove values from state.
2. Lock state with a remote backend and restrict it to the CI identity — state locking and backups are non-negotiable in regulated industries.
3. Enforce compliance as policy on the plan (Sentinel `hard-mandatory` or OPA/conftest) before any apply, in CI on every PR.
4. Pin `required_version` + `required_providers` and commit `.terraform.lock.hcl`; upgrade deliberately with `terraform init -upgrade` via a PR, never accidentally.
5. Isolate one state per environment in `environments/dev|staging|prod`; modules hold no provider configuration and environments override only inputs.
6. Detect drift on a schedule with `terraform plan`; resolve by either adopting the change in code or re-applying to overwrite — and `import` pre-existing resources before refining HCL.
7. Keep a short compatibility matrix (`README.md` / `.terraform-version`) so developer laptops and pipelines run identical toolchains.

## Connects To
- **Ch 3**: variable `sensitive = true` and tfvars handling introduced there are made enterprise-grade here with vault retrieval.
- **Ch 4**: the modules/environment split is the secured, team-scaled version of module composition.
- **Ch 14**: drift detection here feeds directly into troubleshooting failed applies and state lock issues.
- **Ch 16**: policy-as-code and OIDC identities are the governance foundation HCP Terraform formalizes with remote state, VCS integration, and RBAC.