# Chapter 10: How to Use Terraform as a Team

## Core Idea
Getting value from Terraform as a team requires cultural and process change, not just a tool: adopt IaC incrementally with a concrete win to sell your boss, then run infrastructure code through a review/CI/CD workflow that mirrors the application-code workflow — with the Golden Rule that the live repo's main branch must be a 1:1 representation of what's actually deployed in production.

## Frameworks Introduced

### 1. Adopting IaC in Your Team (3 tips — When to use: moving a manually-managed team to IaC)
- **Convince your boss**: Don't sell features ("Terraform is declarative"); sell benefits, then — best — sell *problem solutions*. Ladder: features → benefits → problems. Listen for your boss's biggest pain (e.g., outages from manual deploy errors) and lead with "I have an idea for how to reduce our outages by half." Your goal is to prove IaC brings more value than anything else the team could work on in that time — not that IaC has value. Acknowledge the real costs: skills gap, new tools, change in mindset (direct SSH edits → indirect edit-code/review/automate), opportunity cost.
- **Work incrementally**: "False incrementalism" (steps with no value until the last step) is the failure mode; large migrations (CEO mandates "everything to cloud in 6 months") have failed every time. Each step must deliver standalone value, so a canceled project still leaves wins.
- **Give your team the time to learn**: If only one developer learns Terraform, the first outage sends everyone back to manual changes (faster for them), code drifts from reality, weird errors erode trust, and the codebase is abandoned ("gathering dust"). The bar: when the next outage happens, fixing it *in code* must be easier than fixing it by hand.

### 2. Application-Code Deployment Workflow (well-understood DevOps baseline)
When to use: as the reference model to translate each step into an infrastructure-code analog. How (7 steps):
1. Use version control (Git; work in a branch, e.g. `git checkout -b example-feature`)
2. Run the code locally (`ruby web-server.rb`; tests fully local)
3. Make code changes (optimize the change → test feedback loop; commit regularly)
4. Submit changes for review (pull request on GitHub)
5. Run automated tests (CI server — Jenkins, CircleCI, GitHub Actions — results show in the PR)
6. Merge and release (reviewers check bugs, guidelines, test coverage; then package an immutable, uniquely versioned artifact — Docker image tagged with commit ID or Git tag, e.g. `docker build -t brikis98/ruby-web-server:$commit_id .`)
7. Deploy (tooling, strategy, deploy server, promotion).

Deployment strategies (5 old copies → 5 new):
- **Rolling with replacement**: replace one at a time; never >5 copies; works on fixed capacity / stateful systems; capacity dips.
- **Rolling without replacement**: add one new, then remove one old; never <5 copies; needs flexible capacity.
- **Blue-green**: deploy all 5, pass health checks, shift all traffic at once, undeploy old; only one version user-visible.
- **Canary**: deploy one new copy, compare "canary" vs "control" (CPU, memory, latency, errors, HTTP codes); if identical, finish with a rolling strategy; if different, cancel. Combine with **feature toggles** (if-statement defaulting false; ramp 0% → employees → 1% → 10%…) to separate *deployment of code* from *release of features*.
- **Deployment server**: always deploy from a CI server, never a laptop — forces full automation, consistent environment, and better permissions management (CI server, not every developer, holds prod permissions).
- **Promotion across environments**: promote the *exact same* versioned artifact dev → staging → prod, testing in each; roll back by redeploying an older artifact.

### 3. Infrastructure-Code Deployment Workflow
Same 7 step names, different mechanics. Key differences per step:
- **Version control**: two repos — a *modules repo* (reusable, versioned, production-grade modules; an infra team builds the library, other teams consume it like a service catalog so Ops isn't a bottleneck) and a *live repo* (what's actually deployed where). Three extra requirements: live/modules split, the Golden Rule, and the branch problem.
- **The Golden Rule of Terraform** (exact): "The main branch of the live repository should be a 1:1 representation of what's actually deployed in production." — decomposed: (a) *what's actually deployed* → never make out-of-band changes (web UI, manual API calls); (b) *1:1 representation* → browsing the live repo must reveal every environment; so do **not** use workspaces for environments (one copy of code, 3–30 unseen deployments) — use separate folders/files per environment; (c) *main branch* → all production-affecting changes go into `main`; run `terraform apply` for prod only against main. Health check: pick random folders in the live repo, run `terraform plan` — "no changes" is healthy; occasional small diffs + excuses means drift; failing plans / gigantic diffs means the code is useless.
- **The trouble with branches** (exact rule): "For any shared environment (e.g., stage, prod), always deploy from a single branch." Terraform is a mapping from code to the one real world; state locking can't help. Example: Anna deploys `instance_type` t2.micro → t2.medium to staging on one branch; Bill, on another branch with stale t2.micro code plus a new tag, runs plan and sees `t2.medium -> t2.micro` — silently undoing Anna's change even weeks later.
- **Run locally**: there is no "localhost" for infra; use a sandbox environment (an AWS account for developers — or one per developer). Test by `terraform apply` + `curl <alb_dns_name>`; automated tests via `go test -v -timeout 30m` (Terratest) in a sandbox account. Tests are slow — use test stages to shorten the loop.
- **Apply golden rules**: "Always run plan before apply" (i.e., read the plan output — 30 seconds of scanning catches huge errors; Atlantis or Terraform Cloud/Enterprise auto-run plan on PRs as a comment) and "Always test Terraform changes in pre-prod before prod" (Terraform does NOT roll back on error — a failed deletion or termination is un-rollable).
- **Coding guidelines** to enforce in review (Dellamaggiore's clean-code test: a file written by 10 engineers should be indistinguishable): documentation (write the README first — Readme-Driven Development; comments only for *why*, never *what*; use `description` on variables; example code), automated tests (the key review question: "How did you test this?"), file layout (drives state layout and isolation, e.g. per-environment folders), style guide (consistency over taste; enforce with `terraform fmt` in a commit hook).
- **Merge and release**: Git tag is the version; "Since Terraform natively supports downloading code from Git, the repository at a specific tag is the immutable, versioned artifact you will be deploying."
- **Deploy tooling**: Terraform itself, Atlantis (plan on PRs + apply via PR comment, but no versioning), Terraform Cloud/Enterprise (web UI, variables, secrets, permissions), Terragrunt (DRY wrapper — see below), custom scripts.
- **Deployment strategies**: essentially none built in — only `terraform apply` works or it doesn't (exceptions like `asg-rolling-deploy`). No blue-green for a VPC change, no feature toggles for a DB. So error handling must be first-class: **retries** for transient errors (Terragrunt has built-in retries); **`errored.tfstate`** — if state can't be written to the backend (e.g., lost connectivity mid-apply), Terraform saves it locally; never let CI cleanup delete it — recover with `terraform state push errored.tfstate`; **`terraform force-unlock <LOCK_ID>`** for locks left by crashed CI runs (only when sure they're stale).
- **Promote artifacts across environments** (process, e.g. v0.0.6, credit to Kief Morris):
```
1. Update the dev environment to v0.0.6, and run terraform plan.
2. Prompt someone to review and approve the plan; e.g., send an automated message via Slack.
3. If the plan is approved, deploy v0.0.6 to dev by running terraform apply.
4. Run your manual and automated tests in dev.
5. If v0.0.6 works well in dev, repeat steps 1–4 to promote v0.0.6 to staging.
6. If v0.0.6 works well in staging, repeat steps 1–4 again to promote v0.0.6 to production.
```
The human plan-approval gate is infra-specific: app deploys are similar and low-risk; every infra deploy can be completely different and very costly (e.g., deleting a database).

### 4. CI-server security model for infra (admin-permissions problem)
The CI server needs *arbitrary* (admin) permissions to deploy arbitrary infra, but CI servers are hard to secure, accessible to all developers, and execute arbitrary code — permanent admin creds make it a high-value target. Mitigations: lock it down (HTTPS, auth, hardening, audit logging); don't expose it publicly (private subnets, VPN-only; poll VCS instead of webhooks); **enforce an approval workflow** (every deploy approved by at least one person other than the requester — reviewer sees code changes + plan output; two sets of eyes on everything); no permanent credentials (IAM roles, OIDC — Ch. 6); no admin credentials on the CI server — isolate them in a separate, locked-down **worker** that the CI can trigger only via an extremely limited remote API (specific commands like plan/apply, specific repos, specific branches like main).

### 5. Terragrunt for DRY multi-environment promotion
When: live repo has dozens of copy/pasted envs (provider config, backend config, inputs, outputs boilerplate per module). How: keep all Terraform code in the modules repo; the live repo holds only `terragrunt.hcl` files. Run `terragrunt plan/apply/output` instead of `terraform …`:
- Per module: `terraform { source = "github.com/<OWNER>/modules//data-stores/mysql?ref=v0.0.7" }` + `inputs = { db_name = "example_stage" … }` (secrets via `TF_VAR_*` env vars).
- Per environment root file: a `remote_state` block (backend `s3`, bucket/key/dynamodb_table, `encrypt = true`, `generate` backend.tf) with `key = "${path_relative_to_include()}/terraform.tfstate"`.
- Child files inherit via `include { path = find_in_parent_folders() }` — state keys auto-follow the live-repo folder structure.
- `dependency "mysql" { config_path = "../../data-stores/mysql" }` reads another module's outputs (`mysql_config = dependency.mysql.outputs`) — a less-coupled alternative to `terraform_remote_state` data sources (modules expose generic inputs like `vpc_id`, and don't need to know how siblings store state).
- Under the hood on apply: read the local terragrunt.hcl → pull in included parent config → download `source` into `.terragrunt-cache` → generate `backend.tf` → auto-run `init` (auto-creates the S3 bucket/DynamoDB table if missing) → run `apply`.

## Key Concepts
- **Live repo vs modules repo**: the live repo defines what's deployed per environment; the modules repo holds reusable, versioned, tested modules consumed by the live repo.
- **Golden Rule of Terraform**: main branch of the live repo ≡ what's actually deployed in prod (1:1, no out-of-band changes, no workspaces-for-envs).
- **Out-of-band change**: modifying deployed infra outside Terraform (UI/API/console) — the root cause of drift.
- **Immutable, versioned artifact**: unchanged, uniquely versioned unit you promote (Docker/AMI image for apps; the repo at a Git tag for Terraform).
- **Promotion**: deploying the exact same artifact version from dev → staging → prod rather than rebuilding per env.
- **Feature toggle**: if-statement wrapping new features (default off) to separate deployment of code from release of features; enables gradual ramp-up/rollback.
- **Canary / control**: one new copy compared live against an old copy to detect regressions before a full rollout.
- **Approval workflow**: a human other than the requester reviews code diff + plan output as the final gate before apply.
- **Terragrunt `dependency` block**: reads another Terragrunt module's outputs to pass as inputs, decoupling modules from each other's state layout.
- **errored.tfstate**: local state dump Terraform writes when the remote backend is unreachable after a failed apply; recover with `terraform state push`.

## Mental Models
- **Use the salesperson's ladder when your boss's problems don't obviously map to IaC**: features are least effective, better to "give superpowers," best to solve the boss's stated quarterly pain — and accept that not every team needs IaC (one-person Ops, throwaway prototypes, side projects: managing by hand is often right).
- **Use Terraform-as-mapping reasoning for branches**: Terraform code maps to *the one real world*, so multiple branches map to conflicting realities — deploy shared environments from a single branch; branches exist only to become PRs into main.
- **Use app-code vs infra-code table when defining your pipeline**: identical step names, different mechanics (localhost vs sandbox; artifact vs Git-tag; many strategies vs apply-only; auto-deploy vs plan-approval gate).
- **Use "boring is good" as the deployment goal**: routine, automated, repeatable deployments free the team to improve infrastructure rather than operate it by hand.

## Anti-patterns
- **Deploying infra code like app code (auto-deploy on merge, no plan review)**: app deploys are similar and low-risk; infra deploys are heterogeneous and irreversible — always require the plan-approval step.
- **Out-of-band changes** ("I tweaked that one thing by hand and forgot to update the code") — drift, weird plan errors, loss of trust, death spiral back to manual ops.
- **Terraform workspaces to manage environments** — live infra with no visible code; you can't see what's deployed by browsing the repo.
- **Branches for shared environments** — silent reversions of teammates' changes that state locking can't prevent.
- **Applying without reading the plan** — the rule exists because 30 seconds of reading catches enormous errors (destructive replacements, deletions).
- **CI server with permanent admin credentials** — turns every developer (and any attacker) into an admin; use temporary creds + isolated admin worker.
- **False incrementalism / big-bang migration** — value deferred to the last step; canceled projects return nothing.
- **Untrained team + unused Terraform code** — beautiful code that "gathers dust"; the first outage reverts everyone to manual changes.
- **Deleting errored.tfstate in CI cleanup** — unrecoverable state after a failed apply.
- **Inconsistent style** — enforce `terraform fmt` in a commit hook instead of debating taste.

## Code Examples
Golden Rule (verbatim):
> "The main branch of the live repository should be a 1:1 representation of what's actually deployed in production."

Terragrunt child config (verbatim pattern, `live/stage/data-stores/mysql/terragrunt.hcl`):
```hcl
terraform {
  source = "github.com/<OWNER>/modules//data-stores/mysql?ref=v0.0.7"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  db_name = "example_stage"
  # Set the username using the TF_VAR_db_username environment variable
  # Set the password using the TF_VAR_db_password environment variable
}
```
Terragrunt dependency (verbatim):
```hcl
dependency "mysql" {
  config_path = "../../data-stores/mysql"
}
# usage: mysql_config = dependency.mysql.outputs
```
Versioned release of Terraform code (verbatim):
```
$ git tag -a "v0.0.6" -m "Updated hello-world-example text"
$ git push --follow-tags
```
Error recovery (verbatim):
```
$ terraform state push errored.tfstate
$ terraform force-unlock <LOCK_ID>
```

## Reference Tables
Book's Table 10-1, condensed:

| Step | Application code | Infrastructure code |
|---|---|---|
| Version control | one repo per app; use branches | live + modules repos; don't use branches |
| Run locally | localhost (`ruby web-server.rb`) | sandbox env (`terraform apply`, `go test`) |
| Make changes | edit, rerun app + tests | edit, rerun `terraform apply` + `go test`; use test stages |
| Review | PR; enforce coding guidelines | PR; guidelines **+ plan output** (e.g., Atlantis comment) |
| Automated tests (CI) | unit / integration / e2e / static analysis | same **+ terraform plan** |
| Merge & release | git tag → immutable artifact (Docker/AMI) | git tag; the repo at that tag *is* the artifact |
| Deploy | Terraform, orchestration (K8s, ECS, Nomad, Mesos), scripts; many strategies (rolling, blue-green, canary); limited CI permissions; auto-deploy after merge | Terraform/Atlantis/TFC/TFE/Terragrunt; ~no strategies — plan error handling (retries, errored.tfstate, force-unlock); CI temp creds → locked-down admin worker; plan-approval gate, then auto-deploy |
| Promotion | same artifact dev→stage→prod | same artifact + per-env plan approval |

Deployment strategy selection (5 old copies → 5 new):
| Strategy | Never above/below 5? | Needs flexible capacity? | One version user-visible? |
|---|---|---|---|
| Rolling w/ replacement | never >5 | no (fixed capacity, stateful OK) | no (both versions live) |
| Rolling w/o replacement | never <5 | yes | no |
| Blue-green | never <5 | yes | yes |
| Canary | — | yes (one extra copy) | partial (canary gets live traffic) |

## Worked Example
Two-branch CI/CD pipeline for infra code v0.0.7, end to end:
1. **Modules repo change**: engineer edits `modules/data-stores/mysql/main.tf` and `modules/services/hello-world-app/main.tf` (add provider config for Terragrunt), commits, tags `v0.0.7`, `git push --follow-tags` → the repo at tag v0.0.7 is the immutable artifact.
2. **Live repo (staging)**: `live/stage/data-stores/mysql/terragrunt.hcl` points at `source = "...?ref=v0.0.7"` with `inputs` and `include { path = find_in_parent_folders() }` (root file's `remote_state` generates backend.tf, key = `data-stores/mysql/terraform.tfstate`). `terragrunt apply` → reads config, merges parent, downloads code to `.terragrunt-cache`, generates backend.tf, runs init (auto-creates S3/DynamoDB), applies: 5 added.
3. **Second module in staging**: `live/stage/services/hello-world-app/terragrunt.hcl` same source/ref + `dependency "mysql"` (`config_path = "../../data-stores/mysql"`) feeding `mysql_config = dependency.mysql.outputs`.
4. **PR flow while developing**: branch → sandbox apply → `go test` (Terratest, `-timeout 30m`) → PR; CI runs unit/integration/e2e/static analysis **and** `terraform plan` (or Atlantis posts plan to the PR); reviewers enforce guidelines (README-first, comments-for-why, file layout, `terraform fmt`); the key review question: "How did you test this?"
5. **Promotion to prod**: update `live/prod` terragrunt.hcl files (same ref v0.0.7) → `terraform plan` → automated Slack prompt → a human *other than the requester* reviews code + plan and approves → `terraform apply` against main → manual + automated tests → because staging already validated identical v0.0.7, prod risk is small. Rollback = re-apply an older tag. No auto-rollback exists, so everything was pre-validated in dev/stage first.

## Key Takeaways
- Sell IaC by solving your boss's biggest concrete problem, not by listing Terraform features; and adopt via quick wins that each standalone-deliver value.
- Budget real time for the whole team to learn — otherwise the first outage reverts the team to manual changes and the Terraform code dies.
- Live by the Golden Rule: main of the live repo is a 1:1 picture of prod; no out-of-band changes; per-environment folders, not workspaces.
- Never deploy shared environments from long-lived branches; branches exist only to become PRs into main.
- Always read `terraform plan` before `apply` (make it visible in PRs), and always test in pre-prod before prod — Terraform doesn't roll back.
- Run all applies from a CI server with temporary (IAM role/OIDC) credentials, with a plan-approval gate by someone other than the requester, and admin creds isolated in a locked-down worker.
- Promote the *same immutable versioned artifact* (the modules repo at a Git tag) across environments; use Terragrunt to keep the live repo DRY and to wire module outputs via dependency blocks.

## Connects To
- **Ch. 3 (state)**: backend locking — and why locking can't solve the branch-conflict problem; **Ch. 4 (modules)**: live-vs-modules repo split; **Ch. 5 (drift/refactoring)**: the out-of-band-change error budget.
- **Ch. 6 (secrets)**: why the CI server gets temporary credentials (IAM roles, OIDC); **Ch. 8 (production-grade modules)**: the module library's checklist (composable API, examples, tests, versioning) consumed like a service catalog; **Ch. 9 (testing)**: unit/integration/e2e/static analysis stages, `terraform plan` testing, sandbox accounts, test stages.
- Cross-book: the pipeline design credits Kief Morris (pipelines to manage environments with IaC); the Appendix recommends further reading — books (Morris, *Infrastructure as Code*; *The DevOps Handbook*; *Continuous Delivery*; *Site Reliability Engineering*; *Release It!*; Kleppmann, *Designing Data-Intensive Applications*), blogs (Martin Fowler, High Scalability, Code as Craft, Gruntwork), talks (Jez Humble's "Adopting Continuous Delivery," Flickr's "10+ Deploys Per Day," Rich Hickey's "The Language of the System," Brikman's Terraform module talks), and newsletters (DevOps Weekly, Terraform Weekly).