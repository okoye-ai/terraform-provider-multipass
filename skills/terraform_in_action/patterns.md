# Patterns & Techniques — Terraform in Action

## 1. Globally-Unique Namespace Right-Padding
**When to use**: any resource needing global (cross-account) uniqueness — S3 bucket-ish names, Azure storage accounts. (Ch 5–6, 12)
**How**: `random_string` (24, no specials) + `locals { namespace = substr(join("-", [var.namespace, random_string.rand.result]), 0, 24) }`
**Trade-offs**: adds a dependency on the Random provider before everything else.

## 2. Sort by Group, Then by Size
**When to use**: organizing any single-file (flat) Terraform codebase. (Ch 5, 6, 10)
**How**: group related resources first, sort within each group by dependency count (fewer deps = higher in file), order groups by increasing size overall.
**Trade-offs**: subjective; a few hundred lines per file is the practical ceiling.

## 3. Build the S3 Remote Backend Module
**When to use**: team state storage. (Ch 6)
**How**: DynamoDB table (locking, PAY_PER_REQUEST) + S3 bucket (versioned, KMS-SSE, public-access-block) + least-privileged IAM role assuming accounts assume + resource-group tag housekeeping; outputs the four-piece `config` object (bucket, region, role_arn, dynamodb_table).
**Trade-offs**: none at this cost; one per team partitions state.

## 4. Workspace-Per-Environment
**When to use**: same configuration across dev/int/prod. (Ch 6)
**How**: `terraform workspace new dev` + `terraform apply -var-file=./environments/dev.tfvars`; name resources with `terraform.workspace`. Backend keys land under `env:/<workspace>/...`.
**Trade-offs**: backend config can't be variable-ized; state must not diverge structurally.

## 5. Two-Stage Deployment (Static vs Dynamic)
**When to use**: app code changes far more often than infrastructure. (Ch 7–8, 9)
**How**: Terraform provisions the base/foundation stage; stage 2 is a CI/CD pipeline (Cloud Build, ch7), Terraform jobs (Nomad, ch8), or Ansible (ch9). Monorepo split: `infrastructure/` + `application/`.
**Trade-offs**: two toolchains to wire; faster, more reliable deploys.

## 6. Feature-Flagged Blue/Green Cutover
**When to use**: zero-traffic-loss releases without lifecycle tricks. (Ch 9)
**How**: shared `base` module (LB, VPC, SG; databases live here) + two ASG modules (green v1.0 / blue v2.0); `var.production = "green"|"blue"` re-points the LB listener. Cutover plan = 2 `~` changes in seconds.
**Trade-offs**: 2× idle capacity (scale idle down to cut cost); blast radius reduced by splitting into 3 workspaces.

## 7. Module Expansion with for_each (Self-Service Platforms)
**When to use**: N instances of a pattern (IAM service accounts, teams, etc.). (Ch 10)
**How**: build a `policy_mapping` map of objects (load policy docs via `{ for path in fileset(path.module, "policies/*.json") : basename(path) => file(path) }`), declare the module once with `for_each = local.policy_mapping`, outputs joined via `join("\n", [for m in module.iam : m.credentials])`.
**Trade-offs**: re-addressing existing resources requires state migration (see pattern 8).

## 8. State Migration: mv vs rm+import
**When to use**: refactoring changes resource addresses. (Ch 10)
**How**: `terraform state list` → `terraform state mv SOURCE 'module.x["key"].RESOURCE'` for survivors; `terraform state rm ADDR` ⇒ `terraform import ADDR ID` then `terraform apply` (config-only attributes import as null) for re-created things. Avoid hand-editing the file.
**Trade-offs**: tedious at scale; verify with a plan showing the expected add/destroy counts.

## 9. Targeted Rotation with taint
**When to use**: rotate access keys (≤90 days) or other time-sensitive resources without a full destroy. (Ch 10)
**How**: `terraform taint <address>` → plan shows `-/+ replace` → apply; `terraform untaint` undoes.

## 10. The Four-Stage Terraform Pipeline (Poor Man's TFE)
**When to use**: automation at team/org scale. (Ch 12)
**How**: Source (GitHub + CodeStar) → Plan (CodeBuild, `hashicorp/terraform:<ver>` image) → Approve (manual Manual action; feature-flagged `for_each = var.auto_apply ? [] : [1]`) → Apply. Inject `backend.tf.json` from a `BACKEND` env var; `CONFIRM_DESTROY=1` queues destroy runs; `TF_IN_AUTOMATION`/`TF_INPUT=0` always.
**Trade-offs**: no remote operations or Sentinel (proprietary); CodeStar auth is a manual console step.

## 11. Dynamic Secrets Wiring
**When to use**: replacing static credentials. (Ch 13)
**How**: Vault (`data "vault_aws_access_credentials"` → AWS provider) or ASM (`data "aws_secretsmanager_secret_version"` → `jsondecode(secret_string)` → locals.creds["username"|"password"]). For apps: pass a `SECRET_ID` env var, fetch at runtime in the app.
**Trade-offs**: all state/log rules still apply; Vault ops burden vs ASM managed simplicity.

## 12. Custom Resources, Three Ways (ranked)
**When to use**: an API/utility Terraform doesn't cover. (Ch 7 App D, 11)
**How**: 1) `shell_script` (Shell provider) with `lifecycle_commands { create/read/update/delete }` — full lifecycle, no Go; 2) a provider in Go against a client SDK (SetId() + Read() side effects, acceptance tests, `.terraformrc` dev_overrides); 3) NEVER: null_resource + local-exec provisioners (logs, plan-time surprises, deprecation risk).

## 13. Secret-Hygiene Checklist
**When to use**: always. (Ch 13)
**How**: env vars for provider config; `sensitive = true` on Terraform variables (redaction only); separate git-ignored `secrets.tfvars` + `-var-file`; no secrets in Lambda env blocks (use SECRET_ID); no trace logs in CI; no plan on fork PRs; skim module source before use.
**Trade-offs**: none — the cheapest risk reduction in the whole book.

## 14. Read-in-Files over Inline String Literals
**When to use**: multi-line JSON/YAML content (policies, user data). (Ch 10, 4)
**How**: read from disk with `file()` / `fileset()` globs, or template them: `templatefile("cloud_config.yaml", var.db_config)` in `data "cloudinit_config"`.