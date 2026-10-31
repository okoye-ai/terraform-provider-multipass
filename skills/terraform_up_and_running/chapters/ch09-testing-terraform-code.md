# Chapter 9: How to Test Terraform Code

## Core Idea
Testing Terraform is a probability game, not a guarantee — the goal is confidence to change code. Since you cannot test infrastructure on localhost, all Terraform testing deploys real resources into isolated environments; the discipline is to capture your manual apply → validate → destroy steps as automated code, run them in isolated sandboxes/test accounts, and clean up reliably.

## Frameworks Introduced

### Manual tests
- **What**: run `terraform apply` on a module's easy-to-deploy `examples/` code, poke the deployed resource with the right client (curl/HTTP for an ALB, MySQL client for a DB, SSH for a non-listening server), then `terraform destroy`.
- **When to use**: quick gut checks while developing; also the template the automated test will encode.
- **How**: e.g. `curl -s -o /dev/null -w "%{http_code}" <alb_dns>` → expect `404`. Requires a **sandbox environment** isolated from staging/production — gold standard: one AWS account per developer (child accounts via AWS Organizations cost nothing extra).

### Cleaning up after tests
- **When to use**: always — unmanaged test infra accumulates; costs spiral.
- **How**: culture of `terraform destroy` when done, plus scheduled nukers: `cloud-nuke aws --older-than 48h` (cron, once/day per sandbox) or `aws-nuke`.

### Automated test types: unit / integration / end-to-end
- **Unit tests (Terraform)**: verify a *single reusable module* by deploying just its example to a real environment and validating it. Pure unit testing is impossible (99% of module code is API calls to complicated dependencies; mocking via LocalStack is impractical and proves little), so Terraform "unit tests" are really integration tests kept tiny for speed. Strategy: small module → easy example → `terraform apply` → validate (infra-specific) → `terraform destroy`.
- **Integration tests**: deploy *several modules together* and validate they fit — e.g. deploy the real `mysql` module, then `hello-world-app` pointed at its state, validate, tear down in reverse order.
- **End-to-end tests**: deploy the whole architecture and test from the end-user's view (e.g. Selenium). Full from-scratch E2E is rarely viable (too slow, too brittle); the practical strategy is a **persistent** production-like "test" env deployed once and left running, then each change applied incrementally and validated. Bonus: this also tests the deployment *process*, matching production rollout.

### Dependency injection
- **What**: pass dependencies in from outside instead of hardcoding them, so tests can inject mocks.
- **When to use**: whenever a module hard-references data sources (remote-state DB, default VPC/subnets) that tests shouldn't be forced to deploy.
- **How**: optional input variables (`default = null`) typed to match another module's outputs (`mysql_config = object({address = string, port = number})` enables type-safe composition: `mysql_config = module.mysql`); keep external-dependency data sources in a `dependencies.tf`; gate each with `count = var.X == null ? 1 : 0`; resolve in `locals` ternaries; inject test values via Terratest `Vars` or a mock default.

### Test parallelization
- **When to use**: any suite of >1 test; sequential infra suites take hours.
- **How**: `t.Parallel()` atop each Go test. Default parallelism = CPU count; override via `GOMAXPROCS` or `go test -parallel 2`. Parallelism forces **namespacing**: every name configurable, tests set `fmt.Sprintf("test-%s", random.UniqueId())` (6-char base-62, ~56B combinations). To run multiple tests against the *same* folder, copy it to a unique temp dir (`test_structure.CopyTerraformFolderToTemp`) to avoid `.terraform`/state clashes.

### Test stages (test_structure)
- **When to use**: iterative local development on multi-module tests; no effect in CI (all stages run).
- **How**: wrap each stage in `test_structure.RunTestStage(t, "name", func)`; persist options with `SaveTerraformOptions`/`LoadTerraformOptions` (via disk — stages may run in separate processes). Skip any stage foo with `SKIP_foo=true`. Workflow: deploy stages skipping teardown → iterate deploy_app+validate only (10–60 s vs 10–15 min) → final teardown-only run.

### Retries
- **When to use**: infrastructure is intermittently flaky (throttling, TLS handshakes, eventual consistency).
- **How**: in `terraform.Options`: `MaxRetries`, `TimeBetweenRetries`, `RetryableTerraformErrors` (keys = regexes matched in logs, values = log detail); HTTP-level retry via `http_helper.HttpGetWithRetry` (e.g. 10 retries / 10 s) while health checks and DNS settle.

### The test pyramid
- **What**: many unit tests at the bottom, fewer integration tests, few end-to-end tests on top — cost, complexity, brittleness, and runtime all rise as you go up. Brittleness compounds: at 0.1% transient failure per resource, success odds = 99.9%^N — 20 resources ≈ 98.0%, 60 ≈ 94.1%, 600 ≈ 54.9% (half of E2E runs fail transiently; retries become endless whack-a-mole). **Key takeaway: smaller modules are easier and faster to test** — test as low in the pyramid as possible.

### Static analysis (validate / tfsec / tflint / Terrascan)
- **What**: parse code without executing it.
- **When to use**: cheapest first layer — fast, stable (never flaky), no cloud auth, no deploys.
- **How**: `terraform validate` (built-in, syntax only); `tfsec` (security, YAML/JSON custom checks); `tflint` (pluggable linter, Go plugins); `Terrascan` (compliance, Rego). Enforce policies as code: no inbound `0.0.0.0/0`, tagging conventions. Limits: only statically determinable errors (can't catch violations on dynamic values read from variables/files); passing checks ≠ working infrastructure.

### Plan testing (OPA / Sentinel / Checkov / terraform-compliance / Terratest)
- **What**: run `terraform plan` — executes read steps (state fetch, data sources) but not writes — and assert on the output.
- **When to use**: middle layer: faster/more stable than unit/integration, catches more than static analysis; requires cloud auth, no deploys.
- **How**: Terratest — `terraform.InitAndPlan`, then `GetResourceCount(t, planString)` to assert Add/Change/Destroy counts, and `InitAndPlanAndShowWithStructNoLogTempPlanFile` to assert resource attributes from the parsed plan. OPA — Rego policies (`allow { ... }`), then `terraform plan -out tfplan.binary` → `terraform show -json tfplan.binary > tfplan.json` → `opa eval --data enforce_tagging.rego --input tfplan.json --format pretty data.terraform.allow` (e.g. enforce a `ManagedBy = terraform` tag). Sentinel = HashiCorp commercial; Checkov = Python/YAML; terraform-compliance = BDD.

### Server testing (InSpec / Serverspec / Goss)
- **What**: DSL-based validation that deployed *servers* are configured correctly (file modes, installed deps, listening ports); originated with config management (Chef/Puppet).
- **When to use**: server resources and checklist-style compliance libraries (PCI/HIPAA).
- **How + limits**: e.g. InSpec `describe file('/etc/myapp.conf')`, `describe port(8080)`. Requires full apply plus SSH-style auth; slow, somewhat flaky, costs real resources; checks servers only.

## Key Concepts
- **Sandbox environment**: fully isolated environment (ideally a developer's own AWS account) serving as the "localhost" for manual testing.
- **Test account**: separate AWS account only for automated tests — safe to nuke anything older than a few hours.
- **Unit (Terraform)**: a single reusable module; its "unit test" deploys the module's example.
- **Dependency injection**: making a module's external dependencies optional inputs so tests substitute mocks.
- **Namespacing**: every resource name configurable and unique per test run, so parallel tests never collide.
- **Test stage**: a named, independently skippable test chunk (deploy/validate/teardown) selected via `SKIP_<name>` env vars.
- **Flaky test**: intermittently failing test from transient infra errors; handled with retries.
- **Test pyramid**: proportionality model — many cheap fast unit tests, few expensive brittle E2E tests.
- **Policy as code**: security/compliance/reliability rules as code enforced in the pipeline (Rego/Sentinel/Go/YAML/BDD).
- **Partial backend configuration**: empty `backend "s3" {}` in code; config injected with `-backend-config=backend.hcl` so tests never overwrite real state.
- **`defer terraform.Destroy`**: Go idiom guaranteeing cleanup runs even when assertions fail; place the defer *before* `InitAndApply`.

## Mental Models
- **Use "how would I test this manually?" when designing any automated test** — the test is the manual apply/validate/destroy procedure captured as code.
- **Use the Ruby `Handlers` refactor (simple values in, simple values out) when judging testability** — in Terraform terms: variables/outputs as the interface, hidden data sources as the dependencies to inject.
- **Use the test pyramid when deciding what to write next** — test as low in the pyramid as possible; that's the fastest, most reliable feedback loop.
- **Use the 99.9%^N math when scoping E2E** — transient-failure odds compound with resource count, so don't deploy the world from scratch per run.

## Anti-patterns
- **Testing against shared/staging/production**: hardcoded backend `bucket`/`key` overwrites the real staging state file — always test in an isolated account with injected backend config.
- **Skipping cleanup / not namespacing**: leftover infra costs money; identical names clash across parallel, teammate, and CI runs.
- **Trusting only static analysis or plan testing**: all checks can pass while the infra doesn't work — they don't check functionality, and static tools can't see dynamic values.
- **Full from-scratch E2E on complicated architectures**: hours per run, ~55% pass rate from transients alone, ~one fix attempt per day — teams end up ignoring or bypassing the tests.
- **Destroy at the end of the test body instead of `defer`**: earlier failures exit before cleanup and leak infra.
- **Endpoint mocking (LocalStack) as the unit-test strategy**: impractical at scale and gives little real confidence.
- **Running infra tests under Go's default 10-min timeout**: Go force-kills the run, skipping destroy; always pass e.g. `-timeout 30m`.

## Code Examples

**Basic Terratest unit test for the ALB example** (defer destroy early → init+apply → output → retry HTTP → assert):

```go
func TestAlbExample(t *testing.T) {
    t.Parallel()

    opts := &terraform.Options{
        TerraformDir: "../examples/alb",
        Vars: map[string]interface{}{
            "alb_name": fmt.Sprintf("test-%s", random.UniqueId()),
        },
    }

    // Clean up everything at the end of the test
    defer terraform.Destroy(t, opts)

    // Deploy the example
    terraform.InitAndApply(t, opts)

    // Get the URL of the ALB
    albDnsName := terraform.OutputRequired(t, opts, "alb_dns_name")
    url := fmt.Sprintf("http://%s", albDnsName)

    // Test that the ALB's default action is working and returns a 404
    expectedStatus := 404
    expectedBody := "404: page not found"
    maxRetries := 10
    timeBetweenRetries := 10 * time.Second

    http_helper.HttpGetWithRetry(
        t, url, nil, expectedStatus, expectedBody, maxRetries, timeBetweenRetries,
    )
}
```

**Retries on transient Terraform errors / test stages:**

```go
MaxRetries:              3,
TimeBetweenRetries:      5 * time.Second,
RetryableTerraformErrors: map[string]string{
    "RequestError: send request failed": "Throttling issue?",
},
```

```go
stage := test_structure.RunTestStage
defer stage(t, "teardown_db", func() { teardownDb(t, dbDirStage) })
stage(t, "deploy_db", func() { deployDb(t, dbDirStage) })

$ SKIP_teardown_db=true SKIP_deploy_db=true \
  go test -timeout 30m -run 'TestHelloWorldAppStageWithStages'
```

**Plan testing with Terratest:**

```go
planString := terraform.InitAndPlan(t, opts)
resourceCounts := terraform.GetResourceCount(t, planString)
require.Equal(t, 5, resourceCounts.Add)
require.Equal(t, 0, resourceCounts.Change)
require.Equal(t, 0, resourceCounts.Destroy)
```

## Reference Tables

**Testing approaches compared (Table 9-4; more filled = better):**

| Criterion | Static analysis | Plan testing | Server testing | Unit tests | Integration | End-to-end |
|---|---|---|---|---|---|---|
| Fast to run | ■■■■■ | ■■■■□ | ■■■□□ | ■■□□□ | ■□□□□ | □□□□□ |
| Cheap to run | ■■■■■ | ■■■■□ | ■■■□□ | ■■□□□ | ■□□□□ | □□□□□ |
| Stable and reliable | ■■■■■ | ■■■■□ | ■■■□□ | ■■□□□ | ■□□□□ | □□□□□ |
| Easy to use | ■■■■■ | ■■■■□ | ■■■□□ | ■■□□□ | ■□□□□ | □□□□□ |
| Check syntax | ■■■■■ | ■■■■■ | ■■■■■ | ■■■■■ | ■■■■■ | ■■■■■ |
| Check policies | ■■□□□ | ■■■■□ | ■■■■□ | ■■■■■ | ■■■■■ | ■■■■■ |
| Check servers work | □□□□□ | □□□□□ | ■■■■■ | ■■■■■ | ■■■■■ | ■■■■■ |
| Check other infra works | □□□□□ | □□□□□ | ■■□□□ | ■■■■□ | ■■■■■ | ■■■■■ |
| Check all infra works together | □□□□□ | □□□□□ | □□□□□ | ■□□□□ | ■■■□□ | ■■■■■ |

**Layer / what it tests / tools / cost (synthesized from Tables 9-1 to 9-3):**

| Layer | What it tests | Tools (custom checks) | Cost |
|---|---|---|---|
| Static analysis | Syntax + static policy violations | `terraform validate` (none); `tfsec` (YAML/JSON, AWS/Azure/GCP/K8s); `tflint` (Go plugins); `Terrascan` (Rego) | Lowest — no auth, no deploy |
| Plan testing | Read-path validity + policy on plan JSON | `Terratest` (Go); `OPA` (Rego); `Sentinel` (Sentinel, commercial); `Checkov` (Python/YAML, built-in checks); `terraform-compliance` (BDD) | Low — auth needed, no deploy |
| Server testing | Server config on deployed instances | `InSpec` (Ruby DSL); `Serverspec` (Ruby/RSpec); `Goss` (YAML) | High — full apply + SSH |
| Unit (module) | One module works in isolation | Terratest | Medium — ~4–5 min/module |
| Integration | Modules work together | Terratest + test stages | High — 10–15 min (AWS bound) |
| End-to-end | Whole system, user's view | Terratest + Selenium vs persistent "test" env | Highest |

## Worked Example
**Worked example** (`test/hello_world_integration_test.go`) — integration test of the staging "Hello, World" app with the real MySQL module:

1. Point constants at the live code: `dbDirStage = "../live/stage/data-stores/mysql"`, `appDirStage = "../live/stage/services/hello-world-app"`.
2. Make the live code injectable: expose `db_name` on the mysql layer; `db_remote_state_bucket`/`key`/`environment` variables on the app layer.
3. Partial backend config (`backend "s3" {}` + values in `backend.hcl` via `terraform init -backend-config=backend.hcl`) so tests can't overwrite staging state.
4. Test body (cleanup via `defer` in reverse order):

```go
const dbDirStage = "../live/stage/data-stores/mysql"
const appDirStage = "../live/stage/services/hello-world-app"

func TestHelloWorldAppStage(t *testing.T) {
    t.Parallel()

    // Deploy the MySQL DB
    dbOpts := createDbOpts(t, dbDirStage)
    defer terraform.Destroy(t, dbOpts)
    terraform.InitAndApply(t, dbOpts)

    // Deploy the hello-world-app
    helloOpts := createHelloOpts(dbOpts, appDirStage)
    defer terraform.Destroy(t, helloOpts)
    terraform.InitAndApply(t, helloOpts)

    // Validate the hello-world-app works
    validateHelloApp(t, helloOpts)
}
```

5. `createDbOpts`: `db_name = fmt.Sprintf("test%s", uniqueId)` plus test-only `BackendConfig` (test bucket/region, `key = fmt.Sprintf("%s/%s/terraform.tfstate", t.Name(), uniqueId)`).
6. `createHelloOpts(dbOpts, dir)`: passes `dbOpts.BackendConfig["bucket"]`/`["key"]` as `db_remote_state_*` and `dbOpts.Vars["db_name"]` as `environment` — the app reads the exact state the db just wrote.
7. `validateHelloApp`: reads `alb_dns_name`, then `http_helper.HttpGetWithRetryWithCustomValidation` with `func(status int, body string) bool { return status == 200 && strings.Contains(body, "Hello, World") }` (contains, not equals — user-data emits HTML too).
8. `go test -v -timeout 30m -run "TestHelloWorldAppStage"`: ~795 s, over twice the unit test. Wrapping the same logic in `test_structure` stages cut the inner dev loop (deploy_app + validate only) to 10–60 s.

## Key Takeaways
- **You can't use localhost when testing Terraform code**: manual testing = deploy into isolated sandbox environments (gold standard: per-developer account for manual, a separate account entirely for automated tests).
- **You cannot do pure unit testing of Terraform code**: modules are almost entirely external API calls; "unit tests" deploy one module and stay small for speed.
- **Regularly clean up sandbox environments**: `terraform destroy` plus scheduled `cloud-nuke --older-than 48h`; otherwise cost spirals.
- **You must namespace all of your resources**: make names configurable, inject `random.UniqueId()`-suffixed values so parallel tests don't conflict.
- **Smaller modules are easier and faster to test**: test as low in the pyramid as possible; the bottom has the fastest, most reliable feedback loop.
- **Mix test types in pyramid proportions — start small**: lots of unit, fewer integration, few high-value E2E against a persistent env; even static analysis alone is a valid starting point to build on incrementally.
- **Always `defer terraform.Destroy` and run infra tests with a long `-timeout`** so failures and Go's kill timer never leak infrastructure.
- **Infrastructure code without automated tests is broken**: the ecosystem changes constantly, so run tests after every commit — they catch bugs in your code *and* in Terraform, Packer, AWS, etc.

## Connects To
- **Ch. 8 (modules)**: examples folder, small-module principle, and dependency-injection refactoring continue Chapter 8's module patterns.
- **Ch. 7 (multi-account)**: sandbox/test accounts via AWS Organizations; remote state wiring between modules.
- **Ch. 4 (backends/workspaces)**: partial backend configuration used instead of workspaces for test isolation.
- **Ch. 10 (team workflows)**: destination — a CI server runs the suite after every commit and reverts/fixes failing commits to keep code always working.
- **Ch. 5 (`terraform plan`/state)**: plan testing builds directly on plan output structure and remote state mechanics.