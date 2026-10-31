# Chapter 10: Administering Terraform As Expert

## Core Idea
Expert Terraform ties the whole stack into one codebase: library-grade custom modules with versioned sharing, HashiCorp Vault dynamic secrets replacing long-lived credentials, and Kubernetes (AKS) managed from network resources up through workloads via the Kubernetes/AKS providers.

## Frameworks Introduced
- **Custom Module Creation Method** (from sprawl to library):
  1. **Identify reusable blocks** — anything you copy/modify repeatedly (standard VM setup: NIC + public IP + SG + VM) is a module candidate
  2. **Set up module directory** — `modules/<name>/{main.tf, variables.tf, outputs.tf}`
  3. **Define contract** — typed variables (mark secrets `sensitive = true`), defaults for optional inputs, outputs for IDs/IPs
  4. **Reference locally**, then distribute via `git::` source with version ref (`?ref=v1.2.0`) for teams
- **Dynamic Secrets Pattern (Vault)**: static .tfvars credentials leak, stagnate, and land in logs; Vault issues short-lived auto-expiring credentials at runtime
  - `vault secrets enable azure` → `vault write azure/config` → define roles mapping to Azure permissions → `vault read azure/creds/<role>` yields ephemeral Contributor credentials that Vault *deletes* (including the service principal) at lease expiry
  - Integration: local-exec calling Vault CLI, or environment-injection at apply time
- **Kubernetes-as-Terraform Pattern**: use the `kubernetes` provider to manage namespaces/deployments/services in HCL
  - Provider wiring: read an existing AKS cluster via `data "azurerm_kubernetes_cluster"`, feed `kube_config[0]` host/client_certificate/client_key/cluster_ca_certificate (base64decoded) into `provider "kubernetes"`
  - Deployment of 3-replica Nginx + ClusterIP service with label selectors, all referencing `kubernetes_namespace.example`
- **Image Metadata Sourcing**: marketplace image = `source_image_reference { publisher, offer, sku, version }`; custom image = `data "azurerm_image"` + `source_image_id`; AWS analogue = `data "aws_ami"` with filter + `most_recent = true`

## Key Concepts
- **`sensitive = true`** on variable: keeps the credential out of plan output — minimum hygiene for any password variable
- **`kubernetes_namespace.metadata[0].name`**: how resources reference the namespace block
- **AKS cluster anatomy**: `dns_prefix` (control-plane endpoint), `default_node_pool` (name/count/vm_size/vnet_subnet_id), `identity { type = "SystemAssigned" }`, `role_based_access_control`, `network_profile` (`network_plugin = "azure"` gives pods VNet IPs; `service_cidr`/`dns_service_ip`/`docker_bridge_cidr` must not collide with subnet space)
- **Cluster credential handoff**: output `kube_config_raw` as `sensitive = true`; `terraform output kube_config` then decode to a KUBECONFIG file; or `az aks get-credentials` merges into `~/.kube/config`
- **AKS create timescale**: several minutes — control plane + node VMs

## Code Examples
```hcl
# AKS cluster with custom VNet integration
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = "my-aks-cluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "my-aks"
  default_node_pool {
    name           = "nodepool1"
    node_count     = 3
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }
  identity { type = "SystemAssigned" }
  role_based_access_control { enabled = true }
  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    dns_service_ip     = "10.100.2.10"
    service_cidr       = "10.100.2.0/24"
    docker_bridge_cidr = "172.17.0.1/16"
  }
}
```
```hcl
# Kubernetes provider fed from the AKS data source
data "azurerm_kubernetes_cluster" "existing_aks" {
  name                = "MyAKS"
  resource_group_name = "MyResourceGroup"
}
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.existing_aks.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.existing_aks.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.existing_aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.existing_aks.kube_config.0.cluster_ca_certificate)
}
```
- **What it demonstrates**: provider chaining — Azure provider builds/reads the cluster, Kubernetes provider consumes its credentials, workloads deploy in the same codebase

## Worked Example
AKS end-to-end: RG (`aks-resource-group`, West Europe) → VNet `10.100.0.0/16` → subnet `10.100.1.0/24` → `azurerm_kubernetes_cluster` (3× Standard_DS2_v2 nodes in that subnet, azure network plugin, RBAC on, SystemAssigned identity) → `terraform apply` (minutes) → `az aks get-credentials` + `kubectl get nodes`, or output the sensitive kube_config. Then in the same root: `provider "kubernetes"` wired from the cluster data → `kubernetes_namespace` "demo-namespace" → `kubernetes_deployment` (nginx:1.19, 3 replicas, app=nginx labels) → `kubernetes_service` (ClusterIP, selector app=nginx, port 80) — verify with `kubectl get pods -n demo-namespace`.

## Anti-patterns
- **Static long-lived credentials in .tfvars or env vars**: they leak, never rotate, and land in logs — prefer Vault dynamic secrets, or at minimum Key Vault (Ch 7)
- **Plaintext admin passwords without `sensitive = true`**: plan output exposes them to everyone reading CI logs
- **Splitting cluster infra and workloads across tools by default**: YAML+kubectl for workloads while Terraform owns only the network splits one environment into two drift-prone sources; the expert pattern chains the providers
- **Unpinned shared module references** for teams: mutable repository heads inject untested changes into everyone's environments
- **Unpinned image versions**: `version = "latest"` is convenient for patches but unpredictable for compliance; pin when reproducibility matters

## Key Takeaways
1. Scan for repeated resource groups-of-three (NIC+PIP+SG+VM patterns) — they become your organization's module library
2. Mark every credential variable `sensitive = true`; it costs nothing and prevents plan-output leaks
3. Vault dynamic secrets make leaked credentials self-limiting: lease expiry deletes the credential and its backing service principal
4. AKS network_profile ranges (`service_cidr`, `docker_bridge_cidr`, `dns_service_ip`) must not collide with your VNet subnets — a common cluster-creation failure
5. Chain providers to manage the full stack: azurerm creates the cluster, kubernetes provider consumes kube_config and deploys workloads
6. Fetch image metadata through data sources rather than literals so image changes are one-block edits
7. The same Terraform workflow (init/plan/apply) now spans cloud resources, clusters, and container workloads — that uniformity is the point

## Connects To
- **Ch 4**: custom modules formalize the module-craft introduced with `azure_vnet`
- **Ch 7**: Key Vault static secrets are the stepping stone to Vault dynamic secrets here
- **Ch 8**: AKS VNet/subnet/network_profile requirements rest on the networking layer
- **Ch 9**: test layers apply to K8s workloads; the KPI of deployment frequency shows up as pipeline maturity