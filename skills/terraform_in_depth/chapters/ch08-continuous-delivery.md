# Chapter 8: Continuous delivery and deployment

## Core Idea
CI is not CD: modules are delivered as semver-tagged packages through registries, while infrastructure is deployed from a Git single source of truth by automated systems — pick your project structure (environment as root module wins) and your CD platform (favor broad IaC support) accordingly, and eliminate secrets with OIDC first.

## Frameworks Introduced
- **CI vs CD boundary (Hafner's figure 8.1 split)**
  - When to use: deciding what belongs in which automation tier.
  - How: CI ends at `tag release / publish artifact` — develop feature, PR, run tests, merge to main; CD starts at `trigger deployment` — push to staging, push to production. CI keeps a workable copy of the program; CD regularly deploys into environments.
- **DORA benchmark**
  - When to use: judging your CD maturity.
  - How: high-performing teams deploy multiple times a day with low failure rate and fast recovery.
- **Semantic versioning + version constraints (semver 2.0, vMajor.Minor.Patch tags)**
  - When to use: every module release and version pin.
  - How: patch = safe bug fix, minor = new features without breaks, major = effort required. Registry protocol itself requires `vX.Y.Z` Git tags. For consuming modules, author Hafner's rule: support the widest range possible — floor at the lowest working version, allow everything except majors, expressed as the pessimistic constraint `~> 1.1`. Enforcing semver has no programmatic check — "it is up to developer teams to enforce this with culture."
- **Module delivery channels (SCM → registries → Artifactory)**
  - When to use: choosing how to distribute modules.
  - How: Git sources don't support the `version` field (only a pinned `?ref=`), forcing a tradeoff between random breakage and manual upgrade toil — fine for dev branches, wrong for scale. Public registries (OpenTofu registry, registry.terraform.io — both are indexes pointing at public GitHub repos) and private registries (watch SCM tags; Terrareg is the open source self-hosted option) take over quickly. Artifactory is the enterprise wildcard: it's push-based, not tag-watching, so publish via `jf tf p` in a tag-triggered workflow.
- **GitOps (CNCF's four principles)**
  - When to use: as the standard for centralized infrastructure delivery.
  - How: the desired state must be **Declarative**, **Versioned and immutable**, **Pulled automatically** by software agents, and **Continuously reconciled** (agents observe actual state and apply the desired state — "reconciliation continues to happen, not that it must be instantaneous"). Terraform is declarative, versioned/immutable state, and reconciles — but is not continuous by itself, so it needs an orchestrator to satisfy GitOps.
- **GitOps development workflow (5 steps)**
  - When to use: the daily loop for infra changes.
  - How: branch from Git → local development (spin up temporary feature environments) → PR with automated tests + speculative plan + review → merge to main → deploy from main; orchestrator then refreshes state and reconciles differences forever.
- **Deployment anatomy (code + variables + state → terraform apply → environment + new state)**
  - When to use: understanding why centralized deployment is required, not optional.
  - How: a deployment isn't an artifact — it's the whole infrastructure plus a new state version. Local applies to shared environments produce "local deployment chaos": state locking prevents concurrent runs but not two teammates overwriting each other's work.
- **CD triad of practices**: CI safety nets + fully automated deployments (no manual steps between start and end) + small deployments (three tiny deploys a day beat one weekly big bang — single-feature deploys make causes obvious).

## Key Concepts
- **Environment**: an isolated instance of the system. Kinds: feature (developer's own, launched and destroyed during development), staging (mostly for manual testing once automation covers CI), production, region-based (latency/legal), customer-isolated (each customer runs a different version on an upgrade schedule). Isolation means separate accounts, networks, subdomains, databases — and separate state and variables.
- **TACOS (Terraform Automation and Collaboration Software)**: colloquial umbrella for platforms bundling delivery, state management, and a private module registry.
- **Speculative plan**: a plan generated on a PR to show everyone what will change before merge — a baseline expectation of every CD platform.
- **Continuous reconciliation**: the GitOps requirement that drift (state vs SCM) is not just detected but brought back in line — Terraform detects via plan and corrects by applying, but only a continuously-running system makes it GitOps. Most teams enable detection without auto-correction, alerting via Slack instead.
- **OIDC (OpenID Connect)**: OAuth 2.0 based standard for machine-to-machine auth — "the best way to store a secret is to eliminate the need for the secret." Supported by every major cloud. Setup: register the platform's token URL as a provider (authentication — map the request to an identity), then grant that identity permissions (authorization — e.g., an AWS IAM role with conditions restricting assumption to specific repo and workflow; without conditions, *any* user of the IdP can assume your role).
- **Secret manager**: password manager for automated processes (AWS Secrets Manager, Azure Key Vault, HashiCorp Vault). Store the secret *path*, not the value; retrieve via data source; mark outputs `sensitive = true`. Caveat: values pulled into data sources still land in the state file.
- **Deployment requirements**: credentials/network access to platforms, tolerance for slow resources (a single database instance can take up to an hour), and consistency — never two concurrent deployments to the same environment (orchestrator job queuing).
- **Policy enforcement at deploy time**: module-scan policy (Checkov, ch7) fails once values come from input variables; deploy-time policy runs after variables resolve, which is why CD platforms standardized on OPA/Rego (HCP Terraform added OPA alongside its proprietary Sentinel in 2023).

## Mental Models
- Think of a deployment as "rebuilding a plane while it's flying": the systems being changed are in use, so Terraform's value is limiting changes to exactly what's needed while CD tooling supplies queuing, availability, and access.
- Treat Git as the source of truth and audit log: if the code that launched the running infrastructure isn't findable in a repo, you're not practicing GitOps.
- Use the "environment as root module" lens: a root module is just the entry point where variables and providers are configured — so make a thin per-environment wrapper instead of one shared root module.
- Rank secret handling in three tiers: eliminate (OIDC) → centralize (secret manager) → at minimum, orchestrator settings (write-only values; remember the 2021 Travis CI disclosure). At 500 projects, orchestrator-stored keys stop scaling.

## Anti-patterns
- **Deploying to shared environments from developer laptops**: state locking doesn't stop Alice and Bob from overwriting each other; centralize deployment from a single source of truth.
- **Application as root module for multiple environments** (`staging.tfvars`/`prod.tfvars` against one module): every environment shares the same infrastructure code, so you lose per-environment version control — code with no staged rollout goes to everyone.
- **Pulling reusable modules directly from Git default-branch or pinning every consumer to `?ref=`**: the former ships unreviewed breaking changes, the latter turns every bugfix upgrade into manual toil (teams going this route "rarely update their module versions").
- **Storing credentials in Git**: "even if you trust everyone on your team" — repo access outlives your control (clones, GitHub apps with code access).
- **Assuming OIDC provider registration grants access**: authentication (provider registration) is not authorization; an IAM role or service principal with restrictive conditions is the second, vendor-specific half.
- **Trusting cost estimates blindly**: estimation covers essentially only AWS/Azure/GCP, can't see third-party DNS/CDN spend, and can't predict consumption-based charges.
- **Co-locating your self-hosted CD system with the systems it manages**: if your deployment tool dies in the outage, you can't respond to the outage; isolate it by account, network, and ideally region.
- **HashiCorp resource-hour pricing as a given**: the resource-count x hourly-fee model charges per state entry (a best-practice 3-AZ VPC ≈ 72 resources ≈ $7.25/month per VPC) and is hard to justify.

## Code Examples
```hcl
# Environment as root module: production/main.tf (the recommended structure)
variable "logging_api_key" {
  sensitive = true # secrets arrive as variables, never live in SCM
}

module "application" {
  source  = "registry.example.com/example/aws/application"
  version = "1.1.1" # exact version, not a range: upgrades require a pull
                    # request against this environment

  network_name    = "prod_network" # environment-specific values are
  db_size         = 40             # hardcoded — this root module is
  num_tasks       = 10             # used by exactly one workspace

  logging_api_key = var.logging_api_key
}

output "application_url" {
  value = module.application.url # expose what other workspaces need
}
```
```yaml
# Tag-triggered publish (Artifactory or any push-based private registry)
name: Publish to Artifactory
on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+" # the Registry Protocol's required semver tags
jobs:
  artifactory:
    runs-on: ubuntu-latest
    permissions:
      id-token: write           # OIDC replaces stored credentials
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: jfrog/setup-jfrog-cli@v4
        with: { oidc-provider-name: github-action-workflow }
      - name: Publish Module
        run: make publish_artifactory TAG=${{ github.ref_name }}
```
- **What it demonstrates**: both halves of the chapter — pinned-version environment wrappers for deployment, and semver-tag-driven module publishing with OIDC instead of secrets.

## Reference Tables
CD platform feature matrix (table 8.3):

| System | Open source | State backend | Registry | Terraform only | Policy enforcement | Cost estimates |
|---|---|---|---|---|---|---|
| HCP Terraform | No | Yes | Yes | Yes | Sentinel and OPA | Yes (built in) |
| Spacelift | No | Yes | Yes | No | OPA | Infracost |
| Env0 | No | Yes | Yes | No | OPA | Infracost |
| Scalr | No | Yes | Yes | Yes | OPA | Infracost |
| Digger | Yes | No | No | Yes | OPA | No |
| Terrateam | No | No | No | Yes | Checkov and OPA | Infracost |
| Atlantis | Yes | No | No | Yes | None | No |
| Terrakube | Yes | Yes | Yes | Yes | OPA | Infracost |
| Harness | No | No | No | No | OPA | Infracost |
| Octopus Deploy | No | No | No | No | None | Infracost |

Notes that travel with the table: every commercial vendor except HCP Terraform switches to OpenTofu for v1.6+ and to OpenTofu only beyond that; Spacelift/Env0/Harness/Stable fund OpenTofu developers; Spacelift and Env0 additionally support Terragrunt, Helm, Ansible, CloudFormation, Pulumi; Scalr most faithfully mirrors the HCP Terraform CLI-driven workflow; Digger/Terrateam/Atlantis run GitOps-plus flows through PR comments (GitHub issues as UI).

## Worked Example
Project-structure decision for the three-tier web application (CDN + load balancer + static hosting bucket + container service + database + cache, each a reusable module called by one application module that wires outputs to inputs, with per-environment variables like `db_size`, `num_tasks`, `network`):

- **Option A — application as root module** (repo listing = module support files plus `staging.tfvars`, `production.tfvars`, `future.tfvars`): least extra work, and it's the module you develop with anyway — but all environments run the same code at different variable values. Any new feature or variable deploys everywhere at once; you cannot let staging soak a version, so staged rollout is impossible.
- **Option B — environment as root module**: `staging/main.tf`, `production/main.tf`, `future/main.tf`, each a thin wrapper containing a single module block pinned to an *exact* version with environment values hardcoded. Benefits: each environment upgrades on its own schedule through a PR (built-in audit trail), most input variables disappear (only sensitive values stay variables), no tfvars sprawl. Repository question: keep all environments of one application in one repo when one team owns them; split repos when different teams operate different installations.
- **Option C — Terragrunt**: replaces the wrapper module with a generated `terragrunt.hcl` pointing at `git::...?ref=v1.0.2`, mirrors the `terraform plan/apply` CLI so existing habits carry over, and adds `run-all` to drive many environments as one fleet. Constraint: Terragrunt doesn't honor version constraints — each environment names one exact version, which is a small manual step per upgrade and doubles as audit history.

Hafner's verdict: environment as root module (B) as the baseline; Terragrunt (C) when you're managing many environments and want fleet operations.

## Key Takeaways
1. Separate the CI stage (merge, tag, publish) from the CD stage (trigger deployment) — a CI system can technically deploy, but dedicated platforms add queuing, reconciliation, and access management.
2. Consume reusable modules through a registry with `~> 1.1`-style pessimistic constraints; use Git sources only for development branches and small teams.
3. Structure production as per-environment root-module wrappers pinning exact application versions — that is what makes independent upgrade schedules and staged rollouts possible.
4. Adopt GitOps via the CNCF four principles, and make sure reconciliation runs on a schedule, not only on PRs, or state drift slips through.
5. Eliminate secrets with OIDC wherever a platform supports it; fall back to a secret manager (watch for secret values leaking into state), and keep orchestrator settings as the last resort.
6. When comparing CD platforms, prefer the one supporting more IaC tools even if you don't need them today — one contract covering many tools beats per-tool licensing friction.
7. Prefer the CD ecosystem's common denominator for policy: write OPA/Rego policies rather than Sentinel ones.

## Connects To
- **Ch 7**: CD triad starts with the CI safety net ("automated deployments without CI is like driving without a seatbelt"); the makefile's `publish_artifactory` target plus tag-triggered workflows ship here.
- **Ch 9**: the same environment-wrapper modules are what the test suite validates, and semver majors collide with refactoring wishes.
- **Ch 6**: continuous reconciliation operationalizes the drift taxonomy from 6.6; state-file exposure of secret-manager values echoes state hygiene.
- **Ch 11**: Terragrunt, HCP Terraform, and versioning strategies reappear there; **CNCF GitOps principles** (opengitops.dev) and **semver.org** are the external standards.
