# Chapter 11: Fixing Failures

## Core Idea
IaC has no true rollback — because of immutability you never restore a previous state, you *roll forward*: first stabilize by reverting or replacing to a working state, then troubleshoot systematically through three causes (drift, dependencies, differences), then fix incrementally before re-implementing the original change.

## Frameworks Introduced
- **Rolling forward**: reverting changes to a system and using immutability to return it to a working state — a forward-moving undo, not a restore.
  - When to use: a pushed change breaks the system and you need functionality back fast.
  - How: `git revert <commit>` (not `git reset`/manual console edits), push through the pipeline to testing, confirm the service recovers, then promote to production.
- **Roll forward with new changes** (canary / new environment): when a revert doesn't fix the system, deploy a new instance or environment with the fix and shift traffic using canary deployment; disable the failed environment for debugging.
  - When to use: irrecoverable changes, data corruption risk, or changes so tangled that reverting makes things worse.
  - How: reproducing environments with IaC + immutability makes creating a v2 cheaper than repairing v1.
- **IaC troubleshooting checklist** (the three causes of failed changes — Figure 11.8):
  1. **Check for drift**: does IaC match the live resource state? Run a dry run and compare actual attached permissions/attributes. Eliminate drift that could contribute — but note drift may be unrelated to the failure.
  2. **Check for dependencies**: graph what depends on the updated resource; compare expected vs. actual dependencies (e.g., a server attached to a service account's email). Unexpected dependencies — especially *indirect* ones via a proxy — disrupt change behavior.
  3. **Check for differences between environments**: reconciling what changed in testing vs. production catches break-glass emergency changes that one environment applied and the other never got.
- **Incremental fixes**: breaking repairs into smaller parts to gradually improve a system and prevent future failure.
  - When to use: every fix after troubleshooting; never push a batch of fixes, because you won't be able to attribute a new failure.
  - How: fix drift first, then reconcile environments, then re-implement the original change — one commit, one concern at a time.

## Key Concepts
- **Rolling forward**: reverting changes and relying on immutability so the system reaches a *new* working state matching the previous one, rather than restoring an old state.
- **Immutability**: IaC creates new state on every change, which is precisely why rollback-as-restore is impossible and roll-forward is the model.
- **Drift**: divergence between configuration and active resource state (from manual/break-glass changes or default value updates); check and eliminate it early in troubleshooting.
- **Unexpected dependency**: a dependency that exists at runtime but not in your mental model or configuration graph — the most common hidden failure source.
- **Break-glass change**: an emergency manual change outside IaC; it produces environment differences and drift that later break otherwise-valid changes.
- **Incremental fixes**: staged, small repairs that localize each failure and minimize the blast radius of repair work.
- **Least-privilege access**: the security goal driving the change; a failed tightening must be re-landed as the *minimum* permission, not the original broad one.
- **Reconciling drift**: reconstructing manual changes as IaC (rebuilding commands from command history/package lists) and committing them to code.

## Mental Models
- "Rollback" is a fiction: think of every IaC revert as **a new commit that moves forward** — `git revert` is a forward-moving undo.
- Use the **three D's for root cause**: drift (code vs. state), dependencies (who references this resource), differences (testing vs. production). Work them in that order.
- A bandage restores functionality; only IaC-tracked incremental repairs **promote long-term system healing** — manual console fixes fall off quickly and leave the system less understood.
- Think of a failed tightening as **a dependency you couldn't see**: something (a proxy, a script) was silently exercising the broad permission.

## Anti-patterns
- **Logging into the cloud console to manually "fix" the failure**: it's a bandage that produces drift and future failed changes; fix through IaC and pipelines.
- **Batching multiple repair changes in one push**: makes it impossible to identify which change caused the next failure.
- **Assuming a testing-environment pass means production safety**: a break-glass change in production (e.g., an auth proxy installed by hand) hides the difference until production fails.
- **Re-implementing the original change before reconciling drift and environment differences**: your test bed is inaccurate, so any verdict it gives you is noise.
- **Treating any detected drift as the root cause**: drift can be incidental; investigate whether it affects functionality before "fixing" it.
- **Deleting the broken resource and recreating it by default**: some resources carry state/data or unexpected dependencies.

## Code Examples
```python
def _startup_script(self):
    proxy_download = 'https://dl.google.com/cloudsql/' + \
        'cloud_sql_proxy.linux.amd64'
    exec_start = '/usr/local/bin/cloud_sql_proxy ' + \
        '-instances=${google_sql_database_instance.' + \
        f'{self._environment}.connection_name}}=tcp:3306'
    return f"""#!/bin/bash
wget {proxy_download} -O /usr/local/bin/cloud_sql_proxy
chmod +x /usr/local/bin/cloud_sql_proxy
cat << EOF > /usr/lib/systemd/system/cloudsqlproxy.service
[Install]
WantedBy=multi-user.target
[Unit]
Description=Google Cloud Compute Engine SQL Proxy
Requires=networking.service
After=networking.service
[Service]
Type=simple
WorkingDirectory=/usr/local/bin
ExecStart={exec_start}
Restart=always
StandardOutput=journal
User=root
EOF
systemctl daemon-reload
systemctl start cloudsqlproxy
"""
```
- **What it demonstrates**: reconciling drift — a startup script that reconstructs the break-glass installation of the Cloud SQL Auth proxy as IaC so testing matches production. (Sidebar: prefer a configuration manager or image builder over a startup script in real systems; in AWS use `user_data`, in Azure `custom_data`.)

```python
SERVICE = 'promotions'
ENVIRONMENT = 'prod'
REGION = 'us-central1'
ZONE = 'us-central1-a'
PROJECT = os.environ['CLOUDSDK_CORE_PROJECT']
role = 'roles/cloudsql.client'

if __name__ == "__main__":
   resources = {
       'resource':
           network.Module(SERVICE, ENVIRONMENT, REGION).build() +
           iam.Module(SERVICE, ENVIRONMENT, REGION, PROJECT,
                      role).build() +
           database.Module(SERVICE, ENVIRONMENT, REGION).build() +
           server.Module(SERVICE, ENVIRONMENT, ZONE).build()
   }
```
- **What it demonstrates**: the re-implemented original change after troubleshooting — swapping `roles/cloudsql.admin` for the minimal `roles/cloudsql.client` (enough to list and connect to instances) once testing genuinely mirrors production.

## Reference Tables
| Troubleshooting step | Question it answers | Failure it uncovers |
|---|---|---|
| 1. Check for drift | Does IaC match the live resource state? | Manual changes / default-value divergence |
| 2. Check for dependencies | Do known resources depend on the updated one — any unexpected ones? | Hidden consumers (e.g., an auth proxy) |
| 3. Check environment differences | Do testing and production configuration match? | Break-glass changes applied to only one environment |

| Repair order (incremental fixes) | Action | Rationale |
|---|---|---|
| 1 | Roll forward restore (revert or canary to new env) | Get the system working before root-causing |
| 2 | Reconcile drift (rebuild manual changes as IaC) | Accurate code → accurate testing |
| 3 | Reconcile environment differences | Testing must predict production |
| 4 | Re-implement the original change (minimal permissions) | Now failures surface in testing, not production |

## Worked Example
A change removes `roles/cloudsql.admin` from the promotions service account (a least-privilege task), and an hour later the promotions application cannot reach its database. **Restore**: `git revert a3119fc` re-adds the permission; the pipeline restores service. **Troubleshoot**: (1) drift — both IaC and the live GCP policy show only `roles/cloudsql.admin`, so no drift; (2) dependencies — the server references the service account email, but the app appears to use database IP/user/password directly... deeper debugging reveals the app connects to *localhost* through the **Cloud SQL Auth proxy**, whose own service-account credentials need database access: an indirect, unexpected dependency; (3) differences — testing connects directly to the DB by IP, because the team made an emergency production-only change to install the proxy and never replicated it. **Fix incrementally**: first rebuild the proxy installation as a server startup script in testing IaC (commit d81) and keep `roles/cloudsql.admin` (the proxy needs it); then have the promotions team adopt proxy-based config in testing, verify end-to-end, and push to production; only then commit (fa3) the real change replacing `roles/cloudsql.admin` with `roles/cloudsql.client`, which now passes testing truthfully and lands safely.

## Key Takeaways
1. Stabilize first, diagnose second: revert (or cut traffic to a new environment) to a working state before root-causing.
2. Rollback in IaC always means rolling forward a new state — use `git revert` and the pipeline, never console changes.
3. When reverting can't help (data, irrecoverable resources), roll forward a replacement environment with canary traffic shifting.
4. Run the three D's in order: drift, dependencies, differences between environments — most IaC failures hide in one of them.
5. Watch for indirect dependencies: infrastructure (proxies, sidecars) often needs the permission your application no longer visibly uses.
6. Fix incrementally and in sequence — drift, then environments, then the original change — so testing stays trustworthy.
7. A failed change in production that passed testing usually means the environments differ, not that your change was wrong.

## Connects To
- **Ch 9 (change techniques)**: canary and blue-green deployments are the roll-forward tools for unrecoverable changes.
- **Ch 7 (GitOps, small commits, no break-glass changes)**: batching and manual fixes are exactly what those practices exist to prevent.
- **Ch 10 (refactoring/refactor patterns)**: environment reconciliation is a refactor; refactoring failures route back here.
- **Ch 2 (migrating to IaC, idempotency, source of truth)**: reconciling drift is re-applying the migration workflow.
- **Ch 8 (least privilege)**: the original change was a security tightening, re-landed as `roles/cloudsql.client`.
- **Cloud SQL Auth proxy / Amazon RDS Proxy / Azure Private Link**: provider-side equivalents of the hidden dependency in the walkthrough.