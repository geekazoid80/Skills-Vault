---
name: prtg-network-monitoring
description: Use for PRTG Network Monitor (Paessler) configuration, operations, and tuning. Covers the sensor-based monitoring model and sensor-count optimisation, licensing tiers (free 100-sensor through unlimited), auto-discovery and device templates, the sensor catalogue (SNMP traffic/CPU/memory/custom-OID/trap-receiver, WMI CPU/memory/disk/service/event-log, NetFlow/IPFIX/sFlow/packet-sniffer flow sensors, HTTP/HTTP-advanced/SSL-certificate/REST web sensors, EXE/script/SSH/Python custom sensors), the on-premises architecture (core server, local probe, embedded database, web interface) versus PRTG Hosted Monitor SaaS, remote probe design over TLS (port 23560), maps and custom dashboards for NOC display, scheduled reports and SLA availability reporting, the notification system (triggers, methods, escalation chains, maintenance windows), and the HTTP/REST API for sensor and device automation. References architecture.md, sensors-and-discovery.md, operations.md. Triggers include "PRTG", "Paessler", "PRTG sensor", "sensor count", "PRTG Hosted Monitor", "remote probe", "PRTG map", "PRTG auto-discovery", "PRTG device template", "PRTG notification", "PRTG API", "WMI sensor", "PRTG NetFlow". For vendor-neutral network-monitoring DESIGN, paradigm choice, and platform selection (PRTG vs LibreNMS vs Kentik vs Zabbix) see network-monitoring-selection; for Kentik flow analytics see kentik-network-monitoring; for Cacti RRDtool graphing see cacti-network-monitoring; for the SNMPv3 credentials and API tokens PRTG uses see secrets-hygiene.
license: MIT
metadata:
  version: 1.0.0
---

# PRTG Network Monitor

> **Skill marker**: When applying this skill, begin your reply with `[skill: prtg-network-monitoring]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns PRTG configuration, operations, and tuning. It assumes the design decision (PRTG is the right platform for this network size, budget, and deployment posture) has already been made; for that decision see `network-monitoring-selection`. The depth here is the sensor model, the discovery and notification configuration, and the API automation that keeps a PRTG deployment healthy and within its licence.

## When to use

- Selecting sensor types for a device and optimising sensor count against the licence tier.
- Configuring auto-discovery and device templates for consistent, repeatable monitoring.
- Designing notification triggers, escalation chains, and maintenance windows.
- Building maps and dashboards for NOC display, or scheduled SLA/availability reports.
- Planning an on-premises core-plus-remote-probe topology, or choosing PRTG Hosted Monitor.
- Automating sensor and device management through the HTTP/REST API.
- Diagnosing sensor-count explosion, WMI performance, or remote-probe connectivity issues.

## When not to use

- **Deciding whether PRTG is the right platform**, choosing a monitoring paradigm, or comparing PRTG against LibreNMS, Kentik, Zabbix, or Cacti: `network-monitoring-selection` owns the design and the cross-platform comparison.
- **Kentik flow analytics, BGP monitoring, or DDoS detection**: `kentik-network-monitoring`. **Cacti RRDtool graphing**: `cacti-network-monitoring`.
- **Storing SNMPv3 credentials, WMI passwords, or API tokens**: `secrets-hygiene` owns the secret-store discipline; never inline a credential in a saved API call or a runbook.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / deployment | sensor-based model, licensing tiers, sensor-count optimisation, on-prem core/probe vs Hosted Monitor, remote probe design | `references/architecture.md` |
| Sensors + discovery | auto-discovery process, device templates, SNMP/WMI/flow/HTTP/custom sensor selection, polling intervals | `references/sensors-and-discovery.md` |
| Operations | maps/dashboards/reports, notification triggers and methods, escalation chains, maintenance windows, HTTP API automation, pitfalls | `references/operations.md` |

## Core model (condensed)

**Everything is a sensor, and sensors are the licence unit.** One sensor monitors one metric on one device: one SNMP traffic sensor per interface, one ping sensor per device, one WMI CPU sensor per Windows host. The licence tier (free 100, then 500/1,000/2,500/5,000, XL1/XL5, unlimited) caps the total, so sensor-count discipline is the core operational skill: disable auto-discovered sensors you do not need, use device templates to deploy only relevant sensors, and pause sensors on decommissioned devices.

**Auto-discovery plus device templates gives consistency.** Discovery pings an IP range, attempts SNMP/WMI on responsive hosts, identifies the device type, and applies a device template (a pre-defined sensor set). Without templates, discovery creates inconsistent sensor sets; define a template per device type before discovering at scale.

**Probes put the polling where the devices are.** The local probe runs on the core server; remote probes are Windows agents at remote sites or in a DMZ that connect outbound to the core over TLS (port 23560). They monitor without exposing SNMP over the WAN and cut WAN bandwidth by summarising locally. PRTG Hosted Monitor keeps the core in Paessler's cloud and uses remote probes for the on-premises network.

**Prefer SNMP over WMI for network devices.** WMI polling is resource-intensive on both PRTG and the target Windows host; use it only for Windows-specific metrics and use SNMP for everything else. Default 60-second intervals are unnecessary for most sensors; use 5 minutes for capacity and 60 seconds only for critical availability.

**The API changes are scriptable but the server is authoritative.** The HTTP API (table.json, pause.htm, historicdata.json, setobjectproperty.htm) drives bulk sensor deployment, maintenance automation, and external dashboards, authenticated by API token. There is no native core-server HA, so plan VM-level HA or use Hosted Monitor.

**Anti-patterns:** leaving every auto-discovered interface and disk sensor active (licence exhaustion); WMI where SNMP would do (host load); a 60-second interval on capacity sensors that need 5 minutes; remote probes blocked from outbound TLS 23560 (data gaps); flow sensors deployed without checking the licence tier; one giant map with hundreds of live overlays (slow rendering); assuming the single core server is highly available.

## Reference router

| Need | Load |
|---|---|
| Sensor-based model, licensing tiers, sensor-count optimisation, on-prem core/local-probe/embedded-DB/web-interface architecture, Hosted Monitor SaaS, remote probe architecture and use cases | `references/architecture.md` |
| Auto-discovery process and schedule, device templates, SNMP/WMI/flow/HTTP/custom sensor catalogue and selection, polling intervals | `references/sensors-and-discovery.md` |
| Maps, dashboards and reports, notification triggers/methods/escalation/maintenance-windows, HTTP API endpoints and authentication and automation use cases, common pitfalls | `references/operations.md` |

## Cross-references

- `network-monitoring-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether PRTG fits; this skill builds it. Reciprocal reference.
- `kentik-network-monitoring`, `cacti-network-monitoring`: sibling vendor skills for the other platforms in the family.
- `zabbix-templates-and-triage`: the alternative open-source-adjacent NMS; consult when comparing template-driven Zabbix against sensor-priced PRTG.
- `grafana-dashboards`: PRTG data can feed Grafana via the API for a unified single pane of glass across platforms.
- `secrets-hygiene`: SNMPv3 credentials, WMI passwords, and PRTG API tokens live in the secret store, never inline in a saved API call.
- `multi-vendor-network-ops`: diagnose-first operations that consume PRTG sensor alerts during a wider production network change.

## Red flags

- About to leave every auto-discovered sensor active and burn through the licence tier within days.
- About to monitor a network device with WMI where an SNMP sensor would be lighter on both ends.
- About to set a 60-second interval on capacity sensors that only need 5-minute polling.
- About to deploy a remote probe without opening outbound TLS 23560 to the core (it will disconnect and leave data gaps).
- About to add flow sensors without checking they fit the licence tier.
- About to build one map with hundreds of live sensor overlays instead of several focused maps.
- About to treat the single core server as highly available with no VM-level HA or Hosted Monitor plan.
- About to paste an SNMPv3 password or API token into a saved API URL instead of the secret store.

## Bottom line

In PRTG everything is a sensor and the sensor count is the licence, so the operational discipline is restraint: discover with templates, keep only the sensors you need, prefer SNMP over WMI, and poll at sensible intervals. Put remote probes where the devices are and open their outbound TLS path. Drive bulk changes through the API but remember the core server is authoritative and not natively HA. Bring the platform decision from `network-monitoring-selection`, and keep credentials in the secret store.
