# Chapter 16: Terraform with Continuous Integration/Continuous Deployment (CI/CD)

## Core Idea
The pipeline *is* the Terraform lifecycle: stages/steps that run `init → plan/validate → apply`, with the plan saved (`-out=tfplan`) and applied explicitly.

## Frameworks Introduced
- **Jenkins pipeline stages**: Init → Plan → Apply, each a `sh` step
  - Key detail: `terraform plan -out=tfplan` then `terraform apply tfplan` — apply consumes the reviewed plan
- **GitHub Actions workflow**: checkout → `hashicorp/setup-terraform` (pin `terraform_version`) → init → validate → plan → apply
  - Key detail: `terraform validate` runs in CI to catch config errors pre-apply; apply needs `-auto-approve` in automation

## Key Concepts
- **Saved plan artifact**: the `-out=tfplan` file decouples "what will change" from "make it so"
- **`-auto-approve`**: required flag when apply runs unattended in a pipeline
- **VCS triggering**: GitHub Actions trigger on push to a branch (book example: `master`)

## Mental Models
- **CI/CD as the apply gate**: humans review the plan; the pipeline executes it — automation speeds up, but doesn't skip, review.

## Code Examples *(technical)*
```yaml
name: "Terraform GitHub Actions"
on:
  push:
    branches: [master]
jobs:
  terraform:
    name: "Terraform"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: hashicorp/setup-terraform@v1
        with:
          terraform_version: 1.5.1
      - run: terraform init
      - run: terraform validate
      - run: terraform plan
      - run: terraform apply -auto-approve
```
- **What it demonstrates**: the standard five-step Terraform Actions workflow.

```groovy
pipeline {
  agent any
  stages {
    stage('Terraform Init')  { steps { sh 'terraform init' } }
    stage('Terraform Plan')  { steps { sh 'terraform plan -out=tfplan' } }
    stage('Terraform Apply') { steps { sh 'terraform apply -auto-approve tfplan' } }
  }
}
```

## Key Takeaways
1. Always separate plan from apply in pipelines — even if CI applies automatically.
2. Pin the Terraform version in CI (`setup-terraform` version input).
3. Run `terraform validate` before `plan` to fail fast on config errors.

## Connects To
- **Ch 4**: the same lifecycle commands, now automated
- **Ch 17**: policy checks (Sentinel) slot into this pipeline before apply