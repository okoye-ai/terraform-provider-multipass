# Chapter 1: Introducing infrastructure as code

## Core Idea
Infrastructure as code applies DevOps practices (version control, continuous delivery, software development patterns) to automating infrastructure changes, judged against four principles that you can use to assess any configuration or tool: reproducibility, idempotency, composability, and evolvability.

## Frameworks Introduced
- **RICE Principles** (mnemonic for the four principles of IaC):
  - **Reproducibility**: "you can use the same configuration to reproduce an environment or infrastructure resources."
    - When to use: whenever you copy configuration for a new environment — ask: will a teammate know you changed it? Will rerunning return the expected state? Will a new environment match?
    - How: keep configuration in version control and keep version control as updated as possible; treat console changes as drift (log into the console → fix the IaC → commit, never the reverse).
  - **Idempotency**: "you can repeatedly run the automation on infrastructure without affecting its end state or having any side effects."
    - When to use: every script and rerun; stricter than mere "repeatability" — the *end state* must be identical.
    - How: add conditional checks that the configuration matches the expected one before acting ("if network interface not configured... configure; else do not reboot").
  - **Composability**: "you can assemble any combination of infrastructure resources and update each one without affecting the others."
    - When to use: building environments from modules (network/server/load balancer blocks you can swap, e.g., standard → premium load balancer).
    - How: group resources into modules that each update independently (chapters 3–4).
  - **Evolvability**: "you can change your infrastructure resources to accommodate system scale or growth while minimizing effort and risk of failure."
    - When to use: before hardcoding anything that will change — names, environments, endpoints.
    - How: reference a single variable (e.g., a global `NAME`) instead of find-and-replace across hundreds of tags; output abstractions (a database endpoint) so the backing technology can be swapped (Bigtable → EMR behind an HBase-compatible endpoint).
- **IaC as DevOps automation** (CAMS model: Culture, Automation, Measurement, Sharing): IaC is the automation piece, realized via code as documentation, version control, software development patterns, and CI/CD applied to infrastructure.
- **Development life cycle applied to infrastructure**: write scripts/config → commit to version control → commit triggers CI/API automation → automation applies changes → test infrastructure.

## Key Concepts
- **Infrastructure**: "the software, platform, or hardware that delivers or deploys applications to production" — broader than the data center trio of compute/network/storage; includes PaaS (managed Kubernetes), FaaS, SaaS (hosted monitoring), queues, caches, monitoring, payment platforms.
- **Blast radius**: the impact a failed change has on a system; a larger blast radius affects more or more-critical components.
- **Configuration drift**: the deviation of infrastructure configuration from the desired configuration to the actual configuration.
- **Code as documentation**: ensuring the code communicates the intent of the system without additional reference documentation.
- **Change management**: the steps and reviews (change review board, change windows) a company uses to implement production changes and prevent failure — no change is risk-free, so IaC mitigates risk by modularizing and rolling forward changes.
- **Shifting security left**: auditable IaC surfaces insecure configuration earlier, before production.
- **Provisioning tool**: "creates and manages a set of infrastructure resources for a public cloud, data center, or hosted monitoring solution."
- **Configuration management tool**: "configures a set of servers or resources for the packages and attributes hosted on them" (Chef, Puppet, Ansible, Salt, CFEngine).
- **Image-building tool**: "builds machine images for application runtimes, such as containers or servers" (Packer, Docker).
- **Dry run**: analyzes and outputs expected changes to infrastructure before you apply them (e.g., Terraform plan).

## Mental Models
- Use RICE as an audit checklist for any script/configuration: Does it re-create environments? What happens when you rerun it? Can you mix and match snippets? Can you evolve a resource without impacting other systems?
- Think of manual changes as debt that accumulates: each console tweak is unaudited, unreproducible, and widens the attack surface; the temptation to "just update the value in the console" is the enemy of reproducibility.
- Think of IaC effort as an investment curve: high initial automation effort (~40 hours of drift reduction) vs. an ever-variable manual effort curve; afterwards the same change costs minutes instead of 10 hours of server-by-server logins.
- Think of the three tool types as a server life cycle pipeline: configuration management configures a test server → image builder snapshots/pushes the image → provisioning tool references the image to create production servers.

## Anti-patterns
- **Manual/console changes ("type /24 into the text box")**: the network drifts from version control; rerunning your IaC reverts it and nobody else knew the change happened.
- **Copy-pasted shell scripts or ticket instructions as "IaC"**: they only count as IaC if they reliably reproduce the infrastructure, revert to a specific version, and let you assess blast radius — outdated, unversioned, ambiguous scripts fail all three.
- **Skipping IaC for obscure one-off systems** ("it's just me configuring this passive data center switch once"): when that person leaves and the passive site must become active, the team spends two months reverse-engineering the configuration.
- **Automating without logic checks**: a script that reboots a switch on every run (version 1) or doubles your server count on rerun; one failed automation makes the organization afraid to automate again.

## Code Examples
This chapter has minimal code (it introduces the Python → Terraform JSON workflow used throughout the book), but its evolvability example is the canonical one-liner pattern:

```python
# All resources in infrastructure as code reference a global variable
NAME = "example"        # becomes NAME = "production"

server_name = NAME
load_balancer_name = NAME
```
- **What it demonstrates**: evolvability — one variable change propagates everywhere, versus find-and-replacing hundreds of hardcoded names.

The book's example workflow (Python 3 writes a `*.tf.json` consumed by Terraform):

```bash
$ python main.py          # generates main.tf.json
$ terraform init          # install provider plugins
$ terraform apply         # Terraform creates/updates/deletes resources
```
- **What it demonstrates**: the examples are tool-agnostic patterns expressed in a programming language (Python) that template Terraform's JSON syntax against GCP.

## Reference Tables
Provisioning tools and providers (table 1.1):

| Tool | Provider |
|---|---|
| AWS CloudFormation | Amazon Web Services |
| Google Cloud Deployment Manager | Google Cloud Platform |
| Azure Resource Manager / Bicep | Microsoft Azure |
| HashiCorp Terraform | Various |
| Pulumi | Various |
| AWS Cloud Development Kit | Amazon Web Services |
| Kubernetes manifests | Kubernetes (container orchestrator) |

Image builders (table 1.2):

| Tool | Runtime environment | Build target |
|---|---|---|
| HashiCorp Packer | Containers and servers | Various |
| Docker | Containers | Container registries |
| EC2 Image Builder | Servers | Amazon Web Services |
| Azure VM Image Builder | Servers | Microsoft Azure |

## Worked Example
Rolling out a binary to servers (a failed change retro-assessed with RICE). The author scripted a restart of dependent services, got a teammate check and change review board sign-off, ran it on the weekend — and Monday revealed a reconciliation application was down: an OS incompatibility with script dependencies. Applying RICE to the postmortem exposed four missing mitigations:
- Reproducibility — never reproduced the script on test instances mimicking the different servers' OS versions.
- Idempotency — no logic to check the operating system before running the command.
- Composability — blast radius was not limited to a small set of less-critical servers first.
- Evolvability — servers were not updated to a newer OS; reducing variation across infrastructure makes changes predictable and reliable.

Decision rule: before any high-blast-radius change, walk all four principles; a miss on any one is a stop signal.

## Key Takeaways
1. Define infrastructure broadly: anything — software, platform, or hardware — that delivers an application to production, including PaaS/SaaS.
2. Test every change against RICE before applying it; a missing principle raises the blast radius or blocks future updates.
3. Prefer the console-fix-the-code order: never change infrastructure without changing the IaC first (drift = failed reproducibility).
4. IaC is worth the initial investment because prevention reduces remediation effort, lowers change failure rate and MTTR.
5. Write IaC even for obscure, single-owner systems — it is your documentation when the owner leaves or an outage hits.
6. Choose provisioning tools for dependency management across resources; configuration management and image building solve different layers, and the ideal server pipeline chains all three.

## Connects To
- **Ch 2**: immutability and writing clean IaC operationalize reproducibility and evolvability.
- **Ch 3–4**: modules implement composability via software design patterns.
- **Ch 6, 11**: testing environments (reproducibility) and rolling forward changes / safe upgrades (idempotency) build directly on RICE.
- **Accelerate (Forsgren et al.)** / **The Phoenix Project**: DevOps metrics and theory behind IaC's practices.
- **Building Evolutionary Architectures (Ford et al.)**: deeper theory of evolvability.
- **Design Patterns (Gamma et al.)**: source of the module patterns in chapter 3.