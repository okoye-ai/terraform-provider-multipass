# Chapter 3: Patterns for infrastructure modules

## Core Idea
Group infrastructure resources sharing a function or business domain into modules, and choose the module's pattern — Singleton, Composite, Factory, Prototype, or Builder — by asking how the resource is used, reused, updated, and composed; favor Factory and Prototype for most modules.

## Frameworks Introduced
- **Singleton pattern**: "declares a set of resources as singular instances in a system. It deploys all the resources with a single command."
  - When to use: resources that require only a single instance and rarely change — provider accounts/projects, domain registrations, root SSL certificates, static low-use environments (e.g., a GCP project named `databases`).
  - How: one file/directory with static configuration and inline parameters. Pitfall: it becomes a junk drawer — fine for a few resources, does not scale or compose.
- **Composite pattern**: "treats an infrastructure module as a single instance and allows you to assemble, group, and rank modules in a system" (structural pattern; like a company org chart).
  - When to use: resources with a hierarchy that must deploy as one unit — network + subnetwork bundled so a teammate who "doesn't know much about networking" gets both.
  - How: one module builds each resource and references the other (subnet references `${google_compute_network.my-network.name}`); tools implement this as Terraform modules, CloudFormation nested stacks/StackSets, Ansible top-level playbooks importing tasks. The chapter's final example composites ALL patterns in one system.
- **Factory pattern**: "takes a set of input variables and creates a set of infrastructure resources based on input variables and default constants."
  - When to use: commonly built resources stamped out with minor differences — networks, subnetworks, server clusters, managed databases, queues, caches.
  - How: minimize inputs (two inputs, everything else defaulted); add transformations (e.g., generate subnet names by dash-delimiting the IP address, or calculate `/18` subnet ranges from a `/16`) only sparingly — "the more complex the logic for your transformation, the more you need tests."
- **Prototype pattern**: "takes a set of input variables to build a set of static defaults for consumption by other modules. They usually do not directly create infrastructure resources but export configuration values."
  - When to use: consistent metadata copied to every resource (standard tags: customer, automated, cost_center, business_unit), regions/AZs/account identifiers, templated startup scripts — think of it as a dictionary you reference for words and definitions.
  - How: a module returning a static object/dict; merge custom per-resource tags over the standard set; also use it for static configurations with many global defaults or complex transformations.
- **Builder pattern**: "assembles a set of infrastructure resources that you can enable or disable to achieve your desired configuration" (like choosing blueprint 1 and asking the builder to add an extra room by removing the garage).
  - When to use: modules creating multiple selectable resources — Kubernetes/container orchestrator configurations, cluster-architecture platforms, metrics dashboards, internal-vs-external load balancer choices.
  - How: builder methods decide *which* resources to create (`add_external_load_balancer()`, `add_google_firewall_rule()`), composed of factory modules; factory modules only configure resource *attributes*. Builder modules wrap generic interfaces around provider resources (`add_external_load_balancer` describes intent, not a GCP forwarding rule). They are complex and high-risk to misconfigure — test them (ch 6).
- **Factory modules with CRUD functions** (for legacy/scripted infrastructure): when no IaC tool support exists (e.g., direct GCP API access), separate each resource into a factory module exposing create/read/update/delete; even builder modules then use compositions of these functions. Test each function for idempotency.

## Key Concepts
- **Design pattern**: "a repeatable solution to a common problem in software" — here adapted from Gamma et al. to IaC, using only creational and structural patterns because IaC's immutability makes mutability-based patterns inapplicable.
- **Module**: "organizes infrastructure resources by function or business domain. Other tools or resources may refer to them as infrastructure stacks or sets."
- **Junk drawer (anti-pattern metaphor)**: a singleton that accumulates every resource you don't know where else to put; searching it and updating it cost more over time.
- **Opinionated defaults**: factory input minimization — offer "just enough flexibility to make changes" while balancing reproducibility against evolvability.
- **Module decision tree** (figure 3.11): new resource → serves a different purpose/business domain/function? → will you or someone else reuse it or expect frequent updates? → does it involve *selecting* multiple infrastructure resources → Builder; otherwise → Factory; if not reusable → Singleton; if not a different domain → append to existing configuration or create a Prototype module.
- **Modularization questions**: Is the resource shared? What business domain does it serve? Which environment uses it? Which team manages it? Does it use a different tool? How do you change it without affecting something else in the module?

## Mental Models
- Use Factory when the inputs describe *what the resource looks like*; use Builder when the inputs describe *which resources you want* (factory configures attributes; builder selects resource sets).
- Think of a Prototype as a dictionary that never creates resources — it only returns a copy of static defaults others append.
- Think of modules as building blocks that limit blast radius: fewer resources per module means faster provisioning, smaller failure radius, and easier deploy-test-debug before applying to a larger system.
- Modules serve three levels: you (scalability/resiliency), your team (self-service — pass variables instead of find-and-replace), and your organization (standardized security practices auditable by the security team).

## Anti-patterns
- **The junk-drawer singleton**: "I treated infrastructure configuration like a junk drawer — storage for random items that don't have a place otherwise... Eventually, the singleton pattern became messy." Reproducing production means copy-pasting the whole file, which does not scale.
- **Copy-pasting N similar resources**: needing three subnets and writing the subnet block three times; the factory exists to generate them from a loop.
- **Over-transforming factory modules**: dynamic generation logic adds complexity that demands tests; minimize transformations where possible.
- **Hardcoding global defaults into a factory**: OS, machine type, and tags multiplied until "they overrun the module" — move them to a prototype.
- **Building a builder for a single-instance, rarely-changed resource**: the pattern choice should match complexity; the GCP project needs only a singleton.

## Code Examples
Prototype pattern — standard tags consumed by a server factory (listing 3.4, essentials):

```python
import json

class StandardTags():
    def __init__(self):
        self.resource = {
            'customer': 'my-company',
            'automated': True,
            'cost_center': 123456,
            'business_unit': 'ecommerce'
        }

class ServerFactory:
    def __init__(self, name, network, zone='us-central1-a', tags={}):
        self.name = name
        self.network = network
        self.zone = zone
        self.tags = tags
        self.resource = self._build()

    def _build(self):
        return {
              'resource': [
                    {
                        'google_compute_instance': [
                              {
                                  self.name: [
                                      {
                                          'machine_type': 'f1-micro',
                                          'name': self.name,
                                          'network_interface': [
                                              {'network': self.network}
                                          ],
                                          'zone': self.zone,
                                          'labels': self.tags
                                      }
                                  ]
                              }
                        ]
                    }
              ]
        }

if __name__ == "__main__":
    config = ServerFactory(
        name='database-server', network='default',
        tags=StandardTags().resource)
    with open('main.tf.json', 'w') as outfile:
        json.dump(config.resource, outfile, sort_keys=True, indent=4)
```
- **What it demonstrates**: the prototype exports a copied set of static defaults (no resources); the factory merges them into every server's labels — updating tags happens in one place.

Builder pattern composed of factories (listing 3.8, essentials):

```python
import json
from server import DatabaseServerFactory
from loadbalancer import LoadBalancerFactory
from firewall import FirewallFactory

class DatabaseModule:
    def __init__(self, name):
        self._resources = []
        self._name = name
        self._resources = DatabaseServerFactory(self._name).resources

    def add_internal_load_balancer(self):
        self._resources.extend(
            LoadBalancerFactory(self._name, external=False).resources)

    def add_external_load_balancer(self):
        self._resources.extend(
            LoadBalancerFactory(self._name, external=True).resources)

    def add_google_firewall_rule(self):
        self._resources.extend(
            FirewallFactory(self._name).resources)

    def build(self):
        return {'resource': self._resources}

if __name__ == "__main__":
   database_module = DatabaseModule('development-database')
   database_module.add_external_load_balancer()
   database_module.add_google_firewall_rule()
   with open('main.tf.json', 'w') as outfile:
       json.dump(database_module.build(), outfile,
                 sort_keys=True, indent=4)
```
- **What it demonstrates**: builder modules select which resources to build via add_* methods wrapping factory modules with opinionated defaults (internal vs. external via `load_balancing_scheme: EXTERNAL|INTERNAL`); DSL equivalents are Terraform `count`, CloudFormation conditionals, Bicep deploy conditions,Ansible conditional imports, or templating (Helm) when the DSL has no conditionals.

## Reference Tables
Module pattern decision tree (figure 3.11), as a table:

| Situation | Pattern to use |
|---|---|
| Not a different purpose/domain than existing resources | Append to existing configuration, or create a Prototype module |
| Different purpose/domain, but never reused or rarely updated | Singleton module |
| Different purpose/domain, reused, no resource selection needed | Factory module |
| Different purpose/domain, reused, must select multiple resources | Builder module |

Pattern roles in the chapter's database system:

| Resource | Pattern | Why |
|---|---|---|
| Google project | Singleton | Single instance, rarely changes, unique identifier |
| Network + subnetwork | Composite | Hierarchy, deployed as one unit |
| Network, load balancer, database cluster | Factory | Same resources with minor attribute differences |
| Tags | Prototype | Consistent metadata copied to all resources |
| Database (LB + firewall + server group) | Builder | Composed of factories; enable/disable choices |

## Worked Example
Building the database system pattern by pattern: start with a singleton for the GCP `databases` project (unique project-id derived from `'{name}-{USER}'`). Realize the network needs a subnet, so composite them into a Network module (network + subnet sharing a standardized name `my-network-subnet`). Need three subnets across regions, so write a SubnetFactory whose `_generate_subnet_name()` dash-delimits the IP address (`10.0.0.0/24` → `network-10-0-0-0`) and loops over `{'10.0.0.0/24': 'us-central1', '10.0.1.0/24': 'us-west1', '10.0.2.0/24': 'us-east1'}`, promoting evolvability by keeping subnet naming separate from the network. Need consistent audit tags (`customer`, `automated=true`, cost center, business unit), so add a StandardTags prototype and a server factory that consumes it. Finally, faced with a requirement for private *or* public load balancers, build a DatabaseModule builder that always creates the server group and lets you add internal/external load balancers and firewall rules; the output JSON contains the instance templates, server group manager, external forwarding rule (scheme EXTERNAL, port 3306, target `${google_compute_target_pool.db.id}`), and the TCP/3306 firewall rule. Decision takeaway: the author converted her alerts factory into a prototype once she discovered environment names were unused and thresholds never changed — patterns can outgrow their module.

## Key Takeaways
1. Group resources by function, business unit, or operational responsibility — and write modules with as few resources as possible to shrink the blast radius and speed provisioning.
2. Reach for Factory and Prototype first; they deliver composability, reproducibility, and evolvability for most modules you will write.
3. Reserve Singleton for rarely changed single instances (accounts, projects, root DNS/certs); never let it become the junk drawer for everything.
4. Builder decides *which* resources; Factory decides their *attributes*; Prototype returns static defaults without creating anything; Composite orders a hierarchy of all of them.
5. Minimize transformations in factories — every dynamic generation step needs corresponding tests.
6. For legacy infrastructure without IaC support, write CRUD factory modules per resource and compose them in a builder; test each function for idempotency.
7. Patterns are provisional: modules outgrow and change function, so expect to convert a factory into a prototype (or vice versa) later.

## Connects To
- **Ch 1**: patterns are the concrete mechanisms for composability and evolvability from RICE.
- **Ch 2**: variables/parametrization inside one file become module inputs across files; migration's dependency graph matches the composite hierarchy.
- **Ch 4**: dependency patterns decouple what modules here bind together (e.g., the subnet's `${google_compute_network...}` reference).
- **Ch 5**: sharing modules across teams.
- **Ch 6**: builder modules especially need testing strategies; Ch 8 uses factory modules to standardize security practices.
- **Design Patterns (Gamma et al., "Gang of Four")**: the source taxonomy — creational (Singleton, Factory, Prototype, Builder) and structural (Composite) patterns.