# Patterns

## Attribute-Reference Dependencies
**When to use**: any resource that needs another's attributes.
**How**: reference attributes directly (`location = azurerm_resource_group.rg.location`) instead of repeating literals.
**Trade-offs**: creates implicit dependency edges (good — correct ordering, cascading updates); can tangle distant resources if overused — modules/outputs are the boundary control.

## Credential Separation
**When to use**: any provider needing credentials.
**How**: empty `variable` blocks in `variables.tf`; values in git-ignored `terraform.tfvars` or `TF_VAR_*` env vars; escalate to Key Vault data sources (Ch 7) or Vault dynamic secrets (Ch 10).
**Trade-offs**: adds indirection; saves you from committed-credential incidents and per-machine drift.

## Pinned Versions
**When to use**: `required_providers` always; module sources always for shared code.
**How**: `version = "=3.0.0"` on providers; `source = "git::…//module?ref=v1.2.1"` with semver tags; `v2.0.0` flags breaks.
**Trade-offs**: deliberate upgrades required; reproducible builds guaranteed.

## Plan-File Handoff
**When to use**: pipelines, any reviewed deployment.
**How**: `terraform plan -out=plan.out` → review → `terraform apply plan.out` — no drift between review and execution.
**Trade-offs**: plan file expires if code changes; small discipline cost, big safety gain.

## count vs for_each Split
**When to use**: identical N copies → `count` + `count.index`; keyed distinct resources → `for_each` over a map/set.
**How**: default to `for_each`; keys are address-stable across scale changes.
**Trade-offs**: `count` removals shift indices and churn replacements.

## Dynamic Sub-block Generation
**When to use**: repeated sub-blocks (ingress/egress rules, policies) inside one resource.
**How**: `dynamic "ingress" { for_each = var.rules; content { from_port = ingress.value.from_port … } }` driven by a list(object) variable.
**Trade-offs**: single source of truth for rules; slightly denser reading for newcomers.

## Module Contract (inputs/locals/outputs)
**When to use**: every module; mandatory when a pattern repeats.
**How**: typed inputs w/ descriptions + validation; locals for naming/derivation; outputs as the documented consumer surface; README with examples.
**Trade-offs**: up-front design cost; pays off in environment reproducibility and team sharing.

## Nested Module Orchestration
**When to use**: infrastructure too big for one module (network, compute, storage slices).
**How**: parent creates top-level resources and passes its own values (e.g. `vnet_name` from `azurerm_virtual_network.parent_vnet.name`) to child submodules; root references the parent only.
**Trade-offs**: indirection depth vs. independence of submodule updates/versioning.

## Vault Dynamic Secrets
**When to use**: credentials worth making short-lived (cloud access, DBs).
**How**: `vault secrets enable azure` → `vault write azure/config …` → `vault write azure/roles/<role> …` → Terraform fetches `vault read azure/creds/<role>` (via local-exec or env injection) → lease expiry auto-revokes, even deleting the underlying service principal.
**Trade-offs**: extra infrastructure + wiring; dramatically smaller compromise windows.

## Vault-as-Data-Source (Key Vault)
**When to use**: static secrets with rotation, before adopting dynamic ones.
**How**: `azurerm_key_vault_secret` to write; `data "azurerm_key_vault_secret"` to read into `administrator_login_password` etc.; rotate at the vault, consumers pick it up on next run.
**Trade-offs**: values still flow through state/logs (encrypt state; mark sensitive); rotation is near-transparent.

## file + remote-exec Bootstrap
**When to use**: create-time VM setup without adopting config management.
**How**: `file` uploads the script; `remote-exec` runs `chmod +x` + execute; make scripts idempotent (failures taint → destroy/recreate).
**Trade-offs**: zero extra tooling; not re-run on updates — ongoing changes need cloud-init/Ansible/handoff.

## Trigger-Driven Provisioning (null_resource)
**When to use**: "re-run when X changes" logic with no natural resource.
**How**: `null_resource` with `triggers = { app_version = var.app_version }` + a provisioner; any trigger change forces re-execution.
**Trade-offs**: escape hatch, not architecture — too many revert the codebase to imperative style.

## Provider Chaining for Kubernetes
**When to use**: one codebase managing cloud resources + cluster workloads.
**How**: `data "azurerm_kubernetes_cluster"` → feed host/client cert/key/CA (base64decoded) into `provider "kubernetes"` → manage namespace/deployment/service resources alongside the cluster.
**Trade-offs**: tight coupling to provider's kube_config shape; single workflow for the whole stack.

## Rego Compliance Gates
**When to use**: security/organizational rules that must block bad plans.
**How**: `plan -out=tfplan` → `terraform show -json tfplan > tfplan.json` → `opa eval --data policy.rego --input tfplan.json "data.main.deny"`; non-empty deny → CI exit 1. Cheaper alternatives: tfsec/checkov.
**Trade-offs**: Rego authoring skill; violations die before apply.

## Import Adoption
**When to use**: bringing manual/legacy resources under Terraform.
**How**: write an accurate resource block → find real ID via CLI (`az group show … --query id`) → `terraform import <addr> <id>` → demand a "No changes" plan. Check `terraform state list` first; consider terraformer for bulk.
**Trade-offs**: precise code matching required; avoids destroy/recreate of legacy systems.

## Ephemeral Test Stacks
**When to use**: Terratest at any layer.
**How**: `defer terraform.Destroy(t, options)` + `terraform.InitAndApply` + output assertions; validation layer adds `http_helper.HttpGetWithRetry` with maxRetries/timeBetweenRetries.
**Trade-offs**: slower than static test fixtures; zero test residue and real coverage.