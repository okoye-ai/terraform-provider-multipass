# Cheatsheet — Decision rules from Terraform Up & Running, 3rd Ed.

## IaC tool stack
| Need | Choose |
|---|---|
| >1 server, manual management breaking down | Purpose-built IaC tool (not ad hoc scripts) |
| Config on mutable servers, no templating | Terraform + Ansible |
| Immutable servers, simple stack | Terraform + Packer |
| Blue-green / canary / auto-healing / autoscaling | Terraform + Packer + Docker + K8s |
| Untrusted third-party code isolation | VM (not container) |

## State management
- **Team on one product? → remote backend immediately** (not Git for state: stale state, no locking, plaintext).
- **Never** reuse a backend `key` between modules — silently overwrites other teams' state.
- Isolation: **workspaces for experiments, folder-per-env×component for real isolation, separate AWS accounts for prod** — never workspaces for stage-vs-prod.
- Share **one** S3 bucket + DynamoDB (`LockID` string hash key) per account, once.
- `prevent_destroy` on anything catastrophic to delete.

## Loops, conditionals, refactoring
| Situation | Use |
|---|---|
| Replication keyed by name; may remove items / per-item config | `for_each` (lists → `toset()`) |
| Fixed number N of copies | `count` |
| 0-or-1 resource switch | `count = cond ? 1 : 0` |
| Optional inline block | `dynamic` + `content` |
| Transform/filter collections | `for` expression |
| Template text loops/ifs | `%{ for/if }` with `~` markers |
| Rename resource/module or count→for_each | `moved` block (or `terraform state mv`), success = plan shows no changes |
| Infra made by hand that apply now fails on | `terraform import` — never manage manually again |

- `count`/`for_each` may use **only plan-time-known values**: constants, variables, data sources, known-length lists — never computed resource outputs.
- Zero-downtime: prefer **native** (ASG instance_refresh, ECS deployment %, k8s RollingUpdate) over create_before_destroy glue.

## Secrets
| Machine CI context | Auth method |
|---|---|
| CI runs inside cloud | IAM role |
| CI outside cloud, OIDC supported | OIDC (scope `sub` per repo/branch!) |
| Neither | Stored credentials (last resort) |

| Resource-secret technique | Cost | Best for |
|---|---|---|
| Env vars | $0 | testing |
| Encrypted files in VCS | KMS $1/key/mo | versioned-with-code |
| Central secret store (Vault/Secrets Manager) | $0.40/secret/mo | audit + rotation |

- `sensitive = true` hides values from **logs**, never from **state**: encrypted backend + strict access control are mandatory either way.
- Never attempt state-scrubbing workarounds (break every release).

## Providers & versioning
- Always `required_providers` with explicit source + version; commit `.terraform.lock.hcl`.
- Version pins: Terraform core `">= 1.0.0, < 2.0.0"` (exact in prod: `1.2.3`); providers `"~> 4.0"` + lock file; modules `?ref=vX.Y.Z` (tags, never branches/sha1s).
- **Provider blocks only in root modules**; reusable modules declare `configuration_aliases`, caller injects via `providers = { ... }`.
- Aliases only for truly coupled infra (e.g. CloudFront certs must exist in us-east-1); otherwise separate module per region/account.
- Never create provider credentials and consuming resources in the same module (auth race).

## Production-grade modules
- **Small modules** — >few hundred lines = harmful (slow, hard to review/test); split by domain.
- Every module gets `examples/`; every example gets tests; design the API through the example (TDD).
- Validation ladder: `validation` (per-variable) → `precondition` → `postcondition` (`self.<attr>` only) → Terratest/OPA.
- Prefer **User Data over provisioners**; provisioners / null_resource / external data source = last-resort escape hatches.
- Production build times (plan accordingly): managed service 1–2 wks; stateless ASG app 2–4 wks; stateful cluster 2–4 mo; whole architecture 6–36 mo.

## Testing
| Layer | Tool | Cost |
|---|---|---|
| Syntax/lint | validate, tfsec, tflint, Terrascan | free, no auth |
| Policy on plan | OPA, Sentinel, Checkov | auth, no deploy |
| One module | Terratest unit | ~4–5 min |
| Modules together | Terratest integration | 10–15 min |
| Whole system | Terratest E2E / persistent env | most |

- Static > plan > server > unit > integration > E2E (fast/cheap/stable ranking) — start with static analysis, grow the pyramid (many unit, fewer integration, few E2E).
- Always `defer terraform.Destroy` (declared before InitAndApply); namespace test resources; retries: terraform 3×/5 s, HTTP 10×/10 s, `go test -timeout 30m`; cron-run cloud-nuke `--older-than 48h` on accounts.
- E2E from scratch vs persistent env: full-apply E2E gets slow/brittle past ~600 resources.

## Team workflow (the book's core rules, near-verbatim)
- **Golden Rule**: main branch of the live repo = 1:1 representation of what's actually deployed in production.
- Always run `plan` before `apply` — read the diff; `-/+` = replacement = downtime.
- Always test changes in pre-prod before prod — IaC has no auto-rollback.
- Any shared environment deploys from a **single branch**.
- Health check: run a random `terraform plan` in live-repo folders — **"no changes"** is the gold standard (drift detection).
- Every production apply approved by ≥1 person other than the requester.
- Infra code is never deployed like app code (no auto-deploy to prod); CI keeps temporary credentials, isolated admin worker.