---
name: endpoint-detection-response
description: Use for vendor-neutral endpoint detection and response (EDR) strategy, endpoint and XDR detection methodology, threat hunting, and host-level incident response across any platform (CrowdStrike Falcon, Microsoft Defender for Endpoint, SentinelOne, Carbon Black, Cortex XDR, Elastic Defend, Sophos Intercept X, Wazuh). Covers EDR vs EPP vs XDR vs MDR, signature/IOC vs behavioural/IOA vs ML detection, MITRE ATT&CK coverage mapping, endpoint telemetry architecture, the detection-engineering lifecycle, threat hunting, response actions (host isolation, process kill, quarantine, rollback, remote shell, memory forensics), false-positive tuning and exclusion hygiene, sensor health, performance overhead, and platform selection. References detection-methodology.md, telemetry-and-hunting.md, response-and-tuning.md, platform-selection.md. Triggers include "EDR", "XDR", "endpoint detection", "endpoint protection", "EPP", "MDR", "behavioural detection", "IOC", "IOA", "indicator of attack", "indicator of compromise", "MITRE ATT&CK", "ATT&CK coverage", "threat hunting", "endpoint telemetry", "process injection", "LOLBin", "living off the land", "credential dumping", "LSASS", "host isolation", "endpoint containment", "ransomware rollback", "false positive tuning", "EDR exclusion", "sensor health", "which EDR", "EDR comparison". For SIEM/SOAR strategy and log correlation that consumes EDR telemetry see siem-soar-investigation; for network-side sensors (IDS/IPS, NDR, NAC, micro-segmentation) see network-detection-response; for the incident lifecycle an EDR alert feeds see incident-response-lifecycle and oncall-runbooks; for the identity surface credential-access attacks target see identity-access-management; for credential and token handling in EDR integrations see secrets-hygiene; for UTC-correct event timing see utc-timestamps.
license: MIT
metadata:
  version: 1.0.0
---

# Endpoint detection and response

> **Skill marker**: When applying this skill, begin your reply with `[skill: endpoint-detection-response]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for endpoint detection and response (EDR) and its extension into XDR. It owns the cross-platform reasoning: how endpoint telemetry becomes detections, how those detections are engineered and measured, what response actions exist and when to use them, and how to choose a platform. Platform-specific syntax and tooling (Falcon CQL/RTR, MDE KQL advanced hunting, SentinelOne Storyline, Cortex XQL/BIOC, Elastic EQL, Wazuh rules) is named only as routing context; the depth here is the methodology that survives a platform migration.

## When to use

- Choosing or comparing EDR/XDR platforms against requirements (OS mix, cloud footprint, team maturity, managed-service need).
- Designing endpoint detection logic: IOA vs IOC, ATT&CK coverage, detection-as-code, testing and tuning.
- Reducing false positives: exclusion hygiene, suppression strategy, alert-fidelity tuning.
- Planning response: host isolation, process kill, quarantine, rollback, and the approval gates around them.
- Running endpoint threat hunting against stored telemetry, or scoping a host-level incident.
- Understanding where EDR stops and XDR (cross-domain correlation) begins.

## When not to use

- **SIEM/SOAR strategy, cross-source correlation, log management:** use `siem-soar-investigation`. EDR telemetry is one feed into a SIEM; the correlation and automation layer lives there.
- **Network-side detection** (IDS/IPS, NDR, NAC, micro-segmentation, packet/flow forensics): use `network-detection-response`. EDR sees the host; NDR sees the wire.
- **Vendor platform deep-dives** (a specific Falcon IOA rule, an MDE custom detection KQL, a Wazuh decoder): out of scope by design. The vendor skills are skipped/refer-only in this vault; this umbrella stays generic.
- **Identity-layer attacks with no endpoint artifact** (pure Kerberos/AD abuse): the detection methodology is here, but the identity surface itself is `identity-access-management`.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Detection methodology | IOA vs IOC, ML detection, ATT&CK mapping, EDR vs XDR vs MDR taxonomy | `references/detection-methodology.md` |
| Telemetry + hunting | event types, sensor pipeline, telemetry vs detection, retention, detection-engineering lifecycle, hunting | `references/telemetry-and-hunting.md` |
| Response + tuning | response actions, isolation, rollback, false-positive tuning, exclusion hygiene, sensor health, metrics | `references/response-and-tuning.md` |
| Platform selection | which EDR, feature matrix, deployment decision guide | `references/platform-selection.md` |

## Core model (condensed)

EDR collects host telemetry (process, file, registry, network, authentication, and on deep platforms memory) and turns it into detections. **Telemetry is not detection:** a sensor can record an event without alerting on it, and that stored telemetry is what makes threat hunting and forensic reconstruction possible after the fact.

Detection runs on a layered methodology, most reliable to most noisy:

1. **Signature / IOC** (file hashes, IPs, domains, registry keys, YARA): deterministic, low false-positive, but evaded by trivial obfuscation and blind to novel threats.
2. **Behavioural / IOA** (process lineage, injection patterns, API-call sequences, mass-encryption, LSASS reads): detects intent regardless of tool, catches LOLBin and fileless attacks, but needs tuning.
3. **Machine learning / heuristics**: generalises to new variants; model quality and explainability vary.
4. **Threat-intelligence correlation**: enriches detections with actor and campaign context.

Map detections to **MITRE ATT&CK** so coverage is measurable, and validate coverage with atomic tests and purple-team exercises rather than trusting vendor coverage claims. **EDR** is endpoint-centric; **XDR** correlates endpoint with network, cloud, identity, and email so a phishing-to-ransomware chain becomes one incident instead of two disconnected endpoint alerts. **EPP** (prevention/NGAV) blocks at execution; **EDR** detects and responds to what gets through; **MDR** is the managed-service wrapper around either.

**Response actions** escalate by blast radius: process kill and file quarantine (surgical) -> host isolation (cut all network except sensor comms) -> rollback/remediation (reverse attacker changes) -> remote shell and memory forensics (analyst-driven). Destructive or isolating actions need a manual playbook and an approval gate before they are automated.

**Tuning is the job, not an afterthought.** False positives come from IT automation, software updates, and security tools themselves. Suppress by specific process-plus-parent or signed-certificate, never by broad path or whole system directories, and document every exclusion with an owner and a review date.

**Anti-patterns:** detection-only mode left on when prevention was intended; trusting vendor ATT&CK claims without independent validation; broad path exclusions that an attacker can drop a payload into; automating an isolating response with no approval gate; treating EDR alerts as the whole picture when the attack lived in network or identity telemetry.

## Reference router

| Need | Load |
|---|---|
| IOC vs IOA vs ML vs threat-intel, the detection hierarchy, ATT&CK framework + high-value techniques + coverage evaluation, EDR/EPP/XDR/MDR taxonomy and cross-domain examples | `references/detection-methodology.md` |
| Telemetry event types, the sensor-to-backend pipeline, telemetry-vs-detection, retention defaults, the five-phase detection-engineering lifecycle, threat-hunting workflow | `references/telemetry-and-hunting.md` |
| Response action taxonomy, false-positive sources, tuning and exclusion hygiene, sensor health monitoring, performance overhead, detection-quality metrics | `references/response-and-tuning.md` |
| Cross-platform feature matrix, per-platform deployment decision guide (eight vendors as routing context), selection factors | `references/platform-selection.md` |

## Cross-references

- `siem-soar-investigation`: the correlation and automation layer EDR feeds; SOAR containment steps often trigger EDR isolation via API.
- `network-detection-response`: the network-side sibling; EDR sees the host, NDR sees the wire, and lateral movement shows in both.
- `incident-response-lifecycle`, `incident-response-network`: the process an EDR detection escalates into; this skill produces the host evidence those lifecycles consume.
- `oncall-runbooks`: every high-severity EDR alert should name the runbook to open.
- `identity-access-management`: credential-access detections (LSASS dumping, Kerberoasting, DCSync) target the identity surface that skill owns.
- `systematic-debugging`: the host timeline and process tree feed straight into root-cause analysis.
- `secrets-hygiene`: EDR API tokens and service-account credentials live in the secret store, never in scripts or saved queries.
- `utc-timestamps`: process and file event correlation depends on UTC, NTP-synchronised clocks; skewed host time corrupts the timeline.

## Red flags

- About to leave a sensor in detection-only mode when the intent was prevention.
- About to write a path-based exclusion that covers a whole system directory.
- About to automate host isolation or rollback with no manual playbook and no approval gate.
- About to claim ATT&CK coverage from a vendor brochure without an independent atomic or purple-team test.
- About to treat an EDR alert as the full incident when the kill chain ran through network or identity telemetry the endpoint never saw.
- About to assert a host timeline from endpoints whose clocks are not NTP-synchronised.
- About to put an EDR API token in a saved query, a script, or a dashboard export.

## Bottom line

Telemetry is not detection, and detection is not response. Engineer detections as code, map them to ATT&CK, and prove coverage with tests rather than brochures. Tune relentlessly and exclude surgically. Reserve isolating and destructive response for actions that already have a manual playbook and an approval gate. When the chain runs past the host, reach for the network and identity skills; EDR is one camera, not the whole room.
