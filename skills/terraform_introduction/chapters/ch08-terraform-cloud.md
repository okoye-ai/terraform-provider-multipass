# Chapter 8: Terraform Cloud

## Core Idea
Terraform Cloud is HashiCorp's SaaS layer over the CLI: collaboration, secure shared remote state (locked + versioned), private module registry, UI, and Sentinel policy-as-code.

## Frameworks Introduced
- **Workspace workflow**: account → organization → workspace → link VCS repo → configure variables → trigger runs via UI/API/VCS webhook
  - When to use: teams collaborating on infrastructure, or anyone wanting managed state + Sentinel
  - How: sign up at `app.terraform.io`, create an org, create a workspace choosing the workflow type, link the repository with your Terraform config
- **TFC vs OSS decision rule**: need a UI, shared version-controlled state, access control, or policy enforcement → Terraform Cloud; solo/small project without collaboration needs → open-source Terraform

## Key Concepts
- **Terraform Cloud**: managed SaaS platform enhancing open-source Terraform with collaboration and governance
- **Workspace**: holds a configuration + a set of variables; the unit of management/collaboration
- **Organization**: shared space where teams collaborate on workspaces
- **Terraform variables vs environment variables**: the former feed the configuration, the latter alter Terraform's runtime behavior

## Mental Models
- **Terraform Cloud as the team wrapper**: the CLI stays the same underneath; TFC adds state custody, run history, and guardrails around it.

## Reference Tables

| Capability | Open-source Terraform | Terraform Cloud |
|---|---|---|
| UI | None | Full run management + settings UI |
| State | Local or remote backend | Versioned, secure, shared |
| Access control & collaboration | Absent | Fine-grained |
| Policy as code (Sentinel) | Absent | Integrated |
| Private module registry | Absent | Included |

## Key Takeaways
1. TFC's five headline benefits: **collaboration, remote state management, access controls, private module registry, policy as code**.
2. Workspaces are the organizing unit — config + variables per workspace.
3. If you don't need collaboration, open-source Terraform remains fully capable.

## Connects To
- **Ch 6**: TFC is the best-packaged remote state backend
- **Ch 17**: Sentinel, the policy framework shown here, gets its own treatment