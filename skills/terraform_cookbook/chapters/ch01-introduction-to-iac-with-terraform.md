# Chapter 1: Introduction to Infrastructure as Code with Terraform

## Core Idea
Declarative IaC with Terraform shifts the burden of *how* to the tool: you declare the desired end state in HCL, and Terraform computes ordering, dependencies, and idempotence — eliminating snowflake servers and manual console work. Chapter is conceptual/onboarding; hands-on depth comes in later chapters.

## Frameworks Introduced
- **The Three Pillars of Terraform Design** (author's naming: Providers, Resources, State):
  - When to use: as the mental model for explaining how any Terraform configuration works.
  - How: Providers are plugins translating HCL into platform API calls (versioned, downloaded by `terraform init`); Resources are HCL blocks mapping one-to-one to real objects (`resource "azurerm_virtual_machine" "vm" { … }`); State is `terraform.tfstate`, a JSON file recording the mapping between configuration and real infrastructure, enabling incremental plans and remote backends (Terraform Cloud, Azure Storage, S3 + DynamoDB) for locking.
- **Five Benefits of IaC** (recipe-book framing):
  - When to use: to justify IaC adoption to teams and stakeholders.
  - How: (1) Consistency and repeatability — every environment built from the same code recipe; (2) Version control and auditability — definitions in Git, changes tracked and rollback-able; (3) Collaboration and transparency — pull requests and diffs on infrastructure; (4) Speed and agility — provision or destroy environments in minutes; (5) Documentation and knowledge sharing — the config files ARE the documentation.
- **Imperative vs. Declarative Decision Frame**:
  - When to use: choose declarative (Terraform) for anything rerun, shared, or evolved; scripts only for true one-offs.
  - How: evaluate six aspects — Approach, Error proneness, Idempotence, Visibility of changes, State management, Collaboration (see Reference Tables).

## Key Concepts
- **Snowflake server**: a manually configured, one-of-a-kind server that cannot be reliably reproduced, causing inconsistency and fragility.
- **HCL (HashiCorp Configuration Language)**: Terraform's unified declarative language for describing infrastructure.
- **Provider**: a plugin that translates HCL into API calls for a target platform (Azure, AWS, GCP, Kubernetes, DNS, etc.).
- **State (`terraform.tfstate`)**: JSON file recording the mapping between configuration and actual infrastructure; basis for plan computation.
- **Declarative configuration**: describing the desired end state and letting the tool determine the steps, in contrast to imperative scripting where every step is scripted in order.
- **Idempotence**: re-running a configuration yields no changes once actual state matches declared state — built into Terraform, not scripted conditionals.
- **`terraform plan`**: read-only, safe-to-repeat comparison of desired vs. current state producing an itemized add/change/destroy list before touching anything.
- **Remote backend**: shared, lockable state storage (Terraform Cloud, S3+DynamoDB, Azure Storage) enabling team collaboration.
- **Policy as code (PaC)**: Sentinel or Open Policy Agent (OPA) enforcing tagging, region restrictions, security baselines at plan time.

## Recipes in this chapter
- **Recipe 1: Setting up a Terraform project directory** — init a clean project with `required_providers` + `provider "azurerm"` blocks and run `terraform init`.
- **Recipe 2: Your first Terraform resource** — use a `null_resource` with a `local-exec` provisioner to observe plan/apply without cloud costs.
- **Recipe 3: Terraform plan and apply demo** — use a `local_file` resource to see state metadata recorded in `terraform.tfstate`.
- **Recipe 4: Formatting and validating configuration** — `terraform fmt` for canonical style, `terraform validate` for dry-run syntax checking before deployment.
- **Recipe 5: Updating Terraform resource** — change `triggers` on a `null_resource` to see delta detection and resource replacement.
- **Recipe 6: Destroying infrastructure** — `terraform destroy` to prevent sprawl and unexpected charges in ephemeral environments.

## Anti-patterns
- **Imperative scripts for infrastructure**: rerunning without cleanup hits "already exists" errors; changing a value requires manually re-running `az network vnet subnet update`-style commands in exactly the right order.
- **Manual idempotence checks**: adding "if this resource exists, skip it" conditionals to scripts — you will forget one and get errors; declarative state tracking does this for free.
- **Relying on console log-diffing for visibility**: imperative workflows force manual diffing; `terraform plan` shows precise add/change/delete up front.
- **Skipping plan review / careless `-auto-approve`**: use `-auto-approve` only in automated pipelines with proper guardrails.
- **Committing `terraform.tfstate` to Git**: commit the `*.tf` files, never the state.

## Code Examples
```hcl
# Declarative Azure VM stack (abbreviated from the Chef's Special / worked example)
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "vm-hello"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B1s"
  network_interface_ids = [azurerm_network_interface.nic.id]
  admin_username        = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("${path.root}/id_ed25519.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}
```
- **What it demonstrates**: dependency-driven declarative resource definition — Terraform creates resource group → VNet → subnet → NIC → VM in the right order regardless of file ordering, and `${path.root}` reads the SSH key at runtime.

```hcl
# Trigger-based change detection (Recipe 5)
resource "null_resource" "hello" {
  triggers = { message = "Hello, Terraform v2!" }
  provisioner "local-exec" {
    command = "echo '${self.triggers.message}'"
  }
}
```
- **What it demonstrates**: `triggers` makes Terraform watch a value; changing it produces a delta, and apply destroys/recreates only that resource (idempotent, incremental updates).

## Reference Tables
Table 1.1 — Declarative configuration vs. imperative scripting:

| Aspect | Imperative scripts | Declarative configuration (Terraform) |
|---|---|---|
| Approach | Do these steps in order | Desired end state is declared |
| Error proneness | High: fails if order or environment differs | Low: Terraform computes the dependency graph |
| Idempotence | Must manually ensure repeated runs are safe | Built-in: re-running yields the same outcome |
| Visibility of changes | Poor: manual diffing or logs | `terraform plan` shows precise add/change/delete |
| State management | External or ad-hoc scripts | Centralized via state file and backends |
| Collaboration | Harder: scripts evolve separately | Native GitOps workflow with code reviews |

Key production use cases (where Terraform pays off): team collaboration/governance (PR + CI validate/plan, remote state locking); multi-environment parity (workspaces or separate backends, same code + different variables); immutable infrastructure/DR (full rebuilds in minutes, blue-green/canary); compliance and auditing (Sentinel/OPA at plan time, changes tied to commits); multi-cloud and hybrid (provider aliasing + modules); cost management (scheduled teardown of non-production environments).

## Worked Example
**Chef's Special: end-to-end Azure VM from scratch.**
1. *Appetizer — credentials*: `az login`, then create a service principal with Contributor role scoped to your subscription and pipe the JSON to `sp.json`; load it and export the ARM_* environment variables for the session:
   - `$Env:ARM_CLIENT_ID = $sp.appId; $Env:ARM_CLIENT_SECRET = $sp.password; $Env:ARM_TENANT_ID = $sp.tenant; $Env:ARM_SUBSCRIPTION_ID = "<id>"` (session-only; never check secrets into source control).
2. *Main course — resources*: declare in `main.tf` the `azurerm` (~>4.27.0), `null` (~>3.2.4), and `local` (~>2.5.2) providers, then resource group `rg-hello-tf`, VNet `10.0.0.0/16`, subnet `10.0.1.0/24`, dynamic public IP, NIC, and a `Standard_B1s` Ubuntu VM. Generate the SSH key first: `ssh-keygen -t ed25519 -f $Env:USERPROFILE\.ssh\id_ed25519`, copy `id_ed25519.pub` into the project, reference it via `file("${path.root}/id_ed25519.pub")`.
3. *Dessert — lifecycle*: `terraform init` → `terraform plan` → `terraform apply`; verify in the portal under rg-hello-tf and SSH in; finish with `terraform destroy` to avoid charges.
4. Gotcha covered: a 409 `ConflictingConcurrentWriteNotAllowed` when Terraform auto-registers `Microsoft.HDInsight` — resolve with `az provider register --namespace Microsoft.HDInsight`, poll, re-run plan.
5. Refactor tip: split by function (`main.tf`, `rg.tf`, `network.tf`, `compute.tf`) — Terraform merges all `.tf` files automatically.

## Key Takeaways
1. Use declarative Terraform over imperative CLI scripts for anything that will be rerun, shared, or changed — the tool handles ordering, dependencies, and idempotence.
2. Always preview with `terraform plan`; it is safe to run repeatedly and is your main defense against unintended destroys.
3. State is Terraform's memory: never edit it by hand, never commit it, and move to a remote backend once more than one person applies changes.
4. `triggers` (on `null_resource`) is the primitive that lets you force reprovisioning when an input value changes.
5. `terraform fmt` + `terraform validate` catch style drift and syntax errors before deployment; run them in CI.
6. Codify credentials via environment variables (`ARM_*`, etc.) rather than provider blocks — the HCL stays secret-free.
7. The lifecycle is always init → plan → apply → destroy; destroy deliberately and promptly in dev/test to control costs.

## Connects To
- **Ch 2**: builds directly on this chapter's install/auth setup — adds multi-provider (AWS/GCP) coverage and the first VM deployments across three clouds.
- **Ch 3**: promised as the deep dive into "input variables, output values, and Terraform's state file" introduced here only conceptually (state, plan/apply mechanics).