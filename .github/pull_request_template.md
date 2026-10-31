Thanks for the PR. A few things CI and the review checklist expect:

- `make unit lint fmtcheck` pass locally (the pre-commit hook wires these up — `make hooks`).
- **If you changed provider schema** (`internal/provider/`), run `make docs` and include the regenerated `docs/` — CI fails otherwise.
- **If you changed the CLI contract or docs** (`internal/multipasscli/`, `docs/`, `examples/`), mirror the change in `AGENTS.md` and `llms.txt` where it applies.
- Use Conventional Commit messages (`feat:`, `fix:`, `docs:`, `chore:`, `test:`) — release notes derive from them.
- Acceptance tests (`make testacc`) run against a real Multipass daemon and create/delete VMs — run the suites for the resources you touched if CI can't tell (maintainers run these nightly).

Closes #