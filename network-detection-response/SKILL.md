---
name: network-detection-response
description: Use for vendor-neutral network detection and response (NDR), intrusion detection and prevention (IDS/IPS), network security monitoring (NSM), network access control (NAC), and micro-segmentation strategy across any platform (Suricata, Snort, Zeek; Cisco ISE, Aruba ClearPass, FortiNAC; Illumio, Guardicore/Akamai). Covers signature vs behavioural vs protocol-anomaly detection, east-west vs north-south visibility, traffic-access methods (TAP, SPAN, inline, packet broker, VPC mirroring), encrypted-traffic analysis (JA3/JA4, certificate, flow metadata), lateral-movement detection, network forensics (PCAP, NetFlow/IPFIX, Zeek logs), MITRE ATT&CK network coverage, 802.1X and NAC deployment phases, micro-segmentation and application-dependency mapping, and platform selection. References detection-and-visibility.md, nac-and-segmentation.md, forensics-and-hunting.md, platform-selection.md. Triggers include "NDR", "network detection and response", "IDS", "IPS", "NSM", "network security monitoring", "Suricata", "Snort", "Zeek", "NAC", "network access control", "802.1X", "RADIUS posture", "Cisco ISE", "ClearPass", "FortiNAC", "micro-segmentation", "microsegmentation", "Illumio", "Guardicore", "east-west traffic", "north-south traffic", "lateral movement detection", "network visibility", "TAP vs SPAN", "packet broker", "JA3", "JA4", "encrypted traffic detection", "network forensics", "PCAP analysis", "NetFlow", "beaconing detection", "DNS tunneling". For SIEM/SOAR strategy and correlation that consumes NDR alerts see siem-soar-investigation; for host-side sensors (EDR/XDR, endpoint telemetry) see endpoint-detection-response; for firewall and ACL rule audits see acl-rule-analysis; for switch/router SPAN, TAP, and 802.1X configuration see multi-vendor-network-ops; for device and segment inventory see network-source-of-truth; for NAC tying device access to identity see identity-access-management; for the incident lifecycle a network alert feeds see incident-response-network and oncall-runbooks; for sensor and RADIUS secret handling see secrets-hygiene; for UTC-correct event timing see utc-timestamps.
license: MIT
metadata:
  version: 1.0.0
---

# Network detection and response

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-detection-response]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for detection and control at the network layer: intrusion detection and prevention (IDS/IPS), network security monitoring (NSM), network detection and response (NDR), network access control (NAC), and micro-segmentation. It owns the cross-platform reasoning: how to get visibility into traffic, how that traffic becomes detections, how to detect lateral movement, how to control which devices connect, and how to limit blast radius between workloads. Platform-specific syntax (Suricata rules, Snort inspectors, Zeek scripting, ISE policy sets, Illumio labels) is named only as routing context; the depth here is the methodology that survives a tooling change.

## When to use

- Designing network visibility: where to place sensors, TAP vs SPAN vs inline, east-west vs north-south coverage.
- Choosing or comparing IDS/IPS, NAC, or micro-segmentation tooling against requirements.
- Building network detection logic: signature vs behavioural, protocol anomaly, ATT&CK network mapping, tuning.
- Detecting lateral movement and reconstructing a network forensic timeline (PCAP, flow, Zeek logs).
- Handling encrypted traffic (JA3/JA4, certificate analysis, flow metadata, DNS) without breaking TLS.
- Planning a NAC rollout (802.1X, posture, profiling, phased enforcement) or a micro-segmentation programme.

## When not to use

- **SIEM/SOAR strategy and cross-source correlation:** use `siem-soar-investigation`. NDR alerts and Zeek logs are feeds into a SIEM; the correlation and automation layer lives there.
- **Host-side detection** (process, file, registry, memory telemetry): use `endpoint-detection-response`. NDR sees the wire; EDR sees the host.
- **Firewall and ACL rule audits** (shadowed rules, overly permissive rules, rule hygiene): use `acl-rule-analysis`. This skill designs where to detect and segment; that skill audits the rulebase.
- **Switch, router, and 802.1X device configuration** (the SPAN session, the TAP cabling, the authenticator config): use `multi-vendor-network-ops`. This skill decides the topology; that skill configures the gear.
- **Vendor platform deep-dives** (a specific Suricata rule, a Zeek script, an ISE policy set): out of scope by design. The vendor skills are skipped/refer-only in this vault.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Detection + visibility | IDS vs IPS vs NSM, detection taxonomy, TAP/SPAN/inline, east-west vs north-south, encrypted traffic | `references/detection-and-visibility.md` |
| NAC + segmentation | 802.1X, EAP methods, NAC phases, micro-segmentation, dependency mapping, enforcement boundaries | `references/nac-and-segmentation.md` |
| Forensics + hunting | evidence sources, investigation methodology, retention, protocol analysis, ATT&CK network coverage | `references/forensics-and-hunting.md` |
| Platform selection | which IDS/IPS, which NAC, which micro-segmentation, comparison and decision factors | `references/platform-selection.md` |

## Core model (condensed)

Network detection has three jobs: **see the traffic, judge the traffic, and control the traffic.**

**See it.** Sensors get traffic via a passive TAP (lossless, gold standard), a SPAN/mirror port (convenient, can drop under load), inline placement (can block, single point of failure without fail-open), or cloud VPC mirroring. The visibility problem is real: 80 to 95 percent of traffic is TLS-encrypted, east-west traffic is often 70 to 80 percent of volume and historically unmonitored, and cloud and ephemeral workloads slip past on-prem sensors. North-south (perimeter) is where the rules are richest; east-west (lateral) is where the attacker actually lives after the foothold.

**Judge it.** Detection layers from deterministic to noisy: signature (Suricata/Snort rules, low false-positive, blind to novel), protocol-anomaly (deviation from RFC behaviour), behavioural/statistical (Zeek baselines, beaconing regularity, catches the unknown but needs tuning), ML, and threat-intel matching. Deploy both signature and behavioural: rules catch the known, NSM metadata (Zeek) catches what no signature describes and feeds hunting. For encrypted traffic, fingerprint instead of decrypt: JA3/JA4 client TLS fingerprints, certificate analysis (self-signed, odd issuers), flow metadata (volume, timing, beaconing), and DNS patterns.

**Control it.** NAC decides who connects before they connect: 802.1X (supplicant, authenticator, RADIUS server) with EAP-TLS (certificate, strongest), PEAP (password in a tunnel), or MAB (MAC fallback, spoofable). Roll NAC out in phases (visibility, profiling, policy, pilot, enforcement) or it causes outages. Micro-segmentation enforces least privilege between workloads independent of topology: map application dependencies first, then ring-fence with deny-by-default and explicit allows. Both directly limit lateral movement (ATT&CK T1021, T1210, T1570).

**Anti-patterns:** an untuned default-rules IDS that drowns the SOC in noise; relying only on north-south detection while the attacker moves east-west; ignoring encrypted traffic so 80 percent of the wire is a blind spot; NAC enforcement with no monitor-only baseline (outage risk); micro-segmentation before visibility (you cannot write allow rules for paths you have not mapped); using Zeek as if it could block (it is passive, pair it with Suricata or a firewall).

## Reference router

| Need | Load |
|---|---|
| IDS vs IPS vs NSM, detection taxonomy (method and direction), the visibility problem, traffic-access methods, packet brokers, east-west vs north-south, encrypted-traffic strategy | `references/detection-and-visibility.md` |
| Why NAC, 802.1X components and EAP methods, NAC deployment phases, traditional vs micro-segmentation, application-dependency mapping, enforcement boundaries, east-west segmentation value | `references/nac-and-segmentation.md` |
| Forensic evidence sources (PCAP/flow/Zeek/IDS), the five-phase investigation methodology, retention guidance, per-protocol detection (DNS/HTTP/SMB/Kerberos/NTLM), ATT&CK network coverage, the attacker east-west playbook | `references/forensics-and-hunting.md` |
| IDS/IPS comparison (Suricata/Snort/Zeek), NAC comparison (ISE/ClearPass/FortiNAC), micro-segmentation comparison (Illumio/Guardicore), decision factors | `references/platform-selection.md` |

## Cross-references

- `siem-soar-investigation`: the correlation and automation layer NDR feeds; Zeek logs and IDS alerts are core SIEM sources, and SOAR containment can trigger network blocks.
- `endpoint-detection-response`: the host-side sibling; lateral movement shows on the wire (NDR) and on the host (EDR), and the strongest detections correlate both.
- `acl-rule-analysis`: segmentation and blocking decisions become firewall and ACL rules; that skill audits the rulebase this skill helps design.
- `multi-vendor-network-ops`: the SPAN session, TAP placement, and 802.1X authenticator config live on the switches and routers that skill operates.
- `network-source-of-truth`: device, subnet, and segment inventory that scopes where sensors and NAC enforcement belong.
- `identity-access-management`: NAC binds device access to identity (RADIUS, EAP-TLS certificates, posture); the identity surface itself lives there.
- `incident-response-network`, `incident-response-lifecycle`: the process a network detection escalates into; this skill produces the wire evidence those lifecycles consume.
- `oncall-runbooks`: every high-severity network alert should name the runbook to open.
- `systematic-debugging`: the connection timeline and protocol deep-dive feed straight into root-cause analysis.
- `secrets-hygiene`: RADIUS/TACACS+ shared secrets and sensor API tokens live in the secret store, never in configs committed to a repo.
- `utc-timestamps`: flow and packet correlation depends on UTC, NTP-synchronised clocks; skewed sensor time corrupts the timeline.

## Red flags

- About to enable inline IPS blocking before tuning, so the first false positive drops production traffic.
- About to design detection that only watches north-south while the threat model is post-breach lateral movement.
- About to treat an 80-percent-TLS network as visible without JA3/JA4, certificate, flow, or DNS analysis.
- About to switch NAC to enforcement with no monitor-only baseline and no device inventory.
- About to write micro-segmentation deny rules before mapping application dependencies.
- About to rely on Zeek to block, when Zeek is a passive analysis framework.
- About to assert a network timeline from sensors whose clocks are not NTP-synchronised.
- About to commit a RADIUS shared secret or a sensor API token into a config file or repo.

## Bottom line

See, judge, control. You cannot detect what you cannot see, so fix visibility (east-west included) before tuning rules. Run signature and behavioural detection together, and fingerprint encrypted traffic instead of pretending it is clear. Phase NAC in monitor-first, and map dependencies before you segment. Network and endpoint are two views of the same attack: correlate them through the SIEM rather than trusting either alone.
