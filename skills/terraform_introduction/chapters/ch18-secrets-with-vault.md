# Chapter 18: Managing Secrets with Vault

## Core Idea
Vault is the centralized secrets service — Terraform reads (data source) and writes (resource) secrets through the Vault provider, so secret values stay out of config.

## Frameworks Introduced
- **Vault provider integration**: configure `address` + `token`, then use `vault_generic_secret` resources/data sources
  - When to use: any secret that Terraform config needs or produces
  - How: writing uses the `resource` block with a `data` map; reading uses the `data` block and indexing `data["key"]`

## Key Concepts
- **Secrets as a Service**: centralized secret management behind a unified interface
- **Data encryption**: Vault can encrypt/decrypt without storing — data unreadable at rest
- **Fine-grained access control**: Vault policies decide who reaches which secrets
- **Auditing**: robust audit capabilities over secret access

## Mental Models
- **Vault as the bank vault**: Terraform becomes a depositor (resource) and withdrawer (data source); access rights are account rules (policies).

## Code Examples *(technical)*
```hcl
provider "vault" {
  address = "https://vault.example.com"
  token   = "my-token-here"
}

# write
resource "vault_generic_secret" "example" {
  path = "secret/example"
  data = { password = "my-secret-password" }
}

# read
data "vault_generic_secret" "example" {
  path = "secret/example"
}

output "password" {
  value = data.vault_generic_secret.example.data["password"]
}

# consume
resource "example_resource" "example" {
  password = data.vault_generic_secret.example.data["password"]
}
```
- **What it demonstrates**: the full write→read→consume loop; note the provider token itself should come from env/variables in real setups.

## Key Takeaways
1. Same path (`secret/example`), two modes: `resource` writes, `data` reads.
2. Secrets are consumed by indexing the data map: `data.vault_generic_secret.example.data["password"]`.
3. Vault's three headline features: secrets-as-a-service, encryption without storage, fine-grained policy control.

## Connects To
- **Ch 17**: this is the secrets-manager half of the security chapter
- **Ch 9**: the "use a secrets manager" best practice, made concrete