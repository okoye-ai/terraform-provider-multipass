# Chapter 10: Advanced Terraform Configuration Techniques

## Core Idea
At production scale, each distinct element of complexity should be encapsulated in the Terraform language feature best suited to it: meta-arguments (`count`, `for_each`) for repetition, conditional expressions for optional resources, dynamic blocks for nested config, locals for naming, data sources for live lookups, and provisioners/`null_resource` only as a last resort — all combined with workspaces to drive many environments from one codebase.

## Frameworks Introduced
- **Encapsulation of complexity (chapter's organizing principle)**: "each distinct element of complexity should be encapsulated within the language feature that best suits it" — `count`/`for_each` for many instances, conditionals for on/off, dynamic blocks for nested structures, locals for naming conventions and intermediate calculations, data sources for authoritative lookups.
  - When to use: any configuration that has grown past proof-of-concept into multi-region, security-controlled production code.
  - How: refactor repetitive blocks one feature at a time; keep every naming decision in exactly one place.
- **Custom provider: five foundational concepts**: (1) Provider configuration schema, (2) Resource schema, (3) CRUD lifecycle (Create/Read/Update/Delete/Import translating plans into API calls), (4) State management (persist external identifiers to detect drift), (5) Versioning and compatibility (semantic versioning, responsible deprecation).
  - When to use: infrastructure not covered by any Registry provider; always search the Registry and GitHub for a community provider first.
  - How: evaluate community providers like third-party libraries — licence, maintenance cadence, issue backlog, target Terraform version support, resource coverage; pin an explicit version (e.g. `1.2.3`) in `required_providers`. Scaffold with `terraform-provider-scaffold`, test in Go plus `terraform test` against a sandbox, publish to the public or a private registry.
- **Single-codebase multi-environment pattern (Chef's Special)**: one Terraform configuration + `terraform workspace` for state isolation + variables/locals for sizing + conditionals for prod-only resources.
  - When to use: one team maintaining dev/staging/prod stacks without duplicating HCL.
  - How: `terraform workspace new dev|prod`, per-workspace `env/*.tfvars`, `count = var.env == "prod" ? 1 : 0` for production-only guardrails.

## Key Concepts
- **`count`**: index-based meta-argument that creates N instances from one block; best with lists and with `var.flag ? 1 : 0` toggles.
- **`for_each`**: iterates over a map or set, giving each instance a stable unique key (e.g. `sa["uk"]`); use over `count` when instances must be addressable by name, since removal of a map entry does not reindex the others.
- **Conditional expression + `count`**: `count = var.enable_backup ? 1 : 0` omits the resource (and its dependent VNet/NIC chain) from the plan entirely when the flag is false.
- **`depends_on`**: explicit build-order declaration used when Terraform's automatic reference graph cannot express the real dependency (e.g. DNS A record must wait for an LB rule to avoid race conditions).
- **Dynamic block**: iterates a collection at plan time and emits one nested block per element (e.g. `security_rule` blocks from `var.rules`); priorities computed as `100 + index(var.rules, security_rule.value)` for uniqueness.
- **Local values**: computed once per run and reused; canonical use is naming — e.g. `lower(replace(local.prefix, "-", ""))` to meet Azure's lowercase storage-account constraint.
- **Data source**: read-only plan-time query of existing infrastructure (latest platform image, existing VNet/subnet, remote state outputs) so configs stay portable instead of hardcoding IDs.
- **Provisioner**: `local-exec` or `remote-exec` script execution during create/destroy — explicitly non-idempotent and fragile; the author's rule is to use them only when no native resource or provider can achieve the same result (bootstrap, validation, one-off tasks).
- **`null_resource`**: placeholder resource that hosts provisioners without tying them to an infrastructure object — smoke tests, orchestration scripts, deployment hooks; gate its execution with `depends_on`.
- **Workspace**: per-workspace state under `.terraform/terraform.tfstate.d/<workspace>/`, letting identical HCL deploy isolated dev/prod stacks.

## Recipes in this chapter
- **Recipe 55: Multiple resource deployment with for_each** — three Azure Storage Accounts from one map variable, plus a `random_string` suffix for global name uniqueness.
- **Recipe 56: Conditional resource creation** — a backup VM plus its VNet/subnet/NIC, all gated by `count = var.enable_backup ? 1 : 0`.
- **Recipe 57: Using data sources** — attach a new VM to an existing VNet/subnet and boot the latest `azurerm_platform_image` Ubuntu version with no hard-coded IDs.
- **Recipe 58: Using dynamic blocks** — NSG inbound rules generated from a `rules.tfvars` list; adding a rule needs only a tfvars edit, no code change.
- **Recipe 59: Utilizing local values** — naming logic centralized in `locals`; flipping `env` from `dev` to `prod` renames every resource automatically.
- **Recipe 60: Executing external scripts with null_resource** — a PowerShell retrying health-check script (10 attempts, 5 s apart) wired as a post-deploy smoke test.

## Anti-patterns
- **Repeating resource blocks for similar resources**: duplicate blocks invite drift and human error — prefer `for_each` over a map.
- **Hard-coding IDs, names, or image versions**: breaks portability and silently pins stale patch levels — query data sources instead.
- **Reaching for provisioners first**: they are not idempotent and fail on transient connectivity/timing issues; treat as last resort for lightweight validation only.
- **Scattering naming logic across resources**: long interpolations repeated everywhere means one edit becomes many — centralize in locals.
- **Writing a custom provider before searching the Registry**: community offerings mature quickly and often already meet the requirement.
- **One configuration per environment directory**: code sprawl; the chapter's pattern is one codebase + workspaces + tfvars.

## Code Examples
Dynamic block generating NSG rules at plan time:
```hcl
resource "azurerm_network_security_group" "web_nsg" {
  name                = "web-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  dynamic "security_rule" {
    for_each = var.rules
    content {
      name                       = security_rule.value.name
      priority                   = 100 + index(var.rules, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      destination_port_range     = security_rule.value.port
    }
  }
}
```
- **What it demonstrates**: one variable list becomes multiple nested `security_rule` blocks with unique auto-assigned priorities (100, 101, 102, …) — the DRY pattern for nested provider blocks.

Locals as a single source of truth for naming:
```hcl
locals {
  prefix       = "${var.environment}-${var.project}"        # e.g., "dev-payments"
  storage_name = lower(replace(local.prefix, "-", ""))      # Azure requires lowercase
}

resource "azurerm_resource_group" "rg" { name = "rg-${local.prefix}" ... }
resource "azurerm_storage_account" "sa" { name = local.storage_name ... }
resource "azurerm_virtual_network" "vnet" { name = "vnet-${local.prefix}" ... }
```
- **What it demonstrates**: canonical naming derived once; changing `var.environment` cascades through every resource name with no code edits.

## Reference Tables
Chef's Special — conditional resource by workspace (Table 10.1):

| Workspace | Variable env | Count evaluates to | Result in the state |
|---|---|---|---|
| Dev | dev | 0 | Action group not created |
| Prod | prod | 1 | Action group created |

Validation and cleanup commands (Table 10.2):

| Task | Command |
|---|---|
| List workspaces | `terraform workspace list` |
| Verify URLs | `terraform output app_urls` |
| Destroy Dev | `terraform workspace select dev` then `terraform destroy -var-file="env/dev.tfvars"` |
| Destroy Prod | `terraform workspace select prod` then `terraform destroy -var-file="env/prod.tfvars"` |

Community provider evaluation criteria: licence · maintenance cadence · issue backlog · target Terraform version support · resource coverage.

## Worked Example
Chef's Special — multi-environment web stack on workspaces (three courses):

1. **Appetizer (reusable config)**: one folder (`main.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `env/dev.tfvars`, `env/prod.tfvars`). `local.prefix = "${var.env}-web"` and `common_tags` drive everything. `azurerm_linux_web_app` uses `count = var.instance_count` with `format("%s-%02d", local.prefix, count.index + 1)` so dev→1 app (`dev-web-01`, SKU `S1`) and prod→3 apps (SKU `P1v2`); each app's tags merge `common_tags` with an `instance` number. Output: `output "app_urls" { value = [for app in azurerm_linux_web_app.app : app.default_hostname] }`.
2. **Main course (workspaces)**: `terraform workspace new dev` → plan/apply with `env/dev.tfvars`; `terraform workspace new prod` → plan/apply with `env/prod.tfvars`. Terraform writes state to `.terraform/terraform.tfstate.d/<workspace>/`, so Dev and Prod stay isolated while the HCL is identical.
3. **Dessert (prod-only resource)**: `azurerm_monitor_action_group.pagerduty` declared with `count = var.env == "prod" ? 1 : 0`. Selecting the prod workspace and re-applying creates the action group (email receiver `oncall@example.com`, `short_name = "PD"`); applying from dev evaluates count to 0 and leaves dev state clean. Plan output reads "0 to add" in dev vs `+ azurerm_monitor_action_group.pagerduty` in prod.

Result: a DRY multi-environment workflow where sizing, tagging, and environment-specific guardrails are all variable-driven — code identical, state separated.

## Key Takeaways
1. Use `for_each` over maps rather than `count` over lists when instances need stable, name-addressable references.
2. Wrap every optional environment in `count = var.condition ? 1 : 0`; this pattern scales to wrap any resource, module, or output.
3. Put all naming rules in locals — provider constraints (lowercase, length limits) enforced in one line beat fixes scattered across resources.
4. Data sources keep configs future-proof: reference live image versions, existing networks, and other teams' outputs instead of pasted IDs.
5. Provisioners and `null_resource` are a last resort — reserve them for smoke tests, notifications, and APIs no provider models, and always chain them with `depends_on`.
6. Prefer `terraform workspace` plus per-env tfvars over duplicated configuration directories when one team runs multiple environments.
7. Before authoring a provider, evaluate the Registry/GitHub ecosystem and pin community providers to explicit versions for deterministic builds.

## Connects To
- **Ch 11**: this chapter's workspaces/conditional patterns carry into Kubernetes — the next chapter provisions managed clusters (AKS/GKE/EKS) and deploys workloads with the Kubernetes and Helm providers from the same declarative workflow.
- **Ch 12**: the configurations built here are exactly what the testing/CI/CD chapter wraps in `terraform fmt`/`validate`, Terratest, TFLint, and Checkov gates.