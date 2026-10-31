# Chapter 8: Production-Grade Terraform Code

## Core Idea
Production-grade infrastructure means infrastructure you'd bet your company on — and it takes far longer than engineers expect because of a long, mostly unknown checklist of tasks. The remedy is to build reusable infrastructure from small, composable, testable, versioned modules, with self-validating checks and deliberate (pinned) dependency versions.

## Frameworks Introduced

### Production-Grade Infrastructure Checklist
A canonical list of tasks every piece of infrastructure must consider before going to production: install, configure, provision, deploy, high availability, scalability, performance, networking, security, metrics, logs, data backup, cost optimization, documentation, tests. Most developers know only the first four; the rest (HA, networking, security, backups, monitoring) are what blow up estimates and get forgotten.

- **When to use:** At the start of every new piece of infrastructure — go through the whole checklist.
- **How:** Do not treat it as "all items mandatory." Consciously and explicitly document which items you implement, which you skip, and why. Use it (plus the time-estimate table) to produce realistic project estimates.

### Small modules
Large modules (more than a few hundred lines, or more than a few closely related pieces of infrastructure) should be considered harmful: they are slow (`plan` can take 20 minutes), insecure (everyone needs admin access, violating least privilege), risky (one typo can destroy prod data), hard to understand, hard to review (thousands-of-lines `plan` output goes unread), and nearly impossible to test.

- **When to use:** Always — treat a huge module the way you'd treat a 20,000-line function: as a code smell.
- **How:** Refactor by responsibility into standalone modules (e.g., ASG rolling deployment, ALB, app) organized by domain: `modules/cluster/`, `modules/networking/`, `modules/services/`.

### Composable modules
Follow the Unix philosophy: do one thing and do it well; work together. Mimic function composition — pass everything in via input variables, return everything via output variables, and build complex modules by combining simple ones. Minimize "side effects": no reading hardcoded state (Default VPC, built-in ALB) or hardcoded user data inside the module.

- **When to use:** Whenever two modules must work together, or when a module must serve multiple use cases (no LB, one ALB, multiple NLBs, any app).
- **How:** Expose integration knobs as inputs (`subnet_ids`, `target_group_arns`, `health_check_type`, `user_data`) and emit useful outputs (`alb_dns_name`, `asg_name`, security group IDs) so consumers can extend behavior.

### Testable modules (examples folder)
Every module gets a corresponding example in an `examples` folder; every example gets tests in a `test` folder; each important permutation of a module gets its own example.

- **When to use:** When developing any module; ideally write example code first (a form of TDD).
- **How:** Examples serve triple duty — manual test harness (apply/destroy by hand), automated test harness (Chapter 9), and executable documentation for teammates. Start with the example to design the clean API, then implement backward.

### Self-validating modules (validation / precondition / postcondition)
Modules that check their own behavior to prevent bugs, using three built-in block types (see Key Concepts). Guidance for each:

- **Validation blocks** — When to use: in all production-grade modules, for basic input sanitization, checked before anything deploys; prefer them over preconditions for variable checks because they live with the variable they validate (readable, maintainable API). How: `condition` must evaluate to true when valid; multiple blocks per variable are allowed; limitation — can only reference the surrounding variable, never other variables, locals, resources, or data sources.
- **Precondition blocks** — When to use: in all production-grade modules, for basic assumptions that must hold before deployment: checks spanning multiple variables/data sources, or checks on resources/data sources. How: put a `precondition` inside a `lifecycle` block (Terraform 1.2+); errors surface before apply does damage.
- **Postcondition blocks** — When to use: in all production-grade modules, for guarantees about module behavior after deployment (e.g., ASG spans >1 AZ), giving users confidence the module either delivers or errors out, and giving maintainers a signal of intended behavior during refactors. How: `postcondition` inside `lifecycle`, using `self.<ATTRIBUTE>` expressions (only valid in postcondition, connection, and provisioner blocks — `self` avoids the circular-dependency error you'd get referencing the resource by name).
- **Automated testing tools** — When: for more advanced assumptions/guarantees (e.g., checking a service answers HTTP requests, which needs retries/VPN access pure Terraform can't do). How: OPA, Terratest (Chapter 9).

### Versioned modules (dependency pinning)
Pin all three dependency types so identical code always produces identical results, whether run today or in three years; upgrades must be explicit, deliberate, and visible in version control.

- **Terraform core:** at minimum pin the major version (`">= 1.0.0, < 2.0.0"`); recommended for production: pin exactly (`"1.2.3"`) and upgrade intentionally, consistently, environment by environment. Use `tfenv` with `.terraform-version` files to let different folders/environments use different versions automatically.
- **Providers:** pin major version in `required_providers` (`~> 4.0`). Since Terraform 0.14, the lock file (`.terraform.lock.hcl`, checked into version control) pins exact versions and checksums; upgrade via `terraform init -upgrade`. Multi-OS teams need `terraform providers lock -platform=...` for each platform.
- **Modules:** consume via Git URLs with `?ref=<git tag>` (semantic versioning tags) rather than local paths; or use the Terraform Registry (`source` + separate `version` argument), including Private Registries in Terraform Cloud/Enterprise.

### Escape hatches (Beyond Terraform modules)
Ways to run non-Terraform code from Terraform — for integrating with other systems or working around missing provider APIs / declarative-logic limits. All are last resorts: they make code less portable and more brittle.

- **Provisioners:** `local-exec`, `remote-exec`, `file`. Creation-time by default (run once, on first creation only); `when = destroy` makes them destroy-time; `on_failure = "continue" | "abort"`; multiple provisioners run in order top to bottom. Prefer User Data over remote-exec (no SSH port exposure, works with ASGs/auto-scaling events, debuggable in console and `/var/log/cloud-init*.log`). Provisioners' only real advantage: no 16 KB length cap.
- **Provisioners with null_resource:** run scripts not tied to a real resource; use `triggers` (e.g., `triggers = { uuid = uuid() }`) to force re-execution.
- **External data source:** run a program that reads JSON from stdin (Terraform's `query` args) and writes JSON to stdout, consumed via `data.external.<name>.result.<path>` — for fetching data Terraform has no data source for.

## Key Concepts
- **Production-grade infrastructure:** Infrastructure you'd bet the company on — survives traffic spikes, outages, and attacks without losing or compromising data.
- **Hofstadter's Law:** DevOps projects always take longer than you expect, even when you account for Hofstadter's Law.
- **Yak shaving:** The chain of tiny, seemingly unrelated prerequisite tasks that grows out of a trivial change (typo fix → OS upgrade of the whole fleet).
- **Accidental vs. essential complexity:** Accidental complexity comes from chosen tools/processes (immature DevOps tooling, tight coupling); essential complexity is inherent to the problem — e.g., the long production checklist itself.
- **Small module:** A module that does one thing, contained within a few hundred lines; large modules are explicitly deemed harmful.
- **Function composition (for modules):** Building complex behavior from simpler parts by wiring outputs of one module into inputs of another.
- **Validation block:** A per-variable check on input values, usable from Terraform 0.13, limited to referencing only its own variable.
- **Precondition/postcondition:** Lifecycle checks (Terraform 1.2+) on resources, data sources, and outputs — assumptions before apply, guarantees after apply.
- **`self` expression:** Syntax `self.<ATTRIBUTE>` for referring to the surrounding resource's attributes, valid only in postcondition, connection, and provisioner blocks.
- **Version pinning:** Fixing core/provider/module dependencies to specific versions so applies are predictable and repeatable.
- **Lock file (`.terraform.lock.hcl`):** Auto-generated on `init`; records exact provider versions and checksums (with signature validation); should be committed.
- **Examples folder:** Per-module runnable code used as manual test harness, automated test harness, and executable documentation.

## Mental Models
- **Use the "20,000-line function" test when sizing modules:** If you'd flinch at a 20,000-line function in Java or Python, a 20,000-line Terraform module is the same code smell — split it into small, single-purpose modules.
- **Use "minimize side effects" when designing a module's API:** All inputs as variables, all results as outputs; a module with hidden dependencies (Default VPC, hardcoded user data) is a module you can't reuse or compose.
- **Use "catch errors as early as possible" when layering checks:** validation blocks stop bad inputs at plan time; preconditions stop bad assumptions just before apply; postconditions verify guarantees after apply; automated tests (OPA/Terratest) cover what pure Terraform expressions can't.
- **Use "upgrades are deliberate actions" when managing dependencies:** If the code didn't change, apply must produce the same result today, in three months, or in three years — no dependency ever updates by accident.

## Anti-patterns
- **Huge copy-pasted / monolithic modules:** All environments or an entire architecture in one file/module — slow, insecure (admin for everyone), risky, unreadable, unreviewable, untestable.
- **Modules with built-in assumptions:** Hardcoding infrastructure (Default VPC subnets, an embedded ALB) and app behavior (hardcoded User Data) inside a generic-sounding module instead of exposing them as inputs.
- **Unpinned dependencies:** Floating `required_version`, unconstrained provider versions, or modules sourced from local paths or branch heads — apply results drift over time; major-version bumps land by accident.
- **Not committing the lock file:** Loses exact provider versions and checksum verification across machines.
- **Recorded checksums for only one OS:** Lock file created on Linux breaks `init` for Mac users unless `terraform providers lock` covers every platform.
- **Managing SSH keys in Terraform state / opening SSH to 0.0.0.0/0:** Fine for learning exercises (e.g., `tls_private_key`, wide-open port 22), unacceptable in production — manage keys outside Terraform, restrict to trusted IPs.
- **Reaching for escape hatches by default:** Provisioners and `external` data sources are brittle and less portable (e.g., Bash-dependent code won't run from Windows); prefer User Data over remote-exec.
- **No documented decisions on the checklist:** Deploying infrastructure without explicitly noting which production-grade items were implemented, skipped, and why — every piece ends up deployed a little differently.

## Code Examples

Variable validation (Terraform 0.13+; `condition` true = valid; can reference only its own variable):

```hcl
variable "instance_type" {
  description = "The type of EC2 Instances to run (e.g. t2.micro)"
  type        = string

  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.instance_type)
    error_message = "Only free tier is allowed: t2.micro | t3.micro."
  }
}
```

Precondition (dynamic check before apply, inside `lifecycle`; can use data sources & other variables):

```hcl
resource "aws_launch_configuration" "example" {
  # ...
  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = data.aws_ec2_instance_type.instance.free_tier_eligible
      error_message = "${var.instance_type} is not part of the AWS Free Tier!"
    }
  }
}
```

Postcondition (guarantee after apply; `self` refers to the surrounding resource):

```hcl
resource "aws_autoscaling_group" "example" {
  # ...
  lifecycle {
    postcondition {
      condition     = length(self.availability_zones) > 1
      error_message = "You must use more than one AZ for high availability!"
    }
  }
}
```

Pinning dependencies:

```hcl
terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "4.4.0"
}

# Git-pinned private module:
# source = "git@github.com:foo/modules.git//services/hello-world-app?ref=v0.0.5"
```

## Reference Tables

**Table 8-1 — How long to build production-grade infrastructure from scratch:**

| Type | Example | Time estimate |
|---|---|---|
| Managed service | Amazon RDS | 1–2 weeks |
| Self-managed distributed system (stateless) | Cluster of Node.js apps in an ASG | 2–4 weeks |
| Self-managed distributed system (stateful) | Elasticsearch cluster | 2–4 months |
| Entire architecture | Apps, data stores, LBs, monitoring, etc. | 6–36 months |

**Table 8-2 — The Production-Grade Infrastructure Checklist:**

| Task | Description | Example tools |
|---|---|---|
| Install | Install software binaries and dependencies | Bash, Ansible, Docker, Packer |
| Configure | Runtime configuration: ports, TLS certs, service discovery, leaders, replication | Chef, Ansible, Kubernetes |
| Provision | Provision infrastructure: servers, LBs, network, firewalls, IAM | Terraform, CloudFormation |
| Deploy | Deploy service; zero-downtime rollouts (blue-green, rolling, canary) | ASG, Kubernetes, ECS |
| High availability | Withstand outages of processes, servers, services, datacenters, regions | Multi-datacenter, multi-region |
| Scalability | Scale up/down; horizontally and vertically | Auto scaling, replication |
| Performance | Optimize CPU/memory/disk/network/GPU; tuning, benchmarking, load testing | Dynatrace, Valgrind, VisualVM |
| Networking | Static/dynamic IPs, ports, service discovery, firewalls, DNS, SSH, VPN | VPCs, firewalls, Route 53 |
| Security | TLS, encryption on disk, authn/authz, secrets management, hardening | ACM, Let's Encrypt, KMS, Vault |
| Metrics | Availability/business/app metrics, events, observability, tracing, alerting | CloudWatch, Datadog |
| Logs | Rotate on disk; aggregate to central location | Elastic Stack, Sumo Logic |
| Data backup | Scheduled backups; replicate to separate region/account | AWS Backup, RDS snapshots |
| Cost optimization | Right instance types, spot/reserved, auto scaling, clean up unused | Auto scaling, Infracost |
| Documentation | Document code/architecture/practices; incident playbooks | READMEs, wikis, Slack, IaC |
| Tests | Automated tests for infra code; after every commit and nightly | Terratest, tflint, OPA, InSpec |

**Versioning options:**

| Dependency | Pin how | Notes |
|---|---|---|
| Terraform core | `required_version` — minimum `">= 1.0.0, < 2.0.0"`; production: exact `"1.2.3"` | v1.x upgrades are compatible per the v1.0 Compatibility Promises, but upgrade deliberately; use `tfenv` + `.terraform-version` files per environment |
| Providers | `required_providers` `version = "~> 4.0"` (major) | Lock file pins exact version + checksums; commit it; `init -upgrade` to bump; `terraform providers lock` per platform |
| Modules | Git URL `?ref=v0.0.5` or Registry `version = "4.4.0"` | Tag modules with semver; Registry repos named `terraform-<PROVIDER>-<NAME>`, public repo, `main.tf`/`variables.tf`/`outputs.tf` layout, semver tags; Private Registry via Terraform Cloud/Enterprise |

**Terraform Registry source syntax:** `source = "<OWNER>/<REPO>/<PROVIDER>"`, `version = "<VERSION>"`.

**Typical modules repo layout:**

```
modules
 ├ examples      # one example per module, per permutation
 │   ├ alb / asg-rolling-deploy/{one-instance,auto-scaling,with-load-balancer,custom-tags}
 │   ├ hello-world-app / mysql
 ├ modules       # the implementation
 ├ test          # automated tests for each example
```

## Worked Example
Prototypical refactor of the book's `webserver-cluster` module (Ch. 5) — one module doing three unrelated jobs (ASG with rolling deploys, ALB, "Hello, World" app) — into small composable modules:

1. **Split by responsibility:**
   - `modules/cluster/asg-rolling-deploy` — takes the launch configuration, ASG, autoscaling schedules, instance security group + rule, and CloudWatch alarms. Generic: adds inputs `subnet_ids`, `target_group_arns`, `health_check_type`, `user_data` (replacing hardcoded Default VPC data sources and the baked-in ALB/User Data); outputs `asg_name`, `instance_security_group_id`.
   - `modules/networking/alb` — takes `aws_lb`, listener, and ALB security group; single input `alb_name`; outputs `alb_dns_name`, `alb_http_listener_arn`, `alb_security_group_id`.
   - `modules/services/hello-world-app` — keeps the app-specific glue: target group and listener rule, remote state for the DB, plus `environment` input enforcing the naming convention (`hello-world-${var.environment}` → `hello-world-stage`, `hello-world-prod`).
2. **Compose:** `hello-world-app` declares `module "asg"` and `module "alb"`, then performs function composition: the target group's ARN is passed to the ASG (`target_group_arns = [aws_lb_target_group.asg.arn]`, `health_check_type = "ELB"`), the listener rule points at the ALB output (`listener_arn = module.alb.alb_http_listener_arn`), and a `user_data` script is passed via `templatefile(...)` with the DB address/port from remote state — all wiring is inputs-in/outputs-out, no hardcoded coupling.
3. **Make testable:** create `examples/asg/main.tf` — a root module with provider, backend-agnostic defaults, an Ubuntu AMI data source, and an ASG of size 1 — which is at once a manual harness (apply/destroy), the basis for automated tests (Ch. 9), and executable documentation (with a README). Repeat for every module and every important permutation.
4. **Make versioned/pinned:** pin `required_version` and provider versions; tag releases (`git tag -a "v0.0.5"; git push --follow-tags`); consume in live environments via `source = "git@github.com:foo/modules.git//services/hello-world-app?ref=v0.0.5"`. Deploy the same tag to stage, then — once validated — the same code to prod; roll back by deploying an older tag.
5. **Add self-validation:** validation blocks on inputs (e.g., free-tier instance types, `min_size` bounds), preconditions (free-tier eligibility via `aws_ec2_instance_type` data source), and postconditions (>1 AZ in the ASG).

The book's recommended process for every new module: (1) walk the checklist and document implement/skip decisions, then estimate; (2) write example code first to define the cleanest API; (3) implement as small, composable modules with pinned dependencies; (4) write automated tests for each example.

## Key Takeaways
- Budget realistically: a managed service is 1–2 weeks; a stateless ASG app 2–4 weeks; a stateful cluster 2–4 months; a full architecture 6–36 months — the unknown checklist items are why estimates fail.
- Enforce the production-grade checklist explicitly per piece of infrastructure: record what's implemented, skipped, and why.
- Treat large modules (>a few hundred lines / few unrelated resources) as harmful; refactor into small modules organized by domain: `cluster/`, `networking/`, `services/`.
- Make modules composable: all inputs via variables, all results via outputs; complexity emerges from combining simple modules, like function composition.
- Build an `examples/` folder — write example code before module code (TDD-style); every module needs examples, every example needs tests.
- Layer self-validation: validation blocks for input sanitization, preconditions for assumptions, postconditions for guarantees, OPA/Terratest for anything beyond Terraform's expression language (retries, HTTP checks, VPN access).
- Pin all three dependency types — Terraform core, providers (plus committed lock file, multi-platform checksums), and modules (Git tags or Registry versions); upgrades are deliberate, visible actions.
- Prefer User Data over provisioners for server bootstrapping; treat provisioners, `null_resource`, and `external` data sources as conservatively used escape hatches.

## Connects To
- **Ch. 4 (Modules):** introduces module basics and "Module Versioning" (p. 133); Ch. 8 deepens it into small/composable/testable/versioned modules and pins.
- **Ch. 5 (Terraform Tips & Loops):** source of the `webserver-cluster` module refactored here; the ASG/ALB resources being split were built there.
- **Ch. 2 (State):** "State File Isolation" (p. 93) — why one big module for all environments is a bad idea.
- **Ch. 7 (Working with Multiple Providers):** `required_providers` blocks and provider pinning were introduced there; extended here with lock files and `terraform providers lock`.
- **Ch. 9 (Testing Terraform Code):** the direct continuation — the `examples/`/`test/` structure set up here is where Terratest and OPA automated tests live.
- **Ch. 6 / Ch. 10 (Secrets, and the book's closing chapters):** security, secrets management, and Vault appear as checklist rows pointing at later production-architecture discussions.