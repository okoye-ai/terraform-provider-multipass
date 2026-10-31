# Chapter 12: Advanced State Management

## Core Idea
As usage grows, state becomes an operational asset: version it, lock it, never hand-edit it, and export it (`terraform show -json`) when other tools need it.

## Frameworks Introduced
- **State hygiene triad for corruption avoidance**: 1) never manually edit the state file, 2) use remote state with locking enabled, 3) be deliberate before `terraform destroy`
  - When to use: always — these are the standing rules of state care
- **Locking-type choice**: local locking (lock file, only good when everyone shares one filesystem) vs remote locking (backend-stored lock, the team option — recommended)
- **State versioning**: version-capable backends (Terraform Cloud, S3, GCS) snapshot state on every `apply`, enabling rollback; in TFC view via workspace → States tab → State History

## Key Concepts
- **State versioning**: automatic new version per `apply` on supporting backends
- **State locking**: two kinds — local (default, machine-local) and remote (backend-based, team-ready)
- **State export**: `terraform show -json` dumps current state as JSON for reports/other tools

## Mental Models
- **State as a ledger**: every apply appends a version; locking is the single-writer rule that keeps the ledger honest.

## Code Examples *(technical)*
```bash
terraform state list                 # list resources (+ versions) in state
terraform state show <resource>      # details of one resource
terraform show -json > state.json    # export full state as JSON
```

## Anti-patterns
- **Manual state edits**: the state file must only be manipulated by Terraform commands.
- **Local locking for teams**: fails unless all members share the same filesystem.
- **Casual `terraform destroy`**: check you're not removing resources still needed.

## Key Takeaways
1. Remote state with locking is the corruption-prevention mechanism — enable it before the team conflicts start.
2. `terraform state list` / `state show` are your state inspection tools.
3. State history (TFC) gives you restore points after bad applies.

## Connects To
- **Ch 6**: the base state concepts this chapter scales up
- **Ch 19**: `terraform show` also appears in debugging when Terraform's worldview seems wrong