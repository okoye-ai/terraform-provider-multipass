# Chapter 1: Introduction to Infrastructure as Code (IaC)

## Core Idea
IaC is the practice of managing and provisioning computing infrastructure with machine-readable definition files instead of manual configuration — a precise, repeatable, scalable "recipe" for every environment you build.

## Frameworks Introduced
- **Pets → Cattle shift**: treat servers as replaceable code artifacts, not sacred hand-configured machines
  - When to use: whenever you catch yourself performing a manual setup step on a server
  - How: write the setup as a code file that anyone (or any agent) can re-run to get the same environment

## Key Concepts
- **Infrastructure as Code**: provisioning via machine-readable definition files, not interactive config tools
- **Declarative tooling**: you state *what* you want; the tool figures out *how* to get there
- **Version control for infra**: IaC files live in Git, giving a historical timeline of changes for error correction

## Mental Models
- **Think of IaC as a kitchen recipe**: the code file tells you exactly which ingredients (resources) to combine to produce the meal (environment). Use this framing when explaining IaC to non-DevOps stakeholders.

## Reference Tables

| IaC Tool | Approach | Distinguishing strength |
|---|---|---|
| Terraform | Declarative, cloud-agnostic | Manages multi-cloud with one toolset |
| Ansible | Procedural, YAML, agentless | Software provisioning + config management + app deployment |
| Chef | DSL ("Cookbooks") | Mature, extensive module collection |
| Puppet | Model-driven | Large enterprises with complex networking |

## Key Takeaways
1. Codify every infrastructure step; if a setup step was ever done manually, it belongs in code.
2. The four IaC payoffs: **speed and efficiency, consistency, reusability, version control**.
3. Declarative ≠ procedural: Terraform wants the *what*; Ansible wants the *how*.
4. Pick the IaC tool by scenario — this book's pick is Terraform for its cloud-agnostic nature, simplicity, and popularity.

## Connects To
- **Ch 2**: Terraform is the specific declarative IaC tool this book deep-dives on
- **Ch 17 & 20**: Ansible, Vault, and Sentinel show how tool choices combine into a full stack