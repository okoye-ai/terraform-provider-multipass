# Chapter 12: Cost of Cloud Computing

## Core Idea
Build cost management into IaC the way you build in security: identify cost drivers, control them with policy tests and cost estimation in the delivery pipeline, then reduce cloud waste and optimize further with elastic and on-demand patterns.

## Frameworks Introduced
- **Cost drivers**: the factors or activities that affect your total cloud computing cost.
  - When to use: any surprising cloud bill — first break it down by offering (compute, database, messaging, object storage, data transfer, other) and by environment (testing vs. production) using tags, then calculate percentage by offering/environment to find what to investigate.
- **Policy tests for cost control**: combining unit testing (ch 6) with policy enforcement (ch 8) to check resource type/size against limits.
  - How: parse IaC for machine types → call the provider API for vCPU/memory of each type → fail the test if any exceeds the limit (e.g., 32 vCPUs); enforce as **soft mandatory** so an approved override is possible. Dynamically query the provider API — offerings change frequently and hardcoding breaks.
- **Cost estimation**: extracting infrastructure resource attributes and generating an estimate of their total cost.
  - When to use: proactively checking whether a change stays within a monthly budget, or assessing a cost-driver adjustment before deploying.
  - How: parse IaC for resource counts by machine type and region → get unit prices dynamically from the provider's billing catalog API → compute monthly cost (unit price × vCPU/RAM × **730 hours/month**, converting nano-units) → assert total < monthly budget. Budget tests run in the pipeline on every change; they should guide sizing, never hard-stop a production change. Always reconcile estimates with the actual monthly bill and refine your budget.
- **Reducing cloud waste** (unused or underutilized resources) — five techniques (Figure 12.5):
  1. **Stop untagged or unused resources**: find untagged/zero-metric resources, confirm with the team and metrics, delete the IaC. If unsure, stop the resource for a week or two before deleting.
  2. **Start and stop resources on a schedule**: shut down over weekends/off-hours (e.g., stop Saturday, start Monday) — generally for testing environments; only for production with cyclical usage.
  3. **Choose the right resource type, size, and reservation**: after metrics show real usage, downsize or change type; use ephemeral/spot/preemptible reservations where disruption tolerable. Testing should *simulate* production, not duplicate its cost (e.g., 3 small servers exercising the same topology instead of 72 CPUs).
  4. **Enable autoscaling**: automatically increase or decrease the number of resources in a group based on a metric; set min (often 0 for on-demand workloads), max (cap against runaway/crypto-mining scale-ups), target utilization (e.g., 75% CPU), and scaling schedules.
  5. **Set a resource expiration tag**: tag module adds an `expiration` date (e.g., now + 7 days) to every non-production resource; daily automation deletes expired resources; re-running the pipeline (or any change) renews the tag. Maintain an exemption list for long-term testing resources, enforced by a soft-mandatory policy test.
- **Cost optimization techniques** (Figure 12.11): build environments on demand (reproducibility), use multiple clouds by workload (composability), assess data transfer routes (favor private, co-located networking), and test in production (feature flags + blue-green) when a full replica costs too much.

## Key Concepts
- **Cost driver**: a factor or activity (resource type, size, count, data transfer) that moves your total cloud bill.
- **Cost estimation**: automated parsing of IaC plus provider pricing APIs to produce an expected cost, asserted against a budget in the pipeline.
- **Cloud waste**: unused or underutilized infrastructure resources — the first place to look after a surprising bill.
- **Autoscaling**: increasing or decreasing resource counts in a group based on a target metric (CPU, memory).
- **Ephemeral resource** (spot/preemptible): cheaper reservation the provider may reclaim at any time; only for disruption-tolerant workloads.
- **Resource expiration tag**: a tag holding an absolute deletion date, automatically refreshed by pipeline runs, enabling renewable ephemeral resources.
- **Elasticity**: the cloud's ability to scale up and down — some application architectures must be re-platformed to exploit it.
- **Soft mandatory enforcement**: policy mode where a reviewer can approve exceptions (bigger machine, exempt long-lived test resource) with justification.
- **Testing in production**: practices (feature flags, blue-green, canary) that let you validate changes against production data and systems without a costly full replica.
- **General-purpose resource types**: lower-cost defaults; test for them and require soft-mandatory approval for specialized (e.g., ML-optimized) types.

## Mental Models
- Think of the cloud bill like a cake recipe (ch 8's security analogy): **cost is an ingredient baked in before baking, not trimmed after the cake exists** — removing resources later risks breaking the system.
- Think of cost estimation as **a budget unit test**: it runs on every push and fails loudly when a change overspends, preventing production chargeback surprises.
- Use **expiration tags as renewable leases**: the pipeline run *is* the renewal — active resources keep living, forgotten ones die quietly.
- Treat the provider's **billing catalog API as the price source of truth** — hardcoded prices rot.

## Anti-patterns
- **Hardcoding prices or machine-type specs in tests**: provider offerings and prices change; querying the API keeps tests evolvable.
- **Letting cost estimation block production changes**: it should trigger reassessment, not act as a hard gate.
- **Deleting a "unused" resource without checking metrics and dependencies**: you may break a hidden consumer; stop it for 1–2 weeks first if uncertain.
- **Reboot schedules on fault-intolerant production applications**: scheduled shutdowns disrupt workloads that cannot survive restarts; generally limit to testing.
- **Automatic expiration tagging with post-creation automation as the *only* mechanism**: it introduces drift and confuses teammates whose resources silently vanish; build expiry into the tag module so renewals happen through the pipeline.
- **Unbounded autoscaling maxima**: a bug or bad actor can inflate you to 100 instances; always cap max replicas.
- **Cross-region/cross-cloud/internet-path testing traffic**: integration tests reaching another zone or a public IP incur data transfer charges; consolidate the test environment into one zone with internal DNS.
- **Estimating every cost driver**: model the resources that make up the bulk of the bill (usually compute), not everything.

## Code Examples
```python
@pytest.fixture
def servers(configuration):
   return resources(configuration, 'google_compute_instance')

def test_cpu_size_less_than_or_equal_to_limit(servers):
    CPU_LIMIT = 32
    non_compliant_servers = []
    for server in servers:
        type = compute.get_machine_type(
            PROJECT, server['zone'], server['machine_type'])
        if type.cpus > CPU_LIMIT:
            non_compliant_servers.append(server['name'])
    assert len(non_compliant_servers) == 0, \
        f'Servers found using over {CPU_LIMIT}' + \
        f' vCPUs: {non_compliant_servers}'
```
- **What it demonstrates**: a soft-mandatory policy test that parses every server's machine type, resolves vCPUs via the provider API, and fails the pipeline on oversized servers.

```python
HOURS_IN_MONTH = 730
NANO_UNITS = 10**-9

def calculate_monthly_compute(machine_type, region):
   service_name = ComputeService().name
   sku = ComputeSKU(machine_type.name, service_name)
   cpu_price, ram_price = sku.get_pricing(region)
   cpu_cost = machine_type.cpus * cpu_price * \
       HOURS_IN_MONTH if cpu_price else 0
   ram_cost = machine_type.ram * ram_price * \
       HOURS_IN_MONTH if ram_price else 0
   return (cpu_cost + ram_cost) * NANO_UNITS

def test_monthly_compute_budget_not_exceeded(servers):
    total = 0
    for key, value in servers.items():
        region, _ = key.split(',')
        total += calculate_monthly_compute(value['type'], region) * \
            value['num_servers']
        assert total < MONTHTLY_COMPUTE_BUDGET
```
- **What it demonstrates**: cost estimation — unit prices fetched live from the Cloud Billing Catalog API, monthly cost per machine type (730-hour month, nano-dollar conversion), and a pipeline budget assertion.

```python
EXPIRATION_DATE_FORMAT = '%Y-%m-%d'
EXPIRATION_NUMBER_OF_DAYS = 7

class DefaultTags():
   def __init__(self, environment, long_term=False):
       self.tags = {
           'customer': 'community',
           'automated': True,
           'cost_center': 123456,
           'environment': environment
       }
       if environment != 'prod' and not long_term:
           self._set_expiration()

   def _set_expiration(self):
       expiration_date = (
           datetime.datetime.now() +
           datetime.timedelta(days=EXPIRATION_NUMBER_OF_DAYS)
       ).strftime(EXPIRATION_DATE_FORMAT)
       self.tags['expiration'] = expiration_date
```
- **What it demonstrates**: the tag module (prototype pattern) attaching a renewable 7-day expiration to all non-production resources; a daily script deletes resources whose expiration date matches today.

## Reference Tables
Cloud bill breakdown by offering and environment (Table 12.1, worked example):

| Offering | Testing | Production | Subtotal |
|---|---|---|---|
| Compute (servers) | $400 | $3,600 | $4,000 |
| Database (Cloud SQL) | $250 | $2,250 | $2,500 |
| Messaging (Pub/Sub) | $100 | $900 | $1,000 |
| Object storage (Cloud Storage) | $100 | $900 | $1,000 |
| Data transfer (networking egress) | $100 | $900 | $1,000 |
| Other (CDN, support) | $50 | $450 | $500 |
| **Total** | **$1,000 (10%)** | **$9,000 (90%)** | **$10,000** |

Cost levers at a glance:

| Lever | Technique | Typical guardrail |
|---|---|---|
| Control drivers | vCPU/size policy tests | Soft mandatory, override with justification |
| Predict cost | Budget estimation test | Guides reassessment, never hard-blocks |
| Remove waste | Delete untagged/unused | Confirm metrics + dependencies first |
| Idle capacity | Start/stop schedules | Testing first; expiration time on schedule |
| Overprovisioning | Right-size type/size/reservation | Test topology, not production cost |
| Elastic capacity | Autoscaling (min/max/target) | Cap max replicas; blue-green rollout |
| Forgotten sandboxes | Expiration tag + daily deletion | Exemption list, renewable via pipeline |

## Worked Example
A community-conference platform racks up a $10,000/month bill for a three-hour event. Tags (from ch 8) break the bill down: compute is 40% of spend and production is 90%. The engineer layers fixes: policy tests cap servers at 32 vCPUs (soft mandatory); a budget test estimates monthly cost from the Billing Catalog API (later raised from $4,500 to $4,700 after a legitimate new testing server tripped it). Then cloud waste: two untagged n2d-standard-16 sandbox instances with zero metrics are deleted after team confirmation (−7%); weekend start/stop shutdowns via a `google_compute_resource_policy` save another $700; right-sizing the production database from 4 TB SSD to its actual 1 TB need cuts $1,350 (22.5%); autoscaling replaces fixed servers (min 0, max 3, 75% CPU target with weekday scaling schedules); an expiration tag module auto-deletes forgotten sandboxes and renews via pipeline runs. Result: the bill drops from ~$10,000 to ~$6,500 — a **35% reduction** — with every constraint encoded as a test in the delivery pipeline.

## Key Takeaways
1. Start with the bill, not the code: use tags to break cost down by offering and environment and compute percentages to find the cost drivers.
2. Encode cost constraints as policy tests in the delivery pipeline — soft mandatory enforcement lets humans approve justified exceptions.
3. Fetch prices and machine specs dynamically from provider APIs; anything hardcoded goes stale.
4. Estimate cost with a fixed 730-hour month formula and assert a monthly budget; reconcile estimates against the real bill and refine over time.
5. Attack waste in order: delete confirmed-unused resources, schedule shutdowns for off-hours, right-size types and sizes, then autoscale.
6. Make ephemeral testing resources renewable through the pipeline with expiration tags — the run itself is the renewal.
7. When a replica environment costs too much, favor private co-located networking, on-demand environments, multiple clouds by workload, and ultimately testing in production behind feature flags.

## Connects To
- **Ch 8 (tagging, policy enforcement, prototype pattern)**: cost tests reuse the policy-test pipeline and the default-tags module gains the expiration date.
- **Ch 6 (unit testing)**: budget and limit tests are unit tests over generated configuration.
- **Ch 9/10 (change and refactoring techniques)**: blue-green rollouts for autoscaling groups and on-demand environments; refactoring to consolidate cross-zone testing traffic.
- **Ch 5 (repository/module structure)**: multicloud composability relies on provider-separated modules.
- **Ch 11 (reconciling differences)**: testing in production trades costly environment replicas for a roll-forward plan.
- **FinOps / chargeback**: budget tests give finance and engineering a shared, code-tracked number.