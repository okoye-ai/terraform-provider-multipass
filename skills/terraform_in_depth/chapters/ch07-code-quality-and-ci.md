# Chapter 7: Code quality and continuous integration

## Core Idea
CI can only gate what your project already tests: first build a local, one-command quality-control system (template + makefile + tools), then wire those exact same commands into CI so everything automatable is checked by machines and humans review only what machines can't.

## Frameworks Introduced
- **CI workflow (develop → push → automated tests → review → approve → merge)**
  - When to use: any team merging Terraform changes into a main branch.
  - How: PR becomes the merge gate; quality tools run automatically on the PR and block merge on failure. Hafner's correction: CI does *not* mean "run tests before merging" — the goal is regularly integrating changes into the main build (high-performing teams integrate multiple changes per day).
- **What humans review vs. what machines review**
  - When to use: deciding what a code review should spend attention on.
  - How: humans review Security, Best practices/consistency, Comments/documentation. TIP: "If something can be reviewed automatically ... rely on automation and free up your developers to focus on what matters."
- **Software template bootstrapping (GitHub Template Repos → Cookiecutter)**
  - When to use: starting any new module/root project so quality tools are configured before line one.
  - How: keep a boilerplate repo; upgrade to Cookiecutter once you need conditional logic/config generation (e.g., emit provider-specific TFLint plugin blocks from a `primary_provider` question).
- **Make as the standard command layer**
  - When to use: any project with more than a handful of tool commands ("we're introducing well over a dozen new commands").
  - How: every tool gets a makefile target (`test_validation`, `test_tflint`, `test_security`, `format`, `documentation`) grouped under aliases (`chores`, `security`); a non-PHONY `.terraform:` target caches `init`; the template ships the makefile so nobody memorizes commands.
- **Engine-agnostic builds (TF_ENGINE / TF_BINARY)**
  - When to use: supporting both Terraform and OpenTofu (and testing both in CI).
  - How: default `TF_ENGINE:=terraform`, map to `TF_BINARY` (`terraform`/`tofu`), call `$(TF_BINARY)` everywhere, override per-run with `make format TF_ENGINE=opentofu`.
- **Version manager pattern (tenv over tfenv/tfswitch)**
  - When to use: teams (especially multi-team module owners) needing Terraform, OpenTofu, and Terragrunt versions per project.
  - How: `tenv` transparently hijacks `terraform`/`tofu`/`terragrunt`, selecting versions from `.terraform-version` / `.opentofu-version` files found in the current or parent directories; supports exact versions, `~>` constraints, `latest-stable`, and `latest-allowed`/`min-required` to test that your declared version ranges are accurate. Override with `tenv tf use VERSION`.

## Key Concepts
- **Code linter**: a tool doing static analysis of code without running it, enforcing quality and stylistic standards (not logic).
- **Pre-commit hook**: a script run on every `git commit` that blocks the commit on failure — catching problems earlier in the cycle than CI. Managed via the pre-commit framework (local hooks mapped to makefile targets) or the `pre-commit-terraform` plugin (antonbabenko).
- **terraform validate**: syntax and naming checks without a backend or variables — requires only an initialized workspace (`terraform init -backend=false` preserves any existing backend).
- **TFLint**: the dominant Terraform linter; plugin-based (terraform, aws with 700+ rules, google 200+, azurerm 100+, opa). The terraform plugin is *not* enabled by default; pick `preset = "recommended"` or `"all"`, then enable/disable individual rules.
- **tflint-ignore**: inline comment (`# tflint-ignore: <rule>`) to suppress one rule on one resource, e.g. a beta instance type the ruleset doesn't know yet.
- **Checkov**: free open source security scanner for Terraform code (and plans, Helm, CloudFormation); runs fully locally with no central service; command-line driven; inline exceptions via `#checkov:skip=CKV_AWS_88:<reason>` — the reason is mandatory for review and audit.
- **Trivy (formerly TFSec)**: second open source scanner built by the TFSec team; covers more providers than Checkov but misses some of Checkov's rules, so run both ("when it comes to security, there is nothing wrong with a little redundancy"). Exceptions: `.trivyignore` (project-wide, with justifying comments) or `#trivy:ignore:AVD-AWS-0009` above the line.
- **terraform-docs**: generates documentation (usually markdown tables injected into README.md between `<!-- BEGIN_TF_DOCS -->` markers); `--output-check` mode verifies docs are current without writing.
- **Matrix strategy**: GitHub Actions feature running one workflow per permutation (engine × version), with `continue-on-error: ${{ matrix.experimental }}` for alpha versions that fail without blocking merge.
- **Branch protection**: SCM setting requiring passing checks and (usually two) non-author approvals before merge; bypassable with an explicit override checkbox for emergencies.

## Mental Models
- Use CI as a *merge gate over an already-automated local workflow* — CI must run the same makefile targets developers run locally, so dev and testing environments can't diverge.
- Think of the makefile as the contract between local development and CI: adding a tool means adding a target, a pre-commit hook, and a workflow — never a new memorized command.
- Think of reviews as the expensive tier of a two-tier filter: machines catch format/validation/lint/security; humans catch provider misconfigurations no scanner knows (e.g., RDS in the wrong subnet, backups not configured).
- Use templates to make quality the default: "the vast majority of the configuration and even the pipelines don't change between projects."

## Anti-patterns
- **Human review of automatable checks (formatting, lint)**: wastes reviewer attention on style while missing functionality; automate it and let CI block the PR.
- **Blanket security exceptions**: every skip comment must carry a documented reason; "for everything else, you should solve the problem that Checkov points out, not just tell Checkov to ignore it."
- **Running tflint --fix unreviewed**: autofixes aren't always right (e.g., deprecated AWS features your app intends to use); review findings, add exceptions, *then* autofix — it's deliberately not in the `chores` alias.
- **Hand-building each project from scratch**: tool configs drift between teams and steps get forgotten; bootstrap from a template.
- **Hardcoding `terraform` everywhere**: vendors you to one engine and blocks CI matrix testing of the other.
- **Storing registry tokens in Git**: use the GitHub Actions secret store.
- **Merging without branch protection**: failing tests plus button-merge is how main breaks; required checks + approvals prevent it, with override reserved for outages.
- **Commercial scanners by default**: Snyk/Checkmarx/Mend only make sense if already licensed; Checkov + Trivy are free and usually sufficient (keep Checkov alongside a paid tool anyway).

## Code Examples
```hcl
# .tflint.hcl — plugin presets with per-rule tuning
plugin "terraform" {
  enabled = true
  preset  = "all" # "recommended" is the default; "all" adds description/type rules
}
rule "terraform_comment_syntax" {
  enabled = false # opt out of one rule the preset enables
}
plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```
```yaml
# .pre-commit-config.yaml — local hooks map to makefile targets
repos:
  - repo: local
    hooks:
      - id: format
        name: Test format
        entry: make test_format
        language: system
        pass_filenames: false
      - id: lint
        name: Test lint
        entry: make test_lint
        language: system
        pass_filenames: false
      - id: security
        name: Test security
        entry: make test_security
        language: system
        pass_filenames: false
```
```hcl
resource "aws_instance" "this" {
  ami           = "ami-867166b8518f055af"
  instance_type = "t3.large"

  #checkov:skip=CKV_AWS_88:This instance is meant to be publicly accessible.
  # Trivy: Ignore Public IP address rule.
  #trivy:ignore:AVD-AWS-0009
  associate_public_ip_address = true
}
```
```yaml
# .github/workflows/ — quality gate: same make targets, both engines
name: Validation
on:
  push:
    branches: [main]
  pull_request:
jobs:
  validation:
    strategy:
      fail-fast: false
      matrix:
        engine: ["opentofu", "terraform"]
        version: ["1.6", "1.7", "1.8"]
        experimental: [false]
        include:
          - engine: "terraform"
            version: "1.10"
            experimental: true # alpha: may fail without blocking merge
    continue-on-error: ${{ matrix.experimental }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Terraform
        uses: hashicorp/setup-terraform@v3
        if: ${{ matrix.engine == 'terraform' }}
        with: { terraform_version: "${{ matrix.version }}" }
      - name: Install OpenTofu
        uses: opentofu/setup-opentofu@v1
        if: ${{ matrix.engine == 'opentofu' }}
        with: { tofu_version: "${{ matrix.version }}" }
      - name: Test Validation
        run: make test_validation TF_ENGINE=${{ matrix.engine }}
```
- **What it demonstrates**: the layering the chapter builds — one makefile target drives a tool; pre-commit reuses the targets locally; CI reuses them remotely across an engine x version matrix.

## Reference Tables
| Tool | Checks | Runs without Terraform? | Exception mechanism | Autofix |
|---|---|---|---|---|
| terraform validate | syntax, duplicate/name errors | No (needs init) | — | No |
| terraform fmt | formatting | No | — | Built in (`fmt`) |
| TFLint | style + quality rules; 700+ cloud rules via plugins | Yes | `# tflint-ignore:` / rule disable in `.tflint.hcl` | Yes (`--fix`; review it) |
| Checkov | security & compliance | Yes | `#checkov:skip=<ID>:<reason>` inline; YAML custom policies | No |
| Trivy | security (TFSec lineage) | Yes | `#trivy:ignore:<ID>` inline; `.trivyignore` file | No |
| terraform-docs | documentation freshness | Yes | — (regenerate) | Yes (injects) |
| Snyk / Checkmarx / Mend | commercial scanning + SBOM, central dashboards | Yes | platform-dependent | Partial |

Exception-comment comparison: Checkov takes its reason inline (`skip=ID:reason`); Trivy takes no reason, so put the justification in a comment above the ignore line.

## Worked Example
The end-to-end quality-gate pipeline built across the chapter, for a module bootstrapped from `cookiecutter gh:TerraformInDepth/terraform-module-cookiecutter` (which generates `.tflint.hcl`, `.checkov.yml`, `.pre-commit-config.yml`, `.terraform-docs.yml`, `.terraform-version`, `.opentofu-version`, `makefile`, ...):

1. **Makefile** — `.terraform:` target runs `init -backend=false` once (no `.PHONY`, so Make skips it when the directory exists); `test_validation: .terraform` → `$(TF_BINARY) validate`; `test_format` → `$(TF_BINARY) fmt -check -recursive`; `test_documentation` → `terraform-docs -c .terraform-docs.yml --output-check .`; `test_tflint` → `tflint --init && tflint`; `security: test_checkov test_trivy` → `checkov --directory . $(CHECKOV_OPTIONS)` + `trivy config .`; `chores: documentation format`; `install:` detects brew vs choco from package-list variables and maps to `install_brew`/`install_choco`.
2. **Locally** — `pre-commit install` runs those targets on every commit; `TF_ENGINE:=terraform` default overridable with `make test_validation TF_ENGINE=opentofu`.
3. **In CI** — one GitHub Actions workflow per make target (`tflint.yml`, `Validation`, ...), each `actions/checkout@v4` → setup action → `make test_X`; the Validation workflow adds the matrix so validation and formatting run against both engines across three versions, with `continue-on-error` for the experimental release.
4. **Gate** — branch protection requires checks passing and a non-author approval; Dependabot (`.github/dependabot.yml`, weekly, `github-actions` + `terraform` ecosystems; optional `terraform-registry` type block for private registries with token from `secrets.TERRAFORM_REGISTRY_API_TOKEN`, requiring the registry be network-reachable to GitHub — else self-hosted runners) keeps actions/modules fresh.

Result: a PR automatically reports format, validation, lint, docs, and both security scanners; humans review only security intent, consistency, and documentation.

## Key Takeaways
1. Automate every check you can and reserve code review for what scanners miss.
2. Bootstrap every project from a template (Cookiecutter + makefile) so quality tooling exists before day one and stays consistent between teams.
3. Route all tools through makefile targets driven by `TF_ENGINE`/`TF_BINARY` — the same commands then power pre-commit, CI, and dual-engine testing.
4. Run both free scanners (Checkov and Trivy); they overlap incompletely, and redundancy in security is free.
5. Custom policies: default to Checkov YAML policies (shared via a Git repo and `--external-checks-git`); use OPA/Rego through TFLint only if your team already knows OPA.
6. Enable branch protection as soon as a repo is in production: failing checks block merge, with a manual override for emergencies.
7. Configure Dependabot weekly for GitHub Actions and Terraform modules/providers, including private registries via tokens stored as secrets.

## Connects To
- **Ch 8**: CI is only half of "CI/CD" — registration, GitOps, and CD-platform policy enforcement (OPA at deploy time) are deliberately split out; secrets handling moves to OIDC/secrets managers.
- **Ch 9**: the `terratest` and `terraform_test` makefile stubs (with `TF_ENGINE` and matrix CI) get filled in there.
- **Ch 6**: `terraform init -backend=false` preserves existing backend config in developer workspaces.
- **SCM/GitOps**: the GitHub Actions + semantic-version tag model this chapter assumes is the substrate ch8's GitOps principles build on.
