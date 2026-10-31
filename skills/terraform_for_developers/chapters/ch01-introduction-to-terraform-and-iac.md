# Chapter 1: Introduction to Terraform and IaC

## Core Idea
Infrastructure as Code applies software engineering discipline (version control, review, testing) to infrastructure; Terraform implements it through a declarative, cloud-agnostic, state-tracked model in which you declare the desired end state and Terraform computes how to reach it.

## Frameworks Introduced
- **IaC Evolution Stack (Elements of IaC)**: Five maturity levels of automation tooling
  - Ad Hoc Scripting → Server Templating (Packer/Docker/Vagrant) → Configuration Management (Puppet/Chef/Ansible/SaltStack) → Orchestration (Kubernetes/Swarm/Mesos) → Provisioning (Terraform/CloudFormation/GDM)
  - When to use: as a diagnostic — locate where your team sits, and what the next step adds
  - How: each level solves what the previous lacks (idempotency → orchestration of dependencies → desired-state enforcement → full resource lifecycle management + state)
- **Mutable vs Immutable Infrastructure**: the pivotal decision in the book's worldview
  - Mutable: keep patching servers in place; drifts from desired state over time (the Chef/Puppet generation problem)
  - Immutable (Terraform's model): never modify after deploy — replace resources entirely; drift is eliminated, rollbacks are trivial (re-point to previous version)

## Key Concepts
- **HCL (HashiCorp Configuration Language)**: human-friendly declarative language for describing desired infrastructure state
- **Declarative model**: specify *what* the end state is, not the steps; Terraform computes the diff and the "how"
- **State file**: authoritative record mapping config definitions to live infrastructure objects (resource IDs, metadata, outputs)
- **Resource graph**: directional dependency graph Terraform builds; non-dependent resources parallelize, dependent ones execute in order
- **Provider**: plugin connecting Terraform core to a platform (AWS, Azure, GCP, VMware, K8s); encapsulates that platform's resource types and CRUD logic
- **Provisioner**: runs local/remote actions on a resource during creation/destruction (bootstrapping, config files)
- **Data source**: fetches information from existing infrastructure/external systems to feed configuration dynamically (avoids hard-coding IPs, IDs)
- **Plugin architecture**: core engine (HCL interpretation, graph, reconciliation) stays lightweight; platform logic lives in providers

## Mental Models
- Use infrastructure like application code: every change goes through commit → review → plan → apply
- Think of `terraform plan` as your pre-flight safety check: a detailed report of adds/changes/destroys before anything is finalized
- Think of the state file as infrastructure's source of truth — without it Terraform cannot know whether changes happened (causes duplication or drift)
- Heavy provisioner use is a smell: it usually signals you need a dedicated provider or a configuration-management tool instead

## Anti-patterns
- **Mutable patching of servers**: accumulates hidden configuration drift; environments become unreplicable
- **Manual configuration**: produces the "it works on my machine" effect across dev/test/prod
- **Skipping plan review**: apply without reviewing the itemized ops risks unintended modifications

## Key Takeaways
1. Declare the desired state; let Terraform compute the diff — never script the "how"
2. Prefer immutable replacement over in-place patching to kill drift
3. The plan → review → apply loop is the discipline, not a formality
4. Store state remotely in shared, locked backends for team collaboration and auditability
5. Mix providers freely across clouds in one configuration — that is Terraform's core differentiator
6. Version everything, including infrastructure — commit history doubles as change governance and audit trail

## Connects To
- **Ch 2**: hands-on install, Azure setup, and first configuration
- **Ch 5**: state file, introduced here, becomes the centerpiece of state management
- **Ch 4**: modularity, mentioned here as a principle, is developed into reusable modules