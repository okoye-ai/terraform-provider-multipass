# Glossary

**Acceptance test** — provider test running the real Terraform binary against real infrastructure, gated by `TF_ACC=1`; named with a `TestAcc` prefix (Ch 12)

**Backend** — how Terraform exposes state storage; chosen by the team's existing tech, and it must support locking (Ch 1, Ch 6)

**BSL** — Business Source License; license Terraform moved to at v1.6 (2023), restricting competitive hosted offerings; the reason OpenTofu forked (Ch 1)

**Change / ChangeContainer** — machine-readable plan structures: Change holds actions/before/after plus before-after-sensitive and after_unknown; ChangeContainer wraps it with metadata (Ch 11)

**Check block** — non-blocking assertions (v1.5) that add warnings without failing the run (Ch 10)

**Checkov** — free local security scanner; skip exceptions via `#checkov:skip=<ID>:<reason>` where the reason is mandatory (Ch 7)

**count** — integer meta parameter creating N copies of a resource, exposing zero-based `count.index`; values must be known at plan start (Ch 4)

**Data source** — read-only lookup block fetching live values (AMIs, subnets) to keep code portable across accounts/regions (Ch 2)

**DAG** — directed acyclic graph; Terraform's representation of code, plans, and state (Ch 1, Ch 5)

**dev_overrides** — local-registry override in `~/.terraformrc` that lets a locally built provider binary be used for testing (keep `direct {}`) (Ch 12)

**Diagnostics** — multi-error collector in provider development; keep processing and collect all diagnostics instead of returning early (Ch 12)

**Drift** — infrastructure changed outside Terraform, detected on refresh; a symptom of a deeper problem (Ch 6)

**Dynamic block** — generates repeatable subblocks from a for_each; the iterator keyword is named after the block itself (Ch 4)

**Environment** — an isolated instance of a project with its own accounts, networks, variables, and state (Ch 8)

**Expand-and-contract** — parallel change refactoring: add the new input alongside the old, prefer the old name in a local, delete the old input in the next major (Ch 9)

**for expression** — data transformation: list output `[for x in l : v]` or object output `{for x in l : k => v}`, with `if` filtering and `...` grouping (Ch 4)

**for_each** — meta parameter keyed by object/map/set exposing `each.key`/`each.value`; lists must be converted with `toset` (Ch 4)

**GitOps** — CNCF delivery model: Declarative, Versioned and immutable, Pulled automatically, Continuously reconciled (Ch 8)

**HCL** — HashiCorp Configuration Language, the declarative language of Terraform/OpenTofu (Ch 1)

**Input variable** — module input with description/type/default/sensitive/nullable/validation attributes (Ch 3)

**Impure function** — function (e.g. `uuid`, `timestamp`) whose result is never stored, leaving the workspace permanently out of sync after apply (Ch 4, Ch 6)

**Lineage** — UUID assigned to a state file at first `terraform init`; prevents cross-project state overwrites (Ch 6)

**Linter** — static analysis tool that inspects code without running it (Ch 7)

**Locals** — label-less repeatable block defining one flat module-internal namespace; no duplicates, no circular references (Ch 3)

**Machine-readable UI** — Terraform's machine interface: JSON output (single responses) and JSONL event streams (plan/apply) (Ch 11)

**Meta argument** — language-level argument that changes how Terraform plans rather than configuring a resource (Ch 2)

**Mock provider** — Terraform testing framework feature (v1.7+) supplying fake default values; supplements but never replaces integration tests (Ch 9)

**Module** — reusable, self-contained directory of Terraform code used and composed like a function (Ch 2, Ch 3)

**Module registry** — Git-tag-driven module hosting (~12k public modules); repo naming `terraform-PROVIDER-NAME` (Ch 3)

**moved / removed blocks** — HCL blocks (v1.5/1.7) refactoring addresses and removing resources in code; keep moved blocks through a major release (Ch 2, Ch 6, Ch 9)

**null** — "not set" sentinel; the idiomatic default for optional inputs, tested with `var.x != null` (Ch 3)

**OIDC** — OAuth 2.0-based machine identity; the preferred top tier of the secret-management hierarchy (Ch 8)

**Output** — module return value with description/value/sensitive/depends_on; outputs derived from sensitive values must themselves be sensitive (Ch 3)

**Parallelism** — number of concurrent resource operations during apply; default 10 (Ch 5)

**Plan** — the set of changes Terraform would make; the plan file (tfplan) is authoritative, printed output is only a representation (Ch 5)

**Precondition / postcondition** — lifecycle-attached assertions (v1.9+ cross-object) verifying assumptions before/after changes (Ch 10)

**Provider** — gRPC plugin process exposing resources, data sources, and (1.8+) functions for a vendor API (Ch 1, Ch 12)

**Provider alias** — named provider configuration for multi-region/multi-account usage, referenced as `provider = aws.west` (Ch 2)

**Provider functions** — provider-supplied functions callable as `provider::namespace::name` (Terraform v1.8+) (Ch 12)

**Resource graph** — Terraform's central internal data structure; state is a snapshot of its nodes (resource, provider configuration, resource meta) (Ch 5)

**required_providers** — `terraform`-block constraint pinning provider *install* versions, distinct from `provider` blocks which *configure* them (Ch 2)

**Schema (provider)** — typed parameter/attribute declaration: Required/Optional/Computed/Default/Sensitive/DeprecationMessage; paired with a Go model struct via `tfsdk` tags (Ch 12)

**Sensitive (flag)** — hides values in CLI output; does NOT exclude them from state; propagation must be handled explicitly on outputs (Ch 3, Ch 6)

**Serial** — integer incremented on every state save; proves the latest version; increment manually after a manual state edit to keep guards intact (Ch 6)

**Speculative plan** — plan not saved with `-out` and never applied; refresh/lock exception flags are valid only in this mode (Ch 5)

**State** — collection of metadata mapping Terraform code to real resources; contains every attribute, including sensitive values, in plaintext (Ch 1, Ch 6)

**State-only resource** — resource computed locally and persisted only in state (`random_*`, `time_*`, `null`, `terraform_data`, TLS data); fixes impure-function drift via keepers/triggers (Ch 6)

**TACOS** — Terraform Automation and Collaboration Software; bundle of delivery automation, state backend, and private registry (Ch 1, Ch 8)

**Terratest** — Gruntwork's Go-test-based IaC testing framework; de facto standard, 20+ helper packages (Ch 9)

**Terraform testing framework** — native HCL testing (`.tftest.hcl`, v1.6+): `run` blocks (apply or plan) with `assert` blocks (Ch 9)

**TFLint** — plugin-based linter (aws 700+, google 200+, azurerm 100+ rules); the terraform plugin is not enabled by default — use presets (Ch 7)

**tf.json** — Terraform configuration in JSON; a program-generation target with string-template-only expressions and `//` comment keys — not for humans (Ch 11)

**Trivy** — TFSec-lineage scanner; ignore via `#trivy:ignore:<ID>` comment or project-wide `.trivyignore` (no reason field) (Ch 7)

**Unknown** — value not known until apply; plan-time logic reading unknowns fails, hence plan-modifiers like `UseStateForUnknown` (Ch 12)

**Validation block** — repeatable condition+error_message subblock on inputs; Terraform ≥1.9 may reference other inputs — deep validation with descriptive errors is the hallmark of a great module (Ch 3)

**Workspaces** — same code, different state file; distinct from HCP/cloud-block workspaces, which are fully independent (HashiCorp's most confusing naming) (Ch 1, Ch 6)
