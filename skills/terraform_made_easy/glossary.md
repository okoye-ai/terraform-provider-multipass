# Glossary

**Backend (local)** — Terraform configuration block storing state on the local filesystem; setup-free but no multi-user safety (Ch 3).

**Backend (remote)** — State stored in services like GCS, AWS S3, Azure Blob Storage, Consul, or Terraform Cloud; preferred for teams: single source of truth, locking, encryption, backups (Ch 3, Ch 5).

**Basic roles** — GCP's prebuilt Owner/Editor/Viewer roles; broad, prefer predefined service roles for least privilege (Ch 5).

**Bindings** — IAM links associating a member (user/group/service account) with a role on a resource (Ch 5).

**CMEK (Customer-Managed Encryption Keys)** — Encryption keys managed by you via Google Cloud KMS; grants full key-lifecycle control for compliance requirements, as opposed to GMEK (Ch 5).

**Configuration drift** — Divergence between real infrastructure and recorded state, caused by undocumented manual changes; surfaced by `terraform plan` (Ch 1).

**Data source** — Fetches pre-existing information from the environment (`data "google_sql_database_instance"`, `data "external"`) instead of hard-coding; preferred for PII and existing resources (Ch 5).

**depends_on** — Meta-argument forcing explicit resource ordering when Terraform cannot infer it from references (Ch 3).

**Execution plan** — Terraform's preview of exact create/modify/destroy actions before applying; symbols `+` create, `~` modify, `-` destroy (Ch 1, Ch 2, Ch 4).

**GMEK (Google-Managed Encryption Keys)** — Google's default at-rest encryption, requiring no configuration (Ch 5).

**GCS backend** — Remote backend using Google Cloud Storage with native state locking and object versioning for state history (Ch 4).

**HCL (HashiCorp Configuration Language)** — Terraform's declarative, human-readable config language; structure of blocks → arguments → expressions; shared with Vault and Nomad (Ch 2).

**IAM Policy** — GCP access-control component specifying who gets what role on what resource; composed of roles + bindings (Ch 5).

**Implicit dependency** — Automatically detected ordering from resource references (e.g. a subnet referencing its VPC's `self_link`); always preferred over `depends_on` (Ch 3).

**Input variables** — Module parameters, analogous to function arguments; typed and validated in `variable` blocks (Ch 3).

**Ingress** — Kubernetes resource gateway routing external traffic to services via a backend (Ch 4).

**Labels** — GCP resource metadata key/value pairs (e.g. `environment`, `team`) for tracking and organization at scale (Ch 4).

**Lineage** — Permanent unique identifier of a state file, constant across saves; key when working with remote backends or migrating state (Ch 3).

**Local values** — Named expressions in a `locals` block, reused within a module like function-local temporaries; use moderately (Ch 3, Ch 4).

**Meta-arguments** — Special resource/module arguments: `count`, `for_each`, `providers`, `depends_on`, `lifecycle` (Ch 3, Ch 4).

**Module** — Reusable container of resources + variables + outputs; root module (working directory), child modules (called via `module` blocks), local vs published (registry/VCS) (Ch 2, Ch 3).

**RBAC (Role-Based Access Control)** — Access model assigning roles to principals for minimal necessary permissions (Ch 5).

**Remote state** — State stored in a remote backend; the default choice for collaborative work (Ch 3).

**Secret Manager** — GCP service centralizing secret data: version control, IAM access control, encryption, audit logging. Terraform provisions around secrets; Secret Manager stores them (Ch 5).

**Serial** — Incrementing counter increased with each state modification (Ch 3).

**Service account** — GCP identity for programmatic access used by applications/VMs; keys (JSON) authenticate it (Ch 4).

**State file** — JSON file (`terraform.tfstate`) mapping real resources to configuration; contains `version`, `terraform_version`, `serial`, `lineage`, `outputs`, `resources`, `check_results` (Ch 3).

**State locking** — Mechanism preventing concurrent operations on the same state; leftovers cleared with `terraform force-unlock LOCK_ID` only when verified stale (Ch 3, Ch 5).

**Terratest** — Go framework testing Terraform by provisioning real infrastructure and asserting on outputs (Ch 6).

**Terraform Registry** — Directory of publicly available providers (4,000+) and modules (17,000+): Official / Partner / Community / Archived tiers (Ch 3).

**.tfvars file** — File assigning values to declared variables; per-environment files combined with `-var-file` (Ch 3).

**tfvars + environment variables (`TF_VAR_`)** — Preferred channels for passing values, especially sensitive ones, without hardcoding (Ch 3, Ch 5, Ch 6).

**Workspaces** — Named state environments within one configuration; separate state per environment, managed via `terraform workspace new/select` (Ch 3).

**Worked critique checklist** — The Ch 4 improvement pass: no hard-coded secrets, no duplicated values, parameterized, labeled, complete backup config.