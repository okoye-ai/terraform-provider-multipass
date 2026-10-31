# Chapter 4: Terraform Basics

## Core Idea
Providers are the bridge from Terraform to a platform's API; resources are the infrastructure blocks you declare through them; four commands run the whole lifecycle.

## Frameworks Introduced
- **Provider → Registry lookup**: find providers and modules in the public Terraform Registry before writing your own
  - When to use: starting any new integration — there is almost always an existing provider
- **Resource type + name addressing**: `resource "digitalocean_droplet" "web"` is addressable as `digitalocean_droplet.web` everywhere else in the config
  - How: reference it later (e.g. to attach a DNS record) via the dotted address

## Key Concepts
- **Providers**: plugins that understand API interactions and expose resources of a platform
- **Resources**: a piece of infrastructure — server, database, network — declared in a block
- **Resource type convention**: usually `<provider>_<resource>` (e.g. `aws_instance`, `digitalocean_droplet`)

## Mental Models
- **Providers as interpreters**: Terraform speaks HCL; the provider translates to the API of AWS, DigitalOcean, etc.

## Code Examples *(technical)*
```hcl
provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "web" {
  image  = "ubuntu-22-04-x64"
  name   = "web-1"
  region = "fra1"
  size   = "s-1vcpu-1gb"
}
```

## Reference Tables

| Command | Role |
|---|---|
| `terraform init` | Initialize a working directory; first command for new/existing configs |
| `terraform plan` | Create an execution plan — preview changes before making them |
| `terraform apply` | Create, update, or delete resources to reach the desired state |
| `terraform destroy` | Remove all resources the configuration created |

## Key Takeaways
1. `init → plan → apply` is the daily loop; `plan` is your review gate before any change hits real infrastructure.
2. The resource *name* (`web`) is how other blocks reference the resource — choose it well.
3. When in doubt about what a provider offers, search the Terraform Registry.

## Connects To
- **Ch 5**: variables (`var.do_token`) referenced here are defined in HCL syntax — next chapter
- **Ch 11**: resources created outside Terraform get adopted via `import`