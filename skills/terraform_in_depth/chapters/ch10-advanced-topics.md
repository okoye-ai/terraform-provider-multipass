# Chapter 10: Advanced Terraform topics

## Core Idea
Advanced Terraform is mostly about knowing when a tool fits and when it doesn't: build flexible naming/network modules so your code scales, avoid provisioners and the external provider as last-resort escapes, use checks and conditions to test long-lived infrastructure, and honestly recognize when another tool (Helm, Packer, a container CI) should do the job.

## Frameworks Introduced
- **Hierarchical naming scheme**: names built by extending a parent component's name for each subcomponent.
  - When to use: any codebase with hundreds of resources across applications and systems.
  - How: root module hardcodes the application name and combines it with an `environment` variable (`local.base_name = "${application}-${environment}"`); submodules receive the full name prefix as an input and append a descriptor (`${var.name}-lb`, `${var.name}-logs`); only the primary resource of a module may use `var.name` directly.
- **Four naming constraints** (Hafner's criteria for a good naming scheme): names should be **Unique, Human readable, Identifiable, Sortable**. Unique is the only technically enforced one; sortable lets prod/dev resources cluster and filter together. Pet-style names (`random_pet`, e.g. `current-walrus`) are readable but not identifiable.
- **Three network topology considerations**: before defining a network, decide on (1) **Segmentation of services** (security — isolate internet-facing from private), (2) **High availability needs** (three locations is the standard), (3) **Size of the network** (room to grow without wasting IP addresses).
- **Two-tier vs three-segment network**: two-segment = public + private subnet with a NAT gateway; three-segment adds an isolated subnet with no internet path, bridged explicitly, for extremely sensitive data.
- **Provisioner decision matrix (last-resort rule)**: Table 10.4 maps every provisioner purpose to a better alternative — Software installation → preinstall on machine images; Configure launched instance → Cloud-Init; Environment-specific files → Cloud-Init; Custom shutdown sequence → bake a shutdown service into the image; Metadata to a file → output variables or the local provider.
- **Immutable infrastructure**: rather than keeping instances up to date, replace them when configuration changes. Build machine images in advance; restrict launch-time work to configuration, done with Cloud-Init.

## Key Concepts
- **Provisioners**: a way to create files and run commands locally or remotely when Terraform creates or destroys resources — an advanced feature that is "most likely a bad idea" and should only be used when no other option is available.
- **connection block**: configures how provisioners reach the target (SSH for Unix, WinRM for Windows); supports `self` for the resource's own attributes and bastion-host passthrough. Remote connections hard-code network detail into modules, making them less portable.
- **terraform_data**: the "resource that does nothing" (successor to `null_resource`); its `triggers` let you attach provisioners to multiple dependencies and re-run once only when they change.
- **External provider**: a data-source-only provider that pipes a JSON `query` to a program on `stdin` and reads its JSON result from `stdout` into `result` — for data Terraform has no provider for; last resort because the delivery environment must be able to run your program.
- **Local provider**: manages files on the machine running Terraform; adds the `direxists` provider function (v1.8+) and `local_file`/`local_sensitive_file` data sources with checksum attributes.
- **Precondition / postcondition**: `lifecycle` blocks on resources and data sources that validate before or after creation; failing either stops the apply. Use `self` to refer to the resource the condition is on.
- **check block** (Terraform v1.5): assertions (`assert blocks`) against infrastructure that report health without stopping execution; can own scoped data sources available only inside the block.
- **Tofu files**: OpenTofu v1.8 feature — a `.tofu` file is ignored by Terraform and, when a matching basename exists, preferred over the `.tf` file by OpenTofu.
- **Provider functions**: functions defined by providers, callable via `provider::local::direxists(...)`; require Terraform/OpenTofu 1.8.0+.

## Mental Models
- Think of a hierarchical name as mirroring the module tree: Terraform already addresses resources this way (`module.lb.module.logs.aws_s3_bucket.main`), so your runtime names should mirror the same structure (`acme-dev-api-lb-logs`).
- Think of subnetting as borrowing bits: each borrowed bit doubles the network count; since subnets are powers of two, splitting into thirds requires dividing in half, then dividing one half again (private gets the big half; public and isolated split the rest).
- Think of provisioners and the external provider as escape hatches, not features: "ask if there is a better way to solve the problem" — almost always there is.
- Think of checks as production health tests: preconditions/postconditions gate deployment, checks merely report, so they can run on long-lived production infrastructure.
- Think of Terraform as deployment, not artifact production: packaging things into registries is an integration concern.

## Anti-patterns
- **Using provisioners by default**: they add failure points, deployment time, and unpredictable behavior; modules using them are less portable and harder to debug. Use them only when no alternative exists. Default `on_failure = fail` also taints the resource.
- **Using the external provider as a data hack**: requires extra maintenance and a delivery environment that can run your script; for redistribution, "stick to Bash or avoid the external provider altogether."
- **Creating local files with Terraform in production**: if code isn't run from the same location with the files restored, Terraform always detects drift. Useful only for development/debugging workflows.
- **Checking with no dependencies**: a `check` with only variable inputs runs on the very first plan, before resources exist — always use `depends_on` (or implicit dependencies) on scoped data sources.
- **Naming resources after their type**: don't call a bucket `logging_bucket`; the type is inherent. Also avoid deep module nesting and prefer short names (`db` over `database`).
- **Building container/machine images inside Terraform**: it slows deploys and tightly couples application and infrastructure; and managing Kubernetes deployments with Terraform stacks abstraction on abstraction, making debugging harder.
- **Cross-variable validation backwards**: pre-1.9, cross-variable validation had to be faked with `precondition` blocks; since v1.9 prefer the variable `validation` block itself — it's easier for developers to find.

## Code Examples
```hcl
# Two-tier subnet module: one borrowed bit splits the CIDR in half
locals {
  private_subnet_cidr_block = cidrsubnet(var.cidr_block, 1, 0)
  public_subnet_cidr_block  = cidrsubnet(var.cidr_block, 1, 1)
}

resource "aws_subnet" "public" {
  vpc_id                  = var.vpc_id
  cidr_block              = local.public_subnet_cidr_block
  map_public_ip_on_launch = true                  # the field that makes it public
  availability_zone       = var.availability_zone
  tags = { Network = "Public" }
}

resource "aws_nat_gateway" "main" {               # private subnet's internet egress
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}
```
- **What it demonstrates**: the location-module pattern — `cidrsubnet` carving a per-AZ CIDR into public/private halves, plus NAT and tagging for programmatic discovery.

```hcl
check "health_check" {                            # never stops execution
  data "http" "api" {
    url             = var.healthcheck_endpoint   # no implicit dependency...
    request_headers = { Accept = "application/json" }
    depends_on      = [module.api]               # ...so depend on the app explicitly
  }
  assert {
    condition     = data.http.api.status_code >= 200 && data.http.api.status_code < 300
    error_message = "Healthcheck failed with status code ${data.http.api.status_code}."
  }
}
```
- **What it demonstrates**: a production health check with scoped data sources and the `depends_on` pitfall fix.

```hcl
data "external" "query" {
  program = ["python", "${path.module}/square_root.py"]
  query   = { "0" = "128", "random" = "1024" }     # JSON sent to the program's stdin
}
output "random" { value = data.external.query.result["random"] }
```
- **What it demonstrates**: the external data source contract — query in as JSON, your program returns a JSON object of strings on `stdout`.

## Reference Tables
Table 10.4 — Provisioner purposes and alternatives:

| Purpose | Alternative |
|---|---|
| Software installation | Preinstall software on machine images used for the service |
| Configure launched instance | Use Cloud-Init to pass configuration to the machine |
| Add environment-specific files | Use Cloud-Init to create the files on launch |
| Custom shutdown sequence for destruction | Create a shutdown service, baked into the image or installed with Cloud-Init |
| Machine metadata saved to a file | Use output variables or the local provider to create files |

Condition/check comparison: preconditions/postconditions live in `lifecycle`, accept one boolean `condition` each (many blocks allowed), stop execution on failure, and use `self`; `check` blocks hold many `assert blocks`, cannot use `self`, and only warn on failure.

## Worked Example
The chapter builds the **Acme SaaS naming + network system end-to-end**: root module `acme-${var.environment}` → `api` and `database` service modules, each layering names downward (`acme-dev-api-lb-logs`) and domains outward (`api.dev.acme.example.net`); the network module accepts `cidr_block`, `enable_isolated_subnet`, and `availability_zones` (1–4), computes `subnet_bits` (0/1/2) with a ternary, uses the **binary toggle** to pick between the two-tier and three-tier AZ submodule, and outputs subnet IDs plus any spare CIDR blocks — the same code deploys a cheap dev environment and a highly available three-AZ prod with no code changes.

## Key Takeaways
1. Name resources hierarchically from `application-environment` downward, appending one descriptor per module layer; let names generate themselves and add a `random_string` suffix only where the resource requires it (e.g., S3 namespace squatting).
2. Build networks as `cidrsubnet`-driven modules: a location submodule per AZ plus a high-level module toggling topology and AZ count — same code, different availability and cost per environment.
3. Treat provisioners, the external provider, and local file resources as last resorts; for every provisioner purpose there is a better tool (machine images, Cloud-Init, outputs).
4. Use postconditions to fail fast and checks to report on production health — and give scoped check data sources a `depends_on` so they don't fire on the first plan.
5. Keep Terraform/OpenTofu compatible with `.tofu` override files, and use provider functions (1.8+) instead of scripts when they exist.
6. Don't use Terraform to launch Kubernetes workloads, build images, or manage artifacts; use kubectl/Helm/ArgoCD, Cloud-Init + Packer, and a dedicated artifact pipeline, with Terraform consuming versioned artifacts via input variables.

## Connects To
- **Ch 9**: chapter 9 tested modules during development; checks and conditions extend that to assertions against long-running production infrastructure.
- **Ch 6 / Ch 8**: provisioner `when = destroy` pairs with destroy flows and the deployment orchestrator; `terraform_data` comes from the state-only resources discussion (6.8.4).
- **Ch 12**: the external provider's real alternative when you know Go is writing a custom provider; provider functions come from the same framework.
- **Cloud-Init / Packer**: external standards for launch configuration and image building that replace machine-touching logic.