# Chapter 4: Provisioning Infrastructure on GCP

## Core Idea
Hands-on GCP provisioning: from a single Cloud Storage bucket to an event-driven pipeline and an advanced GKE cluster — with the Cloud SQL section explicitly teaching the code-review loop of *write → name pitfalls → improve* (parameterize, label, back up, restrict access).

## Frameworks Introduced
- **Plan-then-apply with saved plans**: `terraform plan -out=plan.out` then `terraform apply "plan.out"` — apply executes the *exact* reviewed plan without recomputation, guarding against infrastructure that changed between plan and apply.
- **Verification loop**: after every apply, confirm with `gcloud` describe commands (Console or CLI) — e.g. `gcloud storage buckets describe gs://<name>`, `gcloud compute instances describe <name> --zone=... --format="get(name,zone,status)"`.
- **Scaling three ways — choose by similarity**:
  - `count` = N of similar things (`count = length(var.bucket_names)`, name via `count.index`);
  - `for_each` = keyed variations (map/set; `each.key` / `each.value`) — preferred when instances differ;
  - **modules** = repeated distinct deployments of the same unit (call the same module twice with different vars).
- **Hardened remote-state bucket recipe**: GCS backend + `versioning { enabled = true }` (every state change preserved as a distinct version), `force_destroy = false` (no forced deletion with contents), `public_access_prevention = "enforced"`, `uniform_bucket_level_access = true`.

## Key Concepts
- **Provider `credentials`**: in GCP Cloud Shell, auth is automatic (credentials line commented out); outside it, point to a service-account key file — `credentials = file("path/to/key.json")`.
- **GCS backend**: `backend "gcs" { bucket = "..."; prefix = "terraform/state" }`; GCS integrates state locking natively and supports object versioning for state history.
- **Backend migration (local → remote)**: update config → `terraform init` (prompts to move state; answer `yes`) → re-run `init` to verify no re-prompt. Manual path: `terraform state pull > terraform.tfstate` then `terraform state push`. Prereqs: IAM access to the bucket; decrypt any custom-key-encrypted local state first.
- **State bucket ≠ workload bucket**: a dedicated bucket holds the state (create via `gcloud storage buckets create gs://...` or via Terraform itself).
- **Custom vs default VPC**: GCP's default auto-mode VPC preconfigures subnets/firewalls but locks you out of subnet placement, IP ranges, and firewall customization; a **custom VPC** (`auto_create_subnetworks = false`) gives granular control of subnets, CIDRs, firewalls, routes, VPNs, tunnels.
- **Resource hierarchy**: network is an implicit dependency of subnets — Terraform orders it automatically; the apply log makes the ordering visible.
- **Labels**: GCP resource metadata (`user_labels = { environment = "production", team = "devops" }`) for tracking/organization in large environments — added *in the improvement pass* of the Cloud SQL example.
- **`lifecycle { prevent_destroy = true }`**: Terraform-level protection against accidental deletion of the database instance.
- **Cloud SQL HA modes**: `availability_type = "ZONAL"` (default single zone) vs `"REGIONAL"`; a replica is declared by pointing `master_instance_name` at the primary.

## Mental Models
- Reach for `count` when replicating identical resources; `for_each` when each instance is individually addressable (map keys); modules when a *set* of resources is the repeat unit.
- Firewalls belong to data, not code: define rule sets in a `locals` block, then loop — "reduces redundancy and improves readability".
- Review your own applied code like the chapter's Cloud SQL review: hard-coded credentials, duplicated values, missing labels, weak backup config are the standard checklist.
- Load balancers are opt-in: HTTP LB must be enabled in `addons_config { http_load_balancing { disabled = false } }` for Ingress to work on GKE.

## Code Examples
Multiple VPCs in different regions + firewall rules via locals:
```hcl
variable "regions" {
  type    = list(string)
  default = ["us-central1", "europe-west1", "asia-east1"]
}
resource "google_compute_network" "vpc" {
  for_each                = toset(var.regions)
  name                    = "my-vpc-${each.key}"
  auto_create_subnetworks = true
}
locals {
  firewall_rules = [
    { name = "default-allow-ssh",   protocol = "tcp", ports = ["22"],  target_tags = ["ssh"] },
    { name = "default-allow-http",  protocol = "tcp", ports = ["80"],  target_tags = ["http"] },
    { name = "default-allow-https", protocol = "tcp", ports = ["443"], target_tags = ["https"] },
  ]
}
resource "google_compute_firewall" "default_allow_rules" {
  for_each = { for vpc_key, vpc in google_compute_network.vpc : vpc_key => vpc }
  dynamic "allow" {
    for_each = local.firewall_rules
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }
  name          = "${each.value.name}-${local.firewall_rules[0].name}"
  network       = each.value.self_link
  source_ranges = ["0.0.0.0/0"]
}
output "vpc_networks" {
  value = { for region, vpc in google_compute_network.vpc : region => vpc.self_link }
}
```
- **What it demonstrates**: `toset` + `for_each` for regional VPCs, `locals` as a firewall rule table, `dynamic` blocks, and a map-format output.
Private subnets inside a VPC module:
```hcl
resource "google_compute_network" "vpc" {
  name                    = var.name
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "private_subnet" {
  for_each                 = var.subnets          # map: subnet → CIDR
  name                     = each.key
  ip_cidr_range            = each.value           # e.g. "10.1.0.0/16"
  region                   = var.region
  network                  = google_compute_network.vpc.name
  private_ip_google_access = true
}
```
Primary + standby PostgreSQL with backups:
```hcl
resource "google_sql_database_instance" "primary" {
  name             = var.primary_instance_name
  database_version = var.database_version
  region           = var.region
  settings {
    tier                        = var.tier
    availability_type           = "REGIONAL"   # HA across zones
    backup_configuration {
      enabled         = true          # without this, NO backups are created
      start_time      = "03:00"
      retention_count = 15            # keep last 15 daily backups
    }
  }
}
resource "google_sql_database_instance" "replica" {
  name                 = var.replica_instance_name
  database_version     = var.database_version
  region               = var.region
  master_instance_name = google_sql_database_instance.primary.name
  settings { tier = var.tier }
}
```
Monitoring alert (CPU > 80% for 60s → email):
```hcl
resource "google_monitoring_notification_channel" "email_notification" {
  display_name = "Email Notification Channel"
  type         = "email"
  labels       = { email_address = "youremail@domain.com" }
}
resource "google_monitoring_alert_policy" "db_instance_alert" {
  display_name = "Database Instance Alert"
  conditions {
    display_name = "High CPU Usage"
    condition_threshold {
      filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" AND resource.label.database_id=\"${google_sql_database_instance.primary.name}\""
      comparison      = "COMPARISON_GT"
      duration        = "60s"
      threshold_value = 0.8
    }
  }
  notification_channels = [google_monitoring_notification_channel.email_notification.name]
  combiner = "OR"
  enabled  = true
}
```
Service account + key (5-step pattern):
```hcl
resource "google_service_account" "terraform"  { account_id = "terraform"  display_name = "Terraform Service Account" }
resource "google_project_iam_member" "terraform_sa" {
  project = var.project_id
  member  = "serviceAccount:${google_service_account.terraform.email}"
  role    = "roles/editor"
}
resource "google_service_account_key" "terraform_key" {
  service_account_id = google_service_account.terraform.name
  keepers            = { key = google_service_account.terraform.name }
}
output "service_account_key" {
  value     = google_service_account_key.terraform_key.private_key
  sensitive = true   # masked in logs & UI
}
```
GKE cluster core:
```hcl
resource "google_container_cluster" "primary" {
  name               = "my-gke-cluster"
  location           = "us-central1"
  initial_node_count = 2
  node_config { machine_type = "e2-medium"  disk_size_gb = 10 }
  node_pool {
    name               = "default-pool"
    initial_node_count = var.node_count
    autoscaling {
      min_node_count = var.min_node_count
      max_node_count = var.max_node_count
    }
  }
  addons_config {
    http_load_balancing { disabled = false }  # required for ingress
  }
  network_policy { enabled = true }
}
```
Kubernetes RBAC + provider wired from the GKE cluster:
```hcl
resource "kubernetes_role" "restricted-access" {
  metadata { name = "restricted-access-role" }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "update", "delete"]
  }
}
resource "kubernetes_cluster_role_binding" "restricted" {
  metadata { name = "restricted-service-account" }
  role_ref { kind = "ClusterRole"  name = "restricted-access-role"  api_group = "rbac.authorization.k8s.io" }
  subject { kind = "ServiceAccount"  name = "default"  namespace = "default" }
}
provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}
```
Event-driven pipeline (section walkthrough): GCS `csv_bucket` → `google_pubsub_topic` + `google_storage_bucket_notification` (`event_types = ["OBJECT_FINALIZE"]`, payload `JSON_API_V1`) → Cloud Function (`runtime = "python310"`, triggered via Pub/Sub, creates BQ table + calls Cloud Run) → Cloud Run container (`google_cloud_run_service. data_processor`) transforms/loads → `google_bigquery_dataset`. Build steps: write processing scripts → Dockerize → define resources in Terraform.

## Reference Tables
| Decision | Rule |
|---|---|
| Replicate N similar resources | `count = length(...)` + `count.index` |
| Per-instance variations | `for_each` over map/set + `each.value` |
| Same unit, different params | module called repeatedly |
| State bucket location | dedicated bucket, versioning on, `force_destroy = false`, `public_access_prevention = "enforced"` |
| Backend migration | edit config → `init` (yes) → re-`init` to verify |
| Prereq for GKE apply | service account with Kubernetes Engine Admin + Compute Admin + Viewer roles; Kubernetes Engine API enabled |
| Baking in backups | `enabled = true` (else none), `start_time`, `retention_count` |

## Worked Example
The chapter's own critique loop on the MySQL config: the naive version (hard-coded `password = "123456"`, region defined twice, no labels, `backup_configuration { enabled = true }` only) is improved into the parameterized production version: split into `variables.tf` (7 vars) + `terraform.tfvars` (values incl. passwords — isolates sensitive data from logic) + `main.tf` (`ip_configuration` `authorized_networks` restricted to `10.0.0.0/24`, `availability_type = "ZONAL"`, `maintenance_window { day = 7, hour = 23, update_track = "stable" }`, `activation_policy = "ALWAYS"`, `user_labels`, `lifecycle { prevent_destroy = true }`). Then scaled to PostgreSQL: REGIONAL availability + replica + PITR backups + SSL cert user + project IAM member `roles/cloudsql.admin` + CPU alert. That critique checklist (redundancy → variables → labels → backup → access control → monitoring) is the reusable artifact.

## Anti-patterns
- **Hard-coded passwords in resources**: `password = "123456"` directly in code — move to variable, ideally a secrets manager (Ch 5).
- **Defining region twice** (provider block + resource): guarantees eventual inconsistency when one side changes.
- **No labels on GCP resources**: unmanageable at scale.
- **Backup "enabled" without schedule/retention**: enabled-but-unconfigured backups; specify `start_time` + `retention_count`.
- **`auto_create_subnetworks = true` when you need control**: default/auto VPC forbids subnet placement, IP ranges, firewall customization.
- **Applying unsaved plans**: re-running `terraform plan` after infrastructure changes can yield a different result — save with `-out` and apply the reviewed file.

## Key Takeaways
1. `plan -out=plan.out` → `apply "plan.out"` is the reviewable, deterministic apply loop.
2. Every apply ends with a `gcloud` verification command — never trust "Apply complete!" alone.
3. GCS remote-state bucket needs versioning + anti-deletion hardening; state file identity (lineage) survives backend moves.
4. Define firewall rules (and other repeated configs) once in `locals`, loop over them with `for_each` + `dynamic` blocks.
5. Cloud SQL hardening checklist: parameterize, restrict `authorized_networks`, availability mode, maintenance window, labels, `prevent_destroy`, backups with start time + retention, IAM role, monitoring alert with threshold + channel.
6. GKE apply requires prereqs (service account roles + API enabled); wire the Kubernetes provider from the GKE cluster's endpoint/CA cert, not static config.

## Connects To
- **Ch 3**: count/for_each/locals/dependencies all applied at scale here; GCS remote state is Ch 3's backend concept made real.
- **Ch 5**: the "hardcoded password" pitfall and service-account key handling lead directly into secrets management and IAM.