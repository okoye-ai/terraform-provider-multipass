# Chapter 14: Troubleshooting Terraform Errors

## Core Idea
Treat Terraform error messages as guides, not barriers: each error category (auth, syntax, cycle, conflict, lock) follows a recognizable pattern with a standard diagnosis-and-fix path, and failed applies are recovered by reconciling state (import) or replacing broken resources (taint) rather than starting over.

## Frameworks Introduced
- **Error-pattern recognition**: classify errors by keyword.
  - When to use: any failed plan/apply, before searching online.
  - How: auth errors mention authorization/credentials/tokens; syntax errors point at file + line + column and a missing argument; `Error: Cycle:` lists the locked resources in order; `already exists` / `duplicate resource` means import-or-rename; `Error acquiring the state lock` means another run is live or a lock was left behind.
- **Failed-apply recovery ladder**: ordered set of recovery techniques.
  - When to use: an apply that halted midway leaving partially created infrastructure.
  - How: read logs to identify what succeeded → correct config → `terraform import` existing-but-unmanaged resources → `terraform taint` resources that exist but are broken (destroy+recreate) → manual state editing only as last resort.
- **Structured auth debug sequence**: verify credentials → check RBAC role/permissions → test outside Terraform (`az login`, `aws sts get-caller-identity`, `gcloud auth list`) → automate rotation via Key Vault/Vault.
- **Drift direction-of-truth decision**: for a detected drift, either accept the external change (update `.tf` or import it) or reject it (re-apply to overwrite); taint when an immutable field was changed externally.
- **TF_LOG debugging toolkit**: `TF_LOG` levels (INFO → DEBUG → TRACE) plus `TF_LOG_PATH`, `terraform console` for expression checks, and `terraform plan -debug` for dependency-chain diagnostics.

## Key Concepts
- **`terraform validate`**: static configuration check that catches type mismatches and missing arguments before plan; e.g. `default = "3"` on a `number` variable fails with "number required".
- **`terraform fmt`**: normalizes `.tf` formatting so structural errors (unbalanced braces) surface early; should gate CI merges.
- **Dependency cycle**: circular reference in the resource graph where neither resource can be created first; fixed by removing backward references, using data sources, or splitting modules.
- **`terraform import`**: brings an existing resource into state without recreation — the preferred fix when apply fails with "already exists".
- **`terraform taint`**: marks a state-tracked resource as broken so the next apply destroys and recreates it; use sparingly, never on large dependency trees without a plan.
- **State lock**: backend safeguard allowing only one state-modifying process; local backend lock is `.terraform.tfstate.lock.info`, remote backends (TFC, S3+DynamoDB, Azure Storage) require console/`terraform force-unlock <lock-id>`.
- **`TF_LOG=DEBUG|TRACE` + `TF_LOG_PATH`**: provider request/response tracing; always disable afterward to avoid huge logs and secret leakage.
- **`terraform console`**: interactive REPL to test variable values, interpolations, and state lookups without a full plan.
- **Saved plan apply**: `terraform plan -out=plan.tfplan` then `terraform apply plan.tfplan` so executed changes match what was reviewed.

## Recipes in this chapter
- **Recipe 79: Fixing a provider authentication error** — deploy with deliberately fake ARM credentials to see the auth failure, then move to `ARM_*` environment variables (`$env:ARM_SUBSCRIPTION_ID`, etc.) and an empty provider block; never hardcode secrets.
- **Recipe 80: Resolving a syntax error** — two planted faults (missing closing brace, string `default` on a number variable) caught by `terraform fmt -recursive` + `terraform validate`; note that one syntax issue triggers cascading secondary errors, so read the FIRST error.
- **Recipe 81: Breaking a dependency cycle** — `random_integer` with `keepers` referencing the storage account that names itself with the random value produces `Error: Cycle: random_integer.rand, azurerm_storage_account.st`; delete the backward reference.
- **Recipe 82: Recovering from a failed apply** — duplicate storage-account names cause a mid-apply failure; fix by renaming, then `terraform import azurerm_storage_account.st2 <full-resource-id>` for unmanaged resources or `terraform taint` for broken ones.
- **Recipe 83: Handling state lock issues** — trigger the lock by running two applies in parallel terminals; release locally by deleting `.terraform.tfstate.lock.info` only after confirming no other run is live, or `terraform force-unlock` remotely.
- **Recipe 84: Using debug logs** — PowerShell `$env:TF_LOG` / `$env:TF_LOG_PATH` session, then navigate the log by sections: plugin loading, graph walk/eval, HTTP request-retry lines, error/panic context; end by removing `TF_LOG*` env vars.

## Anti-patterns
- **Skimming errors and jumping to online search**: Terraform diagnostics already name the file, line, and cause — reading them first is the fastest fix.
- **Hardcoding credentials in provider blocks**: the Recipe 79 faulty config; use env vars, sensitive variables, or a secret manager.
- **Overusing `depends_on`**: artificial dependencies manufacture cycles that implicit graph references would never create.
- **Applying everything at once in large projects**: small incremental applies and per-environment state limit blast radius.
- **Breaking a lock while another operation runs**: risks state corruption and inconsistent infrastructure — always verify no other user/job is active.
- **Leaving TF_LOG enabled in production**: large log files and potential exposure of sensitive request metadata (scrub logs before sharing).
- **Recreating instead of importing**: if the resource exists (partially created or externally managed), import reconciles state without destruction.
- **Tainting large dependency trees without a plan**: forces broad destroy/recreate cascades.

## Code Examples
```terraform
provider "azurerm" {
  features {}
}
# Credentials come from environment variables instead:
# ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
```
- **What it demonstrates**: the corrected provider block after moving auth out of code (Recipe 79's fix path).

```bash
# Recovery sequence for a failed apply (Recipe 82)
terraform import azurerm_storage_account.st2 \
  /subscriptions/<sub_id>/resourceGroups/failedapply-rg/providers/Microsoft.Storage/storageAccounts/uniquestorageacct8888
# ...or, for a resource in state that is broken/incomplete:
terraform taint azurerm_storage_account.st2
terraform apply

# Debug session (Recipe 84)
$env:TF_LOG="DEBUG"
$env:TF_LOG_PATH="terraform-debug.log"
terraform apply
Remove-Item Env:\TF_LOG -ErrorAction SilentlyContinue   # disable after use
```
- **What it demonstrates**: import vs taint decision plus a properly bounded PowerShell logging session with cleanup.

## Reference Tables
| Error signature | Meaning | Standard fix |
|---|---|---|
| `Error building AzureRM Client: Error obtaining Authorization Token` | Missing/expired credentials | Set `ARM_*` env vars; test with `az account show` |
| `Insufficient privileges to complete the operation` | SPN/IAM lacks RBAC role (e.g. Network Contributor for VNets) | Grant least-privilege role at target scope |
| `Incorrect attribute value type ... number required` | `"3"` quoted string on number variable | Fix type; run `validate` before plan |
| `Error: Cycle: a, b` | Circular reference | Remove backward reference; data source; split modules |
| `A resource with the name "X" already exists` | Name conflict / externally exists | Rename with `random_string` suffix, or `terraform import` |
| `Error acquiring the state lock` | Concurrent run or stale lock | Wait; else remove local `.lock.info` or `force-unlock` |
| `UnauthorizedOperation:` (AWS) | IAM user lacks permission | Fix IAM policy; verify `aws sts get-caller-identity` |

TF_LOG levels: **INFO** (milestones, light audit) → **DEBUG** (recommended start; provider requests/responses) → **TRACE** (very verbose; provider-maintainer use, short runs only).

## Worked Example
Chef's Special — three compact real-world scenarios mapping error messages to structured fixes:
1. **Appetizer: Credential misconfiguration** — errors like `invalid_client`, `unauthorized`, `caller does not have permission`. Resolution: validate outside Terraform (`az account show` / `aws sts get-caller-identity` / `gcloud auth list`), supply credentials via `$env:` PowerShell variables, confirm scope/roles, retry `terraform plan`. Best practice: separate least-privilege identity per environment (dev/test/prod), secrets in a manager, not local files.
2. **Main course: Resource naming conflict** — `already exists` or `conflict` on globally unique resources (storage accounts, DNS zones). Resolution: `terraform state list` to check state → if unmanaged, `terraform import azurerm_storage_account.st_existing <resource-id>` → if it must be new, rename with suffix/`random_string` → re-plan. Best practice: naming conventions combining environment + region + application codes.
3. **Dessert: State drift and correction** — plan shows unexpected changes/replacements from external edits. Resolution: inspect drifted attributes in the plan → choose direction of truth (accept: update `.tf` or import / reject: apply to overwrite) → for externally changed immutable fields, `terraform taint <resource>` + apply → confirm with a clean `terraform plan`. Best practice: forbid manual production edits, alert on drift, keep Terraform the trusted source of truth.

## Key Takeaways
1. Read the first error message fully — file, line, column, and hint — because one root cause typically cascades into many secondary errors.
2. Diagnose auth errors outside Terraform first with cloud CLIs before touching configuration; then use env variables or OIDC, never hardcoded credentials.
3. Always gate code with `terraform fmt` and `terraform validate` locally and in CI so syntax errors never reach plan.
4. On partial apply failures, reconcile state rather than rebuild: import what exists unmanaged, taint only what is genuinely broken, and edit state only as a last resort.
5. Apply from a saved plan file and use `-parallelism` / `-lock-timeout` tuning plus per-environment state to control blast radius.
6. Never remove a state lock without confirming no other run is active; in teams, prefer remote state with locking and scheduled change windows.
7. Use `TF_LOG=DEBUG` with `TF_LOG_PATH` for reproduction, keep a minimal config to reproduce, and always disable logging afterward.
8. Maintain runbooks with exact import/taint/unlock/backup-restore commands so responders act fast under pressure.

## Connects To
- **Ch 13**: drift detection and state-locking practices introduced there are the failure scenarios this chapter teaches you to fix; version pinning (Recipe 77) is also the fix for many "works on my machine" recovery issues.
- **Ch 8**: `terraform import`/state reconciliation techniques extend the external-data and import concepts.
- **Ch 15**: multi-cloud configurations multiply provider-auth error surface — the authentication debugging sequence applies per provider (Azure/GCP/AWS).