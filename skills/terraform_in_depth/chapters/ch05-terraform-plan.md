# Chapter 5: The Terraform plan

## Core Idea
Terraform represents your infrastructure — and every plan it generates — as a directed acyclic graph (DAG); understanding that graph explains why plans print in the order they do, why changes cascade, and why most Terraform errors (cycles, hidden dependencies, uncomputable `for_each`) happen and how to fix them.

## Frameworks Introduced
- **Directed acyclic graph (DAG)**: a graph (nodes + edges) whose edges have direction (dependencies) and which contains no circles.
  - When to use: "infrastructure, and in particular the relationships between different components in infrastructure, can be represented by DAGs" — the insight that enabled IaC tools. Most declarative languages use DAGs.
  - How: you define the edges yourself in code by linking resources together through attributes and parameters; a cycle makes Terraform fail with an error.
- **The Terraform resource graph**: the central data structure all Terraform operations revolve around; "Terraform state is essentially a snapshot of the resources in that graph."
  - When to use: debugging errors, understanding blast radius of changes.
  - How: three node types — **Resources** (each resource/data source instance, expanded per count/for_each), **Provider Configuration Node** (one per provider configuration; every resource depends on one), and **Resource Meta Node** (a convenience group when count > 1).
- **Three planning modes**: default, destroy (`-destroy`), and refresh-only (`-refresh-only`).
  - When to use: default for nearly everything; destroy to tear down a configuration (common in dev cycles); refresh-only to update state without any infrastructure changes (drift detection).
  - How: every plan starts with a refresh; refresh-only *stops after* the refresh.
- **Four categories of plan-altering pitfalls**: circular dependencies, cascading changes, hidden dependencies, and always-detected changes — all rooted in the DAG.
  - When to use: whenever a plan shows more (or fails harder) than your code change implies.

## Key Concepts
- **Speculative plan**: a plan you do not intend to apply (no `-out` file) — common in development; Terraform warns it can't guarantee the same actions later.
- **Plan file (.tfplan)**: binary, not human-readable; the authoritative plan `terraform apply` can consume so the reviewed plan is exactly what runs.
- **Refresh**: the lookups at the start of every plan comparing stored state to real infrastructure, detecting drift.
- **-replace flag**: plan a destroy-and-create of a specific resource (`-/+` in output); replacement of one resource often cascades to dependents. Replaces the deprecated `terraform taint`, which mutates state immediately with no chance to review — "there's really no good reason to run it."
- **Resource targeting** (`-target`): restrict a plan to a resource and its dependencies; an antipattern for normal operations — "modules that require resource targeting to work are a massive antipattern."
- **Root-level module input variables**: the primary way to modify a plan — the same code produces different environments through them.
- **depends_on meta argument**: creates an explicit edge where the code has no attribute link, closing hidden dependencies.
- **force replacement / ignore_changes**: plan output marks replacement-triggering attributes with `# forces replacement`; add them to `lifecycle { ignore_changes = [...] }` to stop the cascade.
- **Parallelism** (`-parallelism=n`): max concurrent provider calls, default 10; dependencies and API rate limits cap its usefulness; lowering it to 1 with `TF_LOG=debug` makes logs readable.

## Mental Models
- Think of the **plan output as the graph read bottom-to-top**: resources at the bottom run first (least dependencies); for destroy plans, that also means destruction happens in the *opposite* order of creation (you can't delete a VPC before its subnets).
- Think of **Terraform plan output as a representation, not the plan**: the real plan is the binary tfplan file; `terraform show` renders it (and can convert it to JSON for programmatic review).
- Use **"what changed and why" (echoed in ch6 drift)** for scary plans: a one-line code change replacing five resources (`forces replacement`) is either expected, ignorable (`ignore_changes`), or a dependency-chain smell.
- Treat **`-refresh=false` as a giant DANGER sign**: your plan won't have up-to-date information and you can expect failed applies; even solo dev environments have automation that can change things.
- Treat **`terraform refresh` (the command) as deprecated poison**: with expired credentials it may decide resources are missing and remove them from state — use `terraform apply -refresh-only` instead, which asks for approval first.

## Anti-patterns
- **`terraform taint`**: changes state immediately with no way to pre-review; use `terraform plan -replace`.
- **Resource targeting as a workflow** (including batching slow changes by target): a sign "your project is too large and should be broken up"; the author has never had a valid production use for it.
- **`-auto-approve` on apply**: no chance to catch errors before infrastructure changes — even when you "know" nothing changed, something may have outside your workflow. (Common-but-discouraged even for `terraform destroy -auto-approve` locally.)
- **Interactive variable input in pipelines**: "relying on individuals to correctly type out all of the values ... is a great way to introduce errors"; set `-input=false` in automation.
- **`-lock=false` outside speculative plans**: concurrent applies can corrupt state; only acceptable when generating throwaway plans.
- **Ignoring the input-precedence rules**: a variable that "doesn't take effect" is almost always shadowed by a higher-precedence source; pick one method and stick with it.
- **Putting secrets in any variable input path**: `-var` lands in shell history, tfvars files in version control, env vars in logs — use CI secret stores or a secrets manager (Vault, AWS/GCP Secret Manager, Azure Key Vault), ideally passing secret *paths* so Terraform never sees the value.

## Code Examples
- **What it demonstrates**: reading and fixing a circular dependency — Terraform's `Error: Cycle:` message lists the loop; break it by routing all three through a shared variable instead of chaining resources.

```hcl
# Broken: alpha -> charlie -> bravo -> alpha
resource "null_resource" "alpha" {
  triggers = { rebuild = null_resource.charlie.id }
}

# Fixed: a higher-level variable triggers the same rebuild-all behavior
variable "build_id" {
  default = null
  type    = string
}

resource "null_resource" "alpha"   { triggers = { rebuild = var.build_id } }
resource "null_resource" "bravo"   { triggers = { rebuild = var.build_id } }
resource "null_resource" "charlie" { triggers = { rebuild = var.build_id } }
```

- **What it demonstrates**: the classic computed-value-in-count failure — `use_eip` must be decidable at plan time, so it reads the `var.domain` input, not the DNS record resource.

```hcl
locals {
  # Broken:  use_eip = endswith("example.com", aws_route53_record.name)  # resource attribute, unknown at plan time
  use_eip    = endswith("example.com", var.domain)
  ip_address = local.use_eip ? aws_eip.example[0].public_ip : aws_instance.example.public_ip
}

resource "aws_eip" "example" {
  count  = local.use_eip ? 1 : 0
  domain = "vpc"
}
```

## Reference Tables
**Input variable precedence** (highest wins; same-source repeats use the last one):
1. `-var` / `-var-file` flags (last flag wins on duplicates)
2. `*.auto.tfvars` / `*.auto.tfvars.json` (lexical order)
3. `terraform.tfvars.json`
4. `terraform.tfvars`
5. Environment variables (`TF_VAR_<name>`, case-matched)
6. Interactive prompt (fails instead if `-input=false`)

**Variable file table** (table 5.2): `*.tfvars` HCL (-var-file), `*.auto.tfvars` HCL (auto), `terraform.tfvars` HCL (auto), `*.tfvars.json` JSON (-var-file), `*.auto.tfvars.json` JSON (auto), `terraform.tfvars.json` JSON (auto). HCL tfvars supports comments; JSON does not, and rejects trailing commas.

**Graph commands** (table 5.1): `terraform graph > graph.dot`; `terraform graph | dot -Tsvg > graph.svg`; `terraform graph | dot -Tpng > graph.png`. `-type` switches plan / plan-refresh-only / plan-destroy / apply (apply graphs require a saved plan, due to a pre-1.7.0 bug, and show every individual resource).

**Always-detected-change tells** (list of provider translation bugs): int -> float, bool -> string, list order changes, mixed-case -> lowercase, missing argument -> empty string/0. Fix by matching your input to the API's format and filing the provider bug.

**Apply/plan behavior matrix**: `terraform apply` with no file = plan + confirm + apply; with a plan file = no confirmation asked (you already approved); `terraform destroy` = alias for `apply -destroy`, no plan file accepted.

## Worked Example
The chapter's recurring worked example is a development TLS certificate authority (listing 5.1) whose structure *is* a DAG: `tls_private_key.ca_key` -> `tls_self_signed_cert.ca_cert`; per-domain `tls_private_key.child_key` (for_each over `var.domains`) -> `tls_cert_request.child_request` -> `tls_locally_signed_cert.child_certificate` (signed with the CA's private key and cert). Walking it:

1. **First plan** (listing 5.2): 11 to add, 0 to change, 0 to destroy; resources listed bottom-to-top by dependency; `(known after apply)` and `(sensitive value)` flags shown; warning that an unsaved (speculative) plan can't be guaranteed.
2. **Apply** (listing 5.8): all private keys create in parallel first, then cert requests and the CA cert, then child certificates — the graph letting independent nodes run concurrently.
3. **Destroy plan** (listing 5.3): `Plan: 0 to add, 0 to change, 11 to destroy`, destruction in reverse creation order.
4. **Replace** (listing 5.4): `terraform plan -replace 'tls_private_key.child_key["charilie.example.com"]'` produces `-/+` rows — replacing one private key cascades to both its certificate request and its certificate: `Plan: 3 to add, 0 to change, 3 to destroy`.
5. **Cascading change** (listing 5.12): switching the CA key's `algorithm` from ECDSA to ED25519 forces replacement of the CA key, the CA cert, and all three child certificates — one small code change, five resources replaced, all marked `# forces replacement`. The lesson: review plans for unexpected `-/+` replacements, and silence justified ones with `ignore_changes`.
6. **Refresh-only** (listing 5.5): renaming the organization in code but running `terraform plan -refresh-only` reports "No changes" — this mode ignores code changes and only syncs state.

## Key Takeaways
1. Every plan starts with a refresh; the plan output orders resources bottom-to-top by dependency, so read destroy plans knowing teardown mirrors build order.
2. Always plan to a file (`terraform plan -out`) and apply that file in automation; the tfplan binary is the only guarantee that what you reviewed is what runs.
3. Watch for `# forces replacement` in plan output; if the replacement isn't justified, trace the triggering attribute and add it to `ignore_changes`.
4. `count`/`for_each` values must be computable at plan time — rewrite locals to use input variables and data that is plan-time-known instead of resource attributes.
5. A `Error: Cycle:` message lists the loop; break it with a shared variable/local rather than restructuring by targeting.
6. Add explicit `depends_on` for real-world dependencies with no code link (e.g. NAT Gateway needs Internet Gateway) — but the competing goal is shorter dependency chains, since those drive cascading replacements.
7. Use `terraform apply -refresh-only` (never `terraform refresh`) to sync state safely; keep parallelism low plus debug logs when diagnosing provider errors.

## Connects To
- **Ch 1**: the plan/apply stage completes the Terraform development flow (code -> plan -> review -> apply) introduced there.
- **Ch 4**: the plan-time knowledge boundary explains the count/for_each limitations met there.
- **Ch 6**: state drift detection, refresh-only, and failed-state-update recovery are chapter 6's subject; state is "a snapshot of the resource graph."
- **Ch 7/9**: speculative plans, CI variable handling, and "project too large" splitting return there.
- **Graph theory / DAG**: external concept — the same structure powers build systems and declarative package managers.
