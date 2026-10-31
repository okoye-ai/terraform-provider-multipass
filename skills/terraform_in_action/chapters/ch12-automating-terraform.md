# Chapter 12: Automating Terraform

## Core Idea
Build "poor person's Terraform Enterprise" — Terraform managing Terraform: a four-stage pipeline (Source → Plan → Approve → Apply) on AWS CodePipeline that plans on every commit, holds a manual approval gate before applying at scale.

## Frameworks Introduced
- **The Four-Stage Terraform Pipeline**: Source (webhook + download from GitHub via CodeStar) → Plan (`terraform plan`) → Approve (manual gate; stakeholders read the plan output) → Apply (`terraform apply`)
  - Why manual approval: stakeholders must read plan output before production changes; never turn off manual approval for mission-critical work (`auto_apply` is the escape hatch via a feature-flagged dynamic block)
  - TFE features replicated: collaboration (state management, web UI, collaborative runs, private registry) and automation (VCS integration, GitOps, notifications, HTTP API); *not* replicated: remote operations, Sentinel (proprietary)
  - Rationale for building instead of buying: ownership (design your own, troubleshoot yourself) + cost (no licensing)
- **The Backend-in-Env Trick**: the pipeline echoes a `BACKEND` env var (a JSON-templated `backend.json`) into `backend.tf.json` before `terraform init` — backend config never touches version control
  - JSON `.tf.json` syntax is the exception to "don't generate config code": more verbose but machine-friendly, for automation exactly this
- **Three Multi-Environment Strategies** (FAQ): GitHub branches (fast, strict PR discipline), many-staged pipelines (one stage set per env — linear only, can't hotfix-skip), linked pipelines (most extensible: apply triggers next environment's pipeline, per-environment rollback)
- **Ways to Pass Terraform Variables in Automation**: checked-in tfvars (no secrets), `TF_VAR_name` env vars, or dynamic retrieval from a central store before `terraform init` (safest/flexible, hardest)

## Key Concepts
- **Terraform settings env vars**: `TF_IN_AUTOMATION` (suppresses "run X next" suggestions), `TF_INPUT=0` (no prompts) — always set both in automation
- **CONFIRM_DESTROY flag**: `0` → plan/apply; anything else → `terraform plan -destroy` / `terraform destroy` — TFE-style destroy runs through the same pipeline (avoids orphaning resources by deleting the backend stack first)
- **Two CodeBuild projects** (`plan`, `apply`) from one resource via `count = length(["plan","apply"])` with `buildspec_<name>.yml` files and the `hashicorp/terraform:<version>` container image (Alpine + Terraform, no runtime download)
- **Environment variable plumbing**: merge `default_environment` + user `var.environment`, then `jsonencode([for k, v in merge(...) : { name: k, value: v, type: "PLAINTEXT" }])` — user values override defaults
- **Feature-flagged dynamic block**: `dynamic "stage" { for_each = var.auto_apply ? [] : [1]; content { ... } }` — empty list creates zero blocks, `[1]` creates one (the canonical toggle idiom)
- **CodeStar connection**: Terraform can create it but not authenticate it — completes as PENDING and must be clicked through in the AWS console ("Update Pending Connection"); a manual step even in full automation
- **Least-privileged deployment policy**: match the policy to what the code deploys (helloworld.json: ec2 RunInstances/Terminate/Tags/Describe*), never hand the pipeline an admin role

## Code Examples
```hcl
# Backend config injected as JSON so it never lives in the repo
locals {
  backend = templatefile("${path.module}/templates/backend.json",
    { config : var.s3_backend_config, name : local.namespace })
  environment = jsonencode([for k, v in merge(local.default_environment,
    var.environment) : { name : k, value : v, type : "PLAINTEXT" }])
}
# buildspec_plan.yml (core)
#   echo $BACKEND >> backend.tf.json
#   terraform init
#   if CONFIRM_DESTROY == 0: terraform plan  else: terraform plan -destroy

# Feature-flag-toggled Approve stage
dynamic "stage" {
  for_each = var.auto_apply ? [] : [1]
  content {
    name = "Approve"
    action { name = "Approve", category = "Approval", owner = "AWS",
             provider = "Manual", version = "1",
             configuration = { CustomData = "Please review output of plan and approve",
                               NotificationArn = aws_sns_topic.codepipeline.arn } }
  }
}
```
- **What it demonstrates**: the whole automation contract — code from GitHub drives plan, humans (or `auto_apply`) approve, apply runs with the deployment role, destroy runs are queued with `CONFIRM_DESTROY=1`

## Key Takeaways
1. Terraform at scale = pipeline: plan on every commit, approve before apply; that's the TFE core minus remote ops/Sentinel.
2. Generate `.tf.json`, not HCL, when a machine needs to write Terraform config.
3. Keep backend config out of repos — inject it via environment/templates at init time.
4. Destroy runs belong in the pipeline too (`CONFIRM_DESTROY`), or you orphan resources when the backend stack is deleted.
5. Order of teardown: destroy the managed workload first, then the pipeline/backend; the CodeStar connection is the one manual step.

## Connects To
- **Ch 6**: the s3backend module reused as the pipeline's state store; workspaces vs branch strategies
- **Ch 10**: integration tests/vaidation slot into extra pipeline stages
- **Ch 13**: environment variables and dynamic secrets for provider credentials; Sentinel policies as extra gates
- **Ch 7**: same CI/CD thinking, but the artifact being deployed is Terraform changes itself