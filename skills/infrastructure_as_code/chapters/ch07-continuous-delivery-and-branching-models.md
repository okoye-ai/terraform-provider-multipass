# Chapter 7: Continuous delivery and branching models

## Core Idea
Automate change management by classifying each infrastructure change (standard, emergency, new/major), picking continuous integration/delivery/deployment accordingly, and standardizing how your team merges work through a branching model — so review is fast, batches stay small, and blast radius shrinks.

## Frameworks Introduced
- **Change management**: a process that facilitates a change to a system, detailing and reviewing the change across the company before approving it for production; uses ticketing, peer review, and a change advisory board as quality gates.
  - When to use: as the baseline you are trying to streamline with IaC and automation.
  - How: submit a change request with rollout/rollback steps; peers and the change advisory board act as quality gates verifying security and availability; schedule and apply.
- **Quality gates for IaC**: enforce a system's security, availability, and resiliency through review or tests.
  - When to use: as pipeline stages (automated tests) plus manual approvals.
- **Continuous integration (CI) for IaC**: regularly and frequently merging changes into your repository after verifying the change in a testing environment.
  - When to use: always — merge when you accumulate a few lines of change that (likely) will not break the system, several times a day; every merge triggers a build-tool workflow (check conflicts → unit tests → peer review → release).
- **Continuous delivery (CD) for IaC**: deploys the change to a testing environment for integration or end-to-end testing after merging, with a manual quality gate before releasing to production.
  - When to use: new or major changes; when the organization is not confident enough to auto-promote.
  - How: unit tests → deploy to testing environment → integration/E2E tests → peer review → release to production → rerun tests against production.
- **Continuous deployment for IaC**: deploys and tests in a testing environment and automatically promotes the change to production when tests pass.
  - When to use: standard and emergency changes; requires a thorough testing strategy and familiarity in fixing failures.
- **Standard change**: a commonly implemented change with well-defined behavior and a rollback plan (e.g., adding servers to a scaling group, upgrading container images, adding an alert). Auto-promote — a bypass commit-message prefix (e.g., `standard`) skips manual approval.
- **Emergency change**: a change you must quickly implement in production to fix system functionality. Continuously deploy an IaC fix tagged with an `emergency` commit-message bypass; never make the manual change by hand except under time pressure (then reconcile IaC to match).
- **New or major change**: potentially affects a system's architecture, security, or availability, with no well-defined implementation or rollback plans (network CIDR, DNS, certificates, orchestrator upgrades, platform refactoring). Requires ticket + manual peer review.
- **Branching model**: defines how your team uses version control to enable parallel work and resolve conflicts. Two types: **feature-based development** and **trunk-based development**.
- **Feature-based development** (feature branching / Git Flow): a branching pattern that separates changes into individual branches, merged to main after testing.
  - When to use: larger teams, many collaborators, changes needing isolation; teams familiar with version control.
  - How: branch named after ticket (TICKET-002) → commit → push → pull request → review → merge to main; give each branch its own temporary testing environment (or omit branch integration tests to save cost).
- **Trunk-based development** (pushing to main): a branching pattern pushing all changes directly to the main branch, favoring small changes verified in testing environments.
  - When to use: small teams comfortable with frequent small changes; reduces configuration drift between environments and states.
  - How: work on main → `git pull --rebase` → push → pipeline tests in a long-lived dedicated testing environment → manual review happens after the push → revert fast if broken.
- **Peer review**: teammates examine your configuration for recommendations, standards, and formatting — automate lint/format checks in tests, and reserve human review for dependent infrastructure and architectural impact.
- **Pair programming**: two programmers working together at one workstation; bakes review in during development and shares institutional knowledge.
- **GitOps**: an approach that uses declarative IaC to manage infrastructure changes through version control and continuously deploy them to production — a controller detects drift between actual state and the version-controlled configuration and runs the delivery pipeline.

## Key Concepts
- **Delivery pipeline**: expresses and automates a workflow to build, test, deploy, and release a change to infrastructure; codifies the release process so you don't have to remember it.
- **Pull request**: notifies repo maintainers that you have external changes you would like merged into the main configuration.
- **Branch**: a pointer to a snapshot of code, allowing you to separately implement changes based on that snapshot.
- **Manual approval batching**: waiting on manual approval accumulates changes into a large batch, which increases blast radius and makes root-cause troubleshooting of failures complex.
- **Change advisory board**: organizational review gate that decides which change applies first to minimize potential impact of failure.
- **Commit-message bypass**: a standardized prefix (`standard`, `emergency`) that lets the pipeline skip manual approval for pre-approved change classes, recording resolution history for audits.
- **Module emergency fix**: isolate a quick fix either by continuously deploying and releasing a new module version (preferred when other teams pin versions) or by branching the module repo and pointing configuration at the branch.
- **Authoritative binding**: defining the list of users for a role (e.g., `google_project_iam_binding` vs. `google_project_iam_member`), which revokes users not in the Terraform resource — a security standard to enforce in review.

## Mental Models
- Think of a delivery pipeline as the codified change-management process: every stage (unit test → testing deploy → integration/E2E → review → release) is a quality gate that used to be a meeting.
- Use "traffic jam" as the model for manual approval: delayed approvals batch changes, and one slowdown cascades; approve quickly and limit batch size.
- Think of trunk-based development as sequencing: changes land in an order, so a failure points at one commit, while feature branching trades that for isolation.
- Use "bake review into the code" when linting: turn teammate standards (indentation, group naming, binding resource) into unit tests so reviewers debate architecture, not formatting.

## Anti-patterns
- **Pushing large batches of changes to production**: manual-approval backlogs batch conflicting changes; troubleshooting which change broke the system takes days.
- **Long-lived feature branches**: stale branches accumulate unresolvable conflicts; eventually you delete the branch and restart on a fresh one; dependent changes block on unfinished branches.
- **Manual (hand-edited) emergency changes without reconciliation**: drift between IaC and actual state; if unavoidable, run IaC through the pipeline anyway and reconcile the configuration to match afterward.
- **Skipping automated tests before adding approval bypasses**: bypasses for standard/emergency changes require automated testing and a standardized commit-message structure first.
- **Nitpicking review only**: waiting days for a human to catch indentation and naming wastes the feedback loop; capture those unknown knowns as lint tests instead.
- **Adopting trunk-based development without a persistent testing environment**: without a dedicated environment mimicking production, pushes to main go unverified before review.

## Code Examples
Feature-based development workflow (TICKET-002 branch, firewall example):

```bash
$ git clone git@github.com:myorganization/firewall.git
$ git checkout -b TICKET-002
$ git commit -m "TICKET-002 Only allow traffic from database"
$ git push --set-upstream origin TICKET-002
# teammate later reconciles with changes already merged to main:
$ git checkout main && git pull --rebase
$ git checkout TICKET-005 && git merge main
```
- **What it demonstrates**: the branch-ticket-merge pattern, and reconciling an unfinished branch with main before it can deploy.

Unit tests enforcing team standards (peer-review feedback turned into linting, GCP IAM):

```python
def test_json_configuration_for_indentation(json):
    assert len(json[1]) - len(json[1].lstrip()) == 4, \
        "output JSON with indent of 4"

def test_user_configuration_for_standard_team_name(users):
    for _, member, _ in GCP_PROJECT_USERS:
        assert member.startswith('team-'), \
            "group should always start with `team-`"

def test_authoritative_project_iam_binding(binding):
    assert 'google_project_iam_binding' in binding.keys(), \
        "use `google_project_iam_binding` to add team members to roles"
```
- **What it demonstrates**: automating reviewer feedback (formatting, naming standards, authoritative bindings) so review time is spent on architecture, not style.

GitOps drift detection on a Kubernetes declarative config:

```yaml
spec:
  containers:
  - name: payments
  -  image: payments:v3.0
  +  image: payments:v3.2
```
- **What it demonstrates**: commit changes to version control; a controller detects drift between actual state and the declared configuration and runs the delivery pipeline.

## Reference Tables
Types of changes and delivery approach (Table 7.1):

| Type of change | Delivery approach | Manual approval before production? | Example |
|---|---|---|---|
| Standard | Continuous deployment | No | Adding servers to a scaling group |
| Emergency | Continuous deployment or manual change | No | Rolling back an operating system image to a previous version |
| Major | Continuous delivery | Yes | Enabling SSL for all services and infrastructure |
| New | Continuous delivery | Yes | Deploying a new type of infrastructure component |

Types of module changes and delivery approach (Table 7.2):

| Type of change | Delivery approach | Manual approval? | Example |
|---|---|---|---|
| Standard | Continuous deployment | No | Enabling an override for an existing default parameter |
| Emergency | Continuous deployment or branch | No | Rolling back an OS image to a previous version |
| Major | Continuous delivery | Yes | Updating a database or infrastructure using data |
| New | Continuous delivery | Yes | Deploying a new server module |

Comparison of branching models (Table 7.3):

| Development model | Benefits | Limitations |
|---|---|---|
| Feature-based | Isolates changes using branches; isolates tests using branches; organizes manual review of code; scales across multiple teams and collaborators | Requires diligence and familiarity with updating branches; encourages long-lived branches; increases cost in money and time |
| Trunk-based | Better representation of change behavior; one version control workflow for all changes; encourages incremental changes to reduce blast radius | Requires long-lived testing environment; does not include a stage for manual review; requires discipline to scale across teams |

## Worked Example
The firewall conflict: you must restrict firewall rules while a teammate refreshes its license — same resource, two changes. Under feature-based development, you branch TICKET-002, the teammate branches TICKET-005, each gets a temporary testing environment running unit/integration/E2E tests; you merge first, and the teammate must pull main, reconcile, and re-test before merging. Under trunk-based development, both push to main in sequence; a persistent testing environment runs the tests, the pipeline is the coordination source, and the first-push failure stops nothing else. The branch-model choice is decided by the team's comfort level, size, and environment setup — not ideology. A second worked example: peer review adds three days of delay for formatting/naming/binding feedback, so the author turns each piece of feedback into a pytest lint rule, shortening future review cycles to architectural discussion only (e.g., "add the user to the role or the role to the user?" goes to the team as a design question).

## Key Takeaways
1. Classify every change as standard, emergency, or new/major with your change review board; the classification decides the delivery approach and keeps you audit-compliant.
2. Prefer continuous deployment for standard and emergency changes (using standardized commit-message bypasses) and continuous delivery with manual approval for new/major changes.
3. Apply changes to production as frequently as possible no matter the branching model — small changes mean small blast radius.
4. Feature-based development buys isolation at the cost of branch hygiene and temporary environments; trunk-based development buys conflict visibility at the cost of a long-lived dedicated testing environment.
5. Automate formatting and standards as unit tests; reserve human review and pair programming for dependencies and architecture.
6. Always make emergency fixes through IaC and the pipeline so commits record resolution history; if you must change manually, reconcile IaC with reality.
7. GitOps combines declarative IaC, version control, and continuous deployment so anyone can propose changes via branch and commit while a controller keeps drift zero.

## Connects To
- **Ch 5**: module delivery pipelines and versioned releases; emergency module fixes via branches or new versions.
- **Ch 6**: the automated tests (unit, integration, end-to-end) that make CD and continuous deployment trustworthy quality gates.
- **Ch 10**: feature toggling as the complement to trunk-based development for gradual change rollout.
- **Ch 11**: fixing and reverting change failures — the prerequisite confidence for continuous deployment.
- **Change management (ITIL)**: the standard/emergency/normal change taxonomy mirrors ITIL change categories.
- **GitOps / OpenGitOps**: declarative reconciliation model (opengitops.dev); Kubernetes ecosystem tooling.