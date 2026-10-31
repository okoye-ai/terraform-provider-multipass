# Chapter 8: A multi-cloud MMORPG

## Core Idea
Multi-cloud is "the glue" — declare five providers in one workspace and Terraform orchestrates across clouds as easily as one; architectures range from easy (hybrid-cloud load balancer round-robin) to hard (federated Nomad/Consul clusters) to pragmatic (managed services per cloud).

## Frameworks Introduced
- **Multi-Cloud vs Hybrid Cloud**: multi-cloud = multiple public clouds; hybrid = at least one private + public. Hybrid companies usually *want* to escape to mono-cloud by migrating; multi-cloud is usually forced (M&A, compliance, China/AliCloud) rather than chosen
- **The Five Multi-Cloud Advantages**: flexibility (best-in-class services), cost savings, avoiding vendor lock-in (negotiating position), resilience (automatic cross-cloud failover), compliance
- **Cluster Federation 101** (Borg lineage): Borg paper underlies Kubernetes/Nomad/Mesos/Rancher/Swarm; nodes = clients or servers; servers follow Raft consensus → **odd number of servers for quorum**, one elected leader; clients are unrestricted compute pools
  - Quorum math for the chapter: 4 clusters × 3 servers minimum = 12 VMs plus clients — plan capacity accordingly
- **Managed Services vs Container Orchestration**: managed services (FaaS/SaaS-like) trade control for low ops; re-architecting to managed services (Fargate + Cosmos DB) means learning each cloud's intricacies — obstacles or opportunities
- **Building-Blocks Metaphor**: providers are block sets that fit together; mixing resources across clouds is legal but not always wise — keep an open mind about non-obvious designs

## Key Concepts
- **One workspace, five providers**: aws, azurerm, google, docker, random in a single apply (20 resources) — that's all multi-cloud takes mechanically
- **Docker provider caveat**: hashicorp no longer maintains it (source is `kreuzwerker/docker` and must be declared in `required_providers`); usually Docker Compose/CLI is better
- **Nomad provider caveat**: more teaching tool than real-world; Winkler recommends deploying Nomad/K8s workloads via SDK/CLI/API in CI/CD instead
- **Public IPs instead of VPN tunnels**: without a VPN between clouds, client nodes need public IPs to join federated clusters (with the security trade-off)
- **Federation pattern**: like-to-like clusters federate (Consul↔Consul, Nomad↔Nomad); Nomad auto-federates via WAN joins; Azure's cluster joins using the AWS consul server public IPs (`join_wan`)
- **Passing providers into modules**: `providers = { nomad.aws = nomad.aws, nomad.azure = nomad.azure }` meta-argument, with aliased provider blocks (needed twice due to a Nomad API oddity)
- **App layer topology**: BrowserQuest web app (AWS), MongoDB (Azure), Fabio reverse proxy on every Nomad client, configured by Consul; exposure via external LB from stage 1
- **Bootstrap lag**: `terraform apply` completing ≠ clusters ready — apps are still bootstrapping for minutes after

## Code Examples
```hcl
# Stage 1: federate a second cloud's Consul into the first (public IPs, no VPN)
module "azure" {
  source               = "terraform-in-action/nomad/azure"
  location             = "Central US"
  associate_public_ips = true
  join_wan             = module.aws.public_ips.consul_servers
  consul = { version = "1.9.2", servers_count = 3, server_instance_size = "Standard_A1" }
  nomad  = { version = "1.0.3", servers_count = 3, clients_count = 3,
             server_instance_size = "Standard_A1", client_instance_size = "Standard_A1" }
}

# Stage 2: pass aliased providers into the workload module
provider "nomad" { address = "<aws.addresses.nomad_ui>", alias = "aws" }
provider "nomad" { address = "<azure.addresses.nomad_ui>", alias = "azure" }
module "mmorpg" {
  source   = "terraform-in-action/mmorpg/nomad"
  fabio_db = "<azure.addresses.fabio_db>"
  fabio_lb = "<aws.addresses.fabio_lb>"
  providers = { nomad.aws = nomad.aws, nomad.azure = nomad.azure }
}
```
- **What it demonstrates**: two-stage deployment on Nomad (ch7's technique, stage 2 via Terraform instead of CI/CD): 96-resource apply for clusters, then 4 jobs (browserquest, fabio×2, mongo)

## Worked Example
Three architectures for the same game:
1. **Hybrid-cloud LB** — Docker NGINX container on localhost round-robins to one VM each in AWS/Azure/GCP (each registering itself via public IP, color-coding its cloud); manual fallback: `docker run -p 5000:80 -e ADDRESSES=... swinkler/tia-loadbalancer`
2. **Federated Nomad clusters** — AWS + Azure, each with Consul (3 servers), Nomad (3 servers, 3 clients); verify via Consul UI (toggle datacenters) and Nomad UI (Regions tab); services register with Consul, health-checked, then routed by Fabio
3. **Managed services** — AWS Fargate serverless containers + Azure Cosmos DB; whole re-architecture is a single ~37-resource apply connecting via `--connectionString ${module.azure.connection_string}`

## Key Takeaways
1. Multi-cloud with Terraform is mechanically trivial — provider + module blocks per cloud; design maturity is the hard part.
2. Federation lets you treat compute across clouds as a commodity; Consul gives service discovery, Fabio gives routing.
3. Apply success ≠ cluster readiness; plan for bootstrap lag after provisioning orchestration platforms.
4. Docker and Nomad providers are "questionable value at best" — prefer direct CLI/API for those domains.
5. Managed services are a legitimate multi-cloud strategy: skip self-managed orchestration entirely, mix per-cloud managed services.

## Connects To
- **Ch 4**: module composition reused at multi-cloud scale
- **Ch 7**: two-stage deployment pattern this chapter reuses
- **Ch 1**: cloud-agnosticism claim proven end-to-end
- **Ch 13**: insecure HTTP Consul/Nomad exposures need TLS in production