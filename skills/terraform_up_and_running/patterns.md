# Patterns — Terraform Up & Running, 3rd Ed.

## Tool-stack combinations (ch01)
**When to use**: choosing the multi-tool IaC stack.
**How**: pick exactly one provisioning tool (Terraform); combine per needs:
- **Terraform + Ansible** — provisioning + config mgmt: easy start, no extra infra, but mutable/procedural debt.
- **Terraform + Packer** — provisioning + server templating: immutable, simple stack; slow VM builds, no native blue-green.
- **Terraform + Packer + Docker + Kubernetes** — full stack: fast builds + native deploy strategies/autoscaling; most complex.
**Trade-offs**: more tools = more moving parts; pick config-vs-provisioning first, then decide.

## Declare-and-reference (ch02)
**When to use**: wiring any two resources.
**How**: reference `<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>`; Terraform builds the dependency graph and parallelizes. Avoid `depends_on`; reserve it for true ordering you can't express by reference.

## Plan-diff reading (ch02)
**When to use**: before every apply, in every code review.
**How**: check for `-/+` (forces replacement) lines; anything an ASG references needs `create_before_destroy`; find "forces replacement" text before saying yes.

## Data-source discovery (ch02)
**When to use**: any hard-coded account ID, region value, AMI, VPC/subnet.
**How**: replace constants with data sources so configs work per-account/region.

## Extract-to-module (ch04)
**When to use**: config is copy-pasted across environments.
**How**: move to `modules/`, parameterize (variables = API, outputs = return values, locals = private DRY values), consume via `module` blocks, tag with semver.

## Separately-defined resources over inline blocks (ch04)
**When to use**: making a module extensible from outside.
**How**: prefer `aws_security_group_rule` + `aws_security_group` over inline `ingress` blocks; never mix both for the same resource (overwrite/conflict errors).

## File-layout state isolation ("bulkheads") (ch03, ch10)
**When to use**: any team deployment.
**How**: one folder per component (vpc, services, data-storage) × environment (stage, prod), each with its own backend key; one shared S3 bucket + DynamoDB table per account; separate AWS accounts per env where possible.

## Remote-state wiring (ch03, ch10)
**When to use**: one component's config needs another's outputs.
**How**: `terraform_remote_state` data source (read-only); Terragrunt `dependency` blocks as the DRYer alternative.

## for_each for loops, count for conditionals (ch05)
**When to use**: replication vs enabling.
**How**: keyed replication or anything where indexes must stay stable → `for_each` (wrap lists in `toset()`); a 0-or-1 resource switch → `count = cond ? 1 : 0`; inline-block loops → `dynamic` + `for`; transformations/filters → `for` expressions; templates → `%{ for/if }` string directives with `~` strip markers.

## one(concat(A[*], B[*])) (ch05)
**When to use**: an attribute may come from either of two if/else-created resources.
**How**: `one(concat(A[*], B[*]))` — `one()` returns null for empty, the element for a list of 1; stable across plan/apply.

## Zero-downtime deployment (ch05)
**When to use**: ASGs serving live traffic.
**How (glue)**: name resource depends on launch-config name + `create_before_destroy` + `min_elb_capacity`; rollback is automatic on failure (wait_for_capacity_timeout = 10 min). **Prefer (native)**: ASG `instance_refresh`, ECS deployment %, Kubernetes RollingUpdate — the glue pattern resets ASG to min_size on every deploy.

## Move-don't-recreate (ch05)
**When to use**: renaming resources, modules, or converting count→for_each.
**How**: `terraform state mv` (imperative) or `moved` block (declarative, committed with code, Terraform 1.1+); success = `terraform plan` shows no changes. Import anything EntityAlreadyExists complains about.

## Machine-auth decision tree (ch06)
**How**: CI inside cloud → IAM role; CI outside cloud with OIDC support → OIDC (tls_certificate → openid_connect_provider → sub-conditioned assume-role policy → id-token in CI); neither → stored credentials (last resort). Humans: env vars + a personal secret manager (1Password CLI / aws-vault).

## Encrypted files in VCS (ch06)
**When to use**: secrets versioned with code, budget ~0.
**How**: `sops`-style plaintext-edit, then `aws kms encrypt` → commit ciphertext → `aws_kms_secrets`/`sops_decrypt_file` data source → locals. Rotation is the weak point.

## Centralized secret stores (ch06)
**When to use**: need audit logs and rotation.
**How**: Vault (open source, many auth methods) or AWS Secrets Manager ($0.40/secret/mo; rotation) / Azure Key Vault; fetch in Terraform via data sources; keys still land in state → encrypted backend mandatory.

## OIDC scoping (ch06)
**How**: condition role assumption on `token.actions.githubusercontent.com:sub` per repo/branch; otherwise every repo in the org can assume the role.

## Provider discipline (ch07)
**How**: always declare `required_providers` with explicit source URL + version constraint; commit `.terraform.lock.hcl`; pin core (exact in prod), providers (`~> 4.0`), modules (`?ref=vX.Y.Z`).

## Configuration aliases + providers map (ch07)
**When to use**: reusable module must deploy into multiple configs (regions/accounts/clouds).
**How**: module declares `configuration_aliases` in `required_providers` and consumes via `providers = { aws = aws.replica }`; the root module injects concrete provider configs. Provider blocks live only in root modules.

## Separate module per region/account/cloud (ch07)
**When to use**: default over aliases — blast-radius isolation, plans still work during an outage.
**How**: aliases only for truly coupled infra (CloudFront certs must be in us-east-1, GuardDuty across all regions).

## Pass-through API design (ch08)
**When to use**: making a module generic for production reuse.
**How**: expose underlying knobs (subnet_ids, target_group_arns, health_check_type, user_data) as variables; break monolith modules by domain (networking/, services/, data-storage/) — "large modules should be considered harmful" (>few hundred lines: slow, insecure, risky, hard to review).

## Example-first (TDD) module design (ch08, ch09)
**How**: write the `examples/` folder and its test first; the example is the module's executable documentation and manual harness.

## Layered validation (ch08)
**How**: `validation` blocks on variables → `precondition` (before apply) → `postcondition` (after apply, using `self.<ATTRIBUTE>` only) → Terratest/OPA for the rest.

## Terratest test shape (ch09)
**How**: `test_structure.RunTestStage` stages + `SKIP_<name>` env vars for the fast inner loop; `defer terraform.Destroy(t, opts)` declared BEFORE InitAndApply; namespace resources `fmt.Sprintf("test-%s", random.UniqueId())`; CopyTerraformFolderToTemp for parallel tests; retries (MaxRetries 3/5s for terraform, 10/10s for HTTP, `go test -timeout 30m`).

## Test tool by layer (ch09)
**How**: syntax/lint → validate + tfsec + tflint + Terrascan (free, no auth); read-path/policy-on-plan → OPA/Sentinel/Checkov plan testing (auth, no deploy); server config → InSpec/Serverspec/Goss (full apply + SSH); one module → Terratest unit (~4–5 min); modules together → Terratest integration (10–15 min); whole system → E2E or persistent test env (deploy once, apply incrementally).

## Plan-based pipeline (ch10)
**When to use**: every infra PR.
**How**: plan-as-PR (Atlantis / TFC auto-plan in the review) → approve-then-apply pipeline; single branch deploys shared environments; production applies gated by ≥1 approver other than the requester.