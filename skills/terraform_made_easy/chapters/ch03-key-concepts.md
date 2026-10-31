# Chapter 3: Key Concepts of Terraform

## Core Idea
Scale-safe Terraform = providers (bridges to any API via the Registry), variables/outputs/locals (the configuration's "heartbeat"), modules (reusable packaged units), dependency management, and state discipline (state file, backends, workspaces, locking).

## Frameworks Introduced
- **Provider Model**: a provider is the bridge between Terraform and external APIs (cloud, SaaS, GitHub, Kubernetes, MongoDB Atlas). Distributed separately from Terraform, versioned on its own schedule.
  - Types (Registry badges): **Official** (HashiCorp-maintained, most reliable) → **Partner** (tech-vendor partners, robust support) → **Community** (niche/emerging, variable quality) → **Archived** (unmaintained — use with caution).
  - Registry scale: 4,000+ providers, 17,000+ modules/policies/tasks.
  - Provider requirement = local name + source location + version constraint, declared in `required_providers` inside the `terraform` block.
  - Plugin cache for repeated inits: `plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"` in `.terraformrc`.
- **Module Composition**: root module (the directory you run Terraform in) → child modules (called via `module` blocks) → local modules (`source = "./modules/x"`) or published modules (Registry/VCS, e.g. `source = "terraform-google-modules/cloud-storage/google"`).
  - Module standard structure: `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `README.md`, optional `modules/` (nested) and `examples/` directories.
  - Module block components: `source` (required), input variables from the child's `variables.tf`, `version` (recommended for registry modules), meta-arguments `count`, `for_each`, `providers`, `depends_on`.
- **Dependency Management**: two kinds —
  - **Implicit**: Terraform auto-detects from references (e.g. `network = google_compute_network.default.self_link` orders network before instance). Prefer this wherever a reference chain exists.
  - **Explicit** (`depends_on = [...]`): only when the order isn't obvious from references — e.g. firewall rule must exist before the Cloud SQL instance is created.
  - **Module dependencies**: no built-in module-to-module dependency — wire it with output → input variables (child exports, parent passes into next child).
- **State**: the map connecting real-world resources to config, stored by default in `terraform.tfstate` (JSON: `version`, `terraform_version`, `serial`, `lineage`, `outputs`, `resources`, `check_results`). The `lineage` is a permanent unique ID — critical when migrating state between backends. Functions: mapping, efficiency, change management.

## Key Concepts
- **tfvars files**: separate variable *values* from definitions; `terraform apply -var-file="dev.tfvars"` per environment; a common layout is `environments/{dev,staging,prod}/{main.tf,*.tfvars}`.
- **`TF_VAR_name` environment variables**: inject values without files — the preferred channel for sensitive inputs.
- **Undeclared variables behavior**: env vars → silently accepted; `.tfvars` → warning (catches typos; `-compact-warnings` to simplify); CLI `-var` → error.
- **Local values** (`locals {}` block, referenced `local.<name>`): named expressions reused within a module — used moderately, they centralize updates; overused, they obscure actual values.
- **Workspaces** (`terraform workspace new/select <name>`): multiple environments from one configuration, each with own state file (e.g. `gs://bucket/terraform/state/default/`).
- **State locking**: remote backends lock the state file during operations so concurrent applies can't conflict; a leftover lock is cleared with `terraform force-unlock LOCK_ID` — only when certain no one else holds it.
- **Reserved variable names**: `source`, `version`, `providers`, `count`, `for_each`, `lifecycle`, `depends_on`, `locals` cannot name meta-arguments.

## Mental Models
- Variables are function arguments for your module; outputs are its return values; locals are function-local temporaries.
- Backends are "safe deposit boxes for your infrastructure": multi-user safety, change history, and disaster-recovery-ready state.
- Reach for `depends_on` only when Terraform *can't see* the ordering — every reference-based edge you add manually is one you'll maintain.
- Treat `terraform graph -type=plan | dot -Tpng > graph.png` as the dependency X-ray when ordering questions arise.

## Code Examples
Variable with validation, sensitivity, nullability:
```hcl
variable "machine_type" {
  description   = "The type of GCP machine to use for the instances"
  type          = string
  default       = "e2-medium"
  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "The machine type must be one of 'e2-micro', 'e2-small', or 'e2-medium'."
  }
}
variable "user_name" {
  type      = string
  nullable  = false
  sensitive = true
}
```
Explicit dependency (firewall before database):
```hcl
resource "google_compute_firewall" "allow_sql_access" {
  name          = "allow-sql-access"
  network       = "default"
  allow { protocol = "tcp"  ports = ["3306"] }
  source_ranges = ["0.0.0.0/0"]  # Adjust this to restrict access
}
resource "google_sql_database_instance" "my_database" {
  name             = "my-database"
  database_version = "POSTGRES_14"
  region           = "us-west1"
  depends_on       = [google_compute_firewall.allow_sql_access]
}
```
Module wiring (child outputs → parent inputs = module dependency):
```hcl
# vpc_module exports
output "vpc_network"  { value = google_compute_network.main.name }
output "subnet_name"  { value = google_compute_subnetwork.public.name }
# webserver_module consumes
variable "vpc_network" { type = string }
resource "google_compute_instance" "web_server" {
  name         = "my-web-server"
  machine_type = "e2-micro"
  network_interface {
    network    = var.vpc_network
  }
}
```
Remote backend (GCS):
```hcl
terraform {
  backend "gcs" {
    bucket = "my-terraform-state-bucket"
    prefix = "terraform/state"
  }
}
```
State snapshot (empty): `{"version": 4, "terraform_version": "1.5.7", "serial": 25, "lineage": "d09d80a0-...", "outputs": {}, "resources": [], "check_results": null}` — read `serial` (every-save counter) and `lineage` (permanent identity) when debugging remote state issues.

## Reference Tables
| Variable block argument | Purpose |
|---|---|
| `description` | human-readable explanation (always set it) |
| `type` | constrains values: primitives `string/number/bool`; complex `list/set/map/object/tuple`, `any` |
| `default` | value when unset — reduces required inputs |
| `validation { condition / error_message }` | rule beyond type constraint |
| `nullable` | whether `null` is allowed (default: yes) |
| `sensitive` | masks value in CLI output & logs |

| Output block optional arguments | Effect |
|---|---|
| `value` | the expression exposed |
| `description` | docs for consumers |
| `sensitive` | mask in display |
| `condition` | expose only if true |
| `depends_on` | force ordering |

| State storage | Pros | Cons | Use when |
|---|---|---|---|
| Local | zero setup, inspectable | no conflict resolution, no auto-backup, weaker security | solo users, experimentation |
| Remote (GCS/S3/Azure/Consul/TFC) | single source of truth, locking, encryption, backups | config + storage cost | teams & larger projects (**preferred**) |

## Worked Example
Building the `gcp_storage_bucket` module from scratch (the chapter's hands-on): create `main.tf` (bucket resource with `lifecycle_rule` `{age-driven Delete}` and `versioning {}` passed through vars), `variables.tf` (9 variables: `credentials_file_path`*, `project_id`*, `region` default `us-west1`, `bucket_name`*, `location` default `US`, `storage_class` default `STANDARD`, `lifecycle_age` default `30`, `versioning` default `false`, `labels` default `{}`), `outputs.tf` (`bucket_name`, `bucket_self_link`, `bucket_url`), `providers.tf` (google 5.38.0; `credentials = file(var.credentials_file_path)`), and a `README.md` documenting inputs (Type/Default/Required table) and outputs. That inputs/outputs table *is* the module's contract — publish it with the module.

## Anti-patterns
- **Omitting `type` on variables**: untyped variables accept anything → unpredictable behavior; always constrain.
- **Locals sprawl**: defining a local for every value hides what the infrastructure actually is — use only for frequently-reused or frequently-changing expressions.
- **Hard-coding project IDs/regions in every block**: one drift-induced inconsistency and your resources land in different projects/regions; define once (`locals` or variable) and reference.
- **Force-unlock as routine fix**: unlocking while another operation holds the lock risks conflicts or corruption — verify the lock is stale first.
- **Local state in teams**: no conflict resolution, no backups, weaker security — the direct cause of "someone applied over my work."

## Key Takeaways
1. Pick providers by badge: Official > Partner > Community, and treat Archived as a red flag.
2. Type + validation every variable; route secrets through `TF_VAR_*` env vars, not files.
3. One `.tfvars` file per environment (`-var-file="dev.tfvars"`) beats copy-edited core configs.
4. Prefer implicit dependencies; use `depends_on` only where Terraform can't infer ordering.
5. Remote backend + state locking is the default for anything collaborative; `lineage` identifies a state file forever, `serial` tracks each change.
6. `terraform force-unlock LOCK_ID` only for confirmed-stale locks.

## Connects To
- **Ch 2**: providers/variables/modules were introduced in skeleton form here; this chapter gives them the full treatment.
- **Ch 4**: applies concepts hands-on to GCP — remote state in Cloud Storage, compute instances, VPCs, Cloud SQL, GKE.
- **Ch 5**: deepens state security (encryption, access control) and secrets discipline.