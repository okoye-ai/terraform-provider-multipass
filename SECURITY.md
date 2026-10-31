# Security Policy

## Supported Versions

Only the latest released minor version receives security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/okoye-ai/terraform-provider-multipass/security/advisories/new).
Do **not** open a public issue for anything you believe is exploitable.

When reporting, include:

- The provider version (and, if known, the commit hash or tag)
- The Multipass CLI version on the affected host
- A description of the issue and how it might be exploited
- Any relevant Terraform configuration or command output (redact secrets)

What to expect:

- **Acknowledgment:** within 7 days of the report.
- **Updates:** at least every 14 days while a report is being investigated.
- **Accepted reports:** a fix is developed in a private fork, released as a
  patched version, and disclosed publicly once a fix is available. You will be
  credited in the release notes unless you prefer otherwise.
- **Declined reports:** you will receive an explanation of why the issue is
  out of scope (for example, it requires an environment the attacker must
  already control).

### Scope notes

Please keep in mind the provider's security model when reporting:

- The provider **shells out to the `multipass` CLI** on the Terraform host and
  runs with the permissions of the Terraform process. Anyone who can write
  your provider configuration or control the local `multipass` binary is
  already in a position of significant trust.
- `cloud_init` content supplied to the provider runs inside the guest VM by
  design. Guest-side code execution via cloud-init configuration is expected
  behavior, not a vulnerability.
- Supplying crafted values in instance/resource arguments that require an
  already-trusted host is generally out of scope; cross-instance or
  cross-host escalation would not be.