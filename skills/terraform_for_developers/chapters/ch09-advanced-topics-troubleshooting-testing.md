# Chapter 9: Advanced Topics — Troubleshooting, Import, and Testing

## Core Idea
Classify every Terraform error as syntax, semantic, or runtime — each arises at a different workflow stage and gets a different debugging strategy — then build the four-layer test suite (unit → integration → validation → compliance) so "the code looks right" becomes "the system behaves right."

## Frameworks Introduced
- **Three Error Categories** — triage by where the failure appears:
  - **Syntax**: code won't parse (missing braces, bad operators); caught by `terraform validate`/editor linting
  - **Semantic**: parses fine, logic wrong (undeclared references, wrong data type, subnet outside VNet CIDR); caught at `plan`
  - **Runtime**: valid code, cloud-side failure (permissions, throttling, region availability, drift); appears at `apply`
  - Plus the specialized set: concurrency collisions, state locks, partial applies — structural fixes (remote state, pipeline concurrency)
- **The Import Procedure**: write the resource block → find the real resource ID (`az group show --query id --output tsv`) → `terraform import <addr> <id>` → `terraform plan` must show **"No changes"**; for bulk imports use terraformer; check `terraform state list` first to avoid double-import
- **Four-Layer Test Suite** (all with `defer terraform.Destroy`):
  - **Unit** (Terratest): one module/resource in isolation; apply with test vars, assert outputs non-empty/pattern-correct
  - **Integration**: compose vnet + vm + nsg modules; assert all cross-module outputs resolve — catches misspelled outputs and missing `depends_on`
  - **Validation**: test the *deployed system's behavior* — `http_helper.HttpGetWithRetry(url, 200, "", 10, 5s)` against the output public IP
  - **Compliance** (OPA/tfsec/checkov): Rego policies evaluated against `terraform show -json tfplan`; non-empty `data.main.deny` fails the pipeline

## Key Concepts
- **`-parallelism=N`**: tune concurrent resource operations; 10 is usually safe, higher risks API throttles
- **HTTP 429 TooManyRequests**: throttle signature — reduce parallelism, batch creations, or raise quotas
- **HTTP 403 / AuthorizationFailed**: RBAC missing — `az role assignment create --role Contributor --assignee <object_id>`
- **`depends_on`**: explicit ordering when the implicit graph isn't enough (slow NAT gateway before its route)
- **Taint/drift runtime signatures**: "inconsistent with the state" → re-import if it exists, remove references if intentionally gone
- **`terraform show -json tfplan`**: the JSON plan that compliance tools parse
- **KPIs for Terraform practice**: execution speed, resource utilization (ephemeral cost), error rates, maintainability (duplication ratio, tflint/tfsec cleanliness), deployment frequency + lead time

## Code Examples
```rego
# OPA/Rego compliance policy: require HTTPS-only storage accounts
package main
deny[msg] {
  input.resource_changes[_].type == "azurerm_storage_account"
  after := input.resource_changes[_].change.after
  after.enable_https_traffic_only == false
  msg := sprintf("Storage account %v must have HTTPS traffic only", [after.name])
}
```
```bash
terraform plan -out=tfplan && terraform show -json tfplan > tfplan.json
opa eval --format pretty --data policy.rego --input tfplan.json "data.main.deny"
# CI gate: non-empty deny output → exit 1
```
- **What it demonstrates**: compliance as code — violations block the pipeline before apply

## Reference Tables
### Runtime error triage
| Signature | Cause | Fix |
|---|---|---|
| `AuthorizationFailed` (403) | Service principal lacks RBAC | `az role assignment create` with correct scope |
| `InvalidParameter` / region error | SKU unavailable in region | `az vm list-skus`; change size or `location` |
| `429 TooManyRequests` | API throttling | `-parallelism=5`, batch, retry with delay |
| Route can't find NAT gateway state | Slow resource allocation | Re-run apply; add explicit `depends_on` |
| "Inconsistent with the state" | External console change (drift) | Re-import via `terraform import`, or remove references |

### Test layers
| Layer | Scope | Tool | Asserts |
|---|---|---|---|
| Unit | single module | Terratest | outputs non-empty, naming pattern holds |
| Integration | module composition | Terratest | all module outputs resolve; wiring correct |
| Validation | live behavior | Terratest http-helper | HTTP 200 with retries, behavior in real env |
| Compliance | policy on plan JSON | OPA + Rego / tfsec / checkov | deny rules empty |

## Worked Example
Validation test against deployed Nginx: Terraform stands up the full environment (RG, VNet 10.0.0.0/16, subnet, static public IP, NIC, VM with remote-exec installing Nginx) and outputs `vm_public_ip`. Terratest then: `defer terraform.Destroy`, `InitAndApply`, read the output, and `http_helper.HttpGetWithRetry(t, "http://"+vmIP, 200, "", 10, 5*time.Second)` — retrying up to 10 times at 5s intervals to absorb boot/install lag. Timeout or 404 means the provisioner or wait logic needs adjustment.

## Anti-patterns
- **Treating all errors as one kind**: reading a parse error's API-style message or blaming the cloud for a typo — classify first, then debug
- **Unit testing against a shared live environment**: unit tests create their own throwaway stack; test-then-destroy keeps cost bounded
- **Skipping the "No changes" plan check after import**: an imported resource whose plan shows changes means your code doesn't match reality yet
- **Double-importing into existing module state**: check `terraform state list` first
- **Manual-only compliance review**: policy violations (missing encryption, open ports, untagged resources) must block in CI, not be caught by eyeballs
- **Confusing code correctness with behavior**: unit/integration green doesn't mean the deployed system responds — that's validation testing's job

## Key Takeaways
1. Triage by position in the workflow: won't parse → syntax; plan rejects → semantic; apply fails → runtime
2. Read the provider's API error code (403/429/404) before changing anything — it names the class of fix
3. Import is: write block accurately, `terraform import`, then require a clean "No changes" plan
4. `defer terraform.Destroy` is non-negotiable in Terratest — ephemeral test environments keep cost and residue at zero
5. Layer the test pyramid: unit (fast, isolated) → integration (wiring) → validation (live behavior) → compliance (policy gates)
6. Compliance gates evaluate the plan JSON, so policies run *before* anything touches production
7. Track Terraform KPIs like any engineering system: lead time and error rate reveal pipeline health

## Connects To
- **Ch 5**: drift and state mismatch are the bridge between runtime errors and state management
- **Ch 8**: semantic subnet-CIDR errors and NAT-gateway runtime issues are network cases
- **Ch 10**: CI/CD pipelines operationalize the compliance gates and test layers assembled here