# Chapter 7: Working with Multiple Providers

## Core Idea
Terraform Core is a Go binary that delegates all platform work to provider plugins (installed via `terraform init`, configured via `required_providers` + `provider` blocks); to deploy across multiple regions, accounts, or clouds you use multiple copies of the same provider via `alias`/`providers` maps — but in production, the real answer is to keep every provider isolated in its own module to limit blast radius, not to pile providers into one module.

## Frameworks Introduced

### 1. Terraform Core vs. Providers (plugin architecture)
- **When to use**: whenever you need to reason about how provider installs, versions, and authentication actually work.
- **How**: Core (CLI, HCL parser, dependency graph, state) communicates with provider plugins over RPC; plugins talk to their platforms over the network. Each provider claims a prefix (`aws_`, `azurerm_`, `kubernetes_`), maintained mostly by the platform vendor (AWS employees maintain the AWS Provider). Terraform reads `required_providers` to know source + version; without it, `terraform init` naively assumes `registry.terraform.io/hashicorp/<local-name>` and installs the latest version.

### 2. Required Providers Block & Version Pinning
- **When to use**: always in production code — any non-hashicorp-namespace provider, any version control, and every reusable module (the `providers` map keys must match the module's `required_providers` local names).
- **How**: `terraform { required_providers { <LOCAL_NAME> = { source = "[HOSTNAME/]NAMESPACE/TYPE", version = "<constraint>" } } }`. Source format: hostname optional (defaults to public Registry), namespace (usually company), type (usually the preferred local name). Use preferred local names in almost all cases; local names exist to disambiguate same-named providers.

### 3. Provider Aliases (multiple copies of the same provider)
- **When to use**: sparingly — only when infrastructure across aliased providers is truly coupled and always deployed together. Good fits: TLS certs in us-east-1 for CloudFront, GuardDuty-style "deploy in every region" services, and multiple providers authenticating differently (e.g., different accounts).
- **How**: add `alias = "<name>"` to each `provider` block; then select with `provider = aws.<alias>` (singular) on resources and data sources, or the plural map `providers = { aws = aws.<alias> }` on modules.

### 4. Multi-Region Deployment
- **When to use**: cross-region coupled resources (CDN + regional TLS cert); otherwise prefer separate modules per region.
- **How**: one provider block per region with distinct aliases; look up region-specific values (e.g., AMI IDs) with aliased data sources (`data "aws_ami"` with `provider = aws.region_1`) instead of hardcoding AMI IDs. Warning: multiregion is hard (latency, one-writer vs multi-writer, unique IDs, data regulations) — aliases alone don't solve active-active. Warning 2: a module spanning two regions **fails during a regional outage**, exactly when you most need to run plan/apply; separate modules per region minimize blast radius.

### 5. Multi-Account Deployment (isolation, authn/authz, auditing)
- **When to use**: production; separate accounts per environment for isolation (blast radius), fine-grained permissions, and consolidated billing/audit trails (via AWS Organizations).
- **How**: use AWS Organizations to create child accounts (root user needs a unique email — Gmail `+suffix` aliases work; keep default `OrganizationAccountAccessRole`; billing rolls up to parent). Developers keep ONE IAM user profile and cross accounts by assuming IAM roles — per-developer IAM users in every account is an antipattern. In Terraform, alias a provider and add an `assume_role { role_arn = "arn:aws:iam::<ID>:role/<ROLE>" }` block; verify with `data "aws_caller_identity"`. Cross-account roles are double opt-in: the target role's trust policy needs `sts:AssumeRole` from the source account AND your source user needs `sts:AssumeRole` on the role.

### 6. Reusable Modules with Multiple Providers (configuration aliases)
- **When to use**: any reusable module that needs more than one provider configuration.
- **How**: never define `provider` blocks inside reusable modules (antipattern: module would control ~50 AWS config options → configuration, duplication, and performance problems — e.g., 125 provider blocks = 125 provider processes thrashing CPU on RPC/API calls). Instead declare **configuration aliases** in the module's `required_providers` (`configuration_aliases = [aws.parent, aws.child]`), reference them with `provider = aws.<alias>` inside the module, and force callers to satisfy the map. Root modules own all provider blocks and inject them.

### 7. Multiple Different Providers Together (EKS + Kubernetes)
- **When to use**: when a second provider manages a layer atop the first (Kubernetes is effectively its own cloud).
- **How**: EKS cluster via the AWS provider (IAM roles for control plane + managed node group, `aws_eks_cluster`, `aws_eks_node_group`, Default VPC data sources); app via the Kubernetes provider authenticated with `host`, `cluster_ca_certificate` (base64decoded), and a token from `data "aws_eks_cluster_auth"`. Multicloud in one module is almost always wrong — "multi-cloud is the worst practice"; manage each cloud in its own module (see Terratest examples for cross-cloud equivalents).

## Key Concepts
- **Terraform Core**: the Go binary providing CLI, HCL parsing/interpeter, dependency graph, and state read/write.
- **Provider (plugin)**: a Go plugin implementing a fixed interface, installed/execute by Core via RPC, managing one platform; claims a resource/data-source prefix.
- **`required_providers`**: `terraform`-block mapping of local names to `source` URLs and `version` constraints; the contract a module makes about which providers it needs.
- **Local name**: the module-unique key for a provider (prefer the official preferred name, e.g. `aws`).
- **Source URL**: `[HOSTNAME/]NAMESPACE/TYPE`; hostname omitted = public Terraform Registry.
- **Provider alias**: `alias = "<name>"` on a `provider` block, creating an extra named configuration addressed as `aws.<alias>`.
- **Configuration alias**: an alias declared in `required_providers` (`configuration_aliases`) that creates no provider but forces callers to pass one.
- **`provider` param vs `providers` map**: singular on resources/data sources (each deploys into exactly one provider); plural map on modules (keys = the module's `required_providers` local/config names).
- **`assume_role`**: provider block that authenticates to another AWS account via IAM role ARN.
- **Reusable vs root module**: reusable = low-level building block, no provider blocks, no apply; root = the module you run `apply` on; owns provider blocks.
- **Reconciliation loop**: Kubernetes continuously nudges actual cluster state toward the intent recorded in objects (Deployments, Services).
- **k8s Deployment / Service / Pod**: declarative app manager (replicas, rollout strategy) / load balancer exposing the app / group of containers scheduled together.

## Mental Models
- Use **aliases** when infrastructure across two provider configurations is truly coupled and always deployed together; use **separate modules** (isolation/blast radius) for everything else — regions, accounts, clouds, and cluster-vs-app.
- Use **configuration aliases + providers map** when building a reusable module: the module declares *which* providers it needs, the root module decides *how* they're configured.
- Treat **Kubernetes as a cloud of its own** (apps, networks, data stores, LBs, secrets) — so EKS+Kubernetes is both a multi-provider and multicloud exercise; the same isolation rules apply.
- Think **"provider blocks live in the root module only"**: one definition, injected into every reusable module, no copy-paste of ~50 auth/region/endpoint settings.

## Anti-patterns
- **Omitting `required_providers`**: `terraform init` silently installs the *latest* `hashicorp/<name>` — non-reproducible; always pin.
- **Hardcoding region-specific IDs** (e.g., AMI IDs) per region instead of aliased `data "aws_ami"` lookups.
- **A module spanning regions with aliases**: works until one region is down — then plan/apply fail exactly during the outage you built redundancy for.
- **`provider` blocks inside reusable modules**: hoards ~50 provider settings as variables, forces duplication across callers, and spawns excess provider processes (real case: 125 provider blocks → 20-minute plans, CPU thrashing, intermittent API failures).
- **Multi-cloud in a single module** ("multi-cloud is the worst practice").
- **Creating a provider's credentials and consuming resources in the same module** (e.g., EKS cluster + Kubernetes resources together): Terraform evaluates provider blocks vs. resources in an order that yields intermittent, hard-to-debug errors — the Kubernetes provider docs explicitly recommend against it (the `aws_eks_cluster_auth` dependency is "a bit of a hack").
- **Separate IAM user profiles per account** per developer: multiple credential sets to manage; use one identity + assumed roles.
- **Unset selector/label drift**: Deployment and Service both target Pods purely by `match_labels`/`selector` — reuse a `locals` block or they silently desync.

## Code Examples

Pinned provider (always include this):
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
```

Aliases selected on resources and data sources:
```hcl
provider "aws" {
  region = "us-west-1"
  alias  = "replica"
}

data "aws_ami" "ubuntu_region_2" {
  provider    = aws.region_2
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
```

Cross-account via assume_role:
```hcl
provider "aws" {
  region = "us-east-2"
  alias  = "child"

  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
  }
}
```

Reusable module with configuration aliases:
```hcl
# In the reusable module: declare, don't configure
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 4.0"
      configuration_aliases = [aws.parent, aws.child]
    }
  }
}

data "aws_caller_identity" "child" {
  provider = aws.child
}
```

Provider injection into modules (root module):
```hcl
module "mysql_replica" {
  source = "../../../../modules/data-stores/mysql"

  providers = {
    aws = aws.replica
  }

  replicate_source_db = module.mysql_primary.arn
}
```

## Reference Tables

| Scenario | Mechanism | Module guidance |
|---|---|---|
| Multiple regions | `alias` per region + `provider = aws.<alias>` | Separate module per region (blast radius) |
| Multiple accounts | `alias` + `assume_role { role_arn }` | Generally avoid cross-account modules |
| TLS cert for CloudFront | alias hardcoded to `us-east-1` | Legit alias use case |
| Every-region services (GuardDuty) | aliased provider per region in one module | Legit but watch provider count |
| Reusable module, multi-provider | `configuration_aliases` in `required_providers` | Callers must pass full `providers` map |
| EKS + app | AWS + Kubernetes providers | Cluster module first, app module after |

Do's / don'ts for module use of providers:
- **DO** pin `version` in every `required_providers`; **DON'T** rely on implicit hashicorp/latest default.
- **DO** keep provider blocks in root modules only; **DON'T** define them in reusable modules.
- **DO** make `providers` map keys match the module's `required_providers` local names (missing keys error); **DON'T** partially populate the map.
- **DON'T** authenticate one provider from resources created in the same module that uses it.

## Worked Example
Deploy a Dockerized app (`training/webapp`) to EKS, two providers in one root module (learning example; warned against for production).

1. **Docker baseline**: `docker run -it ubuntu:20.04 bash` → containers are userspace-isolated (filesystem + network); `-p 5000:5000` publishes a port.
2. **`modules/services/eks-cluster`** (AWS provider): IAM role for the control plane (trust `eks.amazonaws.com`, attach `AmazonEKSClusterPolicy`), Default VPC/subnets data sources, `aws_eks_cluster` (name, role_arn, version, subnet_ids, `depends_on` = policy attachment), then a node-group role (trust `ec2.amazonaws.com`; attach `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`) and `aws_eks_node_group` with `scaling_config { min/max/desired }` and `instance_types`. Outputs: cluster name, ARN, endpoint, certificate_authority.
3. **`modules/services/k8s-app`** (Kubernetes provider, `~> 2.0`): `kubernetes_deployment` with metadata, `spec.replicas`, Pod Template (`template.metadata.labels = local.pod_labels`, `container` with name/image/`port`/`dynamic "env"`), and `selector { match_labels }`; plus `kubernetes_service` (`type = "LoadBalancer"`, port 80 → `target_port`, `selector = local.pod_labels`). Output `service_endpoint` extracted from the nested `status` object with `try(...)`.
4. **Root module** (`examples/kubernetes-eks`):
```hcl
provider "aws" {
  region = "us-east-2"
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(
    module.eks_cluster.cluster_certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.cluster.token
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.cluster_name
}

module "simple_webapp" {
  source         = "../../modules/services/k8s-app"
  name           = "simple-webapp"
  image          = "training/webapp"
  replicas       = 2
  container_port = 5000
  environment_variables = {
    PROVIDER = "Terraform"
  }
  depends_on = [module.eks_cluster]
}
```
5. **Result**: `apply` (EKS takes 10–20 min) yields `service_endpoint = "http://774696355.us-east-2.elb.amazonaws.com"` → `curl` → `Hello Terraform!`. Changing `PROVIDER = "Readers"` and re-running gives a rolling update → `Hello Readers!`. Inspect with `aws eks update-kubeconfig --region us-east-2 --name <cluster>` then `kubectl get deployments/pods/services`; killing a container shows auto-healing (replacement replica). The same k8s-app module ran unchanged against local Docker Desktop (`config_path`/`config_context = "docker-desktop"`) — Kubernetes portability in action.

## Key Takeaways
- Always declare `required_providers` with an explicit `source` and `version` constraint; the implicit hashicorp/latest default is acceptable only for throwaway experiments.
- `alias` creates a named copy of a provider; select it with `provider = aws.<alias>` on resources/data sources and with a `providers` map (keys = module local names) on modules.
- Use aliases sparingly: only for truly coupled infrastructure (CloudFront certs in us-east-1, every-region services, distinct auth). Otherwise separate modules per region/account/cloud — one region's outage can break a cross-region module's plan/apply at the worst time.
- Keep `provider` blocks exclusively in root modules; reusable modules declare needs via `configuration_aliases` and callers inject configurations. This avoids 50-variable bloat, copy-paste auth, and provider-process storms.
- Look up region-specific values (AMI IDs) with aliased data sources rather than hardcoding.
- Multi-account = AWS Organizations + assumed IAM roles (`assume_role`), one identity per developer, double opt-in trust both directions.
- Never create a provider's credentials/cluster and the resources that consume them in the same module (EKS + Kubernetes app): the Kubernetes provider docs warn of intermittent, unpredictable errors; deploy the cluster module first, then app modules after.

## Connects To
- **Ch. 2** (providers introduced, IAM/assumed permissions background) and **Ch. 3** (reusable vs root modules, module isolation/blast radius, environment separation principle reused here).
- **Ch. 5** (dynamic blocks/`for_each` used for container `env`), **Ch. 6** (passing DB secrets as environment variables), and forward to **Ch. 8** (version pinning details, production-grade module design this chapter's do's/don'ts serve) and **Ch. 9** (Terratest examples folder holds the cross-cloud AWS/Azure/GCP equivalents referenced here).