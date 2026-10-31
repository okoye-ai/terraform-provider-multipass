# Chapter 5: Provisioning Cloud Compute Instances with Terraform

## Core Idea
One provider-agnostic playbook — pick image + size, wire network, inject access credentials, bootstrap with startup scripts, scale and load-balance — covers VM provisioning across Azure (primary), GCP, and AWS, with only provider-specific naming changing.

## Frameworks Introduced
- **Cross-cloud VM configuration contract**: every provider needs the same five things.
  - When to use: writing or porting VM code between clouds.
  - How: define (1) OS image, (2) instance size, (3) network/subnet (+ public IP), (4) credentials (SSH key or password), (5) init script (cloud-init / user data).
- **Image selection per provider**: Azure = `publisher`/`offer`/`sku`/`version`; GCP = `project` + `family` (e.g., `projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts`); AWS = region-specific AMI IDs.
  - How: use Terraform **data sources** to fetch the latest image dynamically (AWS `data "aws_ami"` with `most_recent = true, owners = ["amazon"]`) instead of hardcoding IDs.
- **SSH key injection patterns**: Azure = `admin_ssh_key` block embedding username + public key directly in the VM (no pre-registration); AWS = `key_name` referencing a pre-created EC2 key pair in the region; GCP = instance metadata (`ssh-keys = "terraform:${file(...)}"` in the format `username:key`) or OS Login/IAM.
  - Rule: "Always use public keys in configurations. Never store private keys in Terraform files or state."
- **Startup script / cloud-init mapping**: Azure = `custom_data` (Terraform base64-encodes automatically, wrap in `base64encode(<<-EOF)`), commonly `#cloud-config` YAML; AWS = `user_data` shell scripts; GCP = `metadata_startup_script`. Prefer managed scaling with `azurerm_linux_virtual_machine_scale_set` / `aws_autoscaling_group` / GCP MIGs for production — "Terraform may lose track of autoscaled counts, so use terraform refresh or configure scaling limits instead of fixed counts."
- **Load balancer anatomy**: every LB needs a frontend IP + port, a backend group of instances, and a health check.
  - Azure: `azurerm_lb` (L4; Application Gateway for L7) + `azurerm_lb_backend_address_pool` + `azurerm_lb_probe` + `azurerm_lb_rule`; VMs register via NIC `ip_configuration.load_balancer_backend_address_pool_ids` (VMSS auto-registers/deregisters).
  - AWS: `aws_lb` + target group + listener; ASG registration via `aws_autoscaling_attachment`.
  - GCP: `google_compute_target_pool` + `google_compute_forwarding_rule` + HTTP health check.
- **Common tags variable**: define a `common_tags`/`labels` map as a variable or local and reuse `tags = var.common_tags` everywhere (merging resource-specific tags) so a global tag like `Project = X` changes in one place.

## Key Concepts
- **`azurerm_linux_virtual_machine` / `google_compute_instance` / `aws_instance`**: the provider-specific VM resource trio with near-identical intent.
- **Source image reference**: Azure's `publisher`/`offer`/`sku`/`version` tuple identifying the OS image (e.g., Canonical / `0001-com-ubuntu-server-jammy` / `22_04-lts` / `latest`).
- **`custom_data` / `user_data` / `metadata_startup_script`**: per-provider fields delivering boot-time initialization; cloud-init YAML on Linux cloud images.
- **VM Scale Set (VMSS)**: `azurerm_linux_virtual_machine_scale_set` manages a group of identical VMs as one; change `instances = 2` and re-apply to scale.
- **Backend address pool**: the LB component NICs join; scale set instances register and deregister automatically as capacity changes.
- **Health probe**: periodic check (e.g., TCP port 80 every 15 s, 2 probes) so only healthy VMs receive traffic.
- **NSG / Security Group / firewall tags**: provider-specific network access control — Azure NSG rules (e.g., TCP 3389 for RDP), AWS `aws_security_group` ingress/egress, GCP firewall rules targeting instance tags (`target_tags = ["ssh"]`).
- **`count.index` differentiation**: differentiates nominally identical instances created with `count` (naming, per-index address space).
- **DNS round-robin**: a single A record returning multiple cloud LB IPs distributes traffic across clouds without a global LB product.

## Recipes in this chapter
- **Recipe 25: Deploying a single VM on Azure** — RG/VNet/subnet/NIC + Ubuntu 22.04 VM with sensitive SSH-key variable and a trivial `custom_data` cloud-init writing `/var/tmp/welcome.txt`; deliberately no public IP.
- **Recipe 26: Deploying an Azure VM Scale Set with Load Balancing** — VMSS of 2 × Standard_B2s behind a Standard-SKU LB (static public IP, backend pool, TCP-80 probe, LB rule), NGINX installed via cloud-init on every instance; refreshing `http://<LB-IP>` alternates hostnames.
- **Recipe 27: GCP VM deployment** — `e2-micro` instance on the default network with `access_config {}` for an ephemeral public IP, family image URL, SSH via metadata; optional `google_compute_firewall` targeting the `ssh` tag.
- **Recipe 28: Deploying a Windows VM on Azure** — `azurerm_windows_virtual_machine` with sensitive `admin_password` (Azure complexity rules: ≥12 chars, mixed), NSG rule allowing TCP 3389 inward (restrict `source_address_prefix` to your IP in practice), NSG-to-NIC association, RDP client verification.
- **Recipe 29: Configuring cloud-init on Azure VMs** — practical cloud-init: `packages: [NGINX]` + `runcmd: systemctl enable NGINX --now`, NSG opening 80 and 22, verify via `curl http://<IP>` and `/var/log/cloud-init.log`.
- **Recipe 30: Launching an AWS EC2 instance** — `data "aws_ami"` for latest Amazon Linux 2, `t2.micro`, existing key pair name, SSH security group in the default VPC; connect with `ssh ec2-user@<IP> -i key.pem`.

## Anti-patterns
- **Private keys in Terraform files or state**: never store them; inject public keys only, use sensitive variables or environment variables.
- **Hardcoded AMI/image IDs on AWS**: AMI IDs are region-specific and dated — use the `aws_ami` data source with `most_recent` to stay current.
- **Trusting Terraform with autoscaled counts**: autoscalers change instance counts outside Terraform's state; prefer refresh/scaling limits over `instances = N` expectations.
- **RDP (3389) or SSH (22) open to `0.0.0.0/0` long-term**: acceptable for demo, restrict `source_address_prefix` to your IP for real deployments.
- **Relying on `custom_data` for Windows initialization**: Azure doesn't execute custom data on Windows by default — use the Custom Script Extension for VM extensions.
- **Complex logic in startup scripts**: "Keep scripts minimal for reliability. Use configuration management tools for complex setups."

## Code Examples
```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "ch5-r1-vm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.region
  size                  = var.vm_size
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  custom_data = base64encode(<<-EOF
    #cloud-config
    write_files:
      - path: /var/tmp/welcome.txt
        content: |
          Hello from Terraform cloud-init!
    EOF
  )
}
```
- **What it demonstrates**: the full Azure VM contract — image tuple, SSH key block, and base64-encoded cloud-init via `custom_data`.

```hcl
data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "vm" {
  ami                   = data.aws_ami.amzn2.id
  instance_type         = "t2.micro"
  key_name              = "terraform-key"
  vpc_security_group_ids = [aws_security_group.ssh_sg.id]
  tags = { Name = "ch5-r6-instance" }
}
```
- **What it demonstrates**: dynamic AMI lookup via data source plus AWS-style key-pair-by-name access control.

## Reference Tables
**Image + size + script naming per provider:**

| Concern | Azure (azurerm) | GCP (google) | AWS (aws) |
|---|---|---|---|
| VM resource | `azurerm_linux_virtual_machine` / `azurerm_windows_virtual_machine` | `google_compute_instance` | `aws_instance` |
| Image | publisher/offer/sku/version (e.g., Canonical, `22_04-lts`) | project + family (`debian-cloud`, `ubuntu-2204-lts`) | region-specific AMI ID via data source |
| Size | `Standard_B2s`, `D2s_v3` | `e2-micro`, `n1-standard-4` | `t2.micro`, `m5.large` |
| SSH key | `admin_ssh_key` block | metadata `ssh-keys = "user:key"` / OS Login | `key_name` (pre-created key pair) |
| Init script | `custom_data` (cloud-init) | `metadata_startup_script` / user-data | `user_data` |
| Metadata term | tags | labels (+ separate instance `metadata`) | tags |

**Scaling constructs:** Azure = VM Scale Set; AWS = Auto Scaling Group + launch template; GCP = Managed Instance Group + autoscaler. Production prefers managed groups for integrated health checks and autoscaling.

## Worked Example
**Chef's Special — cross-cloud compute cluster** (`chefmulticloud/`, three sub-configs):

1. **Appetizer — Azure cluster** (`azure/`): `multi-cloud-rg-azure` in `uksouth`; static Standard public IP → `azurerm_lb` → backend pool + TCP-80 probe (interval 15 s, 2 probes) + `azure-http-rule`. `azure-multi-vmss`: 2 × `Standard_B2s` Ubuntu 22.04, cloud-init installs NGINX and rewrote the page to "Welcome from Azure VMSS instance"; instance IP configs join the backend pool. Tag `cluster = "azure"`. Apply: `terraform init` + `terraform apply -auto-approve`.
2. **Main course — GCP cluster** (`gcp/`): `google_compute_address` reserved static IP; `count = 2` instances `gcp-web-0`/`gcp-web-1` (`e2-micro`, us-central1-a, default network + `access_config {}`) bootstrapped by `metadata_startup_script` apt-installing NGINX; `google_compute_http_health_check` + `google_compute_target_pool` (instances via `for inst in google_compute_instance.web : inst.self_link`) + `google_compute_forwarding_rule` on port 80; firewall allows TCP 80 from GCP LB source ranges `130.211.0.0/22`, `35.191.0.0/16` targeting `gcp-web` tags.
3. **Dessert — DNS** (`dns/`): `azurerm_dns_zone` `multicloud.example.com` + `azurerm_dns_a_record` `app` with TTL 60 whose `records = ["<Azure_Load_Balancer_IP>", "<GCP_Load_Balancer_IP>"]`. Client DNS queries get both IPs and pick one — DNS round-robin across clouds. Verify with `nslookup app.multicloud.example.com`.

## Key Takeaways
1. Learn the five-part VM contract once; provider differences are naming, not concepts — image selector, size string, network attachment, credential injection, boot script.
2. Fetch images with data sources (AWS AMI lookup, image family URLs) instead of pinning dated IDs; "latest" in Azure's `source_image_reference` serves the same goal.
3. Put cloud-init in `custom_data` on Azure Linux VMs for hands-off bootstrap — NGINX up and serving before you ever SSH in; verify via `/var/log/cloud-init.log` and `curl http://<IP>`.
4. VMSS networking is the load-balancer integration point: `load_balancer_backend_address_pool_ids` on the scale set's IP config makes instance registration automatic and lifecycle-aware.
5. Standard SKU is required for Azure LBs fronting scale sets; static public IPs keep addresses stable across LB updates.
6. Define tags/labels as one shared `common_tags` map; consoles, cost reports, and IAM policies pivot on them.
7. Terraform's provider-agnostic language lets one organization run Azure, GCP, and AWS compute from near-identical code — a shared DNS record is the cheapest cross-cloud traffic splitter.

## Connects To
- **Ch 4 (modules)**: these VM/LB resource blocks are exactly what to extract into reusable modules (the Ch 4 Chef's Special compute module mirrors Recipe 26's pieces); module inputs would replace the hardcoded sizes and images here.
- **Ch 6 (networking and security)**: NSGs, subnets, and firewall rules used as scaffolding here get first-class treatment next.
- **Later chapters (CI/CD, multi-environment)**: per-recipe `dev.tfvars` patterns and tag-driven organization feed into pipeline-managed, multi-environment compute fleets.