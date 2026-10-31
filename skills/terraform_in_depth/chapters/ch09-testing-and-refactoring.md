# Chapter 9: Testing and refactoring

## Core Idea
IaC testing means integration tests against real, destroyed-afterwards infrastructure (with mocks as fast supplements), and a trustworthy test suite is what buys the freedom to refactor — internal changes invisibly, external changes deliberately through expand-and-contract and planned majors.

## Frameworks Introduced
- **Four benefits of a test suite**
  - When to use: justifying test investment to a team.
  - How: fewer bugs and regressions (regression = previously fixed bugs reappearing or features stopping working); easier PR review (no pulling branches to verify); better-maintained backward compatibility (a breaking change should break tests); and psychological safety — teams that feel safe shipping are more productive.
- **What to test vs. what not to test**
  - When to use: deciding where finite test-writing time goes.
  - How: don't test the providers (pass-a-variable, assert-it-comes-back is worthless). Test your logic: data transformations, strings built from data sources and attributes, regular expressions with multiple patterns, dynamic blocks with zero/one/many, and system functionality (HTTP endpoints reachable, generated credentials actually work).
- **Software-testing vs. IaC-testing differences**
  - When to use: setting expectations for speed and cost.
  - How: time (VMs take minutes, databases can exceed 30 minutes — cycle time is orders of magnitude worse) and money (resources cost real money, so destruction is mandatory). Weigh that against not-testing cost: outages.
- **Unit vs. integration testing (and where Terraform sits)**
  - When to use: choosing a testing strategy.
  - How: unit tests isolate pieces behind mocks; integration tests exercise real components together — the real world is a spectrum. Terraform can't meaningfully be unit tested (configuring external systems is the point); providers are the already-unit-tested "functions"; module developers write integration tests, with unit-style checks only for logic like transformations.
- **IaC testing flow: Configure → Launch → Validate → Cleanup**
  - When to use: structuring any test.
  - How: pick configuration options, launch resources with them, run a group of test cases against the running system, destroy everything. Group many assertions under one configuration — infrastructure is too slow and costly to recreate per assertion; run *separate* configurations for contradictory use cases (private-logging S3 vs public-static-host S3).
- **Examples as tests (the `examples/` pattern)**
  - When to use: every module you maintain.
  - How: ship fully working example invocations per integration (`examples/basic`, `examples/lambda`, `examples/ecs`, `examples/ec2` for an ALB module); users learn from them, maintainers iterate from them, and tests pointed at the example directories prove they always work. Bonus: examples can create external test fixtures (data sources, custom outputs) that would pollute the module itself.
- **Test-suite hygiene practices**
  - When to use: running tests reliably and cheaply.
  - How: **concurrency** — tests run in parallel (multiple PRs at minimum), so randomize names with `random_string` (length 8, no special chars, lowercase), or bake randomness into the module for recreate-after-delete resources like `aws_secretsmanager_secret` (one-week deletion recovery); **timeouts** — Go testing defaults to 10 minutes and CI defaults must both be raised (use `go test -timeout 60m`; GitHub Actions default 360 minutes is already generous), because a timeout kills the run, orphans resources, and loses state; **automatic cleanup** — schedule a vendor nuke tool (search "<Vendor> Nuke", e.g. `rebuy-de/aws-nuke`) against isolated test accounts only, never production; **authentication** — use OIDC per ch8; **testing as code** — tests are code: name variables well, comment intent, review PRs with tests in mind, refactor tests freely.

## Key Concepts
- **Terratest**: Gruntwork's de facto standard Terraform test framework (2016/2018, built on the Go testing package); imports as `github.com/gruntwork-io/terratest/modules/...` with 20+ helper packages (provider-specific like AWS/Azure/GCP/OCI, protocol-level like `http-helper` and `dns-helpers`).
- **Terraform testing framework**: native HCL testing since Terraform/OpenTofu v1.6, extended every release; `.tftest.hcl` files with `variables`, `run` (each block one action — apply by default, `command = plan` optional), and `assert` blocks (`condition` + `error_message`).
- **Plan-time limitation**: in a `command = plan` run you can only assert on values known during plan — reading apply-time outputs raises "Unknown condition value" (either drop it or use an apply run).
- **Named values access**: the testing framework can assert directly on any resource attribute, data source, or local (`terraform_data.this.input == "test"`) — impossible for wrapper-based Terratest, which can only see outputs.
- **Mocks (v1.7, beta)**: `mock_provider "aws" {}` replaces the real provider with fake values and zero infrastructure — near-instant, near-free, and as close to unit testing as Terraform gets. Default mock values by type: numbers `0`, booleans `false`, maps `{}`, lists/sets `[]`, objects built from those defaults. Customize via `mock_resource`/`mock_data` defaults, `override_resource`/`override_data`/`override_module` blocks (scoping: inside `mock_provider` → only that provider; top level → every run; inside a run → that run only), and reusable `tfmock.hcl` libraries (imported by *directory*, not file).
- **Mock discipline**: fake data detaches tests from reality — mocks supplement integration tests (edge cases, logic), never replace them; review mock definitions on major provider upgrades.
- **Copilot and testing**: LLMs write decent Terratest (lots of Go training data) but miss your conventions (TERRATEST_BINARY switch, `WithDefaultRetryableErrors`) and are "completely unaware" of the Terraform testing framework — use Copilot as inspiration for assertions, keep your skeleton.
- **Refactoring (strict definition)**: restructuring code without changing external behavior. Hafner's split: **internal refactoring** is invisible to users (anything not touching an input or output) — do it whenever; **external refactoring** changes the interface users notice.
- **Parallel change / expand and contract**: the rename technique — keep old and new variables coexisting behind one local, deprecate the old, remove it in the next major.
- **moved block** (ch6): the right way to rename a resource; *removing* an existing moved block breaks migration from older module versions — keep even deprecated ones, they're harmless (removable only at a major).
- **Technical debt**: deferred quality work; expect roughly 20% of effort on refactoring and code quality for a mature, active codebase (more to pay back debt).

## Mental Models
- Think of a test suite as the safety net that makes refactoring possible: internal refactoring should never break tests — if it does, your change had unintended consequences.
- Use Copilot/LLMs for assertion ideas, your own skeleton for structure: "use Copilot as an inspiration ... adjust your own tests with those suggestions."
- Use examples directories as your test matrix: one directory per integration, each proving both that the example works and that the module works.
- Batch breaking changes: pile interface-breaking wishes in a wishlist (tickets or a markdown file), ship them together at the next major — ideally stacked on a provider major that forces a break anyway (but never sit on a security break).
- Think of version support as the lowest-common-denominator problem: with the native framework, "you are always locked into only using the features of the lowest version of Terraform that you have to support."

## Anti-patterns
- **Testing pass-through attributes**: asserting a variable arrives at a resource unchanged duplicates the provider's own tests.
- **Testing providers instead of your logic**: Terraform already unit-tests its providers; your value-add is transformations, constructed strings, dynamic blocks, and end-user functionality.
- **Per-assertion infrastructure lifecycles**: launching/destroying a stack per test instead of grouping assertions under one configuration burns time and money.
- **Static resource names in tests**: concurrent runs collide (and some resources ban name reuse for a week); add `random_string`.
- **Forgetting the timeout flag**: the default 10-minute Go timeout can kill tests mid-run, orphaning resources and losing state.
- **Letting mock complexity drift from reality**: over-mocked tests stop exercising real provider behavior — review mocks on major provider versions.
- **Unreviewed breaking changes drip-released**: "having a lot of releases with breaking changes in them, even if those changes are small, can be frustrating for users" — bundle them.
- **More than one major per year**: try to avoid it; if a wishlist outgrows that, that's a signal about the next major's scope.
- **Dropping the old major instantly**: users adopt majors asynchronously; fix bugs on a branch cut from the old release tag.

## Code Examples
```go
// terratest/example_test.go — the canonical Terratest test pattern
package tests

import (
    "os"
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestExample(t *testing.T) {
    t.Parallel() // allow concurrent tests

    // Engine switch: honors TERRATEST_BINARY (terraform | tofu)
    terraformBinary := os.Getenv("TERRATEST_BINARY")
    if len(terraformBinary) <= 0 {
        terraformBinary = "terraform"
    }

    terraformOptions := terraform.WithDefaultRetryableErrors(t,
        &terraform.Options{
            TerraformDir:    "../examples/basic", // point at an example
            TerraformBinary: terraformBinary,
            Vars: map[string]interface{}{
                "test_input": "test",
            },
        })

    // Destroy runs after all other test code, even on failure.
    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)
    testOutput := terraform.Output(t, terraformOptions, "test_output")

    assert.Equal(t, "test", testOutput)
}
```
```hcl
# tests/example.tftest.hcl — native framework, mocks, and named values
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
}

variables {
  zone_id = "Z1234567890"
  records = ["127.0.0.1"]
  domain  = "example.com"
  name    = "my_test"
}

run "dns_record_name" {
  command = plan # logic can be tested at plan time with mocks

  assert {
    condition     = aws_route53_record.main.name == "my_test.us-east-1.example.com"
    error_message = "Domain name not properly generated from region."
  }
}

run "input_passed_to_resource" {
  # apply runs can also assert on internal named values:
  #   condition = terraform_data.this.input == "test"
}
```
- **What it demonstrates**: both frameworks obeying the Configure → Launch(dry or real) → Validate → Cleanup flow, with engine switching and one configuration carrying many assertions.

## Reference Tables
Terratest vs. Terraform testing framework (table 9.1):

| Dimension | Terratest | Terraform testing framework |
|---|---|---|
| Language | Go | HCL |
| Release year | 2018 | 2023 |
| Native | No | Yes |
| Flexible versions | Yes | No |
| Copilot support | No | Yes (listed as framework advantage) |
| Community contributions | Yes | No |
| Third-party libraries | Yes | No |

Selection rule the chapter lands on: start new teams on the native framework (same language as the project, lower barrier to entry); stay on Terratest if you already use it, need helper packages and the Go ecosystem, or must support a wide span of Terraform versions (the framework can't even test v1.5, and v1.7 mocks exclude v1.6).

Mock value defaults (table 9.2): numbers → `0`; booleans → `false`; maps → `{}`; lists and sets → `[]`; objects → attributes created with those same defaults.

## Worked Example
Renaming an input variable without breaking users (external refactoring via parallel change):

**Before** — one variable, referenced everywhere:
```hcl
variable "subnets" {
  type        = list(string)
  description = "A list of subnet IDs to deploy the resources into."
}
```
**After (transition release, still backward compatible)**:
```hcl
variable "subnets" {
  type        = list(string)
  description = "Deprecated: use subnet_ids instead."
  default     = null # null lets us detect that it isn't used
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs to deploy the resources into."
  default     = "my_fancy_default" # the module's real default value now lives here
}

locals {
  use_this_variable = var.subnets != null ? var.subnets : var.subnet_ids
}

output "my_output" {
  value = local.use_this_variable # downstream code points at the local
}
```
**End-to-end**: the new name gives identical description/validation to the old; a local picks old-if-set, else new; the module's internal logic rewrites itself to reference the local. Users migrate gradually; each version change is still a non-breaking (minor/patch) upgrade. In the next major release, delete the deprecated variable — the whole point of the transition release. This is the same release-shape used for the rename wishlist: internal refactoring goes out anytime; external refactoring (renamed inputs/outputs, removed moved blocks, removed features) accumulates on the wishlist and ships as one planned major on a release branch with `UPGRADE.md`/`CHANGELOG.md` notes, pre-release tags (`v2.0.0-alpha`, `v2.0.0-beta`), and a bugfix branch cut from the old major's tag.

## Key Takeaways
1. Test your logic, not the providers: transformations, constructed strings, regexes, dynamic blocks (0/1/many cases), and real end-user functionality.
2. Ship working `examples/` per integration and point tests at them — documentation, developer iteration paths, and coverage from one artifact.
3. Build tests for concurrency from day one: random_string names, `-timeout 60m` or equivalent, and scheduled account-reset tooling in *isolated* test accounts.
4. Default to the Terraform testing framework for new suites (add mocks for logic/edge cases) and keep Terratest for broad version support and its helper library; always keep full integration tests on real infrastructure.
5. Internal refactoring is safe and testable-by-construction; classify every change by whether it touches inputs/outputs, and batch external changes into planned majors (ideally piggybacking provider majors).
6. Renames and moves use the two compatibility mechanisms: parallel change (expand and contract) for variables, moved blocks for resources — and never rush to delete moved blocks.
7. Budget ~20% of effort on refactoring and quality for a mature active codebase; debt that isn't paid shows up as outages.

## Connects To
- **Ch 7**: tests fill the `terratest`/`terraform_test` makefile stubs, reuse `TF_ENGINE` and the version matrix, and become required CI checks.
- **Ch 8**: semver majors (2.0.0 tags through registries) are the release vehicle for external refactoring; OIDC authenticates the test runs.
- **Ch 6**: moved blocks and state mechanics underpin resource renaming; **Ch 5**: the dependency graph means file reorganization produces an empty plan.
- **Extreme Programming / refactoring practice**: parallel change ("expand and contract") and regression testing are standard software-engineering concepts the chapter applies to Terraform.
