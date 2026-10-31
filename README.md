# Terraform Provider Multipass

<p align="center">
  <img width="600"  alt="terraform-provider-multipass-heading-image" src="assets/Terraform Multipass Provider Banner.png" />
</p>

<p align="center">
  <a href="https://github.com/okoye-ai/terraform-provider-multipass/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/okoye-ai/terraform-provider-multipass/actions/workflows/ci.yml/badge.svg" /></a>
  <a href="https://github.com/okoye-ai/terraform-provider-multipass/actions/workflows/docs.yml"><img alt="Docs" src="https://github.com/okoye-ai/terraform-provider-multipass/actions/workflows/docs.yml/badge.svg" /></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg" /></a>
  <a href="https://developer.hashicorp.com/terraform/plugin/framework"><img alt="Terraform Plugin Framework" src="https://img.shields.io/badge/Terraform%20Plugin%20Framework-1.x-844FBA.svg" /></a>
</p>

[Terraform](https://www.terraform.io/) provider for [Canonical Multipass](https://canonical.com/multipass), implemented with the modern Terraform Plugin Framework. It exposes rich VM lifecycle management, alias automation, snapshots, file transfers, and data sources for images and networks while favoring performance and clear diagnostics.

The provider drives the `multipass` CLI rather than a REST API, which means:

- **No daemon-side plugins or agents** — if `multipass` works on your machine, the provider works.
- **Full parity with CLI capabilities** — including newer features without provider releases.
- **Runs wherever Terraform runs** — including remote Multipass daemons over SSH tunnels.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Provider Configuration](#provider-configuration)
- [Resources](#resources)
- [Data Sources](#data-sources)
- [Import](#import)
- [Instance Resizing](#instance-resizing)
- [Remote Hosts](#remote-hosts)
- [Pulumi](#pulumi)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [How It Works](#how-it-works)
- [Development](#development)
- [Contributing and Security](#contributing-and-security)
- [License](#license)

## Features

- Provider configuration for CLI discovery, command timeouts, default images, and cached `multipass` metadata.
- Remote Multipass daemons through `server_address`, with provider aliases for managing multiple hosts concurrently.
- `multipass_instance` resource with CPU/memory/disk sizing, multiple networks, host mounts, and inline or file-based cloud-init.
- Configurable resizing: CPU, memory, and disk growth update the existing VM by default; `resize_policy = "replace"` rebuilds it instead.
- In-place disk growth without recreation, with pre-apply rejection of unsupported shrinks and automatic recovery of originally running VMs on failure.
- `multipass_snapshot` resource for managing named snapshots (create/list/delete/import).
- `multipass_alias` resource for ergonomic host shortcuts into instances.
- `multipass_file_upload` and `multipass_file_download` resources for Terraform-managed file transfers without provisioners.
- Data sources for images, networks, instances, and snapshots to compose dynamic plans.
- Parser-backed CLI abstraction with detailed diagnostics and JSON-output version detection.
- Pulumi support through the Any Terraform Provider bridge, with examples and compatibility checks for TypeScript and Python.

## Requirements

| Component  | Version                                                        | Notes                                                  |
| ---------- | -------------------------------------------------------------- | ------------------------------------------------------ |
| Terraform  | >= 1.x (plugin protocol 6)                                     | OpenTofu works the same way                            |
| Multipass  | >= 1.13 (JSON output required; 1.16 for remote-host trust setup) | Installed on the Terraform host, available on `PATH`  |
| Go         | Per [`go.mod`](go.mod)                                         | Required only for local development                    |

Check the installed CLI: `multipass version --format json`.

## Getting Started

1. Install [Multipass](https://multipass.run/install) 1.13 or newer on the machine where Terraform runs and confirm `multipass version --format json` works.
2. Initialize Terraform/OpenTofu in any configuration that declares `okoye-ai/multipass` as a required provider. The CLI downloads it from the Terraform Registry automatically.

A trimmed version of [`examples/basic/main.tf`](examples/basic/main.tf):

```hcl
terraform {
  required_providers {
    multipass = {
      source = "okoye-ai/multipass"
    }
  }
}

provider "multipass" {
  multipass_path  = "/usr/bin/multipass" # optional
  command_timeout = 180                  # optional, seconds
  default_image   = "lts"                # optional
}

resource "multipass_instance" "dev" {
  name   = "dev-box"
  image  = "lts"
  cpus   = 2
  memory = "4G"
  disk   = "15G"

  networks {
    name = "en0"
    mode = "manual"            # optional
    mac  = "52:54:00:4b:ab:bd" # optional
  }

  mounts {
    host_path     = "/home/shared"
    instance_path = "/srv/hostshared"
    read_only     = false # optional
  }
}

resource "multipass_alias" "shell" {
  name     = "dev-shell"
  instance = multipass_instance.dev.name
  command  = "bash"
}
```

A full walk-through (cloud-init, mounts, aliases, outputs) lives in [`examples/dev-lab/`](examples/dev-lab/main.tf); complete resource schemas are documented under [Resources](#resources).

## Provider Configuration

| Attribute         | Type   | Default           | Description                                                                 |
| ----------------- | ------ | ----------------- | --------------------------------------------------------------------------- |
| `multipass_path`  | String | resolved via PATH | Optional explicit path to the `multipass` binary.                            |
| `server_address`  | String | environment / CLI default | Optional daemon address, such as `host:50051`. Overrides `MULTIPASS_SERVER_ADDRESS` for this provider; otherwise inherits the environment or the CLI's local default. |
| `command_timeout` | Int    | `600`             | Timeout in seconds for CLI calls. Must be greater than 0.                     |
| `default_image`   | String | `"lts"`           | Fallback image alias/name when resources omit `image`.                       |

`server_address` values must be non-empty, contain no whitespace or NUL characters, and be known before provider configuration. Provider aliases can select different addresses concurrently. Omitted or null addresses inherit `MULTIPASS_SERVER_ADDRESS`; an unset or empty environment variable uses the CLI's local default. See [remote hosts](#remote-hosts) and the [remote-host guide](docs/guides/remote-hosts.md).

## Resources

| Resource                                                                 | Purpose                                                                       |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| [`multipass_instance`](docs/resources/instance.md)                       | VM lifecycle: create, resize in place or by replacement, recover, destroy.    |
| [`multipass_alias`](docs/resources/alias.md)                             | Host-side command aliases that execute inside instances.                      |
| [`multipass_snapshot`](docs/resources/snapshot.md)                       | Named snapshots of stopped instances (create/delete).                         |
| [`multipass_file_upload`](docs/resources/file_upload.md)                 | Files or directories into instances via `multipass transfer`.                 |
| [`multipass_file_download`](docs/resources/file_download.md)             | Files or directories from instances back to the host.                         |

### Resource highlights

- **`multipass_instance`** — arguments: `name` (required), `image`, `cpus`, `memory`, `disk`, `resize_policy`, `cloud_init_file`, `cloud_init`, `primary`, `auto_recover`, `auto_start_on_recover`, `wait_for_cloud_init`. Nested blocks: `networks` (`name`, `mode`, `mac`), `mounts` (`host_path`, `instance_path`, `read_only`), `timeouts`. Computed: `id`, `ipv4`, `state`, `release`, `image_release`, `snapshot_count`, `last_updated`.
- **`multipass_alias`** — arguments: `name` (required, recreate on change), `instance` (required), `command` (required), `working_directory` (optional, wraps the command with `cd`).
- **`multipass_snapshot`** — arguments: `instance` (required), `name` (optional, auto-generated if omitted), `comment` (optional). Both `name` and `comment` force recreation. Computed: `id` as `<instance>.<snapshot>`. The target instance **must be stopped** or the operation fails.
- **`multipass_file_upload`** — arguments: `instance` (required), `destination` (required), `source` or `content` (exactly one required), `recursive`, `create_parents`. Computed: `content_hash` (SHA256, drives update detection). Destroy removes the remote path (`rm -rf`).
- **`multipass_file_download`** — arguments: `instance`, `source`, `destination` (all required, all force recreation), `recursive`, `create_parents`, `overwrite`, `triggers` (map, forces re-download on change). Computed: `content_hash`. Destroy removes the local destination. **Cannot be imported.**

## Data Sources

| Data Source                                                                        | Purpose                                                          |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [`multipass_images`](docs/data-sources/images.md)                                  | Enumerate launchable images/blueprints from `multipass find`.     |
| [`multipass_networks`](docs/data-sources/networks.md)                              | List host networks bridgeable from instances.                     |
| [`multipass_instance`](docs/data-sources/instance.md)                              | Read-only inspection of an existing instance.                     |
| [`multipass_snapshots`](docs/data-sources/snapshots.md)                            | List snapshots for an instance, with optional name filter.        |

```hcl
data "multipass_images" "lts" {
  alias = "lts"
}

resource "multipass_instance" "vm" {
  name  = "my-vm"
  image = data.multipass_images.lts.images[0].name
}
```

## Import

```sh
terraform import multipass_instance.dev dev-box
terraform import multipass_alias.shell app-shell
terraform import multipass_snapshot.pre_upgrade my-app.pre-upgrade
terraform import multipass_file_upload.config my-app:/home/ubuntu/app.conf
```

| Resource                  | Import ID format           | Example                                              |
| ------------------------- | -------------------------- | ---------------------------------------------------- |
| `multipass_instance`      | instance name              | `terraform import multipass_instance.dev dev-box`    |
| `multipass_alias`         | alias name                 | `terraform import multipass_alias.shell app-shell`   |
| `multipass_snapshot`      | `<instance>.<snapshot>`    | `terraform import multipass_snapshot.b my-app.snap1` |
| `multipass_file_upload`   | `<instance>:<destination>` | `terraform import multipass_file_upload.c vm:/path`  |
| `multipass_file_download` | not importable             | —                                                    |

## Instance Resizing

`multipass_instance.resize_policy` controls what happens when `cpus`, `memory`, or `disk` changes:

- **`"in_place"` (default)** — resizes CPU/memory and grows disk on the existing VM, gracefully stopping and restarting it only if it was running. Already stopped VMs remain stopped; suspended or transitional VMs must first be started or stopped. In-place disk shrink is rejected during apply before any mutation. Resizing never silently falls back to replacement.
- **`"replace"`** — retains the previous behavior of replacing the VM when allocations change, including disk shrink.

Notes:

- Omitting or removing a sizing argument retains the existing allocation. New instances default to 1 CPU, 1G memory, and 5G disk. Refresh/import read daemon allocations; equivalent size spellings do not trigger a resize or replacement.
- Multipass rounds size settings even with `get --raw`. Preserve known configured sizes that match its rounded report; imported/newly discovered values are estimates, and external changes inside the same rounding interval are not detectable.
- `name`, `image`, `cloud_init`, `cloud_init_file`, and `networks` changes **force recreation**, regardless of resize policy. `cloud_init` and `cloud_init_file` are mutually exclusive.
- Resizing failures retain confirmed allocation changes and report the original error. Recovery attempts to restart an originally running, confirmed-stopped VM and read allocations within 60 additional seconds, respecting request cancellation. Use `timeouts.update` to control the normal resize deadline.
- `memory` and `disk` accept positive byte counts or binary size strings such as `"512M"`, `"4G"`, `"1T"`, and `"1.5GiB"`, with overflow validation. Guest filesystem expansion can require a separate step after disk growth.
- Changing only `resize_policy` does not restart or replace the instance.
- `mounts` can be added/removed **in place** without recreation.

See the [instance resource documentation](docs/resources/instance.md#resizing) for downtime, failure recovery, and guest filesystem expansion details.

## Remote Hosts

The CLI runs on the Terraform machine while instances live on any reachable Multipass daemon. Configure the daemon's endpoint, establish TLS trust, and authenticate the CLI user with it before applying.

```hcl
provider "multipass" {
  alias          = "remote"
  server_address = "192.0.2.10:50051"
}

resource "multipass_instance" "remote_dev" {
  provider = multipass.remote
  name     = "remote-dev"
  image    = "lts"
}
```

Multipass 1.16 uses an application-specific CA bundle and the CLI's TLS server name is `localhost`. See the [remote-host guide](docs/guides/remote-hosts.md) for the tested SSH tunnel setup, environment precedence, and networking requirements, or the [two-host example](examples/remote-hosts/main.tf).

## Pulumi

Use the provider through Pulumi's [Any Terraform Provider](https://www.pulumi.com/docs/iac/concepts/providers/any-terraform-provider/) bridge. In an existing Pulumi project:

```sh
pulumi package add terraform-provider@1.4.0 registry.terraform.io/okoye-ai/multipass 1.0.0
pulumi install
```

Start with the [TypeScript or Python examples](examples/pulumi/). The [Pulumi guide](docs/guides/pulumi.md) covers local builds (including Windows), configuration, imports, and lifecycle details such as replacement ordering and the generated `ipv4s` output.

## Examples

Each Terraform directory under [`examples/`](examples/README.md) is self-contained; run `terraform init` (or `tofu init`) inside the target folder and the published provider installs automatically. The [Pulumi examples](examples/pulumi/) use `pulumi install`.

| Example                                       | Shows                                                              |
| --------------------------------------------- | ------------------------------------------------------------------ |
| [`basic`](examples/basic/main.tf)             | Minimal single instance + alias                                     |
| [`dev-lab`](examples/dev-lab/main.tf)         | Multi-instance dev tier (db/api/web) with dependency ordering       |
| [`bridged-workstation`](examples/bridged-workstation/main.tf) | Bridged networking, host mounts, primary instance     |
| [`cloud-init-lab`](examples/cloud-init-lab/main.tf) | Cloud-init from file and from `templatefile()`                 |
| [`file-provisioner`](examples/file-provisioner/main.tf) | Upload/download workflows with triggers                    |
| [`snapshot-test`](examples/snapshot-test/main.tf) | Snapshot lifecycle on a stopped instance                        |
| [`static-ip`](examples/static-ip/main.tf)     | Static addresses via manual-network mode                           |
| [`remote-hosts`](examples/remote-hosts/main.tf) | Two provider aliases pointing at two daemons                      |

## Troubleshooting

<details>
<summary><strong>"Multipass version X.Y.Z is below the minimum supported version"</strong></summary>

Upgrade Multipass to >= 1.13. The provider requires JSON output support added in that release. Verify with `multipass version --format json`.
</details>

<details>
<summary><strong>Instance creation hangs or times out</strong></summary>

Set `timeouts { create = "20m" }` for large images or slow networks. Increase `command_timeout` at the provider level. If using `cloud_init`, the launch itself may be fast but cloud-init runs async — use `wait_for_cloud_init = true` if downstream resources depend on it.
</details>

<details>
<summary><strong>"cloud_init" vs "cloud_init_file" conflict</strong></summary>

These are mutually exclusive. Use `cloud_init_file` for a path to a YAML file, or `cloud_init` for inline content (e.g. from `file()` or `templatefile()`).

For dynamic cloud-init:

```hcl
resource "multipass_instance" "runner" {
  name       = "ci-runner"
  cloud_init = templatefile("${path.module}/cloud-init.tpl", {
    username = "ci-runner"
  })
}
```
</details>

<details>
<summary><strong>Network changes destroy the instance</strong></summary>

The `networks` block uses `RequiresReplace` — any change to the network list forces recreation. Plan network config before first apply. See [`examples/bridged-workstation/`](examples/bridged-workstation/main.tf).
</details>

<details>
<summary><strong>Snapshot fails: "instance is not stopped"</strong></summary>

Multipass requires instances to be stopped before snapshotting. Stop the instance first or use `depends_on` for proper sequencing.
</details>

<details>
<summary><strong>File upload shows no changes but the remote file differs</strong></summary>

The provider tracks content via `content_hash` (SHA256 of the local payload). Remote in-place modifications are not detected.
</details>

<details>
<summary><strong>File download not re-running</strong></summary>

Use the `triggers` argument with a changing value (e.g. `multipass_instance.app.last_updated`) to force re-download.
</details>

<details>
<summary><strong>Instance "Deleted" unexpectedly</strong></summary>

If soft-deleted outside Terraform, set `auto_recover = true` to recover automatically. Pair with `auto_start_on_recover = true` to also start it.
</details>

<details>
<summary><strong>Remote daemon connection problems</strong></summary>

Ensure the endpoint is reachable, the CLI's TLS trust is configured (application-specific CA bundle for Multipass 1.16), and the CLI user is authenticated with the daemon. See the [remote-host guide](docs/guides/remote-hosts.md).
</details>

## How It Works

The provider is a thin, parser-backed wrapper around the Multipass CLI:

```text
Terraform ──▶ resource logic ──▶ internal/multipasscli ──▶ multipass <command> ──▶ JSON ──▶ state
```

- Each CRUD call maps to CLI commands (`list`, `launch`, `stop`, `start`, `get`, `set`, `snapshot`, `transfer`, ...) executed with `--format json` where supported.
- CLI output is parsed into structured models (`internal/models`) rather than matched by string regexes, so schema and diagnostics stay stable across CLI output changes.
- Version detection at configure time enforces the >= 1.13 minimum for JSON output and warns on unsupported versions.
- There is no REST API requirement — the daemon only talks to its own CLI, and the provider only talks to the CLI.

## Development

For local hacking you can still build from source via:

```bash
go build ./cmd/terraform-provider-multipass
```

Development setup, the make-target workflow, and CI expectations are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

### Make targets

| Command | What it does |
|---|---|
| `make` · `make unit` | Run unit tests (default target; CI's `Go test` stage) |
| `make lint` | golangci-lint per `.golangci.yml` (CI's `Golangci-lint` stage) |
| `make govulncheck` | Scan for vulnerabilities reached by code path (CI's `Govulncheck` stage) |
| `make fmt` / `make fmtcheck` | Rewrite files with gofmt / fail if anything is unformatted |
| `make build` · `make install` | Compile the provider into `bin/` for Terraform dev overrides |
| `make testacc` | Acceptance tests against a real Multipass daemon (`TF_ACC=1`) |
| `make docs` | Render `docs/` from `templates/` + the current schema; CI checks it is committed (`git diff --exit-code docs/`) |
| `make goreleaser-dry` | Full release build in snapshot mode, no upload |
| `make validate-docs` | Doc-link validation used by the docs workflow (needs `pwsh`) |
| `make hooks` | Wire the `.githooks` pre-commit gate into this clone |

These need GNU make and Go.

### Tests

Run unit tests and static checks without creating VMs:

```bash
go test ./...
go vet ./...
```

Acceptance tests use real Multipass instances and remove their test resources afterward. They require a running Multipass daemon and Terraform or OpenTofu. Set the provider namespace because the test configurations use `okoye-ai/multipass` explicitly.

```powershell
$env:TF_ACC = "1"
$env:TF_ACC_PROVIDER_NAMESPACE = "okoye-ai"
$env:TF_ACC_TERRAFORM_PATH = (Get-Command tofu).Source # or terraform
go test ./internal/multipasscli ./internal/provider -p 1 -run '^TestAcc' -count=1 -v -timeout 30m
```

On Linux/macOS, set the same environment variables before running the Go command. Leave `TF_ACC` unset for unit tests. The suite covers scoped VM deletion, instance replacement, both resize policies and power-state preservation, cloud-init failure and retry, computed uploads, download contents and ownership, aliases, data sources, and snapshots. Run only resize acceptance tests with `go test ./internal/provider -run '^TestAccInstanceResource_resize' -count=1 -v -timeout 30m` after setting the same environment variables.

### Documentation

Documentation pages under `docs/` are **generated** by `make docs` (tfplugindocs renders `templates/` against the current provider schema), and CI fails if a schema change is not regenerated into `docs/`. The narrative prose is maintained in `templates/` (`index.md.tmpl`, `resources/*.md.tmpl`, `data-sources/*.md.tmpl`); guides live in both `templates/guides/` (source) and `docs/guides/` (rendered copy — edit only `templates/guides/`, then run `make docs`). Registry pages include YAML frontmatter, and guides set `page_title`. Keep links in the READMEs, `AGENTS.md`, and `llms.txt` aligned when renaming pages.

Run the same validation used by CI with PowerShell and Go, plus Terraform or OpenTofu on PATH:

```powershell
./scripts/validate-docs.ps1
# To use OpenTofu instead:
./scripts/validate-docs.ps1 -TerraformPath tofu
```

On Linux/macOS, invoke it with `pwsh -File scripts/validate-docs.ps1`. The script checks local Markdown links, builds the provider from `cmd/`, exports its schema, and runs pinned `tfplugindocs` 0.25.0 validation. That tool requires Go 1.25.8 or newer; Go can download the required toolchain automatically. It needs no Multipass daemon and does not create VMs. Temporary CLI settings and files are isolated under `build/` and cleaned up afterward.

Reference page paths use names such as `docs/resources/instance.md` and `docs/data-sources/instance.md`. Existing release documentation keeps its previous paths; update links to `latest` when the next release publishes these renamed pages. Use the [Registry preview tool](https://registry.terraform.io/tools/doc-preview) to review rendering before a release.

### CI & Releases

- CI runs on GitHub Actions (`.github/workflows/ci.yml`) and executes `go test ./...` across a small matrix of Go versions and OSes.
- Documentation validation runs in `.github/workflows/docs.yml` on Linux and Windows, including documentation-only changes.
- Pulumi compatibility runs separately in `.github/workflows/pulumi.yml`: schema checks, SDK generation, TypeScript checking, and previews with a fake Multipass CLI on Linux and Windows. See [how to run it locally](docs/guides/pulumi.md#compatibility-checks).
- Tagged releases (`X.Y.Z`) trigger GoReleaser (`.goreleaser.yml`) via `.github/workflows/release.yml`, which builds cross-platform artifacts suitable for attaching to GitHub Releases and publishing to the Terraform/OpenTofu registries. Release notes derive from [Conventional Commit](https://www.conventionalcommits.org/) messages, and the editorial history lives in [CHANGELOG.md](CHANGELOG.md).

## Contributing and Security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, the make-target workflow, and CI expectations. Bug reports and feature requests are welcome via the [issue templates](.github/ISSUE_TEMPLATE/).

## License

This project is licensed under the [MIT License](LICENSE).