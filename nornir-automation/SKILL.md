---
name: nornir-automation
description: Use for any Nornir-based network automation orchestration work. Triggers include "nornir", "nornir_napalm", "nornir_netmiko", "nornir_netconf", "nornir_jinja2", "nornir_utils", "InitNornir", "nr.filter", "nr.run(task=", "AggregatedResult", "MultiResult", "Result", "Task", "F filter", "SimpleInventory", "hosts.yaml groups.yaml defaults.yaml", "parallel network device automation in python", "fleet fan-out python framework", "task-based network orchestration", "inventory-driven network automation", "network automation runner". Covers the runner architecture (Nornir is the orchestrator, connections happen via NAPALM / Netmiko / NETCONF plugins), inventory model (SimpleInventory YAML inheritance; NetBox source-of-truth via nornir_netbox), task model (pure function Host -> Result; chained subtasks; severity_level aggregation), plugin ecosystem (nornir_napalm / nornir_netmiko / nornir_netconf / nornir_jinja2 / nornir_pyez / nornir_routeros / nornir_salt / nornir_ansible), concurrency knobs (num_workers; per-host failure isolation; never wrap in asyncio), F filter syntax (site=NYC AND role=spine; data-field filters; filter_func), configuration file shape (config.yaml with inventory / runner / logging / user_defined sections; ENV var overrides), result handling (print_result; custom processors; ServiceNow / Slack / S3 sinks), and the dry-run-first, diff-narrated, severity-sorted operational discipline. Self-authored from public Nornir documentation; no upstream third-party Claude skill exists. Apache-2.0.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# nornir-automation

Pure-Python network automation orchestration. Nornir is the runner; it does not connect to devices itself. Connections happen via plugins (`nornir_napalm`, `nornir_netmiko`, `nornir_netconf`, etc.). The value Nornir adds is inventory-driven parallel task execution with per-host failure isolation and structured results, all in idiomatic Python that you can debug, test, and version-control like any other Python project.

> **Skill marker**: When applying this skill, begin your reply with `[skill: nornir-automation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Nornir inventory, plugin choices, runner concurrency, and credential strategy before authoring tasks. Only ask the user for information not already covered or specific to this run.

Before authoring tasks, understand:

1. **Inventory and plugins**
   - Inventory source (SimpleInventory YAML, NetBoxInventory, custom plugin)?
   - Connection plugins (Netmiko, NAPALM, Scrapli, NETCONF)?
   - Filter strategy (groups, tags, hostname patterns)?

2. **Run shape**
   - Read-only collection, idempotent push, or destructive operation?
   - Concurrency target (default 20, or tuned per change blast radius)?
   - Result-handling expectations (Rich print, structured JSON, ELK / Loki sink)?

3. **Change context**
   - Maintenance window, change ticket, rollback plan?
   - Secrets path (Ansible Vault, Hashi Vault, env)?

---

## Iron rules

1. **Inventory is the source of truth.** Hosts, groups, defaults, and all per-host data live in `hosts.yaml` / `groups.yaml` / `defaults.yaml` (or a NetBox-backed inventory plugin). Tasks read from inventory; tasks do not invent inventory data.
2. **Tasks are pure functions of `Host -> Result`.** A task takes a `Task` object (which carries the host), does its work, and returns a `Result`. No global state, no module-level connection caches; the per-host concurrency model breaks if you reach for those.
3. **Concurrency via `num_workers`, never via asyncio or process pools.** Nornir uses a thread-pool runner by default; the default `num_workers` is 20. Tune up cautiously (device session limits, network device CPU); never wrap `nr.run()` inside `asyncio.run` or `multiprocessing.Pool`.
4. **Failures are per-host, not all-or-nothing.** A host failing inside a task does not abort the run; it is captured in the per-host `Result.failed`. The driver script decides whether to escalate; `print_result(diff_only=True)` surfaces what changed and what failed.
5. **Credentials come from the secret store, never from inventory YAML.** Use environment variables, vault lookups, or a secret-manager plugin; reference them from `defaults.yaml` via env-var indirection or a custom transform function. Plaintext credentials in inventory is a hard rule violation; see `secrets-hygiene`.
6. **Inventory loaders have NO side effects.** Loading the inventory must not connect to devices, hit external APIs that might fail, or mutate state. Inventory load is a read.
7. **Dry run before commit.** For any task that pushes config (NAPALM `napalm_configure`, Netmiko `netmiko_send_config`), run with `dry_run=True` first; print the diff via `print_result(diff_only=True)`; surface to the user via AskUserQuestion before re-running with `dry_run=False`. Per `multi-vendor-network-ops`, the 9-element response contract applies on production-impacting changes.

## What Nornir is (and is not)

| Nornir is | Nornir is not |
|---|---|
| A runner: an inventory plus a task-execution engine that fans out tasks across hosts in parallel. | A connection library. It does not know how to SSH or eAPI to a device on its own. |
| A Python framework. Tasks are Python functions. Inventory is loadable from YAML, JSON, NetBox, Ansible inventory, or custom plugins. | A YAML DSL like Ansible. There is no "playbook"; there are Python scripts that call `nr.run(task=...)`. |
| Vendor-agnostic via plugins. Same task code works against IOS / JunOS / EOS / PAN-OS / FortiOS via NAPALM and Netmiko plugins. | Stateful. Each task gets a fresh `Task` object per host; no implicit cross-host state. |
| Synchronous from the user's view. `nr.run()` blocks until all parallel workers complete. | Asynchronous. Do not wrap in asyncio; the threading model is the contract. |

## Inventory model

The default `SimpleInventory` plugin reads three YAML files:

```yaml
# hosts.yaml
r1.nyc.example.net:
  hostname: r1.nyc.example.net
  groups:
    - cisco-ios
    - nyc-spine
  data:
    site: NYC
    role: spine
    rack: A07

r2.lax.example.net:
  hostname: r2.lax.example.net
  groups:
    - juniper-junos
    - lax-leaf
  data:
    site: LAX
    role: leaf
    rack: B14
```

```yaml
# groups.yaml
cisco-ios:
  platform: ios            # NAPALM driver name OR Netmiko device_type
  port: 22
  connection_options:
    napalm:
      extras:
        optional_args:
          secret: __SECRET_FROM_VAULT__   # placeholder; resolve at load via transform
    netmiko:
      extras:
        secret: __SECRET_FROM_VAULT__

juniper-junos:
  platform: junos
  port: 22

nyc-spine:
  data:
    region: us-east
    change-window: "Mon 02:00-04:00 UTC"

lax-leaf:
  data:
    region: us-west
    change-window: "Wed 02:00-04:00 UTC"
```

```yaml
# defaults.yaml
username: __FROM_ENV__
password: __FROM_ENV__
data:
  ntp_servers:
    - 169.254.169.123
    - time.cloudflare.com
```

**Inheritance:** host data overrides group data overrides defaults. Multiple groups merge in the order they appear in `hosts.yaml`. The `connection_options` dict per group lets you tune NAPALM `optional_args`, Netmiko `device_type`, port, etc.

**NetBox as inventory** (production-grade): swap `SimpleInventory` for `NetBoxInventory2` (from `nornir_netbox`). Hosts, groups, and data come from NetBox device records, custom fields, and tags. Single source of truth for "what devices exist and what attributes they have"; Nornir consumes it.

**Other inventory plugins:** `AnsibleInventory` (read existing Ansible inventories), `NautobotInventory`, `NMAPDiscovery`, custom plugin via the `InventoryPluginRegister` hook.

## Task model

```python
from nornir import InitNornir
from nornir.core.task import Task, Result
from nornir_napalm.plugins.tasks import napalm_get, napalm_configure
from nornir_utils.plugins.functions import print_result

def show_version_and_uptime(task: Task) -> Result:
    facts = task.run(task=napalm_get, getters=["get_facts"])
    f = facts.result["get_facts"]
    return Result(
        host=task.host,
        result=f"{f['hostname']} | {f['os_version']} | uptime={f['uptime']}s",
    )

nr = InitNornir(config_file="config.yaml")
result = nr.run(task=show_version_and_uptime)
print_result(result)
```

**Key shapes:**

- `Task` carries `task.host` (the target), `task.nornir` (the orchestrator), and lets you call `task.run(task=other_fn)` to execute a subtask. Subtasks are part of the same per-host execution and roll up into the parent `MultiResult`.
- `Result` carries `host`, `result` (the payload), `changed` (bool), `failed` (bool), `diff` (string for change tasks), `severity_level` (logging level for the result; `INFO` default, `WARN` / `ERROR` escalates).
- `AggregatedResult` is the per-run dict-like result keyed by hostname, returned by `nr.run()`. Each value is a `MultiResult` (a list of `Result` objects, one per task or subtask).

## Plugin ecosystem

| Plugin package | Purpose |
|---|---|
| `nornir_napalm` | NAPALM tasks: `napalm_get`, `napalm_configure`, `napalm_cli`, `napalm_validate`, `napalm_ping`. |
| `nornir_netmiko` | Netmiko tasks: `netmiko_send_command`, `netmiko_send_config`, `netmiko_save_config`, `netmiko_file_transfer`. |
| `nornir_netconf` | NETCONF tasks: `netconf_get`, `netconf_get_config`, `netconf_edit_config`, `netconf_lock`, `netconf_unlock`. |
| `nornir_jinja2` | Jinja2 rendering: `template_file`, `template_string`. Pair with `napalm_configure` for templated config push. |
| `nornir_utils` | `print_result`, `print_title`, `load_yaml`, `load_json`, `write_file`, `echo_data` (debug). |
| `nornir_pyez` | Junos PyEZ tasks; finer-grained Junos control than NAPALM. |
| `nornir_routeros` | MikroTik RouterOS API tasks. |
| `nornir_f5` | F5 BIG-IP iControl REST tasks. |
| `nornir_pyntc` | PyNTC tasks (multi-vendor; thin alternative to NAPALM). |
| `nornir_salt` | Bridge Nornir into SaltStack (use Nornir as the executor for Salt-managed devices). |
| `nornir_ansible` | Read Ansible inventory; run Nornir tasks against the same fleet. Useful during migration. |
| `nornir_pyats` | Bridge to pyATS / Genie testbed for Cisco-heavy fleets. |

## Concurrency model

```yaml
# config.yaml
inventory:
  plugin: SimpleInventory
  options:
    host_file: "inventory/hosts.yaml"
    group_file: "inventory/groups.yaml"
    defaults_file: "inventory/defaults.yaml"

runner:
  plugin: threaded
  options:
    num_workers: 20

logging:
  enabled: true
  level: INFO
  to_console: true
  log_file: nornir.log
```

- Default runner is `threaded` with `num_workers: 20`. Bump up to 50 to 100 for large read-only fleets; bump DOWN to 5 to 10 for production change runs (TACACS rate limits, device CPU spikes, change-window blast control).
- `runners.serial` (alternative): one host at a time, sequential. Useful for change runs that absolutely must be sequential (cluster member upgrades; ring topology rollouts).
- Per-host failure isolation: a host that times out or fails inside a task captures the exception in `Result.failed`; the run continues for other hosts. Read `result[host].failed` and `result[host][0].exception` to triage.
- Severity-sorted aggregation: tasks set `severity_level=logging.WARN` on degraded outputs (e.g. interface error counters above threshold); `print_result` colour-codes accordingly.
- **Never** wrap Nornir runs in `asyncio.run`. The runner is threaded; mixing event loops with the underlying NAPALM / Netmiko paramiko calls produces obscure deadlocks. If you need concurrency primitives Nornir does not give you, the right answer is usually a custom runner plugin or a higher-level orchestrator (Airflow, Prefect) calling Nornir.

## Filtering (the F filter)

```python
from nornir.core.filter import F

# All Cisco IOS spines in NYC
spines_nyc = nr.filter(F(groups__contains="cisco-ios") & F(site="NYC") & F(role="spine"))

# Everything in us-east region except devices tagged 'maintenance'
us_east_active = nr.filter(F(region="us-east") & ~F(tags__contains="maintenance"))

# Custom filter function for complex predicates
def is_ready_for_change(host):
    return host.data.get("change-window") and not host.data.get("frozen", False)

ready = nr.filter(filter_func=is_ready_for_change)
```

`F` supports `__contains`, `__startswith`, `__endswith`, `__eq` (default), and Python operators `&` `|` `~`. Filter on any host attribute (hostname, port, platform, groups) or any data-dict key. `filter_func` takes any callable for predicates the F syntax cannot express.

## Worked example: parallel show across the fleet

```python
from nornir import InitNornir
from nornir_napalm.plugins.tasks import napalm_get
from nornir_utils.plugins.functions import print_result
from nornir.core.filter import F
import logging

nr = InitNornir(config_file="config.yaml")

# Filter to managed production devices in us-east
target = nr.filter(F(env="prod") & F(region="us-east"))

result = target.run(
    task=napalm_get,
    getters=["get_facts", "get_interfaces", "get_bgp_neighbors"],
)

# Surface failures first
failed_hosts = [h for h, r in result.items() if r.failed]
if failed_hosts:
    logging.error("failures: %s", failed_hosts)
    for h in failed_hosts:
        logging.error("%s exception: %s", h, result[h][0].exception)

print_result(result, severity_level=logging.WARN)
```

200 devices, ~20 seconds total wall time at `num_workers=20` (assuming healthy SSH paths). Each host's per-task timing is captured in the `Result` object.

## Worked example: idempotent config push with diff narration

```python
from nornir import InitNornir
from nornir.core.task import Task, Result
from nornir_napalm.plugins.tasks import napalm_get, napalm_configure
from nornir_utils.plugins.functions import print_result
import logging

def push_ntp_config(task: Task) -> Result:
    # 1. Capture pre-change baseline (always; even though NAPALM has rollback).
    pre = task.run(
        task=napalm_get,
        getters=["get_config"],
        retrieve="running",
        sanitized=False,
        severity_level=logging.DEBUG,
    )

    # 2. Render desired config from inventory data.
    ntp_servers = task.host.get("ntp_servers", [])
    config_block = "no ntp server\n" + "\n".join(f"ntp server {s}" for s in ntp_servers)

    # 3. Push as MERGE (additive); compare_config is implicit.
    return task.run(
        task=napalm_configure,
        configuration=config_block,
        replace=False,
        dry_run=task.host.get("dry_run", True),  # default dry-run; override per-host or globally
    )

nr = InitNornir(config_file="config.yaml")
target = nr.filter(F(role="spine") & F(env="prod"))

# Phase 1: dry run
result = target.run(task=push_ntp_config)
print_result(result, vars=["diff"])

# AskUserQuestion-equivalent gate goes here in a real script:
# proceed = input("Apply? [y/N] ")
# if proceed.lower() != "y": exit(1)

# Phase 2: apply
nr.inventory.defaults.data["dry_run"] = False
result = target.run(task=push_ntp_config)
print_result(result, vars=["changed", "diff"])
```

## Result handling

- `print_result(result)`: default; prints all task results per host, colour-coded by severity.
- `print_result(result, vars=["diff"])`: only show the diff field (config-push case).
- `print_result(result, severity_level=logging.WARN)`: only show results at WARN or above (focus on failures + degraded states).
- `print_result(result, failed=True)`: only show failed hosts.
- **Custom processors:** subclass `nornir.core.processor.Processor`; hook `task_started`, `task_completed`, `task_instance_started`, `task_instance_completed`, `subtask_instance_started`, `subtask_instance_completed`. Use to push results to ServiceNow / Slack / S3 / Splunk / Datadog mid-run.

```python
from nornir.core.processor import Processor

class SlackProcessor(Processor):
    def task_completed(self, task, result):
        failed = sum(1 for r in result.values() if r.failed)
        post_to_slack(f"task {task.name}: {len(result)} hosts, {failed} failed")

nr.with_processors([SlackProcessor()]).run(task=...)
```

## Configuration file shape

```yaml
# config.yaml: full reference
inventory:
  plugin: SimpleInventory          # or NetBoxInventory2, NautobotInventory, AnsibleInventory
  options:
    host_file: "inventory/hosts.yaml"
    group_file: "inventory/groups.yaml"
    defaults_file: "inventory/defaults.yaml"
  transform_function: "myscripts.transforms.resolve_secrets"
  transform_function_options:
    secret_store: "vault"

runner:
  plugin: threaded                  # or serial, or a custom plugin
  options:
    num_workers: 20

logging:
  enabled: true
  level: INFO                       # DEBUG / INFO / WARN / ERROR
  to_console: true
  log_file: nornir.log

user_defined:
  change_id: SCTASK0012345          # surface in custom processor for ServiceNow integration
  operator: opsbot
```

**ENV var overrides:** any config key can be overridden via `NORNIR_<SECTION>_<OPTION>` env var (e.g. `NORNIR_RUNNER_OPTIONS_NUM_WORKERS=10`). Useful for CI / dry-run flags.

## Logging

Nornir uses Python's standard logging. Per-task log scope is per-host; the structured logger captures `host`, `task`, and the result. Common pattern: ship `nornir.log` to Graylog / Splunk via filebeat; tag with `change_id` from `user_defined`. See `graylog-log-investigation` for log-side discipline.

## Testing

```python
import pytest
from nornir import InitNornir

@pytest.fixture
def mock_nr(tmp_path):
    # Point at a fixture inventory with one fake host
    config = tmp_path / "config.yaml"
    config.write_text("""
inventory:
  plugin: SimpleInventory
  options:
    host_file: tests/fixtures/hosts.yaml
    group_file: tests/fixtures/groups.yaml
    defaults_file: tests/fixtures/defaults.yaml
runner:
  plugin: serial
""")
    return InitNornir(config_file=str(config))

def test_my_task_returns_expected(mock_nr, mocker):
    # Mock the device-side library calls
    mocker.patch("nornir_napalm.plugins.tasks.napalm_get", return_value=...)
    result = mock_nr.run(task=my_task_module.show_version_and_uptime)
    assert result["fake-host"][0].result == "fake-host | 17.6.5 | uptime=12345s"
```

`runners.serial` in tests gives deterministic per-host ordering. Mock the plugin tasks (NAPALM, Netmiko) at the module boundary, not inside Nornir.

## Common pitfalls

1. Module-level connection caches inside tasks. Tasks must be re-entrant per host; use `task.host.connections` if you need to share within a per-host run.
2. `num_workers` set to a value the device infrastructure cannot support. Survey device session limits; TACACS / RADIUS rate limits; AAA log volume.
3. Inventory inheritance surprises: a `defaults.yaml` field appears unset because a group or host overrides it with `null`. Read the merged inventory via `nr.inventory.dict()` to debug.
4. F filter typos silently match nothing. `nr.filter(F(role="spinne"))` returns an empty filter; the run is a no-op. Always assert the filter count: `assert len(target.inventory.hosts) > 0`.
5. Forgetting `print_result`. The `AggregatedResult` object's repr is uninformative; you need `print_result` (or a custom processor) to see what happened.
6. Assuming the task receives a connection. Tasks receive `task.host`; the connection is opened lazily by the underlying plugin. If you need fine-grained connection control, use `task.host.get_connection("napalm", task.nornir.config)`.
7. Long-running tasks blocking the worker pool. A 5-minute task at `num_workers=20` blocks the pool; subsequent host work waits. Keep tasks bounded; spawn long-running work as separate runs.
8. Not handling `MultiResult` / `SubTaskResult` shape. `result[host]` is a list; `result[host][0]` is the parent task; `result[host][1:]` are subtasks. Iterate, do not assume index.
9. Assuming Nornir retries. It does not. Wrap `task.run()` in your own retry-with-backoff if needed; do not retry inside the task body without an exit condition.
10. Running against production inventory by default. Two-environment pattern: `inventory/dev/` and `inventory/prod/`; CI defaults to dev; `NORNIR_INVENTORY_OPTIONS_HOST_FILE` env var swaps to prod with explicit operator awareness.

## Cross-references

- `napalm-netmiko`: parent transport; Nornir's NAPALM and Netmiko plugins drive these libraries in parallel.
- `multi-vendor-network-ops`: umbrella; this skill is the orchestration layer underneath the diagnose-first methodology; the 9-element response contract applies on production-impacting Nornir runs.
- `pyats-network-automation`: Cisco-fleet alternative for fleet automation with structured Genie parsing.
- `ansible-network-modules`: declarative alternative; YAML-first; better fit for change-managed environments where Python code review is heavier than playbook review.
- `bgp-analysis` / `igp-routing-analysis`: protocol-depth specialists; Nornir tasks that wrap NAPALM `get_bgp_neighbors` / `get_route_to` feed their decision trees.
- `acl-rule-analysis`: when the change is an ACL push, the audit discipline lives there.
- `secrets-hygiene`: credential sourcing; never plaintext in `inventory/*.yaml`; transform function resolves at load.
- `systematic-debugging`: Phase 1 boundary evidence often comes from a Nornir parallel-getter run.
- `completion-gate` Layer 3: post-deploy verification gate; re-run the read-only Nornir task after a change.
- `plan-time-tooling`: production fleet runs fire `engineering:deploy-checklist`; new orchestration framework choice fires `engineering:architecture`.
- `bash-defensive`: wrapper scripts that invoke `python -m my_runner` follow defensive-bash discipline.
- `graylog-log-investigation`: `nornir.log` shipped to Graylog; structured search across runs.

## Red flags (stop and ASK before)

1. About to push to more than 50 devices without a `dry_run=True` phase first.
2. About to load inventory containing plaintext credentials (any literal `password: changeme` or API key in `*.yaml`).
3. About to use Nornir 2.x API in a Nornir 3.x codebase (the `Nornir` constructor signature changed; many tutorials online still show 2.x).
4. About to nest `ThreadPoolExecutor` or `multiprocessing.Pool` around `nr.run()`. The runner is the concurrency model; do not wrap it.
5. About to disable `severity_level` handling in `print_result`; degraded states will hide in green output.
6. About to swallow `ConnectionException` per-host inside a task without surfacing in the `Result.failed` field; the aggregated report becomes a lie.
7. About to commit a change run without a `print_result(diff_only=True)` narration captured in the conversation.
8. About to deploy a filter that matches more devices than intended (run with `--list-hosts` style assertion first; `len(target.inventory.hosts)` should match expectation before the run).
9. About to run as `root` on the orchestration host. Use a service account; SSH keys for the service account live in the secret store.
10. About to use `nr.run()` synchronously inside an async framework (FastAPI, asyncio orchestrator); deadlocks are subtle. Either offload to a background worker, or use a sync framework.

## Bottom line

Nornir is the runner that turns "for each device, do this" into a parallel, inventory-driven, structured-result Python program. Use NAPALM and Netmiko (via `nornir_napalm` / `nornir_netmiko`) for transport; use `F` filters to scope the run; capture results in `AggregatedResult` and surface via `print_result` or a custom processor. Always dry-run before commit on change tasks; always source credentials from the secret store; never wrap in asyncio. For Cisco-only fleets where structured parsing matters more than vendor breadth, `pyats-network-automation` is an alternative; for declarative paradigms with change-management workflows, `ansible-network-modules` is the alternative.
