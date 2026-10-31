# Cheatsheet — Decision Rules & Thresholds

## Decision rules (when X, do Y)

| When | Do | Because |
|---|---|---|
| Copying a resource block a 2nd time | Extract into a module | Duplication drifts; module contract scales |
| Team > 1 person touching infra | Move state to a remote backend now | Local copies collide; locking serializes runs |
| Resource deleted outside Terraform | `terraform state rm <addr>` | Prevents unwanted recreation on next apply |
| Renaming/refactoring resource addresses | `terraform state mv old new` **before** editing code | Avoids destroy + recreate |
| Plan shows something you didn't intend | Stop, find the variable/extraneous block | Plan surprises mean code-state mismatch |
| Applying in a pipeline | `plan -out=` → review → `apply <file>` | Reviewed plan = deployed plan |
| N near-identical copies | `count = var.n` | Simplest loop for uniform copies |
| Resources differ by names/keys | `for_each = var.map` | Stable addresses; index shift problem avoided |
| Repeated sub-blocks (rules) inside a resource | `dynamic` block | One variable drives all rule edits |
| Provisioner job could be a native resource | Skip the provisioner | Provisioners sit outside the declarative model |
| Provisioner job is at-boot OS config | cloud-init / user-data / custom data instead | More robust than SSH-after-create |
| Provisioner job is ongoing changes | config-management tool (Ansible/Chef) | Provisioners don't re-run on updates |
| Secret needed in a resource | `data "azurerm_key_vault_secret"` lookup | Never embed credentials in code |
| Credential rotates monthly | Update in vault; consumers pick it up next run | Versioned secrets + read-at-startup consumers |
| Credential is powerful + long-lived | Vault dynamic secret | Lease expiry deletes credential + principal |
| Legacy resource must come under Terraform | Write block → `terraform import` → require "No changes" plan | Confirms code matches reality |
| Policy violations must never deploy | OPA/tfsec against plan JSON in CI | Compliance gates before apply |
| Test a module's wiring to siblings | Integration test in Terratest | Cross-module outputs resolve or fail loudly |
| Test deployed behavior (HTTP works) | Validation test: `HttpGetWithRetry(url, 200, "", 10, 5s)` | "Code looks right" ≠ "system responds" |
| API returns 429 | `-parallelism=5`, batch, or retry after delay | Throttle, not a code bug |
| API returns 403 AuthorizationFailed | Fix RBAC: `az role assignment create` | Permissions, not Terraform |
| SKU/region error on VM | `az vm list-skus`; change size or region | Availability, not config logic |
| Stale state lock | `terraform force-unlock LOCK_ID` **only** after verifying nothing runs | Forced unlock corrupts state otherwise |

## Error triage tree
```
Does `terraform validate` fail?
├─ Yes → SYNTAX: brace/keyword/operator issue; fix per parser hint
└─ No → Does `terraform plan` fail?
   ├─ Yes → SEMANTIC: undeclared reference / wrong type / CIDR outside parent
   └─ No → Apply fails → RUNTIME: read provider code
      ├─ 403 → RBAC assignment
      ├─ 429 → parallelism / batching / retry
      ├─ 404 / "inconsistent with state" → drift: re-import or untrack
      └─ premature-dependency failure → re-run; add explicit depends_on
```

## Thresholds & defaults (from the book)
- SSH readiness window after VM create: **30–60s** → retry/timeout logic
- `-parallelism`: **10** normally safe; **5** under throttling
- Key Vault `soft_delete_retention_days`: **7–14**
- Log Analytics retention: **30 days**; AuditEvent category retention: **7 days**
- Validation-test retry: **10 attempts, 5s apart**
- AKS default_node_pool example: **3 nodes, Standard_DS2_v2**, cluster creation takes **several minutes**
- Subnet sizing pattern: VPC `/16` → per-purpose `/24` slices (`10.0.1.0/24`, `10.0.2.0/24`)
- ASG sizing pattern: min 1, max 5, desired 2 with `create_before_destroy`

## Tells & smells
- Many inline `remote-exec` commands → configuration management belongs elsewhere
- Proliferating `null_resource` blocks → codebase going imperative
- `Error: Reference to undeclared resource` → typo'd or renamed label (search `grep -c` the name)
- Plan full of `~` changes you didn't make → variable definitions changed or drift present
- Provisioner failed mid-apply → resource is tainted; next apply replaces it — check script idempotency
- `terraform plan` after import ≠ "No changes" → your block doesn't match reality yet; fix before refactoring
- Secrets readable in `plan` output → missing `sensitive = true` / wrong storage channel
- Two subnets colliding on apply → move to `cidrsubnet()` derivation from one CIDR variable
- Test suite leaving resources behind → missing `defer terraform.Destroy`

## Naming & structure conventions
- `modules/<name>/{main.tf, variables.tf, outputs.tf}` + README documenting inputs/outputs/examples
- `variables.tf` in every root; `terraform.tfvars` git-ignored for secrets
- Interpolation in strings only (`"myapp-${var.env}-vm"`); bare references elsewhere
- Tag releases `v1.2.1`; bump major when compatibility breaks