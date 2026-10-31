# Chapter 9: Making changes

## Core Idea
Before changing production infrastructure, establish visibility (tests, monitoring, redundancy); then apply immutability — blue-green deployment with a canary ramp for stateless resources, and database migration plus incremental application cutover for stateful infrastructure — so a failure affects zero or a small percentage of requests.

## Frameworks Introduced
- **Pre-change checklist**: run before any infrastructure update —
  1. Can you preview each change and test the changes in an isolated environment?
  2. Does the system have monitoring and alerts configured to identify anomalies?
  3. Does the application track error responses with health checks, logging, observability, or metrics?
  4. Do the applications and their systems have any redundancy?
  - When to use: every significant change; build the checklist into delivery pipelines as quality gates (Ch 6/8 practices).
- **Active-passive configuration**: one system is the active environment for completing user requests, and the other is a backup (idle) environment.
  - When to use: improving reliability before risky changes; protecting against regional failure.
  - How: reproduce the active environment in a second region via IaC (copy configuration, change region/IP-range/name constants); on failure, fail over.
- **Failover**: using passive (or standby) resources to take over when the primary resources fail.
  - When to use: active environment breaks during a change; implement by flipping load-balancer weights (e.g., 100% to the passive backend).
- **Active-active configuration**: multiple systems are the active environments for completing user requests and replicating data between them.
  - When to use: long-term reliability goal for distributed systems; requires data-consistency setup, modular refactoring of IaC, global load balancing, and automation to remove a failing environment from serving.
- **Redundancy**: duplication of resources to improve the system's performance — if updated components fail, the system can use working resources with a previous configuration. (Includes the quick backup: duplicate a server so traffic diverts while you debug.)
- **Reliability**: measures how long a system performs correctly within a time period — the reason redundant configurations justify their cost.
- **Blue-green deployment**: a pattern that creates a new subset of infrastructure resources (*green*) with the changes you want to make; you gradually shift traffic from the old set (*blue*) to green and eventually remove blue.
  - When to use: reverting takes a long time; you are not confident you can revert after deployment; the resource has many high-level dependencies you can't easily identify; the change affects critical applications that cannot have downtime. Not for quickly revertable updates like IAM policies.
  - How (5 steps): (1) deploy green — copy blue's configuration, change only the differing attributes (e.g., routing mode GLOBAL, premium network tier); (2) deploy new high-level dependencies of the changed low-level resource onto green (cluster, servers, applications); (3) canary a small percentage of traffic to green; (4) ramp traffic while regression testing, keeping blue as passive fallback; (5) after confirming inactivity (with peer/CAB review for a major change), set green as default, delete blue from IaC, and remove dead files.
- **Canary deployment**: sends a small percentage of traffic to the updated resources in the system; if requests complete successfully, you increase the percentage over time.
  - When to use: before every significant infrastructure change ("canary in a coal mine" — the first indicator); any traffic-splitting mechanism works (e.g., one updated instance in a four-instance round-robin pool ≈ 25%).
- **Regression testing (window)**: checks whether changes to the system affect existing or new functionality — the observation period (a week or two) between traffic increments and after reaching 100%.
  - When to use: between every percentage increase and after full cutover; catches edge-case payloads that only real traffic or time exposes.
- **Stateful infrastructure migration workflow**: infrastructure resources that store and manage data (databases, queues, caches, stream-processing tools).
  - When to use: you cannot update the resource in place, or replacement would corrupt/lose data.
  - How: check if an in-place change is possible → if not, create a new empty green database → add an automated data-migration step (blue → green) to the delivery pipeline with idempotent migration → update applications incrementally: write to both databases → write only to green → read from green, each followed by regression testing → delete blue (compliance plan-tests will flag the deletion; use a manual override once blue is confirmed unused). Keep migration automation in the delivery pipeline, not the IaC, so migration steps can change and be debugged independently.
- **Compliance test for significant plan changes**: a pytest test on the Terraform plan JSON that fails if a database's plan actions include `delete` — prevents accidentally destroying critical data.

## Key Concepts
- **Observability**: the ability to infer a system's internal state from its outputs; without it you cannot quickly troubleshoot broken changes.
- **Blast radius management**: isolating new (green) resources from old (blue) so failure impact stays small; batching or in-place changes to shared resources maximizes it.
- **Singleton pattern config risk**: all resources in one repository sharing one infrastructure state (as in the sundew system) makes wide-reaching changes risky — motivates modularization and blue-green.
- **Reproducibility in change**: the IaC principle that lets you create a new environment (or blue/green copy) by changing a few attributes rather than rebuilding resource by resource.
- **Labels of convenience**: the colors don't matter — production/staging or v1/v2 work too, as long as old vs. new is unambiguous.
- **Traffic-weight load balancing**: define a list of versioned environments plus a default version; weight backend services (90/10, then 100/0) — the load balancer is the control surface for the entire rollout.
- **Permanent CIDR reservations**: for networking specifically, permanently reserve two IP address ranges (one blue, one green) so you can blue-green without hunting for open network space.
- **Idempotent data migration**: migration automation must produce the same database state each run without duplicating data.

## Mental Models
- Think of blue-green as "mutate the copy, not the original": never change a shared, hard-to-revert resource in place when you can duplicate it and flip traffic.
- Use the load balancer as the undo button: always default traffic to the environment you know works (blue), so a green failure is a weight change away from recovery.
- Think of canary percentages as sample sizing: 10% increments starting point — judge increments by daily request volume and the cost of failure, and insert a regression window between each increase.
- Use "cage the canary" for stateful changes: write to both databases first, so critical write functionality is proven before any read depends on green.

## Anti-patterns
- **Deleting a critical blue resource before the load balancer (or applications) stop referencing it**: dangling references break the system; test, then cut over default traffic, then delete.
- **Skipping the pre-change checklist**: the author pushed a change that broke an application and discovered it two weeks later because there were no alerts on the application.
- **Immediate full traffic cutover**: sending 100% to green without a canary turns one bad attribute into a full outage.
- **In-place mutation of stateful infrastructure**: changing a database's network can generate a plan that deletes the instance — data loss the compliance test exists to catch.
- **Leaving unused blue/blue.py files around**: deleted-environment code invites teammates to recreate orphaned resources; delete the files you no longer use.
- **Non-idempotent migration automation**: re-running the migration duplicates data and corrupts state.

## Code Examples
Creating a passive (or green) environment by parameterizing constants — reproducibility in action:

```python
TEAM = 'sundew'
ENVIRONMENT = 'production'
VERSION = 'passive'
REGION = 'us-west1'
IP_RANGE = '10.0.1.0/24'

zone = f'{REGION}-a'
network_name = f'{TEAM}-{ENVIRONMENT}-network-{VERSION}'
server_name = f'{TEAM}-{ENVIRONMENT}-server-{VERSION}'
cluster_name = f'{TEAM}-{ENVIRONMENT}-cluster-{VERSION}'

labels = {
    'team': TEAM,
    'environment': ENVIRONMENT,
    'automated': True
}
```
- **What it demonstrates**: duplicating an entire environment with a handful of changed attributes (version, region, IP range) instead of rebuilding it.

Green network with the actual change — global routing:

```python
def network(name=network_name, region=REGION, ip_range=IP_RANGE):
    return [
        {
            'google_compute_network': {
                VERSION: [{
                    'name': name,
                    'auto_create_subnetworks': False,
                    'routing_mode': 'GLOBAL'
                }]
            }
        },
        # ...subnetwork referencing google_compute_network.{VERSION}.name
    ]
```
- **What it demonstrates**: green differs from blue only in the attributes you are changing; everything else is copied verbatim. (Servers on green add `'network_tier': 'PREMIUM'`.)

Traffic-weighted load balancer services list (canary ramp, in shared.py separate from blue/green):

```python
services_list = [
    {
        'version': 'blue',
        'zone': blue.zone,
        'name': f'{shared_name}-blue',
        'weight': 90
    },
    {
        'version': 'green',
        'zone': green.zone,
        'name': f'{shared_name}-green',
        'weight': 10
    }
]
```
- **What it demonstrates**: separating the load balancer from environment definitions and controlling rollout by weights (90/10 → 100% green → blue deleted from the list, `default_version = 'green'`).

Compliance test failing on plan deletion of a database:

```python
def test_if_plan_deletes_database(database):
    assert database['change']['actions'][0] != 'delete'
```
- **What it demonstrates**: inspecting the Terraform plan JSON so the pipeline halts before a stateful resource is destroyed; later updated to fail only when a *green* database is deleted (manual override allows removing unused blue).

## Reference Tables
Decision guide synthesized from the chapter's criteria:

| Situation | Use |
|---|---|
| Resource reverts slowly / revert confidence low / many unknown high-level dependencies / zero-downtime critical app | Blue-green deployment (stateless) or blue-green + data migration (stateful) |
| Resource reverts quickly in place (e.g., IAM policies) | Direct in-place update, no blue-green |
| Want protection against regional failure during changes | Active-passive configuration + failover |
| Long-term goal, distributed system with data replication | Active-active configuration |
| Significant change going out | Canary ramp (start ~10%), regression window between increments |
| Cannot update stateful resource in place | New green resource → pipeline migration step → write-both → write-green → read-green → delete blue |

Blue-green progression (sundew worked example): deploy green network (GLOBAL routing) → deploy cluster + premium-tier servers + apps on green → canary 10% → +10% daily with regression testing → 100% green for one to two weeks → peer/CAB review of inactivity → default service green, blue removed → delete blue.py.

## Worked Example
The Cape sundew system: everything lives in one repository in a single region — a regional load balancer, regional-routing network, cluster, three servers. An early in-place change accidentally deletes the `blue` server tag and no test catches it; the alert arrives because the watering application breaks. Resetting: the pre-change checklist is completed (test for the tag, monitoring, duplicate backup servers), then a passive environment is built in us-west1 by copying `blue.py` to `passive.py` and changing `VERSION`, `REGION`, and `IP_RANGE`. The actual goal — converting regional to global routing with premium-tier servers — is then done blue-green: `green.py` copies blue with `routing_mode: 'GLOBAL'`, new cluster and servers with `network_tier: 'PREMIUM'` deploy onto green, tests pass, the shared load balancer sends 10% to green, traffic ramps 10% per day for about two weeks with regression windows, green runs at 100% for a week or two, default flips to green, and blue is deleted from IaC and from the codebase. Finally the database: the plan test catches an implicit `delete` when the network ID changes, so the database gets a green copy, a pipeline migration stage copies data, applications are updated write-both → write-green → read-green with regression between each, and blue is removed under a manual override of the deletion test.

## Key Takeaways
1. Never start a significant infrastructure change without the pre-change checklist: preview/testing, monitoring and alerts, application health checks, and redundancy.
2. Use active-passive (or in-place duplicates) as your safety net — IaC reproducibility makes a second region a constants change, not a rebuild.
3. Choose blue-green deployment when reverting is slow or uncertain, dependencies are hard to map, or downtime is unacceptable; skip it for quickly revertable resources like IAM.
4. Always deploy the changed low-level resource *and* new high-level resources that depend on it — the green network alone serves no one.
5. Separate the load balancer configuration from environment definitions and default to the known-good environment so rollback is a weight change.
6. Ramp canary traffic gradually (start ~10%), insert regression-testing windows between increments, and hold at 100% for one to two weeks before decommissioning blue.
7. Protect stateful infrastructure with a plan-level compliance test for destructive actions, an idempotent migration step in the pipeline (not the IaC), and an incremental application cutover (write-both → write-green → read-green).
8. Reserve permanent blue/green IP ranges for network resources, and delete abandoned environment files to prevent orphaned future resources.

## Connects To
- **Ch 2**: the immutability and reproducibility principles that blue-green operationalizes; reconciliation after manual changes.
- **Ch 3**: the singleton pattern as the anti-pattern making wide-reaching changes risky; modules for passing regions as inputs.
- **Ch 6 / Ch 8**: the automated tests, compliance tests, and delivery pipeline stages that serve as the quality gates of the pre-change checklist and catch destructive plans.
- **Ch 7**: blue-green deletion counts as a major change needing peer review; canary is the change-management answer to big-batch risk.
- **Ch 10**: refactoring and feature toggling complement blue-green for changes that must happen in place.
- **Ch 11**: roll-forward and fix failures when the revert path is exhausted.
- **Database Reliability Engineering (Campbell & Majors)**: deeper patterns for migrating and managing stateful infrastructure with minimal downtime.
- **Blue-green / canary software deployment (martin Fowler-style practices)**: the same traffic-ramping patterns applied to infrastructure resources.