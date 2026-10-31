# Chapter 12: Last Thoughts

## Core Idea
TF at scale is "a never-ending journey and not a destination." The book's best practices are heuristic, at best — they won't fit every situation forever. Use this chapter when a company adopts new CSP features, resells services as a line of business, moves to a multi-CSP ecosystem, or faces a merger/acquisition or a volumetric (volume-based) contract decision — the latter is seemingly arbitrary but common and often good business sense due to significant discounts.

The goal state is not a predefined success criterion; it is a **local equilibrium**: a state of low friction, total coverage, and quick responses to unforeseen incidents, all without exceeding a forecasted budget.

Closing mental frame: "every company is now a software company" (Satya Nadella). Enterprises differ mostly in *scale*, not capability — more components, more products, and more lines of business mean a more complex management structure, which (per Conway's Law) directly shapes your infrastructure needs.

## Frameworks Introduced

### Local Equilibrium
Replace "reach a defined end state" with "reach an equilibrium you can hold": low friction + total coverage + fast incident response + inside forecasted budget. Re-test it whenever new CSP features, new lines of business, or M&A/contract changes arrive.

### Minimum Viable Infrastructure (MVI)
Direct adaptation of Eric Ries' MVP ("that version of the product that enables [iterative learning through a] feedback loop with a minimum amount of effort and the least amount of development time") to IaC. An MVI must be:
1. **Usable** by end users — for infrastructure that means your application teams (or data analysis teams).
2. **Developed as quickly as possible.**
3. **Manages the fewest resources to be usable.**
4. **Includes a feedback mechanism** — from the system (logs, metrics) and from users (bug reports/feature requests).

Other published MVI definitions mostly drop the iterative learning feedback loop — do not; the loop is the crucial element. Also: an MVP can ship with minimum quality; an MVI cannot. A product bug is a patch; "even a seemingly small gap in your security infrastructure, if discovered by the wrong person or bot, can wreak havoc on your cloud resources, access, and billing account." A canonical MVI carries **higher quality expectations than an MVP**.

Components any valid MVI includes: access controls, a mechanism for collecting logs (system access + application logs), **resource tags** (cheap at scale; power log filtering, CLI/console search, and cost attribution through one mechanism), and possibly a baseline set of account-wide CSP policies. Beyond that, workload specificity decides: if an application team demands a pinned-version managed solution with explicit properties, the minimum ≈ a maximal implementation (the version meeting all known end users' needs that cannot be extended without degrading UX), differing only by module abstraction/parameterization. If needs are loosely defined, start with provider defaults by omitting explicit assignments.

**Caveat:** MVI's frequent feedback-driven changes can force reorganization of the TF state object; taken to the extreme this means frequently rewriting state, which is risky. Unless you define impact constraints explicitly, nothing else does it for you.

### MVI Build-Measure-Learn Loop (4 steps)
1. **Build** — infrastructure supporting the target application team with baseline feedback mechanisms, least effort. May start with hardcoded values, default values, and untyped variables depending on how fastidious you are about parameterization.
2. **Measure** — collect system/platform/application feedback plus direct user reports. Early: only the static analysis you must comply with; later: comprehensive dashboards and practical alerts. Things worth measuring: access logs, application logs, compute resource metrics, **frequency of infrastructure drift by TF project and CSP service**, number of resources/attributes affected per drift event, release velocity, infrastructure costs. Prefer scripted calculations persisted as log entries (reusing an existing platform component) before building anything custom — and since you analyze logs in the CSP itself, you are technically an end user.
3. **Learn** — analyze correlations and event sequences, troubleshoot defects, pilot unfamiliar features. Early piloting = rigorous review of plan results; later = tests that provision and evaluate live resources in isolated, ephemeral environments.
4. **Iterate** — develop the update, validate it introduces no defects, release. May require `terraform state` manual modification. Run to completion, each loop should yield a **self-consistent infrastructure**.

User feedback channel: start with a designated email/chat conversation; if a ticketing system (Jira, ServiceNow) exists, incorporate it from the beginning but keep it simple and unstructured — no templates or forms initially.

### TF Maturity Model
A maturity model reduces an organization's practices to graduated qualitative designations, serving as both a present assessment and a guide to the next level. Reference models:
- **CMM** (Capability Maturity Model, commissioned by the US DoD): five levels — **initial, repeatable, defined, capable, efficient** — applied per process; one organization may hold dozens of capabilities at different levels. Each level has goals, each goal requires activities (e.g., level 2 "repeatable" typically requires documentation).
- **OMM** (Open Source Maturity Model): three levels — **basic, intermediate, advanced** — applied to the project as a whole; documentation is a basic-level practice.

**Mental Model — three universal implications:**
- **Not an indictment:** every highly mature project passed through lower levels. A low rating is a rubric for planning/validating priorities, not a denunciation — don't let pride block the framework.
- **Rises to the most business-efficient level:** don't push every process to max. Prioritize frequently/regularly executed processes to level 5 (efficient); less frequent ones to level 3 or 4 (defined/capable); very infrequent, ad hoc, highly nuanced or subjective processes may stay at level 2 (repeatable) indefinitely. "Investing in higher levels of maturity in these processes may sap resources from more lucrative activities and may even be more costly than the benefit it would achieve."
- **No partial levels:** you achieve a level only when ALL its features are done. A project claiming 1.4 stays at level 1. There is no fractional level between two levels.

Use maturity models to orient roadmapping, planning, and budgeting (steering committee / governing board); they highlight areas you may be avoiding or overlooking, articulate skill gaps (training, hiring, contracting), and give structure and rationale for budget requests and work scheduling.

**Explicit Maturity Model Verticals (CNMM):** the author's CNCF Cartografos group's Cloud Native Maturity Model expands maturity across five dimensions: **technology, people, process, policy, business outcomes** — because adopting a platform like Kubernetes is never purely technical. In CNMM, all aspects must reach a level for the organization to claim it — an organization's maturity equals its least mature aspect — chosen to avoid arbitrary averaging into a partial level.

Mapped to TF:
- **Technology** — easiest to map; module development standards, change collection/release processes, degree of automation.
- **People** — teams authoring TF code, release managers, business stakeholders, application developers running atop the infrastructure, even their end users.
- **Process** — start largely manual → manually directed → highly/fully automated; treat technology as the goal, not the prescription.
- **Policy** — mix of written and unwritten rules; imposed by regulator, corporate mandate, or self-assumed; consider the aspect in the abstract before implementation.
- **Business outcomes** — hardest to map; left out of the TF sketch. Some derivable from other aspects (licensing costs, personnel costs), but it can't be fully defined before mapping real organizations.

TF maturity trajectory sketch (intentionally ambiguous — no strict goals, no fixed level count — to leave room for discussion): (1) single TF project, single highly skilled team, manual procedures, policies enforced through discipline and tedious audits → (2) many loosely associated TF projects from disparate teams collaborating with centralized security/release-management/observability teams; significant automation; constraint on direct resource manipulation — changes initiated only from within a specific platform → (3) back to a small collection of highly skilled teams supporting a massive, intricately connected assemblage of automated processes governed by comprehensive policies enforced at multiple points. All aspects progress together, to some degree.

### TF Versus Others (comparison frame)
- **vs CSP-native (CloudFormation, ARM):** they accept only JSON/YAML — "expressive to a fault" — while HCL is relatively standardized in format and organization. TF manages all CSPs in a common format (even one project), so a CSP migration or multicloud setup needs a smaller new skillset and far less restructuring. But TF lags: it depends on provider plug-ins (AWS and Azure plug-ins maintained by HashiCorp, GCP's by Google), and CSPs will not prioritize TF over their internal tools when all else is equal.
- **Azure Bicep:** DSL structured very similarly to HCL but with Azure-specific built-ins, compiling directly to ARM — so TF can lag Bicep on Azure features. **Prefer Bicep when a team will only ever own Azure infrastructure.**
- **Google Cloud Infrastructure Manager:** accepts TF HCL directly using the same provider plug-in, effectively running a specific TF version as a managed service — it should match TF support.
- **Crossplane (Upbound):** runs on a Kubernetes cluster, continuously reconciling resources to desired state defined in **composite resource definitions (XRDs)** — thin wrappers around CRDs. More strongly aligned to GitOps, "whereas TF can really only approximate GitOps, and still requires orchestration (but perhaps the real question is, 'do you even want GitOps?')." Free Crossplane requires a K8s cluster → chicken-and-egg: what configures the cluster? TF bootstraps easily with local state (e.g., to initialize a cloud-hosted backend). Crossplane providers lean on community support; TF's are built by HashiCorp or the CSPs.
- **Pulumi:** CLI + SDKs for popular languages — typesafe, far more logic-expressive, more extensively and directly testable. Records state to a file, runs anywhere, detects/remediates drift like TF, and can wrap any TF provider plug-in, so it can theoretically do all TF can. Risk: its inherently programmatic model yields flexibility "that can result in nonidempotent logic."

**Hybrid TF + Crossplane pattern (recommended when you want continuous reconciliation):** TF bootstraps Crossplane — initial/core/foundational resources (remote backend solution, baseline IAM controls for IaC operation, the K8s cluster Crossplane runs on) created first with TF, initially on a local backend; migrate that state to the remote location; thereafter Crossplane becomes the primary IaC platform for the majority of cloud resources.

## Mental Models
- **Journey, not destination / local equilibrium:** success is a sustainable steady state, not a checkbox; every practice is conditional on business change (M&A, volume contracts, new CSP features).
- **Conway's Law as sizing tool:** more components, products, and lines of business → larger management structure → directly influences infrastructure needs and TF project shape.
- **MVP → MVI extension:** keep the feedback loop, raise the quality bar, keep the "minimum effort/time" discipline.
- **Maturity as vocabulary, not judgment:** levels are a planning rubric for steering committees; you design *where each capability stops* based on business frequency and value.
- **State Triplet Theory:** the state triplet (from Chapter 6 — configurations, resources, source of truth/state) is an inherent property of *any* IaC solution. CSP-managed platforms encode the third component in the platform itself; Pulumi's state operates exactly like TF's; Crossplane's XRDs load into the cluster as K8s manifests and are the analog of TF state, except the source of truth lives in a cluster that continuously reconciles live resources with it (active vs static/passive state backend).
- **Autonomous agents framing:** LLM agents trained on public data (StackOverflow, forums) suffer garbage in, garbage out — output quality is proportional to input quality; they effectively copy-and-paste what they've seen, "which is generally considered an amateur procedure" — but that is also how many human practitioners started, learning by trial and error. Hence code generators do serviceable work on arbitrary solutions but hit diminishing returns on truly novel approaches without expert guidance. (Feedback on their outputs is effectively supervised machine learning.)

## Anti-patterns
- **Optimizing for a predefined success criterion in TF at scale.** Fails because business changes (new CSP features, new lines of business, M&A, volumetric contracts) invalidate it; aim at a local equilibrium instead.
- **Driving every process to max maturity level.** Fails because infrequent, ad hoc, nuanced, or subjective processes cost more to mature than the benefit achieved — keep them at "repeatable" and spend the resources on high-frequency processes.
- **Claiming partial maturity levels (e.g., "we're at 1.4").** Fails because level membership is all-or-nothing; a project missing extensive test suites or documented architecture/designs remains at level 1 no matter how many other practices it has. The corollary from CNMM: your maturity equals your least mature aspect.
- **Treating MVI as "MVP quality."** Fails because infrastructure defects are costlier than product bugs — a small security gap found by the wrong actor wrecks cloud resources, access, and billing.
- **Importing an MVI definition that omits the feedback loop.** Fails because without the Build-Measure-Learn loop the "minimum" infrastructure is never informed by users and calcifies; most published MVI definitions make exactly this mistake.
- **Unconstrained MVI-driven state churn.** Frequent feedback-driven changes can end in frequent TF state rewrites; unless you explicitly define impact constraints on state, nothing prevents it — and state rewrites are high-risk operations.
- **Mixing `resource{}` and `module{}` blocks** when extracting into nested modules (restated here as a closing rule). Theory on Nested Modules: when bundling resources out of a root module into a nested module, bundle the *other* resources into their own modules too — maintaining a strict structural distinction between modules that manage resources and modules that manage other modules. Skip this for singular resources (a singleton module signals a different change is needed). In a live project you are already modifying state (`terraform state mv`), so the extra bundling is not much extra work.
- **Relying on drift reports alone to classify manual changes.** Unexpected drift has multiple categories: inappropriate manual changes (some may hold valid business justification or the authority to self-justify — enable a wildcard job capability and possibly temporary access), false change reports (e.g., caused by use of the preferred resource identifier construct), and *expected* changes that belong in a `lifecycle{}` block (e.g., a compute instance's network interfaces, storage device mapping, or swap utilization). Investigate non-manual drift case by case.
- **Assuming CSPs will keep TF support at parity with their own tools.** They won't prioritize TF over internal tools when all else is equal — plan around provider-plugin lag.

## Reference Tables

### Splitting a TF project — heuristics (Useful Heuristics, decision trees Figs 12-4..12-8)
| Signal | Heuristic |
|---|---|
| Some .tf files updated ≤ once/quarter, others every sprint (possibly several times) | Different resource lifecycles → abstract configuration into two or more nested modules, or split into full TF projects |
| Queue of changes waiting on long-running validations in the IaC workflow | Extract validations into a pre-release process (e.g., triggered by merge-request open); if validation must stay in the release workflow, run only checks corresponding to the resources the change updates — not all validations every trigger |
| Many `count` conditional resources; related / same general resource domain | Abstract into a nested module |
| More than ~50% of an environment-style project conditional, and conditional resources needed in only one environment (e.g., production) | Extract those resources into a project dedicated to that environment |
| Repeated `for_each` resources being extracted into a nested module | If resources correspond one-to-one in equal numbers (perhaps sharing the same input variables) → move `for_each` *outside*, into the `module{}` block; if not one-to-one → `for_each` follows the `resource{}` blocks *inside* the module |

### MVI measurement menu
Access logs, application logs, compute resource metrics, drift frequency by TF project and CSP service, resources/attributes affected per drift event, release velocity, infrastructure costs. Logs and resource metrics: largely covered by CSP defaults; the rest: derive with scripted calculations persisted as log entries before building custom logic.

### Maturity model level counts
CMM: 5 levels (initial, repeatable, defined, capable, efficient) — per process. OMM: 3 levels (basic, intermediate, advanced) — per project. CNMM: traditional levels × 5 verticals (technology, people, process, policy, business outcomes), all aspects required to claim a level.

### Tool selection quick guide
| Situation | Preference |
|---|---|
| Azure-only team, want earliest feature/resource support | Bicep (compiles directly to ARM, Azure-specific built-ins) |
| GCP with HCL and same provider plug-in, managed service | Google Cloud Infrastructure Manager |
| Multicloud / CSP migration, one common config language | Terraform HCL |
| Continuous reconciliation / GitOps alignment on Kubernetes | Crossplane, bootstrapped by TF (TF creates remote backend, baseline IAM, the K8s cluster; migrate state to remote; Crossplane then becomes primary) |
| Typesafety, logic expressiveness, direct testing in a real language | Pulumi (watch for nonidempotent logic from its programmatic model) |

## Worked Example
**SaaS Scale-up (Fig 12-2):** a consumer fintech start-up — a sportsbook/prediction-market platform — operating in one economic area, scaling into new jurisdictions. Highly regulated, rapidly evolving laws → culture of discipline, self-regulation, efficient compliance and provenance; a comprehensive policy rules engine runs continuously at runtime and within the SDLC and IaC automation workflows, with scheduled and on-demand compliance reports. Products: mobile apps (iOS/Android), a user web portal, landing pages, internal admin portals, SMS push notifications, plus private data channels to/from other financial institutions. Stack: React frontends; Python, Go, Rust backends; a deliberate policy of **self-hosting platforms instead of CSP-managed services** (especially data services — databases, caches, OSes, encryption software are licensed IPS, not fully OSS), with exceptions for document storage, certain networking controls, CDN, key/secret management; OSS only after substantial de-risking, for policy enforcement, observability, and validation. An LLM provider service agreement allows LLM use for internal workloads case-by-case with documented business justification and leadership sponsorship; **direct LLM updates to customer-facing software are disallowed**. Tech is ~50% of the workforce (FTEs + contractors, specialists to recent grads), roughly Scrum/XP, with fluid roles and pair programming on high-risk components.

The founder-team → angel round → 3x growth arc leaves infrastructure **built primarily by hand in the web console with some CLI operations**; any existing TF is legacy and can be abandoned. You are hired as the TF specialist, effectively acting as the TF team, reporting to the VP of Engineering, expected to hire one or two delegates once oriented and funded. The VP's goals: lean and standardized IaC + self-hosted tooling → your resolve to **standardize compute resources for specific functions** (databases, web servers, container orchestration clusters, specialized appliances) as an ongoing effort that must be superseded by ad hoc leadership requests and critical business functions.

There is effectively one product, so the focus is environment and region replication, yielding **two TF projects**: (1) a **foundational/core layer** — primary structural components, IAM policies, central networking controls; (2) an **application project** — supporting unique variable values per supported environment and region. While building configuration you **import existing resources, prioritizing those that have reached a reasonable degree of stability** (lest new un-encoded changes block other efforts). Substantial manual infrastructure changes remain but are tracked, documented, justified, with a defined mitigation strategy to reduce the behavior. Vibe coding is approved for direct development of TF projects, for now. Tooling: TFE, managed closely with the Platforms Team (which also owns the artifact registry).

Contrast with the other scales: the **Regional Company** (energy conglomerate, BUs from M&A sharing one cloud account, multicloud disaster failover between CSPs with a partially automated, relatively simple procedure, spoked SDLC environment per BU) fits a compact environment managed by a single TF team: one or two core TF projects (central operations services + public edge) plus two or three TF projects per BU (structural components incl. foundational networks, and at least one for SDLC environments); OpenTofu if policy allows, else self-hosted TFE; the team spends more time on cost reduction and auditing than digital performance gains, working Kanban while the BUs run Scrum/SAFe. The **Global Firm** (food & beverage, dozens of continent-bounded brands in independently governed super-regions, mostly internal workloads, multi-CSP from M&A with a persistent consolidation effort) layers its many TF projects into **rings of protection and standardization** — innermost layers most standardized on structural/operational needs, outer layers built from centrally distributed modules plus custom configurations for local brands — with TFE plus a separate general-purpose automation platform running sensitive operations like wildcard jobs, and TF teams operating in loose SAFe with program-increment alignment across BUs and corporate.

## Key Takeaways
- Aim at a local equilibrium — low friction, total coverage, fast incident response, within budget — not a fixed end state; re-derive it when business context shifts.
- All enterprises need the same capabilities; they differ in scale, and scale (via Conway's Law) dictates your TF project shape. Roughly: small/compact org → 1–2 core projects + a few per BU managed by one team; scaling SaaS → core/foundational project + application project focused on environment/region replication; global org → several rings of protection and standardization with centrally distributed modules at the outer edges.
- Split TF projects on observable signals: divergent resource lifecycles (files updated ≤ quarterly vs every sprint), long-running validations queueing the release pipeline, heavy `count` conditionality (>50% in one environment only), and one-to-one vs many-shaped `for_each` when nesting modules.
- Build a Minimum Viable Infrastructure that keeps the Build-Measure-Learn feedback loop, raises quality above MVP standards, and starts with tags, access controls, and log collection — then iterate through hardcoded/default values toward parameterization.
- Use maturity models as planning rubrics for budgeting and roadmapping: no partial levels, don't mature everything to max, and consider explicit verticals (technology, people, process, policy, business outcomes) — your maturity equals your least mature aspect if you adopt that rule.
- TF vs alternatives: stay in HCL for multicloud/CSP migration; take Bicep for Azure-only; take Google Cloud Infrastructure Manager for TF-compatible managed execution on GCP; bootstrapping TF + Crossplane for continuous reconciliation; Pulumi when language-native logic and testing matter.
- The state triplet is universal to IaC — even Crossplane's cluster-held XRDs play the state role — and AI agents in IaC workflows inherit amateur copy-and-paste behavior until an expert practitioner guides them.

## Connects To
- **Ch 6 (state management):** the State Triplet (configurations, resources, state as source of truth) is reasserted here as universal; `terraform state` modification and `state mv` recur in MVI iteration and module extraction.
- **Project splitting / module architecture chapters:** the Useful Heuristics section operationalizes the whole book's guidance on when to extract nested modules and split projects (lifecycles, conditionality, `for_each` placement, avoid mixing `resource{}` and `module{}`).
- **Workflow/CI chapters:** long-running validation mitigation (pre-release triggers, change-scoped checks) and wildcard jobs for justified manual access tie back to IaC automation and drift-handling chapters.
- **Policy/compliance chapters:** the fintech scale-up's policy rules engine and the regional firm's audit processes are the closing case expression of the book's policy-as-code guidance.
- **Beyond the book:** Ries' MVP/Lean Startup for MVI; DoD CMM, OMM, and CNCF Cartografos CNMM for the maturity vocabulary; Crossplane/Pulumi/Bicep docs for the tool comparison.