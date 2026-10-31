# Chapter 16: Collaborative Workflows with Terraform Cloud

## Core Idea
Terraform Cloud / HCP Terraform turns Terraform from an individual CLI tool into a governed team platform: remote state with locking and versioning, VCS-triggered runs, Sentinel policy enforcement, a private module registry, and role-based access. Prefer it over CLI-only workflows whenever more than one person touches the same infrastructure.

## Frameworks Introduced
- **Workspace-per-environment principle**: one Terraform Cloud workspace per environment per infrastructure component or application.
  - When to use: any team managing dev/staging/prod; isolating state, variables, permissions, and run history per environment.
  - How: name workspaces like `billing-app-dev`, `billing-app-stage`, `billing-app-prod`, `networking-dev`; HashiCorp's guiding equation is "Terraform configurations multiplied by environments equals workspaces". Additionally: split state-intensive resources (databases, file storage) into their own workspaces away from compute, align workspace ownership with team responsibilities (`networking-*` owned by the networking team), and group related workspaces into **projects** for bulk assignment of permissions, variable sets, and policy sets.
- **Three Terraform Cloud run workflows**: the chapter's canonical ways to initiate runs.
  - When to use: pick the workflow that matches how changes enter your system.
  - How: **VCS-driven** (commits/PRs trigger runs automatically — the default for code-reviewed infra), **CLI-driven** (local `terraform plan/apply` executing remotely), **API-driven** (programmatic triggering from external pipelines or orchestrators).
- **Run lifecycle**: plan → Sentinel policy check → apply, on dedicated disposable VMs, with workspace locking and sequential queueing.
  - When to use: whenever you need to reason about where policy, approval, and extensibility hooks fit.
  - How: every plan is tied to a specific configuration version and variable set; policy types read `tfplan`, `tfconfig`, `tfstate` data; apply happens only after policy checks pass and (if not autoapply) a human confirms. **Speculative plans** bypass the run queue for PR previews; **saved plans** separate planning from apply. **Run tasks** (pre-plan, pre-apply) inject external tools — security checks, compliance validation, approval gates — at strategic points.
- **Sentinel policy sets with enforcement levels**: governance embedded between plan and apply.
  - When to use: enforce tagging, instance types/regions, public-access bans before any apply.
  - How: author `.sentinel` HCL files importing `tfplan`/`tfconfig`/`tfstate`/`tfrun`; declare them in a `sentinel.hcl` manifest with an enforcement level (`advisory`, `soft-mandatory`, `hard-mandatory`); attach the set to a workspace, project, or the whole organization via UI, API, or the `tfe` provider.

## Key Concepts
- **HCP Terraform (Terraform Cloud)**: HashiCorp's managed collaboration service — remote state with automatic locking and versioning, remote run execution, VCS integration, Sentinel/OPA policy as code, private module registry, RBAC, variable encryption.
- **Remote backend vs cloud block**: `backend "remote"` (with `hostname`, `organization`, `workspaces.name` or `prefix` — never both) is the classic backend; the newer `terraform { cloud { ... } }` block is the Terraform Cloud–native form and supports both local and remote operations.
- **Workspace mapping**: with `prefix = "app-"`, CLI workspace `dev` maps to Cloud workspace `app-dev`; Cloud workspaces encapsulate configuration, state, variables, run history, and access controls, and Cloud's backend settings override any backend block in the code.
- **Speculative plan**: a plan-only run triggered on pull requests that bypasses the run queue and posts a link in the PR; by default it only fires for PRs from the same repository (not external forks).
- **Enforcement levels**: `advisory` (failure logged as warning, run proceeds), `soft-mandatory` (run blocks unless an authorized user overrides), `hard-mandatory` (run stops, no override).
- **Private module registry**: organization-scoped module catalog; publish modules named `terraform-<PROVIDER>-<MODULE_NAME>` (e.g. `terraform-aws-vnet`), versioned by Git tags; consuming them uses source addresses like `app.terraform.io/<ORG>/terraform-aws-vnet/aws`.
- **Run tasks**: pre-plan or pre-apply hooks for external tools (security scanning, compliance checks, approval gates).
- **Terraform Enterprise**: the self-hosted variant, adding SAML SSO, Vault-backed dynamic credentials (just-in-time secrets), Audit Trails JSON API (SIEM integration e.g. Splunk), No-Code provisioning for non-HCL users, and continuous validation.
- **Atlantis**: open-source, self-hosted GitOps tool that runs `terraform plan` inside PRs and applies on `atlantis apply`; pairs with external tooling to fill gaps in policy, RBAC, drift detection, and audit logging.
- **Spacelift**: SaaS alternative with multi-IaC support (Terraform, Pulumi, CloudFormation, Ansible, Kubernetes), declarative trigger policies, OPA policy as code, drift detection, and a private module registry with integrated CI.

## Recipes in this chapter
- **Recipe 91: Remote state on Terraform Cloud** — migrate an existing local project to Terraform Cloud via the `cloud` block, `terraform login`, and `terraform init` (answers yes to state migration); verify state versions in the UI and locking with concurrent background `terraform plan` commands.
- **Recipe 92: VCS-backed workspace** — connect a workspace to GitHub/GitLab, observe speculative plans on PRs and plan runs on pushes, then review and manually approve the apply.
- **Recipe 93: Collaboration via Terraform Cloud** — simulate a two-person flow: one user (Alice) triggers a plan, the other (Bob) reviews the run, optional Sentinel policy check, approves and applies; both inspect run history and state versions.
- **Recipe 94: Sentinel policy in Terraform Cloud** — write `policies/s3-versioning-required.sentinel` plus a `sentinel.hcl` manifest (hard-mandatory), attach the policy set via UI or the `tfe` provider, push a non-compliant S3 change to watch the run fail, then remediate.
- **Recipe 95: Using the private module registry** — publish a module repo following `terraform-<PROVIDER>-<MODULE_NAME>`, tag it (e.g. `v1.0.0`), publish via Registry | Publish | Module, and reference it with `source = "app.terraform.io/<ORG_NAME>/terraform-aws-vnet/aws"`.
- **Recipe 96: Managing team access** — create Networking Team and App Team; grant Plan (plan-only) vs Write (plan + apply + variable changes + lock/unlock) fixed permission sets; scale with project-level permissions and variable sets, then verify least privilege by signing in as each user.

## Anti-patterns
- **Team workflows on local CLI only**: no shared state locking, no run visibility, no policy enforcement — the core problem Terraform Cloud exists to solve.
- **Mixing `name` and `prefix` in the remote backend block**: you may use one or the other, never both.
- **Relying on speculative plans for external-fork PRs**: they are disabled for forks unless explicitly enabled in Enterprise settings — don't assume external contributors get plan previews.
- **Mixing `tfe` policy-attachment mechanisms**: don't set `workspace_ids` on `tfe_policy_set` while also using the dedicated `tfe_workspace_policy_set` attachment resource; pick one method consistently.
- **Adopting Atlantis for large organizations without fill-ins**: scalability, state management, policy enforcement, advanced RBAC, drift detection, and audit logging must come from companion tooling.
- **Cross-team workspace interference**: letting any team share a workspace erodes least privilege; align workspace ownership to teams and use projects for bulk governance.
- **Assuming one edition for everything**: free-tier Terraform Cloud caps policy sets at one set with up to five policies — plan policy architecture to your tier.

## Code Examples
```hcl
// file: policies/s3-versioning-required.sentinel
import "tfplan"

main = rule {
  all tfplan.resources.aws_s3_bucket as _, buckets {
    all buckets as _, b {
      // Require versioning to be explicitly enabled
      b.applied.versioning is not null and
      length(b.applied.versioning) > 0 and
      (b.applied.versioning[0].enabled else false)
    }
  }
}
```
- **What it demonstrates**: a hard-mandatory Sentinel policy reading the `tfplan` scope to block S3 buckets without versioning — the chapter's canonical policy-as-code pattern.

```hcl
data "terraform_remote_state" "networking" {
  backend = "remote"
  config = {
    organization = "<ORG>"
    workspaces = { name = "networking-dev" }
  }
}

resource "azurerm_linux_virtual_machine" "app_vm" {
  name                = "app-vm"
  resource_group_name = data.terraform_remote_state.networking.outputs.rg_name
  # additional configuration...
}
```
- **What it demonstrates**: cross-workspace state sharing in the Chef's Special — the Application workspace consumes the Networking workspace's outputs via `terraform_remote_state` with the `remote` backend (state access and permissions must be enabled).

## Reference Tables
Table 16.1 — CLI commands, variables, and access control (condensed):

| Aspect | CLI usage | Variables / access |
|---|---|---|
| Workspace management | `terraform workspace new/select/list/show` | State isolated per workspace |
| Remote run execution | `terraform plan -out=tfplan` then `terraform apply tfplan`; logs stream locally | Runs execute in the Cloud workspace context; state stays secure |
| Variable precedence | `-var`, `-var-file`, `TF_VAR_…` override | Workflow overrides > workspace variables > variable set values |
| Variable scope | n/a | Workspace variables need read/write variables permissions; org/project variable sets need team permissions (owners or managers) |
| Variable automation | n/a | Project-owned variable sets enable scoped control without org-wide permissions |

Table 16.2 — Chef's Special project structure:

| Component | Workspace(s) | Purpose / mechanism |
|---|---|---|
| Networking project | networking-dev, networking-prod | Hosts infrastructure outputs (e.g. subnet IDs) |
| Application project | app-dev, app-prod | Consumes networking outputs, builds dependent resources |
| Cross-workspace dependency | `terraform_remote_state` | Connects application to networking outputs securely |
| Policy enforcement | Sentinel policy sets | Enforce tagging/compliance before apply |
| Governance & automation | VCS workflow + run tasks | Structured review and guarded application |

## Worked Example
Chef's Special: **Team-based infrastructure project simulation**.
1. *Appetizer — Establish separate workspaces*: create two projects (Networking, Application); under each, workspaces `networking-dev`/`networking-prod` and `app-dev`/`app-prod`. Assign only the Networking team to networking workspaces; attach per-project variable sets (shared credentials) to each project.
2. *Main course — Networking output consumed by application*: in `networking-dev`, modify a subnet CIDR and let the VCS-driven workflow plan and apply. In `app-dev`, declare `data "terraform_remote_state" "networking"` with `backend = "remote"`, and reference `data.terraform_remote_state.networking.outputs.rg_name` in the app VM resource (state access and permissions must be granted).
3. *Dessert — Automated approval flow with Sentinel guardrails*: attach a mandatory-tagging Sentinel policy set to `app-dev`; the application team commits → speculative plan → pre-apply run task performs compliance checks → Sentinel plus a human approval gates the apply. The team lead reviews the plan in the UI and applies in `app-dev`.
Result: modular workspaces, team-owned domains, safely shared outputs, and governance enforced both in code and process — a mature enterprise DevOps pipeline.

## Key Takeaways
1. Move team state to Terraform Cloud via the `cloud` (or `backend "remote"`) block and `terraform init`; migration is non-disruptive and recreates nothing.
2. Structure workspaces as *configurations × environments*, separated further by infrastructure type and aligned to team ownership; group them into projects for bulk permissions, variable sets, and policy sets.
3. Default to the VCS-driven workflow: speculative plans on PRs give reviewers infrastructure impact before merge, and auto-apply vs manual-apply is a deliberate workspace choice.
4. Author Sentinel policies against the `tfplan` scope, bind them with enforcement levels appropriate to risk (advisory → hard-mandatory), and attach policy sets as code with the `tfe` provider for auditability.
5. Standardize module reuse through the private registry: `terraform-<PROVIDER>-<MODULE_NAME>` repos, semantic-version Git tags, and `app.terraform.io/<ORG>/<module>/<provider>` source addresses.
6. Implement least privilege with fixed permission sets (Read, Plan, Write, Admin): plan-only for reviewers, Write for those who approve and apply, project-level grants when many workspaces share a policy.
7. When Terraform Cloud's model feels restrictive, Terragrunt or Terramate add DRY, nested structure; Atlantis or Spacelift are alternatives when you need self-hosting or multi-IaC support — each with governance trade-offs.

## Connects To
- **Ch 15 (multi-cloud, Recipes 85–90)**: precedes this chapter; once workloads exist across clouds, Terraform Cloud is the platform that governs team change over them.
- **Ch 17 (capstone)**: applies the collaboration model to a full enterprise Azure deployment — the capstone assumes the governed workflow this chapter establishes.
- **Earlier policy/testing chapters (Sentinel/OPA, CI recipes 67–72, 74)**: this chapter operationalizes policy as code and pipeline discipline on a managed platform instead of ad-hoc CI.