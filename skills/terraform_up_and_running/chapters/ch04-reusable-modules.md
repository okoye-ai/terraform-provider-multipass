# Chapter 4: How to Create Reusable Infrastructure with Terraform Modules

## Core Idea
Terraform modules — any folder of Terraform configuration files promoted into a reusable unit with inputs, outputs, and locals — are the key ingredient to writing reusable, maintainable, testable infrastructure code, letting multiple environments (staging, production) share one definition instead of copy-pasted code.

## Frameworks Introduced

### Module structure (any folder = module)
When to use: whenever the same infra (a web server cluster, a database, a microservice) is needed in more than one place or environment. How: any set of Terraform files in a folder is a module; run `apply` directly on it and it's a **root module**; move it to `modules/<type>/<name>` and reference it via a `module` block with `source` to make it a **reusable module**. Providers should be configured only in root modules, never in reusable ones. After adding a module or changing its `source`, you must run `terraform init` (it installs providers, configures backends, and downloads modules).

### Module inputs = the module's API
When to use: any value that must differ between environments (names, state locations, instance sizes, cluster bounds). How: define ordinary `variable` blocks in the reusable module and reference them with `var.<NAME>`; consumers set them as arguments on the `module` block using the same syntax as resource arguments. Input variables control how a module behaves in different environments — treat changing them as changing the module's API (with semver implications).

### Module locals (private intermediates)
When to use: for intermediate calculations or to keep code DRY when the value should *not* be an overridable input (e.g., "magic values" like port 80, `0.0.0.0/0`, protocol `-1` copied across many resources). How: define a `locals { }` block and read with `local.<NAME>`. Locals are visible only inside the module — consumers can't override them.

### Module outputs = return values
When to use: whenever a consumer needs something the module created (an ASG name for scheduled actions, an ALB DNS name to test against, a security group ID to attach extra rules to). How: define `output` blocks; read with `module.<MODULE_NAME>.<OUTPUT_NAME>`; "pass through" outputs in environment-level `outputs.tf` to surface key URLs.

### Versioned modules (modules vs. live repos)
When to use: once more than one environment points at the same module folder, a change there affects everything on the next deployment — version instead. How: two repos — **modules** (the "blueprints") and **live** (the "houses" built from them: stage, prod, mgmt). Tag releases with `git tag -a`, use a Git URL `source` with a `?ref=` parameter, and promote a tested tag through environments; roll back by pinning an older tag.

### Module gotchas checklist
When to use: before finalizing any reusable module. How: audit for (1) file paths and (2) inline blocks (below), plus hardcoded names and hardcoded cross-environment state references.

## Key Concepts
- **Root module** — the module Terraform applies directly; the only place providers should be configured.
- **Reusable module** — a module intended to be consumed by other modules/configurations via a `module` block.
- **Input variables** — a module's public "API"/function parameters, the only intended mechanism for per-environment variation.
- **Local values** — module-private named expressions (`local.<NAME>`) for DRY intermediate values that consumers cannot override.
- **Output variables** — a module's return values, read as `module.<NAME>.<OUTPUT>`.
- **Path reference** — `path.module` / `path.root` / `path.cwd` expressions for resolving file paths relative to the right module.
- **Inline block** — a sub-config argument (e.g., `ingress { ... set aside as its own resource.
- **Module source** — where module code comes from: local filepath, Git/Mercurial URL, HTTP URL, registry (init downloads it).
- **Semantic versioning** — `MAJOR.MINOR.PATCH` tags: bump MAJOR on incompatible API changes, MINOR on backward-compatible features, PATCH on backward-compatible bug fixes.
- **Scheduled action** — `aws_autoscaling_schedule` resource (cron `recurrence`) scaling an ASG on a clock; a common consumer of module outputs.

## Mental Models
- **Module = function.** Input variables are parameters, outputs are return values, locals are internal variables. Use this mapping when designing a module's surface area.
- **Modules repo = blueprint, live repo = house.** Blueprints are versioned, reviewed, reused; houses are where you instantiate them per environment.
- **Environment isolation via version pinning.** Use version N in production and N+1 in staging; promote only after proven, roll back by pinning an earlier tag.
- **Input vs. local decision:** expose it as a variable if consumers should vary it; lock it in locals if overriding it would be an accident waiting to happen.

## Anti-patterns (Module Gotchas)
- **Hard-coded resource names** — reusing a module twice in one AWS account causes name-conflict errors; parameterize every name with `var.cluster_name`-style inputs.
- **Hard-coded environment state paths** — a `terraform_remote_state` pointed at staging inside a reusable module makes every environment read staging's state; take bucket/key as inputs.
- **Relative file paths assumed relative to root** — `templatefile("user-data.sh", ...)` resolves against the *current working directory*, breaking in modules; use `templatefile("${path.module}/user-data.sh", ...)`.
- **Mixed inline blocks and separate resources** — Terraform errors because the configurations conflict and overwrite each other; for a given setting, use one or the other.
- **Inline blocks in reusable modules** — they lock consumers out: extra ingress/egress rules can only be added from outside when rules are separate resources (e.g., `aws_security_group_rule`). Prefer separate resources for `aws_security_group`/`aws_route_table`/`aws_network_acl` families.
- **Branch names or sha1s as `ref`** — branches are unstable (latest commit, changes on every init) and sha1s are unfriendly; prefer Git tags.
- **Hard-coding repo credentials** — don't bake private-repo credentials into code; use SSH source URLs (`git@github.com:<OWNER>/<REPO>.git//<PATH>?ref=<VERSION>`) so ssh-agent auths per developer.
- **Environments sharing one VPC** — code-only isolation is not network isolation; a staging mistake or breach reaches production. Run each environment in a separate VPC (or even separate AWS account) outside of toy examples.

## Code Examples
Module block with per-environment inputs (staging vs. prod differ by values only):
```hcl
module "webserver_cluster" {
  source = "../../../modules/services/webserver-cluster"

  cluster_name           = "webservers-stage"
  db_remote_state_bucket = "(YOUR_BUCKET_NAME)"
  db_remote_state_key    = "stage/data-stores/mysql/terraform.tfstate"

  instance_type = "t2.micro"
  min_size      = 2
  max_size      = 2
}
```

Versioned Git source with tag ref (note the required double-slash):
```hcl
module "webserver_cluster" {
  source = "github.com/foo/modules//services/webserver-cluster?ref=v0.0.1"

  cluster_name           = "webservers-prod"
  db_remote_state_bucket = "(YOUR_BUCKET_NAME)"
  db_remote_state_key    = "prod/data-stores/mysql/terraform.tfstate"

  instance_type = "m4.large"
  min_size      = 2
  max_size      = 10
}
```

Locals and module outputs:
```hcl
locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "The name of the Auto Scaling Group"
}
# consumer: autoscaling_group_name = module.webserver_cluster.asg_name
```

## Reference Tables
| Module source type | Example | Notes |
|---|---|---|
| Local filepath | `../../../modules/services/webserver-cluster` | Best for quick local iteration; couples environments without versioning |
| GitHub URL | `github.com/foo/modules//services/webserver-cluster?ref=v0.0.1` | Double-slash separates repo from path inside it; `ref` = tag/branch/sha1 |
| Private Git (SSH) | `git@github.com:acme/modules.git//example?ref=v0.1.2` | Use ssh-agent, not hardcoded creds; verify with `git clone` of the base URL |
| Mercurial / arbitrary HTTP | (URL-based) | other supported source types |

| Path reference | Meaning |
|---|---|
| `path.module` | Filesystem path of the module where the expression is defined (use for module files like user-data) |
| `path.root` | Filesystem path of the root module |
| `path.cwd` | Current working directory; normally equals `path.root`, differs when Terraform runs from elsewhere |

| Semver increment | Trigger |
|---|---|
| MAJOR | Incompatible API changes |
| MINOR | Backward-compatible functionality added |
| PATCH | Backward-compatible bug fixes |

## Worked Example
Turning the single-tenant web server cluster (ASG + ALB + security groups, from Chapter 3) into a reusable, versioned module:

1. **Extract:** `terraform destroy` the stage copy; move `stage/services/webserver-cluster` into `modules/services/webserver-cluster`; delete the provider block (providers belong in root modules only).
2. **Consume:** in `stage/services/webserver-cluster/main.tf` and a new `prod/services/webserver-cluster/main.tf`, declare a `module "webserver_cluster"` block pointing at the local path; run `terraform init`.
3. **Fix hardcoded names:** add `cluster_name` variable; set resource names to `"${var.cluster_name}-alb"`, `"${var.cluster_name}-instance"`, and the ASG Name tag. Fix hardcoded state: add `db_remote_state_bucket`/`db_remote_state_key` variables and wire them into the `data "terraform_remote_state" "db"` config so each env reads its own state.
4. **Fix hardcoded sizing:** add `instance_type`, `min_size`, `max_size` variables into the launch configuration and ASG; staging runs `t2.micro` (2–2), prod `m4.large` (2–10).
5. **Dry up magic values:** extract port 80, `0.0.0.0/0`, protocol `-1` into a `locals` block; reference via `local.http_port`, `local.all_ips`, etc.
6. **Expose outputs:** `asg_name` and `alb_dns_name` in the module's `outputs.tf`; prod adds two `aws_autoscaling_schedule` resources (cron `0 9 * * *` scale-out to 10, `0 17 * * *` scale-in to 2) wired via `module.webserver_cluster.asg_name`; environments pass through `alb_dns_name`.
7. **Fix the path gotcha:** `user_data = templatefile("${path.module}/user-data.sh", {...})`.
8. **Fix the inline-block gotcha:** replace inline `ingress`/`egress` in the ALB security group with separate `aws_security_group_rule` resources and output `alb_security_group_id`, so stage can add a testing-only rule (`from_port = 12345`) from outside the module.
9. **Version:** split into `modules` and `live` repos; `git tag -a v0.0.1`, push `--follow-tags`, point sources at `github.com/foo/modules//services/webserver-cluster?ref=v0.0.1`; test v0.0.2 in stage, promote to prod only after it proves stable.

## Key Takeaways
- Any folder of Terraform files is a module; reusable modules are consumed via a `module` block's `source` — stop copy-pasting between environments.
- Input variables are the module's API; design them deliberately because changing them is an API change (semver MAJOR/MINOR/PATCH).
- Locals keep shared/magic values DRY and private; outputs are how consumers reach into what a module created.
- Always use `${path.module}` for module-internal file references; bare relative paths break the moment code lives in a separate folder.
- Prefer separate resources (`aws_security_group_rule`) over inline blocks in modules — inline blocks make the module unconfigurable from outside; never mix the two for one setting.
- Keep reusable modules in a `modules` repo (blueprints) tagged with semver releases; environment config lives in a `live` repo (houses) and pins `?ref=<tag>`.
- Promote versions stage → prod and roll back by re-pinning a tag; use local file paths only for fast local iteration.
- Code-level environment isolation isn't enough: run each environment in its own VPC, ideally its own AWS account.

## Connects To
- **Ch 3** — supplies the single web-server-cluster config (ASG/ALB/security groups, remote state, `user_data`) that gets modularized; introduced variables, outputs, and the S3 backend this chapter builds on.
- **Ch 5** — tackles what reusable multi-team modules still need: conditionals (e.g., moving the prod-only scheduled scaling into the module), loops (count/for_each), and zero-downtime rollouts.
- **Ch 7** — providers: why they're configured only in root modules and how to manage them.
- **Ch 6 (testing)** — modules are what you validate with code reviews and automated tests (Terratest-style) before tagging a release.