# Changelog

All notable changes to this provider are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and
this project adheres to [Semantic Versioning](https://semver.org/).

Maintainers: commit messages using Conventional Commit prefixes (`feat:`,
`fix:`, `docs:`, `chore:`, `test:`) — the release workflow derives the
GitHub and Registry release notes from them. Breaking changes should be
called out here under the version's `### Changed` heading **before** the
release is tagged.

## [Unreleased]

## [1.0.0] - 2026-10-31

Initial release of the provider.

### Added

- `multipass_instance` resource managing the full VM lifecycle through the
  `multipass` CLI: creation, start/stop, destruction, and refresh with
  graceful recovery handling.
- Instance sizing (`cpus`, `memory`, `disk`) with configurable
  `resize_policy`: `"in_place"` (default) resizes the existing VM without
  replacement, rejecting unsupported disk shrinks before any mutation, while
  `"replace"` retains rebuild-on-change behavior.
- Multiple networks with mode and MAC address selection, plus host directory
  mounts that can be added and removed in place without recreation.
- Cloud-init support via `cloud_init` (inline, e.g. from `templatefile()`) or
  `cloud_init_file`, with `wait_for_cloud_init` for downstream dependency
  sequencing.
- `auto_recover` and `auto_start_on_recover` for instances soft-deleted
  outside Terraform, and `primary` instance selection.
- `multipass_alias` resource exposing commands from instances as host
  command aliases, including `working_directory` support.
- `multipass_snapshot` resource managing named snapshots of stopped
  instances, with auto-generated names and optional comments.
- `multipass_file_upload` resource transferring files or inline content into
  instances with `content_hash`-driven updates and destroy-time cleanup.
- `multipass_file_download` resource copying files or directories from
  instances to the host, with `triggers` for forced re-downloads.
- `multipass_images`, `multipass_networks`, `multipass_instance`, and
  `multipass_snapshots` data sources for composing dynamic plans.
- Remote-host support through `server_address` with per-provider-alias
  daemon addressing, including environment variable inheritance rules
  (`MULTIPASS_SERVER_ADDRESS`).
- Configurable `multipass_path`, `command_timeout`, and `default_image`
  provider settings, with Multipass >= 1.13 version detection.
- Import support for `multipass_instance`, `multipass_alias`,
  `multipass_snapshot`, and `multipass_file_upload`.
- Pulumi bridge examples for TypeScript and Python with compatibility
  checks.
- Documentation generated from schema via tfplugindocs with a CI sync gate,
  plus remote-host and Pulumi guides.
- CI on GitHub Actions covering unit tests across Go versions and OSes,
  golangci-lint, govulncheck, documentation validation, Pulumi
  compatibility, and GoReleaser-driven signed releases.

[1.0.0]: https://github.com/okoye-ai/terraform-provider-multipass/releases/tag/v1.0.0