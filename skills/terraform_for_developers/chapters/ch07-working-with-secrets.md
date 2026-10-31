# Chapter 7: Working with Secrets

## Core Idea
Secrets follow a six-stage lifecycle — generate, store, control access, distribute, rotate/audit, revoke — and in Terraform the pattern is: store secrets in Azure Key Vault, retrieve them with a data source at plan/apply time, and never let a credential appear as a literal in code or state you control.

## Frameworks Introduced
- **Secrets Management Lifecycle (6 stages)**: the layered defense
  1. **Generation** — unique, random, appropriately sized via cryptographic methods; plan complexity and validity intervals up front
  2. **Secure Storage** — vault (Key Vault / HashiCorp Vault / AWS Secrets Manager), never plain text or Git; least-privilege network + auth controls on the vault itself
  3. **Strict Access Control** — role/policy-based; read-only consumers never get delete/rotate rights; every read/update audited
  4. **Distribution** — vault API with authorized tokens, env-var injection through pipelines, encryption in transit / mTLS; secrets live only in memory
  5. **Rotation & Versioning** — short lifetimes limit breach damage; versioned secrets enable smooth rollouts and rollback on incident
  6. **Revocation & Cleanup** — immediate revocation on compromise (e.g. secret posted to GitHub), plus end-of-life cleanup so stale credentials don't linger
- **Key Vault Terraform Integration Pattern**: `azurerm_key_vault_*` resources to create/store + `data "azurerm_key_vault_secret"` to look up at apply time — the .tf code references, never embeds

## Key Concepts
- **Secret**: any data whose exposure grants access — API keys, DB credentials, SSH keys, certificates, tokens
- **Soft delete / purge protection (`soft_delete_retention_days`)**: controls how quickly secrets can be permanently removed — a safety net against accidental or malicious deletion
- **Access policy (`secret_permissions`)**: grant exactly `["get", "set"]` for a writer-only path, or only `["get"]` for consumers; the current principal's identity comes from `data "azurerm_client_config" "current"`
- **`data.azurerm_key_vault_secret.<label>.value`**: how another resource (e.g. `azurerm_sql_server.administrator_login_password`) consumes a stored secret without hard-coding
- **Audit logging**: Diagnostic Setting sending `AuditEvent` logs to a Log Analytics workspace; alerts on anomalies (100 sudden reads, 3AM access)
- **Per-environment vaults or secret names**: dev/staging/prod don't share one secret namespace

## Code Examples
```hcl
# Store in Key Vault...
resource "azurerm_key_vault_secret" "mysql_pass" {
  name         = "mysql-password"
  key_vault_id = azurerm_key_vault.demo_vault.id
  value        = "P@ssw0rd123"          # rotate by updating here or in Vault
}

# ...retrieve by data source at apply time...
data "azurerm_key_vault_secret" "lookup_mysql_pass" {
  name         = azurerm_key_vault_secret.mysql_pass.name
  key_vault_id = azurerm_key_vault.demo_vault.id
}

# ...and consume in another resource — no password literal in the DB block
resource "azurerm_mysql_server" "my_db" {
  administrator_login_password = data.azurerm_key_vault_secret.lookup_mysql_pass.value
  # ...
}
```
- **What it demonstrates**: the reference-don't-embed flow; rotation happens at the vault and flows through on the next run

## Worked Example
Securing database credentials end-to-end:
1. `data "azurerm_client_config" "current" {}` — fetch tenant/object IDs
2. Create Key Vault with soft delete (7–14 days) and standard SKU
3. `azurerm_key_vault_access_policy`: grant the current principal only needed `secret_permissions`
4. Store `db-username` and `db-password` secrets
5. Declare two `data "azurerm_key_vault_secret"` lookups
6. Wire `azurerm_sql_server`'s `administrator_login` / `administrator_login_password` to the data-source values
7. Add `azurerm_monitor_diagnostic_setting` → Log Analytics workspace (30-day retention), `AuditEvent` log category (7-day retention) + AllMetrics
8. Set alerts on read-volume anomalies; rotate monthly by updating the vault secret — next Terraform run picks it up

## Anti-patterns
- **Secrets in version control**: plain-text literals or committed `.tfvars` with real credentials — the primary breach vector; if exposed, revoke immediately and generate new
- **Over-granted vault policies**: an app needing read access must not hold delete/rotation rights — least privilege applies to vault ACLs
- **Secrets in state anyway**: the state file can capture sensitive attributes — secure/encrypt state storage (ties to Ch 5)
- **Un-audited vaults**: without AuditEvent logging, silent breaches persist indefinitely
- **Forever-secrets**: no rotation schedule and no versioning means one compromise is permanent damage

## Key Takeaways
1. Terraform should reference secrets via data sources; it should *create* or *rotate* them only in the vault
2. Vault access policies are least-privilege surfaces too — separate who writes secrets from who reads them
3. Enable and log `AuditEvent` + metrics in your IaC so vault surveillance doesn't depend on console clicks
4. Versioned secrets + consumers reading at startup = near-zero-downtime rotation
5. Compromised secret → revoke + regenerate + allow a grace period for old versions, then purge
6. Different vaults (or names) per environment, never shared prod secrets into dev
7. Note for later chapters: static vault secrets are still Terraform-visible — Ch 10's HashiCorp Vault dynamic secrets eliminate even that exposure

## Connects To
- **Ch 2**: the TF_VAR_/tfvars credential pattern is the floor; this vault pattern replaces it
- **Ch 5**: state files can leak secret values — encrypt/securing remote state matters more when vault-managed secrets flow through plans
- **Ch 10**: HashiCorp Vault dynamic (ephemeral) secrets as the next step beyond static vault storage