# Chapter 8: Administering Networks with Terraform

## Core Idea
Networking is the glue binding infrastructure resources together: define one IP space (VPC/VNet), carve non-overlapping subnets per tier, direct traffic with route tables and gateways, secure it with network security rules, and front it with DNS and load balancers — all of it in one versioned codebase, identical in shape across clouds.

## Frameworks Introduced
- **The Network Stack Layers** (provider-agnostic ordering):
  1. **Boundary**: VPC (AWS) / VNet (Azure) with a CIDR range (e.g. `10.0.0.0/16`)
  2. **Subnets**: non-overlapping slices per use case — public subnet for internet-facing, private for databases/backends; `map_public_ip_on_launch` decides auto-public-IP
  3. **Routing**: route tables + routes with a next hop — internet gateway (IGW) for public `0.0.0.0/0`, NAT gateway for private outbound; `route_table_association` binds subnet to table
  4. **Security boundaries**: security groups / NSGs define permitted protocols, ports, source/destination CIDRs
  5. **DNS**: zones and records (Route 53 / Azure DNS) as Terraform resources — no console clicking
  6. **Load balancing**: ALB/LB front-end in ≥2 public subnets, target group, listener, backend pool + health checks (probes)
- **LB wiring pattern**: `aws_lb` → `aws_lb_target_group` (port/protocol/VPC) → `aws_lb_listener` (default_action forward) → `aws_lb_target_group_attachment` per instance, or auto-scaling group registered so scaled instances receive traffic automatically
- **Cross-network connection**: VPC/VNet peering for private cross-environment traffic; site-to-site VPN gateways for on-prem links; flow logs / network watcher for visibility

## Key Concepts
- **CIDR partitioning**: subnets of the same VPC must be disjoint (`10.0.1.0/24`, `10.0.2.0/24` from `10.0.0.0/16`) — overlapping CIDRs fail at provision time
- **`cidrsubnet()` function**: programmatically derives non-overlapping subnet ranges from the VPC CIDR — prefer it over hand-typed prefixes
- **`lifecycle { create_before_destroy = true }`** on auto-scaling groups: replacement happens in the safe order
- **Kubernetes caveat**: CNI overlays and managed clusters (EKS/AKS) still ride on the VPC/VNet subnets — cluster node networking flows from the Terraform-defined topology
- **Provider resource-name equivalents**: VPC↔VNet, security group↔NSG, ELB/ALB↔azurerm_lb/Application Gateway, Route 53↔DNS zones

## Code Examples
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}
resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
```
- **What it demonstrates**: the layered topology — VPC → subnet → gateway → route → association; Azure repeats the same shape with `azurerm_*` resources

## Reference Tables
### Network troubleshooting playbook
| Symptom / error | Cause | Fix |
|---|---|---|
| `Error: Missing required argument` | Required parameter omitted (e.g. `location` on NSG) | Check provider docs; fill required args; run validate + plan early |
| `Error: Resource not declared` | Typo in a referenced name, or referencing an undeclared resource | Match referenced names exactly to declared ones |
| `Error: CIDR blocks overlap` | Two subnets/VPCs share address space | Adjust prefixes; derive subnets with `cidrsubnet()`; validate with OPA-type tools |

### AWS vs Azure resource mapping
| Layer | AWS | Azure |
|---|---|---|
| Boundary | `aws_vpc` | `azurerm_virtual_network` |
| Subnet | `aws_subnet` | `azurerm_subnet` |
| Routes | `aws_route_table`, `aws_route` | `azurerm_route_table`, `azurerm_route` |
| Security | `aws_security_group`, NACLs | `azurerm_network_security_group` (+ ASGs) |
| LB | `aws_lb`, `aws_lb_target_group` | `azurerm_lb`, backend address pool, probes |
| DNS | Route 53 zones/records | `azurerm_dns_zone`/records |
| Observability | Flow logs | Network Watcher |

## Worked Example
Classic three-tier web stack on AWS: VPC `10.0.0.0/16`; public subnets in `10.0.1.0/24` (AZ-a) and a second AZ; private subnets for the ASG; IGW + public route table + association; application LB placed in the public subnets with an SG allowing port 80; target group `app-tg` (port 80, HTTP, instance targets) with a listener forwarding to it; auto-scaling group in private subnets (min 1, max 5, desired 2, `create_before_destroy`) with every instance attached to the target group so scale-out automatically joins the LB pool. Azure equivalent: `azurerm_lb` + `azurerm_lb_backend_address_pool` + `azurerm_lb_probe`.

## Anti-patterns
- **Hand-typed overlapping CIDRs**: copy-pasted subnet blocks colliding; derive from one variable with `cidrsubnet()` instead
- **Subnets without explicit declaration**: assuming the environment inherits addressing — Terraform requires each subnet declared, so it also implies IP collisions need explicit thought
- **Unversioned network rule edits**: firewall stances changed in consoles, invisible to review; rules belong in Git like any resource
- **Single-subnet load balancers**: LBs need ≥2 subnets (AZs) for redundancy
- **Recreating network resources casually**: `taint`/recreate on network resources can take production services down — sequence carefully

## Key Takeaways
1. Plan IP address space top-down (VPC → subnets) and derive, don't improvise, subnet ranges
2. Public/private subnet separation + `map_public_ip_on_launch` is the front-end/backend boundary control
3. Every subnet needs its routing story: which route table, which gateway as next hop
4. Security groups/NSGs are code too — the version-controlled record of your firewall stance is an audit asset
5. LB plumbing is four resources deep (LB → target group → listener → attachment); miss one and traffic goes nowhere
6. `terraform validate` and `terraform plan` before every network apply — these three error classes (missing args, bad references, overlapping CIDRs) are all catchable pre-apply
7. DNS in code keeps zone edits and IP references in lockstep, preventing stale-record mistakes

## Connects To
- **Ch 3**: `cidrsubnet()` and dynamic blocks (for NSG rules) come from the expression toolkit
- **Ch 6**: network-level monitoring overlaps with provisioner-based external integrations
- **Ch 10**: AKS cluster provisioning builds directly on these network constructs