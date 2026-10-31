# Chapter 11: Alternative interfaces

## Core Idea
Terraform is both a tool and a language, and it was deliberately built for machines as well as humans: you can wrap the CLI to drive it from any language (via JSON output and the machine-readable UI), you can generate configuration as JSON instead of HCL, and CDKTF shows both the power and the limits of writing IaC in ordinary programming languages.

## Frameworks Introduced
- **Wrapping a CLI**: building a library that calls the Terraform/OpenTofu binary, processes the output, and makes it available to the developer in their own language.
  - When to use: no SDK exists for Terraform, and teams want to run Terraform programmatically (deployment platforms, scanners, state analyzers).
  - How: two primary concerns — (1) actually running commands and handling errors, (2) parsing results into language-native data structures. Examples: Terragrunt, HCP Terraform, Spacelift, Env0, Atlantis, Checkov, Trivy.
- **Two machine-readable output flavors**:
  - **JSON output format**: single-response commands (`terraform show`, `validate`, `output`) return one high-level JSON object.
  - **Machine-readable UI**: streaming commands (`plan`, `apply`) emit **JSONL** — one JSON object per line — so results can be processed as they arrive. Both data structures are version controlled and documented; always check current docs for new fields.
- **The two-ways-to-read-state rule**: `terraform state pull` is the most complete structure (and has `serial`/`lineage`) but isn't part of the machine-readable UI; `terraform show` is machine-UI documented but misses `serial`/`lineage` — combine both for a complete picture.
- **JSON-instead-of-HCL format**: a `.tf.json` file is one JSON object whose top-level keys are HCL block types (`resource`, `data`, `variable`, `output`, `locals`, `module`, `provider`, `terraform`). You can mix HCL and JSON files in one project.
- **CDKTF pipeline**: your language → CDKTF library → `cdktf synth` → Terraform JSON → `cdktf deploy` → normal Terraform plan/apply, with all providers reached over gRPC underneath.

## Key Concepts
- **Machine-readable UI event line**: every JSONL event carries `@level` (info/error/warn), `@message`, `@module` (`tofu.ui`/`terraform.ui`), `@timestamp`, and the crucial `type` field (e.g. `version`, `diagnostic`, `outputs`, `change_summary`, `apply_start`) that determines the extra fields.
- **change_summary event**: an apply/plan's closing counts of added/changed/removed/imported items plus the operation type.
- **ChangeContainer vs Change**: a resource change is a documented wrapper (address, module_address, index, action_reason...) holding the actual `Change` (list of `actions`, `before`, `after`, `after_unknown`, `before_sensitive`/`after_sensitive`). `before`/`after` contain only *changed* attributes, despite documentation suggesting more.
- **TF_IN_AUTOMATION / TF_LOG**: environment variables every wrapper should set — automation mode stops interactive prompts; TF_LOG wires up log levels.
- **JSON generation rules**: expressions must be written as string templates (`"${upper(var.config)}"`, `%{ if ... }` directives — string logic only); keywords like `depends_on` become quoted strings; unkeyed repeated blocks (e.g. `provider` with aliases) become lists; comments use a `"//"` key.
- **CDKTF components**: a `cdktf` CLI plus per-language libraries; **apps, stacks, and resources** — resources map to resources/data sources, stacks are top-level modules with their own state, apps are collections of stacks that must call `app.synth()`.
- **Licenses when wrapping**: Terraform v1.6+ is not open source (BSL); tools built on this ecosystem may want OpenTofu, whose permissive license permits it.

## Mental Models
- Think of Terraform as deliberately two-faced: a human-facing HCL UI and a parallel machine-facing JSON UI, both supported and versioned.
- Think of a wrapper as a translation layer: run the binary in automation mode, catch JSONL events as they stream, feed typed handlers per event, and assemble a summary object from specific event types.
- Think of CDKTF as an abstraction layer stacked on an abstraction layer: your language → JSON → Terraform → gRPC → provider. Debugging means going through every layer.
- Think of Hafner's CDKTF skepticism as a concept-cost argument: "most of learning Terraform is not about the language but about the concepts" — state, testing, CI/CD pitfalls are identical under CDKTF, so switching languages buys adoption, not productivity.

## Anti-patterns
- **Generating HCL alongside CDKTF's JSON**: if HCL output exists when you run `cdktf deploy`, Terraform sees both defining the same blocks and errors; delete generated HCL (`cdktf.out`) before deploy.
- **Writing Terraform by hand in JSON**: "Humans should not write Terraform using JSON" — it exists for programmatic generation only.
- **Letting validation raise like a failed command**: a wrapper's `validate` call succeeds even when the configuration is invalid (return code 1 with diagnostics); suppress auto-raising and return the parsed object.
- **Blocking on stream results**: apply/plan can run long; process JSONL per line with generators/`event_handlers` rather than waiting for completion (or use `-skip-synth`-style round trips for nothing else).
- **Adopting CDKTF to save time**: its one major use case is developers who won't learn another IaC language; teams simply managing infrastructure are better served by HCL's richer ecosystem and fewer debug layers. CDKTF also doesn't support OpenTofu.

## Code Examples
```python
class Tofu:
    def _run(self, args: List[str], raise_on_error: bool = True) -> CommandResults:
        args = [self.binary_path] + [str(x) for x in args]
        results = subprocess.run(
            args,
            cwd=self.cwd,
            capture_output=True,
            encoding="utf-8",
            env={**os.environ, "TF_IN_AUTOMATION": "1", "TF_LOG": self.log_level, **self.env},
            timeout=None,
        )
        results = CommandResults(
            command=" ".join(args), stdout=results.stdout,
            stderr=results.stderr, returncode=results.returncode,
        )
        if raise_on_error and results.returncode != 0:
            results.raise_error()
        return results
```
- **What it demonstrates**: the minimal wrapper core — find the binary, run it in automation mode, wrap stdout/stderr/returncode, raise diagnostics-backed errors on failure.

```python
def plan(self, variables: Dict[str, str] = {}, plan_file: Path | None = None,
         event_handlers: Dict[str, Callable[[Dict[str, Any]], bool]] = {},
         extra_args: List[str] = []) -> Tuple[PlanLog, Plan | None]:
    try:
        temp_dir = None
        if not plan_file:                       # need a tfplan file to introspect
            temp_dir = tempfile.TemporaryDirectory()
            plan_file = Path(temp_dir.name) / "plan.tfplan"
        args = ["plan", "-json", "-out", str(plan_file)] + extra_args
        for key, value in variables.items():
            args += ["-var", f"{key}={value}"]
        output = []
        for event in self._run_stream(args):    # JSONL generator
            output.append(event)
            if event["type"] in event_handlers:
                event_handlers[event["type"]](event)
            if "all" in event_handlers:
                event_handlers["all"](event)
        plan_log = PlanLog(output)
        if plan_file.exists():
            show_res = self._run(["show", "-json", plan_file])
            return plan_log, Plan(show_res.json())
        return plan_log, None
    finally:
        if temp_dir: temp_dir.cleanup()
```
- **What it demonstrates**: the streaming plan method — always `-out` a plan file, feed event handlers live, then `show -json` the file for the full `Plan` structure.

## Reference Tables
| Interface | Read via | Shape | Key fields |
|---|---|---|---|
| state | `state pull` + `show -json file` | one JSON object | `values.root_module`, `values.outputs`, `serial`, `lineage`, `terraform_version` |
| plan | `plan -json -out` then `show -json` | stream log + full object | `resource_changes`, `resource_drift`, `output_changes`, `prior_state`, `planned_values`, `errored` |
| apply | `apply -json` | JSONL stream | `@level`, `@message`, `@module`, `@timestamp`, `type` |
| validate | `validate -json` | one JSON object | `valid`, `error_count`, `warning_count`, `diagnostics[]` |
| output | `output -json` | one JSON object | map of name → `{value, type, sensitive}` |

CDKTF mapping: Resource → HCL resource block; Stack → top-level module/workspace (own state); App → collection of stacks; `cdktf synth` → generated Terraform; `cdktf deploy` → plan + apply (re-synthesizes unless `--skip-synth`); `cdktf destroy` for teardown.

## Worked Example
The chapter builds **tofupy**, a Python wrapper library, end-to-end: a `Tofu` client class (cwd/binary/log_level/env) whose `_run` and `_run_stream` primitives power thin `init`, `validate`, `state` (pull + show combined for serial/lineage), `apply`, `plan`, and `output` methods; reusable dataclasses (`CommandResults`, `Diagnostic`, `Validate`, `State`/`Module`/`Resource`/`Output`, `Plan`, `ChangeContainer`/`Change`) keep parsing logic beside the data; pytest fixtures copy a test module (`terraform_data` + `http` data source + checks) into temp dirs; the payoff demo is a **Typer-based security scanner** that runs `init` + `plan` and flags `aws_vpc_security_group_ingress_rule` changes whose `after["cidr_ipv4"]` is `0.0.0.0/0` — the same pattern extends to cost estimation or policy gateways in chapter 8 pipelines.

## Key Takeaways
1. When a CLI lacks a library, wrap it: run the binary with `TF_IN_AUTOMATION=1`, capture stdout, and parse — then reuse one `_run` command runner for every wrapper method.
2. Pick the right output format: `show`/`validate`/`output` return single JSON objects; `plan`/`apply` stream JSONL you can react to live — and a full `Plan` requires `plan -out` plus `show -json`.
3. Reading state completely takes both commands: `state pull` for `serial`/`lineage`, `show -json` for the machine-UI structure.
4. With `plan.resource_changes` mapped to native objects, a tiny program becomes a policy engine — security, pricing, and compliance checks over proposed changes.
5. Generate Terraform as `.tf.json` only from code, treating every value as a string template, with `"//"` keys for provenance comments; never hand-edit generated files.
6. Use CDKTF when a team needs to author IaC in their own language (or build tooling that emits infrastructure), not to escape learning state management, testing, and CI/CD concepts.

## Connects To
- **Ch 8**: the security-scanner pattern slots into continuous delivery platforms as custom safeguards/policy gates.
- **Ch 6**: the state data structures here are the JSON representation of the state management covered in chapter 6.
- **Ch 5**: `Change`/`ChangeContainer` are the JSON twin of the plan's resource changes; wrapping is how you read plans programmatically.
- **OpenTofu**: tofupy deliberately works with both binaries; wrappers should default to tofu to stay on a permissively licensed engine.
- **Pulumi / Terragrunt**: real-world tools built with exactly these wrapping and generation techniques.