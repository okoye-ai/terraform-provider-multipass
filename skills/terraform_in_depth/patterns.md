# Patterns & Techniques

## Saved-plan discipline
**When to use**: any automation or reviewed apply. **How**: `terraform plan -out=tfplan` → review → `terraform apply tfplan`. **Trade-offs**: plan files keep credentials in-process only (never committed); applying without a file lets drift sneak in between review and apply.

## Impure-function replacement
**When to use**: plan shows changes immediately after every apply. **How**: replace `uuid()`/`timestamp()` with `random_id`/`random_string`/`time_rotating` state-only resources; use `keepers`/`triggers` to bridge locals into replacement via `replace_triggered_by`. **Trade-offs**: shifts values into state, where they are readable.

## count-as-toggle
**When to use**: boolean feature flags. **How**: `count = var.enabled ? 1 : 0`. **Trade-offs**: nicer UX than asking callers for a number; count values must resolve at plan start.

## count + local + element (target-bootstrapping avoidance)
**When to use**: count/for_each expression needs a resource attribute (which plan-time values forbid). **How**: copy the value into a `local`, or use `element(var.list, count.index)`. **Trade-offs**: avoids resource targeting, which creates modules that need bootstrapping.

## Dynamic blocks
**When to use**: repeatable subblocks driven by data. **How**: `dynamic "<block>" { for_each = ...; content { ... } }`, iterator named after the block. **Trade-offs**: 0/1/many testability (test all three); dense when nested.

## Validation-subblock deep validation
**When to use**: any typed module input, especially regex-checked IDs/ARNs. **How**: repeatable `validation { condition = ..., error_message = ... }`; Terraform ≥1.9 may reference other variables. **Trade-offs**: catches errors before slow plan/apply — some errors never surface at plan.

## Default-null optional inputs
**When to use**: optional module inputs. **How**: `default = null`, then a `local` testing `var.x != null`. **Trade-offs**: avoids false-equivalence with empty strings/0.

## Module file layout
**When to use**: any shared module. **How**: `variables.tf`, `outputs.tf`, `main.tf`, `README.md`, `modules/` (no sub-submodules), `templates/`, `examples/`; `examples/` root workspace with `source = "../.."` doubles as tests.

## Hierarchical naming scheme
**When to use**: multi-account/multi-environment estates. **How**: root module hardcodes `${application}-${environment}`; each submodule appends one descriptor (`acme-dev-api-lb-logs`); only primary resources use `var.name` directly.

## Network module with AZ toggles
**When to use**: VPC/module design across environments. **How**: `availability_zones` variable 1–4; `cidrsubnet` halve-then-halve bit arithmetic (powers of 2); ternary-computed subnet bits; binary toggle between two-tier/three-tier submodules; output spare CIDRs. **Trade-offs**: same code for dev and prod.

## Provisioner alternatives (decision matrix)
**When to use**: tempted to add a provisioner. **How**: ship software in images; configure at launch with Cloud-Init; use the vendor shutdown service; expose data with outputs + external/local provider. **Trade-offs**: provisioners add failure points, time, unpredictability.

## CI quality gate
**When to use**: every Terraform repo. **How**: makefile targets (`test_validation`, `test_format`, `test_documentation`, `test_tflint`, `test_security`) run identically via pre-commit locally and in CI; matrix across both engines × versions 1.6–1.8 (+ experimental); branch protection requires them. **Trade-offs**: template bootstrapping (Cookiecutter) makes this cheap.

## Security scanning pair
**When to use**: any repo. **How**: run Checkov and Trivy both (incomplete overlap); exceptions are inline comments whose form differs (reason mandatory for Checkov, not Trivy). **Trade-offs**: two scanners cost pipeline seconds but cover each other's gaps.

## Environment-as-root wrapper
**When to use**: production deployments. **How**: thin root module per environment that pins a module's **exact** version (`version = "1.1.1"`), passes variables, stores its own state; upgrades require a PR. **Trade-offs**: more directories than application-as-root; gives per-environment version control; Terragrunt for fleet-heavy setups.

## Secret-management hierarchy
**When to use**: any secret. **How**: eliminate secrets entirely via OIDC → centralize in a secret manager and pass only paths (retrieve by data source) → orchestrator settings as last resort. Never `-var`, tfvars, or env vars. **Trade-offs**: values still land in state regardless — restrict state access.

## Examples-as-tests
**When to use**: module CI. **How**: `examples/basic|lambda|ecs|ec2` directories launched and asserted by the CI pipeline; keep them working or delete them. **Trade-offs**: real-apply coverage vs test runtime and cloud cost.

## Parallel-change (expand-and-contract) variable renames
**When to use**: renaming any module input. **How**: add the new variable; a local prefers the old name when set; deprecate the old; delete in the next major. **Trade-offs**: lets consumers migrate lazily.

## Batched major releases
**When to use**: accumulating breaking changes. **How**: bundle breaking majors (ideally on provider majors), ≤1 major/year; release branch → UPGRADE.md/CHANGELOG.md → alpha/beta tags; bugfix branch from old tag. **Trade-offs**: fewer, louder breaks beat many silent ones.

## Machine-readable plan analysis
**When to use**: wrapping Terraform in a tool. **How**: `terraform plan -out=tfplan` then `terraform show -json tfplan`; parse Change/ChangeContainer; `before`/`after` contain only changed attributes. **Trade-offs**: printed plan output is a representation, not a format; read state via both `show` (documented) and `state pull` (serial/lineage).

## Wrapper-library pattern (SDK-less)
**When to use**: building tooling on Terraform. **How**: shell out to the binary; parse `show/validate/output` JSON and JSONL event streams (`event_handlers` per type); expose dataclasses; treat `validate` rc=1 as invalid config, not a crash. Set `TF_IN_AUTOMATION`. **Trade-offs**: prefer wrapping OpenTofu (Terraform v1.6 is BSL); tofupy is the Python reference pattern.

## Interfaces-first provider development
**When to use**: new provider. **How**: write the user-facing HCL example FIRST → define schema/models → Configure (credential funnel: unknown-check → env default → provider-block override → validation → client) → CRUD + ImportState → provider functions → `dev_overrides` local test → tfplugindocs → GPG-signed goreleaser publish. **Trade-offs**: provider changes are far more disruptive than module changes — get the interface right first.

## Diagnostics-over-early-return (provider)
**When to use**: any provider error path. **How**: keep processing, collect all Diagnostics, return once. **Trade-offs**: users see every problem at once; never `log.Fatal` (bypasses error handling, can corrupt state).

## Normalization of server-modified fields (provider)
**When to use**: vendor injects/mutates field content (e.g. sanitized HTML). **How**: normalize identically in Create, Update **and** Read. **Trade-offs**: skipping Read causes eternal "changes after apply" drift.