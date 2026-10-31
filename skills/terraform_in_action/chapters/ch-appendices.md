# Appendices: Authentication (AWS / Azure / GCP), Shell Provider, Petstore Data Source

## Core Idea
Five short "connect the provider" guides: credentials via cloud CLIs (AWS profile, `az login`, `gcloud auth application-default login`), and two escape hatches for custom resources/data sources (the Shell provider; a read-only Petstore data source).

## Appendix A — AWS
- Create account (free tier), then **never use the root account** daily: create an admin IAM user, get access keys.
- `aws configure --profile tf-user` writes `~/.aws/credentials` with a named profile.
- Terraform: `provider "aws" { profile = "tf-user" }` — empty provider block if using default profile; credentials also work as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars.

## Appendix B — Azure
- Free 30-day trial account; install Azure CLI; `az login`; `az account list` → note subscription `id`; `az account set --subscription=<ID>` if multiple.
- Terraform with default subscription: `provider "azurerm" { features {} }` — the empty features block is mandatory syntax.

## Appendix C — GCP
- $300 credit account; create a **project** (note the *project ID*, which differs from the project name) + assign a billing account.
- `gcloud auth application-default login --project <project_id>` (ADC). Recommended: least-privileged service account (then set `credentials` to the JSON key path).
- Terraform: `provider "google" { project = "<id>", region = "us-central1" }`.

## Appendix D — Custom Resources with the Shell Provider
- `scottwinkler/shell` installs from the Registry via `required_providers` (Terraform checks local dir and `~/.terraform.d/plugins` before the Registry).
- `data "shell_script"` — read-only: `lifecycle_commands { read = <<-EOF ... }` echoes JSON read back as `output["<key>"]` (e.g. `whoami`; generalizes to importing env vars into Terraform).
- `resource "shell_script"` — full managed lifecycle: `create`/`delete` (optionally `read`/`update`) commands; output persists to a state file and participates in plan/apply/destroy.
- Full-CRUD example maps to external scripts loaded via `file()`, with secrets in `sensitive_environment` — more versatile than null_resource + local-exec.

## Appendix E — Petstore Data Source (companion to ch11)
- Register via `DataSourcesMap: {"petstore_pet_ids": dataSourcePSPetIDs()}` in provider.go.
- Two data-source flavors: single-resource (`tfe_workspace`) vs list-of-resources (`tfe_workspace_ids`); Petstore has no unique lookup key except ID, so a **list data source with a `names` filter** (wildcard `*`) is the sensible design — alternatively a `filter` block model like `aws_instances`.
- Implementation: `Read`-only; `d.Get("names")` → SDK `Pets.List` → filter matches → `d.Set("ids", ids)` → **invent a stable ID** via `schema.HashString(strings.Join(ids, ""))`.
- Acceptance-test rule: a data source test must *create the complementary resource first*, then assert with `TestCheckResourceAttrPair` linking `petstore_pet.pet.id` ↔ `data.petstore_pet_ids.pets.id`.

## Key Takeaways
1. CLI-based auth is the dev path; service principals / service accounts are the automation path for all three clouds.
2. Shell provider = custom resources without Go: any command can back create/read/update/delete.
3. Data sources that return lists need a synthesized, deterministic ID (hash of contents).
4. Data-source acceptance tests are always resource-then-data pairs.

## Connects To
- **Ch 1/6**: provider config blocks these appendices feed
- **Ch 7**: provisioners vs Shell provider for ad-hoc code execution
- **Ch 11**: the provider architecture the appendices complete (data source side)