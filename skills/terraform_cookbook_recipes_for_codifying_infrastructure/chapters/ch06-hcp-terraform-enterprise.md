# Chapter 6: HCP Terraform and Terraform Enterprise

## Core Idea
HCP Terraform (formerly Terraform Cloud) and Terraform Enterprise turn Terraform from a CLI tool into a collaborative platform: the `cloud` block moves state, execution, policy, and cost controls server-side, and every recipe layers one capability — VCS automation, Sentinel enforcement, cost estimation, remote operations, or state recovery — on top of that workspace foundation.

## Frameworks Introduced
- **HCP Terraform workspace setup workflow**: the six-step onboarding path from account to applied infrastructure.
  - When to use: first adoption, or standing up a new organization.
  - How: create account → create organization → create a workspace (Version Control Workflow recommended) → configure settings (working directory, sensitive environment variables) → queue the first plan → review and apply.
- **GitOps VCS integration**: infrastructure changes flow through commits, pull requests, and code reviews.
  - When to use: teams wanting plans triggered automatically on push, with optional auto-apply after a successful plan.
  - How: declare the `terraform { cloud { organization ... workspaces { name } } }` block, then in workspace settings connect the VCS provider (GitHub, GitLab, Bitbucket) via token authentication, pick the repository, branch, and subdirectory; add branch protection rules on main branches.
- **Centralized remote state consumption**: HCP Terraform as the authoritative state backend.
  - When to use: multi-environment or multi-team projects where local state is a coordination hazard.
  - How: the `cloud` block alone replaces backend configuration; you gain state locking, state version history, access control, and operational consistency (everyone works from the same state), and keep org/workspace names out of public discussion.
- **GitHub Actions pipeline for HCP Terraform**: CI/CD gated on branch, authenticated by API token.
  - When to use: automating plan/apply on every push to `main` while keeping state in HCP Terraform.
  - How: `hashicorp/setup-terraform` with `cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}`, then init → `fmt -check -recursive` → plan → apply with `if: github.ref == 'refs/heads/main'`; prefer manual approvals or PR workflows over `-auto-approve` for production.
- **Collaborative workspace workflow**: workspaces + RBAC + speculative plans as the team operating model.
  - When to use: multiple people changing infrastructure with review, audit, and separation between environments.
  - How: one workspace per environment (e.g. `project-environment` = production/staging), credentials as workspace variables injected at runtime, teams with role-based permissions in org settings, feature branches and PRs, plus run triggers to chain dependent workspaces.
- **Systematic troubleshooting checklist**: a fixed review order for failed or unexpected runs.
  - When to use: config errors, authentication issues, or VCS integration mishaps in HCP Terraform / Terraform Enterprise.
  - How: run Details tab → VCS connection status and webhooks → workspace General/Variables settings → local `terraform init && terraform validate` → team permissions and credential variables → Sentinel policy review → status.hashicorp.com, then HashiCorp support.
- **Sentinel policy-as-code enforcement**: compliance, security, and cost rules evaluated on every run.
  - When to use: scaling governance without manual oversight; standard guardrails such as instance-type restrictions, required tags, or state attribute checks.
  - How: write a `.sentinel` file with `import "tfplan"` (or `tfstate`/`tfrun`) and a `main = rule { ... }`, connect it as a policy set from VCS under Settings → Policy Sets, scope it to workspaces; failing checks halt the run with violation details. Consider soft-mandatory policies overridable with approval.
- **Cost estimation with Sentinel cost gates**: financial impact reviewed before apply.
  - When to use: controlling cloud spend as infrastructure scales, layered with notifications and standardized modules.
  - How: enable cost estimation in workspace settings, enforce limits with a `tfrun` policy on `cost_estimate.delta_monthly_cost`, add a `tfe_notification_configuration` triggered on `cost_estimation_completed`, and standardize on cost-optimized modules.

## Key Concepts
- **HCP Terraform**: the managed platform (formerly Terraform Cloud) providing centralized workspaces, secure state, VCS integrations, and automated execution plans; concepts largely apply to OpenTofu too.
- **Terraform Enterprise**: the self-hosted counterpart with the same workflow features (VCS integration, Sentinel, remote operations).
- **cloud block**: the `terraform { cloud { ... } }` configuration that binds a configuration to an HCP Terraform organization and workspace, replacing manual backend setup.
- **Workspace**: the unit of state, variables, and access control; logical separation of environments within an organization.
- **Speculative plans**: plans run on pull requests so reviewers see the potential impact before merge.
- **Run triggers**: cross-workspace dependencies that fire runs in one workspace when another's run completes.
- **tfplan / tfstate / tfrun**: Sentinel imports exposing planned resources, current state, and run metadata (including cost estimates) to policies.
- **Cost estimation**: HCP Terraform feature showing potential plan costs before apply; HCP Terraform does not send budget alerts directly — you wire notifications on `cost_estimation_completed`.
- **Remote operations**: plans and applies executed on HashiCorp's infrastructure instead of local machines, removing local resource limits.
- **State locking, versioning, and recovery**: automatic lock against concurrent runs, per-run state history, and States-tab Restore to revert to a previous version; manual `terraform state` commands (e.g. `terraform state rm`) are the cautious fallback.

## Mental Models
- Use the `cloud` block whenever more than one person or environment touches the state — local state is a single point of failure and secrets leak (state risk, lock conflicts, drift all reduce to this).
- Use the Version Control Workflow when infrastructure should change only through reviewed pull requests; use UI/API-triggered runs for exceptions and large-scale operations.
- Use Sentinel when "we trust people to remember" stops scaling — encode instance types, tags, ACLs, and cost ceilings as rules that halt noncompliant runs.
- Use restore-from-state-history first and manual state manipulation last; built-in mechanisms beat `terraform state` surgery in both safety and auditability.

## Anti-patterns
- **Committing secrets to the VCS repository**: API keys and passwords belong in workspace variables injected at runtime, never in code.
- **`-auto-approve` in production pipelines**: the flag removes human review; add manual approval steps or restrict apply to `main` with PR gates.
- **Skipping `terraform fmt -check` in CI**: formatting is the cheap quality gate that catches drift before plan.
- **Assuming HCP Terraform sends budget alerts natively**: it doesn't — configure `tfe_notification_configuration` on cost-estimation events.
- **Manual state surgery as the default**: prefer UI/API inspection and Restore; inform the team before any `terraform state` command.
- **Publishing workspace/organization names carelessly**: they can leak information about your infrastructure.
- **One workspace per project for all environments**: mixing environments into a single workspace forfeits variable, state, and access isolation (cross-environment state contamination).
- **Stale Sentinel policies**: unreviewed policies drift from actual infrastructure goals; review them as the architecture evolves.

## Code Examples
- **What it demonstrates**: binding a configuration to HCP Terraform — the single block every remote-state, collaboration, and remote-operations recipe builds on (Recipes 6.2, 6.3, 6.10).

```hcl
terraform {
  cloud {
    organization = "example-org" # Replace with your organization name
    workspaces {
      name = "example-workspace" # Replace with your workspace name
    }
  }
}
```

- **What it demonstrates**: a GitHub Actions workflow running init/fmt/plan/apply against HCP Terraform, with apply gated to `main` (Recipe 6.4).

```bash
on:
  push:
    branches:
    - main

jobs:
  terraform:
    name: 'Terraform'
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v1
      with:
        terraform_version: 1.10.0
        cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}

    - name: Terraform Init
      run: terraform init

    - name: Terraform Format
      run: terraform fmt -check -recursive

    - name: Terraform Plan
      run: terraform plan

    - name: Terraform Apply
      run: terraform apply -auto-approve
      if: github.ref == 'refs/heads/main'
```

- **What it demonstrates**: a Sentinel cost-control policy blocking any plan whose estimated monthly cost delta exceeds 1000 (Recipe 6.8).

```hcl
import "tfrun"
import "decimal"

monthly_cost_limit = decimal.new(1000)

main = rule {
    decimal.less_than(tfrun.cost_estimate.delta_monthly_cost, monthly_cost_limit)
}
```

## Reference Tables
| State capability (Recipes 6.3 / 6.10) | What it gives you | Mechanism |
|---|---|---|
| State locking | No concurrent corrupting runs | Automatic in workspace |
| State history/versioning | Track changes, revert anytime | Per-run state versions |
| State recovery | Undo unintended edits/deletes | States tab → Restore |
| State inspection | Spot drift vs. desired config | UI or API state view |
| State isolation | Per-environment state | Separate workspaces + variables |
| Constraint enforcement | Standards applied to state | Sentinel `import "tfstate"` |

| Governance lever (6.7 / 6.8) | Scope | Enforcement point |
|---|---|---|
| Sentinel `tfplan` policy | Planned resources (types, tags) | During plan/apply; halts run on failure |
| Sentinel `tfrun` policy | Cost estimate deltas | After cost estimation |
| Sentinel `tfstate` policy | Current state attributes | State validation |
| Cost estimation | Financial impact preview | Before apply |
| Notifications | `cost_estimation_completed` alerts | Email/destination config |

HCP Terraform vs. Terraform Enterprise: the chapter treats them as feature-equivalent (same cloud block, Sentinel, remote operations), differing only in hosted vs. self-hosted; no detailed comparison table is given.

## Worked Example
Recipe 6.1 is the canonical end-to-end setup. (1) Sign up at the HCP Terraform website with email and password. (2) On first login, create an organization with a unique name. (3) In the organization dashboard, click New Workspace, choose the workflow type — Version Control Workflow recommended — connect a VCS provider (GitHub, GitLab, Bitbucket), and select the repository holding your configuration. (4) Configure workspace settings: set the Terraform working directory if configuration is not at the repo root, and add environment variables for sensitive values such as cloud credentials. (5) Queue the first plan and review its output in the UI. (6) Apply to provision. From here the other recipes fork: connect VCS formally (6.2), wire GitHub Actions (6.4), add teams and speculative plans (6.5), attach policy sets (6.7), enable cost estimation (6.8), and flip on remote execution mode for large-scale deployments (6.9). The book's framing: setup is easy; the payoff comes from continuously refining workspaces, Sentinel checks, and cost estimation.

## Key Takeaways
1. Put the `cloud { ... }` block in every shared configuration — it is the entry point for locking, history, access control, and the whole collaboration feature set.
2. Make pull requests the apply path: VCS integration plus branch protection turns infrastructure changes into reviewed, audited GitOps events.
3. Store the HCP Terraform API token in GitHub Secrets (`TF_API_TOKEN`), keep `-auto-approve` off production, and gate apply to `main`.
4. Encode governance as Sentinel policy sets (instance types, required tags, ACLs, monthly cost ceilings) instead of relying on review discipline; start simple, prefer soft-mandatory rules for exceptions.
5. Layer cost control: workspace-level cost estimation, a `tfrun` policy on `delta_monthly_cost`, notifications on `cost_estimation_completed`, and reusable cost-optimized modules.
6. Use remote operations to escape local machine limits — plans/applies run on HashiCorp infrastructure with centralized logs, concurrent operations, and full audit visibility.
7. Recover state through the States tab Restore (pick the version, click Restore) and treat `terraform state` commands as a last-resort, coordinated, audited action.

## Connects To
- **Ch 2 (state fundamentals)**: Recipes 6.3 and 6.10 are the remote-execution answers to local-state locking, drift, and corruption problems.
- **Ch 5 (containers)**: cluster and container configurations deployed through HCP Terraform get the same policy, cost, and collaboration gates.
- **Ch 7 (secrets)**: workspace variables and "keep secrets out of the repo" lead directly into Terraform secrets-management techniques.
- **Sentinel / OPA policy-as-code**: Sentinel is the chapter's enforcement engine; the same pattern generalizes to other policy-as-code frameworks in the ecosystem.
- **GitOps**: every VCS-driven recipe (6.2, 6.4, 6.5) is an application of GitOps — declare intent in Git, let automation reconcile infrastructure.