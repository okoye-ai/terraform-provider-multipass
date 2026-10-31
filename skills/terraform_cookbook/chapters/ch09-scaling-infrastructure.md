# Chapter 9: Scaling Infrastructure with Terraform

## Core Idea
Scaling is codified three ways: platform autoscaling constructs (ASG / VMSS) for load-driven elasticity, meta-arguments (`count`, `for_each`) plus modules+workspaces for replication across regions and environments, and state/performance discipline (state splitting, `-target`, `-parallelism`, blue-green lifecycle) so Terraform itself scales with the codebase.

## Frameworks Introduced
- **Declarative auto-scaling stack**: a scale unit (ASG / VMSS) wired to metrics-driven scaling.
  - When to use: workloads with variable load (flash sales, exam-season spikes).
  - How: pick metric triggers (CPU utilization, request queue length), define cooldown periods to avoid oscillation, configure health checks + grace periods so new instances are functional before traffic, and use lifecycle settings like `create_before_destroy` for interruption-free capacity change. AWS: `aws_autoscaling_group` + launch template + CloudWatch alarm + scaling policy; Azure: `azurerm_linux_virtual_machine_scale_set` + `azurerm_monitor_auto-scale_setting`; GCP: `google_compute_instance_group_manager` + `google_monitoring_alert_policy`/autoscaler.
- **count vs. for_each decision rule**: use `count` for homogeneous, index-based replication (one number, identical instances); use `for_each` when each instance needs distinct parameters or a stable name-key (map/set of strings) — map keys keep state tracking predictable as things are added or removed.
- **Module + workspace multi-region pattern**: encapsulate the stack in a module, instantiate per region by passing `location`/prefix variables, and isolate each region's state in its own workspace.
  - How: `terraform workspace new eastus` / `new brazilsouth`, then `workspace select` + apply with region vars.
- **State splitting + targeted operations (Recipe 54)**: two complementary strategies for large state.
  - When to use: hundreds+ of resources make plan/apply re-evaluate the entire graph for every change.
  - How: (1) targeted runs — `terraform plan -target=module.db.azurerm_sql_database.mydb -out=db.plan` then `apply "db.plan"` for scoped fixes (sparingly: don't build permanent workflows on `-target`); (2) state splitting — one root module + dedicated remote backend per functional area (network/, compute/, database/), init each independently, run per-module CI in parallel; combine both for hot-fix agility plus long-term speed.
- **Blue-green deployment pattern**: provision a parallel green environment beside live blue, validate it, switch traffic (load balancer/DNS), then destroy blue.
  - When to use: zero-downtime version upgrades with a rollback path.
  - How: Application Gateway / AWS ALB listener rule / GCP backend service controls routing; Terraform variables (`env_prefix`) drive which set is live; rolling updates are the alternative — replace instances in small batches instead of duplicating everything.
- **Performance toolkit for large deployments**: `-parallelism=N` for concurrency, `-target` to scope refresh/plan, disable or timeout-config static data sources, cache provider plugins and use workspaces in CI to avoid repeated backend init.

## Key Concepts
- **Auto Scaling Group (ASG) / VM Scale Set (VMSS)**: first-class Terraform resources declared with min/max/desired capacity, health-check settings, and scaling policies — auditable capacity that adapts without manual intervention.
- **`desired_capacity` / `min_size` / `max_size`**: baseline, floor, and ceiling of autoscaling pools; `health_check_grace_period` (e.g., 300s) gives new instances warmup time before checks.
- **Scaling policy + CloudWatch alarm**: `aws_autoscaling_policy` (adjustment_type `ChangeInCapacity`, `scaling_adjustment`, `cooldown`) triggered by an `aws_cloudwatch_metric_alarm` on `CPUUtilization` exceeding a threshold over `evaluation_periods`.
- **`azurerm_monitor_auto-scale_setting`**: Azure Monitor rules (scale-out on CPU above threshold, scale-in below) attached to a VMSS behind a load-balancer backend pool.
- **Module reuse with variable injection**: the same module source parameterized by `location` and `resource_prefix` produces identical, consistent stacks — the anti-drift mechanism for multi-region.
- **Workspaces**: separate state per region/environment while sharing one root configuration; `terraform workspace list/show/select` to navigate.
- **`-target=address`**: scopes a plan/apply to one module/resource so Terraform skips graphing unrelated state — an emergency fix tool, not a daily workflow.
- **`-parallelism`**: raises default concurrency of graph traversal (e.g., `terraform plan -parallelism=50` for hundreds of firewall rules).
- **Per-module remote backends**: dedicated backend blocks (azurerm storage container per tier) turn one giant state into mini-states that teams can own and CI can run independently.
- **`create_before_destroy`**: lifecycle setting ensuring replacement capacity exists before old capacity is removed — the Terraform-native ingredient of both blue-green and rolling updates.

## Recipes in this chapter
- **Recipe 49: Auto-scaling group definition** — AWS launch template + ASG + scale-out policy + CPU CloudWatch alarm (threshold variable, 300s cooldown and period).
- **Recipe 50: Azure VM Scale Set with auto-scale** — VMSS behind a Basic LB with VMSS instances (0/1), `azurerm_monitor_auto-scale_setting` min 1 / desired 2 / max 5; scale-out test by dropping the CPU threshold to 1 then reverting.
- **Recipe 51: Scaling infrastructure with count** — `azurerm_app_service` block replicated with `count = var.web_count`, named `${prefix}${count.index}` under one `azurerm_service_plan`.
- **Recipe 52: Multi-region deployment** — `modules/common` (RG, VNet, subnet, NIC, Linux VM) deployed to eastus and brazilsouth in two workspaces, plus a full 10-step per-region verification sequence.
- **Recipe 53: Blue-green deployment example** — dedicated App Gateway subnet + tagged blue scale set; deploy green alongside, flip routing via `env_prefix`, kill blue with a conditional `count`.
- **Recipe 54: Managing large state** — targeted plan/apply on `module.db.azurerm_sql_database.mydb`, then state splitting into per-tier azurerm backends (`network.tfstate`, etc.), and combining the two.

## Anti-patterns
- **Hard-coding multiple resource blocks for N instances**: error-prone and unscalable — `count`/`for_each` replicate and shrink automatically.
- **Choosing `count` when instances need distinct identities**: index-based tracking can shift on reordering; `for_each` keyed by name destroys the right resource when one entry is removed.
- **Overusing `-target=` for daily work**: undermines Terraform's dependency management; reserve it for emergency fixes or oversized projects.
- **Monolithic state across teams**: every small change re-evaluates everything, causes state contention and merge conflicts — split per functional area/backend.
- **Auto-scaling without cooldowns or health checks**: causes oscillation (thrash between scale actions) and traffic to unhealthy/unready instances.
- **Blue-green without a rollback path**: keep blue intact while green is validated — flipping `env_prefix` back to blue is the safety net.
- **Scaling by console clicks**: the chapter's whole premise is variable-driven, code-only scale-up/scale-down so the lifecycle is repeatable and auditable.

## Code Examples
```hcl
# Policy + alarm pair behind an AWS Auto Scaling group
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out-policy"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1    # Add one instance per trigger
  cooldown               = 300  # Seconds before another scale action
}
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu_high_asg"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.app_asg.name }
}
```
- **What it demonstrates**: the canonical Terraform autoscaling wiring — threshold alarm (70% CPU, 2 eval periods of 300s) triggers a +1 scaling action with a 300s cooldown.

```hcl
# Blue-green: destroy the blue scale set only once green is active
resource "azurerm_linux_virtual_machine_scale_set" "blue" {
  count         = var.env_prefix == "green" ? 0 : var.vm_count
  # ... (same config as 'active' but name = "vmss-blue")
}
```
- **What it demonstrates**: a conditional `count` expression as the teardown lever — one variable flip (`env_prefix = "green"`) scales blue to zero while green serves traffic, giving a reversible cutover.

## Reference Tables
count vs for_each decision table (from the "Resource replication" section):

| Situation | Use | Why |
|---|---|---|
| N identical instances (uniform config) | `count = var.n` | One numeric input; new instances appear when the number grows, extras destroyed when it shrinks |
| Per-instance unique names/params (e.g., distinct domains, TLS settings) | `for_each` over a map/set | Each instance keyed by name; removals destroy the right instance, not an index neighbor |
| Region replication of a whole stack | Module + per-region workspace | Same logic, isolated state, no drift |

Strategy pairing table (Recipe 54):

| Need | Strategy | Command shape |
|---|---|---|
| Emergency one-component fix | Targeted run | `terraform plan -target=module.db.azurerm_sql_database.mydb -out=db.plan` → `apply "db.plan"` |
| Long-term scalability / parallel CI | State splitting | one backend per module (azurerm container, `key = "network.tfstate"`) |
| Both | Combine | `cd database/` + `-target` hotfix; full plan/apply where sub-state is small |

## Worked Example
Chef's Special — event-driven capacity cycle (Appetizer → Main course → Dessert):
1. **Scale-up preparation**: baseline variables `web_instance_count = 3`, `db_read_replica_count = 0` over `azurerm_linux_virtual_machine.web { count = var.web_instance_count }` and `azurerm_sql_database.read_replica { count = var.db_read_replica_count; create_mode = "ReadScale" }`. Before launch: `terraform apply -var="web_instance_count=10" -var="db_read_replica_count=1"` — Terraform creates 7 extra web VMs (auto-registered with the LB) and one read replica to offload read-heavy queries.
2. **Peak traffic handling**: no Terraform change — the LB spreads requests across the pre-scaled pool and the replica absorbs read load; this phase is the payoff of scale-up.
3. **Scale-down post-event**: re-apply the baseline (`web_instance_count=3`, `db_read_replica_count=0`); Terraform destroys exactly the seven surplus VMs and the replica, restoring cost-optimized state — the whole cycle is `count` variables plus plan/apply, with no console intervention.

## Key Takeaways
1. Codify autoscaling (ASG/VMSS + alarm + policy) rather than reacting to load manually — cooldowns and health-check grace periods are what keep it stable.
2. Default to `for_each` with named keys when instance identity matters; save `count` for pure numeric replication.
3. One module + one workspace per region turns multi-region deployment into repeated variable-passing, keeping DR and latency-region stacks drift-free.
4. Split large state into per-function-area backends for consistently fast runs, team ownership, and parallel CI; use `-target` only for spot fixes on top of that.
5. `-parallelism` and provider-plugin caching are cheap wins for large plan/apply cycles (e.g., `-parallelism=50`).
6. Blue-green in Terraform is just two parameterized environments plus a routing flip — the rollback is flipping the variable back.
7. Scale-up/scale-down should be a variable edit and apply, never a console action; Terraform destroys exactly the surplus, leaving core infra intact.

## Connects To
- **Ch 8 (External data)**: the `for_each`-from-external-file pattern (Recipe 45, `jsondecode(file(...))`) is the same replication mechanism Ch 9 scales up per region/environment; `terraform_remote_state` links the split-state modules back together.
- **Ch 10 (Advanced language features)**: per its conclusion, the next chapter formalizes the `count`/`for_each` conditionals used here (dynamic blocks, conditional expressions, locals) plus external data scripts and custom providers — the DRY-configuration layer on top of these scaling recipes.