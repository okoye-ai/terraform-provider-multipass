# Chapter 4: Patterns for infrastructure dependencies

## Core Idea
Decouple high-level resources from the low-level ones they depend on using dependency injection (inversion of control + dependency inversion), then choose among the facade, adapter, and mediator patterns based on how many modules depend on the low-level one — so changes to low-level infrastructure stop breaking everything above it.

## Frameworks Introduced
- **Dependency injection**: combines inversion of control and dependency inversion; high-level modules or resources call for attributes from low-level ones through an abstraction.
  - When to use: always, as the baseline principle whenever a high-level resource (server, queue, database) references a low-level one (network, subnet).
  - How: (1) high-level module calls the low-level module for information; (2) low-level module outputs resource metadata; (3) high-level module parses the metadata for required attributes; (4) it uses parsed attributes to build its resources.
- **Inversion of control**: the principle by which the high-level resource calls the low-level one for attributes or references.
  - When to use: when the high-level resource needs to know a low-level attribute (subnet name, CIDR range) before changing.
  - How: the server parses the network module's `terraform.tfstate` outputs rather than the network pushing values to the server. Isolates changes to high-level modules.
- **Dependency inversion**: the principle of expressing dependencies between high-level and low-level modules or resources through abstractions.
  - When to use: to protect high-level resources from attribute updates or renaming on low-level ones (e.g., network name changes to network ID).
  - How: choose one of three abstraction types — attribute interpolation (within modules), module outputs (between modules), infrastructure state (between modules, via tool state, a configuration manager/key-value store, or the infrastructure provider's API). Isolates changes to low-level modules.
- **Facade pattern**: outputs attributes from resources in a module for dependency injection — "a mirror, reflecting the attributes to other modules."
  - When to use: one low-level module serving a few high-level modules (one-to-one or few-to-one).
  - How: an `outputs()` method returns a facade object exposing minimum fields (start with one or two; prune unused fields every few weeks). Low implementation/troubleshooting cost, but does not scale — renaming an output field forces changing every consuming module.
- **Adapter pattern**: transforms and outputs metadata from the low-level resource or module so any high-level resource or module can use it — "a travel plug."
  - When to use: many high-level dependencies on one low-level module, cross-provider modules (e.g., GCP roles vs. generic read/write/admin; AWS customer gateway vs. GCP Cloud VPN gateway), or providers with poorly defined resource parameters.
  - How: maintain a mapping dictionary of generic terms to provider-specific terms and output the transformed attributes. The mapping is a contract between modules; breaking it (e.g., mapping read → `roles/reader` instead of `roles/viewer`) fails the IaC.
- **Mediator pattern**: organizes dependencies among infrastructure resources and includes logic to create or delete objects based on their dependencies — "air-traffic control."
  - When to use: many levels of dependencies among multiple system components; or between tools (e.g., check Kubernetes cluster health before a second tool deploys services).
  - How: recursive if/else logic that builds low-level dependencies in order (network → server → firewall rule). Must be idempotent and fully tested. Prefer a tool's built-in mediator: most IaC tools (Kubernetes orchestration, Ansible step composition, Terraform's dependency graph) already act as mediators using graph theory — resources are nodes, links pass attributes.

## Key Concepts
- **High-level resource**: a resource or module that depends on another resource or module (server, queue, database, firewall rule).
- **Low-level resource**: a resource with high-level resources depending on it (network, subnet, storage bucket).
- **Circular dependency**: a chicken-or-egg problem where two resources depend on each other's attributes, so you cannot change one without blocking the other — kills predictability and evolvability.
- **Tool state**: a representation of infrastructure state stored by an IaC tool (e.g., `terraform.tfstate`); it tracks configuration of the resources the tool manages.
- **Configuration manager**: a standard key-value interface for passing metadata between tools, an abstraction layer over tool state when multiple tools/providers are in play.
- **Infrastructure state / infrastructure API**: provider API metadata as an abstraction — rarely changes, accounts for out-of-band changes, but needs network access and only resolves values at run time.
- **Predictability and isolation**: the two factors a successful infrastructure change depends on; unidirectional dependencies make changes predictable, patterns isolate changes within modules.
- **Blast radius**: the scope of failures caused by an updated low-level resource; dependency injection minimizes it.

## Mental Models
- Use dependency injection whenever a high-level resource references a low-level one: the high-level resource calls, the low-level resource serves metadata through an abstraction.
- Think of the facade as a mirror (reflect attributes, no logic), an adapter as a travel plug (translate between interfaces), and a mediator as air-traffic control (decide who goes first).
- Think of an abstraction as a contract: if both high- and low-level resources agree on the attributes they need, they evolve independently.
- Use the tool's built-in mediator first; write your own only when a pattern is missing between tools.

## Anti-patterns
- **Circular dependencies**: you don't know which resource to update first; changes to one block connectivity or updates to the other.
- **Hardcoded low-level attributes** (e.g., `'private_network': 'default'`): couples the module to a fixed network; pass an output object or variable instead.
- **Facade with too many fields**: forgetting which outputs exist and their names makes maintenance hard; prune unused fields regularly.
- **Growing a facade past its scale limit**: renaming one output across hundreds of dependent modules does not scale — move to an adapter or mediator.
- **Breaking the adapter contract**: mapping a generic role to a nonexistent provider role fails downstream IaC and is hard to troubleshoot because the adapter obfuscates which module supplied the bad value.
- **Hand-rolling a mediator you don't test**: untested mediation logic can accidentally break resources it was meant to order.

## Code Examples
```python
# Listing 4.2 — inversion of control: server parses network module's tool state
import json

class NetworkModuleOutput:
   def __init__(self):
       with open('network/terraform.tfstate', 'r') as network_state:
           network_attributes = json.load(network_state)
       self.name = network_attributes['outputs']['name']['value']

class ServerFactoryModule:
   def __init__(self, name, zone='us-central1-a'):
       self._name = name
       self._network = NetworkModuleOutput()
       self._zone = zone
       self.resources = self._build()

   def _build(self):
       return {
           'resource': [{
               'google_compute_instance': [{
                   self._name: [{
                       'boot_disk': [{'initialize_params': [{'image': 'ubuntu-1804-lts'}]}],
                       'machine_type': 'f1-micro',
                       'name': self._name,
                       'zone': self._zone,
                       'network_interface': [{'subnetwork': self._network.name}]
                   }]
               }]
           }]
       }
```
- **What it demonstrates**: the high-level server module calls the low-level network's state file for the subnet name instead of the network pushing values to the server.

```python
# Listing 4.8 (trimmed) — adapter pattern: generic roles → GCP roles
class GCPIdentityAdapter:
   EMAIL_DOMAIN = 'example.com'

   def __init__(self, metadata):
       gcp_roles = {
           'read': 'roles/viewer',
           'write': 'roles/editor',
           'admin': 'roles/owner'
       }
       self.gcp_users = []
       for permission, users in metadata.items():
           for user in users:
               self.gcp_users.append(
                   (user, self._get_gcp_identity(user), gcp_roles.get(permission)))

   def _get_gcp_identity(self, user):
       if 'team' in user:
           return f'group:{user}@{self.EMAIL_DOMAIN}'
       elif 'automation' in user:
           return f'serviceAccount:{user}@{self.EMAIL_DOMAIN}'
       else:
           return f'user:{user}@{self.EMAIL_DOMAIN}'
```
- **What it demonstrates**: an adapter translates generic permission language (read/write/admin) and identity types into provider-specific terms (roles/viewer, serviceAccount:...) so the same metadata works across clouds.

```python
# Listing 4.9 (trimmed) — mediator pattern: order network → server → firewall
class Mediator:
   def __init__(self, resource, **attributes):
       self.resources = self._create(resource, **attributes)

   def _create(self, resource, **attributes):
       if isinstance(resource, FirewallFactoryModule):
           server = ServerFactoryModule(resource._name)
           resources = self._create(server)
           firewall = FirewallFactoryModule(
               resource._name, depends_on=resources[1].outputs())
           resources.append(firewall)
       elif isinstance(resource, ServerFactoryModule):
           network = NetworkFactoryModule(resource._name)
           resources = self._create(network)
           server = ServerFactoryModule(
               resource._name, depends_on=network.outputs())
           resources.append(server)
       else:
           resources = [resource]
       return resources
```
- **What it demonstrates**: the mediator recursively builds low-level dependencies first, creating the network before the server and the server before the firewall rule.

## Reference Tables
Pattern trade-offs (from figure 4.14's positioning):

| Pattern | Implementation effort | Troubleshooting effort | Ability to scale with more resources | Isolation for changes |
|---|---|---|---|---|
| Facade | Low | Low | Poor | Poor |
| Adapter | High | High | Good | Good |
| Mediator (tool-built) | Low (tool provides) | Medium (must know tool behavior) | Good | Partial |

Choosing a pattern by dependency shape (figures 4.13/summary):

| Situation | Pattern |
|---|---|
| One low-level module → a few high-level modules | Facade |
| Many high-level dependencies on one low-level module, or cross-provider modules | Adapter |
| Many dependencies among modules / across multiple tools | Mediator (prefer tool built-in) |
| One module referencing another module's attribute directly | Attribute interpolation (intra-module only) |

## Worked Example
The chapter's running example is the server-on-a-network dependency. Step by step:
1. **Naive**: server hardcodes the subnet name. Changing the network name to an ID breaks the server on the next deploy.
2. **Inversion of control**: the server module opens `network/terraform.tfstate` and parses `outputs.name.value`. The network evolves (outputs the CIDR too, for a queue) without rewriting server code — but renaming the output still breaks the server.
3. **Dependency injection**: the server calls the GCP API via Apache Libcloud (`driver.ex_get_subnetwork`), parses the returned network object for name and CIDR, and computes the fifth IP in the range (`ipaddress.IPv4Network(ip_range)` → `ip[-2]`). The abstraction is the API, not the raw output.
4. **Change propagates safely**: you shrink the network's range to `10.0.0.0/24`; you deploy the network first, then run the server IaC, which reads the new range from the API and reallocates the IP. Each module changes in isolation.

## Key Takeaways
1. Enforce unidirectional dependencies (high-level → low-level); a successful change depends on predictability and isolation.
2. Apply dependency injection as the default: high-level calls low-level through an abstraction, never the reverse.
3. Pick the abstraction by scope: attribute interpolation inside a module, module outputs between modules, infrastructure state or API across tools.
4. Start with a facade using the minimum number of output fields; prune what's unused.
5. Reach for an adapter when dependencies multiply or cross providers, accepting higher implementation and troubleshooting cost.
6. Don't build your own mediator unless no tool provides one — most IaC tools resolve dependency order via graph theory already.
7. Treat every pattern's interface as a contract; broken contracts (bad mappings, renamed outputs) are the root cause of downstream IaC failures.

## Connects To
- **Ch 5 (Structuring and sharing modules)**: module versioning and release practices alleviate adapter troubleshooting and make facade outputs stable contracts.
- **Ch 6 (Testing)**: contract testing can enforce required module outputs; testing mediators prevents accidental breakage.
- **Ch 11 (Reverting failed changes)**: the facade's traceability eases debugging and reverting.
- **Structural design patterns / SOLID dependency inversion principle**: the chapter applies GoF structural patterns (facade, adapter, mediator) and the software dependency-inversion principle directly to infrastructure.
- **Graph theory**: tool-built mediators map dependencies as nodes and edges.