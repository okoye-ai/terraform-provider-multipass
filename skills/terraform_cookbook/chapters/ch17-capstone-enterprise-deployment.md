# Chapter 17: Capstone Enterprise Cloud Infrastructure Deployment

## Core Idea
The graduation exercise: assemble everything from the book into one portfolio-worthy, enterprise-grade Azure deployment in Terraform — multi-tier, zone-distributed, module-based, private-networked, observable from day one, and disaster-recovery-capable — proving an architecture can be "resilient, secure, scalable, and ready to recover" purely by codifying it.

## Frameworks Introduced
- **Four pillars of enterprise architecture**: high availability, security, scalability, disaster recovery as the evaluation criteria for every design decision in the capstone.
  - When to use: when judging whether an infrastructure is "enterprise-grade" rather than merely functional.
  - How: availability zones and replication for availability; network isolation, encryption at rest/in transit, Key Vault, and least privilege for security; scale sets and auto-scaling for scalability; failover groups and secondary regions for disaster recovery.
- **Multi-tier, multi-zone deployment pattern**: web, application, and data tiers isolated into separate subnets and distributed across availability zones.
  - When to use: any production service that must survive a component or zone failure.
  - How: web tier behind a load balancer with health checks and controlled ingress; application tier private (VM Scale Set or App Service) spread across zones; data tier on managed databases with built-in replication and failover, secured in its own subnet — connected by routing rules, NSGs, and load balancers.
- **Modules as enterprise building blocks**: a library of standard modules (network, compute, database, monitoring) consumed by the capstone.
  - When to use: any repeated infrastructure pattern across projects or environments.
  - How: encapsulate the VNet/subnets/NSGs into a network module, scalable tiers into a compute module, managed HA services into a database module, and telemetry into a monitoring module; improvements to one module automatically benefit all consumers. Approved modules act as trusted building blocks that enforce enterprise standards.
- **Monitoring as code**: observability provisioned and versioned with the infrastructure, not bolted on later.
  - When to use: every environment, from the first deployment.
  - How: provision a Log Analytics workspace to centralize logs, enable diagnostic settings on compute and database resources, wire Application Insights for app telemetry (request rates, response times, failures), and define alert rules as code (CPU thresholds, service availability).
- **Multi-environment structure**: same codebase, separate environments driven by variable files and backend settings.
  - When to use: staging → production promotion workflows.
  - How: split directories such as `environments/staging` and `environments/production`, each with its own variable definitions and backend configuration; independent remote state prevents accidental overlap; production scales the same blueprint for live workloads and gates promotes behind approval.
- **Post-deployment hardening (bootstrap-then-lock pattern)**: provision secret stores with public access first, then privatize once secrets are written.
  - When to use: any service (Key Vault, SQL) where the writer needs network reachability before private endpoints exist.
  - How: write Key Vault secrets while public network access is enabled; after confirming success, disable public access and add a private endpoint plus firewall rules. Disabling public access up front yields HTTP 403 while Terraform writes secrets.

## Key Concepts
- **NAT gateway egress**: deterministic, scalable outbound internet for private subnets — required so that cloud-init package installs succeed on instances with no public IP.
- **User-Assigned Managed Identity (UAMI)**: an attachable identity that lets the application tier retrieve Key Vault secrets via `DefaultAzureCredential` with zero credentials in code; the identity is granted least-privilege Secret Get/List only.
- **Private Endpoint + Private DNS zone**: makes services (Key Vault, Azure SQL) reachable only inside the VNet; zone `privatelink.vaultcore.azure.net` (KV) / `privatelink.database.windows.net` (SQL) with an A record resolving the service FQDN to a private IP.
- **Zone-redundant Business Critical SKU**: Azure SQL tier with built-in zone redundancy for high availability; only supported in certain region/SKU combinations (e.g. `BC_Gen5_2` in zone-enabled regions).
- **Azure SQL Failover Group**: replicates the primary database to a secondary server in another region and provides stable read-write and read-only listener endpoints (`<fog-name>.database.windows.net`, `<fog-name>.secondary.database.windows.net`) that redirect on geo-failover — apps must use the listeners, not the server-specific FQDN.
- **Workspace-based Application Insights**: the modern ingestion model tied to a Log Analytics workspace (SKU `PerGB2018`), "strongly recommended for enterprise telemetry"; diagnostic settings use the modern `enabled_log` / `enabled_metric` schema.
- **Activity Log alerts**: global-scope resources that must set `location = "Global"`; used to alert on destructive operations.
- **Compliance mappings (GDPR / HIPAA / ISO 27001)**: Terraform enforces the underlying controls — privacy-by-design and network isolation for GDPR; ePHI segregation, encryption, and audit logging for HIPAA; least privilege, full encryption lifecycle, governance tagging, and auditable configurations for ISO 27001.
- **Blast radius limiting**: split enterprise infrastructure into smaller modular components with their own state files instead of one root configuration, reducing widespread-outage risk and enabling independent team deploys.

## Recipes in this chapter
- **Recipe 97: Deploy core network infrastructure** — hub VNet spanning availability zones with web/app/data subnets, tiered NSG rules, and a NAT gateway for private outbound egress; validated with `az network vnet` / `az network vnet subnet` commands.
- **Recipe 98: Secure secrets and identity management** — Azure Key Vault (soft delete, purge protection) with `random_password` DB secrets, a UAMI granted least-privilege secret read, and an optional private endpoint with the `privatelink.vaultcore.azure.net` DNS zone.
- **Recipe 99: Launch scalable application tier** — Linux VM Scale Set across zones behind an internal Load Balancer on a private IP, UAMI attached, NGINX bootstrapped on port 8080 for health probing; identity lookup made robust (`uami_id` literal or lookup by name).
- **Recipe 100: Provision a managed database service** — Azure SQL Database on a business-critical zone-redundant tier, private endpoint in the data subnet, public access disabled once the endpoint exists, admin login/password/connection string persisted as Key Vault secrets.
- **Recipe 101: Implement monitoring and logging** — Log Analytics workspace + workspace-based Application Insights, platform metrics (AllMetrics) streamed from VMSS/LB/SQL IDs passed in from Recipes 97–100, metric and activity-log alerts; validate with a `AzureMetrics | summarize count() by ResourceId` KQL query.
- **Recipe 102: Plan for disaster recovery** — secondary Azure SQL server in a different region, a private endpoint reusing the existing hub VNet/DNS zone (SQL private endpoints support cross-region connectivity), and an `azurerm_mssql_failover_group` with `partner_server` and `read_write_endpoint_failover_policy`.

## Anti-patterns
- **One root configuration for the whole enterprise**: maximize blast radius and blocks independent deploys — split into modules with separate state files.
- **Local state files in team environments**: they invite conflicts and corruption; always use remote backends with locking and versioning, plus access controls on who can modify state.
- **Disabling public network access before the private endpoint exists**: Terraform's secret-write path (HTTP 403) fails; bootstrap with public access, then lock down.
- **Hardcoding secrets in code or variables**: the only permitted pattern is identity-based retrieval — attach the UAMI and use `DefaultAzureCredential` against the vault URI.
- **Using server-specific FQDNs for SQL connectivity on failover**: they break on geo-failover; switch to the Failover Group listeners.
- **Mismatched Private Endpoint region**: the PE must sit in the same region as its VNet/subnet even when the target SQL server is elsewhere (`InvalidResourceReference` otherwise).
- **Blind diagnostic categories**: diagnostic log categories vary by resource type/region/SKU — the chapter enables AllMetrics only until availability is confirmed per resource.
- **Skipping module READMEs and recovery runbooks**: documentation (purpose, inputs, outputs, usage) and runbooks for failed applies/imports are a stated enterprise practice, not optional polish.

## Code Examples
```hcl
# providers.tf — pinned settings used across the capstone
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```
- **What it demonstrates**: the provider-version discipline every capstone recipe uses — keep the same major provider version (`azurerm ~> 4.0`) across all recipes so IDs and schema (e.g. diagnostic settings) stay compatible.

```hcl
# locals.tf + course3_observability.tf
locals {
  name_suffix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    owner       = "platform-engineering"
  }
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.name_suffix}"
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.core.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
```
- **What it demonstrates**: naming/tagging centralized in `locals` (governance-as-code) and the workspace-based Log Analytics resource that anchors the observability tier; Application Insights and diagnostic settings with `enabled_log`/`enabled_metric` attach to it.

## Worked Example
Chef's Special: **Full enterprise-grade infrastructure deployment** (directory `chapter17/chefs_special`, files `providers.tf`, `variables.tf`, `locals.tf`, `course1_foundation.tf`, `course2_app_db.tf`, `course3_observability.tf`, `outputs.tf`, `dev.tfvars`).
1. *Appetizer — Foundational setup*: in `course1_foundation.tf` create the core resource group (`rg-core-${local.name_suffix}`), VNet with public/private subnets, subnet-level NSGs enforcing least privilege, a NAT gateway for deterministic egress, a UAMI, and Key Vault with DB secrets.
2. *Main course — App tier and DB setup*: in `course2_app_db.tf` create the app resource group, an internal Load Balancer with health probe and rolling upgrades in front of a zone-spread VM Scale Set, and Azure SQL with a private endpoint plus the `privatelink.database.windows.net` zone for private-only data access.
3. *Dessert — Observability and alerts*: in `course3_observability.tf` deploy Log Analytics (SKU `PerGB2018`, 30-day retention), workspace-based Application Insights, diagnostic settings streaming `enabled_log`/`enabled_metric` to the workspace, and metric + Activity Log alerts (`location = "Global"` for the activity alerts).
4. *Final servings*: outputs expose `foundation_rg`, `app_rg`, `db_rg`; `dev.tfvars` tunes per environment (e.g. `vmss_sku = "Standard_B4ms"`, `sql_zone_redundant = false` where region/SKU unsupported).
5. *Post-deployment hardening*: once secrets are confirmed written, disable Key Vault public network access and add a private endpoint + firewall rules.
Outcome summarized as four pillars delivered by code: resilience through automation (multi-zone VMSS, health-probe-aware LB), isolation via Private Link/private DNS, enterprise observability wired in from day one, and policy-driven guardrails (NSGs, TLS 1.2 on SQL, activity alerts on destructive operations).

## Key Takeaways
1. Design in tiers (web → app → data) distributed across availability zones with NSG-enforced boundaries; isolation and controlled connectivity are what make a single zone failure survivable.
2. Build with modules — network, compute, database, monitoring — so enterprise standards propagate automatically to every consumer instead of being re-implemented per project.
3. Codify secrets: Key Vault + UAMI + `DefaultAzureCredential` means no credentials in code or variables, and bootstrap-then-harden keeps the provisioning path reachable.
4. Keep data services private and managed: PaaS SQL on a zone-redundant Business Critical tier with a private endpoint beats self-managed VMs on availability, maintenance, and compliance.
5. Ship observability in the same apply as the infrastructure — Log Analytics, Application Insights, diagnostic settings, and alert rules as code — so every environment gets identical monitoring.
6. Make DR a declared resource: a secondary region, partner server, and Failover Group give a stable listener endpoint that survives geo-failover; test DNS resolution of `<fog-name>.database.windows.net`.
7. Run enterprise-scale Terraform with version-control rigor (PR review, `terraform fmt`/`validate` in pipeline), remote locked state, module READMEs and recovery runbooks, small state per component, and Sentinel/OPA/Checkov enforcing compliance in-pipeline.

## Connects To
- **Ch 16 (Terraform Cloud collaboration)**: the capstone's recipes are meant to run inside the governed workflow — VCS-driven plans, Sentinel guardrails, and team permissions — that the previous chapter establishes.
- **Ch 15 (multi-cloud)**: the capstone is Azure-centric, but the book's multi-cloud recipes 85–90 show the same module patterns extended across clouds.
- **Earlier compute/network/storage/monitoring chapters (Recipes 25–66)**: every capstone recipe consciously reuses those building blocks — this chapter is their assembly, not new primitives.

*(Density note: the chapter is mostly a guided six-recipe build; this file reflects its full structure with no invented material.)*