# Chapter 10: Validating at Scale

## Core Idea
Infrastructure validation differs fundamentally from application testing: HCL has no guaranteed order of operations (unless you overuse `depends_on`), and everything you build with Terraform in a CSP is production — live infrastructure doing real work. Central to validation is visibility, which CSP consoles make nontrivial (resources grouped by service/region; details only retrievable resource-by-resource). Validating once is not enough — you are sampling and poll-polling to approximate real-time visibility, and the question is how much you invest in better approximations. Prefer validations built into Terraform itself (especially `variable` `validation{}` blocks, guaranteed to evaluate at plan time) over heavyweight tooling, and treat TF tests as a separate lifecycle from application tests: judicious, case-by-case, not a default pipeline stage or a coverage-percentage mandate.

## Frameworks Introduced
- **Seven classes of Terraform validation**: (1) Internal I/O validation (TF constructs: `validation{}`, `precondition{}`, `postcondition{}`), (2) Data sources, (3) Static code analysis, (4) Behavior analysis (`tf test` / Terratest), (5) Externalized I/O validation (ancillary services validating custom inputs), (6) CSP auditing/monitoring, (7) TF-driven validation (`tf apply` checks consistency across the **state triplet** — HCL code, TF state, running CSP services), plus (8) access-log ingestion matched against `tf apply` results.
- **State triplet**: the consistency target of TF-driven validation — HCL code ⟷ TF state ⟷ CSP services.
- **Validation block precedence convention**: prefer `variable` `validation{}` over resource `precondition{}` (reserve the latter for combinations involving other resources' attributes or nested module outputs); prefer resource `postcondition{}` over output `precondition{}` (reserve the latter for outputs combining multiple entities). Establishing precedence by evaluation order finds invalid values as early as possible and avoids duplicated logic/responsibility.
- **Four-phase evaluation-timing model**: variable `validation{}` = guaranteed at plan; `precondition{}` = plan if computable, else apply; `postcondition{}` = always apply; `timestamp()` is never evaluated until apply time.
- **Custom control taxonomy** (for static analysis tools): gaps in regulatory compliance (e.g., industry policies beyond GDPR/HIPAA), gaps in specific controls (NIST/CIS sets missing from your tool), gaps in corporate policies (stricter than stock), relaxation of stock controls to reduce false positives, and relaxation for unconstrained workloads — the latter may vary per domain, and relaxed-control resources must be sequestered so they cannot taint compliance of constrained components. Regulatory controls should be expressed first.
- **Two-level observability validation split**: scheduled (superficial — attributes read from individual resources or TF state addresses) vs. on-demand (deep — reading related resources, probing resources, even spinning short-lived live resources to isolate account/CSP/environment causes). Deep reports act as the first layer of mitigation before paging on-call engineers.
- **Tool-migration procedure**: run the new tool against an existing repo in a sandbox via a general-purpose wildcard job (Ch. 6), diff its report against the current tool's report and control set; uncovered policies become the parity task list; same-language tools (Rego) are near copy-paste migrations; investigate divergent conclusions between old and new tools case-by-case.
- **Low-tech, low-cost solutions**: live code reviews (review *whatever is in flight*, not finished code — "too good" code elicits no scrutiny; can fold into stand-up; daily push should be mandatory policy), `tf validate` as a fast-fail step before planning (note: it does **not** run variable `validation{}` blocks), a Git pre-commit hook running linting/`tf validate`/`tf plan`, and mandatory TF outputs with a standard naming convention for all operator-relevant information.
- **TF observability strategy ladder**: (1) start with system access logs on day 0 (requires dedicated identities for every actor — automation and human — under strict access control), (2) layer TF validation reports in (stored separately from access logs, dedicated access controls, comparable field names so the two can be cross-referenced), (3) add correlated dashboards/alerts, (4) over time shift from scheduled checks to log-triggered on-demand checks, (5) do both: two-level regular/on-demand split, then optionally stitch in autonomous agents (remediation for well-worn solution paths; investigation suggestions for ambiguous activity — exceptions to automated remediation should be tagged, alerted, and eventually turned back into rules).

## Key Concepts
- **Variable `validation{}` blocks** (v1.9+): can reference *any* other variable, local values, and data source attributes, not just their own variable — enabling comprehensive cross-variable checks with plan-phase evaluation available to read-only operators (e.g., via Git pre-commit hook).
- **`precondition{}` placement heuristic**: if a check *can* be evaluated at plan time, promote it to a variable `validation{}` block (advertising guaranteed plan evaluation). Prefer preconditions for combining otherwise-unrelated variables/data sources, where assigning ownership to one variable's validation block would be arbitrary.
- **`postcondition{}` discipline**: use only for read-only/CSP-computed attributes; anything settable in the resource block should be pre-validated, so failure happens before TF attempts the change — a failed postcondition at apply does not roll back and can leave resources partially configured.
- **Data sources as availability checks, not just lookups**: TF reads them at plan phase and records their existence in state, so missing external data fails the plan instead of failing (or corrupting) the apply. Recommend using a data source even when the identifier itself is the input argument (e.g., VPC/subnet ID for a compute instance).
- **Reference specificity in GCP**: partially-specified references (e.g., `subnetwork = "snet-10"` without `subnetwork_project`) default to the provider project and can create resources in the wrong project or fail at apply — self-links are safer; prefer the most-specific identifier available as a data source attribute.
- **`sensitive()` wrapping**: data-source-retrieved secrets must be wrapped in `sensitive()` — the `sensitive` attribute of variables/outputs does not protect data source values; canonical external-secret pattern is HashiCorp Vault, especially for multi-CSP shared secrets.
- **TFLint**: provider-oriented lint beyond `tf validate` — validates CSP-specific values (real machine types), style standards, unused/dead code, and deprecations; HCL config file; reads `.tfvars` like `tf plan`; default runs root module only — extend to all module paths (run `tf init` first so external modules are available) or use `--recursive` for local modules. Limit per-module distinct standards to early-stage flexibility; mature ecosystems converge to universal standards.
- **Compliance tooling landscape**: KICS (Checkmarx), Aqua Trivy, Checkov — most operate above TF and cover wider IaC. OPA (Rego) is the general-purpose rules engine underlying tools like Trivy, making cross-tool migration cheap. Trivy/Checkov are single binaries = plug-and-play low-effort with high out-of-box coverage. "Implement at least one; unhelpful to implement many more than one" — overlap in coverage is a double-edged sword (corner-case catches vs. double the rule-maintenance work).
- **Checkov's graph advantage and its limit**: builds a TF-like resource graph and can check inter-resource relationships (superior to per-resource checks), but only within the directed state graph rooted at the root module — it cannot see cross-project relationships, so its advantage is severely diminished for layered, domain-driven IaC organizations.
- **`tf test` mechanics**: HCL-defined tests, does nothing by default; default mode runs `tf apply` as subprocess with an internal `tf destroy` cleanup; `command = plan` mode validates local values only (locals are pure functions — conventionally unit-testable) and avoids cost/time. Both modes fail on `lifecycle.prevent_destroy`, `deletion_policy = "ABANDON"`-style provider controls (cleanup fails), and CSP limits/quotas (resource creation exceeded).
- **Terratest mechanics**: Go-based; provisions the whole targeted module; can make HTTP requests and run shell commands — open-ended validation scope (you must manage the out-of-band API auth). Use `defer terraform.Destroy(...)` so teardown runs even when `tf apply` fails — a key advantage over `tf test`'s apply mode, which may exit before running destroy.
- **Terratest's best use at scale**: as a read-only integration test suite over *existing* ecosystem resources (no ephemeral provisioning), comparing live configuration/behavior to expectations — validating how resources actually behave regardless of how they're managed.
- **Terratest `examples/` pattern**: point `TerraformDir` in `terraform.Options` at an `examples/` subdirectory holding canonical use cases, fully isolated from business-critical systems — the standard practice for local/third-party-consumed modules.
- **Logic modules for policy enforcement**: a resource-free module that codifies naming/tagging computation, isolating logic from resource definitions and enabling plan-mode testing of module outputs against curated inputs (pure-function unit tests). Works as **input-only** logic modules (all inputs and outputs available simultaneously); resource-attribute-reading logic modules risk circular dependency in the TF resource map. Output-only logic modules (computing `precondition{}` values for outputs) are feasible for highly complex conditions. If a logic module needs to read computed attributes to validate inputs, treat that as a signal to split the domain into a nested module so the logic module becomes input/output-only.
- **Infrastructure drift**: a resource modified outside TF — not tracked by TF (may be reverted by subsequent apply), and may take the resource out of compliance or expose it. Drift visibility is a core observability dashboard.
- **Automation validation lifecycle creep**: validation workloads you build carry their own lifecycle-management requirement — a known scope-creep vector for infra teams; identify early and address (possibly a dedicated team with business justification). Run validation workloads with service identities (IAM Role / Service Account), not individual access; group CSP-services + TF-operations + access-log analyses in one pipeline context so untracked activity is exposed — unless regulation forbids unifying data sources.
- **Global-namespace resources**: buckets (often CSP-unique) and groupings (GCP Projects, Azure Subscriptions) can't be recreated for a window even after deletion — validating nested modules only beats parallel root-module validation, and Terratest may instead read live environment resources rather than build ephemeral duplicates.
- **Third-party modules**: tests are a *necessary* part of the release-validation workflow for modules published to third parties (unlike internal modules).

## Mental Models
- **Infrastructure as real estate**: cloud infrastructure is the land and buildings of your operation — you need building-inspection equivalents (diagnostics, audits, drift detection) because you cannot physically see it, and cloud software is too young to have centuries of evolved building codes; the ecosystem must fast-forward validation maturity.
- **Validation as approximate real-time visibility**: you can't have full real-time visibility; you sample and poll. Every improvement is a cost/approximation tradeoff.
- **Structure vs. behavior**: static analysis is "making sure all the windows and doors are secured, safety codes are maintained, the building structurally sound"; behavior analysis (`tf test`, Terratest) is "are the machines inside operating as expected" — operations within the building.
- **Validation timing as a placement principle**: put checks as early in the evaluation timeline as their dependencies allow — plan-guaranteed (variable validation) > plan-if-possible (precondition) > apply-only (postcondition, `timestamp()`-dependent checks).
- **Signal vs. noise budget**: more data sources invite more noise; noisy systems cause reviewers to overlook real issues, turning a solution into a waste of effort. Refine, cross-reference, and *reduce* scheduled checks once alerts become focused and actionable.
- **Access-log gap**: logs show when and who/what initiated an action, but neither intent nor always impact; TF validation context fills the gap (e.g., distinguishing a TF-platform drift-correction from an actual violation).
- **Smoke-test sufficiency**: even small test batteries go a long way; not every resource warrants a test — encode problems you actually experience as new tests, filling existing gaps.

## Anti-patterns
- **Driving TF development with tests (TF-TDD) like consumer software**: all TF output is production, resources collide on globally-unique names, and tests creating real resources cost more than they return on frequently-updated projects. Be judicious per case; don't run resource-creating tests in every normal pipeline.
- **Coverage-percentage governance of TF tests**: not the right way to govern them — no analog to code coverage in HCL; a required percentage is the wrong instrument.
- **Inline complex validation conditions in blocks**: any complex calculation should be extracted into local values for reviewer accessibility (Ch. 4 rule); conditions referencing `aws_ami.example.deprecation_time` inside preconditions silently defer to apply phase.
- **Postconditioning on settable attributes**: if the attribute can be set in the resource block, precompute/validate it instead — an apply-phase postcondition failure leaves resources partially configured with no rollback.
- **Duplicating one validation expression in both `validation{}` and `precondition{}`**: duplication of responsibility; prefer the variable `validation{}` block. Exceptions require explicit business justification.
- **Running TFLint against the root module only**: nested modules escape validation; extend to all module paths (and forget `tf init` first and external modules can't be checked).
- **Implementing many compliance tools at once**: coverage overlap doubles rule maintenance and invites "a false sense of security and a never-ending quest of refinement." One tool, chosen for practicality and team accessibility.
- **Relying on stock NIST/CIS coverage alone**: org-specific regulatory and corporate policies need custom controls; conversely, blanket application of controls to unconstrained workloads forces unwieldy relaxations — segment controls by domain.
- **`tf test`/Terratest against modules containing `prevent_destroy` or abandon-on-delete controls**: the final destroy fails and takes the test with it.
- **Trusting validation instead of production verification**: no validation guarantees success — don't trust anything until it runs in its expected place and verifiably operates as expected.
- **Late-stage code review of polished code**: "too good" code elicits no meaningful scrutiny and obscures deviations; review in-flight code on a regular cadence instead.
- **Too-severe pre-commit hooks**: fewer commits result; soften with an env-var override that skips portions, or let failed validation not block the commit (gauge remaining work), rather than full `--no-verify` bypasses.
- **Logic modules reading computed resource attributes of resources that read the module's outputs**: circular dependency in the resource map (see Example 10-7).
- **Individuals holding broad CSP read access for validation**: assign read access to service identities; people get reports, not credentials — only active investigation justifies individual access.
- **Fully autonomous infrastructure mutation on imperfect information**: restrict automation to low-risk, high-reward corrections (targeted applies for firewall rules, IAM permissions) governed by extremely well-crafted, unambiguous rules (OPA-fit), with tagged exception components that still generate alerts.

## Code Examples

```hcl
variable "type" {
  type        = string
  description = "Allowed EC2 instance types."

  validation {
    condition     = local.instance_check
    error_message = "The type must be t3.micro (us-west-1) or t3.small (us-east-1)."
  }
}

locals {
  micro_check    = (contains(["us-west-1"], data.aws_region.region.region)
                      && contains(["t3.micro"], var.type))
  small_check    = (contains(["us-east-1"], data.aws_region.region.region)
                      && contains(["t3.small"], var.type))
  instance_check = local.micro_check || local.small_check
}

data "aws_region" "region" {
  region = var.region
}
```
**What it demonstrates**: the recommended pattern — a variable `validation{}` block whose condition lives in a named local and combines cross-variable input with a data source attribute, so a complex policy is plan-phase-guaranteed, reviewer-readable, and reuses the same `local.instance_check` that a `precondition{}` would (Examples 10-1/10-2).

```go
func TestVPCConstraints(t *testing.T) {
  projectID := "proj-tas-10-components"
  netName   := "vpc-tas-10"

  requiredRegions := map[string]bool{
    "us-west1": false, "us-central1": false, "us-east4": false,
  }

  subnets, _ := svc.Subnetworks.List(projectID, "regions/-").Do()
  count := 0
  for _, s := range subnets.Items {
    if strings.Contains(s.Network, netName) {
      count++
      parts := strings.Split(s.Network, "/")
      region := parts[len(parts)-3]
      if _, ok := requiredRegions[region]; ok {
        requiredRegions[region] = true
      }
    }
  }
  assert.LessOrEqual(t, count, 10)
  for _, found := range requiredRegions {
    assert.True(t, found)
  }

  for _, fw := range firewalls.Items {
    if strings.Contains(fw.Network, netName) && fw.Direction == "INGRESS" {
      for _, r := range fw.SourceRanges {
        assert.NotEqual(t, "0.0.0.0/0", r)
      }
    }
  }
}
```
**What it demonstrates**: Terratest used *read-only* — asserting constraints over existing, live VPC infrastructure (region coverage, subnet count ≤10, no `0.0.0.0/0` INGRESS source ranges) via the CSP API instead of provisioning ephemeral resources — validating behavior regardless of how the resources are managed (Example 10-6).

## Reference Tables
**Validation block evaluation timing**:

| Block | Where | Guaranteed? | When evaluated |
|---|---|---|---|
| `validation{}` | `variable` | yes | plan phase |
| `precondition{}` | `resource` / `data` | no | plan if computable; apply if it depends on attributes not yet available |
| `postcondition{}` | `resource` / `data` | yes | apply phase, after fetch/create |
| `precondition{}` | `output` | no | plan (only if all inputs available then) |

**Baseline dashboards**: resource drift; pipeline metrics; queue depth; run duration; workspace activity heatmap; healthchecks; versions (TF CLI, providers, remote modules).

**Baseline alerts (with routing and tuning notes)**: drift of certain layers/resources → infra platform team owning those resources; run queue backlog too high → TF automation platform team; run duration SLA breach → platform team (may warrant warm-up threshold / cool-off period); resource saturation (workflow runner thresholds) → platform team; health check failure → infra platform team (tune to reduce false positives/temporary disconnects).

**Tool selection sketch**: TFLint (provider-valid + style + dead code + deprecations); KICS/Trivy/Checkov (regulatory/NIST/CIS control sets, broader-than-TF coverage); Checkov (resource-graph relationship checks, single-project scope); OPA/Rego (general policy engine, shared rules language, lowest migration cost).

## Worked Example
A shared naming policy enforced through a policy/logic module (Examples 10-8/10-9). Inputs `app_code` (app1–app3), `business_unit` (bu1–bu2), and `region` (three GCP regions) each carry a `validation{}` block; the module emits a `safe_name` output computed as `"${var.app_code}-${var.business_unit}-${var.region}"`. The root module consumes it: `resource "google_storage_bucket" "example" { name = module.local.safe_name ... }`. The logic module owns the integrity of the composition while consumers keep their own `locals{}` free of the policy. Two enforcement shapes are shown: input-side variable validation before constructing the safe output, or an output-side `precondition{}` where a `valid_inputs` local AND together the three membership checks with a joined error message. The chapter's caveat: this deliberately permits a `module{}`+`resource{}` mix and a dependency that is otherwise discouraged (flat dependency graphs, minimal nesting) — it is acceptable only when the module strictly holds no resources and serves purely as an optional add-on to validate values.

## Key Takeaways
- Put validation logic in variable `validation{}` blocks whenever it can evaluate at plan time — they are the only plan-*guaranteed* TF construct, can reference any variable/local/data source (v1.9+), and work for read-only operators via pre-commit hooks.
- Prefer a single expressed validation per policy (validation > precondition; resource postcondition > output precondition), ordered by evaluation timing so invalid values surface as early as possible.
- Use data sources as pre-apply availability checks for anything outside the project's state — including IDs you could pass directly — and wrap retrieved secrets in `sensitive()`.
- Run `tf validate` always; add exactly one static analysis tool (TFLint for provider validity/lint; Trivy/Checkov/KICS plus OPA-based rules for compliance), keeping custom controls (gap-fillers and relaxations) in source control and segmented by domain.
- Use `tf test` (plan mode for pure local-value logic, apply mode deliberately) and Terratest sparingly and case-by-case — not as universal pipeline stages; Terratest shines read-only against live ecosystem resources and in `examples/` against third-party-consumed modules; both break on `prevent_destroy`/abandon policies and CSP quotas.
- Enforce naming/tagging policy with resource-free logic modules; treat a logic module needing computed attributes as a signal to split the domain into a nested module.
- Build observability on access logs first, then layer TF validation reports cross-referenced against logs, then the regular/on-demand two-level split; route drift alerts to resource owners and platform-health alerts to the automation team.
- Live code review of in-flight code is one of the cheapest, highest-value validation mechanisms — review cadence over polish.

## Connects To
- Ch. 4 (extracting complex expressions into locals for reviewer accessibility; `depends_on` caution), Ch. 5 (modules — standard vs. logic/input-only modules, `examples/` directories), Ch. 6 (automation platform wildcard jobs reused as the sandbox for tool migrations and validation pipelines), Ch. 11 (patterns and realistic scenarios that assemble these validation and observability layers into a world-class ecosystem). TFE/HCP Terraform ship the observability dashboards described here built-in, so the observability strategy applies primarily to OpenTofu builds.