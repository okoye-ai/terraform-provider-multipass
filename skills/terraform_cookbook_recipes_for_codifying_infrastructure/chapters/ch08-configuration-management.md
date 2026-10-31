# Chapter 8: Configuration Management with Terraform

## Core Idea
Terraform doesn't manage software inside servers, but it does orchestrate configuration management: it provisions the infrastructure, bootstraps it (shell scripts via `user_data`), feeds it dynamic values (Consul KV, HTTP data sources, templates), orders and gates it (dependencies, conditionals, workspaces), and can import or blue/green-swap it.

## Frameworks Introduced
- **Launch-time bootstrap with `user_data`**: inject a shell script that runs once at EC2 first launch.
  - When to use: lightweight setup software/config at provision time.
  - How: `user_data = <<-EOF ... EOF` heredoc on the resource; for longer scripts, store them in separate files and load with the `file()` function. Runs only once — later changes need SSH or a config management tool (Ansible, Chef).
- **Terraform-as-Ansible-bootstrap**: provision the instance and drop in Ansible itself plus its config.
  - When to use: Ansible owns ongoing config, Terraform bootstraps the ground.
  - How: `user_data` does `apt-get install -y ansible`, then `echo "${file("ansible.cfg")}" > /etc/ansible/ansible.cfg` (and `hosts`); after launch, Ansible playbooks take over.
- **Consul KV dynamic configuration**: read runtime configuration from a Consul key-value store instead of hard-coding it.
  - When to use: environment-specific or frequently changing parameters you want to change without touching Terraform code.
  - How: `consul` provider (address, datacenter), then `data "consul_keys"` blocks declaring `name` (local reference), `path` (key path), `default` (fallback); consume as `${data.consul_keys.app.var.<name>}`.
- **HTTP data source consumption**: pull any configuration or external data from an HTTP(S) endpoint.
  - When to use: real-time external facts (e.g. `ipinfo.io/json`) or config APIs integrated into resources.
  - How: `data "http"` with `url`; a GET is made on state refresh; parse with `jsondecode(data.http.<name>.response_body)`, inspect `response_headers`; use `request_headers`/`method` for more, HTTPS + sensitive outputs for secrets, caching/local vars to avoid repeat calls.
- **Conditional resource creation with `count`**: create a resource only when a condition holds.
  - When to use: boolean feature flags like "create instance only if `var.create_instance` is true."
  - How: `count = var.create_instance ? 1 : 0`; compute complex conditions in a `local`; reference results with index syntax (`aws_instance.example[0]`); prefer `for_each` when individual instances must be added/removed independently. Caution: flipping the flag destroys the resource.
- **Config-driven import**: bring existing (manually created or other-tool) infrastructure under Terraform via `import` blocks in code.
  - When to use: adopting Terraform for pre-existing resources, especially in teams where imports must be version-controlled.
  - How: define a matching resource block, write `import { to = ... id = ... }`, then `terraform plan -generate-config-out=generated_resources.tf` to generate full config from actual state.
- **Workspace-based environment isolation**: one configuration, many environments, each with its own state file.
  - When to use: dev/staging/prod sharing identical configuration but requiring isolation.
  - How: `terraform workspace new dev`, switch with `terraform workspace select <name>`, differentiate resources with `terraform.workspace` interpolation (tags, names).
- **Template rendering with `template_file`**: keep multiline/complex config (cloud-init, scripts) in separate `.tpl` files.
  - When to use: complex `user_data` you want maintainable, reusable, and in version control separately.
  - How: write `user_data.tpl` with `${hostname}` placeholders (Go templates — conditionals and loops allowed), render with `data "template_file"` (`template = file(...)` + `vars`), consume `data.template_file.<name>.rendered`.
- **Blue-green deployment via conditional counts + ELB**: two identical environments, one live, one idle; traffic switches by variable.
  - When to use: zero-downtime application releases you want Terraform to orchestrate.
  - How: `variable "color"` (blue|green); `aws_instance.blue` with `count = var.color == "blue" ? 2 : 0` (and green likewise); `aws_elb` routes both via `concat(aws_instance.blue.*.id, aws_instance.green.*.id)`; flip `color` and `terraform apply`.

## Key Concepts
- **user_data**: instance-launch parameter holding a script (heredoc or `file()`-loaded) that runs exactly once at first boot.
- **config-driven import**: the newer `import { to, id }` block syntax, preferred over CLI-based `terraform import` because it lives in version-controlled files.
- **-generate-config-out**: `terraform plan` flag that writes a `generated_resources.tf` with complete configuration reconstructed from an imported resource's actual state.
- **terraform.workspace**: read-only expression for the current workspace name, used to tag or differentiate resources per environment.
- **template_file data source**: renders a Go-templated file with `vars`, exposing the result as `.rendered`.
- **implicit dependency**: order Terraform infers automatically from an attribute reference between resources (e.g. `vpc_security_group_ids = [aws_security_group.sg.id]`).
- **explicit dependency**: order you force with `depends_on` when Terraform cannot infer it — use sparingly, since it limits parallelism.
- **blue-green deployment**: two identical production environments (one live, one idle) with traffic switched after the idle one is fully tested.
- **dynamic configuration**: values sourced at apply-time from external stores (Consul KV, HTTP) so behavior changes without code edits.

## Mental Models
- Use Terraform to manage infrastructure and *delegate* software configuration — bootstrap with `user_data`, then hand off to Ansible/Chef playbooks for anything ongoing.
- Use external data sources (Consul KV, HTTP) when configuration values change more often than Terraform code and should be editable outside a plan/apply cycle.
- Use implicit dependencies whenever possible and reach for `depends_on` only when no attribute reference exists — explicit ordering serializes what could run in parallel.
- Use workspaces (or separate config files) for significantly different environments, and reserve conditional `count` logic for minor, well-understood differences.

## Anti-patterns
- **Expecting `user_data` to re-run**: the script executes only once at first launch; changing it on a running instance does nothing — use SSH or a config management tool.
- **Inlining complex scripts in resources**: multiline logic in heredocs hurts maintainability; use separate files via `file()` or `template_file` templates.
- **Flipping conditional `count` flags casually**: setting the condition to false on an existing resource destroys it on next apply — potential data loss or downtime.
- **Overusing conditional logic**: frequent toggles and interdependent conditional resources become hard to reason about and maintain.
- **Unrestrained `depends_on`**: explicit dependencies reduce parallelism and slow applies; also be mindful of creation order for critical dependencies.
- **Trusting external endpoints blindly**: HTTP/Consul data sources must be reliable, secured, and error-handled; sensitive data requires HTTPS and sensitive outputs.
- **Assuming import completes the migration**: Terraform manages the imported resource's state but does not auto-update your config to match its current settings — you must reconcile manually.
- **Treating blue-green as trivially safe**: real deployments involve database migrations, stateful components, and extensive idle-environment testing before the switch.

## Code Examples
```hcl
resource "aws_instance" "example" {
  ami           = "ami-0c94855ba95c574c8"
  instance_type = "t2.micro"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF
}
```
- **What it demonstrates**: the `user_data` bootstrap pattern — a heredoc shell script running once at launch (`nohup` to background the server so the script completes).

```hcl
import {
  to = aws_instance.imported
  id = "i-1234567890abcdef0"
}
```
followed by:
```
terraform init
terraform plan -generate-config-out=generated_resources.tf
```
- **What it demonstrates**: config-driven import — declare the `import` block in code, then let plan generate full resource configuration from the live resource's actual state.

```hcl
variable "color" {
  description = "Deployed environment color: blue or green"
  default     = "blue"
}
resource "aws_instance" "blue" {
  count         = var.color == "blue" ? 2 : 0
  ami           = "ami-0c94855ba95c574c8"
  instance_type = "t2.micro"
}
resource "aws_instance" "green" {
  count         = var.color == "green" ? 2 : 0
  ami           = "ami-0c94855ba95c574c8"
  instance_type = "t2.micro"
}
resource "aws_elb" "example" {
  instances = concat(aws_instance.blue.*.id, aws_instance.green.*.id)
}
```
- **What it demonstrates**: blue-green with conditional `count` — flipping `color` and applying creates the new set, adds it to the ELB, then destroys the old set.

## Reference Tables
None in this chapter.

## Worked Example
Importing existing infrastructure (8.6) — the chapter's most concrete end-to-end flow:
1. **Define a matching resource block** (`aws_instance.imported` with AMI, type, tags) — it need not be complete; the block just has to exist. Comment notes the real ID fills in after import.
2. **Declare the import in code**: `import { to = aws_instance.imported  id = "i-1234567890abcdef0" }` — `to` is the Terraform address, `id` the provider-side identifier (instance ID for EC2; the format is provider-specific, so check provider docs).
3. **Run** `terraform init`, then `terraform plan -generate-config-out=generated_resources.tf`, which writes a file containing the complete resource configuration reconstructed from the imported resource's actual state.
Caveats carried through the recipe: importability and ID format depend on the provider; not all attributes import (some must be set manually afterwards); state is managed but configuration is *not* auto-synced; be careful with sensitive data in imported resources. The payoff: imports are version-controlled and reviewable in teams.

## Key Takeaways
1. Terraform provisions and orders infrastructure; dedicated config management tools (Ansible, Chef) own what happens *inside* servers after the one-shot `user_data` bootstrap.
2. `user_data` runs exactly once at first launch — anything beyond initial setup needs a config management tool or manual access.
3. Move complex scripts into separate files (`file()`) or Go-templated `user_data.tpl` files rendered by `template_file` — cleaner, reusable, diffable in Git.
4. Source volatile configuration from Consul KV (with `default` fallbacks) or HTTP endpoints so values can change without touching Terraform code.
5. Gate resource creation with `count = cond ? 1 : 0`, computing complex conditions in locals — but never toggle a flag that would destroy an in-use resource.
6. Adopt existing infrastructure with config-driven `import` blocks plus `plan -generate-config-out`, then reconcile the generated config manually.
7. Isolate environments with workspaces (one config, one state file per workspace, `terraform.workspace` for tagging) and reserve `depends_on` for orders Terraform can't infer.

## Connects To
- **Ch 7**: workspaces here are the same mechanism recommended there for isolating production secrets into separate state files.
- **Ch 8 recipe 8.5 → 8.10**: the conditional `count` pattern from 8.5 scales directly into blue-green deployment gating in 8.10.
- **Ch 3 (provisioners/functions)**: `file()`, heredocs, and `jsondecode` are the function toolbox this chapter's recipes lean on.
- **Ansible/Chef**: external config management tools Terraform bootstraps but does not replace.
- **Go templates**: the engine behind `template_file` rendering, enabling conditionals and loops in template files.