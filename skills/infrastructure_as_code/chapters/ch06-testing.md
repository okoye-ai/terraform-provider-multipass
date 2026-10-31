# Chapter 6: Testing

## Core Idea
Adapt the software test pyramid to infrastructure — mostly unit and contract tests at the bottom, few integration and end-to-end tests at the top — and choose which tests to write based on whether you are testing a module (factory/builder/prototype) or an environment configuration (singleton/composite).

## Frameworks Introduced
- **Infrastructure testing cycle**: define the configuration → run static analysis tests → apply changes to active infrastructure → run dynamic analysis tests.
  - When to use: structure every testing workflow around this loop.
  - How: static analysis verifies plaintext configuration before deployment (fail = fix or revert the commit); dynamic analysis verifies system functionality after applying changes (fail = fix configuration or revert the live system).
- **Test pyramid (adapted for infrastructure)**: guideline for test types, scope, and frequency; the higher the test type, the more time and money it costs. Wider level = write more of that type.
  - Levels from bottom to top: unit tests → contract tests → integration tests → end-to-end tests → manual tests (for unique configurations or devices where automation is impossible).
  - When to use: sizing how much of each test type to write; expect your real pyramid to be a rectangle or pear with missing levels.
  - How: never let it become a "test signpost" — many manual tests and little else.
- **Module-testing strategy** (factory, builder, or prototype patterns): run unit tests (formatting, standard configuration) → contract tests (module outputs match the input of the dependent module) → integration tests (create the module's resources in a module-testing environment, verify, delete).
  - When to use: any released module (ch 5's release workflow): test before tagging.
- **Configuration-testing strategy** (singleton or composite patterns for environments): run unit tests → integration tests (apply to a testing environment, verify resources still run) → end-to-end tests (verify the user workflow); repeat the same trio against production after deployment as quality control.
  - How: if configuration drifts between testing and production, the tests reflect it — enable or disable specific tests per environment.
- **Integration test create-vs-persist decision tree**: does the configuration/module depend on many other modules or resources? configure many resources? take time to configure? create low-level resources that others need?
  - No to first → create, test, delete. Yes to any of the last → create or update and test without deleting (persistent testing environment).
  - Rule: low-level modules (networks, DNS) → persistent, test in-place updates, avoid deleting; mid-level (workload orchestrators) → depends on size; high-level (application deployments, SaaS) → create and delete each run.

## Key Concepts
- **Static analysis**: verifies plaintext infrastructure configuration before deploying changes — no infrastructure resources needed, rollback is just reverting a commit.
- **Dynamic analysis**: verifies system functionality after applying changes to live infrastructure resources — an early-warning system for broken functionality.
- **Testing environment**: separate from production, used for testing infrastructure changes; its configuration should be as similar to production as possible, different from the application's development environment, and persistent (not created/destroyed per test).
- **Module-testing environment**: a separate environment (test account or project) for testing module changes; label test resources by module type, version, or commit hash to avoid conflicts, and track cost.
- **Test fixture**: a known configuration used to run a test, reflecting expected values, so tests don't copy-paste parsing logic.
- **Dry run**: previews IaC changes without deploying (e.g., `terraform plan -out=dry_run && terraform show -json dry_run > dry_run.json`; CloudFormation change sets; `kubectl --dry-run=client`) — parsing it is still static analysis.
- **Acceptance tests**: the IaC tool's own create/update/destroy tests that certify the tool works; don't duplicate them in your integration tests.
- **Smoke test**: a type of end-to-end test giving rapid feedback on whether a change has broken critical functionality before running more expensive tests.
- **Continuous tests**: run at regular, frequent intervals (monitoring of metrics, security events) to check that current values match expected thresholds; enable autoscaling and self-healing.
- **Regression tests**: run periodically over an extended period (weeks, months) to check configuration conforms to the expected state or functionality; mitigate configuration drift.

## Mental Models
- Use the test pyramid when allocating test types: unit and contract tests run in seconds at near-zero cost; end-to-end tests are the most expensive in time and resources, sometimes affordable only against production.
- Think of a good test as converting siloed knowledge the team should have: tests reflect the known knowns, monitoring tracks the known unknowns, observability debugs the unknown unknowns.
- Think of tests as living documentation of what to verify with every change; when a hidden bug appears, write a test for it.
- Use this filter before writing any test: "Do these tests inform me whether the system works? Do they run reliably enough to give me sufficient information?" Remove flaky tests — they erode confidence and indicate nothing.

## Anti-patterns
- **Relying heavily on mocks**: infrastructure providers change APIs frequently with complex errors and behaviors that mocks don't capture; prefer real (if small, temporary) resources.
- **Duplicating acceptance tests**: verifying every configuration parameter matches the live resource re-tests the tool instead of your configuration's dependencies.
- **The test signpost**: mostly manual tests — manual effort grows with every resource while automated tests' effort decreases as the system grows.
- **Create-and-destroy integration tests for low-level modules**: DNS and networks take long to create and are dependencies for everything; test updates in a persistent environment instead.
- **Flaky tests**: a test failing half the time provides no confidence; remove it.
- **Testing every parameter after deploy**: integration tests should verify that multiple resources work together with correct dependencies, not replicate the tool's acceptance suite.

## Code Examples
```python
# Listing 6.1 — unit tests: static analysis of a network factory module
import pytest
from main import NetworkFactoryModule

NETWORK_PREFIX = 'hello-world'
NETWORK_IP_RANGE = '10.0.0.0/16'

@pytest.fixture(scope="module")
def network():
   return NetworkFactoryModule(
       name=NETWORK_PREFIX,
       ip_range=NETWORK_IP_RANGE,
       number_of_subnets=3)

@pytest.fixture
def subnet_configuration(network):
   return network._subnet_configuration()['google_compute_subnetwork']

def test_configuration_for_network_name(network, network_configuration):
   assert network_configuration[network._network_name][
       0]['name'] == f"{NETWORK_PREFIX}-network"

def test_configuration_for_three_subnets(subnet_configuration):
   assert len(subnet_configuration) == 3

def test_configuration_for_subnet_ip_ranges(subnet_configuration):
   for i, subnet in enumerate(subnet_configuration):
       assert subnet[next(iter(subnet))
                     ][0]['ip_cidr_range'] == f"10.0.{i}.0/24"
```
- **What it demonstrates**: unit tests parse a module's generated configuration as objects (seconds to run, no infrastructure needed); fixtures hold the known configuration shared by tests.

```python
# Listing 6.3 — contract test: network module outputs satisfy the server's input
from network import NetworkFactoryModule, NetworkFacade
import pytest

network_name = 'hello-world'
network_cidr_range = '10.0.0.0/16'

@pytest.fixture
def network_outputs():
    network = NetworkFactoryModule(
        name=network_name,
        ip_range=network_cidr_range)
    return network.outputs()

def test_network_output_is_facade(network_outputs):
    assert isinstance(network_outputs, NetworkFacade)

def test_network_output_has_network_name(network_outputs):
    assert network_outputs._network == f"{network_name}-subnet"

def test_network_output_has_ip_cidr_range(network_outputs):
    assert network_outputs._ip_cidr_range == network_cidr_range
```
- **What it demonstrates**: contract tests enforce the facade/adapter contract between modules; write them in the high-level module so a low-level change is detected from the consumer's side first.

```python
# Listing 6.4 (trimmed) — integration test: deploy to a testing environment, verify, destroy
from libcloud.compute.types import NodeState
from main import generate_json, SERVER_CONFIGURATION_FILE
import os, pytest, subprocess, test_utils

TEST_SERVER_NAME = 'hello-world-test'

@pytest.fixture(scope='session')
def apply_changes():
   generate_json(TEST_SERVER_NAME)
   assert os.path.exists(SERVER_CONFIGURATION_FILE)
   assert test_utils.initialize() == 0
   yield test_utils.apply()
   assert test_utils.destroy() == 0
   os.remove(SERVER_CONFIGURATION_FILE)

def test_changes_should_add_1_resource(apply_changes):
   output = apply_changes[1].decode(encoding='utf-8').split('\n')
   assert 'Apply complete! Resources: 1 added, 0 changed, ' + \
      '0 destroyed' in output[-2]

def test_server_is_in_running_state(apply_changes):
   gcp_server = test_utils.get_server(TEST_SERVER_NAME)
   assert gcp_server.state == NodeState.RUNNING
```
- **What it demonstrates**: the integration test sequence — render configuration, deploy to infrastructure, verify via the provider's API, then delete the resources. An end-to-end test variant (listing 6.5) parses the service URL output and asserts `requests.get(url)` returns the expected page ("It's running!").

## Reference Tables

| Test type | Analysis | Runs against | Typical runtime | What it verifies |
|---|---|---|---|---|
| Unit | Static | Configuration/state files, no infrastructure | Seconds | Names, resource counts, IP ranges, logic (loops/conditionals), team standards |
| Contract | Static | Module inputs and outputs vs. expected values/format | Seconds | Facade/adapter agreement between dependent modules |
| Integration | Dynamic | Testing environment (create or persistent) | Minutes (provision time) | Changes applied successfully; resources exist and run; correct dependencies |
| End-to-end | Dynamic | Testing or production environment | Minutes | End-user workflow works (HTTP requests, job completion, connectivity) |
| Continuous (monitoring) | Dynamic | Production, at frequent intervals | Continuous | Metrics and security events stay within thresholds |
| Regression | Dynamic | Any environment, periodically | Weeks/months | Configuration conforms to expected state; catches drift/manual changes |

Testing strategy by IaC pattern (figure 6.18):

| Target | Pattern | Test combination |
|---|---|---|
| Module | Factory, builder, prototype | Unit → contract → integration |
| Environment configuration | Composite, singleton | Unit → integration → end-to-end (in testing environment, repeated in production) |

## Worked Example
Module release testing for the PostgreSQL 12 database module (tying ch 5's release workflow to tests):
1. Commit and push the module change; deploy to the module repo.
2. **Unit tests** run first: formatting and the team's standard configurations — fast feedback.
3. **Contract tests**: verify the database module's network ID input matches the network module's network ID output, catching dependency mismatches before deployment.
4. **Integration tests**: in an isolated module-testing environment (different account/project), stand up the network, create the database with the module, check it runs, then delete the test database.
5. Only then: tag the release v2.0.0, package the module, update documentation.

A contrasting environment-configuration change (singleton, resizing a server on a network): deploy to testing → unit tests → integration tests (server runs with new size) → end-to-end test (HTTP GET to the application endpoint) → deploy to production → repeat unit/integration/end-to-end there.

## Key Takeaways
1. Every change should pass static analysis before applying and dynamic analysis after; static analysis failures are fixed by editing or reverting commits, dynamic failures by reverting the system.
2. Write mostly unit and contract tests — they run in seconds and need no infrastructure; write few integration and end-to-end tests because they cost minutes and money.
3. Choose tests by IaC pattern: unit/contract/integration for modules (factory, builder, prototype); unit/integration/end-to-end for environment configurations (composite, singleton).
4. Contract tests guard facade and adapter outputs; put them in the high-level module so low-level changes are caught from the consumer first.
5. Run integration tests against a persistent testing environment for low-level, dependency-heavy resources; create-and-delete for high-level, self-contained ones. Keep modules small to keep integration tests fast.
6. Maintain a testing environment that mirrors production, is separate from the development environment, and persists.
7. Write a test whenever you learn something (turning unknown knowns into known knowns) and delete tests that are flaky or no longer informative.

## Connects To
- **Ch 4 (Patterns for infrastructure dependencies)**: contract tests enforce the facade and adapter contracts the dependency patterns establish.
- **Ch 5 (Structuring and sharing modules)**: the module-testing strategy (unit → contract → integration) is the testing stage of the module release workflow; module-testing environments isolate tests from production.
- **Ch 7 (Delivery pipelines and branching models)**: tests slot into delivery pipeline stages.
- **Ch 8 (Security and compliance)**: unit tests applied to secure and audit infrastructure configuration.
- **Ch 11 (Reverting failed changes)**: reverting to previously passing configurations after failed tests; testing in continuous infrastructure delivery.
- **Ch 12 (Cost of cloud computing)**: techniques for managing testing environment costs without mocks.
- **Software testing pyramid**: the chapter adapts the classic test pyramid to infrastructure tools and constraints.