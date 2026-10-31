# Chapter 6: Networking and Security Infrastructure with Terraform

## Core Idea
Codify Azure networking — VNets, subnets, NAT gateways, NSGs, load balancers, DNS/CDN, and peering — as declarative Terraform so security boundaries and traffic flow are version-controlled, reproducible, and auditable; the same mental models (segment → isolate → control egress → distribute ingress) map onto AWS and GCP via equivalent resources.

## Frameworks Introduced
- **Tier segmentation (web / app / db subnets)**: carve a VNet into purpose-specific subnets to apply different security rules per tier, restrict east-west traffic, and minimize blast radius.
  - When to use: any multi-tier application; always for production networks.
  - How: one `/16` VNet address_space; one /24 (or smaller) subnet per tier, e.g. `10.40.1.0/24` web, `10.40.2.0/24` app, `10.40.3.0/24` db, plus `10.40.254.0/27` reserved for GatewaySubnet.
- **Defence in depth with layered NSGs**: NSGs at both subnet level (broad protection for shared infrastructure) and NIC level (fine-grained per-VM control).
  - When to use: whenever traffic rules must be enforced consistently for a whole tier *and* tightened for individual machines.
  - How: `azurerm_network_security_group` + `azurerm_subnet_network_security_group_association`; rules ordered by `priority` (lower numbers evaluated first).
- **Outbound-only egress via NAT Gateway**: private subnets reach the internet for updates/telemetry while remaining unreachable inbound.
  - When to use: backend tiers that need internet egress but must have no public IPs.
  - How: `azurerm_public_ip` (Static, Standard SKU) → `azurerm_nat_gateway` (Standard) → `azurerm_nat_gateway_public_ip_association` → `azurerm_subnet_nat_gateway_association` on private subnets only.
- **Per-tier allowlist NSG rules**: each tier's NSG accepts traffic only from the tier directly above it.
  - When to use: implementing Zero Trust between tiers (web→app→db chain).
  - How: `source_address_prefix` set to the *upstream subnet's CIDR* (web allows Internet on 22/80/443; app allows web-subnet only on 8080; db allows app-subnet only on 1433).
- **Codified governance (tags + diagnostics)**: tags (environment, owner, cost center) plus NSG flow logs/diagnostics on every network resource.
  - When to use: multi-environment estates needing cost attribution, auditing, and threat detection.
  - How: `tags` blocks on resources; `azurerm_monitor_diagnostic_setting` streaming NSG event/rule-counter logs into Log Analytics; validate policies as code with Sentinel or OPA.

## Key Concepts
- **VNet (`address_space`)**: the isolated CIDR block that defines a network's total IP range; subnets are carved out of it.
- **NSG security_rule**: a prioritized filter (priority/direction/access/protocol/port/source/destination) evaluated top-down; NSGs attach to subnets or NICs.
- **NAT Gateway**: managed outbound-only SNAT for private subnets; requires Standard SKU public IP; never accepts unsolicited inbound traffic.
- **Load balancer anatomy**: frontend IP configuration (public or internal) + backend address pool + health probe (protocol/port/request_path/interval/failure threshold) + load balancing rule mapping frontend→backend port.
- **DNS zone / A record / TTL**: `azurerm_dns_zone` claims the domain; `azurerm_dns_a_record` maps a hostname (www) to the LB/public IP with a caching TTL (300).
- **CDN profile**: global service (`location = "Global"`) with a SKU tier (e.g. `Standard_Microsoft`) that caches content close to users.
- **VNet peering**: private link between two VNets, always bidirectional in practice — one peering resource per direction (`dev-to-prod`, `prod-to-dev`); `allow_forwarded_traffic` controls whether forwarded traffic is permitted.
- **GatewaySubnet**: reserved Azure-mandated name for the subnet hosting a VPN Gateway (the Chef's Special maps any subnet literally named "gateway" to `"GatewaySubnet"` via a ternary).

## Recipes in this chapter
- **Recipe 31: VNet with public and private subnets** — VNet + public/private /24 subnets + NAT Gateway (public IP, both associations) for private-tier outbound access; verify NAT attaches only to the private subnet.
- **Recipe 32: Network security groups for a web server** — NSG allowing 80/443/22 inbound (priorities 100/110/120), attached to web-subnet via association resource; verify with `curl http://<public_ip>` from a terminal.
- **Recipe 33: Setting up an Azure Load Balancer** — Standard LB with static public IP, frontend config, backend pool, HTTP probe, and load-balancing rule distributing traffic across back-end instances.
- **Recipe 34: Configuring DNS with Terraform** — DNS zone `example.com` + A record `www` → static public IP; verify the full resolution path from external query to Azure-hosted IP.
- **Recipe 35: Enabling a CDN for static content** — CDN profile + endpoint linked to a storage-account static website for global content delivery.
- **Recipe 36: Connecting networks with VNet peering** — two VNets (dev/prod) with bidirectional peering; verify private IP communication and "VNet Peering"-labelled effective routes on each VM NIC.

## Anti-patterns
- **Assigning public IPs to private-subnet resources for outbound access**: exposes them inbound; use a NAT Gateway instead — centralized, auditable egress.
- **Opening SSH (port 22) to any source in production**: the author's own rule carries "use with caution in production"; restrict source or use bastion/JIT access.
- **Unidirectional peering**: peering must be created in both directions; one `azurerm_virtual_network_peering` resource only connects one way.
- **Untagged, unlogged network resources**: without tags you lose cost attribution and automation hooks; without NSG flow logs/diagnostics you cannot detect threats or audit compliance.
- **Manual security posture drift**: NSGs and rules defined by hand instead of code cannot be reproducibly audited or policy-checked (Sentinel/OPA) across environments.

## Code Examples
```hcl
# Create multiple subnets within the virtual network using a map
# If the subnet is named "gateway", use the required name "GatewaySubnet" for VPN compatibility
resource "azurerm_subnet" "subnets" {
  for_each             = var.subnet_map
  name                 = each.key == "gateway" ? "GatewaySubnet" : "${each.key}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]
}

# Associate the NAT Gateway only with non-web and non-gateway subnets
resource "azurerm_subnet_nat_gateway_association" "nat_assoc" {
  for_each       = { for k, v in var.subnet_map : k => v if k != "web" && k != "gateway" }
  subnet_id      = azurerm_subnet.subnets[each.key].id
  nat_gateway_id = azurerm_nat_gateway.natgw.id
}
```
- **What it demonstrates**: driving tier topology from a `map(string)` variable, with `for_each` + conditional expression handling Azure's reserved GatewaySubnet name and excluding public/ gateway tiers from NAT egress.

```hcl
resource "azurerm_network_security_group" "web_nsg" {
  name                = "web-nsg"
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100            # Lower numbers are evaluated first
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                   = "Allow-HTTPS"
    priority               = 110
    ...
    destination_port_range = "443"
  }
  security_rule {
    name                   = "Allow-SSH"      # use with caution in production
    priority               = 120
    destination_port_range = "22"
  }
}
```
- **What it demonstrates**: the prioritized allowlist rule structure for a web-tier NSG (80/443/22), later mirrored per-tier with `source_address_prefix` set to upstream subnet CIDRs (app: 8080 from web CIDR; db: 1433 from app CIDR).

## Reference Tables
Table 6.1 — key network/security resources across providers:

| Resource type | Azure | AWS | GCP |
|---|---|---|---|
| Virtual network | VNet | VPC | VPC |
| Subnet | Subnet | Subnet | Subnet |
| Firewall | Azure Firewall | AWS Network Firewall / Security Groups | Google Cloud Firewall Rules |
| Traffic filter | NSG | Security group | Firewall rule |
| NAT Gateway | NAT Gateway | NAT Gateway | Cloud NAT |
| Internet gateway | (Implicit with Public IP) / App Gateway | Internet gateway | Default internet gateway |
| VPN gateway | VPN Gateway / Virtual WAN Gateway | VPN Gateway | Cloud VPN |
| LB (public) | Azure Load Balancer | Elastic LB (ELB) | HTTP(S) LB / TCP Proxy LB |
| LB (internal) | Internal load balancer | Internal ELB | Internal TCP/UDP LB |
| Private link / service endpoint | Private endpoint / service endpoint | VPC endpoint (Interface/Gateway) | Private Service Connect |
| DNS | Azure DNS | Route 53 | Cloud DNS |
| CDN | Azure CDN / Front Door | CloudFront | Cloud CDN |
| Peering | Virtual Network Peering | VPC Peering | VPC Network Peering |
| Private circuit | ExpressRoute | AWS Direct Connect | Cloud Interconnect |
| WAF | Azure WAF (App Gateway / Front Door) | AWS WAF | Google Cloud Armor |
| DDoS protection | Azure DDoS Protection | AWS Shield | Google Cloud Armor |
| IDS/IPS | Azure Firewall Premium / NVA | AWS Network Firewall / 3rd-party NVA | Packet Mirroring + 3rd-party (e.g. Palo Alto) |

## Worked Example
Chef's Special — **three-tier web/app/db architecture** (dir `chapter6\chef-special-three-tier`), three modules wired by a root module:
1. **Appetizer — `modules/network`**: resource group, VNet `10.40.0.0/16`, subnets from `subnet_map` (web/app/db/gateway) with the GatewaySubnet ternary, NAT Gateway + public IP associated into app and db subnets only. Outputs `subnet_ids` map.
2. **Main course — `modules/compute`**: Linux VMs per tier, each with a dedicated NSG — web allows Internet on 22/80/443; app allows only `subnet_cidrs["web"]` on 8080; db allows only `subnet_cidrs["app"]` on 1433. Root passes `subnet_ids` + `subnet_cidrs` from the network module.
3. **Dessert — `modules/loadbalancer`**: Standard LB, static public IP frontend, backend address pool for web VM NICs, HTTP probe (interval 15s, 2 probes fail threshold), rule forwarding frontend port 80 → backend port 80; plus a simulated VPN Gateway placeholder on GatewaySubnet for future hybrid use.
Root module composes: `network` → `compute` (consumes `module.network.subnet_ids` / `rg_name`) → `loadbalancer` (consumes web NIC IDs and gateway subnet ID). Verify with **Azure Network Watcher → Topology** on `chef-special-rg`/`chef-vnet`: subnets as nodes, NSGs attached to NICs/subnets (web-nsg|web-subnet, app-nsg|app-subnet, db-nsg|db-subnet), LB frontend connected to the web backend pool, NAT associations on app/db, VPN placeholder on GatewaySubnet; export the PNG diagram for documentation.

## Key Takeaways
1. Segment by tier first: a `/16` VNet with one subnet per function is the substrate every later security rule hangs on.
2. Prefer NAT Gateways over public IPs for any private subnet that needs outbound internet — isolation without cutting egress.
3. Layer NSGs (subnet + NIC) and make rules explicit prioritized allowlists; chain tiers so each accepts traffic only from the tier above it (Zero Trust between app and db).
4. Always create peering in both directions, and reserve `/27` GatewaySubnet up front if hybrid VPN is plausibly in your future.
5. Tags and diagnostics are part of the network, not an afterthought — code them so cost, audit, and threat detection work at scale.
6. Terraform plus policy-as-code (Sentinel/OPA) is what makes network security consistent across dev/staging/prod rather than aspirational.

## Connects To
- **Ch 2 & 5 (compute)**: this chapter's VNets/subnets/NSGs are the substrate VMs, NSG-attached web servers, and scale sets deploy into (e.g. Ch 2's web server deploys into a Chapter 6-style subnet).
- **Ch 7 (storage & databases)**: the same segment-and-isolate pattern reappears — delegated subnets, private DNS zones, and private connectivity are exactly what the MySQL/Cosmos recipes build on; Ch 7's Chef's Special reuses this networking module shape.
- **Ch 8 (external data)**: extends these static networks with dynamic inputs retrieved from APIs/scripts in automation.