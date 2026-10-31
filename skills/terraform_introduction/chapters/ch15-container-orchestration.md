# Chapter 15: Terraform for Container Orchestration

## Core Idea
Terraform manages clusters (via cloud providers like DOKS/EKS/AKS/GKE) and Kubernetes objects (via the Kubernetes provider) with the standard block syntax.

## Frameworks Introduced
- **Two-layer Kubernetes management**: Terraform's `digitalocean_kubernetes_cluster` (etc.) provisions the cluster; the `kubernetes` provider manages namespaces/deployments/services/ingresses inside it
  - How: cluster via your cloud provider block with a `node_pool`; K8s objects via the Kubernetes provider reading `config_path = "~/.kube/config"`

## Key Concepts
- **Kubernetes provider**: manages K8s resources like any other infrastructure
- **`kubernetes_namespace` / `kubernetes_deployment`**: object types mirroring K8s YAML structure in HCL
- **DOKS**: DigitalOcean's managed Kubernetes — a cluster resource plus version slugs from `doctl kubernetes options versions`

## Mental Models
- **K8s YAML becomes HCL blocks**: metadata/spec/container nesting translates block-for-block — if you can read a Deployment manifest, you can write it in Terraform.

## Code Examples *(technical)*
```hcl
resource "digitalocean_kubernetes_cluster" "cluster" {
  name   = "doks-cluster"
  region = "nyc1"
  node_pool {
    name       = "default"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = "1.22.8-do.1"
}
```
- **What it demonstrates**: a managed cluster with a 3-node pool; the version comment shows the doctl lookup ritual.

## Key Takeaways
1. Cluster creation and in-cluster objects are two different providers — plan which layer Terraform owns.
2. Always look up current K8s version slugs before pinning the cluster `version`.
3. The full list of manage-able Kubernetes objects is in the Kubernetes provider docs.

## Connects To
- **Ch 14**: serverless and K8s are both "extra resource types" on the same workflow
- **Ch 10**: nested provider blocks (node_pool, container) are the kind of nesting dynamic blocks generalize