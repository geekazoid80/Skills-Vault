---
name: napalm-netmiko
description: Use for any multi-vendor network device automation work that uses NAPALM, Netmiko, or both. Triggers include "napalm", "netmiko", "ConnectHandler", "send_command", "send_config_set", "device_type", "napalm get_facts", "napalm load_replace_candidate", "napalm load_merge_candidate", "compare_config", "commit_config", "discard_config", "ssh to a network device from python", "multi-vendor device library", "vendor-agnostic config push", "automate cisco / juniper / arista / panos with python (no ansible)", "transport layer for network automation", "network device CLI scraping". Covers the NAPALM driver model with idempotent replace and merge config pushes, the Netmiko transport with send_command and send_config_set, per-vendor quirks (Cisco IOS / IOS-XE / NX-OS / IOS-XR / ASA, JunOS, EOS, PANOS, FortiOS, F5, Linux), authentication patterns sourced from secrets-hygiene rather than YAML, single-threaded concurrency caveat (use nornir-automation for parallel fan-out), error handling (NetMikoTimeoutException, NetMikoAuthenticationException, NAPALMException family), and the diagnose-first, read-only-getter-before-state-change discipline. Self-authored from public NAPALM and Netmiko documentation; no upstream third-party Claude skill exists for either tool. Customised body, Apache-2.0.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# napalm-netmiko

Multi-vendor network device automation in Python. Two libraries, one skill, because the decision is rarely "one or the other"; most fleets use Netmiko as the SSH transport and NAPALM as the abstraction over getters and config push, with NAPALM internally driving Netmiko on platforms where there is no native API.

> **Skill marker**: When applying this skill, begin your reply with `[skill: napalm-netmiko]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the automation estate (target vendors, driver choices, credential vaulting, run-mode conventions) before scripting. Only ask the user for information not already covered or specific to this task.

Before scripting, understand:

1. **Target estate**
   - Vendor(s) and OS version(s) (NAPALM driver supported, or Netmiko-only)?
   - Read-only getter, config diff / replace, or destructive push?
   - Single device, batched fleet, or rolling change?

2. **Library and dependencies**
   - NAPALM and Netmiko versions pinned?
   - Connection method (SSH, telnet legacy, NETCONF for JunOS / IOS-XR)?
   - Existing wrapper or orchestrator (Nornir, custom CLI)?

3. **Change posture**
   - Maintenance window and rollback plan?
   - Pre / post evidence the reviewer will expect?
   - Secrets path (env, Vault, runbook-specific)?

---

## Iron rules

1. **Diagnose-first, read-only before state-change.** Every interaction starts with a NAPALM getter (`get_facts`, `get_interfaces_counters`, `get_config`) or a Netmiko `send_command("show ...")` to capture baseline evidence BEFORE any `load_replace_candidate` or `send_config_set`. Never push config without a prior `compare_config` diff narrated to the user.
2. **Credentials from the secret store, never from YAML or inline.** `username` and `password` keys come from environment, vault, AWS Secrets Manager, HashiCorp Vault, or the platform's secret store. Testbed YAML and inventory files contain references, not values. See `secrets-hygiene`.
3. **Single connection at a time per device.** NAPALM and Netmiko are synchronous and single-threaded. For fleet fan-out (more than one device in flight) use `nornir-automation` or `pyats-network-automation`. Do not spawn ad-hoc threads around `ConnectHandler`; the libraries are not thread-safe per-device.
4. **NAPALM `load_replace_candidate` is destructive by default.** It uploads a full candidate config and replaces running on commit. Always run `compare_config` first; surface the diff via AskUserQuestion for any production device before `commit_config`. `discard_config` if the diff is wrong.
5. **Netmiko `send_command_timing` over `send_command` for prompts that change mid-session** (banner accepts, paging confirmations, `wr mem` Y/N, `reload` at?). `send_command` waits for the device prompt regex to return; if the prompt has changed the call hangs to the read timeout.
6. **Always close the connection.** Use a `with` context manager for Netmiko (`ConnectHandler`) or call `device.close()` for NAPALM in a `finally` block. Leaked sessions hold VTY lines and exhaust device session limits (Cisco IOS defaults to 5).
7. **No state-changing command without rollback.** NAPALM has `rollback()` (Junos and IOS-XR have native rollback; on IOS / NX-OS / EOS NAPALM emulates it via the previous config snapshot). Netmiko has no rollback; capture the pre-change config explicitly via `send_command("show running-config")` and store it before the change.

## When to use NAPALM vs Netmiko vs both

| Scenario | Pick | Why |
|---|---|---|
| Read-only inventory across multi-vendor fleet | **NAPALM** | Normalised getter outputs (same dict shape across IOS / JunOS / EOS); useful for ingest into NetBox / CMDB. |
| Config push with diff and rollback | **NAPALM** | `load_replace_candidate` + `compare_config` + `commit_config` + `rollback` is the canonical idempotent pattern. |
| One-off `show` command with vendor-specific output | **Netmiko** | NAPALM normalises away vendor detail; raw Netmiko returns the unmodified CLI output. |
| Bespoke interactive workflow (`copy ftp:` with prompts, ROMmon recovery) | **Netmiko** | NAPALM is contract-driven; Netmiko exposes the raw session for prompt-by-prompt control via `send_command_timing` and `read_until_pattern`. |
| Vendor not supported by NAPALM (FortiOS, F5, Aruba, MikroTik, etc.) | **Netmiko** | Netmiko's `device_type` registry covers ~80 platforms; NAPALM's first-party drivers cover ~6. |
| Idempotent multi-vendor change automation | **NAPALM (driving Netmiko underneath)** | NAPALM IOS / NX-OS / EOS drivers use Netmiko as transport; you get the abstraction without losing the SSH path. |

## NAPALM driver model

```python
from napalm import get_network_driver

driver = get_network_driver("ios")           # or "iosxr", "nxos", "junos", "eos", "panos"
device = driver(
    hostname="r1.example.net",
    username=os.environ["NETOPS_USER"],
    password=os.environ["NETOPS_PASS"],
    optional_args={"port": 22, "transport": "ssh", "secret": os.environ["NETOPS_ENABLE"]},
)
device.open()
try:
    facts = device.get_facts()
    interfaces = device.get_interfaces()
finally:
    device.close()
```

First-party drivers (commit-supported): `ios`, `iosxr`, `nxos`, `nxos_ssh`, `junos`, `eos`, `panos`. Community drivers (varying maturity): `fortios`, `aruba`, `huawei`, `mikrotik`, `ros` (RouterOS), `linux`, `f5`, `srl` (Nokia SR Linux). Community drivers live in `napalm-<vendor>` packages.

## NAPALM common getters

| Getter | Returns | Use case |
|---|---|---|
| `get_facts()` | hostname, model, serial, OS version, uptime, interface list | Inventory baseline, version audit |
| `get_interfaces()` | per-interface state, MAC, MTU, speed, last_flapped | Interface-down sweep |
| `get_interfaces_counters()` | rx / tx / errors / drops counters | Error-rate baseline |
| `get_lldp_neighbors()` | per-port LLDP neighbour name + port | Topology discovery |
| `get_arp_table()` | IP -> MAC -> interface mapping | L2 / L3 reconciliation |
| `get_mac_address_table()` | MAC -> VLAN -> port | L2 troubleshooting |
| `get_route_to(destination, protocol=None)` | per-protocol route entries with next-hop, metric, age | Routing decision tree (pair with `bgp-analysis` and `igp-routing-analysis`) |
| `get_bgp_neighbors()` | per-peer state, prefixes received / sent, uptime | BGP audit baseline |
| `get_config(retrieve="all", sanitized=True)` | running, startup, candidate config strings | Pre-change snapshot; `sanitized=True` strips passwords for safe storage |
| `get_environment()` | CPU, memory, fans, temperature, PSU | Health monitoring |

The whole getter list is at `napalm.readthedocs.io/en/latest/support/`; coverage varies by driver, check the support matrix before assuming a getter exists.

## NAPALM config push (the canonical pattern)

```python
device.open()
try:
    # 1. Capture pre-change baseline (mandatory; even with NAPALM rollback).
    pre = device.get_config(retrieve="running", sanitized=False)

    # 2. Load candidate config.
    device.load_replace_candidate(filename="r1.candidate.cfg")
    # OR additive: device.load_merge_candidate(config="interface Gi0/1\n description LINK_TO_R2\n")

    # 3. Diff. NEVER skip this step for production.
    diff = device.compare_config()
    if not diff:
        device.discard_config()
        return  # No-op; nothing to do.

    print(diff)  # Surface to user via AskUserQuestion before commit on production devices.

    # 4. Commit.
    device.commit_config()

    # 5. Verify post-change. Re-read getters; compare against expectations.
    post_state = device.get_interfaces()
    # ... assertions ...

except Exception:
    device.discard_config()  # Drop the candidate if anything went wrong before commit.
    raise
finally:
    device.close()
```

Rollback after commit (NAPALM-native on Junos / IOS-XR; emulated by NAPALM on IOS / NX-OS / EOS by re-pushing the snapshot): `device.rollback()`. The rollback window on emulated platforms is one commit; subsequent commits overwrite the snapshot.

## Netmiko connection model

```python
from netmiko import ConnectHandler

device = {
    "device_type": "cisco_ios",   # see netmiko.ssh_dispatcher for the full list
    "host": "r1.example.net",
    "username": os.environ["NETOPS_USER"],
    "password": os.environ["NETOPS_PASS"],
    "secret": os.environ["NETOPS_ENABLE"],
    "port": 22,
    "fast_cli": False,            # leave False unless you have profiled the impact
    "session_log": "r1.session.log",
}

with ConnectHandler(**device) as conn:
    conn.enable()                  # IOS / NX-OS / ASA: enter privileged mode
    output = conn.send_command("show ip interface brief")
    conn.send_config_set(["interface Gi0/1", " description LINK_TO_R2"])
    conn.save_config()             # vendor-specific: write memory / commit / etc.
```

Common `device_type` values: `cisco_ios`, `cisco_xe`, `cisco_xr`, `cisco_nxos`, `cisco_asa`, `cisco_ftd`, `juniper_junos`, `arista_eos`, `paloalto_panos`, `fortinet`, `f5_tmsh`, `f5_linux`, `hp_procurve`, `hp_comware`, `huawei`, `mikrotik_routeros`, `linux`. Append `_telnet` for Telnet (almost always wrong in 2026; only justified for console-server reach to legacy gear).

## Netmiko core methods

| Method | Returns / does | Notes |
|---|---|---|
| `send_command(cmd, expect_string=None, read_timeout=10)` | Output until prompt regex matches | Default; use for stable `show` commands. |
| `send_command_timing(cmd, delay_factor=1, last_read=2)` | Output by read timeout, no prompt expectation | Use when prompt may change (paging, Y/N confirmations, banner). |
| `send_config_set(config_commands, exit_config_mode=True)` | Pushes a list of commands inside config mode | Returns the combined output; check for vendor error markers (`% Invalid input`, `error: ...`). |
| `send_config_from_file(filename, **kwargs)` | Same, sourced from file | Convenient for reviewable change packs. |
| `enable()` | Enters privileged mode | Requires `secret` in the device dict for IOS / NX-OS / ASA. |
| `save_config()` | Vendor-specific persist | Maps to `write memory` (IOS), `commit` (Junos), `copy run start` (NX-OS), `write` (FortiOS). |
| `disconnect()` | Closes the SSH session | Use the `with` context manager instead; it calls this on exit. |
| `read_until_pattern(pattern, read_timeout=10)` | Reads until the regex pattern appears | Build interactive workflows (ROMmon, image-copy progress). |

## Authentication patterns

- **SSH key preferred** over password where the platform supports it. Pass `use_keys=True, key_file="/path/to/key"` to NAPALM `optional_args` or to Netmiko device dict. Combine with `passphrase` if the key is encrypted; `passphrase` itself comes from the secret store.
- **Per-platform enable / privilege quirks:**
  - Cisco IOS / NX-OS / ASA: separate enable secret; pass `secret=`; call `enable()` for Netmiko or set in `optional_args` for NAPALM.
  - JunOS: no enable mode; class-based privilege via `class super-user` etc.
  - PAN-OS: API key preferred over username/password (`api_key=` in NAPALM `optional_args`); Netmiko works against the CLI but the official panxapi route is faster.
  - FortiOS: use Netmiko `fortinet`; `vdom` switch via `conn.send_command("config vdom")` if multi-VDOM.
- **MFA / TACACS / RADIUS:** Netmiko handles standard prompts. For Cisco TACACS where the second prompt is "Password:" expecting the same string, no extra config needed. For RSA token + PIN concatenation, set `password = pin + token_code` at call time (token captured outside Python; never persisted).
- **Inventory pattern:** YAML or TOML inventory holds device hostnames + `device_type` + `secrets_path`. Loader looks up `secrets_path` in the secret store at run time. NEVER plaintext credentials in the inventory file.

## Per-vendor quirks (the table that saves an afternoon)

| Vendor / OS | Quirk | Mitigation |
|---|---|---|
| Cisco IOS-XE | `terminal length 0` paging fix is set automatically by Netmiko, but config-mode commands still page on `show running-config interface` | Use NAPALM `get_config` instead, or wrap in `terminal length 0`. |
| Cisco NX-OS | `show running-config` truncates with `! NX-OS image file is: bootflash:///nxos.X.X.X.bin` header that breaks naive diff | NAPALM `get_config(sanitized=True)` strips this; for Netmiko, post-process. |
| Cisco IOS-XR | Two-stage commit: `commit` may trail `Uncommitted changes found, commit them?` if config is dirty | NAPALM handles via `commit_config()`; raw Netmiko needs `send_command_timing("commit\n", expect_string="]:")`. |
| Cisco ASA | Privilege levels matter; `enable` may be required even for some `show` commands depending on TACACS profile | Always call `conn.enable()` early. |
| JunOS | Config push requires `configure private` (concurrent-edit safe) or `configure exclusive` (locks) | NAPALM uses `configure private`; if you need `exclusive` (long change windows), use Netmiko + explicit `send_config_set(["configure exclusive", ...])`. |
| JunOS | `set system services ssh root-login` may be `deny`; root SSH disabled by default | Use a non-root account; never re-enable root SSH. |
| Arista EOS | `eAPI` (HTTPS+JSON) is faster than SSH for read-heavy work | NAPALM `eos` driver uses eAPI by default; pass `optional_args={"transport": "ssh"}` to force SSH if eAPI is disabled. |
| PAN-OS | API key has no inactivity expiry but rotates on admin password change | Capture key once via `keygen`; refresh on auth failure. |
| FortiOS | Per-VDOM context; `config vdom / edit root` switches scope mid-session | Track current VDOM in your wrapper; assume nothing. |
| F5 BIG-IP | iControl REST is the modern path; tmsh CLI is the Netmiko `f5_tmsh` route | Prefer iControl REST for new code; Netmiko only for break-glass. |
| Linux network device (Cumulus, SONiC, FRR-on-debian) | Netmiko `linux` works but you lose the network-device prompt assumptions | Use raw paramiko or fabric for these; Netmiko adds little. |

## Concurrency caveat (read this once)

NAPALM and Netmiko are SYNCHRONOUS PER DEVICE. They are NOT thread-safe on the same `device` / `ConnectHandler` object across threads. For parallel fan-out across many devices:

- Preferred: `nornir-automation` (purpose-built parallel runner with NAPALM and Netmiko plugins).
- Acceptable: `concurrent.futures.ThreadPoolExecutor` with one connection per worker thread (each worker creates and disposes its own `ConnectHandler`); cap the worker count at something the device infrastructure can handle (10 to 20 typical for production fleets, after surveying device session limits).
- Never: shared `ConnectHandler` across threads, `multiprocessing` against the same SSH session, asyncio against Netmiko (it is not async; wrapping it in `loop.run_in_executor` works but at that point use Nornir).
- For Cisco-dominant fleets with native parallel needs, `pyats-network-automation`'s `pcall` idiom is also a fit.

## Error handling

```python
from netmiko.exceptions import NetMikoTimeoutException, NetMikoAuthenticationException
from napalm.base.exceptions import (
    ConnectionException,
    MergeConfigException,
    ReplaceConfigException,
    CommitError,
    SessionLockedException,
)

try:
    device.open()
except ConnectionException as e:
    # Network unreachable, port closed, SSH version mismatch, host key mismatch
    log.error("connect failed", host=host, error=str(e))
except NetMikoTimeoutException:
    # SSH banner timeout; usually firewall in path or device CPU pinned
    ...
except NetMikoAuthenticationException:
    # Credentials wrong; back off; do NOT retry in a loop, you will lock the account
    ...
```

NAPALM `MergeConfigException` and `ReplaceConfigException` indicate the candidate failed validation (syntax errors, unsupported commands). `CommitError` is post-validation rollback by the device itself. `SessionLockedException` (JunOS) means another user holds `configure exclusive`; back off and surface the lock holder.

## Read this before pushing config to production

- Capture pre-change `show running-config` (or NAPALM `get_config`) explicitly; do not rely on NAPALM rollback being native.
- Run `compare_config` and surface the diff via AskUserQuestion before `commit_config`. The 9-element response contract from `multi-vendor-network-ops` applies (Summary / Goal / Devices / Diff / Risk / Pre-checks / Procedure / Post-checks / Rollback).
- Have the rollback command ready in a separate file (not just in NAPALM's emulated rollback).
- Verify post-commit via getters: `get_interfaces()` for link state, `get_bgp_neighbors()` for peering, `get_route_to()` for reachability. Do not claim "done" without fresh evidence; see `completion-gate`.
- For state-changing chunks, plan-mode entry should fire `engineering:deploy-checklist` per `plan-time-tooling`.

## Cross-references

- `multi-vendor-network-ops`: umbrella; this skill is the Python transport / abstraction specialist underneath the diagnose-first methodology.
- `nornir-automation`: fleet orchestration; Nornir's NAPALM and Netmiko plugins drive this skill's libraries in parallel.
- `ansible-network-modules`: declarative alternative; YAML-first; better fit for change-managed environments where Python code review is heavier than playbook review.
- `pyats-network-automation`: Cisco-dominant alternative for fleet automation with structured Genie parsing.
- `bgp-analysis` / `igp-routing-analysis`: protocol-depth specialists; NAPALM getters feed their decision trees.
- `acl-rule-analysis`: when the change is an ACL push, the audit discipline lives there.
- `secrets-hygiene`: credential sourcing; never plaintext in YAML or scripts.
- `systematic-debugging`: Phase 1 boundary evidence often comes from a NAPALM getter or a Netmiko `show`.
- `completion-gate`: post-deploy verification gate; getter re-read is the evidence.
- `plan-time-tooling`: state-changing chunks fire `engineering:deploy-checklist`; new automation framework choice fires `engineering:architecture`.
- `bash-defensive`: wrapper scripts around python entrypoints follow defensive-bash discipline.

## Common pitfalls

1. Plaintext credentials in `inventory.yaml` or `device.yaml`. Always reference the secret store.
2. Sharing a `ConnectHandler` across threads. Not thread-safe; use Nornir or per-worker connections.
3. `send_command` against a vendor banner-accept prompt. Use `send_command_timing` instead.
4. NAPALM `load_replace_candidate` without `compare_config` first. The diff is the audit trail.
5. Forgetting to call `device.close()` / `conn.disconnect()`; leaks VTY lines.
6. Assuming NAPALM has the getter you need without checking the support matrix.
7. Mixing NAPALM commit with manual config-mode interactions in the same session; NAPALM expects to own the session.
8. Telnet `device_type` in production. Plain text on the wire. Console-server reach to legacy gear is the only acceptable case; document why.
9. Setting `fast_cli=True` without profiling. The default is `False` for a reason; flipping it can return partial output on slow devices.
10. Catching all `Exception` and continuing; you will mask `CommitError` and silently push half-changes. Catch the specific exception classes.

## Red flags (stop and ASK before)

1. About to call `commit_config()` on a production device without a narrated diff in the conversation.
2. About to pass a literal password string to `ConnectHandler` or NAPALM `password=`.
3. About to spawn a `ThreadPoolExecutor(max_workers=>20)` against unknown device population.
4. About to use `device_type="<vendor>_telnet"` for any device that is not a console-server reach to legacy hardware.
5. About to catch `Exception` and `pass` inside a config-push loop.
6. About to push `load_replace_candidate` with a candidate that omits sections present in the current running config (full replace; you may delete VTY ACLs, AAA, banner, etc.).
7. About to call `enable()` against a device whose `secret` is `None` because nobody set it; the call hangs to read timeout.
8. About to use NAPALM `rollback()` on IOS / NX-OS / EOS more than one commit after the change; NAPALM's emulated rollback window is one commit.
9. About to chain `send_config_set` calls without checking the returned output for `% Invalid input` / `error:` / `% Incomplete command`; NAPALM raises, raw Netmiko returns the error in the output.
10. About to commit changes during a maintenance-window-adjacent boundary without coordinating against parallel automation runs (Nornir + ad-hoc + ServiceNow change windows can all hit the same device at once).

## Bottom line

NAPALM gives you a normalised, idempotent multi-vendor abstraction with diff and rollback. Netmiko gives you the raw SSH transport when the abstraction does not fit. Use NAPALM by default for inventory and idempotent change; drop to Netmiko for vendors NAPALM does not cover or workflows that need prompt-by-prompt control. Both are synchronous per device; for fleet fan-out, hand the work to `nornir-automation`. Credentials always come from the secret store; configs always diff before commit; getters always re-run after commit; the response contract from `multi-vendor-network-ops` always applies on production change.
