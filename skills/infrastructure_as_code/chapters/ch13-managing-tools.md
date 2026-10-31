# Chapter 13: Managing Tools

## Core Idea
Tools change, but patterns shouldn't: assess open source tools/modules on functionality, security, and life cycle before adoption; upgrade and replace tools by reusing the book's refactoring, blue-green, rolling-update, and roll-forward patterns — and extend to minimally scoped event-driven modules for dynamic workloads.

## Frameworks Introduced
- **Open source assessment** (three criteria, assessed in order — Figures 13.2–13.4; fail any gate and find or write your own module):
  1. **Functionality**: offers the attributes and default values you need? Opinionated defaults *and* input variables for what you must customize? Review documentation and commit history; check the module pins versions and tests compatibility.
  2. **Security** (the make-or-break gate): does it avoid exposing/outputting sensitive information (e.g., printing a password during dry runs — mitigate by masking/rotating)? Does it avoid sending information to third-party endpoints (a bad actor can hide data exfiltration in minor config)? Does it pass your existing security and compliance tests? Run those tests against the module in an isolated testing environment — defends against software supply-chain attacks.
  3. **Life cycle**: reliable maintainers or company sponsorship? Appropriate open source license approved by legal? If maintainers stop, can you maintain it yourself? Then **pin its version** and, if possible, mirror it into an internal artifact registry so teams use only approved copies.
- **Pre-upgrade checklist** (Figure 13.5) before any tool/plugin upgrade:
  1. Decouple infrastructure dependencies with dependency injection.
  2. Check that all modules have versioning.
  3. Pin module versions across repositories (a team on "latest" will get hit by your next breaking release).
  4. Pin the tool and its plugin versions.
  5. Run the tool and confirm version pinning introduces no new changes (no drift) — then plan the upgrade path through backward-compatible versions (1.7 → 3.0 → 4.0), never more than two versions at a time, testing in a testing environment first.
- **Backward-compatible upgrade workflow** (Figure 13.7): refactor high-level resources (DNS, load balancers) mutably/in place first to validate the process → test → upgrade low-level resources with rolling updates (servers) or blue-green deployment (high-risk low-level resources like networks) → test → finally refactor to new features of the new version.
- **Blue-green deployment for tool state**: a pattern that creates a new subset of infrastructure resources with a new tool version in a separate tool state, gradually shifting traffic from old (blue) to new (green) — isolating breaking changes to the new subset.
  - When to use: upgrades with **breaking changes** (e.g., backend schema changes in version 4.0) or tool replacement without import capability.
  - How: pin versions → update modules and release a new module version noting the breaking change → copy low-level resource configuration to a new folder/repository/branch (creating *new tool state*) → create new low-level resources with tool 4.0 → test → copy high-level resources depending on the new low-level ones → cut over traffic (new tool state becomes source of truth) → remove old resources on 3.0.
- **Tool replacement patterns** (Figures 13.11–13.12), by import capability:
  - **New tool supports import**: write new-DSL configuration for low-level resources in a separate folder/branch → import existing resources into the new tool state → dry run to catch default mismatches → rewrite tests → repeat for high-level resources → remove old tool configuration. No resources recreated.
  - **No import capability**: apply blue-green deployment for tool state — recreate low-level then high-level resources with the new tool, test, cut over traffic, delete old configuration. Same pattern, more effort.
- **Event-driven IaC**: running a minimally scoped infrastructure module to configure infrastructure in response to an event (e.g., a new application instance's IP updates a firewall rule via a script/operator/serverless function/event-queue consumer).
  - Keep the module tiny and fast: avoid long-to-create resources; don't pack many resources into one module; add a cool-down interval between runs; balance module runtime against event frequency (batch if events fire faster than deploys).
  - Relation to GitOps: GitOps (declarative config, drift detection, version control, continuous deployment) is a **subset** of event-driven IaC — its trigger is drift; event-driven IaC covers a broader set of events.

## Key Concepts
- **Tool state**: the copy of infrastructure state an IaC tool maintains to detect drift and track managed resources — distinct from the actual infrastructure state; separate it from the new state during upgrades to shrink blast radius.
- **Permissive open source license** (e.g., MIT): fork or modify code as long as you include a copy of the license and original copyright notice — lets you self-maintain the module if it's deprecated.
- **Copyleft open source license**: fork or modify only if you *release your modified codebase* open source — more restrictions; legal must vet usage.
- **Software supply-chain attack**: malicious code included in vendor software shipped to customers; open source lets you inspect code before adopting, but requires reviewing resources for third-party endpoints.
- **Module pinning**: constraining consumers to a fixed module version so a breaking release cannot cascade automatically.
- **Mirror to internal artifact registry**: copying an approved open source module internally so usage survives public-endpoint outages and stays auditable.
- **Upgrade path planning**: stepping through intermediate backward-compatible versions (e.g., 1.7 → 3.0 → 4.0) instead of jumping to latest.
- **In-place upgrade**: updating resources mutably to the new version when it's backward-compatible — acceptable for high-level resources after dry-run testing.
- **Break-glass-free upgrades**: upgrading a tool changes infrastructure, so change techniques (rolling updates, blue-green, roll-forward) apply unchanged.

## Mental Models
- **Use a tool version like a module version**: pin it, upgrade in steps of at most two versions, and never go straight to latest.
- Think of a breaking tool upgrade as **a blue-green deployment of the tool state**: new version, new state, new resources — traffic moves only after tests pass.
- **Reuse the whole book for tool change**: refactoring (ch 10) splits resources during upgrades; rolling updates shrink server-upgrade blast radius; roll-forward (ch 11) recovers a botched upgrade; blue-green (ch 9) protects high-risk low-level resources.
- Think of test suites as two tiers during a tool swap: **unit and contract tests must be rewritten** (new state/metadata format — parsers read the wrong fields); **integration, end-to-end, and manual tests survive** because they test infrastructure function, not the tool.
- Prefer an **in-place upgrade when the vendor ships a migration script**; when in doubt, fall back to new-state blue-green.

## Anti-patterns
- **Jumping two or more major versions straight to latest**: breaking changes in behavior and syntax stack up unmanageably; step through compatible intermediates.
- **Skipping the pre-upgrade checklist (unpinned modules/plugins, coupled dependencies)**: a "latest"-version team gets upgraded by accident; injected fields break subsets.
- **Adopting a module that dumps secrets during dry runs or phones home to a third-party endpoint**: security assessment is the make-or-break gate; run it in isolation.
- **Forking a module and maintaining it silently forever**: reconciling your fork with upstream is heavy operational overhead — contribute changes upstream where legal allows.
- **Upgrading state in place with breaking changes**: the failure blast radius spans your whole configuration; isolate old and new tool states.
- **Forgetting to rewrite unit/contract tests after a tool swap**: stale tests parse the wrong fields and pass or fail vacuously.
- **Event-driven modules that provision slow or numerous resources**: module run time must beat event frequency, or you accumulate a backlog — keep the subset minimal and cool down between runs.
- **Complex IaC logic (e.g., heavy inline scripting)**: it's what breaks during upgrades; keep the complexity of IaC logic low since no migration tool handles it perfectly.

## Code Examples
```python
# Event-driven IaC: script reacts to a new application instance's
# IP address and runs a minimal module to update the firewall rule.
#   1. Application deploys to a new server with a new IP address.
#   2. Script passes the new IP address to IaC and deploys the change.
#   3. IaC updates the firewall: ip_addresses = ["10.0.1.7/32"]
#   4. Re-run for each deploy, with a cool-down interval between runs.
```
- **What it demonstrates**: event-driven IaC — one minimally scoped module (a firewall rule) triggered by a deployment event, refreshed only when the system changes.

The chapter's other figures are workflows rather than code; its executable patterns (import automation, state removal wrappers, blue-green folders) are the ch 10 listings reused verbatim.

## Reference Tables
| Scenario | Pattern | Key property |
|---|---|---|
| Upgrade, backward compatible | In-place, high-level → low-level, rolling updates for servers | Mutations are safe after dry-run testing |
| Upgrade, breaking changes | Blue-green deployment **for tool state** (low-level then high-level in new state) | Breaking changes isolated to green subset |
| Replace tool, import supported | Write new config → import existing resources → rewrite tests | No resources recreated |
| Replace tool, no import | Blue-green recreation of low- then high-level resources | Costlier: system fully re-created |
| Dynamic event response | Event-driven IaC (minimal module, cool-down) | Run time must outpace event frequency |

Test suites during a tool upgrade or replacement:

| Test type | Refactor needed? | Why |
|---|---|---|
| Unit tests | Yes | Parse tool state/metadata; new tool uses different format |
| Contract tests | Yes | Module interfaces and parsed fields change |
| Integration tests | Mostly no (input parameters may change) | Tests infrastructure function, not the tool |
| End-to-end tests | Mostly no (input parameters may change) | Tests system functionality |
| Manual tests | Mostly no | Verify running system behavior |

## Worked Example
A social media company audits its IaC: most tooling sits on version 1.7 while 4.0 is current. **Adopting a module first**: the feed team evaluates a database module — functionality gate (opinionated, pinned database version; settable name/tags/network), security gate (no password output, no third-party endpoints, passes their ch-8 compliance tests in isolation), life-cycle gate (maintained by a known company, MIT license cleared by legal). They pin the version and mirror it internally. **Upgrade 1.7 → 3.0** (backward compatible): run the pre-upgrade checklist (dependency injection, module versioning, pinned tool/plugins, confirming no drift), then refactor high-level DNS and load balancers in place — clean dry run and passing tests — then servers via **rolling updates**; one server's override script breaks under 3.0, but the rolling update confines the failure to one server, which they roll forward with a fixed script. **Upgrade 3.0 → 4.0** (breaking backend schema changes): the team applies **blue-green deployment for tool state** — copying network configuration into a new folder to get a new state, building "green" resources with 4.0, re-pointing high-level resources at them, testing, cutting over traffic, and removing the 3.0 "blue" resources. Throughout, unit and contract tests are rewritten while end-to-end tests survive untouched.

## Key Takeaways
1. Vet every open source tool or module through three gates in order — functionality, security, life cycle — and pin plus mirror what you approve.
2. Treat security assessment as the make-or-break gate: no secret output, no third-party data flows, and your compliance tests passing in isolation.
3. Before any upgrade, decouple dependencies with dependency injection and pin module, tool, and plugin versions everywhere.
4. Upgrade at most two versions at a time through backward-compatible steps, always rehearsing in testing first.
5. Match the pattern to the change: in-place for compatible high-level resources, rolling updates for compute, blue-green for risky low-level resources, and blue-green *tool state* for breaking changes.
6. When replacing tools, choose import-based migration when available; otherwise recreate with blue-green tool state — and rewrite unit/contract tests either way.
7. For dynamic workloads, use event-driven IaC with minimally scoped, fast modules and a cool-down between runs.

## Connects To
- **Ch 10 (refactoring workflow)**: the same copy → import → separate-state → remove cycle splits tool states and swaps resources during upgrades.
- **Ch 9 (change techniques)**: blue-green and canary deployments reused for resource and tool-state cutovers.
- **Ch 11 (roll-forward)**: the recovery path when an upgrade fails mid-flight.
- **Ch 5 (module versioning, repository structure)**: pinning and separate folders/branches/repositories are prerequisites for safe upgrades.
- **Ch 7 (branching models, delivery pipelines, GitOps)**: how you isolate a new tool state (branch vs. new repository) depends on your branching/deployment model; GitOps is a subset of event-driven IaC.
- **Ch 8 (security and compliance tests)**: the security gate runs these against candidate modules.
- **NIST supply-chain guidance (SP 800-161) / Open Source Initiative licenses**: external references for deeper risk assessment and license categories.