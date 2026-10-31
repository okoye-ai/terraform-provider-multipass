# Chapter 13: Security and secrets management

## Core Idea
Think like a hacker: state, logs, provisioners, external/HTTP data sources all leak secrets — secure state (fewer secrets, least-privileged access, encryption at rest), ship static secrets via environment variables, and prefer dynamic just-in-time secrets from Vault/AWS Secrets Manager; gate everything with Sentinel policy-as-code.

## Frameworks Introduced
- **What Can Land in State** (the exact list): only three block types persist state — **resources, data sources, output values**. Providers, input variables, locals, modules never store stateful data (they can still leak elsewhere). `sensitive = true` does NOT keep secrets out of state — only redacts CLI output
- **The Secret-Reduction Rule**: expose only necessary secrets; the RDS username/password are unavoidable (required resource attrs); Lambda env vars holding DB creds are avoidable — pass a `SECRET_ID` and fetch from Secrets Manager at runtime (zero-trust even within your team)
- **Leak-Vector Catalogue** (the "threat model" for Terraform):
  - Trace logs (`TF_LOG=trace`): full AWS SDK request/response with signed credentials usable ~15 min → turn off except debugging
  - Local-exec provisioners: echo env vars straight into logs even with trace logging off; can read any secret on the machine running Terraform
  - External data sources: "perhaps the most dangerous resources in all of Terraform" — arbitrary code runs during **plan** (no apply needed!); sneak into a module/PR and a plan runs your `data "external"` program
  - HTTP provider data source: `GET ?pw=${var.password}` — whoever owns the URL harvests secrets at plan time
  - Terraform-variable redirection: `sensitive = true` scrubs *references*, not values — round-trip a secret through `local_file` → `data.local_file` → local-exec and it prints plaintext
- **Static vs Dynamic Secrets**: static (passwords, long-lived tokens, credentials files) — pass as env vars when possible, isolate in a separate `secrets.tfvars` (never committed) when forced into Terraform variables, and run Terraform from automation (ties runs to Git commits, leaves evidence); dynamic (just-in-time, created on demand, revoked after use, "the smaller the validity window the better") — read via Vault/ASM data sources
- **Sentinel Policy-as-Code**: rules are functions returning true/false; all rules must pass or the run exits before Apply (checked between plan and apply); sandbox language (embeddable without monkey-patching backdoors, unlike Python/Ruby); proprietary — works only with Terraform Enterprise/Cloud. Typical policies: block local-exec printing `AWS_ACCESS_KEY_ID`, disallow 0.0.0.0/0 CIDRs, restrict instance types, enforce tagging

## Key Concepts
- **Encryption at rest vs in transit**: backends mostly handle transit (avoid the HTTP backend — no transit encryption); at rest is your responsibility — S3+KMS default keys or client-side KMS; Terraform Cloud/Enterprise double-encrypts (KMS + Vault)
- **Scrubbing state is the wrong path**: PGP-encrypt-before-state was tried and deprecated (uninterpolatable values, key loss = state loss); remote backend + encryption at rest is the accepted way
- **CI hardening rules**: no unauthorized plan/apply on workspaces; do not let `terraform plan` run on PRs from forks (fork PRs can trigger external/HTTP data sources without a merge)
- **Vault TTL behavior**: `data "vault_aws_access_credentials"` issues short-lived tokens (20 min default); credentials revoked when the token expires — but all chapter-13 rules still apply
- **ASM vs Vault**: ASM = managed, out-of-the-box key-value + rotation, fewer features; Vault = the gold standard. Azure/GCP have equivalents with the same data-source pattern (`aws_secretsmanager_secret_version` → `jsondecode(secret_string)`)

## Code Examples
```hcl
# Dynamic secrets from Vault (new short-lived creds every run)
provider "vault" { address = var.vault_address }
data "vault_aws_access_credentials" "creds" { backend = "aws", role = "prod-role" }
provider "aws" {
  access_key = data.vault_aws_access_credentials.creds.access_key
  secret_key = data.vault_aws_access_credentials.creds.secret_key
  region     = "us-west-2"
}

# Dynamic secrets from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db" { secret_id = var.secret_id }
locals { creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string) }
#   then local.creds["username"] / local.creds["password"] feed the RDS instance

# The exploit that sensitive = true does NOT stop (local_file round-trip)
resource "local_file" "password" { filename = "password.txt", content = var.password }  # sensitive!
data  "local_file" "password" { filename = local_file.password.filename }
resource "null_resource" "uh_oh" {
  provisioner "local-exec" { command = "echo ${data.local_file.password.content}" }  # prints plaintext
}
```
- **What it demonstrates**: the chapter's worked adversarial examples — every snippet is something a malicious PR could ship; Sentinel's `keywordInProvisioners` policy (`filter tfconfig.provisioners ... matches s`) is the counter-move.

## Key Takeaways
1. Treat state and logs as plaintext JSON full of secrets, because they are.
2. `sensitive = true` is redaction, not protection — it stops honest accidents, not motivated redirection.
3. Provider config belongs in environment variables, never Terraform variables; resource-required secrets go in a git-ignored `secrets.tfvars` + automation.
4. External data sources execute arbitrary code during plan; never run plan against unreviewed/fork code.
5. Rotation is a floor: 90 days for static, or better, dynamic secrets that barely exist at all.

## Connects To
- **Ch 6**: the S3 backend's least-privileged IAM policy and KMS encryption are this chapter's state controls
- **Ch 12**: `TF_IN_AUTOMATION`, env-var plumbing, and where Sentinel checks fit in the pipeline
- **Ch 7/Appendix D**: provisioners and the Shell provider as custom-resource escapes — and their security costs
- **Ch 5**: shim modules carrying everything-in-repo code — the supply-chain rule "skim every module's source"