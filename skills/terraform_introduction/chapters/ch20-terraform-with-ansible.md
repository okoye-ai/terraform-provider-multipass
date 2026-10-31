# Chapter 20: Terraform with Ansible

## Core Idea
Terraform provisions infrastructure; Ansible configures the software on it — combine them via provisioners (`local-exec`, `remote-exec`) rather than stretching either tool past its role.

## Frameworks Introduced
- **Division of responsibilities**: Terraform = provisioning; Ansible (agentless, YAML playbooks, idempotent, hundreds of modules) = configuration management and app deployment
  - When to use: when a newly created machine needs software configured
  - How: run playbooks post-creation through provisioners, wiring the resource's IP into the inventory
- **Provisioner choice rule**: run Ansible on *your* machine against new hosts → `local-exec`; run a playbook *on* the new host itself → `remote-exec`
  - Why: local-exec has SSH access to remote hosts; remote-exec runs inline scripts on the created resource

## Key Concepts
- **Provisioners**: execute scripts on local/remote machines as part of resource creation or destruction
- **Built-in provisioners**: `file` (copy files into the resource), `local-exec` (run command on the Terraform machine), `remote-exec` (run command on the resource)
- **Ansible features**: agentless, idempotent (same result regardless of run count), modular

## Anti-patterns
- **Using Terraform to configure software inside servers**: that's Ansible's layer — Terraform's provisioners are the handoff.
- **Expecting the Ansible provisioner to be HashiCorp-official**: it's third-party and requires manual installation.

## Worked Example
Handing a new droplet to Ansible from the local machine:
```hcl
resource "null_resource" "example" {
  provisioner "local-exec" {
    command = "ansible-playbook -i '${digitalocean_droplet.example.ipv4_address},' playbook.yml"
  }
}
```
Note the trailing comma in the inventory string — it makes the IP a one-host inventory list.

Running a playbook on the host itself:
```hcl
resource "digitalocean_droplet" "example" {
  # ...
  provisioner "remote-exec" {
    inline = [
      "echo '[defaults]' > ansible.cfg",
      "echo 'localhost ansible_connection=local' > hosts",
      "ansible-playbook -i hosts playbook.yml"
    ]
  }
}
```

## Key Takeaways
1. Provisioners run *after* resource creation — they're the Terraform→Ansible bridge.
2. `local-exec` for orchestration from your machine; `remote-exec` for self-configuration.
3. Resource attributes (like `ipv4_address`) become Ansible's inventory — reference them directly.

## Connects To
- **Ch 1**: closes the loop on the Terraform vs Ansible comparison from the tool landscape
- **Ch 14**: both show "extra resource types / handoffs" patterns on the same workflow