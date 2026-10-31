# Chapter 9: Organization Structures and Policy Constraints

## Core Idea
When compliance measures (external: HIPAA, GDPR, government/regulatory) or org structures (internal: SOC 2 / NIST initiatives, reorgs) are imposed on an existing Terraform ecosystem, the response is not "add one compliance module" — it is re-partitioning access controls, policies, and network domains across the TF project hierarchy so that each policy binding, service identity, and network edge lives with the resource and lifecycle it governs. Use borrowed software-engineering principles (SRP, SoC, defense in depth) as decision tools for *where* policies and configurations belong. Competing agendas (security vs. velocity, vendor vs. in-house) must be balanced, not reconciled — paradoxes guarantee there is no single right way, so document trade-offs with business justification rather than seeking a universal answer.

## Frameworks Introduced
- **SRP for Terraform (Martin's Clean Architecture restatement)**: "a module should be responsible to one, and only one, [group of users and stakeholders]." Map: *stakeholders* = everyone who drives the module's development; *users* = anyone consuming it as a child or root module (root-module users are the stakeholder subset that manages it); responsibility for a nested module sits with the module that references it. Use this mapping as the test for **policy binding deduplication** (Table 9-1): same stakeholder group across two scopes → one shared binding at the parent scope; different teams that merely happen to need the same rule → duplicate dedicated policies, even in the same VPC.
- **Separation of Concerns (Dijkstra; two levels per Lopes)**: (1) *conceptual* — each concern is a sufficiently primitive, individually abstracted concept; (2) *implementation* — concerns isolated in separate code blocks with loose coupling. In TF: strictly one-way dependencies between projects (downstream may consume upstream output; never relay back), no mutual dependencies, each module self-consistent. The overfitting-vs-verbosity tension is the operating trade: overfixing fields bloats module libraries and duplicates work when new standards arrive; too many parameters forces intricate `validation{}`/`precondition{}` blocks whose conditions compound in complexity. Mitigate via OSS-inspired internal transparency — let internal consumers view and propose changes to other teams' modules ("opting into becoming a stakeholder"), so separation among *components* never becomes walls between *teams*.
- **Defense in Depth**: layered controls because no single solution covers its vector. Full stack: account-wide policies → scoped policies → layer 7 firewall (domain + content inspection) → known-threat analysis (IDS/IPS) → IAM policies → CSP proxy → layer 4 firewall (IP/protocol). Known costs: steep diminishing returns, multi-layer edits for every change (both for blocking new vectors and for opening legitimate paths — e.g., you must unwind region restrictions *and* add IDS/IPS when you enter a blocked region), and intentional friction (manual approvals, temporary permission elevation). Critically, **certify beneficial anomalous behavior** (pre-allowlist or issue a test service identity) as deliberately as you block malicious behavior.
- **Authoritative vs. nonauthoritative IAM binding discipline** (Table 9-2): authoritative bindings (`*_iam_policy`, `*_iam_binding`) guarantee exactly what is bound but wipe everything else; nonauthoritative (`*_iam_member`) is purely additive but cannot purge access. Canonical pattern: one authoritative baseline in a foundational layer, nonauthoritative layering downstream — and **never both types in the same module/TF state** (breaks idempotence → never-clean states, even if you force ordering via `depends_on`, attribute refs, or `-parallelism=1`). Authoritative bindings should appear once per binding scope, never repeated across projects.
- **Maximal-allowed-access account posture**: restrict only behavior inappropriate for *any* existing or scheduled workload; never write account-level rules so strict that smaller scopes must carve exceptions.
- **Edge taxonomy for cloud networks** — four edge types, each with its own ownership and TF placement: **public edge** (internet gateway/NAT + layered managed proxies), **private edge** (on-prem via colocation/direct link — takes weeks and long contracts — or VPN appliance), **edges between cloud accounts** (VPC peering or VPN to trusted third parties), **CSP-proxied edge** (managed proxy per component/group, e.g., IAP — a workaround for trusted individuals and internally built UIs, not the whole ecosystem).

## Key Concepts
- **CSP scope hierarchies don't translate**: GCP (Organization → Folder, nestable ×10 → Project → resource) vs. Azure (Management Group → Subscription → Resource Group → resource). Remap when porting, e.g., Azure Subscription→GCP Folder, Resource Group→GCP Project. Optimize for the *same operational experience* per engineer across CSPs, not identical component layouts — multi-CSP duplication (warm DR, discounted compute) is almost never a direct mapping.
- **Policy evaluation semantics**: IAM is **union** (effective permissions = union of all bindings, monotonically widening from a zero-permission default); **Deny always wins** and is evaluated before Allow. Account-wide *network* policies are typically the opposite — default full access, effective policy is the **intersection**, so extra rules monotonically restrict. This asymmetry is why account-wide policies that could interfere should use scoping sparingly.
- **Asymmetric detectability**: widening a resource's access goes unnoticed (already-capable parties see no change); narrowing is surfaced immediately by the blocked parties. Hence prefer *most permissive at the highest scope, increasingly restrictive down the hierarchy*: easier to extend, more direct CSP-to-CSP mapping, more defensible in audit. Azure applies the most restrictive of any overlap; GCP allows child overrides of Organization policies — handle overrides via a sibling top-level Folder with its own permissive policy set.
- **Service identities** (AWS roles, GCP service accounts): manage near the resources they attach to — centralizing all creation bottlenecks; pure team autonomy without guardrails yields bloated, over-permissive fleets. Compromise: centralized *oversight* with distributed maintenance; IAM-specific TF projects at multiple layers for SoC-mandated org separation. Bind service-identity permissions **authoritatively** (least privilege for encoded behavior). Service identities are also policy *objects* — developers should be able to view/review them, and the automation platform identity is commonly granted wide binding powers (use sparingly; chained tight-grained identities become brittle — one corrupted link locks out everything below). Identity resources live in TF; **credentials do not** — manage them out-of-band (one-off API calls); prefer GCP service account impersonation to avoid transmitting credentials at all.
- **VPC peering invariants**: never across CSPs (use VPN/direct link: AWS Direct Connect, GCP Interconnect, Azure ExpressRoute); CIDR ranges must not overlap — including across a *peering group* (VPCA peered to both VPCB and VPCC means all three VPCs' CIDRs are disjoint, even if B–C never peer); **routes are nontransitive** (X↔Y, Y↔Z does not give X→Z); firewalls/gateways still apply inside each VPC; unencrypted traffic (HTTP/FTP) crosses peering unencrypted. Cross-account peering usually connects constrained, workload-free DMZ-style VPCs rather than mission-critical workloads.
- **Hybrid edge connectivity**: VPN traverses public internet but is end-to-end encrypted and bypasses public-edge security; direct links are private/high-bandwidth but unencrypted — combine VPN + direct link for encrypted private tunnels *between CSPs*.
- **Specialized appliances** (third-party IPS, licensed security appliances): isolate in their own remote module (custom static-analysis rules) and possibly dedicated root module with a dedicated service identity, so appliance-specific policy exceptions stay tightly scoped. Note these often have init-only configuration steps unsuited to idempotent TF — expect `lifecycle` conditions. Accept that splitting them out means some team holds responsibility in two projects (documented SRP exception).
- **Policy governance of the TF ecosystem itself**: repo-level RBAC (edit rights per team; broad read; auditable *temporary* credentials for security-policy code; account-wide policy repos may be the one place with no universal read access because they enumerate allowed behavior). Prefer one-off elevated operations via a special wildcard automation job over granting standing human access.

## Mental Models
- **Union vs. intersection as a layering axis**: IAM widens through additive layers (read-only baseline at foundation → team permissions per workload → temporarily elevated individual grants); network policies narrow through stacked rules. Design each layer knowing which axis it sits on.
- **Stakeholder test before binding a policy twice**: one group of users and stakeholders → shared binding at common parent; merely congruent-but-different groups → duplicate bindings. Same logic duplicates an identical L4 firewall rule per application even inside one VPC.
- **Paradox balancing, not problem-solving**: vendors (too few = single-vendor compromise risk; too many = each license is a new attack vector and finance caps the count); competing policies (SSH lockdown + appliance + no-attachments rule can only be resolved by stakeholders agreeing to a narrow exception). Expect compromise plus compensating controls, not a clean winner.
- **One module-per-workload public LB / public IPs on production compute = no edge strategy**: enterprise public edges are always multi-component (proxy, L7/WAF, cert) coordinated across several TF projects.
- **The state triplet as SoC**: HCL authoring, applied-state tracking, and live CSP reality are already separated concerns — untracked drift is disposed of as unintentional.

## Anti-patterns
- **Layered wrapper modules**: taking SRP as "one reason to change = one resource" and building a stack of wrapper modules each controlling a single attribute, funneled into a final singleton collector module. Fails: extreme proliferation, no reuse, all complexity collects in one place.
- **Mixing authoritative and nonauthoritative bindings in one TF state** for the same principals/resources: even with forced evaluation order, idempotence is destroyed and every run ends in a never-clean state. Consolidate to one binding type per state.
- **Authoritative bindings repeated across projects for the same resource**: the two projects compete, last-applied-wins, flipping possession on every run. Allow only the deliberate handoff case (project A removing a shared binding re-established by project B) — only predictable when the overlap is known.
- **Standard-defection under diminishing returns**: engineering a back channel (auto-approve to bypass manual approvals, or swapping in an analogous tool to dodge a standard) *increases* cost and effort while removing the defense value. Present the risk, not just the proposed solution, and never withhold a gap report for fear of rejection.
- **Credential transmission malpractice**: unencrypted sends (base64 is encoding, not encryption), identifier + secret in one message, secrets over team chat. Prefer self-service credential generation; otherwise an SSO-integrated encrypted-at-rest file share, ideally with self-managed keys.
- **Defining IAM directly in the CSP/automation platform** during evaluation and leaving it there: severe diminishing returns against an existing IdP; integrate SSO/OAuth early and onboard identities before authorization even exists.
- **Overly strict account-wide policies** that force per-resource exceptions, and **multiple sets of DLP policies** per data sensitivity tier without business justification (PHI handling rules should apply wherever PHI *might* land, not only where expected).
- **Signing the BAA before controls exist**: HIPAA Business Associate Agreement — and the GDPR data processing agreement — are the *last* step, after encryption, DLP, audit logging, network separation, and RBAC are in place.

## Code Examples
Layered authoritative IAM: foundational baseline plus instance-specific bindings on different resources (no interference, since authoritative policies ignore inherited permissions):

```hcl
#-----------------------------------------------------------------------
# In the core/foundational project
#-----------------------------------------------------------------------
resource "google_project_iam_policy" "core" {
  project     = var.project_id
  policy_data = data.google_iam_policy.core.policy_data
}

data "google_iam_policy" "core" {
  binding {
    role = "roles/viewer"

    members = [
      "group:stakeholders@tas-9-2.com",
      "group:developers@tas-9-2.com",
      "serviceAccount:ops@${var.infra_proj_id}.iam.gserviceaccount.com",
      "serviceAccount:app-id@${var.app_proj_id}.iam.gserviceaccount.com"
    ]
  }

  binding {
    role = "roles/editor"

    members = [
      "serviceAccount:ops@${var.infra_proj_id}.iam.gserviceaccount.com",
    ]
  }
}

#-----------------------------------------------------------------------
# In the workload-specific project
#-----------------------------------------------------------------------
resource "google_bigquery_dataset" "dataset" {
  dataset_id = var.dataset_id
}

resource "google_bigquery_dataset_iam_policy" "specific" {
  project     = var.project_id
  dataset_id  = google_bigquery_dataset.dataset.dataset_id
  policy_data = data.google_iam_policy.specific.policy_data
}
```

Because the dataset policy binds a *different* resource than the project, the two authoritative policies coexist; inherited project permissions remain intact. This is also the lever for access freezes: altering only the core project's bindings revokes write/admin for humans while downstream resources and service identities (created downstream, near where they're used) keep running.

**What it demonstrates**: the foundational-scope-then-narrow-scope authoritative layering pattern, mixing grouped human principals with per-project service identities, from which downstream nonauthoritative members can safely append.

Public-edge WAF as a reusable security policy (abridged from the GCP global external ALB example):

```hcl
resource "google_compute_security_policy" "waf" {
  name = "${var.alb_name}-waf"

  # Basic OWASP
  rule {
    priority = 1000
    action   = "deny(403)"

    match {
      versioned_expr = "PRECONFIGURED_WAF"

      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v422-stable')"
      }
    }
  }

  # All other traffic
  rule {
    priority = 2147483647 # This is the lowest priority (lowest evaluated)
    action   = "allow"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
```

**What it demonstrates**: one shared WAF `security_policy` attached by reference to both a `google_compute_backend_service` (`security_policy = ...waf.id`) and a `google_compute_backend_bucket` (`edge_security_policy = ...waf.id`) in the full edge stack — global address, URL maps, HTTPS proxy, forwarding rules, HTTP→HTTPS redirect, SSL cert — the multi-component reality of a public edge versus one load balancer per workload.

## Reference Tables

Table 9-1 — how to bind policies to groups of users and stakeholders (SRP-derived):

| Group scope | Policy binding logic |
|---|---|
| Singular group of users and stakeholders | Assigned in a single policy |
| Distinct groups of users and stakeholders | Assigned in dedicated (but otherwise equivalent) policies |

Table 9-2 — GCP IAM binding types by lockout risk (use it to pick binding type per centralization posture):

| Policy type | Authoritative/nonauthoritative | Lockout risk | Recommended use cases |
|---|---|---|---|
| `*_iam_policy` | Authoritative | Absolute. Wipes out all inherited or preexisting access. | Enforcing strict baseline isolation on highly sensitive resources |
| `*_iam_binding` | Authoritative | Targeted. Destructive to users and groups sharing that specific role. | Configuring exclusive role ownership at wide scopes by specific security groups |
| `*_iam_member` | Nonauthoritative | Low. Cannot purge unauthorized or manually created access. | Layering on permissions for downstream teams in the most focused scopes |

## Worked Example
Retrofitting a non-HIPAA-compliant product to serve a US healthcare customer (largely transfers to SOC 2; PHI is uniformly regulated PII):

1. **Encryption**: each CSP has a KMS; adopt **Customer Managed Keys (CMK)** with a security-team rotation schedule for audit verifiability. Place keys *alongside* the sharing context — key shared by a GCP Project goes in the Project's TF project; a dedicated key for a sensitive data store is created next to that component (bundle standard key+resource as a nested remote module).
2. **DLP**: obfuscate sensitive data in databases, scoped at available scopes, centrally controlled (either a workload is subject, or it isn't — one policy set even across PII/PHI tiers). Set controls *upstream* in the hierarchy so resources inherit protection from instantiation.
3. **Audit logging**: capture activity for the mandated retention (6 years at time of writing) in an *isolated* system — different retention qualities, and ops engineers don't need standing access; **audit logs about PHI are themselves PHI**. Centralize retention/analysis in a dedicated GCP Project with tightly governed IAM and temporary-access generation; embed log forwarding as a standard nested remote module on every Project, since account-wide log inheritance can't be assumed.
4. **Network separation**: create new VPCs dedicated to PHI transit carrying only encrypted traffic — enforce mutual TLS plus a CSP proxy for trusted human access (proxy ships as a standard module alongside the VPC; mTLS support differs per CSP and is typically per-group like per-load-balancer). Add validations that these standard components are actually used where required.
5. **Repo RBAC**: audit-friendly, strict edit rights per team, broad read, auditable temporary credentials for components like security policies.
6. **Last**: sign the CSP's BAA.

GDPR variant highlights: PII stays in the EEA (no globally hosted stores; E2EE channels for permitted out-of-EEA flows); encryption at rest and in flight via KMS/CMK; redirect logs/metrics to EEA-resident collection points; enable CSP assurance tooling (AWS Artifact + Config; GCP Trust and Safety Center, Cloud Asset Inventory, Security Command Center; Azure Service Trust Portal + Azure Policy); staff the 72-hour breach detection/notification obligation and the 30-day access/rectify/delete request SLA with dedicated roles, temporary elevated credentials, and consolidated TF-managed IAM.

ZTA variant highlights: no inherently trusted traffic, even intra-VPC; hyper-segmented networks grouped by aligned lifecycles; firewall rules keyed to **service identities** as source *and* destination (both ingress and egress) instead of tags or CIDR ranges; CSP-proxied edge (AWS Session Manager/Verified Access, GCP IAP, Azure Entra Application Proxy/Easy Auth) restricted to small groups; access logs + network flows with alerting and remediation; keep account-level policies broad so inherited rules can't impede per-hop verification.

## Key Takeaways
- Apply SRP as "one group of users and stakeholders per module" — it is the decision rule for sharing vs. duplicating policy bindings, firewalls, and log configurations across scopes.
- Enforce strictly one-way module/project dependencies; no mutual dependencies, no information flowing back upstream; TF projects apply once in a directed fashion.
- Defense in depth trades perfect security for cost, inertia, and steep diminishing returns; its layers are only as good as the discipline against back channels, and every added layer means more places to update for one change.
- IAM is union-monotonic with Deny overriding; network policies intersect; exploit both by putting the most permissive policy at the widest scope and narrowing downward.
- One authoritative baseline (foundational layer) + nonauthoritative layering (downstream) is the default IAM architecture; never mix binding types in a single state, and never repeat authoritative bindings for the same scope.
- Service identities live and move with the resources they attach to; their credentials never do (out-of-band management, impersonation preferred).
- Every cloud network has exactly four edge categories; internal networks stay out of application TF projects, and the public/private edges sit as direct children of the core project rather than inside or atop it.
- Account-wide policy repos deserve tighter, need-to-know access than most code, because they enumerate what is allowed.
- Compliance controls (HIPAA/GDPR/ZTA) get placed contextually: keys and TLS with their resources, DLP and audit centralized upstream, PHI/PII networks as new isolated VPCs — and the legal agreement is signed only once controls hold.

## Connects To
- **Chapter 8**: the layered TF project organization this chapter places IAM, network, and edge domains into; SoC's one-way dependency rule applies most strictly to project layers.
- **Chapter 6**: the state triplet as built-in separation of concerns; wildcard automation jobs as the sanctioned path for one-off elevated operations; the service-identity-based toolchain.
- **Chapter 10**: next chapter — validating within modules (`validation{}`, `precondition{}`) and with external controls, especially verifying IAM consistency and extending observability to the TF ecosystem itself; also the guardrail mechanisms for standardized PHI components.
- **Chapter 12**: the worked instance of freezing product-team write access by editing only the core project's authoritative bindings while downstream resources and service identities keep serving.