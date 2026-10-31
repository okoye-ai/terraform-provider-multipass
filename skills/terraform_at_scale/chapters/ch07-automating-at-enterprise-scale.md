# Chapter 7: Automating at Enterprise Scale

## Core Idea
Scaling Terraform/OpenTofu beyond a single project means layering automation capabilities deliberately — from shell scripts, to containers, to an automation platform, to pipeline triggering, ephemeral environments, self-service infrastructure, and finally supervised AI agents. A best-of-class platform does not skip to the advanced features: it takes a patient, deliberate approach, ensuring each phase reaches sufficient **stability, saturation, and accessibility** before moving to the next. Assume your organization maintains multiple root modules with logical/operational/compliance boundaries and interdependencies; the most common blunder in IaC is **failing to recognize when a traditional pattern no longer serves its purpose or scales effectively**. No single automation platform has all features, but on a long enough timeline all will have most of them or analogues — focus on the capability, not the platform.

## Frameworks Introduced
- **Three-tier practice maturity ladder** (partially ordered):
  1. *Low effort, high value*: shell scripts → containerized steps → custom containers → automation platform (the baseline layer everything else sits on).
  2. *Highly effective, primary platform*: triggering other pipelines (reusable subprocesses), AI-generated recommendations, migrating bash to Python/Go/JS (for unit testing), platform visibility (monitoring/alerting/auditing), webhooks, temporary access controls.
  3. *Most advanced*: simplified self-service (form-based ticketing + webhooks), AI chatbot interface, supervised TF code generation (PR-opening assistants — never unsupervised updates on critical infrastructure).
- **Two mandatory platform features**: (1) **access control** — RBAC at minimum, with ABAC layered on top via tools issuing temporary credentials that map to static RBAC roles for the credential's lifespan; (2) **a DSL** — pipelines as code in Git, reviewable like app code, ideally supporting composable procedures (DRY).
- **Escape-the-lock-in ladder**: extract shell command sequences into a single script → embed the script in a container image (`ENTRYPOINT`) → migrate the image as-is to any container-supporting platform. Containers insulate execution via Linux namespaces (isolated resources per process group) and cgroups (hierarchical process groups).
- **Entry-point specificity spectrum**: generic shell-reading-input (flexible, good for exploration) ↔ structured entrypoint script built from input elements (strict guardrails, auditability, replayable system logs).
- **Dependency tracking cost-benefit rule**: automate when the recurring operational cost (especially when the problem becomes a single senior engineer's de facto responsibility) exceeds the one-time development cost; otherwise at least document dependencies (digital spreadsheet now, relational database as a stepping stone to automated tracking).
- **Definition of Done / diminishing returns framing**: each phase has its own scope and Diminishing returns as comprehensive solutions chase corner cases; regular stakeholder reviews are needed near saturation. Start the next phase after dust settles but before experience becomes distant memory.

## Key Concepts
- **GHA vs GitLab scope asymmetry**: in GHA an *action* packages scripts, a *step* configures an action, a *job* groups steps, a *workflow* runs jobs in parallel; in GitLab a *job* encodes a script, grouped by *stage* (stages run in parallel), a *pipeline* runs stages sequentially. Parallelism happens at different scopes, making replatforming tedious — sometimes a full rearchitecture. (GHA→GitLab transcription is easy for an LLM; GitLab→GHA is harder because sequential-by-default stages invert the model.)
- **Wildcard jobs**: flexible command-execution jobs operating with the platform's service identity — run ad hoc protected operations (e.g., state manipulation). Expose limited commands/args as form fields with sensible defaults; run in a restricted software context. Never grant anyone persistent access — use temporary, case-by-case identity governance with approval; generate a stakeholder report per use and review usage in cadence meetings. Only possible on general-purpose platforms (GHA/GitLab), not TFE/HCP Terraform — run them on a separate platform there. Each fit-to-purpose wildcard job gets unique policies.
- **Container mental model**: template (entrypoint command) + identity (like a Linux user) + filesystem fragment + dedicated compute slice. Not VMs — they share the host kernel and needn't be virtualized.
- **Pub/sub between pipelines**: an apply operation publishes module outputs to a topic (e.g., Kafka); downstream pipelines subscribe. Gives reviewable and replayable auditability.
- **Domino effect**: upstream updates cascade sequentially into downstream projects (upstream apply must fully complete first). Automation doesn't beat a manual run on end-to-end time; it eliminates typos, forgotten/out-of-order steps, and other consistency failures. Information that can't be detected (e.g., region migration) must flow via upstream output values interpreted as downstream inputs.
- **State of states**: a higher-order registry of all TF projects and their versions — tagged Git commits of known-stable configurations linked into the tracking system. Enables fine-grained org-wide versioning, audit exercises (length of exposure, cost attribution, change impact), and ties otherwise-anonymous action logs to authored commits. Tagged versions have a **shelf life**: only the immediately previous stable version is potentially valid; older ones are audit trail only.
- **Roll forward, not rollback**: destroy and recreate defective components rather than remediating in place; optionally cordon the defective component while its replacement comes up and the flaw is investigated. Catch most defects pre-deployment via blue/green or canary deployments.
- **Self-service as decoupling**: customers request infra through a form/API instead of negotiating with engineers; engineers build reusable capabilities and treat customer input as feature requests. Follows the single responsibility principle — each layer (automation platform → self-contained process/interface → TF CLI → provider APIs) has one role. Drive it with outbound callbacks (jobs exposed as HTTP endpoints with query-parameter inputs) and webhooks into SaaS.
- **Visibility prerequisites for self-service**: monitoring dashboards (role-tailored, baseline + extensible), continuously validated alerts (alert noise is worse than no alerts — it manufactures a false sense of security; alert recipients must influence content/differentiation/sensitivity), and gated audit tools (deeper purview ⇒ stronger, temporary, approval-gated access). Staff it like the mission-critical application it is — two-pizza teams per shift/region, redundancy to prevent burnout.
- **Exceptions process**: support ~80% of teams/workloads as standard (Pareto Principle); track everything custom as exceptions with explicit policy overrides and elevated oversight; regularly evaluate exceptions across all workloads — common ones become new standards, giving you the evidence to prioritize the feature.
- **Autonomous IaC limits**: LLMs recreate what they've seen (Conway's Law — training data can't know your informal communication channels); emergent results are "hallucinations" and rarely valuable outside art. Garbage in, garbage out: an agent asked to extend a poorly architected solution leans into its bad conventions; training on forum answers and tutorial code can't negotiate contradictory org policies. Mitigate with system prompts encoding standards/guardrails, and by asking the model to raise clarifying questions. Keep a human "responsible party with a pulse" accountable for decisions — reduce the experience to a simple approval process.
- **Anonymous LLM usage**: prompt with placeholder values for sensitive fields instead of exposing IP; still disable training on prompt history because LLMs infer across "irrelevant" details. Print seed/temperature and the model's confidence alongside responses as trustworthiness evidence.
- **"Vibe code your applications, not your infrastructure."**

## Mental Models
- **Livestock, not pets**: resources are immutable and disposable. Livestock is numerous, undistinguished, expendable; pets are few, named, special. Consequences: looser naming, richer metadata, replacement over remediation, region/chipset/OS freedom, and "deleting cloud resources is and should be painless, casual, and ordinary." Expect leadership friction ("What do you mean you aren't going to fix prod?") and counter it with efficiency estimates until upgrades are indistinguishable from feature deployments.
- **Antifragility through ephemerality**: full self-contained copies built and torn down at will; teardown must be performant (never a bottleneck) and every new environment must be *totally unique* (roll-forward environment construction) — never recreate. Tag each resource with its expiry; enforce fixed durations or collective policies (e.g., weekly teardown) with governed extension.
- **Estimation heuristic**: best-faith assessment, doubled, then doubled again — padding for unknown unknowns, external delays, holidays, bureaucracy, and escalating stakeholder check-ins; also hedges budget/scope negotiations.
- **Emergent thought**: real epiphanies come from imagination, not accumulated knowledge; a hallucination that recognizes a pattern among disparate concepts *could* theoretically approximate imagination — but we lack a framework for evaluating imagination, so AGI verification would lag AGI itself.
- **Access-granularity guidance**: cover roles and tasks and combine them per member, rather than team-specific grant suites — the former scales, exposes overlaps, and expresses intentional responsibility similarities. Same logic for workflow decomposition: stop extracting subpipelines once significant repetition is gone; don't extract single steps appearing in only a couple of instances (especially with solid code review).

## Anti-patterns
- **Reacting to dependency problems instead of tracking them** ("the worst way"): the split of one project into two forgets dependencies; they surface as unwelcome surprises and settle into undocumented ritual. Fails because it converts a one-time automation cost into a recurring operational tax.
- **Running workstation shell scripts verbatim on an automation platform** ("unforeseen implications"): a script tuned to an engineer's machine may fail in the platform's shell. Prefer containerized execution.
- **Long inline command sequences in pipeline YAML**: vendor-coupled and typo-prone; extract into a single-line-callable script (and then a container image) for portability.
- **Ignoring lock-in scoping differences**: functionally analogous platforms scope contexts and operations differently (GHA parallel jobs vs GitLab sequential stages); ignoring this makes replatforming a rearchitecture.
- **Alert noise**: so many indiscernible alerts that engineers ignore or miss critical ones — worse than no alerts, because it lures you into false security.
- **Recreating ephemeral environments**: violates the roll-forward environment principle; each environment should be unique, rebuilt rather than reused.
- **Treating self-service as a silver bullet** or expecting it to make DevOps trivial. Don't lay off infrastructure/operations teams on adopting autonomous IaC — retrain and reposition them as **custodians and curators** of provisioning assets.
- **Ad hoc completion reviews**: stakeholders ambushing teams in cadence meetings or "impromptu grilling sessions"; terms of engagement and contingencies must be set before the effort starts.
- **Vibe-coding infrastructure**: guardrails don't magically exist; if you build the environment, you own establishing them.
- **Perpetual wildcard-job access**: this job in the wrong hands is catastrophic; permanent grants are unacceptable.
- **Chasing 100% coverage**: supporting all remaining assets dominates the timespan; "south of 100%" is usually the satisfactory level.

## Code Examples
**Example 7-2 — extracting command sequences into a script (lock-in mitigation, step 1):**
```yaml
# Before
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: hashicorp/terraform:latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Install dependencies
        run: terraform init
      - name: Run tests
        run: terraform test
      - name: Construct plan file
        run: terraform plan -out=plan.tfplan

# After
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: hashicorp/terraform:latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Prepare infrastructure
        run: ./prepare.sh
```
**What it demonstrates**: packaging operations at the lowest possible level (a single script invocation) so the pipeline stays vendor-agnostic and the real logic lives portably in source control.

**Example 7-4 — environment-variable-driven container entrypoint (structured, guarded execution):**
```bash
#!/usr/bin/env bash
set -euo pipefail

JOB_ENV="${JOB_ENV:-dev}"
MAKE_PUBLIC="${MAKE_PUBLIC:-false}"

case "$JOB_ENV" in
  dev)
    export TF_VAR_environment="dev"
    export TF_VAR_network_tier="internal"
    ;;
  prod)
    export TF_VAR_environment="prod"
    export TF_VAR_network_tier="restricted"
    ;;
  *)
    echo "ERROR: Unknown JOB_ENV '$JOB_ENV'"
    exit 1
    ;;
esac

if [[ "$MAKE_PUBLIC" == "true" ]]; then
  export TF_VAR_enable_public_networking="true"
else
  export TF_VAR_enable_public_networking="false"
fi

terraform init
terraform apply -auto-approve
```
(Passed into the job via the workflow's `env:` block: `JOB_ENV: "dev"`, `MAKE_PUBLIC: "false"`.)
**What it demonstrates**: the more-specific end of the entry-point spectrum — guardrails steer users into valid configurations, unknown values fail fast, and env-to-TF_VAR mapping lives outside TF itself.

**Example 7-5 — cascading pipelines via GitLab's `trigger` keyword:**
```yaml
# parent.yml
plan_infra:
  stage: build
  image: hashicorp/terraform:latest
  script:
    - terraform init
    - terraform plan -out=plan.tfplan
  artifacts:
    paths:
      - plan.tfplan
    expire_in: 1 hour

trigger_apply:
  stage: deploy
  trigger:
    project: platform/deploy-pipeline
    branch: main
    strategy: depend
  variables:
    PARENT_ID: $CI_PIPELINE_ID

# child.yml
apply_infra:
  stage: deploy
  image: hashicorp/terraform:latest
  script:
    - terraform apply plan.tfplan
  needs:
    - pipeline: "$PARENT_ID"
      job: plan_infra
```
**What it demonstrates**: the domino-effect pattern — an upstream pipeline passes artifacts and context (parent pipeline ID) into a downstream pipeline that runs only after the upstream completes.

## Reference Tables
**Chapter's "Successful Practices" ladder (the author's own summary):**

| Tier | Practices |
|---|---|
| Low effort, high value | Shell scripts; containerized steps; custom containers; automation platform (choose one with native containers, job triggers, webhooks, RBAC, Git-stored DSL) |
| Highly effective, primary platform | Triggering other pipelines; AI-generated recommendations; programming language (bash → Python/Go/JS for unit tests); platform visibility; webhooks; temporary access controls |
| Most advanced | Simplified self-service (form-based ticketing + webhooks); AI chatbot interface; supervised TF code generation |

**Platform scope comparison (Example 7-1 context):**

| | GHA | GitLab |
|---|---|---|
| Parallel unit | Jobs within a workflow | Stages within a pipeline |
| Sequential unit | Job-internal steps (`needs:` for ordering) | Stage sequence |
| Reusable unit | Action / reusable workflow | Job in a triggered project |

## Worked Example
The chapter's connective arc — hardening a `build` job against lock-in: Start with raw steps in GHA YAML (`terraform init`, `terraform test`, `terraform plan -out=plan.tfplan` on `hashicorp/terraform:latest`). Collapse them into `./prepare.sh` (Example 7-2) so the workflow contains one invocation. Then embed `prepare.sh` in a Dockerfile (Example 7-3): `FROM ubuntu:22.04`, `ENV DEBIAN_FRONTEND=noninteractive`, install `ca-certificates git bash`, `COPY prepare.sh /usr/local/bin/prepare.sh`, `chmod +x`, `ENTRYPOINT ["/usr/local/bin/prepare.sh"]`. Reference the image from GHA's `container:` block — the operation now migrates as-is to any container-capable platform, and platform-specific behavior can't leak in because the image fully specifies binaries, libraries, and processes. Finally, parameterize it: the workflow passes `JOB_ENV`/`MAKE_PUBLIC` env vars into `entrypoint.sh`, which fails fast on unknown environments and exports `TF_VAR_*` values (`network_tier=internal` for dev, `restricted` for prod) before `terraform init && terraform apply -auto-approve`. This is the base tier of the practice ladder; everything later — pipeline triggering, self-service, AI agents — layers on top.

## Key Takeaways
- Pick an automation platform by matching capabilities to your existing processes; accept that platform choice, budget pressure, and lock-in are real, and neutralize what you can with low-level, containerized operations.
- Two features are non-negotiable in a platform: access control (RBAC, ABAC layered via temporary credentials) and a DSL (pipelines as reviewable, versioned code).
- Replace, don't remediate: livestock-not-pets plus the roll-forward approach turn failures into routine replacement events.
- Track interproject dependencies deliberately (spreadsheet → relational database → automated triggers), and automate the domino-effect cascade once the cost-benefit analysis favors it.
- Maintain a **state of states**: tagged Git commits of stable configurations linked to pipeline-run records; treat all but the previous stable version as audit trail only.
- Use ephemeral environments for sandbox experimentation, load/chaos testing, and blue/green + canary production swaps; make teardown performant, expiration mandatory, and every environment unique.
- Self-service infrastructure converts negotiation into feature requests — build visibility (dashboards, tuned alerts, gated audit tools) *first*, then staff it as mission-critical.
- Target ~80% standard coverage (Pareto); track the rest as governed exceptions and promote recurring ones into standards.
- Supervised agents can read self-service requests and provision predesigned stacks, but humans remain accountable custodians; never unsupervised updates on critical services.
- Each phase is finished at its own definition of done, not 100% — plan for diminishing returns and start the next phase while experience is still fresh.

## Connects To
- **Ch. 6**: wildcard jobs were first recommended there for protected ad hoc state manipulation.
- **Ch. 3**: driving TF projects from application code (marshaling module inputs/outputs outside the module) reappears as the unit-tested programming-language tier.
- **Ch. 8**: decomposing a project for enterprise scale — signs a project has outgrown a single repository/module.
- **Ch. 10**: validation, troubleshooting, and remediation techniques — the skip-ahead target if you're small-scale or own only one slice of the ecosystem.