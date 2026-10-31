# Chapter 6: Testing and Automation

## Core Idea
Test Terraform in layers — free built-ins first (`fmt`/`validate`/`plan`), then static linting (TFLint), security scanning (Checkov), real-infrastructure testing (Terratest/pytest) — and automate the whole loop in CI/CD (GitHub Actions, GitLab CI, Jenkins) with a validate → plan → apply pipeline.

## Frameworks Introduced
- **The Testing Ladder (do in order)**:
  1. `terraform fmt` — canonical formatting, reduces syntax-error likelihood.
  2. `terraform validate` — syntax + internal consistency, *no remote interaction*.
  3. `terraform plan` — the change preview; review before anything goes live.
  4. **TFLint** — Terraform-specific linter: syntax errors, unused variables, deprecated/outdated resource types, missing required attributes, naming convention enforcement (`^[a-z0-9-]+$`). Run as a **pre-commit hook** so only clean code enters VCS.
  5. **Checkov** — IaC security/compliance scanner (Terraform, CloudFormation, Kubernetes; AWS/Azure/GCP): built-in policy library (open security groups, unencrypted storage, missing logging/uniform access), **custom Python policies**, remediation guidance with links, CI/CD-native (`checkov -d . --quiet`).
  6. **Terratest** — Go framework that *provisions real infrastructure* and asserts against it — catches what static analysis misses (module tests, end-to-end). Pattern: `defer terraform.Destroy(t, opts)` + `terraform.InitAndApply` + `terraform.Output` + assertions.
  7. **Python/pytest** — validate via boto3 or `terraform output -json` parsing; strong when the team already lives in Python.
- **CI/CD stage model**: validate → plan → apply (GitLab stages map this literally; Jenkins adds a manual `input 'Approve Terraform Apply?'` gate; both archive artifacts — `plan.out`/state files).

## Key Concepts
- **Checkov check IDs**: `CKV_AWS_*`, `CKV_GCP_*` (e.g. `CKV_AWS_1` S3 public access, `CKV_AWS_2` SG unrestricted ports, `CKV_GCP_63` bucket logging to itself, `CKV_GCP_29` uniform bucket-level access); custom checks via a Python class extending `BaseCheck` (id + `supported_resources` + `scan_resource_conf`) run with `--check-class-path`.
- **Secrets in pipelines**: never hard-code — `TF_VAR_my_secret: ${{ secrets.MY_SECRET }}` maps GitHub Secrets into TF variables at apply time.
- **`-auto-approve` in CI vs. locally**: in CI, the human review already happened at plan stage / branch review; Jenkins shows the alternative — an explicit manual approval step in the pipeline before apply.
- **State artifact archiving**: Jenkins `post { always { archiveArtifacts artifacts: 'terraform.tfstate' } }` keeps a history of state files.
- **Backend config as pipeline vars**: `-backend-config="bucket=${TF_BACKEND_BUCKET}" -backend-config="key=..." -backend-config="region=..."` keeps backends parameterized per pipeline.
- **TFLint output anatomy**: `[ERROR]/[WARNING]` + resource path + explanation of the convention violated (e.g. missing `logging` block).

## Mental Models
- "The cornerstone of effective testing is rooted in the basics" — the minor overlooked details (missing brace, unused var, no encryption block) cause more failures than exotic scenarios; free commands first, expensive real-infra tests last.
- Static analysis finds what the code *says* wrong; Terratest finds what the infrastructure *does* wrong — you need both kinds.
- Treat `defer terraform.Destroy` as the invariant of every Terratest: tests that leak infrastructure are a cost bug, not just a correctness bug.
- CI is the enforcement point: TFLint blocks at commit (pre-commit), Checkov blocks at PR scan, apply happens only from `main`.

## Code Examples
TFLint fix example (before: missing logging, bad name pattern → after):
```hcl
resource "google_storage_bucket" "example" {
  name          = "example-bucket-dev"
  location      = "US"
  force_destroy = true
  lifecycle_rule {
    action    { type = "Delete" }
    condition { age  = 365 }
  }
  logging {
    log_bucket        = "logging-bucket"
    log_object_prefix = "example-bucket/"
  }
}
```
Checkov custom policy (Python):
```python
class CheckS3BucketTags(BaseCheck):
    name = "Ensure S3 buckets have the 'Environment' tag"
    id = "CUSTOM_S3_TAG_CHECK"
    supported_resources = ["aws_s3_bucket"]
    categories = [CheckType.TAG]
    def scan_resource_conf(self, conf):
        if "tags" not in conf:
            return CheckResult.FAILED
        tags = conf["tags"]
        if tags.get("Environment") != "production":
            return CheckResult.FAILED
        return CheckResult.PASSED
# run: checkov -d . --check-class-path /path/to/custom_check.py
```
Terratest module test (the canonical pattern):
```go
func TestVpcModule(t *testing.T) {
  t.Parallel()
  terraformOptions := &terraform.Options{
    TerraformDir: "../examples/vpc",
    Vars:         map[string]interface{}{ "region": "us-central1" },
    NoColor:      true,
  }
  defer terraform.Destroy(t, terraformOptions)      // cleanup invariant
  terraform.InitAndApply(t, terraformOptions)       // provision for real
  vpcId := terraform.Output(t, terraformOptions, "vpc_id")
  assert.NotEmpty(t, vpcId, "VPC ID should not be empty")
  actualCidrBlock := terraform.Output(t, terraformOptions, "vpc_cidr_block")
  assert.Equal(t, "10.0.0.0/16", actualCidrBlock, "VPC CIDR block does not match expected value")
}
```
Validate Terraform outputs with pytest:
```python
def get_terraform_output():
    result = subprocess.run(['terraform', 'output', '-json'],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise Exception(f"Terraform output failed: {result.stderr}")
    return json.loads(result.stdout)

def test_subnet_cidr_block():
    outputs = get_terraform_output()
    assert outputs.get('subnet_cidr_block', {}).get('value') == "10.0.1.0/24"
```
GitHub Actions — the book's reference Terraform pipeline:
```yaml
name: Terraform
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
        with: { terraform_version: 1.8.0 }
      - run: terraform init
      - run: terraform validate
      - run: terraform plan
      - name: Terraform Apply
        env:
          TF_VAR_my_secret: ${{ secrets.MY_SECRET }}
        run: terraform apply -auto-approve
```
GitLab CI equivalent: `stages: [validate, plan, apply]`, backend via `-backend-config=` CLI flags in the validate job, `plan.out` saved as artifact, `apply` restricted to `only: [main]`.

## Reference Tables
| Tool | Kind | Catches | Runs when |
|---|---|---|---|
| `terraform fmt` | built-in | inconsistent style | pre-commit |
| `terraform validate` | built-in | syntax/schema (no remote calls) | pre-commit/CI |
| `terraform plan` | built-in | wrong changes, drift | every change, reviewable |
| TFLint | linter | syntax, unused vars, deprecated types, naming | pre-commit hook |
| Checkov | security scanner | misconfigurations, compliance (built-in + custom policies) | PR/CI scan |
| Terratest | real-infra (Go) | runtime behavior of modules/E2E | CI after apply |
| pytest+boto3 | verification (Python) | live resources, Terraform outputs | CI after apply |

| CI tool | Pipeline shape | Distinctive |
|---|---|---|
| GitHub Actions | `.github/workflows/terraform.yml` (`init→validate→plan→apply`) | secrets via `secrets.*` → `TF_VAR_*` |
| GitLab CI | `.gitlab-ci.yml` stages: validate/plan/apply | backend-config flags; artifact `plan.out`; apply from `main` only |
| Jenkins | Jenkinsfile stages | manual `input` approval gate; archives state file |

## Worked Example
The Checkov AWS scan: given a bad config (S3 without public-acl blocking, SG open to `0.0.0.0/0` on port 80, RDS with hard-coded `password = "password123"`), `checkov -d /path/to/terraform/main.tf` fails `CKV_AWS_1` (block_public_acls), `CKV_AWS_2` (unrestricted SG), `CKV_AWS_3` (publicly_accessible). The lesson is the loop: scan → read the check ID + guide link → fix the specific attribute → rescan. The Jenkins Checkov pipeline then wraps it: checkout → venv + pip install checkov → `checkov -d . --quiet` → archive logs — making the security gate automatic on every commit.

## Anti-patterns
- **Jumping to complex tooling before the basics**: skipping `fmt`/`validate`/`plan` and buying complexity you don't need.
- **Linting after commit**: without a pre-commit hook, TFLint findings arrive too late to be cheap.
- **Trusting static analysis alone**: Terratest exists precisely because real provisioning reveals issues code analysis can't.
- **Hard-coded secrets in pipelines or configs**: use `TF_VAR_` + platform secret stores (also — the AWS RDS example shown in the book is deliberately bad).
- **Apply without a gate in shared environments**: either branch-review + plan (Actions/GitLab) or a manual approval step (Jenkins).
- **Tests that don't clean up**: missing `defer terraform.Destroy` leaks paid infra.

## Key Takeaways
1. Climb the ladder in order: fmt → validate → plan → TFLint (pre-commit) → Checkov (PR scan) → Terratest/pytest (post-deploy).
2. Every Terratest is `defer Destroy` + `InitAndApply` + assert on outputs — and can go further by querying the cloud API directly.
3. Custom organizational rules are first-class in Checkov: write a Python check for your internal tags/standards.
4. In CI, feed secrets via `TF_VAR_*` ← secrets store; gate applies on main-branch-only or an explicit approval.
5. Keep the classic pipeline skeleton (validate→plan→apply) and archive your plans/state for an audit trail.
6. `terraform output -json` is the universal bridge between Terraform and any external test language.

## Connects To
- **Ch 2/Ch 4**: validation commands and verification loops from earlier chapters become automated pipeline stages here.
- **Ch 5**: the `TF_VAR_*` secret-passing pattern is the CI-safe application of Ch 5's secrets discipline.