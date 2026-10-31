# Chapter 10: Testing and refactoring

## Core Idea
Terraform code rots like any code — refactor with module expansions for_each and state migration (`terraform state mv`, `terraform state rm` + `terraform import`), and keep confidence with module-level integration tests via terraform-exec (init → apply → validate outputs → destroy).

## Frameworks Introduced
- **The Three Signs a Refactor Is Due** (in flat, copy-paste module code): duplicated code (copy/paste per service file), name collisions, inconsistency (non-expert PRs) → fix all three at once by extracting a module
- **Module Expansions** (`count`/`for_each` on modules, Terraform 0.13+): declare once, expand per key
  - Rule of thumb: prefer **maps over sets** when a module needs more than one attribute — sets are limited to `set(string)` and force awkward JSON round-trips; use count only when positional access is needed
- **State Migration Decision Tree**: refactor changed resource addresses → plan shows destroy+recreate → move state so it isn't lost
  - Option A: `terraform state mv SOURCE DESTINATION` (preferred; addresses may be any string — double check)
  - Option B: `terraform state rm ADDRESS` then `terraform import ADDRESS ID` (also how unmanaged resources become managed — the import analogue of ch2's refresh)
  - Option C: hand-edit the state file — not recommended except niche provider-error fixes
- **Testing Levels for IaC**: unit tests live at the provider level (skip); static analysis = `terraform validate`/tflint (fast, run first); integration tests = a module deploys and produces expected outputs (the sweet spot, keep modules small); system tests = whole project + regression/perf (subjective)
  - Plan-is-not-a-dry-run rule: `terraform plan` refreshes data sources, and data sources can execute arbitrary code
  - In CI/CD: static analysis **before** integration testing (integration is slow)

## Key Concepts
- **terraform taint / untaint**: mark a resource for destroy+recreate on next apply, without destroying the whole stack (e.g. rotate access keys every ≤90 days); untaint undoes the mistake
- **terraform state list / show**: enumerate addresses and read a resource's ID (set at provider level, not always intuitive — check provider docs)
- **terraform import**: needs the config declared + the resource ID; post-import state ≠ configuration (config-only attrs like `force_destroy` come back `null`) → run `terraform apply` to reconcile
- **state rm's other job**: removing buggy resources that block apply/destroy on corrupted states (usually buggy provider code → file a GitHub support ticket)
- **Splat limitation**: `[*]` works on lists only, not maps — so you can't splat across for_each modules; write the for expression `[for m in module.iam : m.credentials]`
- **Policy files pattern**: load docs from a `policies/*.json` folder with `{ for path in fileset(path.module, "policies/*.json") : basename(path) => file(path) }` instead of inline string literals
- **Credentials-file assembly**: each module instance outputs a three-line template string; join them: `join("\n", [for m in module.iam : m.credentials])`
- **terraform-exec vs Terratest**: both Go libraries; terraform-exec has full CLI feature parity + a sister library (terraform-json) to parse state as Go structs — "the more polished of the two"

## Code Examples
```hcl
# Module expansion: one declaration, one instance per key of a map
locals {
  policy_mapping = {
    "app1" = { policies = [local.policies["app1.json"]] },
    "app2" = { policies = [local.policies["app2.json"]] },
  }
}
module "iam" {
  source      = "./modules/iam"
  for_each    = local.policy_mapping
  name        = each.key
  policies    = each.value.policies
}
resource "local_file" "credentials" {
  filename = "credentials"
  content  = join("\n", [for m in module.iam : m.credentials])
}

# State migration for the refactored addresses
terraform state mv aws_iam_user.app1 'module.iam["app1"].aws_iam_user.user'

# Integration test skeleton (terraform-exec Go)
tf.Init(ctx, tfexec.Upgrade(true))
defer tf.Destroy(ctx)                       // destroy runs even if the test fails
tf.Apply(ctx, tfexec.Var("bucket_name=<unique-id>"))
state, _ := tf.Show(ctx)
resp, _ := http.Get(state.Values.Outputs["endpoint"].Value.(string))
if resp.StatusCode != http.StatusOK { t.Errorf("status code did not return 200") }
```
- **What it demonstrates**: flat module → nested modules with expansions, state moved so apply shows "7 to add, 0 change, 5 destroy" instead of destroying the users; and the go test pattern (70s) that always cleans up.

## Key Takeaways
1. Self-service provisioning = PR-driven workflow: reviewers only need to read the plan output.
2. Never migrate state by losing it: mv what must survive; rm+import what can safely rotate.
3. After any import, immediately `terraform apply` — config-only attributes import as null.
4. Taint is the targeted replace for secrets rotation; untaint is the undo.
5. Write integration tests at the module level and run validate before them in CI.

## Connects To
- **Ch 2**: resource lifecycle semantics that taint/manipulate
- **Ch 6**: flat vs nested modules — this chapter is the migration path between them
- **Ch 13**: credentials files and access keys are secrets; Vault/Secrets Manager are the real home for them
- **Ch 12**: these tests slot into the CI/CD pipeline for Terraform itself