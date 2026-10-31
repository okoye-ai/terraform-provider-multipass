# Chapter 6: Terraform with friends

## Core Idea
Collaboration means sharing state, not just code: move state to a remote backend (S3 + DynamoDB locking + KMS encryption + least-privileged IAM) so concurrent runs lock state and can't corrupt it — and reuse one configuration across environments with workspaces.

## Frameworks Introduced
- **The Four Components of an S3 Backend**: (1) DynamoDB table (state locking), (2) S3 bucket + KMS key (storage, encryption at rest), (3) least-privileged IAM role other accounts assume to deploy, (4) housekeeping (resource-groups tag group)
  - When to use: standing up team state storage; the same component map applies to AZ Storage/GCS backends
- **Flat vs. Nested Modules**: flat = many little .tf files in one module (one file per component, e.g. iam.tf), no plumbing boilerplate, but higher coupling (like global variables)
  - Rule: flat suits small/medium codebases whose components are functionally independent; nested suits larger/shared codebases — module inputs/outputs abstract implementation details
  - Key: name things well and put them where people expect (main.tf holds the most important resources)
- **Why Remote State Beats VCS-committed state**: state in git exposes secrets and does nothing about race conditions; a remote backend provides locking, encryption at rest, version history
- **Workspaces = Parameterized State**: one configuration, N state files (one per workspace), each parameterized by its own -var-file (dev.tfvars / int.tfvars / prod.tfvars)
  - Mechanism: `terraform.workspace` is a special reference used in tags/naming; workspaces are effectively renamed state files, but remote backends support workspaces rather than `-state=` paths
- **Backend Configuration Rules**: `backend "s3" { bucket, key, region, encrypt, role_arn, dynamodb_table }` inside the terraform block; the backend region can differ from the deployment region — and since backends are evaluated at init, **backend settings cannot be variables**

## Key Concepts
- **Race condition / state lock**: two entities acting on one state file (one apply, one destroy) → corrupted state; the loser gets a lock error and must wait; never run with `-lock=false`
- **Lock error is normal**: `ConditionalCheckFailedException` while acquiring the state lock means someone else is mid-operation — wait, don't force
- **null_resource + local-exec**: dummy resource for tests/hacks; `triggers = { always = timestamp() }` makes it recreate every apply
- **`terraform state list`**: inspect what's in the current state without downloading it
- **State keys**: stored under `key` (e.g. `jesse/james`) and `env:/dev/...` for non-default workspaces
- **Module sourcing options**: local paths, GitHub repo (`terraform-<PROVIDER>-<NAME>` naming), S3/GCS/HTTP URLs, Bitbucket, Terraform Registry
- **Registry publishing rules**: public GitHub repo, `terraform-<PROVIDER>-<NAME>` name, README.md, standard module structure (main/variables/outputs.tf), semver release tags (v0.1.0)
- **terraform-docs**: generates module documentation from config — recommended
- **Terraform Cloud vs Enterprise**: same features; TFE runs in a private datacenter; free TeC tier already gives remote state + VCS workflow; paid tiers add teams, SSO, Sentinel policy-as-code

## Code Examples
```hcl
# Least-privileged policy for backend users: state S3 + lock table only
data "aws_iam_policy_document" "policy_doc" {
  statement { actions = ["s3:ListBucket"]  resources = [aws_s3_bucket.s3_bucket.arn] }
  statement { actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
              resources = ["${aws_s3_bucket.s3_bucket.arn}/*"] }
  statement { actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
              resources = [aws_dynamodb_table.dynamodb_table.arn] }
}

# Backend block (cannot use variables — evaluated at init)
terraform {
  backend "s3" {
    bucket         = "team-rocket-...-state-bucket"
    key            = "jesse/james"
    region         = "us-west-2"
    encrypt        = true
    role_arn       = "arn:aws:iam::...:role/team-rocket-...-tf-assume-role"
    dynamodb_table = "team-rocket-...-state-lock"
  }
}

# One config, many environments
resource "aws_instance" "instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  tags = { Name = terraform.workspace }
}
```
- **What it demonstrates**: the four-piece workspace init contract (bucket, region, role ARN, DynamoDB table) as an output object named `config`

## Reference Tables
| Workspace command | Effect |
|---|---|
| `terraform workspace list` | show workspaces (* marks current); init creates `default` |
| `terraform workspace new <name>` | create + switch (new empty state) |
| `terraform workspace select <name>` | switch |
| `terraform apply -var-file=./environments/dev.tfvars` | parameterize the current workspace |

## Worked Example
Full walkthrough: build the s3backend module (variables.tf, main.tf, iam.tf, outputs.tf, versions.tf, README.md) → publish to the Registry (or use `terraform-in-action/s3backend/aws`) → deploy a backend for Team Rocket by wrapping the module in a root module that outputs `config` → init a test project against it and deploy a null_resource ("gotta catch em all") → verify state lands in S3 under `jesse/james` → create dev/prod workspaces, each deployed with its own var-file and named `terraform.workspace` → clean up by destroying each workspace's stack, then the backend itself.

## Key Takeaways
1. Never commit state to VCS — use a remote backend for locking, encryption, and versioning.
2. One backend per team partitions state with autonomy; a single least-privileged backend also works if you're disciplined.
3. Workspaces: same configuration, different var-files, isolated state — name them dev/int/prod or feature branches.
4. Backend blocks are init-time constants: no variables allowed inside them.
5. Flat modules trade boilerplate for coupling — choose deliberately, and keep files under a few hundred lines.

## Connects To
- **Ch 5**: flat main.tf organization for cohesive small projects
- **Ch 10**: migrating/redeploying state (state moves)
- **Ch 12**: running Terraform in automation (plan/apply separation), bootleg Terraform Enterprise
- **Ch 13**: state files contain sensitive data — securing state is the core theme