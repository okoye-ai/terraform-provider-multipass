# Chapter 2: Introduction to Terraform

## Core Idea
Terraform is HashiCorp's declarative IaC tool: you describe the desired state, Terraform figures out the steps and maintains a state file mapping code to real-world resources.

## Frameworks Introduced
- **Desired-state declaration**: "It's like telling a magic genie, 'I wish for a castle'" — specify the end state, not the steps
  - When to use: every Terraform config you ever write; contrast explicitly with procedural scripts
- **Immutable infrastructure**: instead of mutating existing resources, Terraform replaces them — like functional programming treats variables
  - Why it works: predictability — no snowflakes accumulating drift from in-place edits

## Key Concepts
- **Provider**: plugin bridging Terraform and a target platform API (AWS, DigitalOcean, GCP, Azure...)
- **Module**: encapsulated, reusable group of resources
- **State file**: Terraform's record of real-world resources it manages and their metadata
- **Masterless**: Terraform runs from your machine or CI; unlike Puppet/Chef there is no master node

## Mental Models
- **Terraform as sous-chef**: you wrote the recipe (IaC), Terraform executes it to perfection.
- **Use Terraform over CloudFormation when**: you need multi-cloud or hybrid-cloud with one toolset and one language.

## Anti-patterns
- **Thinking procedurally in a declarative tool**: writing Terraform as step-by-step instructions rather than resource declarations.

## Code Examples *(technical)*
```hcl
provider "digitalocean" {
  token = "your_digitalocean_token_here"
}

resource "digitalocean_droplet" "example" {
  image  = "ubuntu-22-04-x64"
  name   = "web-1"
  region = "nyc2"
  size   = "s-1vcpu-1gb"
}
```
- **What it demonstrates**: a minimal declarative config — name the image, region, size; Terraform handles the rest.

## Reference Tables

| Terraform vs others | Terraform position |
|---|---|
| vs Ansible | Declarative (what) vs procedural (how) |
| vs Chef/Puppet | Masterless — run from anywhere, no master node required |
| vs CloudFormation | Multi-provider; not locked to a single cloud |

## Key Takeaways
1. Terraform's four benefits as the author frames them: **provider-agnostic, immutable infrastructure, modular/reusable, state management**.
2. You only ever need to know *what* you want — never code the *how*.
3. State management is a first-class feature, not an afterthought (covered fully in Ch 6).

## Connects To
- **Ch 6**: the state file introduced here gets its own deep-dive
- **Ch 7**: modules, the reusability mechanism mentioned here