# Chapter 10: Refactoring

## Core Idea
Refactoring IaC means restructuring configuration or code *without impacting existing infrastructure resources* — achieved by preserving idempotency: copy to a separate state, import live resources, verify a clean dry run, then remove the resources from the monolith.

## Frameworks Introduced
- **Rolling update**: a practice of changing a group of similar resources one by one and testing each before implementing the change to the next one.
  - When to use: refactoring a large set of similar resources (servers, nodes) to a new module or version.
  - How: cordon the old resource (stop it serving new requests) → run workloads on the new resource → deprecate the old server (e.g., remove from load balancer) → repeat per resource. Borrowed from workload orchestrators like Kubernetes.
- **Feature flags (feature toggles)**: enable or disable infrastructure resources, dependencies, or attributes using a Boolean.
  - When to use: staging a module swap, avoiding change conflicts with teammates, rapidly disabling a change on failure, staging a group of changes behind one variable.
  - How: (1) define the flag in a separate file/config, default `False`; (2) add a conditional in IaC referencing the flag; (3) test changes; (4) set the flag `True` to deploy; (5) refactor the conditional away; (6) **remove the flag** — leftover flags clutter IaC.
- **Refactoring an IaC monolith workflow** (Figure 10.11): break down a monolith in dependency order.
  1. Extract **high-level resources with no dependencies and nothing depending on them** first (e.g., IAM roles & service accounts).
  2. Extract **higher-level resources that depend on another resource** (e.g., applications on a container orchestrator), refactoring them to use **dependency injection**.
  3. Extract **lower-level resources that depend on another resource** (e.g., orchestrator on a network), again with dependency injection.
  4. Extract **low-level resources with no dependencies** (e.g., network) last.
  - Each cycle: copy config → import live resources into the new state → redeploy and confirm zero changes → remove the resource from the monolith's state and configuration.

## Key Concepts
- **Refactoring IaC**: restructuring configuration or code without impacting existing infrastructure resources.
- **Blast radius**: the scope of system impact if a change fails; minimized via rolling updates, feature flags, and one-resource-at-a-time extraction.
- **Technical debt**: metaphor for the cost of code or approach that makes the system hard to change or extend; in IaC it returns as downtime or security breaches, so assess the impact of *not* fixing it to justify effort.
- **Monolithic architecture for IaC**: defining all infrastructure resources in a single configuration and the same state — distinct from a monorepository, which can hold separate subdirectory configurations.
- **Feature flag**: Boolean variable enabling/disabling resources, dependencies, or attributes; defaults to `False` to preserve the original infrastructure state.
- **Idempotency**: rerunning IaC produces no change; the key safety check during any refactor ("Apply complete! 0 added, 0 changed, 0 destroyed").
- **State import**: attaching existing live resources to a new IaC tool state (e.g., `terraform import`) so configuration can move without recreating resources.
- **State removal**: detaching resources from a tool state (`terraform state rm`) to hand ownership to a new configuration — the monolith stops being the source of truth without deleting anything.
- **Dependency injection**: a high-level module calls an abstraction layer (the infrastructure provider's API is the most straightforward) to obtain low-level resource identifiers instead of referencing the monolith directly.
- **Drift**: differences between configuration and active resource state, often from manual (break-glass) changes; must be fixed before continuing a refactor.

## Mental Models
- Use **dependency order as a refactoring order**: start with resources nothing depends on, end with resources nothing depends *on*.
- Think of a monolith refactor as **handing over ownership**: import links the new state to reality; state removal from the monolith signals the new configuration is the source of truth — nobody deletes anything.
- Think of the infrastructure provider API as **the cheapest abstraction layer** for dependency injection during a split — no need to modify the monolith to output attributes.
- Treat the dry run as **the refactor's safety net**: any diff between code and state is a bug in your refactor, not a change to ship.

## Anti-patterns
- **Deleting and recreating resources to move them** (relying on immutability during a split): some resources cannot be duplicated (e.g., GCP disallows duplicate IAM policies) and deletion locks teams out of the project — use import instead.
- **Managing one resource with two sets of IaC**: conflicting definitions affect dependencies; always remove the resource from the monolith's state and configuration after extraction.
- **Leaving feature flags in the code after the change completes**: complicates logic and confuses the next reader.
- **Defaulting a feature flag to True**: you lose the guarantee that applying IaC preserves the original state.
- **Trust-ing hardcoded identifiers when importing**: dynamically retrieve identifiers from the provider API (using tags/naming conventions to search results) because someone may have changed the resource.
- **Running Python/apply before importing state**: attempting to create already-existing resources fails (409 alreadyExists) and tempts destructive fixes.
- **Starting the monolith breakdown with low-level resources**: every dependent resource still references them; start with independent high-level resources.

## Code Examples
```python
import flags
def _generate_servers(version):
   instances = [
       f'${{google_compute_instance.{version}_0.id}}',
       f'${{google_compute_instance.{version}_1.id}}',
       f'${{google_compute_instance.{version}_2.id}}'
   ]
   if flags.ENABLE_SERVER_MODULE:
       instances = [
           f'${{google_compute_instance.module_{version}_0.id}}',
           f'${{google_compute_instance.module_{version}_1.id}}',
           f'${{google_compute_instance.module_{version}_2.id}}',
       ]
   return instances
```
- **What it demonstrates**: a feature flag gating which servers attach to the load balancer; flag defaulted `False` preserves the original state (idempotency), and `True` swaps in module-built servers.

```python
def import_service_account(project_id, user_id, user_email):
   email = user_email.replace('serviceAccount:', '')
   command = ['terraform', 'import', '-no-color',
              f'{iam.TERRAFORM_GCP_SERVICE_ACCOUNT_TYPE}.{user_id}',
              f'projects/{project_id}/serviceAccounts/{email}']
   return _terraform(command)
```
- **What it demonstrates**: automating batch migration of live resources into a separated state, using resource-type constants exported from the new module and identifiers retrieved dynamically from the provider API.

```python
def _get_network_from_gcp():
   service = googleapiclient.discovery.build('compute', 'v1')
   result = service.subnetworks().list(
       project=PROJECT, region=REGION,
       filter=f'name:"{TEAM}-{ENVIRONMENT}-*"').execute()
   subnetworks = result['items'] if 'items' in result else None
   if len(subnetworks) != 1:
       print("Network not found"); exit(1)
   return subnetworks[0]['network'].split('/')[-1], subnetworks[0]['name']
```
- **What it demonstrates**: dependency injection during a split — the extracted cluster module resolves network/subnet names via the GCP API instead of referencing the monolith.

```hcl
variable "enable_server_module" {
  type        = bool
  default     = false
  description = "Choose true to build servers with a module."
}
module "server" {
  count = var.enable_server_module ? 1 : 0
  ## omitted for clarity
}
```
- **What it demonstrates**: feature-flag equivalents in DSLs — Terraform's `count` ternary; CloudFormation uses a `Condition` tied to a parameter.

## Reference Tables
| Refactor target | Order | Dependency handling |
|---|---|---|
| High-level, no dependencies (IAM roles/service accounts) | First | None needed |
| Higher-level with dependencies (apps on orchestrator) | Next | Dependency injection (provider API for orchestrator name) |
| Lower-level with dependencies (orchestrator on network) | Next | Dependency injection (provider API for network/subnet) |
| Low-level, no dependents (network) | Last | Direct re-creation/association |

## Worked Example
The sundew team's monolith holds hundreds of resources; changes take days and conflict, and the configuration ignores the security-approved server module. The refactor proceeds in two tracks:
1. **Servers to a secure module** — a rolling update builds each server from the module, deploys the app, validates, and retires the old server one at a time. A feature flag `ENABLE_SERVER_MODULE` (in `flags.py`, default `False`) gates which server IDs reach the load balancer, so applying IaC leaves production untouched until the team finishes the load-balancer change; flipping it to `True` attaches module servers, then the flag is deleted from the code.
2. **Splitting the monolith** — first the IAM service accounts and roles (high-level, nothing depends on them): `mkdir sundew_production_iam`, copy `iam.py` plus a new `main.py`, run an `import.py` that queries the GCP project's IAM policy and runs `terraform import` per service account/role assignment, confirm `terraform plan` reports "No changes," then run `remove.py` (`terraform state rm` per resource), strip IAM from the monolith's `main.py`, and reapply — still "No changes." Next the container orchestrator (has dependencies): copy cluster config, add `get_network()` calling the GCP API for subnet/network names, import, deploy, verify clean dry run, and remove from the monolith. Net result: separate folders, each with its own state, zero disruption to GCP.

## Key Takeaways
1. Never let a refactor change active infrastructure: prove it with a no-change dry run before and after every extraction cycle.
2. Refactor high-to-low in the dependency graph: extract independent high-level resources first, and finish with low-level ones.
3. When a resource cannot be recreated, migrate it: import into a new state, then `state rm` it from the monolith to transfer source-of-truth ownership.
4. When separated code needs a dependency's identifier, inject it via the infrastructure provider API rather than importing from the monolith.
5. Use feature flags to stage module swaps behind one Boolean, defaulting to `False`; remove them once the change is permanent.
6. Rolling updates let you validate server refactors one machine at a time so failure stays isolated to a single server.

## Connects To
- **Ch 3/4 (prototype & adapter patterns, dependency injection)**: starting early with modularization avoids inheriting a monolith; dependency injection is reused here for split resources.
- **Ch 5 (repository structure)**: distinguishes monolithic *architecture* from a monorepository — subdirectories allow both.
- **Ch 2 (idempotency, IaC as source of truth)**: refactoring is an extended exercise in preserving both.
- **Import / `terraform state rm` / `terraform import`**: external Terraform commands underpinning migration patterns.
- **Ch 11**: when refactoring failures appear, use the roll-forward and troubleshooting techniques covered there.
- **Kubernetes rolling updates**: the borrowed metaphor for cordon → drain → shift traffic.