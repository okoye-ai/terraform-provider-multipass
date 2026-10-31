# Chapter 3: How to Manage Terraform State

## Core Idea
Terraform persists a mapping from your configuration's resources to real-world infrastructure in a state file; to use Terraform as a team you must move that state to a shared, locked, encrypted remote backend — and then isolate state per environment and per component so a mistake in one place cannot break everything.

## Frameworks Introduced

### 1. Remote Backends
- **What:** A backend determines how Terraform loads/stores state. Default is `local` (file on disk); remote backends (S3, Azure Storage, Google Cloud Storage, Terraform Cloud/Enterprise) store state in a shared store.
- **When to use:** Any team usage of Terraform on a real product. For AWS, S3 is typically the best bet (managed, 11-nines durability, encryption at rest/in transit, locking via DynamoDB, versioning, cheap).
- **How:** Declare a `terraform { backend "<NAME>" { ... } }` block, then run `terraform init`, which prompts to migrate existing local state into the backend. Backends are applied automatically: pull latest state before plan/apply, push after apply, acquire/release lock around apply.
- **Remote backends solve the three team problems:** manual error (automatic pull/push, no stale-state pushes), locking (native lock acquisition; `-lock-timeout=<TIME>` to wait, e.g. `-lock-timeout=10m`), secrets (encryption in transit and at rest, plus IAM-style access control).

### 2. State Locking
- **When to use:** Always, once state is shared. Prevents race conditions / state corruption from concurrent applies.
- **How:** With S3 backend, set `dynamodb_table` pointing at a DynamoDB table whose hash key is exactly `LockID` (type "S"). Terraform acquires the lock before apply and releases it after (`Acquiring state lock...` / `Releasing state lock...`).

### 3. Isolation via Workspaces
- **What:** `terraform workspace new/list/select/show` stores multiple named state files for the *same* configuration (S3 stores them under `env:/<workspace>/<key>`); switching workspace = changing the state file path. `terraform.workspace` expression lets config branch on workspace name.
- **When to use:** Quick, isolated experiments/tests on the same module (e.g. try a refactor against a copy of the infra) without touching deployed state.
- **Never use for:** isolating staging from production — all workspaces share one backend, one auth mechanism, and are invisible in code/terminal, so they are error-prone with no second layer of defense.

### 4. Isolation via File Layout (bulkheads)
- **What:** Separate folders (thus separate state files) per environment *and* per component, plus a separate backend per environment (ideally separate AWS accounts / S3 buckets / auth).
- **When to use:** All production use cases needing strong environment separation.
- **Rationale:** Like ship bulkheads — a leak in staging must not flood production. Isolate further to component level because change frequency differs (VPC changes monthly; web servers deploy daily — never risk the network topology on every app deploy).

### 5. Partial Backend Configurations
- **What:** Backend blocks cannot use variables/references (`backend "s3" { bucket = var.bucket }` is invalid), forcing copy-paste. Partial configs let you omit params in code and supply them at init time.
- **How:** Keep only `key` in the module's `terraform` block; put shared args in `backend.hcl`; run `terraform init -backend-config=backend.hcl`. Terraform merges the two. Alternative: **Terragrunt**, which keeps backend config DRY and auto-sets `key` from the module's folder path.

### 6. terraform_remote_state Data Source
- **What:** A read-only data source that fetches the *outputs* of another Terraform configuration's state file.
- **When to use:** Cross-component wiring when components live in separate folders/state files (e.g. webserver cluster needs the MySQL address/port from `stage/data-stores/mysql`).
- **How:** `data "terraform_remote_state" "db" { backend = "s3" config = { bucket, key, region } }`; read via `data.terraform_remote_state.<NAME>.outputs.<ATTRIBUTE>`. Read-only, so it can't damage the remote component.

## Key Concepts
- **Terraform state file** (`terraform.tfstate`): custom JSON mapping config resources to real-world resource IDs (e.g. `aws_instance.example` → `i-0bc4bbe5b84387543`); it is what lets `plan` diff code vs. reality.
- **Backend**: the mechanism that determines where/how state is loaded and stored; default `local`, configurable via the `terraform` block.
- **State locking**: mutual exclusion around state mutation, preventing concurrent applies from corrupting state.
- **Workspace**: a named, isolated state file for one configuration; `default` is the initial one; workspace state is never visible from other workspaces.
- **Environment vs component**: environment = stage/prod/mgmt/global top-level folder; component = a coherent set of resources usually deployed together (vpc, services, data-storage).
- **`prevent_destroy`**: lifecycle setting that makes any destroy of the resource error out — used to protect the state bucket.
- **State file versioning**: storing every revision of the state (S3 bucket versioning) so you can roll back after a bad apply.
- **`terraform.workspace`**: expression returning the current workspace name, usable for conditional config (e.g. bigger instance in `default`).
- **`templatefile(<PATH>, <VARS>)`**: built-in function rendering a file as a template with `${...}` interpolation against the VARS map — used to externalize User Data scripts.
- **`TF_VAR_<name>`**: environment variable convention for supplying input variable values (kept out of code/state-adjacent files for secrets).

## Mental Models
- **Plan is a three-way diff**: `plan` output = diff between your code and the real world, discovered via IDs in the state file. Use this when debugging "why does Terraform want to change X" — check what state says the resource is.
- **State as private API**: never hand-edit state or parse it with your own code; only touch it via `terraform import` / `terraform state` commands. Use when you "must" manipulate state.
- **Bulkheads**: environments/components are compartments; isolation exists so a leak in one compartment doesn't sink the ship. Use this to justify separate folders, backends, and accounts even at the cost of convenience.
- **Chicken-and-egg bootstrapping**: Terraform code that creates its own state store requires a two-step deploy (create bucket with local backend → add backend block → `terraform init` to migrate). Reverse both steps to tear down. One-time cost per account since the bucket/table can be shared by all Terraform code.

## Anti-patterns
- **Storing state in version control (Git):** three failure modes — manual error (running Terraform with stale local state and rolling back/duplicating deployments), no locking (two concurrent applies corrupt state), and plain-text secrets (e.g. `aws_db_instance` stores DB username/password in state).
- **Editing the state file by hand** or writing code that reads `terraform.tfstate` directly.
- **One single state file for everything:** one mistake or one corrupted state breaks all environments; deploying staging can break production.
- **Workspaces for prod/staging isolation:** shared backend and credentials, invisible in code, easy to run `destroy` against the wrong environment with nothing to stop you.
- **Reusing the same backend `key` across modules:** overwrites another module's state. Every module must have a unique `key`.
- **Hardcoding DB credentials in code** instead of `sensitive = true` variables fed via `TF_VAR_` env vars.
- **Inlining long Bash User Data in HCL** — embedding one language in another is hard to maintain; use `templatefile`.

## Code Examples
S3 backend with locking (the canonical backend block — no variables allowed inside):
```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-up-and-running-state"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}
```

Partial configuration: only unique-per-module `key` stays in code; shared args go in `backend.hcl`.
```hcl
# Partial configuration. The other settings (e.g., bucket, region) will be
# passed in from a file via -backend-config arguments to 'terraform init'
terraform {
  backend "s3" {
    key = "example/terraform.tfstate"
  }
}
```
```bash
$ terraform init -backend-config=backend.hcl
```

DynamoDB lock table — hash key must be exactly `LockID`:
```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-up-and-running-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

Key protections on the state bucket: `lifecycle { prevent_destroy = true }` on `aws_s3_bucket`; `aws_s3_bucket_versioning` with `status = "Enabled"`; `aws_s3_bucket_server_side_encryption_configuration` with `sse_algorithm = "AES256"`; `aws_s3_bucket_public_access_block` with all four flags `= true`.

Reading another component's state (read-only):
```hcl
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = "(YOUR_BUCKET_NAME)"
    key    = "stage/data-stores/mysql/terraform.tfstate"
    region = "us-east-2"
  }
}
# usage: data.terraform_remote_state.db.outputs.address
```

Workspace-conditional sizing:
```hcl
resource "aws_instance" "example" {
  ami           = "ami-0fb653ca2d3203ac1"
  instance_type = terraform.workspace == "default" ? "t2.medium" : "t2.micro"
}
```

## Reference Tables

### Isolation strategies
| Strategy | Mechanism | When to use | Drawbacks |
|---|---|---|---|
| Workspaces | Multiple named state files for one config (S3: `env:/<ws>/<key>`) | Quick tests/experiments on the same already-deployed module | Same backend + same auth for all; invisible in code/terminal; error-prone; **not for env isolation** |
| File layout | Folder per environment per component → separate state + backend per env (ideally separate AWS accounts) | Production-grade env isolation | Multiple `terraform apply` runs (fix: Terragrunt `run-all`); copy-paste across envs (fix: modules, Ch. 4); hard cross-folder refs (fix: `terraform_remote_state` / Terragrunt dependencies) |
| `terraform_remote_state` data source | Read-only consumption of another config's outputs | Wiring components across state files | Requires outputs in the source; must know bucket/key |

### Version control vs remote backend for state
| Concern | State in Git | Remote backend (S3) |
|---|---|---|
| Stale state / manual error | Likely (forget to pull/push) | Eliminated by automatic pull/push |
| Locking | None | Native (DynamoDB) |
| Secrets | Plain text in repo history | Encrypted at rest (AES-256) & in transit (TLS); IAM access control |
| Rollback | Git history of state | S3 bucket versioning |

### File naming conventions (per component folder)
| File | Contents |
|---|---|
| `variables.tf` | Input variables |
| `outputs.tf` | Output variables |
| `main.tf` | Resources & data sources |
| `dependencies.tf` | All `data` sources (optional, shows external deps) |
| `providers.tf` | Provider blocks (optional, shows auth surface) |
| `main-<xxx>.tf` | Split oversized main.tf (e.g. `main-iam.tf`); or split into modules |

## Worked Example
The recommended repo layout with state isolation:

```
.
├── global/
│   └── s3/                      # state bucket + DynamoDB lock table
│       ├── main.tf, variables.tf, outputs.tf
│       └── backend key: global/s3/terraform.tfstate
└── stage/
    ├── services/
    │   └── webserver-cluster/   # backend key: stage/services/webserver-cluster/terraform.tfstate
    │       ├── user-data.sh
    │       └── main.tf, variables.tf, outputs.tf
    └── data-stores/
        └── mysql/               # backend key: stage/data-stores/mysql/terraform.tfstate
            └── main.tf, variables.tf, outputs.tf
```

How it fits together:
1. **Bootstrap** (`global/s3`, local backend first): create `aws_s3_bucket` (+`prevent_destroy`, versioning, AES-256 SSE, public access block) and `aws_dynamodb_table` with `LockID` hash key. Then add the `backend "s3"` block and run `terraform init`, answering "yes" to migrate state.
2. **Database** (`stage/data-stores/mysql`): `aws_db_instance` (MySQL, `db.t2.micro`, `skip_final_snapshot = true`) with `sensitive = true` `db_username`/`db_password` variables (no defaults) fed via `export TF_VAR_db_username=...` / `TF_VAR_db_password=...`; outputs `address` and `port`; backend key mirrors the folder path.
3. **Webserver** (`stage/services/webserver-cluster`): `data "terraform_remote_state" "db"` points at the mysql state path; User Data externalized to `user-data.sh` and rendered with `templatefile("user-data.sh", { server_port = var.server_port, db_address = data.terraform_remote_state.db.outputs.address, db_port = data.terraform_remote_state.db.outputs.port })`; `aws_launch_configuration` keeps `lifecycle { create_before_destroy = true }`.
4. **Convention:** the backend `key` always equals the folder path of the code — a 1:1 mapping between version control and state files in S3 makes the connection obvious and prevents key collisions.
5. `prod/` mirrors `stage/` with its own folders (ideally own account/backend); the duplicated resource code is DRYed up with modules in Chapter 4.

## Key Takeaways
- State is Terraform's private mapping of config → real-world IDs; treat `terraform.tfstate` as a private API — never hand-edit or parse it; use `terraform import`/`terraform state` (Ch. 5).
- Never store state in Git: stale-state mistakes, no locking, and plain-text secrets. Use a remote backend; for AWS, S3 + DynamoDB locking + `encrypt = true` + bucket versioning.
- Bootstrap the state store in two steps (deploy with local backend, then add backend block and `terraform init` to migrate) — and share one S3 bucket/DynamoDB table across all your Terraform code (once per account).
- Backend blocks can't reference variables; reduce copy-paste with partial configs (`terraform init -backend-config=backend.hcl`) keeping only unique `key`s in code, or with Terragrunt.
- Use workspaces only for disposable experiments on the same module; use folder-based isolation (separate env + component folders, separate backends/accounts) for staging-vs-production.
- Make every backend `key` unique and mirror the code's folder path — a wrong shared `key` silently overwrites another module's state.
- Wire components across folders with the read-only `terraform_remote_state` data source (`data.terraform_remote_state.<NAME>.outputs.<ATTR>`); externalize User Data with `templatefile`; probe functions/state with `terraform console` (read-only). IaC bugs are more severe than app-code bugs, so add more safety mechanisms deliberately.

## Connects To
- **Ch. 2** provided the web server cluster code reorganized here; introduced the first lifecycle setting `create_before_destroy` (this chapter adds `prevent_destroy`).
- **Ch. 4** solves the copy-paste drawback of the file layout with Terraform modules.
- **Ch. 5** covers `terraform import` / `terraform state` for legitimate state manipulation, ternary/conditional logic (e.g. `terraform.workspace == "default" ? ... : ...`), and secure secret handling.
- **Ch. 6** covers proper secrets management; the `TF_VAR_` env var + password-manager approach here is the stopgap.
- **Ch. 10** covers Terragrunt (`run-all`, `dependency` blocks, DRY backend config) as the tool-level fix for multi-folder limitations.