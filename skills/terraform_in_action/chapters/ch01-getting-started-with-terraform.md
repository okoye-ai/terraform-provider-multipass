# Chapter 1: Getting started with Terraform

## Core Idea
Terraform is a declarative, cloud-agnostic infrastructure-as-code provisioning tool — its six distinguishing characteristics (provisioning tool, easy to use, free/open source, declarative, cloud-agnostic, expressive/extensible) are exactly why it beats CloudFormation-style vendor tools and Ansible-style CM tools.

## Frameworks Introduced
- **The Six Characteristics of Terraform**: the competitive-advantage checklist Winkler uses to evaluate any IaC tool
  - When to use: choosing between IaC tools, or explaining Terraform's position in a stack
  - How: score a candidate tool on (1) provisioning vs configuration management, (2) ease of use, (3) free/open source, (4) declarative, (5) cloud-agnostic, (6) expressiveness/extensibility
- **Provisioning vs Configuration Management**: provisioning deploys infrastructure; CM (Ansible, Chef, Puppet, SaltStack) deploys software onto existing servers
  - Use provisioning (Terraform) for infrastructure; you may still need CM, but many orgs drop CM after adopting Terraform
- **Mutable vs Immutable Infrastructure**: CM favors mutable (update existing servers); Terraform favors immutable (infrastructure is disposable)
  - Mental model: reusable vs disposable mentality
- **Declarative vs Imperative**: declarative cares about the destination, not the journey; imperative cares about the journey, not the destination

## Key Concepts
- **HCL**: HashiCorp Configuration Language — human/machine-readable, fully JSON-compatible (1:1 bidirectional conversion); a substitute for XML/JSON configs
- **Terraform core**: the open source (MPL v2.0) engine; Terraform Cloud / Enterprise are paid wrappers for scale, not different engines
- **Provider**: a plugin (binary, written in Go, distributed via the Terraform Registry) that interfaces with external APIs; handles auth, API calls, timeouts, errors (`provider "aws" { ... }`)
- **Resource**: the most important Terraform element; HCL block with type `resource` + 2 labels (`<type>` and `<name>`); type+name form the unique resource identifier
- **Data source**: an unmanaged resource Terraform can read from but doesn't control; declared as `data "<type>" "<name>" { ... }` with query constraint arguments
- **Arguments vs Attributes vs Computed attributes**: inputs passed into a resource (some also readable back); attributes are outputs; computed attributes (e.g. `id`, `arn`) exist only after creation
- **Execution plan**: CLI output describing the actions Terraform intends to perform (`+ create`, `- destroy`, `~ update`); always review before approving
- **terraform.tfstate**: the state file — a JSON file recording all stateful info; never manually edit or delete it

## Reference Tables
| Tool | Provisioning | Easy | Free/OSS | Declarative | Cloud-agnostic | Expressive |
|---|---|---|---|---|---|---|
| Ansible | ✓ | ✓ | | | ✓ | ✓ |
| Chef/Puppet | | ✓ | ✓ | ✓ | ✓ | ✓ |
| SaltStack | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Terraform | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Pulumi | ✓ | | ✓ | | ✓ | ✓ |
| CloudFormation | ✓ | ✓ | | ✓ | ✗ | ✗ |
| GCP DeployMgr / Azure ARM | ✓ | ✓ | | ✓ | ✗ | ✗ |

vs. CloudFormation (inspiration for Terraform): 115 intrinsic functions (CF: 11), for loops (CF: none), 7+ types, pluggable providers, modular.

## Worked Example
"Hello Terraform!" — deploy an EC2 instance with a dynamically looked-up AMI:
```hcl
provider "aws" {
  region = "us-west-2"
}
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  owners = ["099720109477"]     # Canonical's AWS account id
}
resource "aws_instance" "helloworld" {
  ami           = data.aws_ami.ubuntu.id   # chains data source -> resource
  instance_type = "t2.micro"
  tags = { Name = "HelloWorld" }
}
```
Deployment sequence: write configuration files → configure provider → `terraform init` → `terraform apply` (review plan, enter yes) → `terraform show` to verify → `terraform destroy` for cleanup. `terraform destroy` is exactly equivalent to deleting all configuration code and running `terraform apply`.

## Key Takeaways
1. Terraform handles provisioning; CM tools handle configuration — don't conflate the two when picking tools.
2. The deployment workflow is always the same skeleton: write config → init → apply → (show) → destroy.
3. Chain data sources into resources to make deployments dynamic instead of hardcoding values.
4. The `.terraform.lock.hcl` lock file should be committed to version control for reproducible provider selection.
5. State is a plain JSON file (`terraform.tfstate`) tracked by Terraform — treat it as precious.

## Connects To
- **Ch 2**: the resource lifecycle (plan → create → no-op → update → delete) that ch1's apply/destroy commands trigger
- **Ch 11**: writing your own provider in Go
- **Ch 13**: secrets management (provider credentials shouldn't be plaintext)