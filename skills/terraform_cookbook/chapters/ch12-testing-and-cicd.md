# Chapter 12: Testing and CI/CD Integration for Terraform

## Core Idea
Terraform code should travel a layered quality gauntlet before reaching production: built-in `terraform fmt`/`validate` gates on every PR, behavioural verification with Terratest, static analysis with TFLint, security/compliance scanning with Checkov, and finally automated plan/apply pipelines in GitHub Actions or Jenkins (with remote backends/Terraform Cloud providing state locking, audit trails, and Sentinel policy enforcement).

## Frameworks Introduced
- **Layered quality-gate pipeline (chapter's organizing sequence)**: syntax → behaviour → policy → security → deploy.
  - When to use: any team moving Terraform from local execution to enterprise delivery.
  - How: `terraform fmt -check` + `terraform validate` as the first line of defense (block merge on failure); Terratest for real-provisioning tests; TFLint for cloud-specific linting; Checkov for security baselines; only then auto-apply or gate applies behind manual approval.
- **Terratest lifecycle**: (1) initialize and apply a Terraform module, (2) verify deployed resources using cloud SDKs or CLI tools, (3) tear down to avoid residual costs.
  - When to use: reusable modules and production-bound infrastructure, where `validate` cannot confirm behaviour.
  - How: `go mod init`, `go get github.com/gruntwork-io/terratest/modules/terraform` + `stretchr/testify/assert`; write a Go test that calls `terraform.InitAndApply`, reads `terraform.Output`, asserts, and `defer terraform.Destroy`; run `go test -v -timeout 20m` in CI.
- **Jenkins Terraform pipeline stages**: Init → Validate → Plan → Apply, with the plan archived as an artifact (`terraform plan -out=tfplan` + `archiveArtifacts`), apply restricted with `when { branch 'main' }`, and a manual `input` approval stage before `terraform apply tfplan`.
  - When to use: enterprise environments standardized on Jenkins; note Azure credentials injected via Jenkins `credentials()` into `ARM_CLIENT_ID/ARM_CLIENT_SECRET/ARM_SUBSCRIPTION_ID/ARM_TENANT_ID`.
- **Chef's Special pipeline (Appetizer / Main course / Dessert)**: three GitHub Actions workflows on one repo — quality checks on `pull_request` (fmt, init, validate, plan with `azure/login@v1` from `AZURE_CREDENTIALS` secret), Checkov scan on `pull_request`, and `terraform apply -auto-approve` on `push` to `main` pinned to a GitHub `environment: name: staging`, with manual gates recommended for production.
  - When to use: teams adopting Terraform CI/CD at scale with Azure service principals.
  - How: `az ad sp create-for-rbac --name "terraform-cicd" --role="Contributor" --scopes="/subscriptions/<id>" --sdk-auth`, paste the JSON into GitHub Secrets as `AZURE_CREDENTIALS`.
- **Remote backends / Terraform Cloud in CI**: centralize state and run plans/applies remotely rather than on runners or laptops.
  - When to use: collaborative environments where local state risks conflicts and corruption.
  - How: `terraform { backend "remote" { ... } }` with org/workspace; authenticate CI via `TF_TOKEN_app_terraform_io` or GitHub OIDC for tokenless access; backend options — Azure Blob + Table Storage locking, S3 + DynamoDB locking, GCS.

## Key Concepts
- **`terraform fmt -check`**: enforces canonical style in CI; a formatting diff fails the workflow and blocks the merge.
- **`terraform validate`**: syntactic and structural verification — valid expressions, references, and resource definitions; does not confirm deployed behaviour.
- **TFLint**: pluggable static analyzer catching issues native validation misses — missing required tags, deprecated/unsupported parameters, misconfigured arguments, naming/policy violations; extensible with custom plugins and provider-specific rules.
- **Checkov**: Bridgecrew's Python IaC scanner with hundreds of built-in policies mapped to CIS, SOC 2, GDPR, and NIST; detects open security groups, unencrypted storage, missing logging; run `checkov -d .` and configure it to fail builds on critical findings.
- **PR plan commenting (GitOps-style review)**: on every PR touching `**.tf`, run `terraform plan -no-color` and post output as a sticky PR comment (`marocchino/sticky-pull-request-comment@v2`) so reviewers see proposed infrastructure changes before merge.
- **`TF_IN_AUTOMATION = 'true'`**: environment flag set in CI pipelines to suppress Terraform's interactive hints.
- **Manual approval gate**: Jenkins `input` stage (or GitHub environment protection rules) between plan and apply so production changes are human-approved.
- **Service principal + GitHub Secrets**: headless Azure auth for pipelines (`azure/login@v1` with `creds: ${{ secrets.AZURE_CREDENTIALS }}`), avoiding developer-machine credentials.

## Recipes in this chapter
- **Recipe 67: Terraform validation and linting in CI** — GitHub Actions workflow failing a PR that deliberately introduces malformed HCL (`terraform fmt -check` red, `terraform validate` gating).
- **Recipe 68: Terratest for a Terraform module** — Go test deploying an `azurerm_resource_group` module, asserting `output == "terratest-rg"`, auto-destroying via `defer`.
- **Recipe 69: Jenkins pipeline for Terraform** — declarative Jenkinsfile with credential bindings, plan artifact, `Manual Approval` stage, and apply of the saved plan file.
- **Recipe 70: Static code analysis with TFLint** — install (`choco`/`brew`/install script), `tflint --init && tflint` locally, then `reviewdog/action-tflint@v1` reporting violations on the PR.
- **Recipe 71: Security scanning with Checkov** — deliberately insecure NSG (SSH `0.0.0.0/0`) caught by `checkov -d .` and the `bridgecrewio/checkov-action@master` workflow step.
- **Recipe 72: Automated Terraform plan in GitHub** — plan output written to `$GITHUB_STEP_SUMMARY` and posted as a sticky PR comment on PRs that change `**.tf`.

## Anti-patterns
- **Merging code that only passes `terraform validate`**: syntactic correctness says nothing about deployed behaviour; add Terratest for modules and critical infrastructure.
- **Local/state-per-machine state in teams**: leads to conflicts, inconsistencies, and state corruption when multiple users or agents run concurrently — use remote backends with locking.
- **Hard-coding cloud credentials in pipelines or configs**: use GitHub Secrets with a scoped service principal, or Jenkins `credentials()`, or Vault (the author notes Vault can dynamically inject secrets during provisioning).
- **Security scanning after deployment**: Checkov exists to stop open SSH rules and unencrypted storage before `apply`; configure it to fail the build on critical findings.
- **Applying to production on merge without a gate**: the Chef's Special auto-applies only to a `staging` environment; production gets manual or policy-based approval.
- **Terraform runs on developer machines in CI pipelines**: prefer remote execution (Terraform Cloud workspaces) for consistency, audit logging, and access control.

## Code Examples
Terratest module test — the full behavioural lifecycle:
```go
func TestTerraformModule(t *testing.T) {
  t.Parallel()
  terraformOptions := &terraform.Options{
    TerraformDir: "../",
  }
  defer terraform.Destroy(t, terraformOptions)
  terraform.InitAndApply(t, terraformOptions)
  output := terraform.Output(t, terraformOptions, "resource_group_name")
  assert.Equal(t, "terratest-rg", output)
}
```
- **What it demonstrates**: apply → assert on output → guaranteed cleanup with `defer terraform.Destroy`, run in CI as `cd tests && go test -v -timeout 20m`.

Jenkins gates with plan-artifact and manual approval:
```groovy
stage('Terraform Plan') {
  steps {
    sh 'terraform plan -out=tfplan'
    archiveArtifacts artifacts: 'tfplan', fingerprint: true
  }
}
stage('Terraform Apply') {
  when { branch 'main' }
  steps {
    input 'Approve infrastructure changes?'
    sh 'terraform apply tfplan'
  }
}
```
- **What it demonstrates**: apply consumes the archived plan artifact (not a fresh plan), runs only on `main`, and requires human approval — the author's governance workflow.

## Reference Tables
Chapter's tooling decision matrix (assembled from the text):

| Tool | Role | What it catches | Typical CI invocation |
|---|---|---|---|
| `terraform fmt -check` | Formatting | Non-canonical style blocks merge | `run: terraform fmt -check` |
| `terraform validate` | Syntax/structure | Broken expressions, references | `run: terraform validate` |
| Terratest (Go) | Behavioural integration tests | Modules that deploy wrongly | `go test -v -timeout 20m` |
| TFLint | Static analysis | Missing tags, deprecated args, org conventions | `reviewdog/action-tflint@v1` |
| Checkov | Security/compliance scanning | Open SGs, unencrypted storage vs CIS/SOC 2/GDPR/NIST | `bridgecrewio/checkov-action@master` |
| Terraform Cloud | Remote state + runs | State conflicts; adds audit, Sentinel policy-as-code | `backend "remote"` + `TF_TOKEN_app_terraform_io` |

Remote backend options: Azure Blob Storage (locking via Table Storage) · AWS S3 (locking via DynamoDB) · GCS bucket · Terraform Cloud remote backend.

## Worked Example
Chef's Special — production-grade Terraform CI/CD on GitHub Actions (three courses):

1. **Base setup**: repo with `main.tf` (resource group `chef-special-rg` in East US, output `resource_group_id`), `variables.tf`, `provider.tf` (`azurerm ~> 3.0`, `required_version >= 1.5.0`), and three workflow files: `ci-appetizer.yml`, `ci-main-course.yml`, `ci-dessert.yml`. Create the service principal (`az ad sp create-for-rbac --name "terraform-cicd" --role="Contributor" --scopes="/subscriptions/<id>" --sdk-auth`) and store the JSON as repository secret `AZURE_CREDENTIALS` (Settings | Secrets and variables | Actions).
2. **Appetizer (PR quality gate)**: on `pull_request` to `main` with `permissions: contents: read, pull-requests: read` — checkout, `setup-terraform@v2`, `azure/login@v1` from the secret, then `terraform fmt -check`, `init`, `validate`, `plan`. Result: no broken or unreviewable code reaches `main`.
3. **Main course (security gate)**: separate workflow running `bridgecrewio/checkov-action@master` with `directory: ./` on every PR — insecure configurations (open ports, missing encryption, missing tags) fail before merge.
4. **Dessert (apply on merge)**: on `push` to `main`, a workflow with `permissions: id-token: write, pull-requests: write` pinned to GitHub `environment: staging` runs `init → plan → apply -auto-approve`. The author's extension path: add manual approvals or branch-based multi-environment deploys for production.
5. **Verification**: branch `feature/test-ci`, small edit, push, open PR; watch all three pipelines run in the Actions tab. Author's closing framing: "Every pull request is now a conversation backed by automation. Every deployment is now intentional, auditable, and repeatable."

## Key Takeaways
1. Order your gates cheap-to-expensive: fmt/validate on every PR, then TFLint and Checkov, Terratest where modules warrant it, apply last.
2. Apply from a saved plan artifact (`terraform plan -out=tfplan`), not a fresh plan, so reviewers approve exactly what gets executed.
3. Guard applies with environment separation: auto-apply only to staging on merge; production needs a human `input`/environment gate.
4. Use a dedicated least-privilege service principal stored in GitHub Secrets (`AZURE_CREDENTIALS`) for headless auth — never developer credentials.
5. Terratest is for confidence, not syntax: it provisions real infrastructure, asserts on outputs, and always cleans up with `defer terraform.Destroy`.
6. Post `terraform plan -no-color` as a sticky PR comment to make every infrastructure change reviewable in the pull request itself (GitOps-style).
7. Move state to remote backends or Terraform Cloud for locking, audit trails, and Sentinel policy enforcement; run plans/applies remotely instead of on CI runners or laptops.

## Connects To
- **Ch 11**: the AKS/GKE/EKS and Helm configurations from the previous chapter are the kind of multi-layer code that most needs these CI gates and remote-state discipline.
- **Ch 13**: the next chapter extends assurance into security and best practices — secrets management (Azure Key Vault, HashiCorp Vault), RBAC, policy-as-code with Sentinel/Open Policy Agent, and code structure/state/drift strategies for team collaboration.