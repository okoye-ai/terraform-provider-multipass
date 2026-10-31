# Chapter 5: Terraform Configuration Language (HCL)

## Core Idea
HCL is human-readable and declarative: blocks declare *what* exists, arguments assign values, and variables/outputs make configs reusable and injectable.

## Frameworks Introduced
- **Variables for input, outputs for extraction**: `variable` blocks externalize values (`var.<name>`), `output` blocks expose resource attributes to humans/other configs
  - When to use: a value varies per environment → variable; a value others need after apply → output

## Key Concepts
- **Blocks**: type + optional identifier + `{}` body — the basic HCL structure
- **Arguments**: `<name> = <expression>` inside blocks
- **Comments**: `#` or `//` single-line; `/* ... */` multi-line
- **`var.<name>` expression**: how a variable's value is consumed

## Mental Models
- **Outputs as return values**: your Terraform config is a function; `output` blocks are what it returns to the caller.

## Code Examples *(technical)*
```hcl
variable "token" {
  description = "DigitalOcean token"
  type        = string
}

provider "digitalocean" {
  token = var.token
}
```

```hcl
resource "digitalocean_droplet" "web" {
  image  = "ubuntu-22-04-x64"
  name   = "web-1"
  region = "fra1"
  size   = "s-1vcpu-1gb"
}

output "web_ip" {
  value = digitalocean_droplet.web.ipv4_address
}
```
- **What it demonstrates**: variable declaration + consumption, and an output surfacing the droplet's IPv4 address.

## Key Takeaways
1. Master blocks and arguments first — every Terraform file is compositions of them.
2. Give variables `description` and `type`; HCL is written to be read.
3. Any attribute you'll need later (like an IP) should be an `output`.

## Connects To
- **Ch 9**: `.tfvars` files feed values into these variables per environment
- **Ch 10**: functions and locals layer on top of this syntax