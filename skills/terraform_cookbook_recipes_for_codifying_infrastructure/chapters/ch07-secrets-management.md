# Chapter 7: Consuming and Managing Secrets with Terraform

## Core Idea
Keep sensitive data out of Terraform configuration files and version control entirely: Terraform should *retrieve* secrets at apply time from a dedicated secrets system (Vault, AWS Secrets Manager, a password manager, or the pipeline's secret store) and treat every value as `sensitive = true` so it never appears in logs or outputs.

## Frameworks Introduced
- **Secrets manager as data source (AWS Secrets Manager)**: retrieve secrets at provision time with `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` data sources instead of storing values in `.tf` files.
  - When to use: when the platform you run Terraform on is AWS and you need rotation without code changes.
  - How: look the secret up by name, `jsondecode()` the `secret_string`, assign the parsed value to a resource attribute; declare the variable `sensitive = true` and output only non-sensitive data.
- **Vault KV retrieval via `vault_generic_secret`**: read key-value pairs from Vault KV (v2) by path.
  - When to use: multi-cloud or cross-platform setups where Vault is the central secrets tier.
  - How: configure `provider "vault"` with the server address (no hard-coded token), read the secret by `path`, consume entries as `data.vault_generic_secret.<name>.data["key"]`.
- **Kubernetes-native secrets pattern**: Terraform creates a `kubernetes_secret` resource; Pods consume it via `value_from` / `secret_key_ref`, never inline values.
  - When to use: when you want Kubernetes' built-in secret management (encryption at rest, RBAC) and Terraform stays the provisioning layer.
  - How: define the credentials as `sensitive` variables, create the Secret, reference `kubernetes_secret.<name>.metadata[0].name` in the Pod spec.
- **Vault Secrets Operator pattern (Vault + Kubernetes)**: Terraform sets up Vault auth (Kubernetes auth method), a Vault policy, a service account, the operator via Helm, and a `VaultStaticSecret` custom resource; the operator syncs Vault → Kubernetes.
  - When to use: when you want centralized Vault features (dynamic secrets, rotation) with automatic synchronization into the cluster.
  - How: `vault_auth_backend` (type `kubernetes`) → `vault_kubernetes_auth_backend_config` → `vault_policy` (read-only caps on `secret/data/...`) → `kubernetes_service_account` + `vault_token` → `helm_release` `vault-secrets-operator` → `kubernetes_manifest` of kind `VaultStaticSecret` (`type = "kv-v2"`, `refreshAfter`).
- **TF_VAR_ environment variable injection**: pass secrets through `TF_VAR_<variable_name>` env vars in the shell or CI/CD, matched exactly by casing to the Terraform variable.
  - When to use: local runs and CI/CD pipelines where the platform's secret store can surface values as env vars.
  - How: define a `sensitive = true` variable, set `export TF_VAR_database_password=...`, reference `var.database_password`; inject from the pipeline's secrets context (e.g. GitHub Actions `${{ secrets.X }}`).
- **Audit-and-rotate pattern**: enable Vault audit logging server-side (e.g. `vault audit enable file ...` — outside Terraform) and configure rotation policies in the backend (e.g. `aws_secretsmanager_secret_rotation` with `automatically_after_days = 30`).
  - When to use: whenever long-lived secrets exist and compliance requires access tracking.
  - How: read secrets via data sources so Terraform always picks up the latest version; attach a rotation Lambda/schedule; review audit logs and test rotation for graceful app handling.
- **Password-manager bridge via `external` data source**: 1Password/Bitwarden-style password managers integrated by running a small script with `data "external"`, returning JSON.
  - When to use: teams already storing secrets in a password manager with a CLI (e.g. `op get item ...`).
  - How: `data "external"` runs `retrieve_secrets.py`, the script shells out to the manager's CLI and prints a JSON map, Terraform reads `data.external.secrets.result.<key>`. Use MFA, rotation, and access controls; prefer dedicated secret services for strict security requirements.
- **Compliance and governance stack**: combine a compliant secrets system + least-privilege IAM policy + CloudWatch access logging + environment separation.
  - When to use: regulated environments where storage, access, and auditing of secrets are mandated.
  - How: secrets in a dedicated manager, `aws_iam_policy` scoped to `secretsmanager:GetSecretValue`, log group with retention (e.g. 90 days), workspaces or separate state files to isolate sensitive environments, and onboarding/offboarding processes.

## Key Concepts
- **sensitive = true**: variable/output attribute that stops Terraform from displaying the value in logs, plan output, or console output — while the value is still usable in configuration.
- **dynamic secrets**: credentials generated on demand with a limited lifespan (TTL), rather than static shared secrets held for long periods.
- **vault_generic_secret**: the Vault provider data source that reads arbitrary key-value pairs from a Vault path.
- **Vault Secrets Operator**: the Kubernetes operator (installed via Helm) that watches `VaultStaticSecret`/dynamic resources and syncs Vault secrets into native Kubernetes Secrets.
- **VSO VaultStaticSecret CRD**: custom resource (`secrets.hashicorp.com/v1beta1`) declaring which Vault KV v2 path to sync and the destination Kubernetes Secret name.
- **Kubernetes auth method**: Vault authentication that lets the cluster's service accounts authenticate to Vault instead of using static tokens; AppRole is the fallback where no native auth method exists.
- **vault_database_secret_backend_creds**: data source against the Vault database secrets engine that mints fresh short-lived DB credentials per read.
- **TF_VAR_ prefix**: Terraform's convention for binding an environment variable to a same-named input variable.
- **external data source**: Terraform data source that executes a local program and consumes its JSON stdout as a data map — the bridge to password managers.
- **encryption at rest**: state/backend and secret-store configuration requirement so secrets aren't recoverable from disk; for Kubernetes Secrets the cluster must be configured to encrypt them.

## Mental Models
- Use a secrets management service + `sensitive = true` variables when a secret must reach a resource, and never output it; only non-sensitive artifacts (endpoints, ARNs) belong in outputs.
- Use Vault's auth methods (AWS auth, then AppRole) when Terraform must authenticate — never hard-code a Vault token in the provider block.
- Use dynamic Vault database credentials when static DB passwords sitting unchanged for long periods are the main compromise risk.
- Use `TF_VAR_` env vars when the CI/CD platform already has an encrypted secret store that can inject values at runtime.

## Anti-patterns
- **Hard-coding secrets in `.tf` files or version control**: direct exposure in commits and state; the whole chapter's recipes exist to avoid this.
- **Hard-coding a Vault token in the provider block**: use Vault auth methods instead (AWS auth in AWS, AppRole elsewhere).
- **Plain-text env vars in scripts**: storing the values inside the scripts or config files that set `TF_VAR_` variables leaks them; feed env vars from a secrets system or encrypted store instead.
- **Outputting secret values**: outputs for endpoints are fine, but echoing password/API-key values into logs or plan output defeats `sensitive`.
- **Static, never-rotated secrets**: credentials unchanged for long periods; rotate automatically (e.g. AWS Secrets Manager rotation every 30 days) and confirm apps tolerate rotation.
- **Assuming Kubernetes Secrets are safe by default**: Secrets are only encrypted at rest when the cluster is *configured* for it; otherwise rely on RBAC plus encryption settings.
- **Importing/generating config that captures sensitive data carelessly**: imported resources may contain sensitive attributes — keep them in a secrets system, not baked into generated config.

## Code Examples
```hcl
data "aws_secretsmanager_secret" "db_password" {
  name = "prod/db/password"
}
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}
variable "db_password" {
  type        = string
  description = "Database password"
  sensitive   = true
}
resource "aws_db_instance" "example" {
  # ... other configuration ...
  password = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]
}
```
- **What it demonstrates**: AWS Secrets Manager retrieval + `jsondecode`, with `sensitive = true` so the value never appears in output.

```hcl
provider "vault" {
  address = "https://vault.example.com"
}
data "vault_generic_secret" "example" {
  path = "secret/example"
}
resource "example_resource" "example" {
  username = data.vault_generic_secret.example.data["username"]
  password = data.vault_generic_secret.example.data["password"]
}
```
- **What it demonstrates**: the Vault KV v2 read flow — read by path, consume `data["key"]`, no token in the provider.

```hcl
resource "kubernetes_secret" "example_secret" {
  metadata { name = "example-secret" }
  data = {
    username = var.database_username
    password = var.database_password
  }
}
```
- **What it demonstrates**: Kubernetes-native secrets — Terraform creates the `kubernetes_secret`, Pods consume it via `value_from` → `secret_key_ref` env vars.

## Reference Tables
No single comparison table is printed in this chapter; the recipes rank approaches implicitly, in increasing sophistication:

| Approach | Where secrets live | Strengths | Watch out for |
|---|---|---|---|
| `TF_VAR_` env vars (7.5/7.10) | Shell session / CI secret store | Zero extra config; natural CI/CD fit | Never set them in plain text in scripts; casing must match the variable name |
| Password managers via `external` (7.7) | 1Password/Bitwarden-style manager | Centralized, encrypted, access controls, audit logs | Bridge script must be hardened; may not meet strict security requirements |
| AWS Secrets Manager (7.1/7.6/7.8) | Secrets Manager | Rotation without code changes, IAM-scoped access, CloudWatch auditing | IAM perms + rotation testing required |
| HashiCorp Vault KV v2 (7.2/7.4) | Vault | Dynamic secrets, rotation, fine-grained policies | Use auth methods, TLS, Vault policies, regular audits |
| Vault dynamic secrets (7.9) | Vault database engine | Short-lived auto-rotated creds, fully auditable | TTL tuning; apps must handle credential rotation |

## Worked Example
Vault dynamic database credentials (7.9) — the chapter's most complete end-to-end flow:
1. **Mount the engine**: `resource "vault_mount" "db" { path = "database"  type = "database" }`.
2. **Connect Vault to MySQL**: `vault_database_secret_backend_connection` named `mysql` with `connection_url = "{{username}}:{{password}}@tcp(mysql.example.com:3306)/"` and `allowed_roles = ["app"]`.
3. **Define the role**: `vault_database_secret_backend_role` `app` with `default_ttl = "1h"`, `max_ttl = "24h"`, and `creation_statements` that `CREATE USER '{{name}}'` and `GRANT SELECT` — Vault executes these to mint each credential.
4. **Mint credentials on demand**: `data "vault_database_secret_backend_creds" "creds" { backend = vault_mount.db.path  role = vault_database_secret_backend_role.app.name }` — every read generates a fresh username/password.
5. **Consume them**: `mysql_database` `app_db` is provisioned with `user = creds.username` / `password = creds.password`.
Result: credentials expire automatically (1h, max 24h), every request is logged in Vault, and no static DB password exists anywhere in Terraform code, state values in config, or the database.

## Key Takeaways
1. Secrets never belong in Terraform configuration files, variables' default values, or version control — Terraform reads them at apply time from a dedicated system.
2. Mark every credential-carrying variable `sensitive = true` and output only non-sensitive data (endpoints, IDs, ARNs).
3. Authenticate to Vault with auth methods (AWS auth, AppRole), Vault policies, and TLS — never a hard-coded token.
4. Data-source-based retrieval means rotation is free: rotate the secret in the backend and Terraform picks up the new value on the next run, no code change.
5. Prefer dynamic Vault secrets (database engine with TTLs and creation statements) over static credentials wherever the consumer can tolerate short-lived credentials.
6. In CI/CD, chain the pipeline's encrypted secret store to Terraform via `TF_VAR_` env vars (`${{ secrets.X }}` in GitHub Actions) rather than writing values into workflow files.
7. Treat auditing and rotation as part of the config: enable Vault audit logging server-side, attach rotation schedules (e.g. 30 days), review logs, and verify apps handle rotation gracefully.

## Connects To
- **Ch 4 (state)**: remote, encrypted backends — state files themselves must be handled as sensitive data when secrets land in them.
- **Ch 3 (variables and outputs / sensitive values)**: `sensitive = true` and non-sensitive-only outputs are the HCL-side half of every pattern here.
- **Ch 7 recipe 8.7 workspaces**: separate state per environment isolates sensitive credentials for production.
- **Dynamic secrets**: Vault's database secrets engine as the broader "zero standing credentials" / short-lived-credential security model.
- **Kubernetes RBAC + encryption at rest**: the K8s-side controls that make native Secrets viable for `kubernetes_secret`.