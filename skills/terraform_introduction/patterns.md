# Patterns

## Backend relocation
**When to use**: any team or production Terraform setup.
**How**: declare a `backend` (e.g. `s3 { bucket, key, region }`) in the `terraform` block, then re-run `terraform init` so state moves to the remote backend.
**Trade-offs**: adds setup/infrastructure requirement, but buys locking, sharing, backup, and versioning.

## Module extraction
**When to use**: a resource set appears in more than one place, or a project grows past flat files.
**How**: move the resources into a directory with `main.tf`/`variables.tf`/`outputs.tf`; call it with a `module` block, passing `source`, `version` (for registry/Git sources), and inputs.
**Trade-offs**: indirection cost vs reusability and standardized structure.

## Environment-per-tfvars
**When to use**: one codebase serving multiple environments (staging/production).
**How**: write `production.tfvars`, `staging.tfvars`, etc.; run `terraform apply -var-file="production.tfvars"`.
**Trade-offs**: zero code duplication; requires keeping environment files in sync mentally.

## Conditional existence (`count = cond ? 1 : 0`)
**When to use**: making a resource optional per environment/input.
**How**: `count = var.create_resources ? 1 : 0`, or `count = contains(var.availability_zones, "us-east-1a") ? 1 : 0`.
**Trade-offs**: simple toggle; `for_each` is better once items become individually addressable.

## Environment-based sizing
**When to use**: the same component gets bigger/smaller per environment.
**How**: `instance_type = var.environment == "production" ? "t3.large" : "t3.micro"`.
**Trade-offs**: keeps one config; nested conditionals get unreadable — promote repeated logic to `locals`.

## Locals for shared computed values
**When to use**: any value used in multiple places (common tags, derived subnet maps).
**How**: define in a `locals` block, reference as `local.<name>`; compose functions like `cidrsubnet`, `index`, `for`-expressions inside.
**Trade-offs**: one more indirection; kills repetition and centralizes changes.

## Dynamic blocks for repeated nested structures
**When to use**: repeated nested blocks (tags, rules, network interfaces) driven by input data.
**How**: `dynamic "tag" { for_each = var.common_tags; content { key = tag.key; value = tag.value } }`.
**Trade-offs**: removes hand-written repetition; can reduce readability for complex content.

## Cross-provider attribute wiring
**When to use**: resources spanning providers — e.g. DNS record pointing at a machine on another cloud.
**How**: reference the source attribute directly: `records = [digitalocean_droplet.web.ipv4_address]` in the AWS Route53 resource.
**Trade-offs**: dependencies are implicit in references — Terraform orders applies correctly, but hidden coupling deserves comment.

## Function + IAM role pairing (AWS Lambda)
**When to use**: every Lambda deployment.
**How**: define `aws_iam_role` with an `assume_role_policy` trusting `lambda.amazonaws.com`, then set `role = aws_iam_role.<name>.arn` on the function.
**Trade-offs**: one extra resource; required — the function cannot execute without it.

## Import-to-adopt
**When to use**: existing resources created manually or by other tools.
**How**: write the config block first, then `terraform import <address> <id>`.
**Trade-offs**: state gains custody but config must match reality or next plan shows diffs.

## Transition-over-recreate (non-importable resources)
**When to use**: a resource type doesn't support import.
**How**: prefer creating a new Terraform-managed resource, shifting traffic/DNS/app config to it, then deleting the old one; fall back to recreate only when identity can't move (e.g. an unchangeable droplet IP).
**Trade-offs**: transition costs coordination but avoids downtime/data loss risk.

## Pipeline-embedded lifecycle
**When to use**: automating infrastructure changes through CI/CD.
**How**: stages `init → validate → plan (-out=tfplan) → apply -auto-approve` (Jenkins Jenkinsfile or GitHub Actions with `hashicorp/setup-terraform` pinned to a version).
**Trade-offs**: `-auto-approve` removes the human confirm — keep plan review in the pipeline.

## Vault secret injection
**When to use**: any secret needed in Terraform.
**How**: read via `data "vault_generic_secret"` + index (`data["password"]`), write via `resource "vault_generic_secret"`; provider configured with `address` + `token`.
**Trade-offs**: adds a Vault dependency; secrets never live in config or state.