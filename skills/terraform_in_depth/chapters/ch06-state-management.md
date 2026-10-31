# Chapter 6: State management

## Core Idea
State is Terraform's mapping between the code and the real-world infrastructure — "a collection of metadata about the resources that Terraform manages" — so it must be treated as critical, secret-bearing infrastructure: stored centrally (resilient, secure, available), locked, backed up, and manipulated only through code-first tooling.

## Frameworks Introduced
- **The three state-storage considerations** (section 6.2): **Resiliency**, **Security**, and **Availability**.
  - When to use: evaluating any state backend before commit.
  - How — Resiliency: check the vendor's historic durability (S3's "99.999999999%" = ~1 lost object per 100 trillion per year) *and* assume human error; reliable, tested backups are mandatory. Security: state "includes not just identifiers for resources but all the attributes as well" — sensitive values included — so require MFA, correct configuration, and minimize secrets in state. Availability: state access is a hard gate on all deploys; the author expects "at least 99.99% (four nines)" and treats state storage as absolutely critical infrastructure.
- **Backend configuration requirements** (figure 6.1): Restrict Access, Enable Logging, Enable Encryption, Configure Backups, Configure Locking.
  - When to use: setting up any self-managed backend.
  - How: "Never use a backend without locking or you'll risk corrupting your state" (S3 needs explicit/DynamoDB locking); plus the golden rule — "if you haven't tested it recently, your backups are worthless."
- **State manipulation hierarchy** (6.5): code-driven changes (moved/removed blocks) are best; CLI commands are second; manual editing is the last resort.
- **Four categories of state drift** (figure 6.2): Machine Error = Conflicting Automated Change + Terraform Error; Human Error = Accidental Manual Change + Intentional Manual Change.
  - When to use: after asking "What changed and why?" — categorize the source, then apply that category's fix.

## Key Concepts
- **Stateful vs. stateless systems**: stateful systems memory of what happened before that drives current actions; Terraform keeps a record of all managed resources and refreshes it every plan.
- **Purpose of state** (6.1): **Real-world linkage** (mapping code to true identifiers like ARNs — impossible to do generically via tags, which not all resources support and which people change independently), **Reduced complexity** (fewer lookup paths makes Terraform *and providers* easier to build, strengthening the whole ecosystem), **Performance** (fast dev cycles), and it enables **state-only resources**.
- **State file anatomy** (local `.tfstate` JSON): top-level fields are `version` (data structure version), `terraform_version` (generator version), `serial` (incremented by 1 on every state change), `lineage` (UUID, assigned at first `terraform init`, never changes), `resources` (resources *and* data sources), `outputs` (root module only), `check_results`.
- **Resource record fields**: `module`, `mode` (`managed` vs `data`), `type`, `name` (together forming the resource address), `provider` (how Terraform detects provider changes), `instances[].attributes` (all computed + configured attributes, **including sensitive values in plain text**), `schema_version`.
- **moved block**: declares `from`/`to` resource addresses so refactors rename or relocate resources without destroy/recreate; only processes when the `from` resource exists in state, so it idles after migrating. Works for modules too, and is critical in shared modules — it lets you change module internals "without forcing your module users into painful upgrade situations."
- **removed block**: takes `from` plus a mandatory `lifecycle { destroy = false }` (or true) to stop managing a resource without touching the infrastructure.
- **terraform_remote_state data source**: built into Terraform (no provider); read-only access to *outputs* of another project's state; use `defaults` to turn a hard dependency on remote state into a soft one.
- **State-only providers/providers**: calculate values programmatically and persist them in state, touching no external APIs — TLS (ch5), random, time, null, and the built-in `terraform_data`.
- **keepers / triggers / triggers_replace**: the mechanism state-only resources use to persist randomness or timestamps until a chosen input changes, avoiding impure-function drift.

## Mental Models
- Think of **state as a snapshot of the resource graph** (ch5): Terraform walks code to build the graph, then compares it against this snapshot during refresh.
- Think of the **lineage/serial pair as state's version-control envelope**: lineage proves you're looking at *this project's* state; serial proves you're looking at the *latest* it. `state push` refuses mismatches unless `-force`.
- Think of **workspaces as the same code with different state** (local) — versus Terraform Cloud workspaces, which are fully independent environments; the shared name is "one of the most confusing decisions" HashiCorp made, and `terraform.workspace` is usable in code (even in count/for_each) to switch VPCs per environment.
- Use **remote state as "another set of variables"**: keep `terraform_remote_state` calls in the top-level composing module (or a dedicated org-internal module) so logic-carrying modules stay reusable and portable.
- Consider **alternatives before remote state lookups**: data-source lookups are more standalone and more secure (anyone with state access sees every attribute); variables work but need maintenance.

## Anti-patterns
- **Local backend in production**: fails every consideration — not resilient, not secure, not available to anyone beyond one machine. "Should never be used in production."
- **S3 backend without state locking**: "your backend state can easily end up corrupted"; also makes S3 emulations (Wasabi) unsuitable.
- **Manual state editing**: loses repeatability and Terraform's structural validation; if unavoidable, back up first, run JSON validation, diff against the backup, and increment `serial` by 1 to keep the other push checks intact.
- **`terraform state push` without understanding the guards**: different lineage or lower serial fails — `-force` is for reverting to an older state deliberately.
- **Treating state drift as just noise**: drift is "often a symptom of another problem"; fix the source (access policy, CI/CD enforcement), don't just re-apply.
- **Reverting intentional emergency changes by running Terraform**: until the manual change is codified, "it's not safe to run Terraform."
- **Committing backend credentials in code**: use tfvars backend-config files, cloud config files, or environment variables; note whatever you pass gets cached in `.terraform` on disk anyway.
- **Relying on `sensitive` for safety**: the sensitive flag only controls display; "sensitive values do still get stored in state."

## Code Examples
- **What it demonstrates**: code-driven state manipulation — renaming/moving a resource and un-managing an S3 bucket without destroying it.

```hcl
resource "random_password" "main" { length = 12 }

moved {
  from = random_password.my_password
  to   = random_password.main
}

# Works the same for relocations into modules:
# moved {
#   from = random_password.my_password
#   to   = module.password.random_password.main
# }

removed {
  from = aws_s3_bucket.bucket
  lifecycle {
    destroy = false   # keep the real bucket; only leave Terraform
  }
}
```

- **What it demonstrates**: reading another project's state and passing its outputs into a service, with `defaults` making the dependency soft.

```hcl
data "terraform_remote_state" "rds" {
  backend = "s3"
  config = {
    bucket = var.state_bucket_name
    key    = var.rds_state_path
    region = var.state_region
  }
  defaults = {
    rds_uri = null   # output exists even while the remote project bootstraps
  }
}

module "service" {
  source = "./modules/service"
  image  = "my_example_image"
  env = { rds_uri : data.terraform_remote_state.rds.outputs.rds_uri }
}
```

## Reference Tables
**Terraform backends** (table 6.1, abridged):
| Backend | System | Workspaces | Notes |
|---|---|---|---|
| local | local FS | Yes | Never in production |
| azurerm | Azure | Yes | Natural for Azure teams |
| consul | Consul | Yes | Good self-hosting option (HA recommended) |
| cos | Tencent | Yes | Natural for Tencent teams |
| gcs | Google Cloud Storage | Yes | Natural for GCP teams |
| http | custom HTTP API | No | Build your own backend |
| kubernetes | K8s Secrets | Yes | Avoid before Terraform v1.6 (state size limits) |
| oss | Alibaba Cloud | Yes | Uses Table Store for locking |
| pg | PostgreSQL | Yes | State in a SQL database |
| s3 | AWS S3 | Yes | Requires DynamoDB locking; unsuitable for S3-emulation systems |
| remote | Terraform Enterprise | Yes | Being replaced by the cloud block |
| cloud | TACOS | No | More than a backend — overrides plan/apply to run remotely |

Backends are built into Terraform (not extensible), differ mainly in where state lives, and have had non-backward-compatible changes (Terraform v1.3 removed legacy non-locking backends) — read upgrade notes. Config goes in a `terraform { backend "<name>" { ... } }` block, root module only; usually empty (partial configuration) with values supplied via `terraform init -backend-config=PATH` (tfvars-style) or flags (flags win over files). Changing backends prompts `terraform init` to offer `-migrate-state` (move current state; older versions aren't migrated) or `-reconfigure` (start fresh).

**State-only provider toolkit** (6.8): `random` (uuid, integer, pet, shuffle; `random_password` is the only resource guaranteed to use a cryptographic RNG and is the chapter's state-dissection example), `time` (`time_static`, `time_offset`, `time_rotating` + `time_sleep` for delays via `depends_on` chains), `null` (`null_resource` does nothing — ideal for testing pipelines with no infrastructure), `terraform_data` (built-in since v1.4, `triggers_replace` instead of `triggers`; can convert a local/variable into a `replace_triggered_by` signal, which `replace_triggered_by` cannot accept directly).

## Worked Example
Recovering from and codifying drift, end to end:

1. **Detect**: a change was merged on infra managed by Terraform; every plan shows unexpected changes discovered by the initial refresh.
2. **Ask "What changed and why?"**: review logs and team history to find the source — on-call engineer made an intentional manual change to bring the system back up (Human Error -> Intentional Manual Change). Note the blame framing: "this isn't the fault of the individual ... it's a problem with the systems around them" — restrict production access, enforce CI/CD.
3. **Freeze Terraform**: running a plan at this point would revert the emergency fix; the change must get into code first.
4. **Codify**: bring the changed attributes into the configuration, or use `lifecycle { ignore_changes = [tags] }` for expected outside changes (external taggers, autoscaler desired counts); for new artifacts/versions (image publishes, RDS minor upgrades) choose *apply* the change or *ignore* the attribute — a refresh-only plan suffices for harmless ones.
5. **Verify state alignment**: `terraform plan --refresh-only` updates stored state with no infrastructure changes and asks for approval (never `terraform refresh`, which can drop resources on auth failures without review).
6. **Backstop**: before any state manipulation, `terraform state pull > my_backup.tfstate`; if a change went wrong, `terraform state push -force my_backup.tfstate` restores it (the push's lineage/serial guards require `-force` when reverting an older state).

## Key Takeaways
1. State is critical, secret-bearing infrastructure: pick the backend your team already uses, then restrict access, log, encrypt, lock, and back up (and test the backups).
2. Refactor resources with `moved` and leave Terraform's control with `removed` — code-driven state changes beat CLI commands, which beat hand-editing JSON.
3. Every drift response starts with "What changed and why?", categorized as accidental-manual, intentional-manual, conflicting-automated, or Terraform error.
4. If Terraform created resources but failed to save state, either `terraform import` them or delete them for real; for unsaved updates/deletes, a refresh-only apply usually realigns state.
5. Read cross-project values via `terraform_remote_state` (top-level module only, with `defaults`), but prefer data-source lookups or managed-secret paths when they work.
6. Use `random`/`time` resources (not impure functions) for randomness and timestamps; `terraform_data` replaces `null_resource` and bridges locals into `replace_triggered_by`.
7. Never expose secrets through state-backed flows without remembering they persist in plaintext in the tfstate file.

## Connects To
- **Ch 5**: state is a snapshot of the plan's resource graph; refresh-only mode and failed-state-update recovery were flagged there.
- **Ch 4**: impure functions motivated the random/time state-only providers.
- **Ch 7/8**: the cloud block, TACOS, and null_resource testing of pipelines lead directly into CI/CD; the `import` block and provisioner details land in ch8/10.
- **Conway's law**: external concept — "The structure of any system designed by an organization is isomorphic to the structure of the organization" — the main driver for splitting projects and reading state across teams.
- **SLAs / nines / durability numbers**: external SRE vocabulary for evaluating state vendors.
