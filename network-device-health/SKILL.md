---
name: network-device-health
description: "Use for a structured device health check and triage on Cisco (IOS-XE routers, switches and Catalyst; NX-OS Nexus), Juniper (JunOS MX, SRX, EX, QFX, PTX) and Arista (EOS 7000, 7500, 720X) platforms: CPU, memory, interfaces, routing neighbour state, environment, crashes and cores, and the platform-specific layers (IOS-XE RP versus QFP, NX-OS VDC and vPC, JunOS RE mastership, alarms and PFE, EOS agents, MLAG and VXLAN/EVPN). Triggers include \"device health check\", \"device is slow or dropping traffic\", \"high CPU on a router or switch\", \"memory leak on a switch\", \"post-upgrade health\", \"RE failover\", \"chassis alarm\", \"EOS agent crashed\", \"MLAG inconsistent\", \"vPC peer-link down\", \"QFP drops\", \"PFE errors\", \"core dump found\", \"scheduled device health audit\". Read-only, one device at a time. NOT for link errors and optics on a specific interface (interface-health), NOT for before-and-after proof of a change (change-verification), NOT for protocol diagnosis of a down BGP, OSPF or EVPN session (bgp-analysis, igp-routing-analysis, evpn-vxlan-fabric), NOT for firewall platform audits (fortigate-firewall-audit, palo-alto-firewall-audit, cisco-firewall-audit), NOT for choosing monitoring tooling (network-monitoring-selection)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network device health

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-device-health]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

A triage procedure for the health of one network device, from identity and uptime through CPU, memory, interfaces, routing neighbours and environment, ending in a prioritised findings report with severities and actions. The frame is shared across vendors; the platform-specific layers, commands and thresholds live in one reference per platform, loaded only for the platform in front of you.

**Posture.** Read-only. Everything here is a `show` command over SSH or console, plus session housekeeping that does not change configuration (`terminal length 0`, moving the session to the master RE with `request routing-engine login`, selecting a VDC with `switchto vdc`, an EOS `bash` shell for read-only Linux diagnostics). Nothing in this skill changes configuration or device state. The remedies the trees lead to (restart an agent, power-cycle a line card, reload, clear storage) are recommendations that go through a change request, and clearing evidence (counters, logs, cores) before it is collected is itself a mistake. Command syntax was written from vendor documentation and was not run against devices while authoring, so confirm it on the release and platform you operate.

## Pick the platform reference

| Platform | Load | Platform-specific layers |
|---|---|---|
| Cisco IOS-XE (ISR, ASR, Catalyst 9K) and NX-OS (Nexus 3K, 5K, 7K, 9K) | `references/cisco.md`, with `references/cisco-cli-reference.md` and `references/cisco-threshold-tables.md` | IOS-XE route processor versus QFP data plane; NX-OS VDC scope, modules, vPC |
| Juniper JunOS (MX, SRX, EX, QFX, PTX) | `references/juniper.md`, with `references/juniper-cli-reference.md` and `references/juniper-threshold-tables.md` | RE mastership first, then alarms, RE versus PFE, commit correlation |
| Arista EOS (7000, 7500, 720X series) | `references/arista.md`, with `references/arista-cli-reference.md` and `references/arista-threshold-tables.md` | Linux-native agents, MLAG, VXLAN/EVPN |

Read the platform file before running anything: it carries the ordered procedure, the decision trees and the troubleshooting notes. The CLI and threshold files are lookups.

## When to use

- A device is reported slow, dropping traffic or unresponsive.
- A scheduled health audit of routers, switches or data-centre leaves and spines.
- Verification after an upgrade, patch or reload where the question is "is the box healthy", not "did the change land" (that is `change-verification`).
- Capacity-planning data for CPU, memory and link load.
- An incident where this device is a suspected fault domain.
- Platform events: an RE failover, a chassis alarm, an agent restart, an MLAG inconsistency, a vPC peer-link failure, a crash or core dump.

## When not to use

- **One interface is the problem** (errors, flaps, optics, discards): `interface-health`. This skill only counts interface errors; that one diagnoses them.
- **Proof that a change worked, or a rollback decision:** `change-verification`.
- **A routing session will not establish, or a path is wrong:** `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`. Use this skill to rule the device in or out first, then hand over.
- **Ongoing drift or compliance of the configuration:** `config-management`.
- **Firewall platforms** (FortiGate, Palo Alto, Cisco ASA and FTD, Check Point, Sophos): the per-vendor firewall audit skills.
- **MikroTik, Nokia and other platforms:** `multi-vendor-network-ops` and `mikrotik-routeros`.
- **Fleet-wide polling and alerting design:** `network-monitoring-selection` (SNMP, flow, streaming telemetry) and `network-streaming-telemetry`.

## Prerequisites

- SSH or console access with a read-only role (Cisco privilege 1 or `show` role, JunOS `view` class, EOS privilege 1).
- The device's normal baseline for CPU, memory and traffic, or a prior report to compare with. Without a baseline, only absolute thresholds apply, and you should say so.
- Knowledge of the device's role and redundancy (dual-RE, VDCs, MLAG pair, vPC peer), because the right session and the right peer matter.
- Credentials handled per `secrets-hygiene`: never paste device passwords into the conversation, and redact secrets from `show tech-support` or configuration output before quoting it.
- A shared clock or a recorded timestamp, in UTC, so findings can be correlated with syslog.

## Procedure

The same five phases apply on every platform. The platform file orders and details them.

1. **Establish context.** Hostname, model, software version, uptime and the reason for the last reload. A short uptime is a finding in its own right: find out whether it was planned. Confirm you are on the right instance of the thing you are checking (the master RE, the intended VDC, the right MLAG peer), because health data from the wrong one is confidently wrong.
2. **Control plane resources.** CPU (average and recent spikes, per-process or per-agent), memory (used, free, fragmentation or reclaimable cache) and, where the platform has them, platform-specific control-plane indicators.
3. **Data plane and interfaces.** Forwarding-plane drops where the platform exposes them, interface summary, error and discard counters. Classify errors by type and hand a specific link to `interface-health`.
4. **Routing and redundancy state.** Neighbour counts and states for the protocols in use, plus redundancy protocols (vPC, MLAG, RE redundancy). Compare with the baseline, not with what you expect from memory.
5. **Environment, crashes and platform health.** Power, fans, temperatures, alarms, crash logs and core files, recent reload cause.

Then grade each finding against the platform's thresholds, apply the escalation criteria, and write the report.

## Cross-platform thresholds

These are shared starting points copied from the platform tables, which add a fourth tier (Emergency) and the per-platform detail. Where they differ, the platform file wins, and a local policy that states other numbers wins over both. `interface-health` grades per-interface counters on its own scale; for a single link its verdict wins over this device-level screen.

| Parameter | Normal | Warning | Critical | Notes (Emergency is the platform table's top tier) |
|---|---|---|---|---|
| CPU, 5-minute average | 0 to 40% | 41 to 70% | 71 to 90% | Emergency over 90%. NX-OS baselines run higher; JunOS RE spikes to 80 to 90% during a commit are normal |
| Memory | platform-specific | | | NX-OS 55 to 65% used is normal; EOS page cache is reclaimable (read `available`); IOS-XE check fragmentation |
| Interface error rate | under 0.001% | 0.001 to 0.01% | 0.01 to 0.1% | Emergency over 0.1%. Device-level screen; the per-link verdict belongs to `interface-health` |
| Output drops per hour | 0 to 50 | 51 to 500 | 501 to 5,000 | Emergency over 5,000 |
| Routing neighbours | all established | flapping | down | Compare with baseline; more than 3 state changes in an hour escalates |
| Chassis and environment | no alarm | minor alarm, or within 5 C of the limit | major alarm, or at or over the limit | Any environmental alarm escalates |
| Core dump or crash | none | | present within 7 days | Collect before any restart |

## Decision tree skeleton

```
Is the device reachable?
├── No: console, power, environment; after recovery collect the reload cause, crash logs and cores
└── Yes
    ├── Right instance? (master RE, intended VDC, correct MLAG peer)  -> if not, switch and restart
    ├── Alarms or agent failures present? -> address Major or crashed first
    ├── CPU high?  -> identify the process or agent; separate control plane from data plane
    ├── Memory low or growing? -> top consumers; leak versus reclaimable cache; plan a reload only through change control
    ├── Interface errors? -> classify (CRC, input, output, discards); hand specific links to interface-health
    ├── Redundancy or neighbour state degraded? -> platform tree (vPC, MLAG, RE)
    └── Everything inside thresholds -> document a clean result, with the baseline you compared against
```

The platform files expand each branch with the platform's own causes.

## Escalation criteria

Escalate to a senior engineer or the vendor's support when:

- CPU stays over 90% for 15 minutes or more with no identifiable cause.
- Memory is under 15% free with no change to explain it.
- A crash, traceback or core dump appears from a critical process.
- Any environmental alarm (power, fan, temperature).
- More than 3 routing neighbour state changes in an hour.
- Redundancy is lost with no clear physical cause (RE failover loop, vPC peer-link or MLAG peer-link failure, a repeating agent crash).
- A line card, FPC or module is not in its healthy state after a power-cycle attempt.

## Report template

```
DEVICE HEALTH REPORT
====================
Device: [hostname]
Platform: [IOS-XE | NX-OS | JunOS | EOS]
Model: [from inventory]
Software: [version]
Instance checked: [master RE slot | VDC name | MLAG peer | n/a]
Uptime: [uptime string]; last reload cause: [reason]
Check time (UTC): [timestamp]
Performed by: [name or team]
Baseline compared against: [prior report date | none]

SUMMARY: [HEALTHY | WARNING | CRITICAL | EMERGENCY]

FINDINGS
1. [Severity] [Component]: [description]
   Domain: [system | interface | routing | redundancy | environment | platform-specific]
   Observed: [metric value]
   Threshold: [normal / warning / critical range]
   Action: [recommended action; any change goes through a change request]

PLATFORM-SPECIFIC NOTES
- IOS-XE: QFP drop summary. NX-OS: VDC name, module status, vPC state.
- JunOS: RE slot and mastership; chassis alarms (Major n, Minor n); RE and PFE status per FPC; dual-RE state.
- EOS: agent health (total, running, crashed, recent restarts); MLAG state and peer-link; VXLAN/EVPN VTEP and peer counts.

RECOMMENDATIONS
- [Prioritised actions]

NEXT CHECK: [Emergency escalate now, re-check within 4 h | Critical 24 h | Warning 7 d | Healthy 30 d]
```

## Cross-references

- `interface-health`: the next step for any interface the health check flags; owns errors, discards, flaps and optics.
- `change-verification`: use a healthy report as part of the pre-change baseline, and the same commands for the post-change comparison.
- `config-management`: configuration drift, archive freshness and compliance for the same device.
- `network-topology-discovery`: what is attached to the device, when a finding implicates a neighbour.
- `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`: protocol-depth diagnosis once the device itself is cleared or implicated.
- `multi-vendor-network-ops`: the diagnose-first entry point, and the nine-element response contract for any production-impacting remedy.
- `pyats-network-automation`, `napalm-netmiko`, `nornir-automation`: to run these checks across a fleet; keep the posture read-only.
- `network-monitoring-selection`: which signals to monitor continuously so that the health check is the second look, not the first.
- `oncall-runbooks` and `incident-response-network`: when a health finding becomes an incident.
- `completion-gate` Layer 3: no "healthy" or "fixed" claim without a fresh collection in the same turn.
- `secrets-hygiene`: redact before quoting any output.

## Red flags

- About to read health data before confirming the instance (master RE, VDC, MLAG peer).
- About to call a device healthy from one snapshot with no baseline and say nothing about that.
- About to restart a process, agent, line card or device to "see if it clears", before the evidence is collected.
- About to clear logs, counters or core files while triaging.
- About to treat reclaimable page cache or an expected commit spike as a leak or a fault.
- About to apply one platform's thresholds to another (NX-OS memory, EOS cache, JunOS commit CPU).
- About to diagnose a routing protocol from this skill instead of handing over.
- About to quote raw `show tech-support` output without redacting secrets.

## Bottom line

Confirm you are looking at the right instance, work from identity to control plane to data plane to redundancy to environment, grade with the platform's own thresholds, and collect evidence before anyone restarts anything. Report what you compared against, and hand specific links and protocols to the skills that own them.

## Provenance

Re-authored from the Apache-2.0 `cisco-device-health`, `juniper-device-health` and `arista-device-health` skills in `vahagn-madatyan/netsec-skills-suite`, consolidated into one cross-vendor skill with a reference per platform. Upstream persona, safety-tier and tool-dependency metadata removed; platform procedures, thresholds, decision trees and report templates kept; cross-references added for this vault.
