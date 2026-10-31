# Chapter 5: Container Management with Terraform

## Core Idea
Terraform manages containers across Docker, Kubernetes, and Nomad, but each platform splits into two distinct jobs — deploying the cluster itself and configuring the workloads on it — and the biggest decision in every recipe is whether workload definitions live in YAML (reuse existing manifests) or HCL (full Terraform expression power).

## Frameworks Introduced
- **Local vs. remote Docker image selection**: choose image sourcing per container, not per project.
  - When to use: remote for the latest published version or images not present locally; local (`keep_locally = true`) for a custom image you have built and never pushed, or a locally pinned version.
  - How: declare a `docker_image` per source; set `keep_locally = true` to stop Terraform checking the registry for locally present images. Air-gapped environments the Terraform host cannot reach are out of scope for this method.
- **Cluster deployment vs. cluster configuration separation**: two different Terraform layers for one platform.
  - When to use: whenever you create a cluster and then run workloads on it (the EKS example).
  - How: layer 1 deploys infrastructure via a module (e.g. `terraform-aws-modules/eks/aws`); layer 2 wires a second provider (e.g. `kubernetes`) from layer 1's outputs, then manages in-cluster objects such as `kubernetes_namespace`.
- **EKS authorization chain**: the standard handshake that authorizes Terraform against the cluster API.
  - When to use: every time Terraform must operate on an EKS cluster it did not create in the same config.
  - How: `data "aws_eks_cluster"` for endpoint + CA data, `data "aws_eks_cluster_auth"` for the token, and a `kubernetes` provider with `host`, `cluster_ca_certificate = base64decode(...)`, `token`, and `load_config_file = false`; underlying AWS IAM permissions are still required.
- **YAML-manifest scheduling**: schedule containers by feeding existing YAML into `kubernetes_manifest`.
  - When to use: infrastructure teams already holding YAML manifests, even from non-Terraform IaC.
  - How: `kubernetes_manifest` with `manifest = yamldecode(file("${path.module}/deployment.yaml"))` (Terraform ≥ 0.15, Kubernetes provider ≥ 2.0.0; otherwise define resources directly in HCL).
- **HCL-native scheduling**: define Kubernetes objects with typed Terraform resources.
  - When to use: greenfield configs, or whenever you want variables, functions, and expressions inside definitions.
  - How: use purpose-built resources (`kubernetes_deployment`) with `metadata`/`spec`/`template`/`container` blocks instead of `kubernetes_manifest`.
- **YAML-to-HCL transmutation (k2tf)**: Recipe 5.6's method converts Kubernetes YAML to wrapped HCL without external tools.
  - When to use: migrating YAML estates into HCL-managed `kubernetes_manifest` resources.
  - How: in `terraform console`, `jsonencode({ resource = { kubernetes_manifest = { example = { manifest = yamldecode(file("deployment.yaml")) } } } })`, copy the output, strip the outer braces, and `terraform fmt`; review and test all complex conversions.
- **Additive default-deny NetworkPolicy pattern**: security groups for Pods, with an allowlist posture.
  - When to use: restricting Pod-to-Pod traffic by labels and protocols.
  - How: `kubernetes_network_policy` with `pod_selector`, `policy_types = ["Ingress", "Egress"]`, then `ingress`/`egress` rules; start with default deny, add allow rules, and require a NetworkPolicy-capable CNI (Calico, Cilium, Weave Net).
- **Helm release lifecycle management**: run charts as first-class Terraform resources.
  - When to use: deploying packaged applications (Redis, Prometheus, Grafana) while keeping Terraform state as the record.
  - How: `helm_release` with pinned `version`, and one `set` block per value (or a values file for complex configuration).

## Key Concepts
- **keep_locally**: `docker_image` argument that makes Terraform load a locally present image instead of verifying against the Docker registry.
- **kubernetes_manifest**: dynamic resource that applies an arbitrary manifest map (e.g. from `yamldecode`) to the cluster; the book's recommended way to manage Kubernetes resources in Terraform.
- **Scheduling (Kubernetes sense)**: assigning Pods to nodes via the Kubernetes scheduler — not cron-style timed task execution.
- **kubernetes_deployment**: typed HCL resource for Deployments, covering replicas, selector, pod template, containers, ports, and env.
- **Annotations vs. labels**: annotations attach arbitrary, non-identifying metadata (build info, monitoring config, rollout tracking, tool-specific settings) consumed by tools; labels identify and select objects — the two are not interchangeable.
- **NetworkPolicy additive semantics**: if any policy allows a connection, it is allowed; you cannot deny what another policy permits, and enforcement requires a supporting network plug-in.
- **helm_release**: Terraform resource managing a chart's lifecycle, gaining Terraform state management; `set` blocks pass individual chart values.
- **Nomad job**: Nomad's main unit of work (`job` → `group` → `task`), fed to the Nomad provider's `nomad_job` resource via `jobspec = file(...)`, with its own scheduler distinct from Kubernetes.
- **k2tf**: the tool named for YAML→HCL conversion; the recipe's portable variant uses only `terraform console` with `file`/`yamldecode`/`jsonencode`.

## Mental Models
- Use remote images when you want the newest version or lack the image locally; use local images when running your own unpushed builds or pinned local versions.
- Use YAML manifests (Recipe 5.4) when YAML already exists and Terraform is only the executor; use HCL resources (Recipe 5.5) when definitions should join Terraform's variables, functions, and expressions.
- Use a second provider instance for in-cluster configuration — cluster creation and object creation are separate state layers, never one recipe.
- Use Nomad when mixed microservice, batch, containerized, and noncontainerized workloads share an orchestrator; use Kubernetes for Pod-based standards plus NetworkPolicies and Helm.

## Anti-patterns
- **Pointing the Docker provider at air-gapped registries**: unreachable registries make the provider unusable; choose other deployment strategies matching your security policies.
- **Combining labels and annotations carelessly**: annotations cannot select objects — putting selection metadata there silently breaks selectors.
- **Assuming NetworkPolicies can deny overrides**: additive semantics mean one permissive rule admits traffic everywhere.
- **Unpinned Helm chart versions**: reproducibility dies; always pin `version` and read the chart's own documentation for valid `set` keys.
- **Hardcoding replicas, image tags, and env values**: Recipe 5.8 moves these into `replica_count`/`image_version` variables so environments differ without editing the resource.
- **Plaintext Grafana `adminPassword` or disabled persistence in production**: manage via secrets tooling and enable persistence to avoid data loss.
- **Skipping nonproduction testing**: the chapter repeats it for Deployments, NetworkPolicies, and Nomad jobs — policies and configs easily block necessary traffic.

## Code Examples
- **What it demonstrates**: the EKS authorization chain feeding a Kubernetes provider without a local kubeconfig (Recipe 5.3).

```hcl
provider "aws" {
  region = "<REGION>"
}

data "aws_eks_cluster" "cluster" {
  name = "<CLUSTER_NAME>"
}

data "aws_eks_cluster_auth" "cluster" {
  name = "<CLUSTER_NAME>"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.ca.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}
```

- **What it demonstrates**: scheduling from an existing YAML manifest with `kubernetes_manifest` + `yamldecode` (Recipe 5.4).

```hcl
resource "kubernetes_manifest" "example" {
  provider = kubernetes

  manifest = yamldecode(file("${path.module}/deployment.yaml"))
}
```

- **What it demonstrates**: an additive, label-driven NetworkPolicy scoping a `role=db` Pod to TCP 6379 from `role=frontend` and to `role=replica` (Recipe 5.9).

```hcl
resource "kubernetes_network_policy" "example" {
  metadata {
    name      = "example"
    namespace = "default"
  }

  spec {
    pod_selector {
      match_labels = {
        "role" = "db"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "role" = "frontend"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6379"
      }
    }
  }
}
```

## Reference Tables
| Decision | Remote image | Local image |
|---|---|---|
| Version freshness | Latest published | Pinned local |
| Custom unpushed build | No | Yes |
| `keep_locally` | Not needed | `true` (skips registry check) |
| Air-gapped Terraform host | Unsuitable | Unsuitable — use other strategies |

| Decision | YAML manifests | HCL resources |
|---|---|---|
| Reuse existing team YAML | Yes (`kubernetes_manifest`) | No |
| Terraform vars/functions/expressions | Limited | Full |
| Provider/Terraform requirement | ≥ 0.15, provider ≥ 2.0.0 | Any |
| Consistency with rest of IaC | Mixed | Single language |

HCP-style comparison tables: none in this chapter.

## Worked Example
Recipe 5.11 stands up a monitoring stack from scratch: one `helm` provider (with nested `kubernetes` block) drives two `helm_release` resources. Prometheus deploys from `https://prometheus-community.github.io/helm-charts` pinned at chart `15.10.1` with `server.persistentVolume.enabled = "false"` for simplicity. Grafana deploys from `https://grafana.github.io/helm-charts` at `6.43.1`, configured through `set` blocks: an (insecure, replace-me) `adminPassword`, then four set keys of the form `datasources.datasources\.yaml.datasources[0].name` / `.type` / `.url` / `.access`, defining a Prometheus data source of type `prometheus` pointed at `http://prometheus-server` with `access = "proxy"`. After apply, Prometheus scrapes deployment metrics, you port-forward to the Grafana service, log in with the admin credentials, and build dashboards. Production guidance: enable persistence for both charts, secure the admin password via variables or a secrets manager, and add retention periods, resource limits, ingress rules, and access controls.

## Key Takeaways
1. Separate cluster deployment (module-built EKS) from cluster configuration (kubernetes provider + namespace and workloads); feed the second layer from the first's outputs.
2. Prefer HCL-native resources for new Kubernetes work; keep `kubernetes_manifest` + `yamldecode` as the adapter for YAML you already own — and check the version floor first.
3. Migrate YAML with the Terraform console (`jsonencode`/`yamldecode`), not a toolchain: strip outer braces, `terraform fmt`, then review and test.
4. Design NetworkPolicies default-deny, rely on consistent Pod labels, and remember they are additive and CNI-dependent (Calico, Cilium, Weave Net).
5. Pin every Helm chart version and prefer a values file over a pile of `set` blocks for complex configuration.
6. Parameterize Deployments through variables (`replica_count`, `image_version`) so dev/staging/production differ without resource edits — and validate against production clusters only after nonproduction testing.
7. Nomad's `nomad_job` keeps job specs in Nomad HCL inside Terraform state; its scheduler differs from Kubernetes', so learn Nomad's architecture before relying on placement behavior.

## Connects To
- **Ch 3–4 (Docker/HCL basics)**: the Docker provider, `docker_image`/`docker_container`, and the Terraform console pattern carried into Recipe 5.6 build on earlier console usage.
- **Ch 7 (Secrets)**: the Grafana admin password and Nomad/cluster credentials point at proper secrets management rather than hardcoded values.
- **GitOps / pull-request workflow**: container definitions become reviewable code, which Chapter 6's HCP Terraform automation generalizes.
- **Kubernetes standards**: annotations, labels, and NetworkPolicies map to upstream Kubernetes API concepts; NetworkPolicies additionally require a CNI that enforces them (Calico, Cilium, Weave Net).