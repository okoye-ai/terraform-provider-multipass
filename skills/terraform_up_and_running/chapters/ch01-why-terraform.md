# Chapter 1: Why Terraform

## Core Idea
Software isn't done until it's delivered to the user, and infrastructure as code (IaC) is the DevOps practice that makes delivery efficient; Terraform is a declarative, cloud-agnostic, masterless, agentless provisioning tool that wins on trade-offs compared to Chef, Puppet, Ansible, Pulumi, CloudFormation, and OpenStack Heat.

## Frameworks Introduced
Frameworks/categories, with author attribution (as presented in the book):

**CAMS (DevOps core values)** — culture, automation, measurement, sharing. *When to use:* to frame what DevOps actually is (a set of processes/ideas, not a team or job title). *How:* focus on automation — manage infrastructure through code, not clicks or manual shell commands. The book's DevOps definition: "The goal of DevOps is to make software delivery vastly more efficient."

**Five categories of IaC tools (Brikman's taxonomy)** — *When to use:* classifying any automation need before picking a tool. *How:*
1. **Ad hoc scripts** (Bash/Python/Ruby) — small one-off tasks; no conventions, no idempotence, single-machine.
2. **Configuration management** (Chef, Puppet, Ansible) — install/manage software on *existing* servers; conventions, idempotence, distribution across many servers.
3. **Server templating** (Docker, Packer, Vagrant) — build a self-contained image (VM or container) of OS + software; deploy identical copies elsewhere.
4. **Orchestration** (Kubernetes, ECS, Docker Swarm, Nomad, Marathon/Mesos) — deploy/manage VMs & containers: rolling/blue-green/canary deploys, auto healing, auto scaling, load balancing, service discovery.
5. **Provisioning** (Terraform, CloudFormation, Heat, Pulumi) — *create* the servers, databases, caches, load balancers, network topology, etc.

**Two categories of server images** — VMs (virtualize hardware via hypervisor: VMware, VirtualBox, Parallels; full isolation, high overhead, slow boot) vs. containers (virtualize only OS user space via container engine: Docker, rkt, cri-o; fast ms boot, minimal overhead, weaker isolation — fine for your own code, use VMs for untrusted third-party code). *When to use:* choosing image type by isolation vs. performance needs.

**Ten IaC tool-selection trade-offs (Brikman)** — *When to use:* choosing an IaC tool rationally instead of by feature list. *How:* compare candidates on each axis — config mgmt vs. provisioning; mutable vs. immutable; procedural vs. declarative; GPL vs. DSL; master vs. masterless; agent vs. agentless; paid vs. free; large vs. small community; mature vs. cutting edge; using multiple tools together.

**Three IaC tool-stack combinations (Brikman)** — *When to use:* no single tool covers everything; pick a combination. *How:* (1) Provisioning + config mgmt (Terraform + Ansible): easy start, no extra infra, but drifts toward mutable procedural code; (2) Provisioning + server templating (Terraform + Packer): immutable, easy start, but VM builds are slow and Terraform's native deployment strategies are limited (no blue-green); (3) Provisioning + templating + orchestration (Terraform + Packer + Docker + Kubernetes): fast Docker builds plus K8s deployment/auto-healing/auto-scaling, at the cost of extra infra and abstraction layers. (Also cites the Gruntwork Infrastructure as Code Library as an example of reusable-module reuse.)

**Immutable infrastructure (inspired by functional programming)** — *When to use:* wanting reproducible, easy-to-reason-about deployments. *How:* never modify deployed servers; build a new image, deploy new servers, terminate old ones. Downsides: slow rebuilds for trivial changes; drift begins the moment a server runs (mitigated by frequent deploys).

## Key Concepts
- **DevOps**: not a team or job title but a set of processes, ideas, and techniques whose goal is making software delivery vastly more efficient; the Dev/Ops distinction blurs once both write software.
- **Infrastructure as code (IaC)**: writing and executing code to define, deploy, update, and destroy infrastructure — treating all operations, even hardware-like aspects, as software.
- **Ad hoc script**: any task automated in a general-purpose language with no structure, idempotence, or multi-server distribution; fine for one-offs, unmaintainable at scale.
- **Idempotence**: code that works correctly no matter how many times you run it (Ansible functions are idempotent by default; ad hoc scripts need explicit if-checks).
- **Server template / image**: a fully self-contained snapshot (OS, software, files) of a server, defined as code with Packer/Vagrant (VMs) or Docker (containers); install software at image build time, run it at boot.
- **Immutable infrastructure**: deployed servers are never modified; updates mean building a new image and deploying new servers, so drift is prevented and test→prod equivalence holds.
- **Configuration drift / snowflake servers**: servers each ending up subtly differently configured (from manual or mutable in-place changes), producing hard-to-reproduce bugs.
- **Provisioning tool**: creates the servers and everything else (DBs, caches, load balancers, queues, subnets, firewall rules, SSL certs) — the category Terraform belongs to.
- **Terraform configuration**: text files (in HCL) declaring desired infrastructure; the "code" in IaC. The single `terraform` Go binary parses them and makes API calls to the relevant providers.
- **Provider**: a cloud/service API adapter (AWS, Azure, GCP, DigitalOcean, OpenStack, …) Terraform calls on your behalf, reusing your existing API keys; Terraform runs no extra infrastructure of its own.
- **Master/agent**: Chef/Puppet's need for a central master server plus per-server agent software — extra infra, maintenance, and attack surface; Terraform/Ansible/CloudFormation/Heat/Pulumi are masterless and agentless by default.
- **Procedural vs. declarative IaC**: procedural code encodes step-by-step *how* (Chef, Ansible) and requires knowing deployed state and change history; declarative code encodes the *end state* and the tool computes the diff (Terraform, Puppet, CloudFormation, Heat, Pulumi).
- **Bus factor**: the number of people you can lose before you can't operate; IaC in source control keeps it from being 1.

## Mental Models
- **Think of Terraform as a translator**: a single client binary that parses your HCL and converts it into API calls to whichever providers your code names — leveraging the cloud's existing API servers and auth instead of running your own master.
- **Think of IaC as documentation**: the source files are a readable, version-controlled description of production that anyone can consult, eliminating the bus-factor-1 sysadmin.
- **Think of code-as-end-state as immune to change history**: with declarative code the repo always shows the current deployed state; to change it you edit the same file and re-apply — Terraform diffs against past state and does only what's needed.
- **Use the "webserver built five ways" ladder when deciding depth of automation**: ad hoc script → config mgmt → image template → orchestrator → provisioner; each rung buys idempotence, distribution, reproducibility, or fleet management.

## Anti-patterns
- **Managing real infrastructure with ad hoc scripts**: general-purpose flexibility means custom code for every task, per-developer style, no idempotence, single-machine scope; large Bash repos "devolve into spaghetti."
- **Tossing code over the wall to Ops ("throw over the wall")**: manual, slow, unpredictable releases → snowflake servers → more bugs → lower release cadence → merge nightmares → silos → the company grinds to a halt.
- **Chasing transparent multi-cloud portability**: a red herring — providers simply don't offer the same infrastructure; use the same language/tool/practices per provider, but expect provider-specific code.
- **Procedural IaC at scale ("count: 10" then a new "count: 5" script)**: doesn't fully capture state (you must know the order every template was applied), and reusability collapses because the code encodes a transient world state; codebases bloat.
- **Accepting master/agent moving parts by default**: extra servers, upgrades, backups, ports, and auth multiply failure modes — at 3 a.m. you can't tell which layer the bug is in.
- **Assuming a paid IaC service will always be there**: pricing models change (Pulumi ~10x for some in 2021), acquisitions happen (Chef/Puppet/Ansible); know whether the free tool alone can run your production. Pulumi without Pulumi Service lacks transactional checkpointing, concurrent locking, and encrypted state — impractical for >1 developer.
- **Picking a tool by ignoring its community/maturity**: you're also picking the ecosystem — plugins, docs, hiring pool — which can matter more than the tool's inherent quality.

## Code Examples

The same Apache webserver shown as an ad hoc Bash script (`setup-webserver.sh`):
```bash
sudo apt-get update
sudo apt-get install -y php apache2
sudo git clone https://github.com/brikis98/php-app.git /var/www/html/app
sudo service apache2 start
```
*What it demonstrates*: works once, but is not idempotent, not distributable, and has no structure — the baseline IaC-tool categories improve on.

Terraform provisioning a server built from a Packer AMI:
```hcl
resource "aws_instance" "app" {
  instance_type     = "t2.micro"
  availability_zone = "us-east-2a"
  ami               = "ami-0fb653ca2d3203ac1"

  user_data = <<-EOF
              #!/bin/bash
              sudo service apache2 start
              EOF
}
```
*What it demonstrates*: provisioning ("create the server") + server templating (the Packer-built `ami`) working together — the common immutable-infrastructure pattern; `user_data` boots Apache only at runtime.

Declarative scaling — changing `count = 10` to `count = 15` in the same file and applying; `terraform plan` previews only the five new instances (`Plan: 5 to add, 0 to change, 0 to destroy`). The Ansible procedural equivalent needs a *new* template (`count: 5`) or it deploys 15 more servers (25 total).

Terraform across providers (multi-cloud in one config):
```hcl
resource "aws_instance" "example" { ... }
resource "google_dns_record_set" "a" {
  name         = "demo.google-example.com"
  managed_zone = "example-zone"
  type         = "A"
  ttl          = 300
  rrdatas      = [aws_instance.example.public_ip]
}
```
*What it demonstrates*: one syntax, interconnected resources across AWS and Google Cloud, with references between providers.

## Reference Tables

**Table 1-4 — The most popular IaC tools compared (default/common usage, June 2022):**

| | Chef | Puppet | Ansible | Pulumi | CloudFormation | Heat | Terraform |
|---|---|---|---|---|---|---|---|
| Source | Open | Open | Open | Open | Closed | Open | Open |
| Cloud | All | All | All | All | AWS | All | All |
| Type | Config mgmt | Config mgmt | Config mgmt | Provisioning | Provisioning | Provisioning | Provisioning |
| Infra | Mutable | Mutable | Mutable | Immutable | Immutable | Immutable | Immutable |
| Paradigm | Procedural | Declarative | Procedural | Declarative | Declarative | Declarative | Declarative |
| Language | GPL (Ruby) | DSL | DSL (YAML) | GPL | DSL | DSL | DSL (HCL) |
| Master | Yes | Yes | No | No | No | No | No |
| Agent | Yes | Yes | No | No | No | No | No |
| Paid service | Optional | Optional | Optional | Must-have | N/A | N/A | Optional |
| Community | Large | Large | Huge | Small | Small | Small | Huge |
| Maturity | High | High | Medium | Low | Medium | Low | Medium |

**Table 1-1 — IaC communities (June 2022):** Chef 640 contributors/6,910 stars/3,695 libraries (Chef Supermarket); Puppet 571/6,581/6,871 (Forge); Ansible 5,328/53,479/31,329 (Galaxy); Pulumi 1,402/12,723/15 (Registry); CloudFormation closed source, AWS-only, 369 (Quick Starts); Heat 395/379/0; Terraform 1,621/33,019/9,641 (Registry modules). Since Sept 2016 (Table 1-2), Terraform grew contributors +148%, stars +476%, libraries +24,003%, Stack Overflow +10,106%; Ansible also exploded. Ansible and Terraform are the clear popularity leads.

**Table 1-3 — Maturity (June 2022):** Puppet 2005 (High), Chef 2009 (High), CloudFormation 2011 (Medium), Ansible 2012 (Medium), Heat 2012 (Low), Terraform 2014 v1.2.3 (Medium — post-1.0 notably more stable), Pulumi 2017 (Low).

**DevOps results:** Nordstrom +100% features/month, −50% defects, −60% lead time, −60–90% incidents; HP LaserJet Firmware dev time on features 5%→40%, costs −40%; Etsy 25–50 deploys/day (source: *The DevOps Handbook*, Kim/Humble/Debois/Willis). 2016 State of DevOps Report: IaC-practicing orgs deploy 200x more frequently, recover 24x faster, lead times 2,555x lower.

## Worked Example
Brikman's 10-servers-to-15-to-new-AMI walkthrough (declarative vs. procedural):
1. **Deploy 10 servers** running `ami-0fb653ca2d3203ac1` (Ubuntu 20.04). Ansible (procedural): `ec2` task with `count: 10`. Terraform: `resource "aws_instance" "example"` with `count = 10`. Both look equivalent on first apply.
2. **Traffic rises; want 15.** Ansible: rerunning gives 25 total, so you must write a *new* template `count: 5` aware of what's deployed. Terraform: edit the same file to `count = 15`.
3. **Preview**: `terraform plan` shows only `aws_instance.example[11]…[14]` created — "Plan: 5 to add, 0 to change, 0 to destroy" — because Terraform remembers its past state.
4. **Ship a new version** (`ami-02bcbb802e03574ba`). Ansible: yet another template to hunt down existing instances via tags/instance_tags/count_tag (and image version, AZ, etc.). Terraform: same file, change `ami` only.
5. **Moral**: the two Ansible templates each encode a point-in-time world state; Terraform's single config always describes the current desired end state, so codebases stay small and reusable. (Two procedural failure modes: code doesn't capture state or apply-order; code loses reusability as state shifts.)

## Key Takeaways
- DevOps = making software delivery vastly more efficient; its key lever here is automation, and IaC is automation applied to infrastructure.
- Classify your need first: ad hoc script vs. config mgmt vs. templating vs. orchestration vs. provisioning — then pick within the right category.
- Real infrastructures use multiple IaC tools together; the three common stacks are Terraform+Ansible, Terraform+Packer, and Terraform+Packer+Docker+K8s, trading simplicity against immutable/declarative benefits and complexity.
- Prefer declarative over procedural, immutable over mutable, and masterless/agentless over master/agent: each reduces drift, state-tracking burden, and moving parts.
- Don't expect transparent cross-cloud portability; expect the same workflow and practices, with provider-specific code.
- Evaluate a tool by its community (Table 1-1) and maturity (Table 1-3), and verify the free tier alone is production-capable — paid services can change pricing, get acquired, or shut down.
- The IaC payoff is software-engineering leverage on ops: self-service, speed and safety, documentation, version control, validation, reuse, and engineer happiness.

## Connects To
- **Ch. 2**: Terraform/HCL syntax — learning the single syntax referenced throughout this chapter.
- **Ch. 3**: Terraform state — the mechanism behind `terraform plan`'s "5 to add" diff and declarative behavior.
- **Ch. 7**: Worked examples of the tool combinations — Terraform + Docker, and provisioning a Kubernetes cluster.
- **Appendix / The DevOps Handbook** (Gene Kim, Jez Humble, Patrick Debois, John Willis, IT Revolution Press, 2016): the cited source for Nordstrom/HP/Etsy DevOps results.
- **Gruntwork Infrastructure as Code Library**: the reusable-modules example for the "Reuse" benefit.
- **External concepts**: immutable infrastructure, configuration drift, idempotence, Packer/Docker/Kubernetes, the 2016 State of DevOps Report.