# Chapter 4: Deploying a multi-tiered web application in AWS

## Core Idea
Break a complex deployment into modules — self-contained packages treated as functions with side effects (the resources they provision) — and pass data between them by "bubbling up" outputs to the root module and "trickling down" inputs; minimize the passing, because inter-module plumbing is the main cost of modularization.

## Frameworks Introduced
- **Modules as Functions with Side Effects**: a module's inputs are variables, outputs are return values, side effects are the resources `apply` provisions
  - Treat modules as black boxes: know the inputs/outputs, not the internals
- **Bubble-Up / Trickle-Down Data Flow**: child module output → parent (root) module → passed as an input variable of a sibling child module
  - When to use: whenever sibling modules need to share data (networking → database → autoscaling)
  - Rule: data passing is tedious and hurts readability — co-locate resources that share a lot of data in the same module, and bubble up only the minimum needed (least privilege for data)
- **Software Componentization**: large projects are built mostly *from other modules* (VPC module by the AWS team, security-group module, ALB module) instead of raw resources
- **Build vs. Buy for Modules**: registry modules save time now but add supply-chain risk (backdoors, abandonment, deletion)
  - How: trust only high-star GitHub modules, skim the source, fork and/or version-lock third-party modules
- **Nested Module Hierarchy**: root → child → grandchild; keep it ≤ 3–4 levels deep

## Key Concepts
- **Root module**: the directory where you run `terraform apply`; where variables are configured and child modules are wired together
- **Standard module structure (min)**: `main.tf` (entry point), `outputs.tf`, `variables.tf`; root module additionally wants `versions.tf`, `providers.tf`, `README.md`, `terraform.tfvars`
- **Module syntax**: `module "<name>" { source = ...; version = ...; <inputs> }` — source may be local (`./modules/autoscaling`) or remote (Terraform Registry)
- **Namespace variable**: a single project identifier (e.g. `tiachapter4-dev`) used for unique resource naming; some authors split it into `project_name` + `environment` — either is fine as long as it's unique and descriptive
- **`any` type**: skips type checking — only use for inter-module data passing, never for root-module inputs (lazy habit)
- **Object-typed output values**: group related attributes into a single output object (`sg = { lb = ..., db = ..., websvr = ... }`)
- **launch template / autoscaling group**: ASG instances come from a launch template blueprint (user data, AMI, metadata); the ASG is one load-balancer target; registers via `target_group_arns`

## Code Examples
```hcl
# Root module wiring: outputs of one module become inputs of another
module "database" {
  source    = "./modules/database"
  namespace = var.namespace
  vpc       = module.networking.vpc          # bubbles up, trickles down
  sg        = module.networking.sg
}

# Strict object typing for a passed-in config (good vs. the lazy "any")
variable "db_config" {
  type = object({ user = string, password = string, database = string,
                  hostname = string, port = string })
}

# Random DB password + RDS instance consuming bubbled-up VPC/SG data
resource "random_password" "password" {
  length = 16
  special = true
  override_special = "_%@/'\""
}
resource "aws_db_instance" "database" {
  identifier             = "${var.namespace}-db-instance"
  password               = random_password.password.result
  db_subnet_group_name   = var.vpc.database_subnet_group
  vpc_security_group_ids = [var.sg.db]
  skip_final_snapshot    = true
  # engine mysql 8.0, db.t2.micro, ...
}

# cloud-init user data templated from the DB config
data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/cloud_config.yaml", var.db_config)
  }
}
```
- **What it demonstrates**: the classic three-tier wiring: ASG (private subnets, min 1/max 3) behind a public ALB (:80 → backends on :8080), MySQL in private subnets on :3306, security groups chained lb → websvr → db

## Reference Tables (Chapter architecture)
| Module | Resources | Outputs |
|---|---|---|
| networking | VPC (registry module: 10.0.0.0/16, public/private/db subnets, NAT), 3 SGs | `vpc` (whole module ref), `sg` (object of 3 IDs) |
| database | random_password, aws_db_instance | `db_config` object (user/password/database/hostname/port) |
| autoscaling | IAM instance profile, cloudinit AMI lookup, launch template, ASG, ALB | `lb_dns_name` |

Rule from the dependency diagrams: declare resources in a module top-to-bottom from fewest to most dependencies ("resource chaining"); SGs optionally live in the networking module vs. the consuming module — preference.

## Worked Example
The chapter's capstone: a social-media-style pet website. Root module exposes only `namespace` (required), `ssh_keypair`/`region` (optional, default us-west-2); outputs `db_password` and `lb_dns_name`. Deployment takes ~10–15 min (40 resources); 502 errors right after apply mean the web server is still initializing — persistent 502 means a malformed cloud-init file. Cleanup via `terraform destroy`.

## Key Takeaways
1. Design module boundaries around data-sharing: resources that share a lot of data belong in the same module.
2. Expose root-module outputs the user actually needs (DNS name, credentials) and nothing more.
3. Version-lock third-party modules; trust high-star, briefly-audited registry modules.
4. Strict `object(...)` types beat `any` for the data flowing between modules — free validation at plan time.
5. Template runtime config (cloud-init) from module inputs so launch templates stay parameterized.

## Connects To
- **Ch 6**: flat modules as an alternative to nested hierarchies; publishing modules to the Registry
- **Ch 5/7/8**: serverless and containerized alternatives to this multi-tier VM architecture
- **Ch 13**: the printed db_password is a secret leak pattern; port 80 public HTTP is dev-grade, not production