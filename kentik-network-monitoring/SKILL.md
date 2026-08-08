---
name: kentik-network-monitoring
description: "Use for Kentik network observability configuration and operations: large-scale flow analytics, BGP monitoring, DDoS detection and mitigation, and the Kentik API. Covers the flow analytics engine (NetFlow v5/v9, IPFIX, sFlow, VPC Flow Logs, eBPF ingestion at billions of records per day with sub-second ad-hoc queries), flow enrichment (BGP AS path, GeoIP, RPKI validation, custom tags, device metadata), DDoS detection via ML baseline profiling and anomaly detection plus automated mitigation (RTBH, BGP Flowspec, A10, Radware, custom webhook), BGP route monitoring (prefix-hijack, route-leak, RPKI-invalid, subprefix-hijack detection and BGP+flow correlation), Kentik NMS (integrated SNMP device polling) and Kentik Map (automated topology), AI Insights (\"What Changed?\" root-cause analysis and natural-language queries), built-in synthetic monitoring, and automation through the REST API, the topXdata query API, the Terraform provider, and the Python SDK. References architecture.md, traffic-and-bgp.md, api-and-automation.md. Triggers include \"Kentik\", \"flow analytics\", \"NetFlow analyzer\", \"Kentik NMS\", \"Kentik Map\", \"DDoS detection\", \"DDoS mitigation\", \"RTBH\", \"Flowspec\", \"BGP monitoring\", \"BGP hijack\", \"route leak\", \"RPKI validation\", \"Kentik API\", \"topXdata\", \"network observability\", \"What Changed\". For vendor-neutral network-monitoring DESIGN, paradigm choice, and platform selection see network-monitoring-selection; for PRTG sensor monitoring see prtg-network-monitoring; for Cacti RRDtool graphing see cacti-network-monitoring; for security-driven flow detection and IDS/IPS see network-detection-response; for BGP routing-protocol troubleshooting (adjacency, path selection) see bgp-analysis; for the API tokens Kentik uses see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Kentik network observability

> **Skill marker**: When applying this skill, begin your reply with `[skill: kentik-network-monitoring]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Kentik configuration and operations. It assumes the design decision (Kentik is the right platform: a SaaS flow-and-BGP analytics engine at scale) has already been made; for that decision see `network-monitoring-selection`. The depth here is the flow query model, the DDoS and BGP detection configuration, and the API automation that drives a Kentik deployment.

## When to use

- Designing flow queries, dashboards, and alert policies for traffic analysis and capacity planning.
- Configuring DDoS detection (baseline profiling, anomaly thresholds) and automated mitigation (RTBH, Flowspec, scrubber API).
- Setting up BGP route monitoring and hijack/leak/RPKI detection, and correlating BGP changes with flow.
- Enabling Kentik NMS SNMP polling and Kentik Map topology alongside flow.
- Using AI Insights ("What Changed?") and natural-language queries to find a dominant dimension fast.
- Automating device onboarding, tags, and alert policies through the REST API, Terraform, or the Python SDK.

## When not to use

- **Deciding whether Kentik is the right platform**, choosing a monitoring paradigm, or comparing Kentik against PRTG, LibreNMS, or Zabbix: `network-monitoring-selection` owns the design and the cross-platform comparison.
- **PRTG sensor monitoring**: `prtg-network-monitoring`. **Cacti RRDtool graphing**: `cacti-network-monitoring`.
- **Security-driven flow detection, IDS/IPS, and east-west threat visibility**: `network-detection-response` owns security detection. Kentik does flow for capacity and DDoS here; NDR does flow for threat detection.
- **BGP routing-protocol troubleshooting** (adjacency down, path-selection debugging, route reflectors): `bgp-analysis`. This skill monitors BGP routes and alerts on changes; it does not troubleshoot the protocol.
- **Storing API tokens**: `secrets-hygiene` owns the secret-store discipline; never inline a token in a saved query or a script.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / data model | flow ingestion and scale, enrichment dimensions, the flow data model, Kentik NMS, Kentik Map | `references/architecture.md` |
| Traffic + BGP | DDoS detection/classification/mitigation, BGP route monitoring and hijack/leak/RPKI detection, BGP+flow correlation, AI insights | `references/traffic-and-bgp.md` |
| API + automation | REST API, topXdata query API, Terraform provider, Python SDK, synthetic monitoring, pitfalls | `references/api-and-automation.md` |

## Core model (condensed)

**Flow at scale, enriched and queryable in sub-seconds.** Kentik ingests NetFlow, IPFIX, sFlow, VPC Flow Logs, and eBPF into a proprietary time-series datastore that holds billions of records per day at full granularity for months, and answers ad-hoc multi-dimensional queries in under a second. The power is the enrichment: every flow is tagged with BGP AS path, GeoIP, RPKI status, the IANA application, device metadata, and user-defined custom tags, so a single query can pivot across all of them.

**Custom tags and a BGP feed are what make it useful.** Flow without a BGP feed lacks AS-path enrichment; flow without custom tags lacks business context (customer, site, application). Configure both, or queries return raw IPs with no story.

**DDoS detection is ML baselines plus automated mitigation.** Kentik profiles normal traffic per customer/network/application/interface, then alerts when current traffic exceeds the learned baseline by a configured multiplier, classifying the attack (volumetric, protocol, application). Mitigation is automated: RTBH announces a null route via a BGP community, Flowspec installs granular filter rules, or a scrubber API (A10, Radware) or custom webhook is triggered. Baselines need 2+ weeks to learn; tight thresholds during that window cause false positives.

**BGP monitoring detects routing security events.** Receiving full BGP feeds (and public collectors like RIPE RIS and RouteViews), Kentik alerts on prefix hijack, route leak, RPKI-invalid origins, and subprefix hijack, and correlates a route change with the traffic shift it caused.

**AI Insights finds the dominant dimension first.** "What Changed?" identifies the top contributing ASN, prefix, application, or interface for any anomaly in seconds, replacing slow manual query iteration; natural-language queries translate plain English into optimised flow queries.

**Anti-patterns:** flow sampling so aggressive (1:10000) that small flows vanish; running flow with no BGP feed (no AS-path context); skipping custom tags (no business context); DDoS thresholds tuned tight before the 2-week baseline learns; iterating queries manually instead of using "What Changed?"; trusting VPC Flow Logs that may sample or drop fields for billing or security; ignoring RPKI validation alerts.

## Reference router

| Need | Load |
|---|---|
| Flow ingestion sources and scale, query speed and retention, flow enrichment dimensions, the flow data model, Kentik NMS SNMP polling, Kentik Map topology | `references/architecture.md` |
| DDoS baseline profiling, anomaly detection, attack classification, automated mitigation (RTBH/Flowspec/A10/Radware/webhook), BGP route collection and hijack/leak/RPKI detection, BGP+flow correlation, AI Insights | `references/traffic-and-bgp.md` |
| REST API endpoints and auth, the topXdata query API, Terraform provider, Python SDK, synthetic monitoring, common pitfalls | `references/api-and-automation.md` |

## Cross-references

- `network-monitoring-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether Kentik fits; this skill builds it. Reciprocal reference.
- `prtg-network-monitoring`, `cacti-network-monitoring`: sibling vendor skills for the other platforms in the family.
- `network-detection-response`: security-driven flow detection and IDS/IPS. Kentik straddles flow-for-capacity-and-DDoS (here) and flow-for-threat-detection (NDR); cross-reference, no duplication.
- `bgp-analysis`: BGP routing-protocol troubleshooting (adjacency, path selection). This skill monitors and alerts on BGP routes; that diagnoses the protocol.
- `grafana-dashboards`: Kentik data can feed Grafana via the API for a unified single pane of glass.
- `secrets-hygiene`: Kentik API tokens and SNMPv3 credentials live in the secret store, never inline in a saved query or script.
- `multi-vendor-network-ops`: diagnose-first operations that consume Kentik flow alerts during a wider production network change.

## Red flags

- About to set a flow sampling rate so aggressive that small but important flows disappear.
- About to run flow analytics with no BGP feed, losing all AS-path enrichment.
- About to skip custom tags, so queries return raw IPs with no customer/site/application context.
- About to tune DDoS thresholds tight before the 2-week baseline has learned normal traffic.
- About to iterate flow queries by hand instead of letting "What Changed?" surface the dominant dimension.
- About to rely on VPC Flow Logs for billing or security without checking for sampling, delay, or missing fields.
- About to ignore RPKI-invalid alerts that flag a routing-security problem.
- About to paste a Kentik API token into a saved query or a script instead of the secret store.

## Bottom line

Kentik is flow analytics at scale, made useful by enrichment: feed it BGP and custom tags or queries have no story. DDoS detection is ML baselines plus automated RTBH/Flowspec/scrubber mitigation, and it needs two weeks to learn before you tighten thresholds. BGP monitoring catches hijacks, leaks, and RPKI-invalid routes and correlates them with traffic. Reach for "What Changed?" before manual query iteration. Bring the platform decision from `network-monitoring-selection`, route security detection to `network-detection-response` and BGP troubleshooting to `bgp-analysis`, and keep tokens in the secret store.
