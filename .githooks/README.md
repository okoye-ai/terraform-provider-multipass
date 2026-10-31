# Git hooks

Shared hooks for this repo, one commit-gate ahead of CI.

## Install

```sh
git config core.hooksPath .githooks
```

(`core.hooksPath` is local repo config, not versioned — run this once per clone.)

## What runs

`pre-commit` mirrors the CI stages and fails fast on the first problem:

1. `golangci-lint run` — config from `.golangci.yml` (skipped with a warning if
   the binary is missing; `go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0`)
2. `go test ./...` — unit tests only (`TF_ACC` tests never run here)

To bypass in an emergency: `GITHOOK_SKIP=1 git commit ...`. CI still runs both
checks, so a bypass only defers a failure.