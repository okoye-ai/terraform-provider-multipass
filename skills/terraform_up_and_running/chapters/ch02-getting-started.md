# Chapter 2: Getting Started with Terraform

## Core Idea (1–2 sentences)
Terraform is a declarative infrastructure-as-code tool (written in HCL, `.tf` files) where you describe the desired end state, and Terraform figures out the creation order, parallelism, and diffs needed to get there. This chapter walks a progression — single EC2 instance → web server → configurable web server → ASG cluster → ALB load balancer — that establishes the core Terraform workflow (init → plan → apply → destroy) and primitives (providers, resources, references, variables, outputs, data sources, lifecycle).

## Frameworks Introduced (exact author names, each with "When to use" and "How")
- **Terraform declarative workflow (HashiCorp)** — When to use: any time you provision or change infrastructure. How: write config describing desired state, run `terraform init` (download providers), `terraform plan` (preview diff), `terraform apply` (execute with confirmation), `terraform destroy` (tear down).
- **Resource + attribute reference model (HashiCorp)** — When to use: wiring resources together. How: syntax `<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>` (e.g. `aws_security_group.instance.id`); data sources use `data.<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>`.
- **DRY principle (Andy Hunt and Dave Thomas, *The Pragmatic Programmer*)** — When to use: any value duplicated in code (the chapter's example: port 8080 in both the security group and User Data). How: extract into an input variable and reference it everywhere (`var.server_port`).
- **Immutable infrastructure paradigm (Brikman, drawing on server-templating tools like Packer)** — When to use: when instance config (User Data) changes; mutable in-place updates won't re-run boot scripts. How: set `user_data_replace_on_change = true` / resource replacement (`-/+` "forces replacement" in plan) to terminate and relaunch rather than modify.
- **Input/output variable configuration (HashiCorp)** — When to use: making code configurable and reusable across environments. How: `variable` blocks with `description`, `type`, `default`, `validation`, `sensitive`; `output` blocks with `value`, `description`, `sensitive`, `depends_on`; consume via CLI (`-var`), `TF_VAR_<name>` env vars, or `terraform output`.
- **ALB component model (AWS)** — When to use: load balancing HTTP/HTTPS apps. How: compose listener (port 80 + protocol, with default action), listener rules (path/hostname conditions → actions), and target groups (health checks forward only to healthy instances).

## Key Concepts (5–10 terms, 1-sentence precise definitions)
- **Provider**: the plugin Terraform uses to talk to a platform (aws, azure, gcp, etc.), configured in a `provider` block and downloaded by `terraform init` into `.terraform/` with versions locked in `.terraform.lock.hcl`.
- **Resource**: a piece of infrastructure to create, `resource "<PROVIDER>_<TYPE>" "<NAME>" { [CONFIG ...] }`.
- **Data source**: a read-only lookup fetched from the provider on every run that creates nothing, used for queries like the Default VPC or its subnets.
- **Reference / interpolation**: expressions that return values — `aws_security_group.instance.id` between resources, `${...}` inside string literals.
- **Implicit dependency**: Terraform infers creation order from references between resources, building a dependency graph (viewable via `terraform graph`, DOT/Graphviz) and creating resources in parallel where possible.
- **Input variable**: a parameterized value with optional `description`, `type`, `default`, `validation`, `sensitive`; missing value prompts interactively or errors on invalid type.
- **Output variable**: a value surfaced after apply (e.g. `public_ip`, `alb_dns_name`), readable via `terraform output` for scripting smoke tests.
- **User Data**: a shell script or cloud-init directive run on an EC2 instance's *first boot only*; hence `user_data_replace_on_change = true` forces replacement so changed scripts actually execute.
- **Auto Scaling Group (ASG)**: AWS service that maintains a cluster between `min_size`/`max_size`, launching instances from a launch configuration and replacing failed ones (self-healing).
- **Lifecycle settings**: per-resource options like `create_before_destroy = true` that invert replacement order — needed when other resources (an ASG) reference a resource about to be replaced.

## Mental Models (2–4, written as "Use X when Y")
- **Use `plan -style diff reading when sanity-checking changes**: the plan output is a diff — `+` created, `-` deleted, `~` modified in-place, `-/+` replaced; search for "forces replacement" to find what triggers a destroy/recreate.
- **Use `create_before_destroy = true` when a referenced resource is immutable** (e.g. launch configurations): replacement must happen in the other order or Terraform cannot delete the old object.
- **Use data sources when values depend on the account/region** (Default VPC, subnets, AMI IDs) instead of hardcoding — hardcoding won't be maintainable or portable (AMI IDs differ per region).
- **Use declarative state tracking instead of procedural scripting when you need to know "what will change"**: Terraform refreshes state each run, so it can always diff real vs. desired infrastructure.

## Anti-patterns
- **Using the root AWS user day-to-day** — root can do anything; use it only to create limited IAM users, then switch.
- **Checking in state or the scratch directory** — `.gitignore` must contain `.terraform`, `*.tfstate`, `*.tfstate.backup`; commit `main.tf` and `.terraform.lock.hcl` but never state files.
- **Committing secrets in plan/apply logs** — mark secret-typed variables and outputs with `sensitive = true`; Terraform will not log them.
- **Duplicating values across resources (DRY violations)** — port numbers, AMI IDs, etc. belong in variables/referenceable places.
- **Relying on User Data changes without forcing replacement** — default in-place update silently skips the new script since User Data runs only on first boot.
- **Running servers in public subnets in production** — fine for experiments, in production only load balancers/reverse proxies belong in public subnets; servers and all data stores must be in private subnets.
- **Using `destroy` casually** — there is no undo; only run it for teardown of non-production resources.
- **Static instance lists with ASGs** — with an ASG instances come and go, so use the ASG's `target_group_arns` integration rather than `aws_lb_target_group_attachment`.
- **Memorizing provider syntax instead of consulting docs** — dozens of providers × resources × arguments; even the author checks docs multiple times per day.

## Code Examples (2–3 short key HCL blocks/CLI workflows, exact syntax)

Core workflow and resource syntax:
```hcl
provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "example" {
  ami                      = "ami-0fb653ca2d3203ac1"   # Ubuntu 20.04, us-east-2 only
  instance_type            = "t2.micro"
  vpc_security_group_ids   = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  user_data_replace_on_change = true

  tags = {
    Name = "terraform-example"
  }
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

output "public_ip" {
  value       = aws_instance.example.public_ip
  description = "The public IP address of the web server"
}
```

CLI workflow:
```sh
export AWS_ACCESS_KEY_ID=(your access key id)
export AWS_SECRET_ACCESS_KEY=(your secret access key)
terraform init     # download provider plugins into .terraform/, lock in .terraform.lock.hcl
terraform plan     # diff preview: + create, - delete, ~ modify, -/+ replace
terraform apply    # shows same plan, requires typing 'yes'
terraform output public_ip   # or: terraform plan -var "server_port=8080" / export TF_VAR_server_port=8080
terraform destroy  # no undo; confirms before deleting in dependency order
```

Security group + data sources:
```hcl
resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
```

## Reference Tables (reproduce any table, e.g. plan/apply lifecycle, provider mechanics)

Terraform lifecycle commands:
| Command | Purpose | Notes |
|---|---|---|
| `init` | Prepare working directory; download provider plugins | Idempotent, safe to rerun; writes `.terraform/`, `.terraform.lock.hcl` |
| `validate` | Check configuration validity | |
| `plan` | Show changes before applying | Diff symbols: `+` add, `-` delete, `~` modify, `-/+` replace |
| `apply` | Create/update infrastructure | Replays the plan, requires typed `yes`; prints outputs |
| `destroy` | Delete all managed infrastructure | No undo; deletes in dependency order |
| `output` | Read output values without applying | `terraform output <NAME>` for scripting |
| `graph` | Emit DOT dependency graph | Render with Graphviz; unusable at large scale |

AWS load balancer types:
| Type | OSI layer | Traffic | Notes |
|---|---|---|---|
| ALB | L7 | HTTP/HTTPS | Best fit for web apps |
| NLB | L4 | TCP/UDP/TLS | Fastest scaling, tens of millions of req/s |
| CLB | L4 + L7 | HTTP/HTTPS/TCP/TLS | Legacy; fewest features |

ASG vs EC2 resource parameter mapping: `ami` → `image_id`, `vpc_security_group_ids` → `security_groups`; launch configuration drops `tags` and `user_data_replace_on_change` (ASGs always launch new instances).

Input variable parameters: `description` (docs, shown during apply), `type` (string, number, bool, list, map, set, object, tuple, any — defaults to `any`), `default` (else interpolate prompt / `-var` / `TF_VAR_<name>`), `validation` (custom rules), `sensitive` (suppress logging). Output parameters: `value`, `description`, `sensitive` (required if referencing sensitive values), `depends_on` (explicit ordering hint).

## Worked Example (reconstruct ONE concrete example walk-through from the chapter — e.g. the web-server deployment progression — compactly)

**Progression: single server → HA cluster behind ALB (all in AWS Default VPC, us-east-2):**

1. **Single server.** `provider "aws"` + `aws_instance` (Ubuntu 20.04 AMI `ami-0fb653ca2d3203ac1`, `t2.micro`). `init` → `plan` (shows `Plan: 1 to add`) → `apply` → instance live in the EC2 console. Add a `tags = { Name = "terraform-example" }` block, re-apply — Terraform shows an in-place update (`~ resource`, `Plan: 0 to add, 1 to change`).
2. **Single web server.** Add a Bash User Data script (`echo "Hello, World" > index.html; nohup busybox httpd -f -p 8080 &`) plus `aws_security_group` allowing inbound TCP 8080 from `0.0.0.0/0`, referenced as `aws_security_group.instance.id`. Because `user_data_replace_on_change = true`, the next apply shows `-/+ ... # forces replacement`: old instance terminated, new one launched with `curl http://<PUBLIC_IP>:8080` returning `Hello, World`.
3. **Configurable web server (DRY).** Extract the port into `variable "server_port"` (type `number`), reference it via `var.server_port` in the security group ports and `${var.server_port}` in the User Data heredoc. Add `output "public_ip"` so `terraform output` prints the IP for a scripted smoke test.
4. **Cluster.** Swap `aws_instance` for `aws_launch_configuration` (same params, `security_groups`, no `user_data_replace_on_change`) with `lifecycle { create_before_destroy = true }` (launch configurations are immutable and the ASG references them). Add `aws_autoscaling_group` with `min_size = 2`, `max_size = 10`, `vpc_zone_identifier = data.aws_subnets.default.ids`, and a propagated `Name` tag.
5. **Load balancer.** Create `aws_lb` (`load_balancer_type = "application"`, `subnets` from the data source, ALB security group allowing inbound 80 and all egress), a listener on port 80 with a fixed 404 default response, a `aws_lb_target_group` health-checking `/` every 15s (matcher 200, thresholds 2), and a listener rule `path_pattern ["*"] → forward` to the target group. Wire the ASG with `target_group_arns` and `health_check_type = "ELB"` so instances failing app health checks get replaced (not just VM-down instances).
6. **Verify and self-heal.** Apply produces the `alb_dns_name` output; after instances show healthy in the target group, `curl http://<alb_dns_name>` returns `Hello, World`. Terminating an instance manually: ALB stops routing to it and the ASG launches a replacement automatically.
7. **Cleanup.** `terraform destroy` confirms (`8 to destroy`), deletes in dependency order; code is kept in Git since `apply` can recreate everything.

## Key Takeaways (3–7 actionable)
- Follow the canonical loop: `init` → `plan` → `apply`, reading the plan diff (`+`, `-`, `~`, `-/+`) as your safety net before every change; treat "forces replacement" as a red flag that the change will cause downtime.
- Use references (`<RESOURCE>.<ATTRIBUTE>`) to express dependencies — Terraform builds the graph, orders creation, and parallelizes for you.
- Parameterize every repeated value with input variables (`description` + `type` always; `sensitive` for secrets), expose useful endpoints as outputs, and script smoke tests with `terraform output`.
- Use data sources for account-relative lookups (Default VPC, subnets) instead of hardcoding IDs that vary per region/account.
- Set `user_data_replace_on_change = true` and `create_before_destroy = true` on launch configurations — the two lifecycle gotchas of first-boot scripts and immutable references.
- Prefer ALB over NLB/CLB for web apps (ALB = L7, NLB = L4), and let ASG + target-group health checks (`health_check_type = "ELB"`) give you scaling and self-healing for free.
- Version-control Terraform code (`main.tf` + `.terraform.lock.hcl`) but gitignore `.terraform/` and all `*.tfstate*` files; run `terraform destroy` to stop cloud charges, never in production.

## Connects To
- **Ch. 1** — why Terraform vs. manual config/procedural IaC (declarative language, immutable infrastructure, server templating with Packer).
- **Ch. 3** — Terraform state: how `.tfstate` tracking (mentioned here as "Refreshing state…") works, why state files can't be checked in, and backend storage.
- **Ch. 4** — modules: input/output variables were introduced here precisely to make code reusable and configurable.
- **Ch. 5** — zero-downtime deployment (this ALB/ASG setup has per-instance replacement downtime today).
- **Ch. 6–7** — secrets management and provider/auth configuration depth (`AWS_ACCESS_KEY_ID` here; IAM roles, provider settings later).
- **Ch. 8** — the `.terraform.lock.hcl` dependency lock file and version pinning.
- **Ch. 10** — Terraform as a team: plan output in code reviews, git workflows for infrastructure.