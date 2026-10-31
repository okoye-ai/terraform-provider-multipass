# Chapter 3: Managing Variables, State, and Outputs in Terraform

## Core Idea
Variables inject dynamic input, state captures what was actually deployed, and outputs push information back out — together a feedback loop that links configuration to real infrastructure; the chapter's operational payoff is mastering state handling (remote backends, imports) and detecting/reconciling drift.

## Frameworks Introduced
- **The Variables / State / Outputs feedback loop**:
  - When to use: any configuration moving from fixed one-off scripts to multi-environment, team-managed code.
  - How: variables parameterize inputs at plan time; state (`terraform.tfstate`) is the authoritative ledger recording addresses, provider-assigned IDs, attribute values, and the dependency graph; outputs are named results stored in state and readable by humans, scripts, chaining modules, or remote-state consumers.
- **Variable precedence ladder** (each step overrides the one before):
  - When to use: whenever a value seems to "not take" — check which source wins.
  - How: default in variables.tf → `*.tfvars` files (`terraform.tfvars` or `-var-file=dev.tfvars`) → environment variable (`TF_VAR_vm_size=...`) → CLI flag (`-var="vm_size=..."`) → Terraform Cloud workspace variable (set in workspace UI).
- **Drift formula and reconciliation** (Drift = Actual state − Desired state):
  - When to use: whenever out-of-band changes (portal tweaks, autoscaling, scripts) may have diverged from code.
  - How: detect with `terraform plan` / `plan -refresh-only`; then either enforce desired state (`terraform apply`) or accept the manual change (`terraform apply -refresh-only` to update state only, then a clean plan); import unmanaged resources rather than duplicating them.
- **Drift guard rails** (five practices):
  - When to use: standing team policy, not incident response.
  - How: (1) lock state via remote backend; (2) run `terraform refresh` before big plans; (3) import before destroy; (4) automate policy checks (OPA/Sentinel blocking drift-prone PRs); (5) schedule drift detection — nightly `terraform plan -detailed-exitcode` in CI where a nonzero exit code triggers an alert.

## Key Concepts
- **Input variable**: a named placeholder resolved at plan time; declared with `description`, `type` (string, number, bool, list, map, object), optional `default`, optional `sensitive`.
- **Output value**: a named result Terraform records in the state file and prints after apply; stays current because it lives in state.
- **`sensitive = true`**: masks the value in plan/apply logs and UI while Terraform still uses it; sensitive values end up in plaintext only in the encrypted state in the remote backend.
- **State file contents**: resource addresses, provider-assigned IDs, attribute values, dependency-graph info — treat it like a production database (back it up, restrict access).
- **Remote backend**: centralized state storage with versioning and write-locks (Azure Blob, Terraform Cloud, S3+DynamoDB) so two engineers cannot write conflicting truths.
- **Configuration drift**: divergence of real infrastructure from code/state (Drift = Actual − Desired).
- **`for_each = toset(var.list)`**: repeats a resource block per element; adding/removing VMs becomes editing the list.
- **`terraform import <ADDR> <ID>`**: brings an existing unmanaged resource under Terraform control without recreating it.
- **`terraform state rm` / `state mv`**: safely remove or rename entries inside the ledger — never hand-edit the JSON.
- **`terraform plan -detailed-exitcode`**: 0 = no changes, nonzero = drift/changes — the primitive behind scheduled drift alerts.

## Recipes in this chapter
- **Recipe 13: Defining and using variables** — parametrized Linux VM driven by `dev.tfvars` (`region`, `vm_size`, `admin_public_key`); deploy the same code into a different region/SKU with no edits.
- **Recipe 14: Outputs for a web server** — static public IP resource plus `web_ip` output; apply ends by printing the external IP.
- **Recipe 15: Migrating to remote state (Terraform Cloud)** — `backend "remote"` block on app.terraform.io, then `terraform init -migrate-state` to gain version history and write locks.
- **Recipe 16: Declaring variables as lists** — `list(string)` of env names + `for_each = toset(var.vm_names)` to clone VMs (`dev-vm`, `qa-vm`, `prod-vm`).
- **Recipe 17: Marking sensitive variables** — `sensitive = true` on both the `admin_password` variable and an output; secrets split into `secret.auto.tfvars`, plan prints `<sensitive>`.
- **Recipe 18: Importing existing resources** — `terraform import azurerm_storage_account.legacy <full resource ID>`, then evolve safely (e.g., add tags) once Terraform owns it.

## Anti-patterns
- **Hand-editing `terraform.tfstate`**: corrupts the ledger; use `terraform state rm`/`state mv` instead.
- **Keeping local state once anyone else applies**: shared/team or CI applies on local state cause overwrite conflicts — move to a remote backend before you regret it.
- **Ignoring portal fixes**: emergency portal edits bypass review, break reproducibility, and can make the next apply delete or downsize critical resources.
- **Letting out-of-band scripts create resources**: bring the script under Terraform or import what it created.
- **Committing secrets or state to Git**: .gitignore `.terraform/`, `*.tfstate*`, `*.tfvars`/`*.auto.tfvars`, `crash.log`, `override.tf*`; deliberately pick a policy on `.terraform.lock.hcl` (commit it for reproducible provider versions, or ignore it — as a team, pick one and stick to it).
- **Passing secrets through non-sensitive outputs**: mark outputs carrying passwords or connection strings `sensitive = true`.

## Code Examples
```hcl
# Recipe 16: three VMs from one list variable — the for_each pattern
variable "vm_names" {
  type    = list(string)
  default = ["dev", "qa", "prod"]
}
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = toset(var.vm_names)
  name     = "${each.key}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.region
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  disable_password_authentication = true
}
```
- **What it demonstrates**: one block cloning per list element — clarity/brevity, consistency across instances, and scalability (add/remove a VM by editing the list; plan detects the delta).

```hcl
# Recipe 18: adopting an unmanaged resource
terraform import azurerm_storage_account.legacy \
  /subscriptions/<subscriptionId>/resourceGroups/legacy-rg/providers/Microsoft.Storage/storageAccounts/legacytfstate
```
- **What it demonstrates**: the import workflow — the HCL block must already match real attributes, the full provider resource ID is the import argument, and afterwards `terraform plan` shows ownership (then safe edits like adding `tags = { ManagedBy = "Terraform" }`).

Also illustrative: cross-repo output consumption via `data "terraform_remote_state"` (backend `azurerm`, then `data.terraform_remote_state.web_stack.outputs.web_ip`) — the loose-coupling pattern for separate repositories/workspaces.

## Reference Tables
Table 3.1 — Variable precedence (lowest to highest): default in variables.tf → `*.tfvars` files → `TF_VAR_*` env vars → CLI `-var` flags → Terraform Cloud workspace variable. Env vars are the perfect home for secrets since they never hit source control.

Table 3.2 — Output retrieval cheat sheet:

| Situation | Command / location |
|---|---|
| Immediately after apply | printed automatically, no command |
| Human, later | `terraform output web_ip` |
| Script / CI raw string | `terraform output -raw web_ip` |
| Another module, same repo | `module.web.web_ip` |
| Separate repo / workspace | `data.terraform_remote_state.<name>.outputs.web_ip` |
| Terraform Cloud UI (Enterprise) | Workspaces → workspace → Outputs tab |

Table 3.3 — Common drift causes and cures:

| Cause | Example | Prevention or cure |
|---|---|---|
| Emergency portal tweak | VM SKU upgraded in portal | Import resource or reapply to restore desired state |
| Out-of-band automation | Script creates a subnet | Bring script under Terraform or import |
| Policy / autoscaling events | Auto-scaler adds instances | Design for elasticity; use `ignore_changes` |
| Manual state file edits | JSON block deleted by hand | Never hand-edit; `terraform state rm`/`mv` |

Table 3.4 — Drift command toolkit: `terraform plan` (red output often signals drift), `plan -refresh-only` (show state-only updates, no proposals), `apply -refresh-only -auto-approve` (reconcile benign drift without resource changes), `terraform import <ADDR> <ID>`, `terraform state rm`/`mv`.

## Worked Example
**Chef's Special: conquering state drift (VM + attached data disk).**
1. *Appetizer — baseline*: variables include `disk_size_gb` (number, default 32); main.tf builds resource group, VNet/subnet, NIC, SSH-key-only Linux VM, an `azurerm_managed_disk` (Premium_LRS, Empty, 32 GB), and an `azurerm_virtual_machine_data_disk_attachment` (LUN 10, caching None), plus a `data_disk_uri` output. `terraform apply -auto-approve` with `dev.auto.tfvars` holding the public key.
2. *Main course — drift on purpose*: in the Azure portal, resize `chef-drift-disk` from 32 GB to 64 GB and add tag `PortalEdit = true`. State still says 32 GB; cloud says 64 GB — configuration drift.
3. *Dessert — detect and reconcile*: `terraform plan` reports the mismatch (desired 32 GB vs actual 64 GB). Choose: **Option A** enforce — `terraform apply -auto-approve` resizes back to 32 GB; or **Option B** accept — update the variable/code to 64 GB, `terraform plan -refresh-only`, `terraform apply -refresh-only` (state updates only, no resource changes), then a plain `terraform plan` shows no further changes. Clean up with `terraform destroy -auto-approve`.

## Key Takeaways
1. Type your variables and give them descriptions — that is what converts a one-off script into a reusable template other people can configure.
2. Precedence is a ladder: CLI flag beats env var beats tfvars beats default; debug "wrong values" from the top down.
3. Move state to a remote backend as soon as more than one identity can apply — version history and locking come almost free with `terraform init -migrate-state`.
4. Treat the state file like a production database: it holds live IDs and secrets, so restrict access and never commit or hand-edit it.
5. Drift is feedback, not failure: detect it cheaply (nightly `plan -detailed-exitcode`), then consciously enforce OR accept it — never let it linger silently.
6. Prefer `-refresh-only` for attribute drift reconciliation; reserve import for resources Terraform has never managed.
7. Split secrets into dedicated `secret.auto.tfvars`-style files and mark both the variable and any echoed output `sensitive = true`.

## Connects To
- **Ch 2**: formalizes the shallow variable/output/remote-state recipes (7–9) introduced there; assumes its credential environment setup.
- **Ch 4**: promised next — packaging this parameterized logic into versioned, registry-published modules with input validation and tests; the `for_each` and typing patterns here become module input design there.