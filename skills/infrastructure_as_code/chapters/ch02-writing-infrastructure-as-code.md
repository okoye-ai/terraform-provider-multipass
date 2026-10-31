# Chapter 2: Writing infrastructure as code

## Core Idea
Treat infrastructure as immutable whenever possible (creating a new resource replaces drift), migrate brownfield environments from base infrastructure upward, and then write clean IaC — version control hygiene, linting, descriptive naming, deliberate variables-vs-constants, parametrized dependencies, and secrets externalized to a secrets manager.

## Frameworks Introduced
- **Mutable vs. Immutable infrastructure**:
  - Mutable infrastructure: you update the resource in place without recreating or restarting it. Use when the change is small, localized, and fast — and for fixing a broken system.
  - Immutable infrastructure: "you must create a new resource for any changes to infrastructure configuration." Use as the default because creating a new resource eliminates drift, limits blast radius, and preserves reproducibility; machine image builders are built on this concept.
  - Trade-off: mutable changes affect a small portion of the state and are faster; immutable changes replace the whole state (recreating tens of thousands of servers takes days). You will switch between them by circumstance.
- **Out-of-band change remediation**: a quickly implemented change that temporarily treats immutable infrastructure as mutable (mutable coffee vs. immutable cappuccino — sugar can be added to coffee; a milk mistake requires a whole new cappuccino). After any out-of-band change: upgrade Python in place → update version control to install Python 3 → future servers get Python 3. Reconcile the source of truth or the change becomes drift.
- **Brownfield migration workflow** (reconstructing a source of truth for a manually configured environment):
  1. Inventory resources; find **base infrastructure** that everything depends on (networks).
  2. Reverse-engineer attributes (name, CIDR block) from the provider API; write them into IaC **exactly** or the IaC breaks the network.
  3. Import into the provisioning tool's state if possible (`terraform import`, CloudFormation resource import); otherwise create a new greenfield resource; if neither, write conditional statements to check resource existence.
  4. Rerun IaC and check the dry run for drift; a dry run showing changes means the configuration has not captured actual state — correct it before moving on.
  5. Migrate the next, higher-level resource (composability lets each migrate separately).
- **Nine-step migration order** (dependency-driven): 1) accounts/projects/provider isolation + automation service account → 2) networks, subnetworks, routing, root DNS + SSL certs → 3) compute (servers, databases) → 4) compute orchestration platform (e.g., Kubernetes cluster) → 5) application deployments to that platform → 6) queues/caches/event streaming → 7) DNS subdomains, load balancers, firewalls → 8) alerts/monitoring → 9) SaaS resources not depending on applications. Rerun configuration between each step.
- **Code hygiene** ("a set of practices and styles to enhance the readability and maintainability of code") applied to IaC: version control communicates context, linting, formatting, naming, variables/constants, parametrized dependencies, secret separation.
- **Decision rule — variable vs. constant**: "consider the impact and security implications of changing the value. The frequency of change matters less." If changing it affects dependencies or security → variable. Names and environments are always variables. Unlike software development, IaC prioritizes constants over variables — too many variables make configuration unmaintainable; use local values for constants (OS images, tags, account identifiers, domain names, internal/external network types).

## Key Concepts
- **CRUD**: every infrastructure change reduces to create, read, update, delete — the four functions you write even in hand-rolled automation.
- **Imperative style**: describes *how* to configure a resource step-by-step; does not scale (reconstructing 200 change requests took 1.5 months and still did not match).
- **Declarative style**: describes the *desired end state*; the tool decides the steps.
- **Infrastructure source of truth**: "structures information about the state of your infrastructure system consistently and singularly" — version control configuration is the source of truth.
- **Drift**: the difference between version control and actual state; the enemy of reproducibility.
- **Linting**: automatically checks code style for nonstandard configuration (catches `ip` vs `ip_address` field-name errors early); include rules for security standards such as no secrets in version control.
- **Formatting**: automatically aligns code for correct spacing and configuration formats; run via pre-commit Git hooks and the CD workflow.
- **Secret**: sensitive information ( passwords, tokens, SSH keys, certificates); always pass as variables and store in a secrets manager — never hardcoded or committed in plaintext.
- **Commit message as why-documentation**: the diff already says what changed; the commit message explains *why* and the impact on other infrastructure, optionally prefixed with a ticket ID (TICKET-002) for traceability.

## Mental Models
- Use the declarative style when you need to reproduce or extend environments; use imperative step-by-step only for one-shot scripts.
- Think of every mutation as "create new, delete old" by default; demote to in-place updates only when blast radius and time justify it — and always reconcile the source of truth afterwards.
- Think of migration as reconstructing the dependency graph bottom-up: low-level (networks, accounts, IAM) first, then servers/databases, then firewalls/load balancers/DNS last because fewest things depend on them.
- Name resources by "describing them to someone else": if another person understands the resource from the name alone, it is good.

## Anti-patterns
- **Hardcoding dependency names** (`development` network in a server config): reproducing for production becomes hours of error-prone search-and-replace across multiple references.
- **Hardcoded values in copy-pasted configuration**: reduces readability and reproducibility; hardcoded `hello-world` took an hour to find-and-replace while the variable'd port took seconds.
- **Committing secrets in plaintext config or version control**: anyone who reads the repo can use your GCP service account key; also breaks evolvability (an encrypted SSL certificate committed two years ago expires and cannot be decrypted).
- **Naming resources meaninglessly** (`firewall-rule-1`): two weeks later the author could not remember the rule's purpose and spent 30 extra minutes tracking down its IP allowances.
- **Making everything a variable**: configuration becomes hard to maintain; scope values to a resource as constants/locals instead.
- **Migrating top-down**: you cannot write IaC for servers before the networks they run on exist as code.
- **Accepting dry-run drift after migration**: if rerunning IaC outputs changes, the configuration does not match actual state — fix it or your next apply may break the resource "by accident."

## Code Examples
Listing 2.1 — parametrize dependencies as variables (essentials):

```python
import json

def hello_server(name, network):
   return {
       'resource': [
            {
                'google_compute_instance': [
                      {
                            name: [
                                {
                                    'zone': 'us-central1-a',
                                    'boot_disk': [
                                        {
                                            'initialize_params': [
                                                 {'image': 'ubuntu-1804-lts'}
                                            ]
                                        }
                                    ],
                                    'machine_type': 'f1-micro',
                                    'name': name,
                                    'network_interface': [
                                        {'network': network}
                                    ],
                                    'labels': {
                                        'name': name,
                                        'purpose': 'manning-infrastructure-as-code'
                                    }
                                }
                            ]
                      }
                ]
            }
       ]
   }

if __name__ == "__main__":
   config = hello_server(name='hello-world', network='default')
   with open('main.tf.json', 'w') as outfile:
       json.dump(config, outfile, sort_keys=True, indent=4)
```
- **What it demonstrates**: passing name and network as parameters loosely couples server and network — reproducing on another network means changing one variable, not search-and-replacing `development` everywhere.

Commit message communicating context (why, not what):

```bash
$ git commit -m "TICKET-002 Allow app to connect to queues
app-network needs to connect to shared-services-network
because the application uses queues.
All ports need to be open."
```
- **What it demonstrates**: version control as change documentation; weeks later reproducing in production, the history explained the allowance.

## Reference Tables
Imperative vs. declarative (synthesized from section 2.1):

| Aspect | Imperative | Declarative |
|---|---|---|
| Describes | How to configure, step-by-step | Desired end state |
| Tool decides steps | No — you enumerate CRUD steps | Yes — automation figures it out |
| Scales with many changes | Poorly (replaying change requests) | Well |
| Reproducibility | Steps may not end in the same result | Configuration is the source of truth |

Mutable vs. immutable:

| Aspect | Mutable | Immutable |
|---|---|---|
| Change mechanism | Update in place | Create new resource, replace old |
| Effect on state | Localized, partial | Entire state replaced |
| Speed/cost | Faster | Slower, more time and effort |
| Risk | May break the resource or cause drift | Isolates change to the new resource, limits blast radius |
| Best for | Quick fixes, minor changes | Default; environments you must reproduce |

## Worked Example
Migrating the brownfield hello-world development environment (dev.hello-world.net) to immutable IaC:
1. Base layer: terminal query prints network names/CIDRs — `development` (10.0.0.0/16) and `development-database` (10.28.0.0/16); copy exactly into IaC, import, rerun, confirm zero drift.
2. Next layer: print server attributes — hello-world server on `development`, region A, 1 CPU, Ubuntu; database `hello-world` table, 10 GB memory on `development-database` network. Write configs recording their dependency on the networks; server and database depend on the networks but *not on each other*, so they migrate in parallel. Rerun and reconcile.
3. Last layer (fewest dependents): DNS `dev.hello-world.net` targeting the load balancer; public-access firewall `allow from 192.168.0.0/16`; load balancer targeting the hello-world server at 10.0.0.5; database-access firewall `allow from 10.0.0.0/16`.
4. Result: version control is now a consistent source of truth and the brownfield environment can be treated as immutable infrastructure. Key rule: identify what others heavily depend on and migrate first; rerun after each set because "you rarely get all the parameters and dependencies you need on the first try."

## Key Takeaways
1. Reduce every script to CRUD and prefer declarative configuration for anything you will reproduce.
2. Default to immutable changes; after any out-of-band (mutable) change, immediately update the source of truth or it becomes drift.
3. Migrate brownfield infrastructure dependency-first: accounts/projects → networks → compute → orchestration → deployments → queues → DNS/LB/firewalls → alerts → SaaS, verifying zero drift in the dry run at each layer.
4. Write commit messages that explain why and impact, not what; prefix ticket IDs for audit traceability.
5. Name resources `<environment>-<type>-<purpose>` (e.g., `dev-firewall-rule-allow-hello-world-to-database`); prefer the provider's native attribute naming so docs lookups stay easy.
6. Decide variables vs. constants by the impact and security implications of change, not frequency — and favor constants/local values over proliferating variables.
7. Never commit secrets: pass them as variables from a secrets manager so rotation is a rerun, not a find-and-replace-and-re-encrypt.

## Connects To
- **Ch 1**: immutability and drift reduction directly enforce reproducibility and idempotency (RICE).
- **Ch 3**: modules are the next step up from parametrizing dependencies within a single file; chapter 4 covers decoupling dependencies across modules.
- **Ch 7**: structured version control and pre-commit hooks feed continuous delivery for infrastructure.
- **Ch 8**: linting rules for secrets and tagging extend security checks here.
- **Ch 10**: importing resources into a source of truth is the same mechanism used when refactoring IaC.
- **GitOps (ch 7)** and **Pro Git (Chacon & Straub)**: the version-control-as-source-of-truth and commit message disciplines.