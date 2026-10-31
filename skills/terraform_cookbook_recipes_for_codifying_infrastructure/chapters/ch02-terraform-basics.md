# Chapter 2: Terraform Basics

## Core Idea
Terraform code quality is produced by a layered validation and automation pipeline — fmt and validate for style and syntax, TFLint and TFSec for lint and security, preconditions/postconditions and OPA for runtime and policy checks — all wired into GitHub Actions so bad code can never reach `main`.

## Frameworks Introduced
- **fmt-then-validate Gate**: format before you check
  - When to use: every save/commit, to make code readable and syntactically sound.
  - How: run `terraform fmt` (style; needs no provider context), then `terraform init` and `terraform validate` (syntax, missing required arguments, incorrect references — validate requires provider context from init, but cannot tell whether the config produces the desired infrastructure).
- **Terraform Console REPL**: rapid experimentation loop
  - When to use: testing functions, expressions, or interpolation without touching configuration files.
  - How: run `terraform console` (a read-eval-print loop on the current workspace's state); try `2 + 3`, `join(",", ["a","b","c"])`, `lookup({a="foo", b="bar"}, "a", "default")`.
- **TFLint Linting Layer**: provider-aware quality checks beyond validate
  - When to use: catching what built-in validation misses — deprecated resource attributes, AWS naming-convention violations, insecure overly permissive security group rules, variable-type/usage inconsistencies, unused variables, duplicate resources.
  - How: install the TFLint binary, run `tflint` in the config directory; integrate into CI/CD or Git precommit hooks.
- **TFSec Security Scanning Layer**: static security analysis of Terraform
  - When to use: finding insecure patterns — unencrypted S3 buckets, permissive ingress rules, default VPC usage, unencrypted EBS volumes.
  - How: install and run `tfsec`; suppress a single check with `#tfsec:ignore:<check-id>` plus a documented reason (use sparingly); configure via `.tfsec.yml`/`.tfsec.yaml`.
- **Preconditions and Postconditions**: validate inputs before, outcomes after
  - When to use: preconditions to catch bad inputs before any resource operation; postconditions to verify a resource's resulting state meets criteria.
  - How: preconditions via a `validation` block inside a `variable` block (`contains(["t2.micro","t2.small"], var.instance_type)` with an `error_message`); postconditions via a `lifecycle { postcondition { condition = ... } }` block on the resource (available from Terraform 0.13).
- **Policy as Code with OPA**: evaluate a plan JSON against Rego rules
  - When to use: enforcing organization-wide rules (allowed instance types, mandatory tags) before apply.
  - How: write `deny[...]` rules over `input.resource_changes[_]` in a Rego file; generate the plan with `terraform plan -out=tfplan` then `terraform show -json tfplan > tfplan.json`; evaluate `opa eval --data terraform.rego --input tfplan.json "data.terraform.deny"` — empty output means no violations; in CI, fail the run if violations are non-empty, and review/update policies as infrastructure evolves.
- **Blast Radius Limitation**: shrink what any one change can damage
  - When to use: every real infrastructure change, as design-in defaults.
  - How: modularize code; isolate environments in HCP Terraform workspaces with state locking and RBAC; fine-grained least-privilege IAM roles; toggled resource creation via `count = var.enable_feature_x ? 1 : 0`; strong change management (branches, PRs, plan output in review); Sentinel policies for governance; smaller, more frequent applies; module unit tests plus integration tests with Terratest; `-target` only for troubleshooting and emergencies.

## Key Concepts
- **terraform fmt**: reformats Terraform files to the recommended style guidelines automatically; a generic operation that does not need provider information.
- **terraform validate**: checks syntax and semantics (syntax errors, missing required arguments, incorrect references) before apply; requires `terraform init` first for provider context.
- **TFLint**: a third-party linting tool detecting issues built-in validation misses, including provider-specific best practices.
- **TFSec**: a third-party security scanner flagging insecure patterns, misconfigurations, and noncompliant settings with fix suggestions.
- **Precondition**: a condition verified before Terraform creates or modifies resources — in practice a `validation` block that halts execution with a custom error message.
- **Postcondition**: a condition checked after a resource is created or updated, verifying the resulting state meets criteria (declared under `lifecycle`).
- **Open Policy Agent (OPA)**: a general-purpose policy engine; with Terraform, Rego `deny` rules evaluate against the plan JSON's `resource_changes` array to block noncompliant changes.
- **terraform-docs**: a third-party generator that turns module code (inputs, outputs, providers, resources) into documentation in Markdown, JSON, YAML, HTML, or AsciiDoc, driven by the `description` fields and a `.terraform-docs.yml` config.
- **Dependabot**: GitHub's dependency-update automation; with `package-ecosystem: "terraform"` it opens pull requests (e.g., weekly, limit 5) to raise provider and module versions, with `ignore` rules to block specific upgrades such as the AWS 5.x major line.
- **DevContainer**: a `.devcontainer/` Dockerfile + `devcontainer.json` pair that builds a reproducible environment (Terraform image, git, `hashicorp.terraform` extension) for GitHub Codespaces.
- **Blast radius**: the scope of infrastructure affected by a change or failure — reduced structurally through modules, workspace separation, least-privilege IAM, and feature toggles.
- **Sentinel policies**: HCP Terraform's policy-as-code mechanism for enforcing governance rules across infrastructure.

## Mental Models
- "Think of the validation stack as a series of sieves: fmt catches style, validate catches syntax, TFLint catches quality, TFSec catches insecurity, OPA catches policy violations — each sieve exists because the previous one lets things through."
- "Think of a variable `validation` block as a bouncer at the door and a resource `postcondition` as an inspector at exit: one gates what enters apply, the other verifies what apply produced."
- "Think of a Terraform plan as the contract: convert it to JSON with `terraform show -json` and any engine (OPA, CI checks) can read and veto that contract before apply."
- "Think of the devcontainer recipe as the same Terraform team playbook executed in the browser: Terraform image, git, and the `hashicorp.terraform` extension, identical for every contributor."

## Anti-patterns
- **Relying on `terraform validate` alone for confidence**: it reports errors but explicitly does not check whether the configuration produces the desired infrastructure — stack TFLint, TFSec, and OPA on top.
- **Scattering `#tfsec:ignore:` comments without documentation**: the recipe says to use suppression sparingly and always document why; undocumented suppressions hide real risk.
- **Using `local-exec` provisioners for production postcondition checks**: shown only to simulate postconditions; it runs on the machine running Terraform and is "unsuitable for most production use cases" — verify with external tools, scripts, or testing frameworks instead.
- **Auto-accepting Dependabot provider PRs**: always review the changelog, run validation and tests against the update, weigh breaking changes, and adapt code before merging — never apply straight to production.
- **Blanket `allow` on dependency updates for all major versions**: the example deliberately uses `ignore` on the AWS 5.x line to exclude major upgrades; letting majors flow through invites breaking changes.
- **Large, sweeping applies and `-target` as a routine tool**: both amplify blast radius — favor smaller, more frequent applies and reserve `-target` for troubleshooting or emergencies.
- **Letting documentation drift from code**: hand-written module docs go stale; generate with terraform-docs in precommit hooks or CI and keep meaningful `description` fields so output stays informative.
- **Credentials loose in cloud dev environments**: with Codespaces, use environment variables or a secure secret-management system (e.g., set `TF_TOKEN_APP_TERRAFORM_IO` from `terraform login` when using HCP Terraform).

## Code Examples
<!-- fmt/validate order -->
```bash
# Step 1: Run the Terraform format command
terraform fmt

# Step 2: Run the Terraform validate command
terraform init
terraform validate
```
- **What it demonstrates**: the mandatory ordering — `validate` needs provider context from `init`; `fmt` does not.

<!-- precondition and postcondition -->
```hcl
# Precondition: Variable validation
variable "instance_type" {
  type        = string
  description = "The instance type for the EC2 instance."

  validation {
    condition     = contains(["t2.micro", "t2.small"], var.instance_type)
    error_message = "The instance_type must be one of: t2.micro, t2.small."
  }
}

# Resource with postcondition
resource "aws_instance" "example" {
  ami           = "ami-0c947788c95c71c99"
  instance_type = var.instance_type

  tags = {
    Name = "example-instance"
  }

  lifecycle {
    postcondition {
      condition     = self.tags["Name"] == "example-instance"
      error_message = "The Name tag must be set to 'example-instance'."
    }
  }
}
```
- **What it demonstrates**: validation block as precondition (halts with the error message) and a `lifecycle` postcondition asserting the resulting tags.

<!-- OPA policy as code -->
```rego
package terraform

# Define a policy to restrict allowed EC2 instance types
deny["Instance type must be t2.micro or t2.small"] {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"
  instance_type := resource.change.after.instance_type
  not instance_type == "t2.micro"
  not instance_type == "t2.small"
}
```
- **What it demonstrates**: a Rego deny rule evaluated over the plan JSON's `resource_changes` array — empty `opa eval` output means no violations.

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
opa eval --data terraform.rego --input tfplan.json "data.terraform.deny"
```
- **What it demonstrates**: the plan-to-JSON-to-OPA evaluation chain that gates applies on policy compliance.

## Reference Tables
**Validation layer comparison (recipes 2.1–2.6):**

| Layer | Command / Tool | Catches | Needs init? |
|---|---|---|---|
| Style | `terraform fmt` | Non-conforming formatting, hard-to-read code | No (generic operation) |
| Syntax/semantics | `terraform validate` (after `terraform init`) | Syntax errors, missing required arguments, incorrect references; does not check the config produces the desired infrastructure | Yes (provider context) |
| Quality/lint | TFLint | Deprecated attributes, naming-convention violations, unused variables, duplicate resources, type mismatches, permissive security groups | — |
| Security | TFSec | Unencrypted S3 buckets, permissive ingress rules, default VPC usage, unencrypted EBS volumes | — |
| Input/output contract | `validation` blocks, `postcondition` blocks | Invalid inputs before apply; wrong resulting resource state after | Built into Terraform |
| Policy | OPA (`opa eval` on plan JSON) | Organization rules: disallowed instance types, missing mandatory tags | Yes (plan) |

**Dependabot configuration fields (recipe 2.9):**

| Field | Value / meaning |
|---|---|
| `package-ecosystem` | `"terraform"` — updates Terraform providers and modules |
| `directory` | `"/"` — check the repository root |
| `schedule.interval` | `"weekly"` (adjustable) |
| `open-pull-requests-limit` | `5` — cap on simultaneous open update PRs |
| `allow` | `"all"` — direct and indirect dependencies |
| `ignore` | Exclude specific updates, e.g. `aws` versions `["5.x"]` to skip major upgrades |

## Worked Example
**Automated validation pipeline (recipes 2.8 + 2.9 + 2.1), end to end:**

1. Create `.github/workflows/terraform_validation.yml` triggering on push to `main` and on all `pull_request` events.
2. Job steps: check out the repository (`actions/checkout@v4`); set up Terraform (`hashicorp/setup-terraform@v2`, `terraform_version: 1.10.0`); run `terraform init` and `terraform validate` for basic syntax and configuration errors; set up TFLint (`terraform-linters/setup-tflint@v3`, `v0.53.0`) and run `tflint --format=compact` for stylistic issues validate misses; run TFSec (`aquasecurity/tfsec-action@v1.0.3`) for security issues.
3. If any check fails, the workflow errors and GitHub blocks the merge into `main` — only valid Terraform code gets in.
4. Extend the same workflow with an OPA evaluation step: generate `tfplan.json` with `terraform show -json`, run `opa eval`, and `exit 1` on any policy violations so noncompliant changes can never be applied.
5. Keep provider versions fresh: commit `.github/dependabot.yml` with `package-ecosystem: "terraform"`, a weekly schedule, an open-PR limit of 5, and an ignore on the AWS 5.x major line.
6. When a Dependabot PR arrives: review the changelog, re-run the workflow's validation and tests against the updated version, assess breaking changes, and update the code if needed before merging.

## Key Takeaways
1. Always run `terraform fmt` before `terraform init` + `terraform validate`; formatting is a generic operation, while validation needs provider context and still cannot guarantee the config produces what you expect.
2. Layer the sieves rather than trusting one tool: validate for syntax, TFLint for lint and provider-specific quality, TFSec for security, OPA for policy.
3. Put validation where it cannot be bypassed — a GitHub Actions workflow on push and pull_request, or Git precommit hooks — so failures block the merge.
4. Preconditions (`validation` blocks) catch bad inputs before any resource changes; postconditions (`lifecycle` blocks) verify the resulting state; keep the `local-exec` simulation out of production.
5. Convert plans to JSON (`terraform show -json tfplan > tfplan.json`) and evaluate Rego `deny` rules with `opa eval` in CI; an empty result passes, violations fail the pipeline, and policies need regular review as infrastructure evolves.
6. Generate module docs with terraform-docs (`.terraform-docs.yml` for section, sort, and format control) driven by meaningful `description` fields — never hand-maintain them.
7. Provision consistent dev environments as code: a `.devcontainer/` Dockerfile from `hashicorp/terraform:latest` plus `devcontainer.json` with the `hashicorp.terraform` extension eliminates "works on my machine."
8. Design blast radius down deliberately: modules, separate HCP Terraform workspaces per environment with state locking and RBAC, least-privilege IAM, feature toggles via `count`, smaller and more frequent applies, Terratest for module and integration tests, and `-target` only in emergencies.

## Connects To
- **Ch 1**: chapter 1's version constraints, lock files, and GitOps branch protection are the standards this chapter's pipeline mechanically enforces; HCP Terraform reappears as remote state (workspace isolation) and Sentinel policy execution.
- **Ch 3 (Terraform Syntax Patterns)**: the `terraform console` REPL used here for experimentation is the natural proving ground for the functions and data-structure manipulation covered next.
- **Policy as code / OPA Rego**: `deny` rules over `input.resource_changes` are the standard OPA-Terraform integration pattern, with Sentinel as HCP Terraform's native counterpart.
- **Shift-left security (TFSec/TFLint in CI/CD)**: running scanners pre-merge mirrors the broader DevSecOps principle of catching issues at the earliest, cheapest stage.
- **Terratest**: the named tool for the unit and integration testing that blast-radius reduction requires.