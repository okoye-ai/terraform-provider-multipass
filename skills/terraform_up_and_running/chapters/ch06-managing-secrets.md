# Chapter 6: Managing Secrets with Terraform

## Core Idea
Never store secrets in plain text — not in code, not in version control. Since Terraform inevitably writes every secret passed to resources into state and plan files in plain text, the real job is (1) feeding secrets to providers and resources via env vars, encrypted files, or secret stores, and (2) encrypting and strictly access-controlling the state and plan files where secrets unavoidably land.

## Frameworks Introduced

### 1. Secret-type taxonomy
Three primary types of secrets; each tool is designed for exactly one type, and forcing a tool across types is insecure or unusable:
- **Personal secrets** — belong to an individual: website passwords, SSH keys, PGP keys.
- **Customer secrets** — belong to your customers (including internal employees if you run internal services): login credentials, PII, PHI.
- **Infrastructure secrets** — belong to your infrastructure: DB passwords, API keys, TLS certificates.

Key asymmetry: infrastructure passwords are stored with reversible encryption (AES, with nonce) because you must decrypt them; customer passwords are stored with one-way hashing (bcrypt, with salt) because you must never recover them. Using the wrong approach is catastrophic.

### 2. Secret-storage strategies
- **File-based secret store** — encrypted files checked into VCS. But the encryption key is itself a secret ("the key-storage conundrum"). Solve it by trusting a cloud KMS (AWS KMS, GCP KMS, Azure Key Vault) or by encrypting with developers' PGP public keys (private keys protected by a memorized/personally-stored password).
- **Centralized secret store** — a web service over the network that encrypts secrets and stores them in MySQL/PostgreSQL/DynamoDB; the encryption key is managed by the service itself or a cloud KMS.

Access interfaces: APIs (programmatic; what Terraform uses under the hood), CLIs (developer convenience and scripting; the only interface file-based stores have), and UIs (team-wide convenience; centralized stores only).

### 3. Provider-auth framework (human vs machine users)
- **Human users**: environment variables (`export AWS_ACCESS_KEY_ID=...`) — the leading space on exports keeps commands out of shell history; store the actual keys in a personal secrets manager (1Password/LastPass), optionally via a CLI helper (`op`, `aws-vault`). aws-vault stores keys in the OS keychain and fronts every command with short-lived STS credentials: `aws-vault exec dev -- terraform apply`.
- **Machine users** (no human present; e.g., CI/CD), in escalating quality:
  - *Stored credentials* — permanent IAM-user keys pasted into the CI platform's secret store (CircleCI Context), exposed as env vars to the build. Simple, but manual and permanent.
  - *IAM roles* — the machine lives inside the cloud provider; AWS fetches temporary, auto-rotated credentials from the instance metadata endpoint (http://169.254.169.254). No manual management, no permanent credentials.
  - *OIDC* — establish a trust relationship between an external CI system and the cloud: CI gets a short-lived token, cloud trusts it via an identity provider + federated assume-role policy scoped to specific repos/branches. No credentials to manage; works outside the cloud provider.

### 4. Resource/data-source secret techniques (with When-to-use / How)
- **Environment variables** — When: quick start, testing (easy mock values), zero cost, and your team already has *some* secret solution. How: declare `variable "db_password" { sensitive = true }` with no default; pass values as `TF_VAR_db_password`. Drawbacks: secrets live outside the code, so nothing is versioned or enforced, and config drift across environments is likely.
- **Encrypted files** — When: you want secrets versioned, packaged, and tested with the code, and you can tolerate a fiddly workflow. How: encrypt a plain-text file with KMS (`aws kms encrypt --key-id <alias> --plaintext fileb://...`) or PGP, commit the ciphertext, decrypt with `aws_kms_secrets` + `yamldecode`. `sops` transparently decrypt-on-edit/encrypt-on-save; Terraform needs the third-party `carlpett/sops` provider or Terragrunt's `sops_decrypt_file`. Drawbacks: rotation/revocation is hard (any compromised key decrypts all history), audit shows only key usage, learning curve.
- **Centralized secret stores** — When: production at scale, where per-secret audit logs, rotation (e.g., every 30 days), and standardization matter. How: store JSON in the store (e.g., `db-creds` in AWS Secrets Manager), read with `aws_secretsmanager_secret_version`, parse with `jsondecode`. Drawbacks: secrets not versioned with code, per-secret cost, harder automated retrieval and testing.

### 5. The state/plan-file reality
Any secret passed into resources or data sources lands **in plain text** in both `terraform.tfstate` and any `-out=` plan file (open issue since 2014; state-scrubbing workarounds are brittle and rejected). Therefore: (1) store backends in encrypted-at-rest-and-in-transit backends (S3, GCS, Azure Blob), (2) strictly control backend and plan-file access with IAM policies scoped to a few trusted devs or just the prod CI server, and (3) encrypt plan files the same way.

### 6. Plain-text anti-patterns (why VCS storage fails)
Anyone with repo access gets the secret; every machine that ever cloned the repo keeps a copy (devs, CI, VCS hosts, deployment, backups); every piece of software on those machines can read it; and there is no audit log or way to revoke — you can't even tell if you were compromised.

## Key Concepts
- **Secret management**: the practice of storing, accessing, rotating, and auditing sensitive data (DB passwords, API keys, TLS/SSH/GPG keys).
- **Key management service (KMS)**: cloud-managed service (AWS KMS, GCP KMS, Azure Key Vault) holding encryption keys so you never see the underlying key material — only AWS can read it.
- **Customer managed key (CMK)**: a KMS encryption key you create and control via a key policy; best practice is giving it a human-friendly alias (`alias/kms-cmk-example`).
- **Assume role policy**: an IAM policy defining *who* may assume an IAM role (e.g., the `ec2.amazonaws.com` service).
- **IAM role**: an assumable IAM entity with no permanent credentials — the identity granted to EC2 instances, Jenkins, or OIDC-federated CI.
- **Instance profile**: the bridge attaching an IAM role to an EC2 instance, whose metadata endpoint hands out temporary credentials to any AWS SDK client.
- **OIDC (OpenID Connect)**: federation protocol letting an external CI system prove its identity to a cloud provider, yielding temporary credentials with zero stored secrets.
- **`sensitive = true`**: variable/output flag that stops Terraform logging the value in plan/apply output — but does *not* keep it out of state.
- **TF_VAR convention**: environment variables named `TF_VAR_<name>` feed Terraform variables named `<name>`.
- **CircleCI Context**: a named bundle of secrets the CI platform exposes to workflow jobs as environment variables.
- **Trusted AWS account ID**: `123456789012` appears in the book's examples (use your own).
- **CiphertextBlob / fileb://**: the KMS CLI contract — `fileb://` reads binary input, `--output text --query CiphertextBlob` extracts base64 ciphertext.

## Mental Models
- **Use env vars when you need zero cost and easy testing.** Free, universally compatible, trivially mocked in automated tests — at the price of unversioned, unenforced secrets.
- **Use encrypted files when secrets must live in version control with the code.** Versioned, packaged, tested like any other artifact; pay for it with awkward edit/encrypt cycles and painful rotation.
- **Use centralized secret stores when audit logs and rotation are non-negotiable.** The only option with per-secret audit logs and easy rotation/revocation — at real cost in money and retrieval complexity.
- **Use IAM roles for machines inside the cloud; OIDC for machines outside it.** Both avoid permanent, manually managed credentials; OIDC closes the gap for hosted CI like GitHub Actions.

## Anti-patterns
- **Hardcoding secrets in Terraform code** (`username = "admin"`, `password = "password"`): spreads the secret to every repo clone, CI box, and backup; no audit, no revocation.
- **Plain-text credentials in provider blocks** (`access_key`/`secret_key` in `provider "aws"`): also impractical — one credential set for every user and environment.
- **Checking the unencrypted plain-text file into VCS** during the encrypt workflow (encrypt first, `rm` the plaintext, *then* commit).
- **Typing secrets without a leading space** — most shells write each command to `~/.bash_history` on disk, leaving secrets in the history file.
- **Scrubbing secrets from state files** via workarounds: brittle, breaks on every Terraform release — don't.
- **A federated IAM role with an unscoped trust policy**: without the `condition` on `token.actions.githubusercontent.com:sub`, *all* GitHub repos could assume the role.
- **Leaving the instance metadata endpoint open**: prefer restricting it (iptables/nftables) to the specific OS user, or disabling it after boot.
- **Forcing a tool across secret types**: e.g., using an AES-style reversible store for customer passwords instead of salted bcrypt hashing.

## Code Examples

### Sensitive variables fed from environment variables
```hcl
variable "db_password" {
  description = "The password for the database"
  type        = string
  sensitive   = true
}

resource "aws_db_instance" "example" {
  identifier_prefix   = "terraform-up-and-running"
  engine              = "mysql"
  allocated_storage   = 10
  instance_class      = "db.t2.micro"
  skip_final_snapshot = true
  db_name             = var.db_name

  # Pass the secrets to the resource
  username = var.db_username
  password = var.db_password
}
```
```bash
# leading space keeps these out of shell history
 export TF_VAR_db_username=(DB_USERNAME)
 export TF_VAR_db_password=(DB_PASSWORD)
```

### KMS-encrypted file decrypted and parsed in Terraform
```hcl
data "aws_kms_secrets" "creds" {
  secret {
    name    = "db"
    payload = file("${path.module}/db-creds.yml.encrypted")
  }
}

locals {
  db_creds = yamldecode(data.aws_kms_secrets.creds.plaintext["db"])
}
```
```bash
./encrypt.sh alias/kms-cmk-example us-east-2 db-creds.yml db-creds.yml.encrypted
```

### AWS Secrets Manager secret read via data source
```hcl
data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "db-creds"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.creds.secret_string
  )
}
```

### OIDC trust between GitHub Actions and AWS
```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
      type        = "Federated"
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for a in var.allowed_repos_branches :
        "repo:${a["org"]}/${a["repo"]}:ref:refs/heads/${a["branch"]}"
      ]
    }
  }
}
```
```yaml
permissions:
  id-token: write   # give the build permission to mint OIDC tokens
```

## Reference Tables

### Table 6-1 — Secret management tool comparison
| Tool | Types of secrets | Secret storage | Secret interface |
|---|---|---|---|
| HashiCorp Vault | Infrastructure | Centralized service | UI, API, CLI |
| AWS Secrets Manager | Infrastructure | Centralized service | UI, API, CLI |
| Google Secrets Manager | Infrastructure | Centralized service | UI, API, CLI |
| Azure Key Vault | Infrastructure | Centralized service | UI, API, CLI |
| Confidant | Infrastructure | Centralized service | UI, API, CLI |
| Keywhiz | Infrastructure | Centralized service | API, CLI |
| sops | Infrastructure | Files | CLI |
| git-secret | Infrastructure | Files | CLI |
| 1Password | Personal | Centralized service | UI, API, CLI |
| LastPass | Personal | Centralized service | UI, API, CLI |
| Bitwarden | Personal | Centralized service | UI, API, CLI |
| KeePass | Personal | Files | UI, CLI |
| Keychain (macOS) | Personal | Files | UI, CLI |
| Credential Manager (Windows) | Personal | Files | UI, CLI |
| pass | Personal | Files | CLI |
| Active Directory | Customer | Centralized service | UI, API, CLI |
| Auth0 | Customer | Centralized service | UI, API, CLI |
| Okta | Customer | Centralized service | UI, API, CLI |
| OneLogin | Customer | Centralized service | UI, API, CLI |
| Ping | Customer | Centralized service | UI, API, CLI |
| AWS Cognito | Customer | Centralized service | UI, API, CLI |

(Vault's multiple secret engines cover mostly infrastructure secrets, plus a few customer-secret engines.)

### Table 6-2 — Machine-user provider auth (CI server) trade-offs
| | Stored credentials | IAM roles | OIDC |
|---|---|---|---|
| Example | CircleCI | Jenkins on an EC2 Instance | GitHub Actions |
| Avoid manually managing credentials | x | ✓ | ✓ |
| Avoid using permanent credentials | x | ✓ | ✓ |
| Works inside of cloud provider | x | ✓ | x |
| Works outside of cloud provider | ✓ | x | ✓ |
| Widely supported as of 2022 | ✓ | ✓ | x |

### Table 6-3 — Passing secrets to resources/data sources
| | Env variables | Encrypted files | Centralized secret stores |
|---|---|---|---|
| Keeps plain-text secrets out of code | ✓ | ✓ | ✓ |
| All secrets management defined as code | x | ✓ | ✓ |
| Audit log for access to encryption keys | x | ✓ | ✓ |
| Audit log for access to individual secrets | x | x | ✓ |
| Rotating or revoking secrets is easy | x | x | ✓ |
| Standardizing secrets management is easy | x | x | ✓ |
| Secrets are versioned with the code | x | ✓ | x |
| Storing secrets is easy | ✓ | x | ✓ |
| Retrieving secrets is easy | ✓ | ✓ | x |
| Integrating with automated testing is easy | ✓ | x | x |
| Cost | 0 | $ | $$$ |

(Pricing anchors: AWS KMS ≈ $1/key/month + $0.03 per 10k API calls — typically $1–$50/month total; AWS Secrets Manager ≈ $0.40/secret/month + $0.05 per 10k API calls — typically $10–$25/month small, up to hundreds of dollars/month large; self-managed Vault adds developer time, potentially thousands of dollars/month.)

### Secret-state taxonomy (implicit in the chapter)
The chapter's security model spans four locations a secret can exist: **in code / in VCS** (forbidden in plain text), **in memory** (env vars, aws-vault's temporary STS credentials), **in encrypted storage** (KMS ciphertext in files, or a centralized store's data store), and **in state and plan files** (plain text, unavoidable — mitigate with encrypted backends and strict access control).

## Worked Example
**Wiring OIDC provider auth from GitHub Actions to AWS (the chapter's flagship machine-user flow):**

1. **Fetch GitHub's OIDC thumbprint** so AWS can trust the endpoint:
   ```hcl
   data "tls_certificate" "github" {
     url = "https://token.actions.githubusercontent.com"
   }
   ```
2. **Create the IAM OIDC identity provider** in your account:
   ```hcl
   resource "aws_iam_openid_connect_provider" "github_actions" {
     url             = "https://token.actions.githubusercontent.com"
     client_id_list  = ["sts.amazonaws.com"]
     thumbprint_list = [
       data.tls_certificate.github.certificates[0].sha1_fingerprint
     ]
   }
   ```
3. **Define an IAM role with EC2 admin permissions** ("who may assume" via the federated trust policy above, restricting `sub` to `var.allowed_repos_branches` entries like `org/repo/branch` = `brikis98/terraform-up-and-running-code/main`; "what they can do" via `ec2:*` on `*`):
   ```hcl
   resource "aws_iam_role" "example" {
     name_prefix        = var.name
     assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
   }
   resource "aws_iam_role_policy" "example" {
     role   = aws_iam_role.example.id
     policy = data.aws_iam_policy_document.ec2_admin_permissions.json
   }
   ```
4. **In the workflow**, grant `id-token: write` permission, then authenticate before Terraform runs:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v1
     with:
       role-to-assume: arn:aws:iam::123456789012:role/example-role
       aws-region: us-east-2
   - uses: hashicorp/setup-terraform@v1
     with:
       terraform_version: 1.1.0
       terraform_wrapper: false
   ```
   When the build runs on an allowed repo/branch, GitHub mints an OIDC token, AWS exchanges it via `AssumeRoleWithWebIdentity` for temporary credentials, and `terraform apply` authenticates as the role — zero stored credentials.

## Key Takeaways
1. **Never store secrets in plain text** — not in `.tf` code, provider blocks, or version control: every clone, CI box, and backup keeps a copy with no audit or revocation path.
2. **Match the credential mechanism to the runner**: humans → personal secrets manager + env vars (or `aws-vault`/`op` for CLI convenience); machines → OIDC > IAM roles > stored credentials, in that order of preference.
3. **IAM roles beat stored credentials**: no manual management, and credentials are temporary and auto-rotated via the instance metadata endpoint. OIDC gets you the same properties when the CI runs outside your cloud account.
4. **Pick the resource-secret technique against Table 6-3**: env vars for free/testing-first, encrypted files for secrets versioned with code, secret stores when per-secret audit logs and rotation matter.
5. **Terraform always writes secrets passed to resources into state and plan files in plain text** — this is an unresolved upstream issue, so encrypt those files (TLS in transit, AES-256 at rest, e.g., S3/GCS/Azure Blob backends) and gate access with IAM policies as tightly as the secrets themselves.
6. **Scope federation policies tightly**: the OIDC assume-role policy must `condition` on the repo/branch `sub`, or every GitHub repo can assume your role; likewise restrict or disable the EC2 instance metadata endpoint.
7. **Don't scrub secrets from state** via workarounds — they break with each Terraform release; rely on backend encryption and access control instead.

## Connects To
- **Ch. 3 (Terraform syntax/modules)** — introduced `sensitive = true` variables and the `TF_VAR_*` convention reused here; the S3 remote backend pattern from Ch. 3 returns as the encrypted-state requirement.
- **Ch. 4–5 (Module/create-before-destroy patterns)** — the `aws_db_instance` running example and `aws_iam_policy_document` JSON-generation pattern recur.
- **Ch. 7 (Multi-provider: multi-region/accounts/clouds)** — the immediate next topic; provider auth across accounts builds directly on IAM roles assumed here.
- **Ch. 9 (CI/CD workflows)** — the CircleCI/Jenkins/GitHub Actions snippets here are deliberately simplified; production-ready pipelines (including plan-file handling between plan and apply) come in Ch. 9.
- **aws-vault's STS temporary credentials** foreshadow the assume-role and MFA workflows used for human access at scale in later chapters.