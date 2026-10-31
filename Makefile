# Makefile — local build/test/lint/docs entry points.
# Requires GNU make (the stock /usr/bin/make on macOS is GNU 3.81; Linux and CI
# runners have GNU make). CI mirrors these stages: `unit` (ci.yml Go test),
# `lint` (ci.yml Golangci-lint) and `govulncheck` (ci.yml Govulncheck).

BIN ?= bin
PROVIDER ?= terraform-provider-multipass
GOLANGCI_LINT_VERSION ?= v2.15.0
GOVULNCHECK_VERSION ?= v1.9.0

GOLANGCI_LINT := $(shell command -v golangci-lint 2>/dev/null || echo $(HOME)/go/bin/golangci-lint)
GOVULNCHECK := $(shell command -v govulncheck 2>/dev/null || echo $(HOME)/go/bin/govulncheck)

GOFILES := $(shell git ls-files '*.go' ':!*testdata*')

.DEFAULT_GOAL := unit

.PHONY: default build install unit testacc fmt fmtcheck lint govulncheck docs goreleaser-dry validate-docs hooks

default: unit

## build: compile the provider binary into $(BIN)/
build:
	go build -o $(BIN)/$(PROVIDER) ./cmd/terraform-provider-multipass

## install: same as build, into a repo-local $(BIN)/ for Terraform dev_overrides
## (point dev_overrides at $(PWD)/$(BIN))
install: build

## unit: run unit tests (CI's `Go test` stage)
unit:
	go test ./...

## testacc: run acceptance tests against a live Multipass daemon; needs the
## multipass CLI installed and will create/destroy real instances
testacc:
	TF_ACC=1 go test ./... -run 'TestAcc' -timeout 2h

## fmt: rewrite Go files with gofmt (CI enforces formatting via the lint stage)
fmt:
	gofmt -s -w $(GOFILES)

## fmtcheck: fail if any tracked Go file is not properly formatted
fmtcheck:
	@unformatted="$$(gofmt -s -l $(GOFILES))"; \
	if [ -n "$$unformatted" ]; then \
		echo "not gofmt-clean:"; echo "$$unformatted"; exit 1; \
	fi

## lint: golangci-lint against .golangci.yml (CI's `Golangci-lint` stage)
lint:
	@if [ ! -x "$(GOLANGCI_LINT)" ]; then \
		echo "golangci-lint not found at $(GOLANGCI_LINT)"; \
		echo "run: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)"; \
		exit 1; \
	fi
	$(GOLANGCI_LINT) run

## govulncheck: scan for vulnerabilities reached by calls in this module
## (CI's `Govulncheck` stage); uses an installed binary, else falls back to
## `go run`, which needs no separate install
govulncheck:
	@if [ -x "$(GOVULNCHECK)" ]; then \
		$(GOVULNCHECK) ./...; \
	else \
		go run golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION) ./...; \
	fi

## docs: render docs/ from templates/ and the current schema (CI's docs-sync
## gate runs this then `git diff --exit-code docs/`, so every schema change
## must be regenerated into the committed docs)
## Note: tfplugindocs resolves every path relative to --provider-dir (that dir
## is also its build cwd, which is why it points at cmd/ — main.go lives there)
docs:
	go tool tfplugindocs generate \
		--provider-name multipass \
		--provider-dir cmd/terraform-provider-multipass \
		--website-source-dir ../../templates \
		--rendered-website-dir ../../docs

## goreleaser-dry: full build + checksums in snapshot mode, no upload, no GPG
## (the release workflow handles signing with the imported key)
goreleaser-dry:
	goreleaser release --snapshot --clean --skip=sign

## validate-docs: link validation used by the docs workflow (needs pwsh)
validate-docs:
	pwsh ./scripts/validate-docs.ps1

## hooks: wire the .githooks pre-commit gate into this clone
hooks:
	git config core.hooksPath .githooks
	@echo "pre-commit hook installed (lint + unit tests); bypass with GITHOOK_SKIP=1"