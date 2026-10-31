# Chapter 10: Real-World Use Cases

## Core Idea
Ten end-to-end recipes apply the book's techniques to production-shaped problems — multienvironment management, multiregion high availability, Kubernetes, zero-downtime releases, databases, serverless, GitOps, cost optimization, multicloud monitoring, and disaster recovery — showing that architecture decisions, not Terraform syntax, are the hard part.

## Frameworks Introduced
- **Workspace-driven multi-environment management**: one config, one workspace per environment, `terraform.workspace` selecting values.
  - When to use: dev/staging/prd share structure but differ in variables; code duplication is growing.
  - How: a `variable` defaulting to `terraform.workspace`; instance types in a workspace-keyed map; `terraform workspace new dev|prd`, then `select` + `apply`; separate state files give environment isolation.
- **Aliased providers for multi-region HA**: paired regional VPC + Auto Scaling groups unified by one global traffic entry point.
  - When to use: mission-critical web apps must survive an entire region outage.
  - How: declare `provider "aws"` blocks with `alias` per region; instantiate the same `modules/vpc` and `modules/asg` per region via `providers = { aws = aws.us_east_1 }`; front them with AWS Global Accelerator — a listener plus `endpoint_group` weighting each region's ALB (50/50) — which routes to the nearest healthy endpoint.
- **Cluster-as-code EKS stack**: the whole Kubernetes platform (network, control plane, node groups) from community modules.
  - When to use: manually standing up EKS is slow and hard to make consistent, secure, or scalable.
  - How: `terraform-aws-modules/vpc/aws` (pinned 3.14.0) with private subnets, NAT gateway, and `kubernetes.io/cluster/<name> = shared` tags; `terraform-aws-modules/eks/aws` (pinned 20.24.0) with `eks_managed_node_groups` (desired/min/max, on-demand capacity type); output the kubeconfig as `sensitive`.
- **Blue-green deployment via target-group switch**: two parallel ASGs behind one ALB; switching is one listener edit.
  - When to use: traditional deploys cause downtime or hard rollbacks.
  - How: launch templates (blue, green) with distinct `user_data`; an ASG + `aws_lb_target_group` per color; `aws_lb_listener` forwarding to the active target group — flip green live by re-pointing the listener, and roll back by re-pointing again.
- **Hash-triggered migration execution**: run schema migrations only when the SQL actually changes.
  - When to use: schema changes must stay in sync with provisioned infrastructure, repeatably across environments.
  - How: RDS instance + subnet group + SG; `data "template_file"` loading `migrations/V1__initial_schema.sql`; a `null_resource` whose trigger is `sha256(data.template_file.migration_script.rendered)` running a `local-exec` `mysql` pipe, `depends_on` the DB instance.
- **Serverless wiring (Lambda + API Gateway)**: function, IAM, REST API, and the invoke-permission loop as code.
  - When to use: manually configuring functions, permissions, and triggers is error-prone.
  - How: execution role with `AWSLambdaBasicExecutionRole`; `aws_lambda_function` with `source_code_hash = filebase64sha256(...)` for redeploy-on-change; REST API → resource → method → `AWS_PROXY` integration to the Lambda `invoke_arn`; deployment on stage `prod`; `aws_lambda_permission` (principal `apigateway.amazonaws.com`, scoped `source_arn`) closing the loop.
- **Branch-to-workspace GitOps pipeline**: Git branches ARE the environments; the workflow maps branch name to workspace.
  - When to use: multi-environment deployments need consistency, traceability, and controlled promotion.
  - How: repo layout `environments/` + shared `modules/`; GitHub Actions on push to `development`, `staging`, `main` plus PRs to `main`; plan step runs `terraform workspace select ${GITHUB_REF##*/} || terraform workspace new ${GITHUB_REF##*/}`; apply is gated to `refs/heads/main` pushes — other branches need approval; protect `main` and store AWS creds as GitHub secrets.
- **Spot-Instance mixed-instances policy**: an On-Demand base plus capacity-optimized Spot for most capacity.
  - When to use: workloads tolerant of interruption where on-demand pricing dominates cost.
  - How: launch template + `mixed_instances_policy` with per-type `override` blocks carrying `weighted_capacity`; `instances_distribution` sets `on_demand_base_capacity`, `on_demand_percentage_above_base_capacity`, and `spot_allocation_strategy = "capacity-optimized"`; design the app for the two-minute termination notice.
- **Multicloud monitoring aggregation**: AWS + Azure resources under one third-party pane of glass.
  - When to use: per-cloud monitoring tools can't be consolidated; manual per-platform setup is unmanageable.
  - How: declare `aws`, `azurerm`, and `datadog` providers together; provision instances in both clouds; `datadog_monitor` resources with per-cloud metric queries (`aws.ec2.cpu`, `azure.vm.percentage_cpu`) at a critical threshold; one `datadog_dashboard` charting both clouds side by side.
- **Automated DR architecture**: warm standby in a second region with event-driven failover.
  - When to use: manual DR setup is slow and error-prone; downtime threatens business continuity.
  - How: aliased `aws` provider with `alias = "dr"` for the DR region; versioned S3 backup bucket with a lifecycle rule (GLACIER at 30 days, expire at 90); primary EC2 + EBS `gp3` volume with `aws_volume_attachment`; `aws_drs_replication_configuration_template` with EBS encryption under a KMS key; a CloudWatch event rule matching `aws.health` issue events in the primary region that triggers a Lambda failover handler.

## Key Concepts
- **Terraform workspace**: separate state files per environment within one config — the unit of environment isolation in this chapter.
- **Provider alias**: a named secondary provider instance (`alias = "us_east_1"`, `alias = "dr"`) letting one config manage multiple regions, selected per module via `providers`.
- **AWS Global Accelerator**: static single entry point that routes traffic to the nearest healthy regional endpoint group — the failover mechanism of recipe 10.2.
- **Target group / listener switch**: the ALB construct that makes blue-green a routing change instead of a rebuild.
- **`source_code_hash`**: `filebase64sha256` of the function bundle so Terraform redeploys Lambda only when code changes.
- **`AWS_PROXY` integration**: API Gateway's direct proxy pass-through of requests to a Lambda `invoke_arn`.
- **`null_resource` trigger hash**: `sha256`-of-content trick that re-runs migrations/scripts exactly when their input changes.
- **`instances_distribution`**: the ASG policy block balancing On-Demand base capacity against Spot, with `capacity-optimized` allocation favoring availability.
- **Spot Instance termination notice**: the two-minute warning an app must handle to use Spot safely.
- **AWS Elastic Disaster Recovery (DRS)**: replication configuration service providing encrypted cross-region server replication for DR.
- **GitOps**: Git as the single source of truth so every infra change is a commit, reviewable and auditable end to end.

## Mental Models
- Use the branch name as the workspace name when promotion between environments should be a Git push, not a command decision.
- Use a global entry point (Global Accelerator, weighted endpoint groups) whenever regional independence matters — individual regions fail; the entry point does not.
- Use "flip the listener, flip the color" as the definition of a zero-downtime deploy: two complete environments, one routing decision, rollback = flip back.
- Use lifecycle rules on the backup bucket and a warm DR region as a spectrum, not constants — match DR spend to the disaster tolerance you actually have.

## Anti-patterns
- **Deploying a single-region app as mission-critical**: a regional failure takes the whole app down — plan for cross-region fault tolerance.
- **Manual database schema changes**: leads to inconsistencies, lost migration history, and data-loss risk — keep migrations versioned and hash-triggered.
- **Hardcoded credentials or non-idempotent migration scripts**: secrets leak and re-runs corrupt state — use Terraform variables or AWS Secrets Manager, design migrations to run repeatedly.
- **All-On-Demand fleets for tolerant workloads**: expensive — mix Spot with a modest On-Demand base and diverse instance types.
- **Per-cloud monitoring silos**: each provider's tools can't be consolidated manually; aggregate via one platform (Datadog) provisioned in Terraform.
- **DR that is never exercised**: failover paths rot — run regular DR drills, and remember data synchronization (e.g. AWS DMS) between sites.
- **Keeping old environments after a successful blue-green switch**: wasted cost — clean up unused resources; plan data sync between colors for stateful apps.

## Code Examples
```hcl
# Aliased providers + shared module per region, unified by Global Accelerator
provider "aws" { alias = "us_east_1"; region = "us-east-1" }
provider "aws" { alias = "us_west_2"; region = "us-west-2" }

module "vpc_east" {
  source   = "./modules/vpc"
  providers = { aws = aws.us_east_1 }
  cidr_block = "10.0.0.0/16"
  region     = "us-east-1"
}

resource "aws_globalaccelerator_endpoint_group" "example" {
  listener_arn = aws_globalaccelerator_listener.example.id

  endpoint_configuration {
    endpoint_id = module.asg_east.alb_arn
    weight      = 50
  }
  endpoint_configuration {
    endpoint_id = module.asg_west.alb_arn
    weight      = 50
  }
}
```
- **What it demonstrates**: multi-region HA with aliased providers feeding a weighted global entry point.

```hcl
# Run the migration only when the SQL content changes
data "template_file" "migration_script" {
  template = file("${path.module}/migrations/V1__initial_schema.sql")
}

resource "null_resource" "db_migration" {
  triggers = {
    migration_hash = sha256(data.template_file.migration_script.rendered)
  }

  provisioner "local-exec" {
    command = <<EOF
      mysql -h ${aws_db_instance.example.endpoint} -u ${var.db_username} -p${var.db_password}
        ${aws_db_instance.example.db_name} < ${path.module}/migrations/V1__initial_schema.sql
    EOF
  }

  depends_on = [aws_db_instance.example]
}
```
- **What it demonstrates**: content-hash-triggered migration execution alongside RDS provisioning.

```hcl
# On-Demand base + capacity-optimized Spot in one ASG
resource "aws_autoscaling_group" "example" {
  name                = "example-asg"
  min_size            = 2
  max_size            = 10
  desired_capacity    = 4

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.example.id
        version            = "$Latest"
      }
      override {
        instance_type     = "t3.micro"
        weighted_capacity = "1"
      }
      override {
        instance_type     = "t3.small"
        weighted_capacity = "2"
      }
    }
    instances_distribution {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }
}
```
- **What it demonstrates**: the cost-optimization balance between availability and Spot savings.

## Reference Tables
None in this chapter. Guidance is prose-weighted: use Spot + weighted instance overrides for interruption-tolerant work; reserve blue-green for zero-downtime needs; choose warm DR replication (DRS) plus event-triggered Lambda failover when downtime must shrink to minutes; prefer a single monitoring aggregator (Datadog) over per-cloud consoles.

## Worked Example
Recipe 10.4 assembles a complete blue-green system: a VPC (two AZs, NAT gateway) and one SG open on port 80; `aws_launch_template` `blue` and `green` carrying `user_data` that writes a distinct index page and serves it; an `aws_autoscaling_group` per color (desired 2, max 4, min 1) each bound to its own `aws_lb_target_group`; an internet-facing `aws_lb` on the public subnets; and one `aws_lb_listener` on port 80 whose `default_action` forwards to `aws_lb_target_group.blue`. Deploying a new version means loading the new code into the green launch template, letting the green ASG come up verified and healthy, then editing the listener to forward to `aws_lb_target_group.green` — live traffic moves without downtime, and a bad release reverts by pointing the listener back. Rollouts can be gradual by shifting weights, and the now-idle blue stack is torn down once green is confirmed.

## Key Takeaways
1. Environments differ in variables, not in code — encode the differences in workspace-keyed maps and promote through branches.
2. High availability is a routing design: aliased providers per region, identical shared modules per region, and a global weighted entry point that fails over for you.
3. Treat a release as a routing change: build the new color fully, verify health, flip the listener, keep the old color as instant rollback.
4. Pair infrastructure provisioning with schema migrations in one pipeline, using content-hash triggers so migrations run only when they change.
5. Wire serverless completely — function, role, API, integration, and the explicit `aws_lambda_permission` — and version APIs with stage variables or Lambda aliases.
6. Cost optimization is policy, not luck: On-Demand base for availability, `capacity-optimized` Spot for the rest, diverse instance types, and app-level handling of the two-minute termination notice.
7. DR that isn't automated and regularly tested doesn't exist; define primary + DR region as code, replicate via DRS, and trigger failover from AWS Health events with Lambda.

## Connects To
- **Ch 9**: workspaces (10.1) operationalize Chapter 9's workspace pattern; the GitOps pipeline (10.7) is the chapter's CI/CD pattern extended to many environments with drift detection.
- **Kubernetes / EKS**: the community `terraform-aws-modules` stack is the canonical IaC entry point for a scalable cluster plus Cluster Autoscaler.
- **GitOps**: branch-protection, review-gated applies, and Git as source of truth align with standard GitOps practice.
- **Datadog/Prometheus-style monitoring integrations**: 10.9 shows the aggregator pattern as the multicloud generalization of 9.8's managed Prometheus/Grafana setup.
- **RTO/RPO (disaster recovery planning)**: DRS replication and automated failover map to recovery-time and recovery-point objectives in formal DR strategy.
- **Spot pricing model / Reserved Instances**: for predictable long-term workloads blend Reserved, On-Demand, and Spot for optimal savings.