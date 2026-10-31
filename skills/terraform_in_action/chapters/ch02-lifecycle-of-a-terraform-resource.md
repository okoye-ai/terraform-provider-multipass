# Chapter 2: Life cycle of a Terraform resource

## Core Idea
Terraform is fundamentally a state management tool that performs CRUD operations on managed resources: every managed resource implements the resource schema interface with four lifecycle function hooks — Create(), Read(), Update(), Delete() — and Terraform invokes them based on plan-time diffing of desired vs. current state.

## Frameworks Introduced
- **The Plan Decision Tree** (figure 2.4): the exact algorithm behind `terraform plan`
  - When to use: predicting what an apply will do, or debugging surprising plans
  - How:
    1. Read configuration (main.tf) and state (terraform.tfstate)
    2. For each resource: **in state?** No → `Create()`. Yes → call `Read()`
    3. **Has changes?** No → No-op. Yes → **is it a destroy plan?** Yes → `Delete()`, No → `Update()` (or destroy/recreate for force-new attributes)
    4. Output the plan, ordered by the dependency graph
- **Lifecycle Function Hooks**: Create() on create; Read() on plan generation (and refresh); Update() on in-place updates; Delete() on destroy. Data sources implement only Read().
- **Force New / Immutable Updates**: some attributes (e.g. local_file's `content`) are "force new" — changing them taints the resource and triggers a destroy-then-recreate (`-/+ destroy and then create replacement`), not an in-place update
  - Failure mode: force-new replacements of live services cause downtime → chapter 9's zero-downtime techniques
- **Configuration Drift Correction**: someone changed the deployed resource out-of-band → Terraform detects the diff between current and desired state on the next plan and corrects it on apply
  - `terraform refresh` = "a plan that also alters the state file" — reconciles state with what is deployed; read-only for infrastructure, writes only to state. (Winkler: "I rarely find terraform refresh useful.")

## Key Concepts
- **Local-only resources**: resources that make no remote API calls (private keys, self-signed TLS certs, random ids, local_file) — usually glue, but ideal for teaching the lifecycle
- **terraform block**: `terraform { required_version, required_providers }` — version-locking code; also configures backends and provider download (ch6)
- **Heredoc syntax**: `<<-EOT ... EOT` for multiline strings; leading whitespace ignored
- **Idempotency**: `terraform init` and `terraform plan` are idempotent — safe to run repeatedly
- **-auto-approve**: skips the manual approval step; dangerous unless the plan was already reviewed
- **terraform.tfstate.backup**: archival copy of the previous state file; safe to delete
- **TF_LOG=trace**: enables trace-level logging for debugging; turn it off (and raise `-parallelism=n`) if plans run slowly

## Code Examples
```hcl
terraform {
  required_version = ">= 0.15"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"    # version-lock all providers for repeatable deployments
    }
  }
}
resource "local_file" "literature" {
  filename = "art_of_war.txt"
  content  = <<-EOT
    Sun Tzu said: The art of war is of vital importance to the State.
  EOT
}
```
- **What it demonstrates**: the terraform settings block + declared resource with heredoc; Terraform infers the Local provider dependency and downloads it on `terraform init` (no provider block required)

Plan-to-JSON pipeline for tool/policy integration:
```bash
terraform plan -out plan.out && terraform apply "plan.out"
terraform show -json plan.out > plan.json
```
- **What it demonstrates**: the apply output is identical to the plan output; `plan -out` + `apply "plan.out"` guarantees exactly the reviewed actions run (key for CI/CD, ch12)

## Reference Tables
| Command | Calls | Mutates infra? | Mutates state? |
|---|---|---|---|
| terraform plan | Read() per resource | No | No |
| terraform apply | Create/Update/Delete | Yes | Yes |
| terraform refresh | Read() per resource | No | Yes |
| terraform destroy | Delete() on all resources | Yes | Yes |
| terraform show | — | No | No (prints state/plan) |

## Key Takeaways
1. Always run `terraform plan` before deploying — it's a free linter + dry-run; never `-auto-approve` an unreviewed plan.
2. A plan can only produce five actions: Create, Read, Update, Delete, No-op — knowing which one you'll get is knowing Terraform.
3. Resources are executed in dependency order via the dependency graph (`terraform graph` emits DOT).
4. Force-new changes destroy and recreate the resource — plan output will show `-/+ destroy and then create replacement`.
5. Losing or corrupting terraform.tfstate means losing track of managed resources — never edit it manually.

## Connects To
- **Ch 5**: state management in depth (remote backends)
- **Ch 9**: zero-downtime deployments for force-new replacements
- **Ch 11**: writing providers that implement these hooks
- **Ch 12**: plan/apply separation for CI/CD automation