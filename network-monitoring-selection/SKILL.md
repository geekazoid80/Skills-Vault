---
name: network-monitoring-selection
description: Use for vendor-neutral network monitoring and NMS DESIGN, monitoring-paradigm choice, and platform selection. Covers the four monitoring paradigms (SNMP polling for device health, flow analytics for traffic analysis, synthetic monitoring for user experience, packet capture for forensics), golden signals for the network (latency, traffic, errors, saturation, plus availability, jitter, packet loss, path changes), SNMP internals (v1/v2c/v3, security levels, key OIDs, GET/GET-BULK/TRAP/INFORM, polling intervals, 64-bit counters), flow protocols (NetFlow v5/v9, IPFIX, sFlow, VPC Flow Logs, flow enrichment with BGP/GeoIP/tags), synthetic test types (ICMP/TCP/traceroute/HTTP/DNS/web-transaction/BGP, cloud vs enterprise vs endpoint agents, path visualisation), alerting design (static vs baseline vs rate-of-change vs composite thresholds, severity tiers, alert-fatigue mitigation via deduplication/dampening/correlation/maintenance-windows, escalation patterns), SNMP traps and syslog, topology discovery (LLDP/CDP/SNMP/BGP), monitoring at scale (distributed polling, hot/warm/cold storage tiers, capacity-planning matrix by device count), and which platform to choose (SolarWinds NPM vs LibreNMS vs PRTG vs Kentik vs Zabbix vs Nagios vs Cacti vs ThousandEyes). The organising idea is pick-the-paradigm-from-the-question, let golden signals frame what to measure, alert on actionable signals, then choose the platform by scale, budget, and deployment model. References concepts.md, paradigms-and-signals.md, alerting-and-scale.md, platform-selection.md. Triggers include "network monitoring", "NMS", "NMS selection", "network monitoring comparison", "which NMS", "SNMP monitoring", "SNMP polling", "flow analytics", "NetFlow", "sFlow", "IPFIX", "synthetic monitoring", "golden signals", "monitoring architecture", "alerting strategy", "alert fatigue", "network observability", "distributed polling", "monitoring at scale", "capacity planning monitoring", "topology discovery", "SNMP trap", "syslog monitoring". For PRTG configuration and operations see prtg-network-monitoring; for Kentik flow analytics, DDoS, and BGP monitoring see kentik-network-monitoring; for Cacti RRDtool graphing and polling see cacti-network-monitoring. For application and infrastructure metrics, dashboards, and tracing see grafana-dashboards, prometheus-configuration, and distributed-tracing; for Zabbix templates and triage see zabbix-templates-and-triage. For routing-protocol troubleshooting see bgp-analysis, igp-routing-analysis, and evpn-vxlan-fabric; for security-driven flow detection and IDS/IPS see network-detection-response; for log correlation see siem-soar-investigation. SolarWinds NPM, LibreNMS, and ThousandEyes are named here only as routing context; deep per-vendor depth for those is not yet in this vault.
license: MIT
metadata:
  version: 1.0.0
---

# Network monitoring and NMS design

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-monitoring-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for network monitoring and NMS design. It owns the reasoning that survives any one product: which monitoring paradigm answers the question, what the golden signals are for a network, how to design alerts that get acted on instead of ignored, how monitoring scales across sites, and which platform earns the deployment. Platform-specific configuration (PRTG sensors, Kentik flow queries, Cacti graph templates) lives in the per-vendor skills; the depth here is the design that outlasts a platform change.

## When to use

- Choosing a monitoring paradigm for a given question (device health, traffic analysis, user experience, or forensics).
- Designing an alerting strategy that reduces noise and ensures every alert is actionable.
- Selecting an NMS for a given network size, budget, and on-premises-versus-SaaS posture.
- Designing the golden signals and data-collection tiers for a network monitoring stack.
- Planning monitoring at scale: distributed polling, storage tiers, retention, capacity planning.
- Comparing platforms (SolarWinds, LibreNMS, PRTG, Kentik, Zabbix, Nagios, Cacti, ThousandEyes) and choosing one.
- Designing the integration between an NMS, a flow platform, a synthetic platform, and a dashboard or SIEM.

## When not to use

- **Configuring a specific platform** (the exact PRTG sensor set, Kentik flow query, or Cacti graph template): use `prtg-network-monitoring`, `kentik-network-monitoring`, or `cacti-network-monitoring`. This umbrella owns the design; those own the syntax and operations.
- **Application and infrastructure metrics, dashboards, and tracing** (Prometheus exporters, Grafana dashboards, OpenTelemetry spans): `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing` own those. This skill owns the network-device-centric paradigm framing; `zabbix-templates-and-triage` owns Zabbix, which straddles into SNMP device monitoring.
- **Model-driven streaming telemetry and the receiver/collector tier** (gNMI, gNOI, NETCONF/YANG-push, Cisco MDT, OpenConfig sensor paths, gnmic/Telegraf/OTel collectors): `network-streaming-telemetry` owns the push-based fifth paradigm and its collectors. This umbrella frames the classic four paradigms (SNMP polling, flow, synthetic, packet capture) and selects platforms; it points at streaming telemetry as the push alternative to SNMP polling rather than owning it.
- **Routing-protocol troubleshooting** (BGP adjacency, OSPF/IS-IS/EIGRP convergence, EVPN-VXLAN): `bgp-analysis`, `igp-routing-analysis`, and `evpn-vxlan-fabric` own diagnosis. This skill monitors routing state; it does not troubleshoot the protocol.
- **Security-driven flow detection and IDS/IPS** (threat detection from flow, east-west visibility for security): `network-detection-response` owns that. This skill uses flow for capacity and traffic analysis, not security detection.
- **Log correlation and SOC investigation** (SIEM detection engineering, SOAR automation): `siem-soar-investigation` owns the security log pipeline; this skill forwards NMS alerts and syslog to it.
- **SolarWinds NPM, LibreNMS, ThousandEyes deep configuration**: named here as routing context only; deep per-vendor depth for those is not yet in this vault.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Protocol fundamentals | SNMP versions and OIDs, GET-BULK vs GET-NEXT, NetFlow vs sFlow vs IPFIX, traps and syslog, topology discovery | `references/concepts.md` |
| Paradigm + signals | SNMP polling vs flow vs synthetic vs packet capture, golden signals, synthetic test types and agents | `references/paradigms-and-signals.md` |
| Alerting + scale | threshold strategies, alert-fatigue mitigation, escalation, distributed polling, storage tiers, capacity planning | `references/alerting-and-scale.md` |
| Platform selection | SolarWinds vs LibreNMS vs PRTG vs Kentik vs Zabbix vs Nagios vs Cacti, decision matrix, architecture and integration patterns | `references/platform-selection.md` |

## Core model (condensed)

**Pick the paradigm from the question.** Device health (interface utilisation, CPU, memory, up/down) is SNMP polling. Traffic analysis (who is talking to whom, which application, capacity by destination) is flow analytics. User experience (is the SaaS app reachable and fast from where the users are) is synthetic monitoring. Deep forensics (TCP retransmits, protocol bugs, security investigation) is packet capture. Most networks need SNMP plus flow; add synthetic when users depend on SaaS or multi-ISP paths, add packet capture only for the hard problems.

**Golden signals frame what to measure.** Adapted from SRE: latency (RTT, path delay), traffic (bandwidth, flow volume), errors (interface errors, discards, CRC), and saturation (CPU, memory, buffer, queue depth). The network adds availability, jitter, packet loss, and path changes. Decide which signals matter for each service before choosing how to collect them, not after.

**Alert on actionable signals, not raw thresholds.** A static threshold (CPU > 90%) is simple but noisy; a learned baseline cuts false positives; rate-of-change catches sudden failures; a composite condition (CPU high AND memory high AND sustained) is the quietest. Alert fatigue is the single biggest operational problem: every alert needs a documented response, deduplication and dampening suppress floods, parent/child correlation collapses a device-down storm into one alert, and maintenance windows silence planned work. An alert nobody acts on should be deleted, not tuned.

**Collect at the right interval and retain in tiers.** Five minutes for capacity metrics, sixty seconds for availability, sub-minute only where a dashboard truly needs it. Use 64-bit counters (ifXTable) on gigabit-plus interfaces or they wrap. Sample flow on high-volume cores (1:1000 to 1:4096) and keep it unsampled on the edge. Store hot for days, warm at reduced resolution for months, cold and aggregated for compliance years.

**Scale with distributed polling.** A single poller handles roughly 500 to 2,000 devices depending on OID count and interval. Beyond that, deploy remote pollers per site that report to a central NMS: it cuts WAN bandwidth, survives a WAN partition, and keeps polling local.

**Then choose the platform.** Match the network size, budget, deployment posture, and dominant paradigm to the product: open-source self-hosted (LibreNMS, Cacti, Zabbix) for budget-conscious or homelab-to-mid-enterprise; sensor-priced on-premises or SaaS (PRTG) for predictable SMB-to-mid-market deployment; enterprise on-premises (SolarWinds NPM) for large estates with dedicated teams; SaaS flow-and-BGP at scale (Kentik) for service providers and DDoS-sensitive networks; SaaS synthetic (ThousandEyes) for SaaS-dependent and multi-ISP shops. No single platform is best at every paradigm; a complete stack often combines an NMS, a flow platform, a synthetic platform, and a unifying dashboard.

**Anti-patterns:** using flow analytics to answer a device-health question (or SNMP to answer a traffic question); polling every interface at sixty seconds when five minutes would do; 32-bit counters on high-speed links; static thresholds everywhere with no baselines and no correlation; alerts with no documented response; one central poller for a 5,000-device multi-site network; buying a platform before the dominant paradigm and the device count are known.

## Reference router

| Need | Load |
|---|---|
| SNMP versions/security/OIDs/operations/polling, NetFlow v5/v9, IPFIX, sFlow, VPC Flow Logs, flow enrichment, traps and syslog, topology discovery | `references/concepts.md` |
| The four paradigms and what each is best for, golden signals for the network, synthetic test types, agent types, path visualisation | `references/paradigms-and-signals.md` |
| Threshold strategies, severity tiers, alert-fatigue mitigation, escalation patterns, data-collection best practices, distributed polling, storage tiers, capacity planning | `references/alerting-and-scale.md` |
| Platform profiles (SolarWinds, LibreNMS, PRTG, Kentik, Zabbix, Nagios, Cacti, ThousandEyes), decision matrix, architecture patterns (single-site/distributed/hybrid), integration (NMS+flow+synthetic, SIEM, ITSM, Grafana) | `references/platform-selection.md` |

## Cross-references

- `prtg-network-monitoring`: PRTG sensor-based configuration, auto-discovery, remote probes, maps and notifications, HTTP API. This umbrella decides whether PRTG fits; that skill builds it.
- `kentik-network-monitoring`: Kentik large-scale flow analytics, DDoS detection and mitigation, BGP monitoring, AI insights, API. Reciprocal reference.
- `cacti-network-monitoring`: Cacti RRDtool graphing, poller tuning, data and graph templates, threshold alerting. Reciprocal reference.
- `zabbix-templates-and-triage`: Zabbix is both a general monitoring platform and an SNMP-capable NMS; consult it for Zabbix templates, low-level discovery, and triage. This umbrella frames the paradigm; that skill builds the Zabbix side.
- `grafana-dashboards`: the unifying visualisation layer across NMS, flow, and synthetic data sources; an NMS often feeds Grafana for a single pane of glass.
- `prometheus-configuration`, `distributed-tracing`: application and infrastructure metrics and tracing, the observability counterpart to network-device monitoring.
- `network-streaming-telemetry`: model-driven streaming telemetry (gNMI, MDT, YANG-push) and the receiver/collector tier, the push-based alternative to SNMP polling. This umbrella frames the classic four paradigms; that skill owns the fifth.
- `network-detection-response`: security-driven flow detection, IDS/IPS, and east-west visibility. This skill uses flow for capacity; NDR uses it for threat detection (Kentik straddles both).
- `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`: routing-protocol troubleshooting. This skill monitors routing state and alerts on route changes; those diagnose the protocol.
- `siem-soar-investigation`: forward NMS alerts and syslog here for correlation with security events; network context enriches security investigations.
- `secrets-hygiene`: SNMPv3 credentials, API tokens, and read/write community strings live in the secret store, never inline in a config or a saved query.
- `multi-vendor-network-ops`: diagnose-first operations that consume NMS alerts and telemetry as input artefacts during a wider production network change.

## Red flags

- About to answer a device-health question with flow analytics, or a traffic-analysis question with SNMP polling.
- About to poll every interface at sixty seconds when five minutes meets the need, multiplying load for no benefit.
- About to monitor gigabit-plus interfaces with 32-bit counters that wrap before the next poll.
- About to deploy static thresholds everywhere with no baselines, no dampening, and no parent/child correlation.
- About to create an alert with no documented response procedure (it will be ignored within a week).
- About to run a single central poller for a multi-site network of thousands of devices instead of distributed pollers.
- About to choose a platform before the dominant paradigm (device health vs traffic vs user experience) and the device count are known.
- About to put SNMPv3 credentials or an API token inline in a config or saved query instead of the secret store.

## Bottom line

Pick the paradigm from the question: device health is SNMP, traffic is flow, user experience is synthetic, forensics is packet capture. Let the golden signals decide what to measure before you decide how to collect it. Alert only on signals someone will act on, and kill alerts that nobody does. Collect at sensible intervals, retain in tiers, and distribute pollers once one box cannot keep up. Choose the platform from the network size, budget, deployment posture, and dominant paradigm, not from familiarity, and route all per-vendor configuration to the PRTG, Kentik, and Cacti skills.
