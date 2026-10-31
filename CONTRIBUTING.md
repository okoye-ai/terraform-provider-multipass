# Contributing

Thanks for improving the Multipass Terraform provider. This document covers
what a working machine needs and what CI will expect from your PR.

## Prerequisites

- **Go 1.26+** (`go version`) — the module's `go` directive is 1.26
- **GNU make** (`make --version`) — all developer commands are make targets
- **Multipass CLI >= 1.13** — required on the PATH for everything except
  unit tests
- **golangci-lint** (`make lint` prints the install command if missing) —
  falls back to `~/go/bin`
- Terraform or OpenTofu for acceptance tests and doc generation

## First clone setup

```sh
make hooks   # wires the .githooks pre-commit gate: lint + unit tests
make build   # builds bin/terraform-provider-multipass for dev overrides
```

Run a provider build from this repo against real configs via Terraform
development overrides: point `dev_overrides` for
`registry.terraform.io/okoye-ai/multipass` (and
`registry.opentofu.org/okoye-ai/multipass` if you also use OpenTofu) at the
repo's `bin/` directory, then `tofu plan` / `terraform plan` — no `init`
needed. `tofu` requires the dev-overrides block; it does not need (and
should not have) a lock file.

## Day-to-day commands

| Command | Purpose |
| --- | --- |
| `make unit` | Unit tests (default target) |
| `make lint` | golangci-lint, config in `.golangci.yml` |
| `make govulncheck` | Vulnerability scan (CI gate: zero called vulnerabilities) |
| `make fmt` / `make fmtcheck` | gofmt rewrite / verification |
| `make testacc` | Acceptance tests against a live Multipass daemon (`TF_ACC=1`) |
| `make docs` | Regenerate `docs/` from `templates/` + schema |
| `make goreleaser-dry` | Snapshot release build, no upload or signing |
| `make validate-docs` | Doc-link and frontmatter validation (needs `pwsh`) |

## Rules CI enforces

1. **Docs are generated.** `docs/` is tfplugindocs output. Narrative text
   lives in `templates/`; schema descriptions live in the Go source. If you
   change schema, run `make docs` and commit `docs/` too — the `docs-sync`
   job fails otherwise. Guides are edited in `templates/guides/` only.
2. **Conventional Commits.** Release notes derive from commit messages
   (`feat:`, `fix:`, `docs:`, `chore:`, `test:`). Breaking changes go into
   `CHANGELOG.md` under the relevant version **before** tagging.
3. **Cross-references.** CLI-provider behavior changes belong in `AGENTS.md`
   and `llms.txt` as well as this repo's normal docs; those files are the
   LLM/tooling-facing summary.
4. **No unexplained CLI-contract changes.** The provider wraps the
   `multipass` CLI (`internal/multipasscli`); `multipass stop --force`
   requires Multipass >= 1.14, and comparable minimum-version notes belong
   in the method comment and the resource docs.

## Tests

- Unit tests never touch a daemon: `make unit`.
- Acceptance tests create and destroy real VMs: `make testacc` (needs the
  Multipass daemon, TF or tofu, and takes a while). CI runs them nightly,
  not per-PR.
- Resizing has both policies (`in_place` default, `replace`) with different
  power-state semantics — extend
  `internal/provider/*resize*_test.go` / `_acc_test.go` together when
  touching that path.

## Pull requests

`.github/pull_request_template.md` lists the checklist. CI runs unit tests
and lint on all three OSes, govulncheck, docs validation on Linux and
Windows, the schema drift gate, and Pulumi-bridge compatibility. Report vulnerabilities privately via GitHub security advisories on the repository — not in issues.