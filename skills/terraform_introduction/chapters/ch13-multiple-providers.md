# Chapter 13: Terraform with Multiple Providers

## Core Idea
Declare one provider block per platform, then reference resources across providers — Terraform resolves the attribute wiring between clouds for you.

## Frameworks Introduced
- **Multi-provider declaration**: add a provider block per platform; store credentials via variables (or environment variables), never hardcoded
  - When to use: multi-cloud, hybrid (on-prem + cloud), or cloud + third-party services (Cloudflare, Datadog)
- **Cross-provider references**: one resource's attribute feeds another provider's resource (e.g. DigitalOcean droplet IP → AWS Route53 A record)
  - How: `records = [digitalocean_droplet.web.ipv4_address]` inside the AWS resource — dependencies follow references

## Key Concepts
- **Multiple provider blocks**: one per platform in the same configuration
- **Cross-provider resource management**: resources spanning providers in one config

## Mental Models
- **Terraform as the wiring board**: each provider is an outlet; Terraform just wires resources together across them.

## Worked Example
DNS pointing at an infrastructure resource on a different cloud:
```hcl
resource "digitalocean_droplet" "web" {
  name   = "web"
  image  = "ubuntu-22-04-x64"
  region = "nyc2"
  size   = "s-1vcpu-1gb"
}

resource "aws_route53_record" "web" {
  zone_id = var.zone_id
  name    = "web.example.com"
  type    = "A"
  ttl     = "300"
  records = [digitalocean_droplet.web.ipv4_address]
}
```
The droplet's IPv4 address — created by one provider — sets the A record of another, in one apply.

## Reference Tables

| Use case | Why Terraform fits |
|---|---|
| Multi-cloud (redundancy, geographic coverage, best-of-breed services) | Consistent management across providers |
| On-premise + cloud (hybrid) | One tool manages both |
| Cloud + third-party services (Cloudflare, Datadog) | All resources together in one config |

## Key Takeaways
1. Multi-provider config is just more provider blocks — no special syntax.
2. Reference attributes across providers and Terraform infers the dependency order.
3. Credentials go through variables or environment variables for each provider.

## Connects To
- **Ch 9**: the credential hygiene rule applies per provider
- **Ch 21**: multi-cloud deployment is listed as a top-tier advanced use case