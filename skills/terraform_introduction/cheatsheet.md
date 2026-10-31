# Cheatsheet — Introduction to Terraform (Bobby Iliev)

## The lifecycle loop

| Command | When | Notes |
|---|---|---|
| `terraform init` | after any backend/provider change | downloads plugins, sets up state backend |
| `terraform validate` | before every plan | catches config/variable errors |
| `terraform plan` | before every apply | review the diff; `-out=tfplan` in CI |
| `terraform apply` | to change the world | CI uses `-auto-approve` (with pre-reviewed plan) |
| `terraform destroy` | teardown everything | double-check what's still needed |
| `terraform fmt` / `terraform -v` | hygiene / install check | fmt before commit |

## Decision rules

- **Team uses this state?** → remote backend with locking (S3/GCS/Terraform Cloud), always. Local state only for solo experiments.
- **State file needs a fix?** → never edit it; use Terraform commands (`import`, `state list/show`, re-apply). Corruption prevention = no manual edits + remote locking + careful `destroy`.
- **Resource exists outside Terraform?** → write its config block, then `terraform import <address> <id>`.
- **Resource can't be imported?** → transition-to-new-resource first; recreate (delete + create) only when identity is immovable (e.g. fixed IP) — recreate risks downtime/data loss.
- **Secret needed in config?** → input variable with runtime value, or Vault/AWS Secrets Manager/Azure Key Vault. **Never** plaintext in `.tf` or state.
- **Same code, different environments?** → `.tfvars` per environment + `-var-file`; size/branch inside config with conditionals (`environment == "production" ? t3.large : t3.micro`).
- **Value repeated in config?** → `locals`. Resource set reused → module. Repeated nested blocks → `dynamic` block.
- **Need a UI, shared state, access control, private registry, or Sentinel policies?** → Terraform Cloud. Otherwise open-source CLI is enough.
- **Terraform acting strangely?** → `TF_LOG=DEBUG` (+`TF_LOG_PATH`), then validate → plan → comment-to-isolate → `terraform show` → `terraform console`.

## Thresholds & defaults to remember

- Backend lock = automatic on most remote backends; local locking only works on a shared filesystem.
- Import needs the resource's config block to exist *before* importing.
- Module `version` = Git tag pin (e.g. `1.0.0`); remote module sources use `//` before the subpath (`repo//modules/my-module`).
- Resource type convention: `<provider>_<resource>` (`aws_instance`, `digitalocean_droplet`), addressed as `type.name`.
- Provisioners run after creation: `local-exec` = on your machine (wire `ipv4_address` into the Ansible inventory), `remote-exec` = on the new host.
- Sentinel inspects `tfplan` — failed policy blocks the run before any apply.

## Common errors → fixes

| Symptom | Fix |
|---|---|
| Provider not initialized | `terraform init` |
| Invalid resource attributes | check the resource type's docs |
| Conflicts with existing infrastructure | `terraform import` it, or delete the conflict if unneeded |
| Config validity unknown | `terraform validate` |
| Unclear variable value | `terraform console` → `> var.my_variable` |
| Suspicious world state | `terraform show` (or `show -json > state.json` for export) |

## One-line mental models

- Terraform = declarative genie: say what, not how.
- State = Terraform's only map of reality — guard it like production data.
- Modules = functions for infrastructure; providers = the API bridge.
- Terraform provisions; Ansible configures; Vault keeps secrets; Sentinel enforces the rules.