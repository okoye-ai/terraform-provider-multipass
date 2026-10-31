# Cheatsheet — Terraform Made Easy (Ivy Wang, GCP-focused)

## Decision Rules

**Replicating resources →**
- Identical copies → `count`
- Each differs / individually addressable → `for_each` (map)
- Same *set* of resources re-deployed → module
- Never delete from the middle of a `count` list; convert to `for_each` first.

**Where does this value come from? →**
- Constant across environments → `locals`
- Varies per environment/deployment → variable + `.tfvars` (`-var-file`)
- Sensitive → `TF_VAR_*` env var (never tfvars hardcode, never code)
- Secret data itself → Secret Manager; read via data source
- Already exists in GCP → data source (`data "..."`), not a resource block

**Resource ordering →**
- Can I reference an attribute of the prerequisite? → implicit dependency (use `self_link` / `name`) — always prefer
- Terraform can't see the order? → `depends_on = [resource]`
- Cross-module? → child `output` → parent input variable

**Secrets in state? → assume yes.** Secure state like a credential store: remote backend + encryption + IAM + locking + versioning + audit.

**Applying to shared/production infra →** `plan -out=plan.out` → review → `apply "plan.out"`; never re-generate the plan silently, never `--auto-approve` locally for destructive ops.

**Which test layer? →** as early as possible: fmt (style) → validate (schema) → plan (diff) → TFLint (pre-commit) → Checkov (PR scan) → Terratest (real infra, CI).

**Destroying anything? →** review plan + team check first; "no undo".
- Stateful resource → `lifecycle { prevent_destroy = true }`
- Stale lock → `terraform force-unlock LOCK_ID` only when certain.

**Encryption →** GMEK by default; CMEK (KMS) when compliance needs your key lifecycle.

## Built-in Command Sequence
```
terraform fmt          # style
terraform validate     # syntax/schema (no remote calls)
terraform init         # backend + plugins + modules + state; re-run after backend/module changes
terraform plan -out=plan.out
terraform apply "plan.out"        # or terraform apply (confirm: yes) / --auto-approve in CI
terraform destroy      # review first; no undo
terraform graph -type=plan | dot -Tpng > graph.png   # dependency X-ray
```

## Plan Symbols
| Symbol | Action |
|---|---|
| `+` | create |
| `~` | modify |
| `-` | destroy |
| `Plan: N added, N changed, N destroyed` | the summary to read before confirming |

## Backend Migration (local → GCS)
1. Add `backend "gcs" { bucket = ...; prefix = "terraform/state" }`
2. `terraform init` → answer `yes` to migrate
3. `terraform init` again → no prompt = success
4. Manual fallback: `terraform state pull > terraform.tfstate` → `terraform state push`

## State Bucket Hardening (GCS)
`versioning { enabled = true }` · `force_destroy = false` · `public_access_prevention = "enforced"` · `uniform_bucket_level_access = true` · dedicated bucket.

## Variable Block Checklist
- [ ] `description` (1–2 sentences)
- [ ] `type` (string/number/bool; list/set/map/object/tuple; any)
- [ ] `validation { condition / error_message }` for constrained values
- [ ] `sensitive = true` for credentials
- [ ] `nullable = false` when a value must be present
- [ ] Reserved names avoided: source, version, providers, count, for_each, lifecycle, depends_on, locals

## Undeclared Variable Behavior
| Where set | Terraform response |
|---|---|
| Env var (`TF_VAR_*`) | silent — nothing warns you |
| `.tfvars` | warning (typo catcher) |
| CLI `-var` | error |

## Cloud SQL Production Recipe
`authorized_networks` restricted → `availability_type` ZONAL/REGIONAL → maintenance window → labels → `prevent_destroy` → backups (`start_time` + `retention_count`) → `roles/cloudsql.admin` IAM member → alert policy (CPU > 0.8 for 60s → email channel).

## Secret Manager Split
Terraform: `google_secret_manager_secret` (identity, labels, replication) + `_secret_version` (data). Consumers: `data "google_secret_manager_secret_version"` with `version = "latest"`. Death dates: `ttl = "24h"` (relative) or `expire_time = "..."` (absolute). CMEK = KMS IAM member for the service agent + `customer_managed_encryption` in replication.

## Terraform-Tests-In-CI Skeleton
```yaml
init → validate → plan → apply
secrets: TF_VAR_my_secret ← ${{ secrets.MY_SECRET }}
apply gated to main branch (GitLab only:) or manual input (Jenkins)
archive: plan.out / terraform.tfstate
```

## Terratest Invariants
```go
defer terraform.Destroy(t, opts)   // never leak infra
terraform.InitAndApply(t, opts)
assert.NotEmpty(t, terraform.Output(t, opts, "<output>"))
```

## Tells & Smells
- `password = "..."` literal in code → state + VCS exposure; move to TF_VAR_ or Secret Manager.
- Same attribute defined in provider block AND resource → drift waiting to happen.
- Resource without labels → unmanageable at scale.
- `auto_create_subnetworks = true` where you need custom subnets/IPs → switch to custom VPC.
- Backup `enabled = true` with no `start_time`/`retention_count` → backups you can't rely on.
- "Plan: 1 to add" where you expected a modify → address/id changed; the resource will be replaced — stop and review before confirming.
- Missing `access_config {}` block on network_interface → no public IP.
- HTTP LB disabled in `addons_config` → Ingress silently won't work on GKE.