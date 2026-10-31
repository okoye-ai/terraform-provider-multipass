# Chapter 11: Containers and Kubernetes with Terraform

## Core Idea
Terraform can act as a single control plane for both layers of a containerized system: provisioning managed Kubernetes clusters (AKS, GKE, EKS) and then managing in-cluster objects — Deployments, Services, Ingress, Helm releases — through the Kubernetes and Helm providers, so infrastructure and applications share one state, one review process, and one CI/CD pipeline.

## Frameworks Introduced
- **Managed-cluster provisioning playbook (per platform)**: common parameters across clouds are location/region, name, node_pool (or equivalent), and networking; the platforms differ in authentication wiring.
  - When to use: any managed Kubernetes deployment in Azure, GCP, or AWS.
  - How (per the author's matrix): Azure/AKS — provider `azurerm`, key params `resource_group_name`, `dns_prefix`, `default_node_pool`, `identity`; auth via `kube_config_raw` or Azure CLI. GCP/GKE — provider `google`, params `project`, `location`, `initial_node_count`, `node_config`; auth via `master_auth` or `gcloud container clusters get-credentials`. AWS/EKS — provider `aws`, params `role_arn`, `vpc_config`, node_group; requires VPC/subnets/IAM roles up front and an `aws_auth` config map post-creation.
- **Node pool, networking, and authentication configuration**: Azure `default_node_pool` with `node_count`/`vm_size`/`enable_auto_scaling`; GCP `node_config` with `machine_type`/`oauth_scopes`/`preemptible`; AWS `eks_node_group` with `scaling_config`/`instance_types`/`ami_type`. Network: `vnet_subnet_id` (Azure), `subnetwork` (GCP), `vpc_config` (AWS), plus pod/service CIDRs and public/private control-plane access.
  - When to use: sizing and connecting clusters to existing networks.
- **Two-layer state separation**: separate state files for the infrastructure layer (clusters, VPCs, IAM) and the Kubernetes layer (Deployments, Services, ConfigMaps, Secrets).
  - When to use: any team-managed Kubernetes environment.
  - How: export `kube_config`/`cluster_endpoint` outputs from the infra module; consume them via `data "terraform_remote_state"` in the Kubernetes configuration; store state remotely (Azure Blob + Table Storage locking, GCS bucket, S3 + DynamoDB locking); detect drift with regular `terraform plan` and reconcile manual `kubectl` changes with `terraform import`.

## Key Concepts
- **Helm**: Kubernetes package manager; packages are **charts** — bundles of YAML manifests with default configs, parameterized via `values.yaml`, versioned for upgrades and rollbacks.
- **`helm_release`**: Terraform resource that installs a chart with stateful tracking — upgrades, rollbacks, and drift detection for Helm releases inside the Terraform workflow.
- **`kubernetes_deployment`**: manages replica sets and rolling updates for a containerized app declaratively.
- **`kubernetes_service`**: exposes pods (`ClusterIP`, `NodePort`, `LoadBalancer`); `LoadBalancer` suits a single standalone app, Ingress suits multi-service routing.
- **Ingress**: edge routing layer for external HTTP(S) — host/path/TLS rules behind one external IP; requires a controller (NGINX, AGIC, ALB, GKE-native) and is heavily tuned via platform-specific **annotations**.
- **Kubernetes internal DNS for service discovery**: services reach each other at names like `api-service.default.svc.cluster.local` — no address wiring needed between microservice modules.
- **Kubeconfig handoff**: cluster modules output `kube_config_raw` (mark it `sensitive`); retrieved with `terraform output -raw kube_config > ~/.kube/config-file` and passed to `provider "kubernetes"` via `config_path`.
- **Microservices decomposition (author's recipe)**: frontend (Deployment + LoadBalancer/Ingress), backend API (Deployment + ClusterIP), data layer (StatefulSets or external services; credentials via Secrets); each service in its own Terraform module, linked by variables/outputs and `depends_on`.

## Recipes in this chapter
- **Recipe 61: Provision an AKS cluster with Terraform** — AKS with `SystemAssigned` identity, default node pool from variables, sensitive `kube_config_raw` output.
- **Recipe 62: Deploy a Kubernetes deployment via Terraform** — namespace + 2-replica NGINX Deployment + LoadBalancer Service against the saved kubeconfig.
- **Recipe 63: Terraform Helm provider example** — Bitnami WordPress chart (v15.2.5) with inline `set` blocks for service type and credentials.
- **Recipe 64: Provisioning a GKE cluster** — `google_container_cluster` with `initial_node_count`, `node_config.machine_type`, `oauth_scopes`; kubectl via `gcloud container clusters get-credentials`.
- **Recipe 65: Configuring Kubernetes Ingress** — echo-server Deployment plus an NGINX Ingress Controller installed with `kubectl apply -f` (controller v1.10.0, `--validate=false`) exposing the app.
- **Recipe 66: Provisioning an EKS cluster** — `terraform-aws-modules/vpc/aws` (v5.1.0) + `terraform-aws-modules/eks/aws` (v20.8.4, cluster v1.29) with a managed node group auto-scaling 1–3 `t3.medium`.

## Anti-patterns
- **Hard-coding kubeconfig or cluster addresses in the Kubernetes layer**: pull `cluster_endpoint`/`client_cert`/`client_key` from `terraform_remote_state` outputs instead.
- **One monolithic state for clusters and workloads**: dual-layer state in one file increases blast radius; split infrastructure state from Kubernetes state.
- **Manual `kubectl` edits left unreconciled**: causes drift; if unavoidable, follow with `terraform import` and detect drift with regular `terraform plan`.
- **Exposing every service with its own LoadBalancer**: prefer a single Ingress controller for centralized routing, SSL termination, and one external IP.
- **Mixing ad-hoc scripts and manual steps with Terraform for cluster management**: the chapter's premise is reducing toolchain fragmentation — govern clusters and workloads with the same VCS, review, and CI/CD processes.

## Code Examples
Remote-state-fed Kubernetes provider (the two-layer state pattern):
```hcl
data "terraform_remote_state" "aks" {
  backend = "azurerm"
  config = {
    storage_account_name = "tfstateprod"
    container_name       = "tfstate"
    key                  = "aks-infra.tfstate"
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.aks.outputs.cluster_endpoint
  client_certificate     = base64decode(data.terraform_remote_state.aks.outputs.client_cert)
  client_key             = base64decode(data.terraform_remote_state.aks.outputs.client_key)
  cluster_ca_certificate = base64decode(data.terraform_remote_state.aks.outputs.cluster_ca)
}
```
- **What it demonstrates**: decoupling the cluster module from the workload module via remote state outputs — the chapter's canonical state-sharing pattern.

Declarative Helm release:
```hcl
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "nginx" {
  name             = "nginx"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "nginx"
  version          = "13.2.21"     # pin chart versions for reproducible deploys
  namespace        = "nginx"
  create_namespace = true
  values = [
    file("nginx-values.yaml")
  ]
}
```
- **What it demonstrates**: Helm's ecosystem (charts, `values.yaml` overrides, versioning) brought under Terraform state for upgrades, rollbacks, and drift detection.

## Reference Tables
Platform comparison for cluster provisioning (assembled from the chapter's per-platform lists):

| Dimension | Azure AKS | Google GKE | AWS EKS |
|---|---|---|---|
| Provider | `azurerm` | `google` | `aws` |
| Key cluster params | `resource_group_name`, `dns_prefix`, `default_node_pool`, `identity` | `project`, `location`, `initial_node_count`, `node_config` | `role_arn`, `vpc_config`, node_group |
| Networking | `vnet_subnet_id` | `network`, `subnetwork`, `ip_allocation_policy` | VPC/subnets/IAM set up first |
| Node pool config | `node_count`, `vm_size`, `enable_auto_scaling` | `machine_type`, `oauth_scopes`, `preemptible` | `scaling_config`, `instance_types`, `ami_type` |
| Auth to K8s API | `kube_config_raw` / Azure CLI | `master_auth` / `gcloud container clusters get-credentials` | `aws eks update-kubeconfig` |
| Ingress options | NGINX Controller or AGIC; Key Vault CSI for TLS | GKE-native controller, Google-managed certs, Cloud Armor/CDN | AWS Load Balancer Controller (ALB) or NGINX |
| Platform extras | AGIC, Key Vault CSI Driver, Azure Monitor | Cloud SQL proxy sidecar, Workload Identity, Anthos Config Connector | EBS/EFS CSI, AWS Load Balancer Controller, Karpenter |

Key Ingress annotations by platform: AWS `service.beta.kubernetes.io/aws-load-balancer-type` (`nlb`/`external`), `alb.ingress.kubernetes.io/scheme` and `.../target-type`; Azure `kubernetes.io/ingress.class = azure/application-gateway`, `appgw.ingress.kubernetes.io/backend-path-prefix`; GCP `kubernetes.io/ingress.global-static-ip-name`, `networking.gke.io/managed-certificates`.

## Worked Example
Chef's Special — multi-tier microservices on AKS (three courses):

1. **Appetizer (infrastructure)**: `azurerm_resource_group.rg` + `azurerm_kubernetes_cluster.aks` (`dns_prefix = "chef"`, node pool 2x `standard_a2_v2`, `identity { type = "SystemAssigned" }`, `depends_on = [azurerm_resource_group.rg]`). Retrieve credentials: `terraform output -raw kubeconfig > ~/.kube/terraform-aks-config`, then `kubectl get nodes` to verify.
2. **Main course (microservices)**: three interconnecting Deployments appended to `main.tf` — frontend (`nginxdemos/hello`), backend API (ClusterIP service), Redis store — each with its own `kubernetes_deployment` and `kubernetes_service`, discovering each other via internal DNS. Verify with `kubectl get pods` and `kubectl get svc`.
3. **Dessert (Ingress)**: install the NGINX Ingress Controller (`kubectl apply -f .../controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml --validate=false`), then declare a `kubernetes_ingress_v1` rule for `/` (`path_type = "Prefix"`, backend `service { name = kubernetes_service.frontend.metadata[0].name, port { number = 80 } }`, annotation `kubernetes.io/ingress.class = "nginx"`). After apply, `kubectl get ingress` yields the external IP; browsing it reaches the frontend.

Result: one `terraform apply` lifecycle spanning cluster, three-tier workload, and public routing — the blueprint other teams or environments replicate.

## Key Takeaways
1. Use one Terraform workflow for both cloud and in-cluster resources; the Kubernetes provider works unchanged across AKS, GKE, and EKS given correct kubeconfig/context.
2. Split state: infrastructure module outputs (kubeconfig, endpoint, certs) feed `data "terraform_remote_state"` into the Kubernetes-layer configuration.
3. Always mark kubeconfig outputs `sensitive` and retrieve them with `terraform output -raw`.
4. Reach for `kubernetes_service` of type LoadBalancer only for standalone apps; use Ingress behind a controller for multi-service routing, TLS, and multi-tenant access.
5. Pin Helm chart versions and pass overrides via `values = [file(...)]` or `set` blocks so releases remain reproducible and rollback-capable.
6. Structure microservices as one Terraform module per service, wiring them with outputs, references, and `depends_on`, with Secrets for credentials.
7. On EKS, expect the most setup (VPC, subnets, IAM roles before the cluster; `aws_auth` config map after); use the `terraform-aws-modules` VPC and EKS modules rather than raw resources.

## Connects To
- **Ch 10**: the cluster and workload configs reuse that chapter's meta-arguments, conditionals, locals naming, and workspaces for environment separation.
- **Ch 12**: these Terraform/Kubernetes configurations are the artifact the testing and CI/CD chapter protects — `terraform plan` gates, Checkov/TFLint scans, and GitHub Actions apply flows.