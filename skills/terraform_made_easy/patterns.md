# Patterns

## Pattern: Plan-file Apply Loop
**When to use**: any change to shared/production infrastructure where the reviewed plan must be exactly what gets applied.
**How**: `terraform plan -out=plan.out` → review → `terraform apply "plan.out"`. Apply executes the planned actions verbatim without recomputing (infra changes between plan and apply won't produce a different apply).
**Trade-offs**: plan files become stale quickly; single-use; keep them out of version control.

## Pattern: Three Ways to Scale a Resource
**When to use**: creating multiple instances of anything.
**How**:
- `count = length(list)` + `count.index` — N near-identical resources;
- `for_each = map/set` + `each.value` — individually addressable, differing resources (map of object configs in tfvars);
- modules — repeat a whole *unit* of resources with different parameters per call.
**Trade-offs**: `count` reindexes resources when the list shrinks/moves (destructures); `for_each` keyed by map key survives changes; modules cost a directory + contract but pay off in reuse.

## Pattern: State Bucket Hardening
**When to use**: creating the bucket that holds Terraform state.
**How**: `versioning { enabled = true }` (every state save preserved as a version for rollback), `force_destroy = false` (can't delete with contents), `public_access_prevention = "enforced"`, `uniform_bucket_level_access = true`, dedicated bucket per purpose.
**Trade-offs**: versioning retains storage costs; set lifecycle rules if needed.

## Pattern: Backend Migration (local → remote)
**When to use**: infrastructure has outgrown single-machine local state (team, CI, security).
**How**: add `backend "gcs" { bucket; prefix }` → `terraform init` (prompts to migrate; answer yes) → re-run `terraform init` to verify no re-prompt. Manual path: `terraform state pull > terraform.tfstate` → `terraform state push`. Prereqs: IAM access to bucket; decrypt custom-key-encrypted local state first.
**Trade-offs**: brief coordination across the team; do it once, early.

## Pattern: Local-driven Repeated Configs
**When to use**: one config block repeated with small variations (firewall rule sets, multiple similar subnets).
**How**: declare the table in `locals { firewall_rules = [ {...}, ... ] }`, then `for_each` over it, using `dynamic "allow" { for_each = local.firewall_rules; content { ... } }` to expand nested blocks.
**Trade-offs**: adds one indirection layer; pays for itself on the second reuse.

## Pattern: Module as Contract
**When to use**: any reusable unit (compute instance, VPC, storage bucket).
**How**: standard structure `main.tf` (resources) + `variables.tf` (typed, described inputs) + `outputs.tf` (stable surface: `name`, `self_link`, `url`) + `providers.tf` + `README.md` documenting inputs/outputs in a table. Nested modules under `modules/`, worked usage under `examples/`. Module-to-module dependency = child outputs → parent inputs.
**Trade-offs**: boilerplate per module; standard structure enables registry indexing and docs tooling.

## Pattern: Parameterized Environment via tfvars
**When to use**: dev/staging/prod from one codebase.
**How**: keep variables typed/described in `variables.tf`; per-environment values in `dev.tfvars` / `staging.tfvars` / `prod.tfvars` (or `environments/{dev,staging,prod}/` dirs); apply with `-var-file="prod.tfvars"`. Sensitive values via `TF_VAR_*` env vars instead.
**Trade-offs**: values live outside the code — don't commit sensitive tfvars.

## Pattern: Secret Split — Terraform as Plumber, Secret Manager as Vault
**When to use**: any credential, API key, or password in the config.
**How**: Terraform creates `google_secret_manager_secret` (identity/labels/replication) and versions; data values flow in via sensitive variable or are created directly; consumers read via `data "google_secret_manager_secret_version"` with `version = "latest"`. Terraform never stores or rotates secret data itself.
**Trade-offs**: one extra service; buys rotation, audit logs, and access control Terraform can't provide.

## Pattern: Hardened Database Instance
**When to use**: any Cloud SQL or stateful service.
**How**: parameterize all attributes; restrict `ip_configuration { authorized_networks }`; set `availability_type` (ZONAL/REGIONAL); maintenance window; labels; `lifecycle { prevent_destroy = true }`; `backup_configuration` with `start_time` + `retention_count`; project-level IAM role for admins; monitoring alert policy (threshold + duration + notification channel).
**Trade-offs**: REGIONAL availability costs more; both are defaults in the book's production posture.

## Pattern: Resilience Stack (backup + failover)
**When to use**: services with availability guarantees.
**How**: snapshots (`google_compute_snapshot` with timestamped names), versioned backup bucket with lifecycle rules (e.g. delete at 30 days), Cloud SQL automated backups + PITR, DNS failover: managed zone + primary/secondary A records from instance IPs + health check on `/healthz`, traffic auto-routes to the healthy region.
**Trade-offs**: cross-region costs; health-check tuning.

## Pattern: Testing Ladder
**When to use**: any Terraform repo; adopt in order.
**How**: `fmt` → `validate` → `plan` → TFLint as pre-commit hook → Checkov in PR CI (built-in + custom Python checks) → Terratest (real infra: `defer Destroy` + `InitAndApply` + assert outputs) or pytest over `terraform output -json`.
**Trade-offs**: Terratest is slow and bills real infra — reserve for modules and E2E, run in CI.

## Pattern: CI/CD Stage Skeleton
**When to use**: automating Terraform in GitHub Actions / GitLab CI / Jenkins.
**How**: stages validate → plan → apply. Backend parameterized with `-backend-config=` flags; secrets via `TF_VAR_<name>` ← platform secret store (e.g. `${{ secrets.MY_SECRET }}`); apply restricted to `main` (GitLab `only:`) or behind a manual approval input (Jenkins); archive `plan.out`/state as artifacts.
**Trade-offs**: `-auto-approve` in CI assumes review happened earlier in the pipeline — keep the plan artifact or approval step visible.