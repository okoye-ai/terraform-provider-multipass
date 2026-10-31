# Patterns — Terraform Cookbook (Husain)

## Remote State for Team Collaboration
**When to use**: More than one person or automation touches the same infra.
**How**: Move state to a lockable backend (Azure Blob, S3+DynamoDB, Terraform Cloud) with `terraform init -migrate-state`; lock file stays out of Git decisions documented.
**Trade-offs**: adds a bootstrap resource + backend config vs. no concurrent-write corruption.

## Import-first Adoption
**When to use**: Resources already exist outside Terraform (hand-built or from a failed apply).
**How**: `terraform import azurerm_resource_group.example <provider-id>`; then adapt code until `plan` shows no changes.
**Trade-offs**: safest way to inherit legacy infra, but import specs are provider-specific.

## Module Version Pinning
**When to use**: Any module source that can change under you.
**How**: pin registry modules with `version = "~> 1.3"`; for Git sources pin `ref = tags/v1.3`. Upgrade deliberately via the pin.
**Trade-offs**: reproducibility vs. freshness.

## Module Composition via Outputs
**When to use**: Chaining modules (network → compute → database).
**How**: each module exposes outputs (subnet IDs, resource group name); the next module takes them as inputs. Root module wires the graph.
**Trade-offs**: clean dependency graph vs. more boilerplate in root.

## `for_each` over `count` for Named Sets
**When to use**: Resources are individually addressable (per-subnet, per-disk).
**How**: `for_each = toset(var.subnet_names)` gives map-addressed resources that survive list reordering.
**Trade-offs**: count works for simple clones, but item identity shifts on reorder.

## Conditional Resource Creation
**When to use**: Optional components per environment.
**How**: `count = var.create_monitoring ? 1 : 0` gates whole resources/modules.
**Trade-offs**: readable toggles vs. hidden resources that surprise readers.

## Dynamic Blocks
**When to use**: Many repeated nested blocks (NSG rules, backend pools).
**How**: `dynamic "ingress" { for_each = var.rules ... }` driven by a list of objects.
**Trade-offs**: removes copy-paste vs. slightly less readable than literal blocks.

## Local Values as Composition Layer
**When to use**: Expressions recur (naming, tags, subnet CIDRs).
**How**: compute once in `locals {}` (e.g. `common_tags` map), reference everywhere.
**Trade-offs**: one place to change vs. indirection.

## Remote State as Data Source
**When to use**: One stack needs outputs of another stack (network team → app team).
**How**: `data "terraform_remote_state" "network" { backend = ... }` — read-only coupling.
**Trade-offs**: no dependency cycles vs. implicit ordering between teams' applies.

## Detect-then-Decide Drift Handling
**When to use**: Portal/console changes or other actors mutated real infra.
**How**: `terraform plan` reveals the diff. Config is correct → `terraform apply` enforces it back. Manual change is wanted → `terraform plan -refresh-only`, confirm, then `terraform apply -refresh-only` to adopt it into state only.
**Trade-offs**: enforce preserves IaC's single source of truth; accept preserves someone's emergency fix.

## Blue-green Deployment
**When to use**: Zero-downtime environment updates.
**How**: provision green set alongside live blue (two scale sets / target groups), switch traffic at load balancer or DNS, validate, destroy blue. Requires `create_before_destroy`-friendly lifecycle.
**Trade-offs**: double capacity cost during cutover vs. instant rollback.

## Active-active Multi-cloud
**When to use**: Cross-cloud resilience or latency routing.
**How**: same Terraform root provisions provider-specific resources per cloud, fronted by round-robin/DNS (e.g., Azure VMSS + GCP target pool behind one DNS name).
**Trade-offs**: highest availability vs. duplicated operational surface.

## Terragrunt Orchestration
**When to use**: Many environments/regions where vanilla Terraform repeats config.
**How**: Terragrunt generates/backends-per-module config, DRY-ing backend and dependency wiring.
**Trade-offs**: extra tool to learn vs. eliminated repetition at scale.

## VCS-driven Run Governance (Terraform Cloud)
**When to use**: Team-owned infrastructure needing review and policy gates.
**How**: connect workspace to Git; PRs get speculative plans; merges trigger plan → Sentinel policy checks → manual confirm or auto-apply. Path/tag patterns scope triggers in monorepos.
**Trade-offs**: strongest reproducibility and audit trail vs. platform dependency.

## Sentinel Policy Sets
**When to use**: Rules that must never be broken (tags, region, instance size).
**How**: policy files import `tfplan`/`tfconfig`/`tfstate`, grouped into sets, attached to projects/workspaces; choose enforcement level per rule.
**Trade-offs**: enforcement lives in the platform (not portable to vanilla CI, unlike OPA).

## Dynamic Secrets at Apply Time
**When to use**: Any password/connection string.
**How**: fetch from Azure Key Vault / HashiCorp Vault at apply; `sensitive = true` on the variable; mark secrets outputs `sensitive`.
**Trade-offs**: rotation + audit built-in vs. dependency on the vault being reachable.

## Least-privilege Execution Identity
**When to use**: Pipelines running Terraform.
**How**: Managed Identity (Azure) or short-lived tokens; scope RBAC to the resource group/prefix actually managed, never subscription-wide Contributor.
**Trade-offs**: more policy configuration vs. contained blast radius.

## CI Quality Gate Ladder
**When to use**: Every merge.
**How**: `terraform fmt` → `terraform validate` → TFLint (static lint) → Checkov (security posture) → plan as PR artifact → Terratest for critical modules.
**Trade-offs**: longer pipelines vs. catching errors pre-apply.

## Large-deployment Performance
**When to use**: Thousands of resources, slow plans.
**How**: `-parallelism=N` to tune concurrency, `-target=module.iam` for scoped edits, cache plugins in CI, isolate slow resources into separate state.
**Trade-offs**: faster cycles vs. targeted ops can miss cross-module dependencies.

## Git Hygiene Rules
**When to use**: Any repo with Terraform.
**How**: ignore `.terraform/`, `*.tfstate*`, `*.tfvars` (when secret-bearing), `crash.log`, `override.tf*`; commit `.terraform.lock.hcl` if reproducibility is the team policy.
**Trade-offs**: one deliberate lock-file policy, uniformly enforced.