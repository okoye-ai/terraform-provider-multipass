# Cheatsheet — Hafner's Decision Rules

## Deprecated / never use
| Instead of... | Use... |
|---|---|
| `terraform taint` | `terraform plan -replace=<resource>` (taint is deprecated) |
| `terraform refresh` | `terraform plan -refresh-only` / `apply -refresh-only` |
| `null_resource + triggers` | `terraform_data` (v1.4+) |
| Hardcoded provider without `required_providers` | Declare `required_providers` (inferred providers lose version pinning) |

## State safety rules
- Local backend = dev only (fails resiliency + security + availability).
- Never a backend without locking (S3 needs DynamoDB) — state corrupts under concurrency.
- `state pull` a backup before ANY state manipulation. Untested backups are worthless.
- Manual state edit (last resort): back up → JSON-validate → diff → increment serial by 1.
- `state push` guards lineage/serial; reverting needs `-force`.
- Terraform created something but state save lost? Import it or delete it for real.
- State exposes ALL attributes incl. sensitive values in plaintext — restrict backend access, prefer data-source lookups or secret-manager paths over `terraform_remote_state`.

## Drift response flow
1. Detect: `plan -refresh-only` → categorize (machine error: conflicting automation / Terraform error; human error: accidental / intentional).
2. Intentional manual change → freeze Terraform → codify it in code or add `ignore_changes`.
3. Verify with `refresh-only`, restore backups with `state push -force` if needed.

## Tool selection
- **Security scans**: Checkov + Trivy both (incomplete overlap; both free). Skips differ: `#checkov:skip=<ID>:<reason>` (reason mandatory) vs `#trivy:ignore:<ID>`.
- **Custom policy**: default Checkov YAML policies (shared repo + `--external-checks-git`); OPA/Rego only if team already knows it.
- **CI platform**: SCM built-in (GitHub Actions/GitLab Pipelines) unless your org has none; runners `ubuntu-latest`.
- **CD platform**: prefer multi-IaC + OPA support (Spacelift/Env0/Scalr…); Terraform-only or OSS-only constraints narrow it; Infracost covers AWS/Azure/GCP only. (Matrix in ch08.)
- **Testing framework**: native `.tftest.hcl` for new suites; Terratest for multi-version support — native pins you to your lowest supported version (v1.7 mocks exclude v1.6).
- **Module consumption**: registry + pessimistic constraint `~> 1.1`; Git sources only for dev branches; environment-as-root pins EXACT version in prod.

## Plan & apply rules
- Always `plan -out`, then apply the FILE (reviewed = executed).
- Plan output reads bottom-to-top = execution order; destroy runs in reverse creation order.
- `# forces replacement` → check dependency chain for cascades; silence justified ones with `ignore_changes`.
- `Error: Cycle:` → break with a shared variable/local.
- `count`/`for_each` values must resolve at plan start — no resource attributes, no impure functions; use a local + `element()`.
- Immediate re-drift after apply → impure function (`uuid`/`timestamp`); switch to `random_*`/`time_*` resources.
- `-refresh=false` and `-lock=false` are danger flags: valid only in speculative/dev plans.
- `-parallelism=1` + `TF_LOG=debug` to read interleaved action logs. Default parallelism = 10.
- Variable precedence (highest wins): CLI flags > auto.tfvars > terraform.tfvars.json > terraform.tfvars > `TF_VAR_` env > interactive — pick ONE method.
- Building JSON/YAML/IAM docs: use `jsonencode`/`yamlencode`/policy-document data sources, never string templates.

## Secrets
- Never via `-var`, tfvars files, or plain env (visible in process lists/shell history).
- Prefer OIDC (eliminate) > secret manager + pass PATHS (centralize) > orchestrator settings.
- Sensitive flag ≠ excluded from state. Outputs derived from sensitive values must be sensitive.

## Tests & refactoring
- Random names: `random_string` len 8, lowercase, no special chars — enables concurrent test runs.
- Timeout: raise Go default (10 min) to `-timeout 60m`; timeouts orphan resources and lose state.
- Deletion never skipped — schedule "<Vendor> Nuke" against isolated test accounts only.
- Rename variables via expand-and-contract (old=null default, local prefers old) — delete old in next major.
- Breaking changes: batch, ≤1 major/year, keep `moved` blocks.
- `Unknown condition value` assert error → you read an apply-time output in a plan-run test; use apply-run or plan modifiers.
- Test logic (transforms, regex, dynamic blocks 0/1/many, endpoint behavior) — never pass-through attributes.

## Design tells
- Provisioner requested → check Table 10.4 alternatives first (images / Cloud-Init / shutdown service / outputs+local provider) — provisioners are last resort.
- Don't use Terraform for: K8s workload objects (kubectl/Helm/ArgoCD), building container/machine images, artifact deployment.
- Naming: Unique, Human readable, Identifiable, Sortable — pet-name randomness fails identifiability.
- Splitting a CIDR into 3 → bits are powers of 2: halve, then halve.
- `check` block with no implicit dependency → add `depends_on` or it fails on first plan. (v1.9+: cross-variable validation belongs in variable validation blocks.)
- Wrap .tofu/.tf: Terraform ignores `.tofu`; OpenTofu prefers `.tofu` over matching `.tf`.
- CDKTF output alongside HCL → duplicate block errors; delete generated HCL before deploy.

## Provider development
- Design interfaces first: user-facing HCL example → schema → implementation.
- Collect Diagnostics; don't return early. Never `log.Fatal` (corrupts state).
- Normalize server-mutated fields in Create, Update AND Read (else eternal drift).
- Credentials: Optional attrs + env fallbacks so credential swaps need no code change.
- Local dev: `go install` + `dev_overrides` in `~/.terraformrc` (keep `direct {}`).
- Acceptance tests: `TestAcc*` prefix, `TF_ACC=1`; unit tests for functions: `tfversion.SkipBelow(1.8.0)`.

## Thresholds & defaults
| Thing | Value |
|---|---|
| Apply parallelism default | 10 |
| Test timeout | 60m (vs Go default 10m) |
| random_string test names | len 8, lowercase, no special |
| Refactoring budget (mature codebase) | ~20% |
| Breaking majors | ≤1/year, batched |
| High-performer deploy cadence (DORA) | multiple times daily |
| CI matrix engine versions | 1.6–1.8 stable + latest experimental |
| Three-AZs | standard HA baseline (1–4 supported) |