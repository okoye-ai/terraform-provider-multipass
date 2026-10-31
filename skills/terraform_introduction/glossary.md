# Glossary

**Ansible** — open-source agentless configuration-management / app-deployment tool using YAML playbooks; Terraform's pair for software configuration (Ch 1, Ch 20)

**Backend** — service Terraform uses to store state, e.g. S3, Google Cloud Storage, Terraform Cloud (Ch 6)

**Block** — basic HCL structure: type, optional identifier, and a `{}` body (Ch 5)

**CI/CD** — automation of the Terraform lifecycle; the pipeline runs init → validate/plan → apply (Ch 16)

**Compliance as code** — compliance rules defined and enforced programmatically, e.g. via Sentinel (Ch 17)

**`terraform console`** — interactive expression evaluation for debugging values (Ch 19)

**Data source** — read-only Terraform resource, e.g. `data "vault_generic_secret"` for reading secrets (Ch 17, Ch 18)

**Declarative vs procedural** — Terraform takes the desired state (what); Ansible-like tools take steps (how) (Ch 1, Ch 2)

**Dynamic block** — constructs repeatable nested blocks from a collection via `dynamic` + `for_each`/`count` (Ch 10)

**`terraform fmt`** — built-in command that canonicalizes config formatting and keeps diffs clean (Ch 9)

**Import** — command to bring existing, externally created resources into Terraform state; requires a pre-written config block (Ch 11)

**Immutable infrastructure** — replacing resources instead of modifying them; Terraform's model (Ch 2)

**Local state** — default `terraform.tfstate` on disk; fine solo, unsafe for teams (Ch 6)

**Locals** — named expressions (`locals` block / `local.<name>`) for DRY reuse of computed values (Ch 10)

**`TF_LOG` / `TF_LOG_PATH`** — environment variables controlling Terraform's log level and output file (Ch 19)

**Masterless architecture** — Terraform runs from any machine or CI; no master node (unlike Chef/Puppet) (Ch 2)

**Module** — container for multiple related resources; like a function: inputs (variables) → resources → outputs (Ch 7)

**Module registry** — public Terraform Registry, or Terraform Cloud's private registry, for sharing modules (Ch 7, Ch 8)

**Output** — extraction of resource attribute values from a config, like a return value (Ch 5)

**`terraform plan`** — execution plan previewing what Terraform will do before changes; supports `-out=tfplan` (Ch 4, Ch 16)

**Provider** — plugin bridging Terraform and a platform's API (e.g. aws, digitalocean, google, kubernetes, vault) (Ch 4)

**Provisioner** — runs scripts as part of resource creation/destruction: `file`, `local-exec`, `remote-exec` (Ch 20)

**Resource** — a piece of infrastructure declared in a block, e.g. `resource "digitalocean_droplet" "web"` (Ch 4)

**Sentinel** — HashiCorp's embedded policy-as-code framework; inspects `tfplan` and blocks non-compliant runs (Ch 8, Ch 17)

**Serverless** — cloud function resources (AWS Lambda, Google Cloud Functions, Azure Functions) declared like any other resource (Ch 14)

**State (`terraform.tfstate`)** — JSON file mapping config to real-world resources; Terraform's source of truth (Ch 6)

**State locking** — prevents concurrent state-modifying runs; local (lock file) vs remote (backend) locking (Ch 6, Ch 12)

**State versioning** — automatic state snapshots on each apply, on supporting backends; enables rollback (Ch 12)

**`.tfvars`** — variable definition files selected per environment via `-var-file` (Ch 9)

**`terraform validate`** — pre-apply check for configuration/variable errors (Ch 16, Ch 19)

**Vault** — HashiCorp's centralized secrets manager: secrets as a service, encryption, fine-grained policies (Ch 17, Ch 18)

**Variable** — input value declared with `variable` block, consumed as `var.<name>`, optionally supplied via `.tfvars` (Ch 5, Ch 9)

**Workspace** — unit of management in Terraform Cloud: a configuration plus its variables (Ch 8)