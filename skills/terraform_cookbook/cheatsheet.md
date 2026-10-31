# Cheatsheet — Terraform Cookbook (Husain)

## Error → Fix decision table (Ch 14)

| You see | It usually means | Do this |
|---|---|---|
| `Error acquiring the state lock` | Another run is active, or a crashed run left the lock | Verify no run is active → release per backend (Cloud UI unlock; delete the DynamoDB entry; delete local `.lock.info`) |
| `A resource ... already exists` | Resource pre-dates Terraform | `terraform import` it (or rename yours uniquely) |
| `Cycle: a, b, c` | Circular reference | Break with a data source, split modules, or drop the artificial `depends_on` |
| Authorization / token errors | Creds expired, missing, or over/under-scoped | Verify env/creds → check IAM role scope → test `az login` / `aws sts get-caller-identity` outside Terraform |
| `Missing required argument` / type errors | Syntax/typing slip | Read the file:line:col Terraform gives you; `terraform validate` before plan |
| Half-created stack after failed apply | Quota, naming conflict, transient API fault | Re-apply; import orphaned pieces; `taint` broken ones — state edit only as a last resort |

## Drift handler (Ch 3, 13)
Plan shows a diff → decide who is right:
- **Config is correct** → `terraform apply` (enforce desired state back onto reality)
- **Manual change is wanted** → `terraform plan -refresh-only` → `terraform apply -refresh-only` (adopt into state only, no infra changes)
- Recurring drift → nightly `terraform plan -detailed-exitcode` in CI; nonzero exit = drift alarm

## Failed-apply recovery ladder (Ch 14)
1. Read the apply log; note what succeeded vs failed
2. Fix root cause (quota / name conflict / transient) and re-apply
3. `terraform import` anything created outside state
4. `terraform taint <resource>` to rebuild a broken resource (sparingly)
5. Manual state edit — last resort, backup state first
Habits: apply from a saved plan (`terraform plan -out=tfplan`), use `-lock-timeout`, `create_before_destroy` for replacements, scope state per environment to limit blast radius.

## Debug logging picker (Ch 14)
- Overview → `TF_LOG=INFO`
- Auth/API/config hunting → `TF_LOG=DEBUG`
- Provider bugs, huge volumes → `TF_LOG=TRACE` (last resort)
- Always set `TF_LOG_PATH` and turn logging OFF in production afterwards; use `terraform console` to test expressions interactively.

## Sentinel enforcement level picker (Ch 16)
- **Advisory** — nice-to-have rules; warns, run proceeds
- **Soft-mandatory** — company policy with an escape hatch; a privileged user can override
- **Hard-mandatory** — compliance red lines; halts the run, no override

## Policy tool choice (Ch 13, 16)
- Terraform Cloud/Enterprise → **Sentinel** (native, plan/state/config aware)
- Vanilla CI or multi-platform → **OPA/Rego** in the pipeline

## Secrets ladder (Ch 13, 17)
1. Never in code, never in committed tfvars
2. Static creds → `terraform.tfvars` locally + `sensitive = true` (never Git)
3. Production → fetch from Azure Key Vault / Vault at apply time; rotate automatically
4. Sensitive outputs masked with `sensitive = true`

## Workspace sizing rule (Ch 16)
**configurations × environments = workspaces.** One workspace per environment per component; split state-heavy resources (DB/storage) from compute; align workspace names with owning teams (`networking-*`, `app-*`).

## Compute pattern contract (Ch 5)
Every VM needs five things: image · size · network · credentials (SSH key, not password) · boot script (cloud-init / custom_data / user_data) — the attribute names differ per provider.

## Naming & uniqueness (Ch 14, 17)
Globally unique services (storage accounts, DNS) need a suffix: `tfstorage-${random_string.suffix.result}`; tag everything (`environment`, `cost_center`, `application_id`) so partial builds can be cleaned and audited.

## Scale-out choice (Ch 9, 10)
- Unknown future count, metric-driven → autoscaling groups (ASG/VMSS/MIG) + CloudWatch/monitor alarms
- A known set of named resources → `for_each`
- Identical clones, list-ordered → `count`
- Optional component → `count = var.enabled ? 1 : 0`
- Zero-downtime app update → blue-green (duplicate env + traffic switch) or rolling replaces-in-batches

## Big-stack speed knobs (Ch 9)
`-parallelism=N` (raise concurrency) · `-target=module.x` (scoped edits only) · cache provider plugins in CI · split slow/state-heavy resources into separate state.

## Git hygiene one-liner (Ch 3)
Ignore `.terraform/`, `*.tfstate*`, secret-bearing `*.tfvars`, `crash.log`, `override.tf*`. Commit `.terraform.lock.hcl` if your team standardizes reproducible provider versions — either policy is fine, drifting between them is not.

## Lifecycle order rules (Ch 3, 14)
Import before destroy · refresh before big plans · plan before apply (always read it) · policy checks before apply · destroy explicitly when done with lab stacks to stop billing.