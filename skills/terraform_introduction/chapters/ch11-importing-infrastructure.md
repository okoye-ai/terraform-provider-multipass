# Chapter 11: Importing Existing Infrastructure into Terraform

## Core Idea
`terraform import <address> <id>` adopts existing resources into Terraform state — but you must first write a configuration block for the resource to map into.

## Frameworks Introduced
- **Import protocol**: write config first → run `terraform import` → resource is now Terraform-managed
  - When to use: adopting resources created manually or by other tools
  - How: 1) create the config block (e.g. `resource "digitalocean_droplet" "web" {...}`), 2) `terraform import digitalocean_droplet.web <droplet_id>`
- **Non-importable resource decision tree**: resource can't be imported?
  1. Recreate with Terraform (delete + create — risk: downtime/data loss)
  2. Create a new resource and transition to it (safer: shift DNS/app config, then delete old)
  - Rule: prefer transition except when the resource's identity is immovable (e.g. you can't change a droplet's IP)

## Key Concepts
- **`<address>`**: the resource's address in your configuration
- **`<id>`**: the existing resource's provider-specific ID
- **Import vs apply**: import = existing resources into state; `terraform apply` = create new

## Mental Models
- **Import as adoption paperwork**: the resource exists; the config block + import command formalize its custody.

## Anti-patterns
- **Importing without pre-writing the config block**: Terraform needs a block to map the imported resource onto.
- **Recreating stateful resources carelessly**: deletion can mean downtime or data loss — check for a transition path first.

## Code Examples *(technical)*
```bash
terraform import digitalocean_droplet.web 12345678
```

```bash
terraform show -json > state.json
```
- **What the second demonstrates**: state export for reports/other tools (the reverse direction: import/export).

## Key Takeaways
1. Every provider identifies resources differently — import IDs are provider-specific.
2. Write the config block before importing; import fills the state, not the file.
3. For non-importable resources, transition beats recreate unless identity pins you in place.

## Connects To
- **Ch 12**: state conflicts & corruption — the state you just imported now needs care
- **Ch 19**: "conflicts with existing infrastructure" error → import is one of the fixes