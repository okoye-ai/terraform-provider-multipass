# Chapter 8: Security and compliance

## Core Idea
"Bake security into the infrastructure instead of icing it later": secure pipeline credentials with least privilege, mask and rotate secrets, tag resources for auditability, and express every security/compliance rule as policy-as-code tests enforced in the delivery pipeline — before an audit fails you.

## Frameworks Introduced
- **Principle of least privilege**: users or service accounts should have minimum access requirements to a system — only enough to complete their tasks.
  - When to use: every delivery pipeline's infrastructure-provider credentials.
  - How: remove administrative credentials; grant write access only to the resource types the IaC creates; attach roles to credentials for composability; use factory modules of permission sets (e.g., a web-application module bundling network, App Engine, Cloud SQL access); re-check with provider tools (e.g., GCP excess-permission analysis) every time you add a resource.
- **Masking**: suppressing or redacting plaintext sensitive information to prevent someone from reading it.
  - When to use: anything in pipeline logs or dry-run output someone could use to gain access (passwords, encryption keys, identifiers like IP addresses).
  - How: mark IaC variables as sensitive (tool redacts in plan/output logs) plus a pipeline plugin that masks sensitive strings; if a secret leaked, rotate it in the secrets manager and change it directly in the resource.
- **Secrets manager workflow**: store and rotate credentials in a secrets manager; generate secrets via a random-string function or read them from the manager — never pass secrets as static variables. Separately managing secrets introduces intentional mutability/drift (the IaC-stored password diverges from the rotated one), which is acceptable to prevent exploitation.
- **Security requirements checklist for delivery pipelines (to minimize attack surface)**:
  1. Check least-privilege access for provider credentials from the beginning.
  2. Generate secrets by function or read from a secrets manager; avoid static variables.
  3. Verify the pipeline masks sensitive configuration in dry-run output and logs.
  4. Provide a mechanism to revoke and rotate compromised credentials or data quickly.
- **Tagging strategy**: defines a set of metadata (tags) used for auditing, managing, and securing infrastructure resources in your organization; implemented with the prototype pattern as a shared tag module.
  - When to use: production resources at minimum (enforce required tags there; testing can host untagged resources).
  - How: minimum tags — service or team, team email/channel, environment. Optional — automation flag (distinguishes manual from automated resources), repository, business unit for billing, compliance marker for personal-information handling. Prefer dash-case names/values and watch provider character limits (typically 128-character keys, 256-character values).
- **Policy as code** (a.k.a. shift-left security testing, static analysis of IaC): tests infrastructure metadata and verifies that values comply with security or compliance requirements before pushing to production; includes rules for dynamic analysis tools and vulnerability scanning.
  - When to use: always, after functional testing in the pipeline but before release to production.
  - How: parse the configuration/state → check field values → fail on mismatch (pass/fail).
- **Policy engine**: takes policies as input and evaluates resource metadata for compliance. Three use cases: (1) security tests for specific platforms, (2) policy tests for industry/regulatory standards, (3) custom policies. In practice you mix tools — expect to adopt five or six — and extend one with custom policies (the author uses pytest as a primitive policy engine).
- **Static vs. dynamic analysis**: static analysis runs the policy tests in the pipeline against configuration before production; dynamic analysis scans the running production environment continuously, catching emergency or break-glass changes. Run the most critical tests statically; run soft/advisory tests asynchronously.
- **Enforcement levels** (borrowed from HashiCorp Sentinel's terminology): **hard mandatory** (must fix — pipeline fails before production, e.g., database tagging), **soft mandatory** (may require manual analysis for an exception — security team reviews and approves, e.g., a firewall rule needing public 0.0.0.0/0 for a load balancer), **advisory** (knowledge-sharing of best practices — fix what you can, doesn't block, e.g., CIS benchmarks).

## Key Concepts
- **Policy**: a set of rules and standards in your organization to ensure compliance to security, industry, or regulatory requirements.
- **Attack surface**: the sum of different points of attack where an unauthorized user can compromise a system — full-admin pipeline credentials and leaked root passwords both expand it.
- **Break-glass changes**: manual changes to stabilize or fix system failures; dynamic analysis catches the compliance drift they introduce.
- **Positive vs. negative testing**: negative testing asserts a value does not match (no `0.0.0.0/0` in firewall source ranges); positive testing asserts it does (a required VPN CIDR). The author writes both — the combination better expresses the policy's intent.
- **Security tests as education**: descriptive test names and error messages teach teammates the secure configuration and let them self-correct, scaling security across the organization.
- **Shared policy-test repositories**: modularize tests (database-tests, firewall-tests, cis-benchmark) into a shared repo (e.g., `gcp-security-tests`) that all teams reference; divide by business unit, function, environment, provider, resource, stack, or benchmark.
- **NIST National Checklist Program / DoD STIGs / CIS benchmarks**: sources of industry and regulatory security benchmarks; few policy engines ship complete standards, so you usually write or augment these yourself.

## Mental Models
- Think of a pipeline credential as a single point of compromise: whatever it can do, an attacker can do — so scope it to exactly the resources the IaC touches.
- Think of policy-as-code tests as unit tests for unknown knowns: every rule your security team knows and engineers don't becomes a failing test with a self-explanatory error message.
- Use "icing vs. baking" when sequencing: adding compliance at the end delays delivery or breaks functionality; embedding tests from the start shortens time to production.
- Think of enforcement levels as a triage: hard mandatory gates production, soft mandatory routes to a human, advisory just teaches.

## Anti-patterns
- **Full administrative credentials on delivery pipelines**: anyone who steals them can create and update anything in the environment (mine crypto, read customer data).
- **Printing secrets in pipeline logs**: an unmasked root database password in logs is a compromise waiting to happen; mask, then rotate.
- **Passing secrets as static variables in configuration**: secrets belong in a secrets manager or generated by function.
- **Deploying untagged production resources**: after a breach, no tags means nobody knows which resource was compromised or who owns the ballooning bill.
- **Immediately deleting untagged resources**: risky — you may destroy an essential resource; examine before deleting.
- **Running all policy tests asynchronously**: you temporarily push noncompliant configuration to production even if you fix it quickly; only run soft/advisory checks async, never the critical ones.
- **Relying on code review alone to catch insecure config**: a teammate missed the permissive firewall rule and missing tags, and the database was breached two weeks later.

## Code Examples
Security test: firewall rule must not allow the world (negative testing):

```python
@pytest.fixture(scope="module")
def resources():
    with open(CONFIGURATION_FILE, 'r') as f:
        config = json.load(f)
    return config['resource']

@pytest.fixture
def database_firewall_rule(resources):
    return resources[0][
        'google_compute_firewall'][0][APP_NAME][0]

def test_database_firewall_rule_should_not_allow_everything(
        database_firewall_rule):
    assert '0.0.0.0/0' not in \
        database_firewall_rule['source_ranges'], \
          'database firewall rule must not ' + \
          'allow traffic from 0.0.0.0/0, specify source_ranges ' + \
          'with exact IP address ranges'
```
- **What it demonstrates**: a policy test that parses the IaC JSON, checks a value, and fails with an error message telling the engineer exactly how to comply. (AWS: `ingress.cidr_blocks`; Azure: `security_rule.source_port_range`.)

Policy test: database must be tagged:

```python
def test_database_instance_should_have_tags(database_instance):
    assert database_instance['settings'][0]['user_labels'] \
        is not None
    assert len(
        database_instance['settings'][0]['user_labels']) > 0, \
        'database instance must have `user_labels`' + \
        'configuration with tags'
```
- **What it demonstrates**: an audit/compliance policy as code — non-empty labels — that fails the pipeline before an untagged database reaches production.

Least-privilege access module for a pipeline service account:

```python
def build_frontend_configuration():
    name = 'frontend'
    roles = [
        'roles/compute.networkAdmin',
        'roles/appengine.appAdmin',
        'roles/cloudsql.admin'
    ]
    frontend = iam.ApplicationFactoryModule(name, roles)
    resources = {
        'resource': frontend._build()
    }
    return resources
```
- **What it demonstrates**: expressing least privilege as composable role lists through a factory module instead of granting admin credentials.

Tags prototype module (excerpt):

```python
class TagsPrototypeModule():
    def __init__(self, service, department, business_unit,
                 company, team_email, environment):
        self.resource = {
            'service': service,
            'department': department,
            'business-unit': business_unit,
            'company': company,
            'email': team_email,
            'environment': environment,
            'automated': True,
            'repository': f"${company}-${service}-infrastructure"
        }
```
- **What it demonstrates**: the prototype pattern standardizing tags once so every resource inherits the audit metadata.

## Reference Tables
Examples of policy engines for provisioning tools (Table 8.1):

| Tool | Use case(s) | Technology integration(s) |
|---|---|---|
| AWS CloudFormation Guard | Security tests for specific platforms; custom policies | AWS CloudFormation |
| HashiCorp Sentinel | Security tests for specific platforms; custom policies | HashiCorp Terraform |
| Pulumi CrossGuard | Security tests for specific platforms; custom policies | Pulumi SDK |
| Open Policy Agent (underlying tech for Fugue, Conftest, Kubernetes Gatekeeper, and more) | Security tests for specific platforms (tool-dependent); policy tests for industry/regulatory standards (tool-dependent); custom policies | Various (openpolicyagent.org/docs/latest/ecosystem) |
| Chef InSpec | Security tests for specific platforms; custom policies | Various (supermarket.chef.io) |
| Kyverno | Security tests for specific platforms; custom policies | Kubernetes |

## Worked Example
uDress story end-to-end: the frontend pipeline ran full-admin GCP credentials and printed the root database password in logs (expanded attack surface). Remediation sequence: (1) replace admin credentials with roles limited to network, App Engine, and Cloud SQL; (2) mask the password via the IaC tool's sensitive variables plus a pipeline plugin, then rotate the password out-of-band; later, an untagged permissively firewalled test database was breached and nobody could identify the owner — so (3) tests were added: the firewall test fails on `0.0.0.0/0` with a corrective error message, and the tags test fails on empty `user_labels`. A teammate then tries opening the firewall again; the pipeline fails with the message and they self-correct to exact IP ranges without a security investigation. Finally the team modularizes the tests into a shared `gcp-security-tests` repo and classifies them: tagging = hard mandatory, the firewall exception = soft mandatory (security-team review), CIS benchmark = advisory.

## Key Takeaways
1. Run the four-item delivery-pipeline security checklist: least privilege, generated/managed secrets, masked output, fast revoke-and-rotate.
2. Group pipeline permissions into roles via modules so access composes with new resources; re-audit excess permissions every time you add one.
3. Mask anything sensitive in dry-run and log output — and assume masking is not protection; rotate anything that leaked.
4. Tag at minimum service/team, team email, and environment in production; choose dash-case and respect provider tag character limits.
5. Write security and policy tests with descriptive names and error messages — the message is the remediation guide.
6. Run critical (hard mandatory) policy tests in the pipeline before production; run soft mandatory through manual exception review and advisory asynchronously.
7. Share policy tests in a dedicated repository so all teams and the security team evolve one source of compliance truth.
8. Mix and match policy engines — no single tool covers platform security, industry standards, and custom policies.

## Connects To
- **Ch 2**: securing secrets with a secrets manager, naming/tagging standards, reconciliation of drift introduced by rotating secrets.
- **Ch 3 / Ch 5**: prototype and factory module patterns reused for tag modules, permission-set modules, and modular policy tests.
- **Ch 6**: policy tests are unit tests/static analysis applied to security values; positive/negative assertion techniques carry over.
- **Ch 7**: enforcement levels map to pipeline quality gates — hard mandatory tests act as the automated review stage.
- **Ch 9**: a compliance test on the Terraform plan (detecting database deletion) protects stateful infrastructure during blue-green changes.
- **CIS Benchmarks / NIST National Checklist Program / DoD STIGs**: industry and regulatory standards to codify as advisory or mandatory tests.
- **HashiCorp Sentinel**: source of the hard mandatory / soft mandatory / advisory enforcement-level terminology.