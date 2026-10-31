# Chapter 2: Terraform HCL components

## Core Idea
Everything in Terraform HCL is a block — the language has 12 block types, and `resource` blocks are the point of it all: you are the systems architect writing blueprints, and Terraform is the construction crew that interprets them.

## Frameworks Introduced
- **Block anatomy**: every block has a type, labels, arguments, subblocks, and exported attributes — `type "label" { argument = value; subblock { ... } }`.
  - When to use: whenever reading or writing any HCL; the structure is identical for all 12 block types.
  - How: type first (defines how the rest is interpreted), labels in quotes, then braces containing arguments (`name = value`, usable once) and subblocks (no `=`, usable repeatedly).
- **Label strategies** (the main differentiator between block types):
  - **No labels**: `terraform` and `locals` — one `terraform` block per module, so no name needed.
  - **Single label**: `variable`, `provider`, `output`, `module` — arbitrary except `provider`, whose label must match a key in `required_providers`.
  - **Subtype + label**: `data` and `resource` — first label is the subtype (resource/data source type from the provider), second is your unique identifier.
- **The 12 Terraform block types**: `terraform` (workspace settings), `provider` (vendor settings), `resource` (creates/updates infrastructure), `data` (read-only lookups), `variable` (external inputs), `locals` (module-scoped variables), `module` (reusable code), `import`, `moved`, `removed` (refactoring/state-adjacency), `check` (validate deployed infra), `output` (share data out).
  - When to use: as the inventory of what each piece of a `.tf` file is doing.
  - How: `resource` creates infrastructure; nearly everything else exists to feed, configure, organize, or extract from resource blocks.
- **Provider aliases**: one `provider` block per connection to a vendor; the unlabeled-alias block is the default, aliased ones are opt-in via the `provider` meta argument (`provider = aws.west`).
  - When to use: multi-region or multi-account deployments of the same vendor in one configuration.
- **Meta arguments**: arguments every `data`/`resource`/`module` block always has, built into the language itself (`provider`, `lifecycle`, `depends_on`, `count`/`for_each`) — they change how Terraform plans, not the infrastructure.
  - How: they must usually be literal or known at plan time; they cannot depend on attributes only known after apply.

## Key Concepts
- **Reference string**: the unique identifier formed by block type + labels (e.g., `resource.aws_instance.hello_world`, `data.aws_vpc.default`, `var.instance_type`); the prefix is dropped when context forces the block type (e.g., `depends_on`).
- **`required_providers` vs. `provider`**: the former (inside `terraform { }`) tells Terraform *what to install* (source + version); the latter *configures* the installed provider (region, credentials).
- **Data source**: a read-only block that searches and filters existing data from its provider and exposes it as attributes; it can never create or modify.
- **Attribute**: what a block exports; resource/data blocks automatically expose all their arguments plus read-only computed attributes (e.g., `arn`, `instance_state`) populated by the provider after plan/apply. Subblock contents are NOT exposed as attributes.
- **`lifecycle` subblock**: container for per-resource management arguments (`create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by`); declared at most once per resource.
- **`depends_on`**: explicit dependency between resources that share no attribute flow (e.g., NAT Gateway needs the Internet Gateway up though it takes no value from it); on a `module` block it propagates to all resources inside.
- **`import` / `moved` / `removed` blocks**: v1.5/v1.5/v1.7 additions — codify adoption of existing resources, rename/move within a project, and mark resources as gone-from-code-without-destroying.
- **Lock file (`.terraform.lock.hcl`)**: records provider selections made at init; commit it to guarantee the same selections later.

## Mental Models
- Use **"blocks are nouns; arguments and subblocks are adjectives"** when designing HCL — you create nouns and describe/link them.
- Use **"resource blocks are the point; everything else supports them"** to decide where complexity belongs.
- Use **"providers are like vendor SDKs"** — install at a pinned version, configure credentials/region, possible multiple clients (aliases), one per vendor/platform.
- Use **"code order is meaningless; the dependency graph is the execution order"** — file layout is organization, not sequencing.

## Anti-patterns
- **Skipping `required_providers`** for HashiCorp-namespace providers: Terraform will infer `hashicorp/<localname>`, but you lose version pinning, so upgrades can silently break code.
- **Hardcoding configuration values** (AMI ID, subnet ID, region): hardcoding an AMI forces code republishing on each patch release; a hardcoded subnet makes the code runnable in exactly one account. Prefer data lookups and variables to keep code portable.
- **`prevent_destroy = true` as routine protection**: takes only literal values (can't differ per environment), blocks tearing down temporary dev environments, and silently vanishes when the resource block itself is deleted. Prefer `ignore_changes` (which still allows explicit destroy plans).
- **Provider blocks in submodules/reusable modules**: providers are configured only at root level for the whole workspace; reusable modules keep `required_providers` but delete `provider` blocks.
- **Ignoring style conventions**: order breaks nothing (Terraform ignores style when planning), but `terraform fmt` and the convention (meta arguments top, then arguments with aligned equals, then subblocks, then meta-argument subblocks like `lifecycle` last) make teams able to read each other's code.

## Code Examples
- **What it demonstrates**: the Hello World project split by concern — providers.tf (settings), lookups.tf (data sources), main.tf (resource). Note the portable pattern: no hardcoded AMI or subnet.
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" { region = "us-east-1" }  # root modules only

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
data "aws_ami" "ubuntu" {
  owners      = ["099720109477"]   # Canonical's AWS account
  most_recent = true               # always latest bug/security fixes
  filter { name = "virtualization-type"; values = ["hvm"] }
  filter { name = "name"; values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"] }
}

resource "aws_instance" "hello_world" {
  ami           = data.aws_ami.ubuntu.id
  subnet_id     = data.aws_subnets.default.ids[0]
  instance_type = "t3.micro"   # cheapest by default; becomes a variable in ch3
}
```

- **What it demonstrates**: the two lifecycle patterns used most in practice — ignore a replacement-forcing attribute (`ami`) and trigger replacement from a change elsewhere via a `null_resource` (whose `triggers` argument inspired `replace_triggered_by`).
```hcl
resource "null_resource" "replace_instance" {
  triggers = { instance_type = var.instance_type }
}
resource "aws_instance" "hello_world" {
  ami           = data.aws_ami.ubuntu.id
  subnet_id     = data.aws_subnets.default.ids[0]
  instance_type = var.instance_type

  lifecycle {
    ignore_changes       = [ami]     # new AMIs won't replace running instances
    replace_triggered_by = [null_resource.replace_instance]  # type change -> replace, not in-place update
  }
}
```

- **What it demonstrates**: explicit dependency for resources with a logical ordering need but no attribute flow; and provider aliases for a second region.
```hcl
resource "aws_nat_gateway" "example" {
  subnet_id = aws_subnet.example.id
  depends_on = [aws_internet_gateway.main]   # NAT can't launch without the IGW
}
```

## Reference Tables
**Block references (table 2.1):**

| Block type | First label / subtype | Second label | Full reference |
|---|---|---|---|
| resource | aws_instance | hello_world | resource.aws_instance.hello_world |
| data | aws_vpc | default | data.aws_vpc.default |
| variable | instance_type | — | var.instance_type |

**Meta arguments from this chapter:**

| Meta argument | Purpose | Notes |
|---|---|---|
| provider | Select a provider alias | Optional; needed only with multiple connections to one vendor |
| depends_on | Explicit ordering | Takes block references, not attributes; inherited by everything in a module block |
| lifecycle.create_before_destroy | Replacement order | Good default is destroy-first; create-first errors on non-shareable names (IAM roles, EIPs) |
| lifecycle.ignore_changes | Ignore attribute changes | `ignore_changes = all` (no brackets) makes the resource read-only after creation |
| lifecycle.replace_triggered_by | Force replacement on external change | Takes resource or resource-attribute references — not variables |

**Module block meta arguments:** `source` (required: registry, filesystem path, or Git), `version` (registry version range), `providers` (which aliases get passed down).

## Worked Example
The Hello World AWS instance, walked from research to apply: (1) Research what an `aws_instance` minimally needs — `ami`, `instance_type`, and `subnet_id` — via the provider docs. (2) Create the project (git repo + `main.tf`, `lookups.tf`, `providers.tf`; any `.tf` filename works, names are for humans). (3) Configure the provider in `providers.tf` (listing 2.1). (4) Replace hardcoding with lookups in `lookups.tf`: default VPC -> its subnets -> latest Canonical/Ubuntu AMI, cascading because the subnets filter consumes `data.aws_vpc.default.id`. (5) Define the resource in `main.tf` mapping attributes, returning the `arn` as an output. (6) Configure credentials the AWS way (`aws configure`), then `init` (lock file created) -> review `plan` (1 to add) -> `apply` (instance i-01792587739c8e453 in ~12 s). Result: code reusable by any developer, in any account/region, unchanged.

## Key Takeaways
1. Pin provider versions in `required_providers` every time — inference works but can silently break on upgrades.
2. Make code portable: look up dynamic values (latest AMI, default subnets) with data sources instead of hardcoding, and let users override via variables (ch3).
3. Reach for `ignore_changes = [ami]` rather than `prevent_destroy` when the goal is "don't replace my running instance on a new release."
4. Use `depends_on` only when resources must sequence but share no attribute — otherwise let the graph infer.
5. Subblocks repeat and don't take `=`, arguments don't repeat and do; this one syntax distinction resolves the filter-vs-object confusion.
6. Keep `provider` blocks out of reusable modules; configure providers once at the root.
7. Use the `moved` block freely for renames inside projects — it's safe to leave in published modules because it applies to new projects too.

## Connects To
- **Ch 1**: the plan/DAG theory that makes inferred ordering work.
- **Ch 3**: variables and outputs — where module arguments (`instance_type`) and module attributes come from.
- **Ch 4**: expressions and iteration — what can appear to the right of an `=`.
- **Ch 5**: debugging plans and escaping circular dependencies.
- **Ch 9**: `import`/`moved`/`removed` in depth as refactoring tools.
- **Ch 12**: writing your own provider (the gRPC interface).
