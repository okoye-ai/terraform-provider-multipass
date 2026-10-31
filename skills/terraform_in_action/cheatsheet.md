# Cheatsheet — Terraform in Action (Winkler's judgment on one page)

## Decision rules: what Terraform is for
- Deploying **infrastructure that changes slowly**? → Terraform. Application code changing daily? → CI/CD or Ansible (two-stage deployment). Terraform plans are too slow to front app deploys.
- Config management vs provisioning: provisioning deploys infra (Terraform); CM deploys software onto it (Ansible). "Terraform and Ansible: better together."
- Provisioners / local-exec: **last resort only**. HashiCorp calls them an anti-pattern; prefer Shell provider (full lifecycle, no Go) → custom provider in Go → never null_resource hacks.
- `for_each` over `count` whenever possible; `count` only when position matters (cycling templates). Maps over sets for module expansions when >1 attribute per instance.
- Blue/Green lifecycle: databases belong in the **base** layer; deploy new version to the **idle** env; cutover = flip `var.production`.
- Implicit dependency (`a.b` interpolated) > explicit `depends_on`; if forced explicit, document why.

## Decision tree: what will this plan do?
```
Resource in state? ─ No → Create()
Yes → Read() (refresh)
  Changes? ─ No → No-op
  Yes → Destroy plan? ─ Yes → Delete()
        Attr force-new? ─ Yes → Destroy + Create (-/+)
                          └ No → Update in-place (~)
```

## Command cheat table
| Goal | Command |
|---|---|
| Dry-run / lint | `terraform plan` (also refreshes data sources — not a safe sandbox) |
| Inspect state | `terraform state list` / `state show <addr>` / `show -json plan.out` |
| Move address | `terraform state mv SRC DST` |
| Orphan / re-admit | `state rm ADDR` → `import ADDR ID` → `terraform apply` (reconciles null attrs) |
| Rotate a resource | `terraform taint ADDR` (+ `untaint` to undo) |
| Multi-env | `workspace new/select dev` + `apply -var-file=dev.tfvars` |
| Graph | `terraform graph` (DOT) |
| JSON deps of plan | `terraform plan -out plan.out && terraform show -json plan.out` |
| Debug | `TF_LOG=trace` (off again afterwards!) |

## Thresholds & defaults
- Rotate access keys: **at least every 90 days** (Vault tokens: 20 min TTL; trace-log creds valid ~15 min).
- One workspace's modules: ≤ **3–4 levels deep**; file: ≤ a few hundred lines.
- ASG quorum math (ch8): Raft needs an **odd** count; 3 servers minimum per cluster.
- Provider blocks: version-lock everything third-party (`~>`); read-lock files go in version control.
- Backend block is init-time const: **no variables inside**. That's what the `echo $BACKEND >> backend.tf.json` trick is for.

## Secret-leak tells (you're exposed if you see these)
- `TF_LOG=trace` in CI → signed credentials (15-minute window) in every log.
- Secrets in Lambda `environment {}` → console-readable by anyone with read access. Use `SECRET_ID` + runtime fetch.
- `sensitive = true` giving false confidence → any local_file→data.local_file→echo round-trip prints it. Reference-scrubbing only.
- `data "external"`, `data "http"` with interpolations → runs at **plan** time (fork PRs can trigger it).
- `output { value = var.<secret> }` or `local_file { content = var.<secret> }` → the simplest exfiltration.
- State treated casually → only resources/data sources/outputs persist state; providers, variables, locals don't — audit accordingly.

## Idioms worth memorizing
```hcl
# Feature flag creating 0 or 1 of anything
count/for_each = var.enabled ? 1 : 0            # resources
dynamic "stage" { for_each = var.enabled ? [] : [1] content { ... } }   # nested blocks

# Random-padded global namespace
locals { namespace = substr(join("-", [var.namespace, random_string.rand.result]), 0, 24) }

# Cycle K items across N instances
templatefile(element(local.templates, count.index), {...})

# Load policy files from disk instead of inline literals
{ for path in fileset(path.module, "policies/*.json") : basename(path) => file(path) }

# Join expanded module outputs
join("\n", [for m in module.iam : m.credentials])

# Conditional env-var provider config (Go, EnvDefaultFunc)
DefaultFunc: schema.EnvDefaultFunc("PETSTORE_ADDRESS", nil)
```

## Pipeline shape (Terraform managing Terraform)
Source → Plan → **Approve (manual)** → Apply; destroy runs via `CONFIRM_DESTROY=1`; `TF_IN_AUTOMATION=1`, `TF_INPUT=0`; least-privileged deployment policy per project (never admin). Sentinel checks sit between plan and apply (Enterprise-only).

## Build-vs-buy tells for registry modules
- Trust: high GitHub stars + skimmed source + version-locked. Watch for: local-exec in modules, external data sources, shim modules shipping binaries, missing README/standard structure/semver.