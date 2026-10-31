# Cheatsheet — Terraform Cookbook (Satirli & Dolezal)

*Decision rules, thresholds, and smells — the authors' judgment in one page.*

## When Terraform / When something else
| Situation | Tool choice |
|---|---|
| Multi-provider, multi-env, complex resource graphs | **Terraform / OpenTofu** |
| Single server / single vendor, tiny footprint | Ansible/Puppet or the provider's native tool (CloudFormation, ARM) |
| PaaS (Netlify, App Engine) | Skip IaC — the platform owns the infra |
| "Snowflake" system with unique needs | Try to codify anyway if the org has an IaC mindset; manual config only for genuinely bespoke systems |

## Validation ladder — what catches what
| Layer | Catches |
|---|---|
| `terraform fmt` → `validate` | Style, syntax, types (no state touched) |
| `terraform console` | Expression behavior — experiment **before** committing |
| TFLint | Provider-specific errors early (bad instance types/AMI refs) |
| TFSec | Security smells: open SGs, hardcoded credentials |
| `validation` blocks | Bad input values, **at plan time, with a readable error** |
| `lifecycle.postcondition` | Wrong resulting state after create/update |
| OPA / Sentinel | Org rules: regions, tags, cost ceilings |
| GitHub Actions | All of the above on every PR |

Rule: **new variable → its `validation` block; new resource → its `lifecycle.postcondition` if a state guarantee matters**.

### String-cleaning defaults
- Leading/trailing whitespace → `trimspace`; trailing newline after `file()` → `chomp`
- Known affixes → `trimprefix` / `trimsuffix` (no native all-in-one trim)
- Pattern deltas → `regex`/`replace`; guard lookups → `can()` / `try()`
- Every cleaned input also gets a `validation` block with an explicit `error_message`

## Secrets decision tree
| Need | Reach for |
|---|---|
| Short-lived credentials | Dynamic Vault secrets (highest tier) |
| Static app secrets | Vault KV or password-manager bridge (external data source) |
| CI runs | `TF_VAR_*` env vars injected late; never plaintext in scripts |
| Anything stored | `sensitive = true` + audit + rotation schedule |
Smells: secret in a `.tf` file, secret in an `output`, secret in state, non-rotated static Vault token, `local-exec` anywhere near production.

## Blast-radius containment (do these always)
- One module per isolated unit of change; **separate workspace/state per env**
- Least-privilege IAM roles (e.g. read-only policy attachment, not `*`)
- Feature resources gated by `count = var.enable_feature_x ? 1 : 0`
- **Small, frequent applies** over sweeping ones
- `-target` only for documented emergencies — never routine
- Plan output is part of PR review; Sentinel/OPA as the backstop

## State rules
| Situation | Author-approved move |
|---|---|
| Lock conflicts | HCP Terraform state locking (preferred over manual) |
| Bad apply corrupted state | Workspace **States tab → select version → Restore** |
| Resource must be orphaned | `terraform state rm` — cautiously, with team notice |
| Drift detected | Re-run apply, or `import` the real resource |
| Default | Automated/backend mechanisms **over manual state surgery** |

## Containers & clusters
- **Deployment vs configuration** — provisioning the cluster ≠ managing what runs on it; separate lifecycles
- Schedule in HCL with `kubernetes_manifest`; existing YAML → `k2tf`; charts/monitoring → Helm provider; Nomad also viable
- Multiple accounts/regions/clusters → provider **aliases**; healthy-endpoint selection → `http` data source + `jsondecode` + ternary

## Upgrading & modules
- Major-version upgrade (0.x → 1.x): pin exact versions, read release notes, upgrade in a **copy of staging state first**
- Provider constraints: pin with bounded pessimistic constraints (e.g. `~>`), don't blanket-allow every major
- New provider auth: prefer role assumption/Vault over static keys; private registry modules need `credentials`/token config
- Public modules (e.g. EKS) from the Registry: pin `source` + `version`

## Repo & workflow defaults
- Everything in VCS; plan reviewed in PRs; smaller applies; auto-apply only with the full ladder in CI
- Dependabot for provider bumps — **review diffs before merging**, don't auto-merge
- Codespaces/DevContainers so every contributor has identical Terraform tooling