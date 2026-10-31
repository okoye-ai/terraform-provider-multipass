# Patterns & Techniques — Terraform Cookbook (Satirli & Dolezal)

## Validation Ladder
**When to use**: before every plan/apply, and in CI on every PR.
**How**: layered, each catching what the previous cannot —
1. `terraform fmt` → consistent style (pure formatting)
2. `terraform validate` → syntax/type errors without touching state
3. `terraform console` → experiment on expressions safely (REPL)
4. TFLint → provider-specific linting (catches bad AMI IDs, instance types)
5. TFSec / security scanning → hardcoded secrets, open security groups
6. Variable `validation` blocks (preconditions) → reject bad input at the boundary
7. Resource `lifecycle.postcondition` → guarantee about the produced state
8. OPA / Sentinel policy as code → organizational rules (regions, tags, cost tiers)
9. GitHub Actions → run the whole ladder automatically on every PR/repo event
**Trade-offs**: later layers = more setup but closer to real-world behavior; never rely on `local-exec` checks in production.

## Optimistic Data Retrieval (can / try)
**When to use**: values or attributes that may be absent (e.g. optional outputs, empty data lookups).
**How**: `try(actual, fallback)` returns first success; `can(expr)` returns a boolean guard. Wrap attribute access, not whole resources.
**Trade-offs**: masks real errors if the fallback hides a genuine misconfiguration; keep fallbacks loud and explicit.

## Input Sanitization Pipeline
**When to use**: any user/module-supplied string.
**How**: `trimspace` (edges) → `chomp` (trailing newline, esp. after `file()`) → `trimprefix`/`trimsuffix` (known affixes) → `regex`/`replace` (deltas) → declare a `validation` block so bad shape dies at plan time with a good error message.
**Trade-offs**: a few lines of `locals` vs. drift caused by invisible whitespace.

## Guarded File Access
**When to use**: reading local files into configs.
**How**: `fileexists()` before `file()`, `fileset`/`filebase64` as needed.
**Trade-offs**: local files tie the config to the operator's filesystem — CI needs the same files present.

## CIDR Decomposition
**When to use**: generating many subnets/hosts from one network block.
**How**: compute `/24`s per tier with `cidrsubnet`, individual nodes with `cidrhost`; parameters, not hand-math.
**Trade-offs**: math-heavy to read; document the netmask scheme in a local/comment.

## Provider Credential Ladder
**When to use**: choosing how a provider authenticates.
**How**: prefer (1) IAM role assumption, (2) dynamic secrets from Vault, (3) explicit credentials in env vars, over (4) static keys in plaintext. For private module registries: `credentials` block or auth token in config.
**Trade-offs**: convenience vs. blast radius if credentials leak.

## Multiple Identical Providers (Aliases)
**When to use**: same provider, different accounts/regions/clusters (AWS orgs, multi-region, service-health-aware endpoints).
**How**: name a `provider "aws" { alias = ... }` per target and set `provider =` on each resource; add `profile`/`region` per alias. Health-aware routing: pair an `http` data source + `jsondecode` + a ternary to pick a healthy endpoint.
**Trade-offs**: more wiring per resource; keeps multi-target state in one config.

## Secrets Tiering
**When to use**: deciding where a secret lives.
**How**: dynamic secrets (Vault, short TTL) > Vault KV / password-manager bridging (external data source) > `TF_VAR_` env vars > anything plaintext. Always `sensitive = true`, audit and rotate, inject late in CI, never into state where avoidable.
**Trade-offs**: strongest tiers add moving parts (Vault) and ops overhead.

## Kubernetes: Three Deployment Surfaces
**When to use**: choosing how Terraform schedules containers.
**How**: `kubernetes_manifest` (HCL-native), Helm provider for charts + monitoring, or k2tf to convert existing YAML. Distinguish **cluster deployment** (provisioning the cluster) from **cluster configuration** (what runs on it) — different tools, different lifecycles.
**Trade-offs**: YAML is the ecosystem default, HCL gives plan/apply semantics; NetworkPolicies are infrastructure, not app config.

## Import Before You Delete
**When to use**: adopting infrastructure built outside Terraform.
**How**: config-driven import (`import` blocks / `terraform import`), then reconcile and validate; workspaces or state moves organize the result.
**Trade-offs**: slow, meticulous; the only safe way to retire "snowflake" systems into code.

## Blue-Green via Conditional Counts
**When to use**: zero-downtime deploys with a load balancer in front.
**How**: two resource sets whose `count`/weights are driven by variables; flip traffic, then retire blue.
**Trade-offs**: doubles cost transiently; simpler than provider-level blue-green tooling.

## State Safety Doctrine
**When to use**: any state question, ever.
**How**: prefer built-in/automated HCP Terraform mechanisms (locking, versioned state history, UI restore) over manual `terraform state` surgery; `terraform state rm` only with team awareness and a backup; regular state audits.
**Trade-offs**: manual edits are fast and dangerous; automation is slower and reversible.

## Repository Strategy (VCS)
**When to use**: structuring Terraform repos for teams.
**How**: version-control everything; PR + review gates; Terraform's plan output is part of the review; smaller, more frequent applies; Dependabot for provider bumps (review before merging).
**Trade-offs**: monorepo vs. per-stack repos affect review scope and state isolation.

## GitOps Loop
**When to use**: treating the repo as the source of truth for infrastructure.
**How**: PR → CI (validation ladder) → automated plan → apply (remote operations at scale) → drift detection feeds back into PRs.
**Trade-offs**: full automation demands the full validation ladder; humans stay on the PR step.