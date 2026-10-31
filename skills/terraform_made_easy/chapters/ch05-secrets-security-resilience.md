# Chapter 5: Managing Secrets, Enhancing Security, and Ensuring Resilience

## Core Idea
Terraform is the wrong *vault* but the right *plumber*: provision the infrastructure, access policies, and audit/monitoring around secrets — but keep secret *data* in dedicated services like Google Secret Manager, and secure state file as if it contains passwords (because it does).

## Frameworks Introduced
- **Secret Management Services (Secret Manager first)**: Terraform has no secret lifecycle (rotation/expiration/auditing) — the split of responsibilities: Terraform provisions secret *infrastructure and policies*; Secret Manager holds secret *data*.
  - Secret Manager features: version control per secret (roll back), IAM access control, encryption at rest & in transit, audit logging of every access.
  - Pattern: `google_secret_manager_secret` (identity + labels + replication) + `google_secret_manager_secret_version` (data) + `data.google_secret_manager_secret_version` to *read* secrets by other configs.
- **Encryption taxonomy**:
  - **At rest**: GMEK (Google-managed keys, default, zero config) vs **CMEK** (customer-managed via Cloud KMS — full key lifecycle control: creation, rotation, access permissions). Use CMEK for control/compliance requirements.
  - **In transit**: TLS/HTTPS, VPNs, Dedicated Interconnect.
  - CMEK wiring = `google_kms_crypto_key_iam_member` (grant `roles/cloudkms.cryptoKeyEncrypterDecrypter` to the Secret Manager service agent) + `replication { auto { customer_managed_encryption { kms_key_name = ... } } }` — the reference creates the implicit dependency.
- **Secret version lifecycle meta-arguments**:
  - `ttl = "24h"` — relative auto-deletion after creation;
  - `expire_time = "2024-10-31T23:59:59Z"` — absolute timestamp (precise, independent of creation time);
  - `timeouts { delete = "15m" }` — per-operation caps;
  - `lifecycle { create_before_destroy = true }` / destroy operation for permanently removing versions.
- **IAM/RBAC enforcement**: **IAM Policies** (who + role + resource) → **Roles** (Basic Owner/Editor/Viewer vs Predefined vs Custom) → **Bindings** (member ↔ role) → **Principals** (users, groups, service accounts). Principle of least privilege as the stated rule throughout.
  - Least-privilege ladder for BigQuery: `dataViewer` → `dataEditor` → `dataOwner`.
- **Secure remote state checklist (7 items)**: remote backend (never local in teams) → encryption at rest + transit → access controls/RBAC on state → state locking → versioning & backups → audit/monitor access.

## Key Concepts
- **State file sensitivity**: state stores resource attributes *including secrets* — anyone with state read access can retrieve credentials; encrypt + lock + control access.
- **Inappropriate secret storage (the chapter's list)**: hard-coding in configs (exposed via VCS/sharing), plain text in `.tfvars` (unsecured sharing), state-file storage unsecured.
- **ADC**: `gcloud auth application-default login` generates Application Default Credentials; read a secret: `gcloud secrets versions access latest --secret="my-secret"`.
- **Data sources over hard-coding**: `data "google_sql_database_instance"`, `data "google_firestore_database"`, and `data "external"` (JSON-returning scripts via `${path.module}/scripts/...`) to fetch existing resources/member lists — recommended especially for PII: "avoid hard-coding values in .tfvars".
- **IAM condition expressions**: CEL `condition { expression = "resource.name.startsWith('${...name}')" }` for conditional granular access.
- **DR stack**: DR = restore strategies after disruptive events; backups = scheduled copies. GCP tools: Compute Engine disk snapshots, Cloud Storage (lifecycle rules), Cloud SQL automated backups + point-in-time recovery, Cloud DNS failover.
- **Auditing vs monitoring**: auditing = who did what when (Cloud Audit Logs; export via `google_logging_project_sink` to BigQuery); monitoring = health/performance (Cloud Monitoring alert policies with thresholds + notification channels).

## Mental Models
- Terraform manages the *container*, Secret Manager manages the *contents* — split roles this way and rotation stops being your problem.
- Use GMEK by default; reach for CMEK when a compliance requirement names *your* key lifecycle, not Google's.
- Think of state files as plain-text password stores: apply the same lock/backup/audit policy as a database.
- Least privilege is a direction, not a state: bind roles per dataset/service-account (`_iam_member`, not project-wide), and tighten with conditions when the role alone is too broad.

## Code Examples
Create + access a secret (with multi-region replication):
```hcl
variable "secret_data" {
  description = "The sensitive data to be stored in Secret Manager"
  type        = string
  sensitive   = true
}
resource "google_secret_manager_secret" "my_secret" {
  secret_id = "my-secret"
  labels    = { environment = "production", version = "v1" }
  replication {
    user_managed {
      replicas { location = "us-central1" }
      replicas { location = "us-west1" }
    }
  }
}
resource "google_secret_manager_secret_version" "my_secret_version" {
  secret      = google_secret_manager_secret.my_secret.id
  secret_data = var.secret_data
}
```
- **What it demonstrates**: secret (identity) vs secret_version (data) split; sensitive variable feeding it; user-managed replication.
Read a secret dynamically instead of hardcoding:
```hcl
data "google_secret_manager_secret_version" "db_password" {
  secret  = "projects/my-project/secrets/db-password"
  version = "latest"
}
```
CMEK for a secret:
```hcl
resource "google_kms_crypto_key_iam_member" "kms-secret-binding" {
  crypto_key_id = "projects/your-project-id/locations/global/keyRings/your-key-ring/cryptoKeys/your-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}
resource "google_secret_manager_secret" "secret-with-automatic-cmek" {
  secret_id   = "my-secret"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key_iam_member.kms-secret-binding.crypto_key_id
      }
    }
  }
}
```
Departmental IAM with conditions (worked scenario, abridged):
```hcl
resource "google_sql_database_instance_iam_member" "department2_editor_sql_db_1" {
  for_each = toset(data.external.department2_members.result["members"])
  instance = data.google_sql_database_instance.sql_db_1.name
  role     = "roles/cloudsql.editor"
  member   = "user:${each.value}"
  condition {
    title       = "Department 2 editor access to SQL DB 1"
    expression  = "resource.name.startsWith('${data.google_sql_database_instance.sql_db_1.name}')"
  }
}
```
Backups: disk snapshot with timestamp + backup bucket with lifecycle:
```hcl
resource "google_compute_snapshot" "app_disk_snapshot" {
  name       = "app-disk-snapshot-${timestamp()}"
  source_disk       = google_compute_disk.app_disk.id
  storage_locations = ["us"]
  labels            = { environment = "production" }
}
resource "google_storage_bucket" "backup_bucket" {
  name          = "my-backup-bucket"
  location      = "us"
  storage_class = "STANDARD"
  versioning { enabled = true }
  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 30 }   # auto-delete 30-day-old backups
  }
}
```
Audit logs → BigQuery sink:
```hcl
resource "google_logging_project_sink" "audit_logs_sink" {
  name        = "audit-logs-sink"
  project     = "my-project-id"
  filter      = "logName:\"/logs/cloudaudit.googleapis.com%2Factivity\""
  destination = "bigquery.googleapis.com/projects/my-project-id/datasets/my_dataset"
}
```
Monitoring alert (CPU > 80% avg for 60s) + general threshold pattern:
```hcl
resource "google_monitoring_alert_policy" "high_cpu_usage" {
  display_name = "High CPU Usage"
  conditions {
    display_name = "CPU usage"
    condition_threshold {
      filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      duration        = "60s"
      threshold_value = 0.8
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  combiner = "OR"
  enabled  = true
}
```
DNS failover: `google_dns_managed_zone` + `google_dns_record_set` (ttl 300, primary + secondary `rrdatas` from each instance's `nat_ip`) + `google_compute_health_check` (`/healthz`, port 80) + DNS policy — traffic auto-redirects to the secondary region when the primary fails.

## Reference Tables
| Secret storage decision | Verdict |
|---|---|
| Hard-coded in `.tf` | ❌ version control exposure |
| Plain text in `.tfvars` | ❌ acceptable only if files secured; prefer env vars/secrets mgr |
| `TF_VAR_*` env var | ✅ for passing values into Terraform |
| Secret Manager + data source | ✅✅ store & retrieve dynamically |
| State file read access | treat as secret exposure — encrypt/lock/audit |

| Encryption choice | When |
|---|---|
| GMEK | default for everything (zero config) |
| CMEK (KMS) | compliance/rotation control requirements |
| In transit | TLS/HTTPS everywhere; VPN/Interconnect for network links |

| Least-privilege roles ladder (BigQuery) | Grants |
|---|---|
| `roles/bigquery.dataViewer` | view metadata, query — no modify |
| `roles/bigquery.dataEditor` | read + modify + manage permissions |
| `roles/bigquery.dataOwner` | full control incl. deletion |

| Remote state hardening | Practice |
|---|---|
| Backend | remote always for teams |
| Encryption | at rest + in transit |
| Access | IAM roles/RBAC, not "full access to all" |
| Locking | enabled (backends manage it) |
| Version/backup | bucket versioning + regular backups |
| Audit | log & monitor state access |

## Worked Example
The granular-access scenario: three departments, three databases (SQL 1, SQL 2, Firestore). Requirements table: Dept 1 = view both SQL DBs; Dept 2 = edit SQL DB 1 only; Dept 3 = full admin on SQL DB 2 + Firestore. Implementation: never hard-code member lists (PII) — `data "external"` scripts fetch each department's members as JSON; `data` sources fetch the DB instances; then per-department `_iam_member` resources with `for_each = toset(...members)`, role ladder (`cloudsql.viewer` / `cloudsql.editor` / `cloudsql.admin`, `datastore.owner`), and CEL conditions restricting to the right resource names. The reusable idea: *departmental requirements table → role ladder + condition expressions with dynamically fetched members*.

## Anti-patterns
- **Hard-coding secrets** anywhere in configs — VCS exposure, accidental sharing.
- **Securing state as if it's just metadata**: secrets land in state through resource attributes; an unsecured state file is a credential dump.
- **Expecting Terraform to rotate secrets**: rotation/expiration/auditing belong to a secret manager, not Terraform.
- **Project-wide roles over targeted bindings**: granting broad basic roles (Owner/Editor/Viewer) when a `_iam_member` binding with a predefined role + condition would do.
- **Hard-coding member lists/PII in tfvars**: fetch via data sources instead.
- **Backups without retention rules**: unbounded backup buckets grow costs; use lifecycle rules (`age = 30` → Delete).

## Key Takeaways
1. Separate secret storage (Secret Manager) from secret infrastructure provisioning (Terraform) — and `sensitive = true` on the variables that carry data into secret versions.
2. Know the three inappropriate storage ways (hard-code, plain-text tfvars, unsecured state) — and that state is the sneaky one.
3. Wire CMEK with two resources: the KMS IAM member for the service agent, then the replication block referencing its key.
4. Give secret versions a death date (`ttl` for relative, `expire_time` for absolute) — secrets shouldn't live forever.
5. Least privilege via predefined service roles (`roles/cloudsql.viewer`, `roles/bigquery.dataViewer`...) bound per resource, tightened with IAM conditions.
6. Resilience = backups (snapshots, versioned buckets with lifecycle rules) *plus* failover (DNS + health checks) — not one or the other.
7. Automate auditing (`logging_project_sink`) and monitoring (`alert_policy` with threshold/duration/channel) alongside the infra they protect.

## Connects To
- **Ch 4**: extends the Cloud SQL secrets pitfall into a full discipline; `sensitive` variables and `.tfvars` separation both reappear.
- **Ch 3**: the remote-state checklist operationalizes state concepts (backends, locking) security-wise.
- **Ch 6**: monitoring/auditing here sets up testing and CI/CD automation as the operational layer.