# Chapter 7: CI/CD pipelines as code

## Core Idea
Separate **static infrastructure** (changes rarely — VMs, load balancers, pipeline plumbing → Terraform's wheelhouse) from **dynamic infrastructure** (changes constantly — application code → CI/CD pipelines like Cloud Build); Terraform plans are too slow to front application deployment.

## Frameworks Introduced
- **Two-Stage Deployment** (static vs dynamic):
  - When: any project where app code changes far more often than infrastructure
  - How: Terraform applies the foundation once (monorepo `infrastructure/` folder); pushes to a source repo trigger build-test-release-deploy without touching Terraform (monorepo `application/` folder)
  - Even a Kubernetes cluster can be static Terraform while Helm charts go to a separate workspace
- **for_each > count** (recommended default): takes a map/set, addresses instances by key (`<type>.<name>["<key>"]`), exposes `each.key`/`each.value`; adding/removing a middle element doesn't shift later references the way count's index does
  - Use count only when you genuinely need positional access (e.g. the round-robin Mad Libs pattern)
- **Dynamic Blocks**: "the rarest of all Terraform expressions" — generate repeating nested config blocks from complex types: `dynamic "<block>" { for_each = ...; content { ... } }` with `step.value` accessors and `lookup(step.value, "env", null)` for optional fields
  - Use sparingly — they hurt readability — and pair with locals/variables instead of hardcoding
- **Provisioners as Last Resort**: creation-time `provisioner { when = "apply" (default) }` runs after Create() exits but before "created"; destruction-time (`when = destroy`) runs before Delete()
  - null_resource + creation-time script + destruction-time script = bootleg custom resource (or use the Shell provider, appendix D)
  - HashiCorp calls provisioners an anti-pattern (lesser ones deprecated in 0.13); local-exec undermines declarative+stateful; sleep-delay hacks fix provider race conditions that deserve bugs filed
- **Implicit vs Explicit Providers**: provider blocks are implicit by default; explicit `provider = <alias>` at resource/module level overrides — for multi-region deploys or the google-beta provider (needed for early Cloud Run)

## Key Concepts
- **GCP service enabling**: `google_project_service` must run before everything; only the magic-modules-generated GCP provider needs local-exec sleeps (60s after create, 15s before destroy) to dodge API race conditions
- **Pipeline stages**: commit → test → build → release (Container Registry) → deploy (Cloud Run); Cloud Run = Knative serverless containers, default Deny All; open with `roles/run.invoker` to `allUsers`
- **Cloud Run image placeholder**: the `image` argument must exist at apply time but gets overridden by the first build — point it at Google's demo image
- **Cloud Build IAM**: grant `roles/run.admin` + `roles/iam.serviceAccountUser` to the Cloud Build service account
- **Monorepo split**: `infrastructure/` (Terraform) + `application/` (code, Dockerfile, tests) in one project dir

## Code Examples
```hcl
# for_each over a set of API services, with creation/destroy provisioners
resource "google_project_service" "enabled_service" {
  for_each = toset(local.services)
  project  = var.project_id
  service  = each.key
  provisioner "local-exec" { command = "sleep 60" }          # creation-time
  provisioner "local-exec" { when = destroy; command = "sleep 15" }
}

# Dynamic block generating build steps from a local list
build {
  dynamic "step" {
    for_each = local.steps
    content {
      name = step.value.name
      args = step.value.args
      env  = lookup(step.value, "env", null)
    }
  }
}

# Bootleg custom resource
resource "null_resource" "cowsay" {
  provisioner "local-exec" { command = "cowsay Hello World!" }
  provisioner "local-exec" { when = destroy; command = "cowsay -d Goodbye cruel world!" }
}
```
- **What it demonstrates**: the GCP CI/CD pipeline: sourcerepo → cloudbuild trigger (dynamic steps) → IAM for Cloud Build → cloud_run_service (demo image) + public invoker policy

## Reference Tables (Provisioner reference, table 7.1)
| Provisioner | What it does |
|---|---|
| file | copies files/dirs from the Terraform machine to the new resource |
| local-exec | arbitrary process on the machine *running Terraform* |
| remote-exec | script on the remote resource after creation (bootstrap, CM tools) |

## Key Takeaways
1. Sort your design first: what changes rarely (static/Terraform) vs. often (dynamic/CI/CD).
2. Default to for_each over count — keyed addressing beats index addressing for both readability and mutation stability.
3. Declare helper locals right above where they're used.
4. Provisioners are backdoors into the runtime: last resort only, and file bugs instead of shipping sleeps.
5. GCP requires explicit API enabling before any resource will provision — do it first, gated by depends_on.

## Connects To
- **Ch 12**: Terraform itself *in* a CI/CD pipeline (plan/apply stages)
- **Ch 8**: multi-cloud capstone with Nomad/Consul
- **Appendix D**: Shell provider — custom resources without provisioners
- **Ch 13**: provisioners' security implications