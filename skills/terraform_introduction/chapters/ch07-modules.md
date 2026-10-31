# Chapter 7: Modules in Terraform

## Core Idea
A module is a container for multiple related resources — like a function in a traditional language: you input variables, and it creates the resources for you.

## Frameworks Introduced
- **Module-as-function**: inputs (`variable` blocks) → resources created → outputs (`output` blocks) returned
  - When to use: any resource set used in more than one place or project
  - How: put `.tf` files in a directory, call it via `module` block with `source` + inputs
- **Standard module layout**: `modules/<name>/` with `main.tf` (entry point, resources), `variables.tf` (inputs), `outputs.tf` (outputs)
  - When to use: any repo growing past a single flat set of files

## Key Concepts
- **Module**: self-contained package of Terraform configs managing a set of related resources
- **`source` argument**: where Terraform finds the module — local path, GitHub/Bitbucket repo, generic Git/HTTP/Mercurial, or the Terraform Registry (e.g. `hashicorp/consul/aws`)
- **Module versioning**: pin versions with Git tags via the `version` argument

## Mental Models
- **Think of modules as reusable infrastructure components**: encapsulate → version → share across environments and projects.

## Code Examples *(technical)*
```hcl
# modules/droplet/variables.tf
variable "name" {
  description = "The name of the droplet"
  type        = string
}
variable "region" {
  description = "The region of the droplet"
  type        = string
}

# modules/droplet/outputs.tf
output "ip_address" {
  description = "The IP address of the droplet"
  value       = digitalocean_droplet.web.ipv4_address
}

# calling configuration
module "web_server" {
  source  = "./modules/droplet"
  version = "1.0.0"
  name    = "web-1"
  region  = "fra1"
}
```
- **What it demonstrates**: inputs + outputs + a version-pinned `module` call.

## Reference Tables

| Module source | Example `source` value |
|---|---|
| Local path | `./modules/droplet` |
| GitHub | `github.com/username/repo//modules/my-module` |
| Bitbucket | `bitbucket.org/username/repo//modules/my-module` |
| Generic Git / HTTP / Mercurial | `git::https://example.com/repo.git//modules/my-module` |
| Terraform Registry | `hashicorp/consul/aws` |

## Key Takeaways
1. Modules are the mechanism for reusability and organization; start extracting early.
2. Note the double-slash in remote sources (`repo//modules/my-module`) — it separates repo path from subdirectory.
3. Version-pin registry/Git modules so upgrades are deliberate.

## Connects To
- **Ch 9**: the recommended project folder structure hangs off `modules/`
- **Ch 8**: Terraform Cloud adds a private module registry on top