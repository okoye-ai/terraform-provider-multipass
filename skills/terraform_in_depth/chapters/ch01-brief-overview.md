# Chapter 1: A brief overview of Terraform

## Core Idea
Terraform is a declarative infrastructure-as-code engine: you describe the *end state* you want in HCL, and Terraform builds a directed acyclic graph (DAG) of actions to bring real infrastructure in line with that description — turning infrastructure into reproducible, versioned, shareable building blocks.

## Frameworks Introduced
- **Infrastructure as Code (IaC)**: a class of technology that lets developers provision infrastructure using software development practices.
  - When to use: whenever infrastructure must be reproducible, reviewable, and shared across teams.
  - How: codify infrastructure in Git (audit trails, branches, PR reviews), lint it, and run it through CI/CD pipelines.
- **Terraform component stack** (core -> provider -> vendor): the Terraform core (inside the CLI) translates HCL into provider calls; each provider wraps one vendor's API; vendors expose resources/data sources.
  - When to use: as the mental map for how any Terraform code reaches real infrastructure.
  - How: read the code -> identify the provider per resource prefix (e.g., `aws_instance` -> AWS provider) -> the provider talks gRPC to the vendor API.
- **Terraform's organizational hierarchy**: state, backends, workspaces.
  - When to use: when reasoning about where a deployment's data lives and how to get multiple deployments (staging, prod, ephemeral feature copies) from one code base.
  - How: a backend tells Terraform where state is stored; a workspace is one deployment of the code base (code + workspace config + its state).
- **The Terraform deployment flow**: Change Desired -> Init -> Plan -> Review -> Apply.
  - When to use: every change, whether run by hand or by a CI/CD system calling the CLI.
  - How: write the change; `init` downloads providers/modules and initializes the backend; `plan` builds the DAG of actions; review the plan output; `apply` executes it.
- **Declarative vs. imperative languages**: declarative languages describe *what the outcome should be*; imperative languages describe *how to do it*.
  - When to use: declarative for infrastructure (no migrations needed, versions move freely); imperative for stepwise logic.
- **TACOS (Terraform Automation and Collaboration Software)**: Terraform-specific CI/CD platforms (HCP Terraform, Terraform Enterprise, Spacelift, Scalr) that wrap the CLI with speculative plans, module publishing on tags, and merge-driven deploys.

## Key Concepts
- **Provider**: a plugin (usually Go, communicating over gRPC) supplying the resources, data sources, and functions for one vendor; effectively a wrapper around a vendor API.
- **State**: the collection of metadata about the resources Terraform manages; every deployment (workspace) has its own state.
- **Backend**: configuration for where a workspace stores its state (local by default; S3, GCS, AzureRM, HTTP, or the enhanced remote/cloud backends).
- **Workspace**: a deployment of a Terraform code base with a specific backend and set of input variables — comparable to one installation of a program.
- **HCL (HashiCorp Configuration Language)**: Terraform's declarative language, designed to be readable by non-experts; shared (in different flavors) by Packer, Nomad, and Consul.
- **DAG (directed acyclic graph)**: the structure of a Terraform plan — an ordered list of actions with no cycles.
- **Plan**: both an action and an output: Terraform's computed series of actions to align real infrastructure with the code.
- **OpenTofu**: the open source fork of Terraform created after HashiCorp's 2023 BSL license change; a superset of the Terraform language, governed under the Linux Foundation.
- **BSL (Business Source License)**: a shared-source license — source is visible but restricted from building competitive hosted products; applies to Terraform >= 1.6.

## Mental Models
- Use **"declarative describes what, imperative describes how"** when explaining or choosing IaC tools: you never write "check if the machine exists, create it if missing" — you just describe the machine.
- Think of **backends as a filesystem and workspaces as saved files** in a desktop program.
- Use **"declarative languages use nouns and adjectives, imperative languages use verbs"** to set expectations about HCL.
- Use **"relationships are inferred from value flow"** for dependency ordering: once you say the application uses a value from the database, "deploy the database first" is already defined — never write explicit ordering you can express by referencing an attribute.

## Anti-patterns
- **Circular dependencies between resources**: a resource cycle (R2 needs R4, R4 needs R3, R3 needs R2) means nothing can launch; DAG-based engines cannot create them without manual workarounds.
- **Manual (ClickOps) provisioning as a practice**: hand-configured machines don't scale and produce systems you can't reproduce.
- **Vendor-specific IaC by default**: CloudFormation-style tools limit you to one vendor; Terraform's provider abstraction exists to avoid this.

## Code Examples
- **What it demonstrates**: the plan phase sees everything — data source reads, the single create action, and `(known after apply)` placeholders are how Terraform marks values that only exist post-apply.
```hcl
data "aws_vpc" "default" { default = true }
data "aws_ami" "ubuntu" { /* read-only lookup */ }

resource "aws_instance" "hello_world" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
}
```

- **What it demonstrates**: dependency inference — the subnets lookup uses an attribute from the VPC lookup, so Terraform orders them automatically with no explicit ordering syntax.
```hcl
data "aws_vpc" "default" {
  default = true
}
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
```

## Reference Tables
**The plan phase's three subphases:**

| Subphase | What happens |
|---|---|
| Refresh | Reads the real state of infrastructure from the vendor (plus data sources) to find drift |
| Compare | Compares refreshed state to what the code says should exist |
| Plan | Builds the DAG of actions (create/change/destroy) to reach the desired end state |

**Terraform vs. OpenTofu decision points:**
- Terraform <= 1.5.7 is the last open source (MPL) version; >= 1.6 is BSL.
- Homebrew and many Linux distros stopped carrying Terraform past 1.5.7; OpenTofu is supported by most open source package managers.
- `tofu` is a drop-in CLI with the same subcommands (aliasing `terraform` -> `tofu` works); OpenTofu is a language superset, so adding fork-only features makes the trip back to Terraform harder; OpenTofu lags Terraform slightly on new features.

## Worked Example
The chapter's end-to-end deployment-flow walkthrough: add one EC2 instance. `terraform init` resolves the `~> 4.0` constraint to aws v4.41.0, installs it (cryptographically signed, so you know who published it), and creates the `.terraform.lock.hcl` lock file — commit it, since it guarantees the same selections on future inits. `terraform plan -out tfplan` first refreshes (reads `data.aws_vpc`, `data.aws_ami`, `data.aws_subnets`), then shows one planned action: `+ resource "aws_instance" "hello_world"` with concrete values (`ami`, `instance_type = "t3.micro"`, `subnet_id`) alongside `(known after apply)` placeholders for `arn`, `id`, and outputs — summarized as `Plan: 1 to add, 0 to change, 0 to destroy`. The reviewed plan file is applied via `terraform apply tfplan`; the created resource gets a unique ID (`id=i-01792587739c8e453`), outputs populate after creation, and `terraform graph` renders the same DAG as a picture.

## Key Takeaways
1. Write for end state, not steps: if ordering can be expressed by passing an attribute from one block to another, never hardcode it with `depends_on`.
2. Commit `.terraform.lock.hcl` — it makes `init` reproducible across machines and CI systems.
3. Apply a saved plan (`terraform apply tfplan`) so exactly what you reviewed is what runs.
4. One code base can produce unlimited deployments: use workspaces for prod/staging/ephemeral environments rather than copied code.
5. Codifying infrastructure into reusable modules spreads improvements across every project consuming them — treat infrastructure like a shared library.
6. Choose Terraform/OpenTofu consciously: OpenTofu is the open source, foundation-governed path; Terraform past 1.5 is BSL with faster feature delivery.

## Connects To
- **Ch 2**: the concrete block types (`resource`, `data`, `provider`, `terraform`) introduced here abstractly.
- **Ch 5**: plans as DAGs in depth, including debugging and surviving unavoidable dependency cycles.
- **Ch 6**: backends and state management.
- **Ch 7 & 8**: CI/CD and TACOS automating the init/plan/apply flow.
- **Kubernetes YAML / Puppet DSL**: the same declarative language class; Terraform's DAG is the IaC expression of the pattern.
