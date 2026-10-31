# Chapter 5: Terraform State Management

## Core Idea
The state file is Terraform's source of truth mapping code to live resources; keep exactly one authoritative copy (remote backend with locking), correct drift through refresh → plan → deliberate reconciliation, and move resources with `state mv` before refactoring addresses so nothing gets destroyed and recreated.

## Frameworks Introduced
- **Local vs Remote State decision rule**
  - Local (`terraform.tfstate` in project folder): solo experiments and quick PoCs only
  - Remote (S3 / Azure Blob / GCS / Terraform Cloud): any team, any duration — locking prevents concurrent apply collisions; encryption/versioning/replication protect state; `terraform init` migrates local state on confirmation
- **Drift Reconciliation Loop**: the four-step lifecycle
  1. **Initiation** — apply stores desired state
  2. **Drift occurrence** — outside-Terraform change (portal edit, auto-scaling event, bug)
  3. **Detection** — next plan/apply compares desired vs state vs actual
  4. **Reconciliation** — `terraform refresh` (sync state with reality) → `terraform plan` (show the delta) → then choose: **apply to make reality match code**, or **revert the external change** then refresh
- **State Migration Playbook**: when to move state and how
  - Refactoring configs (resources between modules) → `terraform state mv old.addr new.addr` + update code before next apply
  - Adopting or switching remote backends → edit `backend` block, `terraform init`, confirm copy prompt ("Enter a value: yes")
  - Always back up state before any migration; rehearse in non-production

## Key Concepts
- **State file (`terraform.tfstate`)**: updated after every apply; contains resource IDs, metadata, and possibly secrets — handle as sensitive data
- **State manipulation subcommands**: `terraform state rm` (untrack a resource deleted outside Terraform — avoids unwanted recreation), `terraform state mv` (rename/move without destroy+recreate)
- **State locking**: remote backends lock during operations to serialize concurrent runs; a held lock yields state lock errors
- **`terraform force-unlock LOCK_ID`**: manual unlock for stale locks — only after verifying no operation is truly running, or state corruption follows
- **Refresh semantics**: `terraform refresh` reads real infrastructure and updates state; the next `plan` then shows the delta to be reconciled

## Code Examples
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "mystatestorage"
    container_name       = "tfstate"
    key                  = "myproj.tfstate"
  }
}
```
```bash
terraform state rm azurerm_virtual_machine.example
terraform state mv module.old.azurerm_virtual_machine.example \
                   azurerm_virtual_machine.example
terraform init -backend-config="new-backend.hcl"   # prompts to copy state
```
- **What it demonstrates**: the one-place state lives (backend block) and the two emergency-address operations

## Reference Tables
| Situation | Command | Effect |
|---|---|---|
| Resource deleted in cloud console | `terraform state rm <addr>` | Terraform stops tracking it; no forced recreation |
| Rename/move between modules (refactor) | `terraform state mv <old> <new>` | Address updated in place; resource survives |
| Suspected drift | `terraform refresh` then `terraform plan` | State syncs to reality; delta becomes visible |
| Drift is desired/expected (auto-scaling) | update code or accept, then `terraform apply` | Code and reality converge on purpose |
| Drift is unauthorized | revert external change, then `terraform refresh` | Reality returns to code's model |
| Stale state lock | `terraform force-unlock LOCK_ID` | Unlocks — *only after confirming nothing is running* |
| Backend change | new `backend` block + `terraform init` | State copied to new backend on confirm |

## Worked Example
Local → Azure remote state migration:
1. Add the `backend "azurerm"` block above to `main.tf`.
2. Run `terraform init`; Terraform detects pre-existing local state and prompts:
   `Do you want to copy existing state to the new backend? ... Enter a value: yes`
3. Answer "yes" — state migrates to the storage container; every subsequent plan/apply reads and writes the shared blob.
4. From now on, no teammate holds a divergent local copy; locking serializes concurrent runs.

## Anti-patterns
- **Team collaboration on local state**: divergent copies, conflicts, unencrypted secrets on every laptop, unrecoverable if the disk dies
- **Habitual manual state editing**: corruption risk far exceeds the convenience; reserve `state rm`/`state mv` for genuine emergencies, back up first
- **Force-unlocking without verification**: if another operation actually holds the lock, unlocking invites corruption
- **Refactoring addresses in code without `state mv`**: Terraform sees a delete + create; the resource data (and any in-place state) is destroyed for nothing
- **Ignoring drift**: undetected drift yields unpredictable plans, broken dependencies, and unmanaged security/compliance exposure

## Key Takeaways
1. State is sensitive — it can contain credentials; secure and encrypt wherever it lives
2. Remote backend + locking is the default for anything shared; local state is a PoC pattern
3. The reconciliation decision is always: make reality match code (apply) or make code match reality (revert + refresh) — decide *which* before running
4. Move addresses with `state mv` before touching code addresses in a refactor; update code to match, then plan
5. Back up state before every manipulation or migration; rehearse backend switches outside production
6. Auto-scaling and other "expected drift" is usually a signal to codify it, not to fight it

## Connects To
- **Ch 4**: module refactoring is the top cause of needing `state mv`
- **Ch 9**: drift detection feeds troubleshooting and testing workflows
- **Ch 2**: the apply command introduced there updates the state described here