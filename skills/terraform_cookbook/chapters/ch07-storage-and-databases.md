# Chapter 7: Managing Storage and Databases with Terraform

## Core Idea
Terraform can provision the entire data layer — storage accounts and blobs, managed disks, SMB file shares, managed MySQL/PostgreSQL/SQL, Cosmos DB NoSQL, and backup vaults with retention policies — so persistence, security, and durability become declarative, repeatable code rather than console clicks; the chapter culminates in a full-stack modular WordPress-style deployment.

## Frameworks Introduced
- **Private database connectivity pattern**: managed databases never exposed publicly — dedicated subnet with service delegation + private DNS zone + VNet link.
  - When to use: provisioning MySQL Flexible Server (or any managed DB) reachable only from inside the VNet.
  - How: `azurerm_subnet` with `delegation { service_delegation { name = "Microsoft.DBforMySQL/flexibleServers" } }` → `azurerm_private_dns_zone` (`private.mysql.database.azure.com`) → `azurerm_private_dns_zone_virtual_network_link` → server bound to subnet and DNS zone.
- **Random-suffix naming pattern**: Azure global names (storage accounts, vaults) get uniqueness from `random_string`.
  - When to use: any globally-unique resource name that must not collide across deployments.
  - How: `resource "random_string" "suffix" { length = 4; upper = false; numeric = false; special = false }` interpolated into the name, e.g. `"filestor${random_string.suffix.result}"`.
- **Backup as code**: vault → policy → protected item, all declared so backup is baked into the lifecycle, not an afterthought.
  - When to use: protecting VMs or file shares with scheduled snapshots and defined retention.
  - How: `azurerm_recovery_services_vault` (Standard SKU, storage redundancy type) → daily backup policy (frequency, retention) → `azurerm_backup_protected_vm` passing the VM's resource ID.
- **Provisioned-throughput Cosmos DB setup**: account → SQL database → container with explicit RU/s and partition key.
  - When to use: globally distributed NoSQL apps needing explicit capacity control (not serverless).
  - How: `azurerm_cosmosdb_account` (consistency_policy, geo_location with failover_priority 0) → `azurerm_cosmosdb_sql_database` (throughput 400) → `azurerm_cosmosdb_sql_container` (partition_key_path `/id`, `partition_key_kind = "Hash"`, consistent indexing).
- **Layered module composition (data / web / frontend / network)**: the SaaS stack split into per-concern modules orchestrated by a root module passing outputs as inputs.
  - When to use: full-stack deployments combining compute, storage, data, and networking.
  - How: each module owns its resources and outputs IDs/names (`db_host`, `subnet_ids`); root wires `module.network.subnet_ids["web"]` into the web module, etc.

## Key Concepts
- **`azurerm_storage_account`**: the object-storage entry point; key knobs are `account_tier` (Standard/Premium), `account_replication_type` (LRS…), and `account_kind` (e.g. `FileStorage` for Azure Files); a `static_website` block enables $web hosting with index/error documents.
- **`container_access_type`**: blob containers are `"blob"` (public read of blobs) or `"private"` (authenticated only) — media uploads use private.
- **`azurerm_managed_disk` + `azurerm_virtual_machine_data_disk_attachment`**: block storage defined by `storage_account_type` / `create_option` / `disk_size_gb`, attached with explicit `lun` and `caching` (`ReadWrite`).
- **`azurerm_storage_share`**: SMB file share with a `quota` in GB; requires a Premium-tier FileStorage account and `depends_on` the storage account.
- **RDBMS server resources**: `azurerm_mysql_server` / `azurerm_postgresql_server` / `azurerm_mssql_server` (or `azurerm_mysql_flexible_server`) — SKU, storage, version, admin credentials, `ssl_enforcement_enabled`, `backup_retention_days`, `geo_redundant_backup_enabled`.
- **Cosmos DB consistency policy**: account-level `consistency_level` (e.g. `"Session"`) governing the CAP trade-off for all databases under it.
- **Recovery Services Vault**: the container for backup policies and protected items; redundancy type (`LocallyRedundant` etc.) set at creation.
- **`sensitive = true` variables**: DB admin passwords are declared sensitive and passed via tfvars, not hardcoded.
- **`custom_data = filebase64(...)`**: cloud-init/base64 startup script injected into VMSS instances at boot to install/configure the app.

## Recipes in this chapter
- **Recipe 37: Blob container for a static website** — storage account with a `static_website` block (index.html / 404.html); verify the auto-created `$web` container and primary web endpoint.
- **Recipe 38: Deploy an Azure database for MySQL** — MySQL Flexible Server in a delegated subnet with private DNS zone + VNet link for private-only access; password as a `sensitive` variable.
- **Recipe 39: Attach a managed disk to a VM** — build VNet/subnet/NIC/VM plus `azurerm_managed_disk`; verify with `lsblk` / `df -h` over SSH.
- **Recipe 40: Setting up Azure File storage** — Premium `FileStorage` account (random suffix name) with `azurerm_storage_share` app-share, 100 GB quota, for SMB mounts across VMs.
- **Recipe 41: Provisioning a Cosmos DB database** — SQL API account with Session consistency and free tier, database at 400 RU/s, container with `/id` hash partition key and consistent indexing.
- **Recipe 42: Implementing backup for Azure resources** — Recovery Services Vault (random-suffixed name, `LocallyRedundant`) + daily backup policy + `vm_id` passed via tfvars to protect an existing VM; verify under Backup Items → Azure Virtual Machine.

## Anti-patterns
- **Hardcoding globally unique names**: storage account and vault names repeat across deployments — use a `random_string` suffix.
- **Exposing databases over public endpoints**: always pair a managed DB with a delegated subnet + private DNS zone + VNet link so it is unreachable from the internet.
- **Treating backup as an afterthought**: vaults, policies, and protected items belong in the IaC lifecycle with explicit retention, not manual console configuration.
- **Hardcoded admin passwords**: declare DB credentials as `sensitive = true` variables supplied via tfvars/secret stores.
- **Assuming creation order implicitly**: for resources within a storage account (e.g. file share), make dependencies explicit with `depends_on`.
- **Serverless/throughput ambiguity on Cosmos DB**: know whether you need provisioned RU/s (with `throughput` on the database) or serverless — the recipe verifies the account reports provisioned mode.

## Code Examples
```hcl
# Create a subnet dedicated to the MySQL Flexible Server
resource "azurerm_subnet" "mysql_subnet" {
  name                 = "mysql-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.mysql_vnet.name
  address_prefixes     = ["10.20.1.0/24"]
  # Delegate this subnet to the MySQL Flexible Server service
  delegation {
    name = "fsdelegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
    }
  }
}

# Create a private DNS zone for secure name resolution of the MySQL server
resource "azurerm_private_dns_zone" "mysql_dns" {
  name                = "private.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}
```
- **What it demonstrates**: the private-database pattern — service delegation plus private DNS zone (with `azurerm_private_dns_zone_virtual_network_link` to the VNet) so the MySQL server resolves and connects only inside the VNet.

```hcl
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = var.account_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  consistency_policy {
    consistency_level = var.consistency_level
  }
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
  free_tier_enabled          = true
  analytical_storage_enabled = true
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                = var.container_name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_path  = var.partition_key_path
  partition_key_kind  = "Hash"
  indexing_policy {
    indexing_mode = "consistent"
  }
}
```
- **What it demonstrates**: the Cosmos DB account→database→container trio with consistency, geo-failover priority, provisioned throughput on the database, and an explicit hash partition key with consistent indexing.

## Reference Tables
Table 7.1 — storage and database equivalents across clouds (Azure / GCP / AWS, with each cloud's Terraform resource):

| Azure | GCP | AWS |
|---|---|---|
| Storage Account / Blob Storage — `azurerm_storage_account` | Cloud Storage Buckets — `google_storage_bucket` | Amazon S3 Buckets — `aws_s3_bucket` |
| Managed Disk — `azurerm_managed_disk` | Persistent Disk — `google_compute_disk` | Elastic Block Store (EBS) — `aws_ebs_volume` |
| Azure Database for MySQL — `azurerm_mysql_server` | Cloud SQL for MySQL — `google_sql_database_instance` | Amazon RDS for MySQL — `aws_db_instance` |
| Azure Database for PostgreSQL — `azurerm_postgresql_server` | Cloud SQL for PostgreSQL — `google_sql_database_instance` | Amazon RDS for PostgreSQL — `aws_db_instance` |
| Azure SQL Database — `azurerm_mssql_database` | Cloud SQL for SQL Server — `google_sql_database_instance` | Amazon RDS for SQL Server — `aws_db_instance` |
| Azure Cosmos DB — `azurerm_cosmosdb_account` | Cloud Firestore/Bigtable — `google_firestore_database` | Amazon DynamoDB — `aws_dynamodb_table` |
| Recovery Services Vault (Backup) — `azurerm_recovery_services_vault` | Cloud Backup — `google_backup_dr_backup_plan` | AWS Backup — `aws_backup_vault` |

## Worked Example
Chef's Special — **WordPress-style SaaS stack** (dir `chapter7\chef-special-wordpress`), root module wiring four modules:
1. **Appetizer — `modules/data`**: MySQL Flexible Server `wordpress-db` (`B_Standard_B1ms`, version 8.0.21, zone 1, 20 GB storage, admin password via sensitive var) + `wpstorage<random4>` storage account with a **private** `media` blob container. Outputs `db_host` (FQDN), storage account/container names.
2. **Main course — `modules/web`**: `azurerm_linux_virtual_machine_scale_set` (`Standard_B1s`, 2 instances, SSH-key auth, Canonical `22_04-lts`) with `custom_data = filebase64("${path.module}/cloud-init-wordpress.sh")`; the cloud-init script apt-installs apache2/php/php-mysql, writes a phpinfo index page, and enables/starts apache2.
3. **Dessert 1 — `modules/frontend`**: static public IP + Standard LB with `web-fe` frontend configuration for public access.
4. **Dessert 2 — `modules/network`**: resource group, VNet, and subnets via `for_each` over `subnet_map` (web = 10.60.1.0/24); outputs the `subnet_ids` map.
Root module composes them: network → data (db_password) → web (takes `module.network.subnet_ids["web"]` and SSH key path) → frontend. Verify in `chef-wordpress-rg`: chefwp-vnet/web-subnet, VMSS with 2 running instances, wpstorageXXXX with private media container, running wordpress-db; browse the LB public IP (Apache landing page / install wizard); check `/var/log/cloud-init.log`; `terraform output` should return the DB FQDN, storage account, container name, and LB IP.

## Key Takeaways
1. Managed databases get private by default in your code: delegated subnet + private DNS zone + VNet link, never a public endpoint.
2. Every globally-named resource (storage accounts, backup vaults) should interpolate a `random_string` suffix — uniqueness is a provisioning concern, not a naming convention.
3. Block storage is a pair of resources: the disk defines type/size, the attachment resource controls LUN and caching; don't try to set both in one place.
4. Match your Azure Files account shape to the workload — Azure Files requires a Premium-tier `account_kind = "FileStorage"` account, not a general-purpose one.
5. Cosmos DB capacity and partition design are code: declare the database's RU/s, the container's partition key path/kind, and the indexing mode explicitly.
6. Vault + policy + protected item is the minimum backup-as-code unit; if a VM is created by Terraform, its backup policy should be too.
7. Compose full stacks as per-concern modules (network/data/web/frontend) whose outputs feed each other — the same skeleton the book's Chef's Specials reuse.

## Connects To
- **Ch 6 (networking)**: this chapter's private database pattern is Chapter 6's segment-and-isolate approach applied to the data layer; the WordPress Chef's Special reuses the VNet/LB module shapes built there.
- **Ch 5 (compute)**: the VMSS + cloud-init + load balancer web tier comes from the compute recipes; managed disks are attached to VMs created in that chapter's style.
- **Ch 8 (external data)**: these static data-layer configs are the baseline for injecting dynamic inputs (API data, scripts, local-exec provisioners) into storage/database workflows.
- **Ch 3/4 (state & secrets)**: sensitive DB passwords passed via variables/tfvars point toward the secrets-management and state-handling practices covered earlier.