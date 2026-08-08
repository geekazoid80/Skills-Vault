---
name: pyats-network-automation
description: Use for any Cisco pyATS / Genie network-automation work. Triggers include "pyats", "genie", "easypy", "aetest", "testbed yaml", "Cisco network test framework", "device connection pooling", "fleet health check", "baseline capture", "configuration drift detection", "parallel device operations", "change-then-verify automation", "rollback to baseline", "pcall", "pyats job", "structured CLI parsing", "show command parser", "ServiceNow change gating", "GAIT audit trails", "NetBox inventory integration", "pyats learn config / interface / ospf / bgp", "pyats diff before / after", "genie parser command catalogue", "34 learnable features list", "AEtest verdicts errored vs failed", "CPU top processes Cisco", "memory consumers Cisco IOS-XE", "named log pattern catalogue", "fleet size scaling tiers", "emergency change carve-out". Cisco-dominant scope; tied to Genie structured parsers (Cisco IOS / IOS-XE / NX-OS / IOS-XR plus partial Junos / Linux). NOT NAPALM, NOT Netmiko, NOT Nornir (those are separate ecosystems; for cross-vendor automation beyond pyATS-supported platforms, the multi-vendor-network-ops umbrella stays the entry point and a Netmiko / NAPALM / Nornir skill would be a future addition). Eight sections cover framework fundamentals, Genie parsing, dynamic test generation, configuration management with rollback, health monitoring with thresholds, fleet orchestration with pCall concurrency, integration hooks (ServiceNow, GAIT, NetBox), and Cisco-specific templates. Diagnose-first; testbed YAML credentials must come from secrets-hygiene patterns (vault, env, secret store) not plaintext. Consolidated 5-to-1 fold of automateyournetwork/netclaw's pyats-network + pyats-dynamic-test + pyats-health-check + pyats-parallel-ops + pyats-config-mgmt (all Apache-2.0).
metadata:
  version: 1.1.0
---

# pyATS Network Automation

One entry-point for any Cisco pyATS / Genie-based network automation work. Consolidated from five netclaw upstreams into a single skill because the framework, parser, dynamic test, health check, parallel ops, and config management workflows share one mental model: testbed defines devices, pyATS connects, Genie parses, AEtest validates, pCall scales, ServiceNow / GAIT gate the change.

This skill is the framework specialist. The `multi-vendor-network-ops` umbrella stays the entry point for general network work; this skill loads when the work is specifically pyATS / Genie automation. For protocol semantics (BGP / OSPF / ACL behaviour), pair with `bgp-analysis` / `igp-routing-analysis` / `acl-rule-analysis`.

**Scope boundary**: Cisco-dominant (IOS / IOS-XE / NX-OS / IOS-XR are first-class; Junos and Linux have partial pyATS support). NAPALM, Netmiko, and Nornir are separate ecosystems and outside this skill. For multi-vendor automation that must cross beyond pyATS-supported platforms, drive Ansible / NAPALM / Netmiko via your normal patterns and use `multi-vendor-network-ops` for the per-vendor semantics.

> **Skill marker**: When applying this skill, begin your reply with `[skill: pyats-network-automation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the pyATS estate (testbed structure, vendor coverage, runner harness, parser version) before authoring jobs. Only ask the user for information not already covered or specific to this run.

Before authoring jobs, understand:

1. **Testbed and target estate**
   - Testbed YAML location and schema version?
   - Vendor(s) and OS version(s) (Genie parser coverage; pyATS unicon plugin per platform)?
   - Single device, group, or full testbed scope?

2. **Run intent**
   - Read-only parse and compare, snapshot diff, or executing a destructive command set?
   - AEtest harness, Robot integration, or standalone script?
   - Expected reporting (HTML report, JUnit XML, ELK sink)?

3. **Change posture**
   - Maintenance window, change ticket, rollback plan?
   - Secrets path (testbed `credentials` block, env, Vault)?

---

## When to use

- Designing a testbed YAML for a fleet of Cisco devices.
- Writing or reviewing pyATS / Genie test scripts (AEtest classes, fixtures, assertions).
- Capturing pre-change baselines and verifying post-change state.
- Health-monitoring a fleet (CPU, memory, interfaces, NTP, logs, routing, hardware).
- Parallelising fleet operations safely (pCall concurrency, failure isolation, severity-sorted reporting).
- Configuration-management workflows that need explicit rollback (capture baseline, plan, deploy with abort-on-fail, post-check, rollback if any post-check fails).
- Integrating change automation with ServiceNow change gating, GAIT audit trails, or NetBox source-of-truth.
- Reviewing or designing structured-data extraction from `show` commands (Genie parser idioms, Diff utilities, when to fall back to TextFSM or regex).

## Do NOT use this skill for

- NAPALM workflows (different driver model; use a NAPALM skill or write one).
- Netmiko-only SSH automation without pyATS (different abstraction).
- Nornir orchestration (different runner model).
- Pure Ansible network playbooks (see `ansible-network-modules`).
- Live device interaction without testbed YAML (this skill assumes the testbed-driven workflow).

## Prerequisites

- Python 3.10 or newer with `pyats[full]` installed (pulls in Genie, AEtest, pyATS).
- A testbed YAML describing devices (name, OS, platform, connection details, credentials reference).
- Credentials sourced via `secrets-hygiene` patterns (vault retrieval, env vars, OS keyring); never plaintext in tracked YAML.
- For ServiceNow / GAIT / NetBox integration: API endpoints reachable and credentials in the secret store.
- Read-only access to devices is sufficient for inventory, health checks, and baseline capture; configure-mode access is required only for the config-management section.

## Framework fundamentals

### Testbed YAML

The testbed is the source of truth for device inventory.

```yaml
testbed:
  name: lab
  credentials:
    default:
      username: "%ENV{NET_USER}"
      password: "%ENV{NET_PASS}"
    enable:
      password: "%ENV{NET_ENABLE}"

devices:
  R1:
    os: iosxe
    platform: csr1000v
    type: router
    connections:
      cli:
        protocol: ssh
        ip: 198.18.0.11
```

Discipline:

- Credentials reference env vars or vault paths, **never** literal strings.
- One testbed per logical environment (lab, staging, prod); do not mix.
- `os` and `platform` are the parser-selection key; misconfigured `os` produces wrong-vendor parser failures.
- Connection class defaults to Unicon for IOS / IOS-XE / NX-OS / IOS-XR; specify `class: unicon.Unicon` only when overriding.

### Connection lifecycle

```python
from genie.testbed import load
tb = load("testbed.yaml")
device = tb.devices["R1"]
device.connect(log_stdout=False, mit=True)
try:
    output = device.parse("show interfaces")
finally:
    device.disconnect()
```

The `mit=True` flag (modular initialisation, no banner) speeds connection. Always `disconnect()` in `finally`; orphaned sessions block subsequent runs and trip device session limits.

### Easypy job structure

For multi-script orchestration, wrap scripts in a job:

```python
# fleet_health.py
from pyats.easypy import run

def main(runtime):
    runtime.job.name = "fleet_health"
    run(testscript="health_check.py")
    run(testscript="config_audit.py")
```

Run with `pyats run job fleet_health.py --testbed-file testbed.yaml`. The job report aggregates results across scripts and produces a structured archive for audit.

## Genie structured parsing

`device.parse("<show command>")` returns a Python dict when a Genie parser exists for the (os, command) tuple. Coverage is strongest on IOS-XE and NX-OS; weakest on Junos and Linux.

Genie parser command coverage on IOS-XE (representative; partial on NX-OS / IOS-XR; light on Junos / Linux):

- **Routing.** `show ip route` / `show ip route vrf <name>`, `show ip protocols`, `show ip bgp` / `show ip bgp summary` / `show ip bgp neighbors`, `show ip ospf` / `show ip ospf neighbor` / `show ip ospf interface` / `show ip ospf database`, `show ip eigrp neighbors` / `show ip eigrp topology`, `show isis neighbors` / `show isis database`, `show ip static route`.
- **Interfaces.** `show ip interface brief` / `show ipv6 interface brief`, `show interfaces` / `show interfaces <name>`, `show interfaces status`, `show interfaces counters`, `show ip interface`.
- **L2 / switching.** `show vlan` / `show vlan brief`, `show spanning-tree` / `show spanning-tree detail`, `show mac address-table`, `show etherchannel summary`.
- **Neighbors.** `show cdp neighbors` / `show cdp neighbors detail`, `show lldp neighbors` / `show lldp neighbors detail`.
- **FHRP.** `show standby` / `show standby brief`, `show vrrp` / `show vrrp brief`.
- **System.** `show version`, `show inventory`, `show processes cpu` / `show processes cpu sorted`, `show processes memory` / `show processes memory sorted`, `show platform`, `show ntp associations` / `show ntp status`, `show snmp`, `show clock`, `show bootflash`, `show license`.
- **Security.** `show access-lists` / `show ip access-lists`, `show crypto isakmp sa` / `show crypto ipsec sa`, `show dot1x`, `show port-security`, `show authentication sessions`.
- **QoS.** `show policy-map` / `show policy-map interface`.
- **VRF / MPLS.** `show vrf` / `show vrf detail`, `show mpls forwarding-table`, `show mpls ldp neighbor`.
- **Other.** `show arp`, `show ip nat translations`, `show ip dhcp binding`, `show track`, `show route-map`, `show ip prefix-list`, `show bfd neighbors`, `show flow monitor`.

This catalogue is the IOS-XE baseline; NX-OS and IOS-XR support most but not all (parser-not-found is the common failure mode on the edges). Verify per (os, command) pair with `device.parser.get_parser("<command>", device)` before assuming the dict is available.

Idioms:

- **Always check** the parser exists with `device.parser.get_parser("<command>", device)`. Missing parsers raise `ParserNotFound`; catch and fall back to raw `device.execute(<command>)` plus regex / TextFSM.
- **Diff utilities**: `from genie.utils.diff import Diff; d = Diff(before, after); d.findDiff()` produces a structured before / after report. Use for baseline-vs-current comparisons.
- **Learn features** for higher-level abstractions: `device.learn("interface")`, `device.learn("ospf")`, `device.learn("bgp")` return aggregated structured state across multiple show commands. Useful for snapshot-and-compare. Full 34-feature catalogue: `acl`, `arp`, `bgp`, `config`, `device`, `dot1x`, `eigrp`, `fdb`, `hsrp`, `igmp`, `interface`, `isis`, `lag`, `lisp`, `lldp`, `mcast`, `mld`, `msdp`, `nd`, `ntp`, `ospf`, `pim`, `platform`, `prefix_list`, `rip`, `route_policy`, `routing`, `static_routing`, `stp`, `terminal`, `utils`, `vlan`, `vrf`, `vxlan`. Per-platform coverage varies; treat an empty `info` dict as "feature not supported on this OS or version" rather than "no state present".
- **Filter early**: parsers return everything; filter the dict in Python before logging or asserting, or memory grows fast on big fleets.
- **Version drift**: parser output schemas can change between Genie releases. Pin the Genie version in your project; an unpinned upgrade can silently break consumers.

When no parser exists: prefer NTC-Templates (TextFSM) before raw regex. Log the gap so it can be contributed back upstream.

## Dynamic test generation (AEtest)

AEtest is pyATS's test framework: `Testcase` classes with `setup`, `test`, `cleanup` sections.

```python
from pyats import aetest

class InterfaceTest(aetest.Testcase):
    @aetest.setup
    def connect(self, testbed):
        self.device = testbed.devices["R1"]
        self.device.connect(log_stdout=False, mit=True)

    @aetest.test
    def all_interfaces_up(self):
        intfs = self.device.parse("show ip interface brief")
        down = [i for i, d in intfs["interface"].items()
                if d.get("status") != "up"]
        if down:
            self.failed(f"down interfaces: {down}")

    @aetest.cleanup
    def disconnect(self):
        self.device.disconnect()
```

Discipline:

- One responsibility per `Testcase`; many small testcases beat one giant one.
- Parametrise across devices via testbed iteration; do not hardcode device names.
- Inline test data only for trivial tests; for large data sets, use a YAML alongside the script and load via `aetest.loop`.
- Use `self.failed(<reason>)`, `self.passed(<reason>)`, `self.skipped(<reason>)`; never bare `assert` (loses the AEtest report).
- AEtest verdict semantics (distinguish in the report and in any downstream tooling):

  | Verdict | Meaning |
  |---|---|
  | `Passed` | All assertions succeeded; network state matched expectations. |
  | `Failed` | One or more assertions did not match; the failure message explains what was wrong. |
  | `Errored` | The script itself had a runtime error (syntax error, banned import, exception, 300s sandbox timeout); the test did not complete. |
  | `Blocked` | `CommonSetup` failed (could not connect to a device, missing fixture), so the testcases were skipped without running. |

  `Errored` and `Failed` look similar in casual reports but are operationally different: `Failed` is a real-state finding to act on; `Errored` is a tooling bug or environment issue that demands a fix before the next run is meaningful.

## Configuration management with rollback

Iron rule: **every configuration change captures a baseline first, deploys with abort-on-fail, runs post-checks, and rolls back if any post-check fails.**

Five-stage workflow:

1. **Baseline capture**: `device.execute("show running-config")` and learn() for protocol state. Persist to a timestamped file under the change ticket.
2. **Change plan**: produce the config diff, the post-check criteria, and the rollback script. Surface to the user via `AskUserQuestion` per the standing rule on multi-option choices, then map onto `multi-vendor-network-ops` 9-element response contract.
3. **Deploy** with `device.configure(config, error_pattern=["%Error", "Invalid input"])` so any device-side error aborts the apply and surfaces immediately.
4. **Post-check**: re-run the baseline-capture commands; diff against the **expected** state, not the original baseline. A successful change typically changes some state.
5. **Rollback**: if any post-check fails, run the rollback script (which may be a `configure replace` to the baseline, or a manual reverse diff). Retry until the device matches the original baseline; escalate if rollback itself fails.

This is the operational equivalent of `completion-gate` Layer 3: no claim of "change applied" without fresh post-check evidence in this turn. If the change touches multiple devices, treat the cluster as a single unit; partial success is failure until the cluster is consistent.

## Health monitoring (8-step workflow)

For each device in the fleet:

1. **CPU**: `show processes cpu sorted | exclude 0.00` and threshold per platform (typical: greater than 80 percent sustained = warning; greater than 95 percent = critical). On Cisco platforms, top-process names that explain high CPU: `IP Input` (high traffic volume or routing loops); `BGP Router` / `BGP I/O` (large BGP table or instability); `OSPF-1 Hello` (OSPF adjacency churn); `Crypto IKMP` / `Crypto Engine` (IPsec overhead); `SNMP ENGINE` (polling storm); `ARP Input` (ARP storm or L2 loop). Always read the named process, not just the aggregate percentage; the process name is the diagnostic vocabulary.
2. **Memory**: `show processes memory sorted` and threshold (greater than 85 percent used = warning; greater than 95 percent = critical, risk of process crashes or OOM). On Cisco platforms, top consumers that explain high memory: `BGP Router` (large BGP table; full internet table is roughly 1M routes); `CEF process` (large FIB); `OSPF Router` (large LSDB); `HTTP CORE` (web server or RESTCONF overhead); `IOSD iomem` (I/O memory for packet buffers).
3. **Interfaces**: `show interfaces` and check `error`, `drops`, `crc`, `flap` counters; non-zero deltas vs baseline are signals.
4. **NTP**: `show ntp status` for `synchronized`; `show ntp associations` for stratum and reach.
5. **Logs**: `show logging | last 100` and grep for `%[A-Z]+-[1-3]-` (severity 1-3 messages); pair with `secrets-hygiene` to redact sensitive log content. Named patterns to scan for explicitly:

   | Pattern | What it signals |
   |---|---|
   | `%SYS-*-RELOAD` | Reload event. |
   | `%LINEPROTO-5-UPDOWN` | Interface flap. |
   | `%OSPF-*-ADJCHG` | OSPF adjacency state change. |
   | `%BGP-*-ADJCHANGE` | BGP peer state change. |
   | `%DUAL-*-NBRCHANGE` | EIGRP neighbour change. |
   | `%SYS-2-MALLOCFAIL` | Memory allocation failure (CRITICAL). |
   | `%SYS-3-CPUHOG` | Process monopolising CPU (HIGH). |
   | `%TRACKING-*` | IP SLA or object-tracking state change. |
   | `%SEC-*` / `%AUTHMGR-*` | Security event. |
   | `%PLATFORM-*-CRASH` | Crash event (CRITICAL). |
   | `Traceback` | Software bug (CRITICAL; open a vendor TAC case). |
6. **Connectivity**: ping a known reachable address from the device; verify expected ICMP success.
7. **Routing**: `show ip route summary` and protocol-specific learn (`device.learn("bgp")`, `device.learn("ospf")`); cross-ref `bgp-analysis` and `igp-routing-analysis` for thresholds.
8. **Hardware**: `show inventory`, `show platform`, `show environment`; flag failed PSUs / fans / linecards.

Optional: integrate NetBox to compare actual inventory against expected (catches device misclassification, missing rack space, untracked devices). NetBox API key per `secrets-hygiene`.

## Fleet orchestration (pCall concurrency)

`pCall` (parallel call) runs the same function across a list of inputs concurrently; isolated failures do not abort the batch.

```python
from pyats.async_ import pcall

def check_device(name, testbed):
    device = testbed.devices[name]
    device.connect(log_stdout=False, mit=True)
    try:
        return {"name": name, "cpu": device.parse("show processes cpu")}
    finally:
        device.disconnect()

results = pcall(check_device,
                name=list(testbed.devices),
                testbed=[testbed] * len(testbed.devices))
```

Discipline:

- **Default to bounded concurrency**: large fleets need a worker pool; uncapped pCall on 500 devices will exhaust file descriptors and trigger device session limits. Use `pcall(... max_workers=20)`.
- **Fleet-size scaling tiers** (default strategies; tune per environment):

  | Fleet size | Strategy |
  |---|---|
  | 1-5 devices | Single parallel wave; all commands at once. |
  | 6-20 devices | Two waves: critical devices first, then the remaining. |
  | 20-50 devices | Group by role or site; 10-15 devices per wave. |
  | 50+ devices | Group by site; sample 20 percent per wave; expand only if anomalies surface. |

  For very large fleets, lead with a sampling probe (2-3 devices per role per site) and expand to the full fleet only if anomalies surface. Sampling beats a full sweep when the goal is "is anything wrong" rather than "audit every device".
- **Always wrap in try / finally** so a single device failure does not orphan its session.
- **Aggregate results by severity**: critical / warning / healthy buckets, sorted critical-first. Report bundle with per-device detail and fleet summary.
- **Pre-flight reachability**: ping all targets before connecting; mark unreachable devices in the report rather than failing the whole batch.
- **Per-device timeout**: set a connection timeout per device (default 60s is too generous for fleet-wide health checks); time-out failures count as warnings, not aborts.

## Integration hooks (ServiceNow, GAIT, NetBox)

These are tooling-specific; this section captures the discipline, not the wire-level API call.

- **ServiceNow change gating**: every state-changing pyATS run records the change ticket number in the testbed metadata; pre-deploy step queries ServiceNow for ticket state; if not Approved + In Window, abort. Post-deploy step appends a comment with the test report archive URL. Emergency-change carve-out: for network outages or active security incidents, the approval gate is bypassed BUT the change-request is still created up front with category `Emergency`, a human is notified before the change runs, and the CR must be retroactively approved within 24 hours; missing the 24-hour window breaks the audit trail and weakens the change-management process for everyone.
- **GAIT audit trails**: every device interaction logs `(device, command, output, timestamp_utc, user, change_ticket)` to the GAIT audit store. `secrets-hygiene` requires that command output is redacted before logging when it contains credentials.
- **NetBox source-of-truth**: the testbed YAML can be auto-generated from NetBox at the start of a run, ensuring the device inventory matches the live source-of-truth. Drift between testbed and NetBox is a warning; missing-from-testbed but present-in-NetBox is critical.

## Cisco-specific templates

Brief: pyATS support is strongest for IOS-XE / NX-OS, then IOS-XR, then ASA / FTD, then F5. Per-platform deep work is netclaw's per-platform skills (which the vault has NOT adopted; revisit in a future stage if a platform-specific need surfaces).

| Platform | Genie parser coverage | Notes |
|---|---|---|
| IOS / IOS-XE | strongest | Default for most netclaw examples; full Diff support |
| NX-OS | strong | VPC, VRF, FEX patterns supported |
| IOS-XR | medium | Many learn() abstractions absent; expect parser fallbacks |
| ASA / FTD | medium | Read-only firewall ops; pair with `acl-rule-analysis` for rule walks |
| Junos | partial | Limited; PyEZ may be a better fit for deep Junos automation |
| Linux (jumphost) | limited | Use Netmiko / Paramiko directly for Linux unless you need pyATS test-report integration |

## Cross-references

- `multi-vendor-network-ops`: umbrella entry-point for general network work; pyATS is Cisco-dominant so the umbrella stays primary for non-Cisco vendors. Cross-platform automation beyond pyATS scope falls back to the umbrella plus the Stage 6 multi-vendor automation skills (`napalm-netmiko`, `nornir-automation`, `ansible-network-modules`).
- `napalm-netmiko`: when the project requires a vendor not in pyATS / Genie's coverage matrix (FortiOS, F5, Aruba, MikroTik, full Junos with PyEZ-equivalent control), use NAPALM (idempotent abstraction with diff and rollback) or raw Netmiko (vendor-specific CLI) instead of pyATS.
- `nornir-automation`: when fan-out across a multi-vendor fleet is required (rather than Cisco-fleet-only with `pcall`), Nornir is the orchestration layer; its `nornir_pyats` plugin can also drive pyATS jobs from inside a Nornir run when bridging is the right answer.
- `ansible-network-modules`: when change management is built around playbook review (declarative YAML; vault-encrypted credentials per platform; resource modules with state semantics), Ansible is the alternative; suitable for organisations where Python code review is heavier than playbook review.
- `bgp-analysis`: `device.learn("bgp")` and `device.parse("show ip bgp ...")` are the data-gathering side; the protocol semantics for interpreting the output live in `bgp-analysis`.
- `igp-routing-analysis`: `device.learn("ospf")` and `device.parse("show ip ospf ...")` data-gathering pairs with `igp-routing-analysis` semantics.
- `acl-rule-analysis`: `device.parse("show access-lists")` returns structured rule data; the methodology (shadowing, hit-count staleness, severity classification) lives in `acl-rule-analysis`.
- `secrets-hygiene`: testbed YAML credentials MUST come from env vars, vault, or OS keyring (never plaintext); GAIT audit logs MUST redact credential output.
- `systematic-debugging`: pyats-troubleshoot equivalents are procedural; for actual diagnostic logic (boundary evidence, hypothesis testing, root-cause discipline), use `systematic-debugging`.
- `bash-defensive`: any wrapper shell scripts (testbed-builder, run-orchestrator, archive-uploader) follow strict mode + traps + ShellCheck; CLI-injection risks on dynamic show commands are real.
- `plan-time-tooling`: state-changing pyATS runs (config push, restart, reload) fire the `engineering:deploy-checklist` mandatory trigger. ServiceNow / GAIT integration assumes external tooling fired at plan-time.
- `completion-gate` Layer 3: post-deploy verification is the iron law (see config-management section); no "change applied" claim without fresh post-check in this turn.
- `oncall-runbooks`: pyATS test reports are useful incident artifacts; attach the archive URL in the postmortem.

## Common mistakes

- Plaintext credentials in tracked testbed YAML (use env vars or vault references).
- Unbounded pCall on a large fleet (exhausts file descriptors and device session limits).
- Forgetting `device.disconnect()` in `finally` (orphans session).
- Using bare `assert` in AEtest tests instead of `self.failed()` (loses the test report).
- Treating partial cluster success as success (must be all-or-rollback).
- Catching `ParserNotFound` silently (logs lose the gap signal; track it so it can be contributed upstream).
- Mixing testbeds for lab and production in one job (one wrong device target = production change in lab, or worse, lab change in production).
- Pinning Genie version implicitly via `pip install -U` rather than a version-locked requirements file (parser schema drift breaks consumers).
- Running config push without baseline capture, abort-on-fail, post-check, or rollback (any one missing breaks the iron rule).
- Logging command output to GAIT without redacting credentials (`secrets-hygiene` violation).
- Assuming `device.learn("X")` exists for every protocol on every platform (NX-OS coverage differs from IOS-XR coverage).

## Red flags

- About to push to a fleet without `pCall` failure isolation.
- About to commit a baseline-less change.
- About to assume a Genie parser exists for a non-Cisco platform without checking `get_parser`.
- About to ship a testbed YAML with plaintext credentials.
- About to skip the post-check step because the deploy "looked successful in the CLI".
- About to call rollback "manual" without scripting it; manual rollback under pressure is the most common cause of compounded outages.
- About to share a test report archive URL in a customer-facing channel without redacting device credentials and IPs first.
- About to declare `device.learn("X")` reliable on a platform you have not tested it on (silent partial output is worse than `ParserNotFound`).
- About to declare a fleet operation done without a per-device severity-sorted result table.
- About to claim done without `completion-gate` Layer 3 post-check evidence.

## Bottom line

Testbed is source of truth; Genie is the parser; AEtest is the test framework; pCall is concurrency; rollback is non-negotiable; ServiceNow / GAIT / NetBox are the gating integrations. Cisco-dominant scope; for cross-vendor work the `multi-vendor-network-ops` umbrella stays primary. Credentials always come from `secrets-hygiene` patterns. Production state-changing pyATS runs always emit the 9-element response contract per `multi-vendor-network-ops`; no claim of "applied" without `completion-gate` Layer 3 post-check.
