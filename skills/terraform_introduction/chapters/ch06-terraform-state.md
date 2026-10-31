# Chapter 6: Terraform State

## Core Idea
`terraform.tfstate` is Terraform's mapping of your code to real-world resources — lose it and Terraform loses track of your infrastructure; keep it remote, locked, and out of manual hands.

## Frameworks Introduced
- **Local → Remote state upgrade**: local state is fine for solo testing, but teams need remote state with locking and versioning
  - When to use: the moment more than one person touches the same infrastructure
  - How: declare a `backend` (S3, GCS, Terraform Cloud...) in a `terraform` block, then `terraform init` to migrate
- **State-answers-three-questions test**: use state to answer — what resources exist? what are their attributes? what are the dependencies between them?

## Key Concepts
- **State file**: JSON file (`terraform.tfstate`) tracking metadata/attributes of managed resources
- **Backend**: service Terraform uses to store state (S3, GCS, Terraform Cloud)
- **State locking**: prevents concurrent `terraform` runs from corrupting shared state; automatic on most remote backends

## Mental Models
- **State as Terraform's source of truth**: Terraform doesn't inspect the real world — it consults state. Corrupt state = Terraform acting on a wrong world.

## Anti-patterns
- **Manually editing the state file**: leads to inconsistencies; state is Terraform-managed, period.
- **Leaving state in local storage for a team**: not shareable, no concurrency safety, no backups/versioning.
- **Unencrypted local state**: state can contain passwords, API keys, even a public IP — a secrets trove.

## Code Examples *(technical)*
```hcl
terraform {
  backend "s3" {
    bucket = "my-bucket"
    key    = "path/to/my/key"
    region = "us-east-1"
  }
}
```
- **What it demonstrates**: an S3 remote backend — state stored as an object at `path/to/my/key`.

## Reference Tables

| Property | Local state | Remote state |
|---|---|---|
| Team sharing | Poor | Easy |
| Concurrent modifications | Unsafe | Handled via locking |
| Backup & versioning | None | Automatic on supporting backends |

## Key Takeaways
1. State maps config → reality; treat it as production data, secure at rest and in transit.
2. Remote state with locking is mandatory for team/production work.
3. Version-capable backends let you restore previous state versions when needed.

## Connects To
- **Ch 8**: Terraform Cloud packages remote state + locking + versioning as a service
- **Ch 12**: advanced state handling (conflicts, corruption, import/export)