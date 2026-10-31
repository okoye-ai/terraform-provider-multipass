# Glossary — Terraform Cookbook (Husain)

**Advisory policy** — Sentinel enforcement level where a failed policy only logs a warning; the run proceeds (Ch 16).

**Backend** — Configuration block defining where Terraform stores state; `backend "remote"` (Terraform Cloud/HCP) uniquely both stores state and executes runs remotely (Ch 3, Ch 16).

**Chef's Special project** — The book's recurring end-of-chapter construct combining the chapter's recipes into one enterprise-grade implementation, structured as Appetizer → Main course → Dessert (all chapters).

**Data source** — Read-only Terraform query of an existing provider attribute; used to break dependency cycles and fetch external facts without creating a dependency edge (Ch 8, Ch 10, Ch 14).

**Dependency cycle** — Circular wait between two resources Terraform cannot order; surfaces as `Error: Cycle: <resource a>, <resource b>` (Ch 14).

**Drift** — Divergence between real infrastructure and Terraform-configured state; detected by plan, resolved by either enforce (`apply`) or accept (`apply -refresh-only`) (Ch 3, Ch 13).

**Dynamic block** — HCL construct that generates nested blocks (e.g. repeated `ingress` rules) from a list/map, avoiding copy-paste repetition (Ch 10).

**Hard-mandatory policy** — Sentinel enforcement level whose failure immediately halts the run with no override permitted (Ch 16).

**HCL** — HashiCorp Configuration Language, Terraform's declarative configuration language (Ch 1).

**Import-first adoption** — Pattern of bringing pre-existing resources under Terraform management with `terraform import` instead of recreating them (Ch 3, Ch 14).

**Lock file (`.terraform.lock.hcl`)** — Records provider version checksums; teams commit it for reproducible builds — pick one policy and stick to it (Ch 3).

**Module** — Reusable configuration package with inputs/outputs; sourced from the public Registry, a private registry, or the local filesystem (Ch 4).

**Module version pinning** — Constraining module source with version ranges (e.g. `version = "~> 1.3"`) so upgrades are deliberate (Ch 4).

**null_resource** — Resource with no infrastructure attributes, used as a hook for provisioners/triggers, e.g. to execute external scripts (Ch 10).

**Policy as code** — Enforcing governance rules automatically before deployment; tools covered: Sentinel (Terraform Cloud/Enterprise) and Open Policy Agent with Rego in CI (Ch 13, Ch 16).

**Remote state** — Storing state in a shared backend (Azure Blob, S3, Terraform Cloud) with locking, enabling safe team collaboration (Ch 3).

**Run task** — Terraform Cloud hook that invokes an external tool (security check, approval gate) at pre-plan or pre-apply stages (Ch 16).

**Sentinel** — HashiCorp's policy-as-code framework; policies import `tfplan`, `tfconfig`, or `tfstate` scopes and are grouped in policy sets attached to workspaces or projects (Ch 13, Ch 16).

**Snowflake server** — A manually configured, one-of-a-kind server that cannot be reliably reproduced; the primary evil IaC eliminates (Ch 1).

**Soft-mandatory policy** — Sentinel level that blocks the run but can be overridden by a sufficiently privileged user (Ch 16).

**Speculative plan** — Terraform Cloud plan triggered on a pull request that previews changes without applying and never enters the run queue (Ch 16).

**State lock** — Backend-managed mutex ensuring only one process modifies state; interrupted runs can strand it (`Error acquiring the state lock`) (Ch 13, Ch 14).

**Sensitive variable/output** — Attribute flagging values as masked in CLI output, logs, and plan files; still present in state, so pair with `sensitive = true` and secure backends (Ch 3, Ch 13).

**Taint** — Mark a resource as broken so the next apply destroys and recreates it (Ch 14).

**Terragrunt / Terramate** — Third-party wrappers for multi-environment, DRY Terraform structures when default workspaces feel restrictive (Ch 15, Ch 16).

**TF_LOG / TF_LOG_PATH** — Environment variables controlling log verbosity (`INFO` → `DEBUG` → `TRACE`) and directing logs to a file (Ch 14).

**Terraform Cloud / HCP Terraform** — HashiCorp's managed collaboration platform: remote state with locking/versioning, remote runs, VCS integration, Sentinel policy enforcement, private module registry, RBAC (Ch 16).

**tfvars** — Variable assignment files (`terraform.tfvars`, `*.auto.tfvars`) holding environment-specific values; kept out of Git when they carry secrets (Ch 3, Ch 13).

**VCS-driven workflow** — Terraform Cloud mode where commits/PRs to a connected branch automatically trigger plans (and optionally applies) (Ch 16).

**Workspace** — Isolated container of state and variables. CLI workspaces switch within one backend; Cloud workspaces encapsulate state, variables, run history, and access control — Cloud workspaces are one-per-environment-per-component (Ch 9, Ch 16).

**Workspaces equation** — The book's sizing rule: configurations × environments = workspaces (Ch 16).