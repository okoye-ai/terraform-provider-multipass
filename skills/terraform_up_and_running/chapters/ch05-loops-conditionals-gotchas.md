# Chapter 5: Tips and Tricks: Loops, If-Statements, Deployment, and Gotchas

## Core Idea
Terraform is declarative and has no for-loops or if-statements, but primitives — `count`, `for_each`, `for` expressions, string directives, the ternary operator, `create_before_destroy`, and built-in functions — let you emulate loops, conditionals, and zero-downtime deployments; each has sharp edges (identity-by-index, plan-time evaluation, state-coupled identifiers) that can silently destroy infrastructure.

## Frameworks Introduced

### 1. Loops with `count`
- **When to use**: Simplest iteration over resources/modules; also the idiomatic way to do *conditional* creation (count = 0 or 1). Author's rule: "use count to conditionally create resources and modules, and for_each for all other types of loops and conditionals."
- **How**: Set `count = <number>`; access the iteration index via `count.index`. Combine with `length(<ARRAY>)` and array lookup `ARRAY[<INDEX>]` to loop over a list of values. After using count, the resource becomes an *array*: reference attributes as `<PROVIDER>_<TYPE>.<NAME>[INDEX].ATTRIBUTE`, or all of them with a splat `[*]`. Works on modules too (Terraform 0.13+), turning a module into an array of modules.
- **Fatal limitation**: Terraform identifies copies by *position (index)* in the array. Removing an item from the middle shifts subsequent items, so Terraform renames/destroys and recreates everything after that point — potential downtime and data loss.

### 2. Loops with `for_each`
- **When to use**: Almost always preferred over count for creating multiple copies of a resource, inline block, or module, because identity is by key, not position.
- **How**: `for_each = <COLLECTION>` where COLLECTION must be a *set or map* (lists are not supported on resources — wrap lists with `toset()`). Use `each.key` / `each.value` in config. The resource becomes a *map* of resources; extract values with `values(<MAP>)[*].attr`. Removing a middle item destroys only that exact resource. Also enables dynamic inline blocks via the `dynamic` block (see below), and works on modules identically.

### 3. Loops with `for` expressions
- **When to use**: Transforming a value (a single variable/parameter/output), not creating copies of resources — Terraform's analog of Python list comprehensions.
- **How**:
  - List output: `[for <ITEM> in <LIST> : <OUTPUT>]`, with optional filter `[for x in list : <OUT> if <COND>]`
  - Map loop: `[for <KEY>, <VALUE> in <MAP> : <OUTPUT>]`
  - Map output: `{for <ITEM> in <LIST> : <KEY> => <VALUE>}` (curly braces, arrow-separated key/value)
  - Combine `for_each` + a `for` expression to conditionally filter/transform the collection a resource loops over (arbitrary conditional logic on inline blocks).

### 4. Loops with the `for` string directive
- **When to use**: Rendering loops *inside a string* (template generation, e.g. comma-separated lists, generated config text).
- **How**: `%{ for <ITEM> in <COLLECTION> }<BODY>%{ endfor }` (index variant: `%{ for i, item in ... }`). Use `${…}` for interpolation inside. Trailing/extra whitespace is fixed with strip markers `~` (`%{~ for ... ~}`) and with the `if` directive.

### 5. Conditionals
- **count param (if/if-else)**: `count = <CONDITION> ? 1 : 0` creates a resource conditionally; two resources with mirrored ternaries (`? 1 : 0` and `? 0 : 1`) simulate if-else. Prefer this over for_each for pure conditionals — simpler than passing empty/nonempty collections.
- **for_each conditionals**: pass an empty collection → zero copies; combine with a `for` expression filter for conditional inline blocks.
- **`if` string directive**: `%{ if <CONDITION> }<TRUEVAL>%{ endif }` and `%{ if C }T%{ else }F%{ endif }` inside strings/HEREDOCs; use `~` strip markers to control whitespace.
- **Ternary operator**: `<CONDITION> ? <TRUE_VAL> : <FALSE_VAL>` — used for picking values (e.g., which output to expose).
- **Safe if-else attribute access**: instead of a brittle duplicated ternary, use `one(concat(A[*].attr, B[*].attr))` — `concat` joins the two lists (one is always empty), `one` returns null for empty, the element for exactly one, and errors if >1 — so the output stays correct no matter how the condition evolves.

### 6. Zero-Downtime Deployment (create_before_destroy pattern)
- **When to use**: Replacing stateful/traffic-serving resources (ASG behind an ALB) where destroy-then-create means downtime. (Original technique credit: Paul Hinze.)
- **How** (3 steps on the ASG):
  1. Make the ASG's `name` depend on the launch configuration's name (`name = "${var.cluster_name}-${aws_launch_configuration.example.name}"`) so any change to AMI/User Data forces ASG replacement.
  2. `lifecycle { create_before_destroy = true }` — create the replacement ASG before destroying the original.
  3. `min_elb_capacity = var.min_size` — wait for that many new servers to pass ALB health checks before tearing down the old ASG.
- **Mechanics**: v1 and v2 run simultaneously, ALB routes to both (users see responses alternate), old ASG is deregistered then shut down. Rollback is automatic: if v2 fails health checks, Terraform waits `wait_for_capacity_timeout` (default 10 min), deletes v2, errors out, and v1 keeps serving.
- **Preferred modern alternative**: native, first-class deployment mechanisms — ASG `instance_refresh` (Rolling strategy, `min_healthy_percentage`), ECS `deployment_maximum_percent`/`deployment_minimum_healthy_percent`, Kubernetes `strategy = "RollingUpdate"` with `rolling_update`. Prefer native over create_before_destroy glue whenever the resource supports it.

### 7. Safe Refactoring (state-aware refactoring + `moved` blocks)
- **When to use**: Renaming variables used in `name` parameters, renaming resource identifiers, splitting modules, or adding count/for_each to existing resources — all of which Terraform reads as destroy + create.
- **How**: Update state, never by hand-editing files:
  - `terraform state mv <ORIGINAL_REFERENCE> <NEW_REFERENCE>` (manual; success check = subsequent plan shows no changes), or
  - a `moved { from = ...; to = ... }` block in code (Terraform 1.1+) — automatic, versioned with the code, so every consumer of a shared module gets the migration on their next apply.

## Key Concepts
- **meta-parameter**: A parameter (`count`, `for_each`, `lifecycle`, …) available on every resource/module that controls Terraform's behavior rather than the resource's config.
- **count.index**: The index of the current "iteration" when a resource is replicated with count.
- **each.key / each.value**: Accessors for the current item when looping with for_each (key usually only meaningful with maps).
- **splat expression (`[*]`)**: Shorthand to get an attribute from all elements of a resource array/map, e.g. `aws_iam_user.example[*].arn`.
- **`toset()`**: Converts a list to a set so it can be used with for_each on a resource (only sets/maps allowed).
- **dynamic block**: `dynamic "<VAR>" { for_each = ...; content { ... } }` — generates repeated inline blocks inside a resource.
- **for expression**: Inline loop/filter/transform over lists and maps, outputting a list `[...]` or map `{...}`.
- **string directives**: `%{ ... }` control statements (for, if/else) inside strings; `${ ... }` interpolates values.
- **strip markers (`~`)**: `%{~ ... ~}` swallow surrounding whitespace in HEREDOC/template rendering.
- **`one()` / `concat()` functions**: concat flattens lists; one returns null/element/error for 0/1/many — together they make if-else outputs robust.
- **`min_elb_capacity`**: Number of instances that must pass ALB health checks before Terraform considers the new ASG ready.
- **`terraform import`**: Brings existing out-of-band infrastructure into state; args = resource address + provider-specific ID.
- **`moved` block**: Declarative, in-code state migration for refactors (Terraform 1.1+).

## Mental Models
- **Use for_each when identity matters; use count when only the number matters.** count identifies copies by array position (fragile to list edits); for_each identifies by key (safe removals).
- **Use count (0/1) when you need a conditional; use for_each when you need iteration.** Count-based conditionals are simpler than crafting empty/nonempty collections.
- **plan is a prediction, not a guarantee.** plan only sees state; out-of-band resources and apply-time values make valid plans fail anyway.
- **Refactoring Terraform changes "external behavior" by definition**: any identifier/name/loop-structure change is a destroy-create unless the state is moved alongside.

## Anti-patterns (the Gotchas)
- **Removing an item from the middle of a count-looped list**: every resource after that index is destroyed and recreated (availability loss; data loss if it's a DB). Fix: for_each, or `terraform state mv`/moved block.
- **count inside inline blocks is unsupported**: you cannot loop `tag {}`-style nested blocks with count; use `dynamic` + for_each instead.
- **Referencing resource outputs in count/for_each**: `count = random_integer.num_instances.result` fails at plan ("Invalid count argument" — value cannot be determined until apply). count/for_each may use constants, variables, data sources, and *lengths* of resource lists, but not computed resource attributes.
- **create_before_destroy + auto scaling policies**: each deployment resets ASG size to min_size (a 9 a.m. scale-out to 10 is undone by an 11 a.m. deploy → 2 servers until the next recurrence). Workarounds are hacky; prefer native instance refresh.
- **create_before_destroy glue vs. native mechanisms**: stringing together create_before_destroy + min_elb_capacity + custom scripts is fragile; AWS ECS/Kubernetes resources offer first-class rolling deployments — check provider docs first.
- **Valid-looking plans that fail at apply**: e.g., creating an `aws_iam_user` that already exists → `EntityAlreadyExists`. plan only examines the state file; manually created resources are invisible to it. Lessons: use only Terraform for anything Terraform manages; `terraform import` pre-existing resources (bulk: terraformer, terracognita).
- **Renaming a variable that feeds a `name` parameter** (e.g., cluster_name foo → bar renames the ALB/security groups): Terraform deletes and recreates them → traffic-serving gap = outage.
- **Renaming a resource identifier** (`aws_security_group.instance` → `.cluster_instance`), splitting modules, or adding count/for_each after the fact: identical effect — destroy + create, downtime.
- **HEREDOC whitespace leakage**: every space/newline in a HEREDOC lands in the rendered string; fix with `~` strip markers, not manual fiddling.
- **Brittle duplicated conditionals in outputs**: a hand-copied ternary that indexes `[0]` on a conditionally-created resource breaks confusingly when the condition changes; prefer `one(concat(...[*]...))`.

## Code Examples

Loops over a list of names with count (and the for_each version to prefer):
```hcl
resource "aws_iam_user" "example" {
  count = length(var.user_names)
  name  = var.user_names[count.index]
}

resource "aws_iam_user" "example" {
  for_each = toset(var.user_names)
  name     = each.value
}
```

Dynamic inline blocks for custom ASG tags, filtered/transformed with a for expression:
```hcl
dynamic "tag" {
  for_each = {
    for key, value in var.custom_tags:
    key => upper(value)
    if key != "Name"
  }

  content {
    key                 = tag.key
    value               = tag.value
    propagate_at_launch = true
  }
}
```

If/if-else via count + ternary, and the robust single output:
```hcl
resource "aws_autoscaling_schedule" "scale_out_during_business_hours" {
  count = var.enable_autoscaling ? 1 : 0
  # ...(config)...
}

output "neo_cloudwatch_policy_arn" {
  value = one(concat(
    aws_iam_user_policy_attachment.neo_cloudwatch_full_access[*].policy_arn,
    aws_iam_user_policy_attachment.neo_cloudwatch_read_only[*].policy_arn
  ))
}
```

The zero-downtime ASG pattern:
```hcl
resource "aws_autoscaling_group" "example" {
  name = "${var.cluster_name}-${aws_launch_configuration.example.name}"
  # ...
  min_elb_capacity = var.min_size

  lifecycle {
    create_before_destroy = true
  }
}
```

Safe refactor as code:
```hcl
moved {
  from = aws_security_group.instance
  to   = aws_security_group.cluster_instance
}
```

## Reference Tables

**count vs for_each vs for vs for-directive decision table**

| Construct | Loops over | Applies to | Identity of copies | Use when |
|---|---|---|---|---|
| `count` | a number (0–N) via index | resources, modules | array position (fragile) | fixed N; conditional creation (0/1); list iteration where list never shifts |
| `for_each` | set or map via key | resources, modules, inline blocks (via `dynamic`) | map key (stable) | almost all resource/module replication; removable items; per-key config |
| `for` expression | list or map | values (variables, outputs, arguments) | n/a (not copies) | transforming/filtering a collection into a list `[...]` or map `{...}` |
| `for` string directive | list or map | strings | n/a | rendering iterated text inside a string/HEREDOC |
| `dynamic` + for_each | list or map | inline blocks within a resource | map key | repeated nested blocks (tags, etc.) |

**When you can't use for_each / count (hard limitations)**
- `count` cannot loop over inline blocks within a resource (use `dynamic`).
- `for_each` on resources/modules accepts sets and maps only — not raw lists (wrap with `toset()`).
- Neither `count` nor `for_each` may reference computed resource outputs — the value must be computable at plan time (constants, variables, data sources, and known-length list attributes are fine).
- `aws_autoscaling_group` doesn't support provider `default_tags` (set its tags explicitly).

**Refactor-safety rules**
| Change | Effect without state fix | Fix |
|---|---|---|
| rename var feeding a `name` param | destroy + create of named resources (outage) | never change it, or plan + create_before_destroy |
| rename resource identifier | destroy + create | `terraform state mv` or `moved` block |
| split a module / add count or for_each late | destroy + create | same state-migration fix |

## Worked Example — Zero-downtime rollout of new server text (stage webserver cluster)
1. Module exposes `ami` and `server_text` variables; User Data renders `${server_text}` into `index.html` via `templatefile`; the launch configuration takes `image_id = var.ami` and already has `lifecycle { create_before_destroy = true }` (required for ASG + launch configuration).
2. Change `server_text = "New server text"` in `live/stage/services/webserver-cluster/main.tf` and run plan: it shows launch configuration replacement (`user_data ... forces replacement`) and an in-place ASG update — but an in-place pointer change deploys nothing until new instances launch.
3. First attempt (destroy/recreate ASG) means downtime. Fix: ASG `name = "${var.cluster_name}-${aws_launch_configuration.example.name}"` (forces ASG replacement whenever the launch configuration changes), `create_before_destroy = true`, `min_elb_capacity = var.min_size`.
4. Re-plan: both resources now say "must be replaced" (`Plan: 2 to add, 2 change, 2 destroy`). Apply: v2 instances boot, connect to the DB, register in the ALB, pass health checks; v1+v2 serve traffic concurrently (a `while true; do curl ...; sleep 1; done` loop shows responses flip-flopping between old and new text); once `min_elb_capacity` servers are healthy, Terraform deregisters and shuts down v1.
5. Failure path: if v2 never passes health checks, Terraform waits up to `wait_for_capacity_timeout` (10 min default), deletes the v2 ASG, and exits with an error while v1 keeps serving — automatic rollback.
6. Production-grade variant: undo the name/capacity/lifecycle hacks and use AWS's native `instance_refresh { strategy = "Rolling"; preferences { min_healthy_percentage = 50 } }` — fully AWS-managed, error-handled, though slower (up to ~20 min for two instances).

## Key Takeaways
- Prefer `for_each` (wrapping lists in `toset()`) for almost all replication — it identifies copies by key, so mid-list removals destroy exactly one resource instead of shifting indices.
- Prefer `count = cond ? 1 : 0` for conditional creation (and mirrored ternaries for if-else); return `one(concat(A[*].attr, B[*].attr))` for robust if-else outputs.
- Use `for` expressions to transform values (list `[...]` or map `{...}`, with `if` filters) and `%{ for }`/`%{ if }` string directives (with `~` strip markers) to template strings.
- Use `dynamic` blocks for repeated inline blocks — count doesn't work inside them.
- For zero-downtime deployments, prefer native mechanisms (ASG instance refresh, ECS deployment percents, Kubernetes RollingUpdate) over the create_before_destroy/min_elb_capacity workaround; the workaround also resets ASG size to min_size on every deploy.
- Terraform state is its whole world: never manage a Terraform-managed resource by hand, and `terraform import` (or terraformer/terracognita at scale) anything that already exists.
- Never hand-edit state; refactor identifiers/modules/loop-structures with `terraform state mv` or, better, a `moved` block committed with the code (correct refactor = plan shows no changes).
- Always run plan and scan for unexpected destroys; check resource docs for immutable/force-replacement parameters before changing them.

## Connects To
- **Ch. 1–2**: count first appears with `create_before_destroy` in the launch configuration; declarative vs. procedural IaC trade-offs.
- **Ch. 4**: builds on the webserver-cluster module and input variables; the conditional `enable_autoscaling`/`custom_tags` pattern is how you turn a module blueprint into a clean, simple API for its consumers; `templatefile` powers User Data.
- **Ch. 6**: designing modules that handle secrets and sensitive data (the "clean module API" goal continues).
- **Ch. 9**: enforcing tagging standards ("all resources must have a ManagedBy tag") as policy-as-code with tools like OPA; `default_tags` as the baseline-tagging mechanism.
- **Chapter's forward pointer**: native deployment features (instance refresh, ECS/Kubernetes rolling updates) over Terraform glue.