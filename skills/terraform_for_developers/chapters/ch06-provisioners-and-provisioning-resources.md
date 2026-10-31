# Chapter 6: Provisioners and Provisioning Resources

## Core Idea
Provisioners (`file`, `local-exec`, `remote-exec`, `null_resource`) bridge Terraform's declarative model into imperative post-creation setup — but they exist outside that model, so treat them as a last resort for small, create-time-only tasks and hand ongoing configuration to cloud-init or a config-management tool.

## Frameworks Introduced
- **The Four Built-In Provisioners** — a selection rule:
  - **file**: copy files/directories to a new remote resource (needs a `connection` block)
  - **local-exec**: run a command on the machine running Terraform (CI or your laptop) — external APIs, notifications, register-in-firewall scripts
  - **remote-exec**: SSH/WinRM into the new resource and run commands — package installs, small initialization
  - **null_resource**: a dummy resource whose `triggers` map re-runs provisioners when those values change (e.g. redeploy-on-app-version-change)
- **Provisioner failure lifecycle**: a failed provisioner marks the resource **tainted** → next run destroys and recreates it → scripts must be idempotent or resilient to retries
- **Provisioners don't re-run on updates**: changes after creation need re-creation, `triggers`-based null_resource, or a config-management handoff
- **Bootstrap-don't-manage pattern**: use one remote-exec to install the Ansible agent / Chef client, then let that tool own all OS-level state; Terraform's code stays declarative

## Key Concepts
- **`connection` block**: SSH type/user/private_key/host (usually a public IP reference) shared by `file` and `remote-exec` provisioners
- **`self` object**: access the resource's own computed attributes inside its provisioner (`${self.primary_access_key}`)
- **SSH timing gap**: new VMs take 30–60s to boot and open SSH; Terraform retries briefly then times out — failed connections are a common first-minute failure
- **Idempotency requirement for remote-exec scripts**: partial installs are common; harmful re-runs must be avoided
- **Create-time vs ongoing configuration**: Terraform owns creation; config management owns the life after

## Code Examples
```hcl
# file + remote-exec combo: upload, then execute
provisioner "file" {
  source      = "configure_web.sh"
  destination = "/home/ubuntu/configure_web.sh"
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = azurerm_public_ip.web_vm_ip.ip_address
  }
}
provisioner "remote-exec" {
  inline = [
    "chmod +x /home/ubuntu/configure_web.sh",
    "/home/ubuntu/configure_web.sh"
  ]
  connection { /* same block as above */ }
}

# null_resource triggers: re-run on version change
resource "null_resource" "notify_deploy" {
  triggers = { app_version = var.app_version }
  provisioner "local-exec" {
    command = "echo Deploying version ${var.app_version}..."
  }
}
```
- **What it demonstrates**: the standard upload-then-execute pattern and trigger-driven re-provisioning

## Reference Tables
| Provisioner | Runs where | Typical use | Key risk |
|---|---|---|---|
| `file` | local → remote resource | Upload scripts, certs, config dirs | SSH may not be ready; timing failures |
| `local-exec` | Terraform runner machine | Notify (Slack webhook), external APIs, firewall registration | Machine-specific deps — breaks reproducibility |
| `remote-exec` | inside the new resource | Install packages, start services | Fails → tainted → destroy/recreate cycle |
| `null_resource` | anywhere (host of the above) | Re-run on `triggers` change; orphan tasks | Too many = procedural mess in declarative code |

| Better alternative | Replaces |
|---|---|
| cloud-init / user-data / Azure custom data | most remote-exec OS configuration |
| Ansible / Chef / Puppet | all ongoing configuration management |
| Native provider resource | most scripted API calls done via local-exec |

## Worked Example
Web-server provisioning sequence on Azure: Terraform creates the load balancer, two Linux VMs, and the database from HCL; each VM gets a `file` provisioner copying `configure_web.sh` (installs Nginx, copies index files, adjusts firewall) and a `remote-exec` provisioner running `chmod +x` then the script. The whole thing is reproducible by re-applying the code. The limit: rotating a certificate or adding a site later does *not* re-run those provisioners — that's the signal to move the logic to config management or cloud-init.

## Anti-patterns
- **Large command sets in one remote-exec**: sprawling inline scripts live only in shell commands, escape Terraform's dependency logic, and fail opaquely — keep remote-exec small or hand off to a script/config tool
- **Non-idempotent provisioner scripts**: a partial install followed by a tainted rebuild can re-run destructive steps
- **local-exec assuming the runner's environment**: works on your laptop, fails on CI — document dependencies or run only in a consistent build environment
- **Using provisioners for ongoing changes**: they fire at creation (or destroy) only; update workflows need different tooling
- **Too many null_resources**: converts a declarative codebase back into an imperative one, one trigger at a time

## Key Takeaways
1. Prefer native provider resources, cloud-init/custom data, or Ansible whenever they can do the job — provisioners are the last stop
2. Provisioner scripts must be idempotent: failed runs taint the resource and force a full destroy/recreate
3. Expect a 30–60s SSH readiness gap on fresh VMs; design for connection retries/timeouts
4. Use `null_resource.triggers` as the escape hatch for "re-run when X changes" logic — sparingly
5. Combine `file` + `remote-exec` as the standard bootstrap dance: upload the script, then run it
6. Terraform's long-term split of duties: Terraform provisions resources; a config-management tool or CI manages what happens on them afterward

## Connects To
- **Ch 1**: provisioner-as-smell (heavy use signals a missing provider/config tool) originates here
- **Ch 7**: secrets passed as provisioner arguments (e.g. `${self.primary_access_key}`) should flow through a secrets manager instead
- **Ch 9**: taint/recreate cycles and connection failures are prime runtime-error territory