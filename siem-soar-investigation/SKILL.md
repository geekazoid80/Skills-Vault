---
name: siem-soar-investigation
description: "Use for vendor-neutral SIEM and SOAR strategy, detection engineering, security log investigation, and SOC operations across any platform (Splunk, Microsoft Sentinel, Elastic Security, IBM QRadar, Google Chronicle/SecOps, Palo Alto XSIAM, CrowdStrike LogScale; SOAR via Cortex XSOAR, Splunk SOAR, Sentinel Playbooks, Tines, Torq). Covers the log-management lifecycle (collection, parsing, normalisation, enrichment, indexing, retention), event correlation, SIGMA detection-as-code, MITRE ATT&CK coverage mapping, normalisation standards (CIM, ECS, ASIM, UDM, OCSF), log-source onboarding and prioritisation, alert-triage tiers, SOC metrics (MTTD, MTTR, alert fidelity, coverage), cost optimisation, SOAR automation strategy and playbook design (enrichment, triage, containment), automation maturity, platform selection, and forensic timeline construction from network-device syslog with or without a SIEM. References: detection-engineering.md, normalisation-and-onboarding.md, soar-automation.md, platform-selection.md, network-log-forensics.md. Triggers include \"SIEM\", \"SOAR\", \"which SIEM\", \"SIEM comparison\", \"detection engineering\", \"detection as code\", \"SIGMA rule\", \"correlation rule\", \"log management\", \"normalisation standard\", \"ECS\", \"CIM\", \"ASIM\", \"UDM\", \"OCSF\", \"MITRE ATT&CK coverage\", \"alert triage\", \"alert fatigue\", \"MTTD\", \"MTTR\", \"SOC metrics\", \"SOC maturity\", \"playbook design\", \"phishing playbook\", \"containment playbook\", \"security automation\", \"log source onboarding\", \"ingestion cost\", \"threat hunting\", \"forensic timeline\", \"syslog investigation\", \"lateral movement detection\". For Graylog-specific query construction, streams, pipelines, and index lifecycle see graylog-log-investigation; for metrics-side triage see zabbix-templates-and-triage, grafana-dashboards, and prometheus-configuration; for endpoint and network response tooling see endpoint-detection-response and network-detection-response; for the runbook an alert should point to see oncall-runbooks; for token and credential handling in SIEM/SOAR integrations see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# SIEM and SOAR investigation

> **Skill marker**: When applying this skill, begin your reply with `[skill: siem-soar-investigation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for security information and event management (SIEM) and security orchestration, automation, and response (SOAR). It owns the cross-platform reasoning: how logs become detections, how detections are engineered and measured, what to automate and when, how to pick a platform, and how to reconstruct a forensic timeline from raw events. Platform-specific query syntax (SPL, KQL, EQL, AQL, YARA-L, XQL, LQL) is named only as routing context; the depth here is the methodology that survives a platform migration.

## When to use

- Choosing or comparing SIEM/SOAR platforms against requirements (cloud footprint, volume, budget, team maturity).
- Designing a detection-engineering programme: SIGMA, ATT&CK coverage, detection-as-code, testing and tuning.
- Planning log-source onboarding, normalisation, enrichment, retention, and ingestion-cost control.
- Defining alert-triage tiers, SOC metrics, and what to automate first in SOAR.
- Designing playbooks (enrichment, triage, containment, notification) and assessing automation maturity.
- Running a security log investigation: correlation, anomaly detection, timeline construction, classification.

## When not to use

- **Graylog-specific work** (Graylog query language, streams, pipelines, sidecars, index sets, rotation/retention): use `graylog-log-investigation`. That skill also carries the Elastic-Stack-as-log-backend comparison.
- **Metrics-side triage** (dashboards, thresholds, alerting on time-series): use `grafana-dashboards`, `prometheus-configuration`, `zabbix-templates-and-triage`. Metrics complement logs; they are not this skill.
- **Endpoint or network response tooling** (EDR/XDR agents, NDR/NAC sensors): use `endpoint-detection-response` and `network-detection-response`. This skill consumes their telemetry; it does not operate the sensors.
- **Vendor platform deep-dives** (a specific SPL search, a KQL analytics rule, an XSOAR playbook build): out of scope by design. The vendor skills are skipped/refer-only in this vault; this umbrella stays generic.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Detection engineering | SIGMA authoring, ATT&CK mapping, rule testing, tuning, detection-as-code | `references/detection-engineering.md` |
| Data pipeline | normalisation standards, parsing, enrichment, onboarding priority, retention, ingestion cost | `references/normalisation-and-onboarding.md` |
| SOAR / automation | what to automate, playbook patterns, automation maturity, ROI, integration architecture | `references/soar-automation.md` |
| Platform selection | which SIEM, which SOAR, comparison, decision tree | `references/platform-selection.md` |
| Log investigation | forensic timeline, correlation, anomaly detection, network-device syslog, with or without SIEM | `references/network-log-forensics.md` |

## Core model (condensed)

A SIEM runs a pipeline: **collect -> parse -> normalise -> enrich -> index -> correlate -> alert -> investigate -> report**. Cross-source correlation is impossible without normalisation, and detection quality is capped by pipeline quality (garbage in, garbage out). A SIEM without active, tuned detections is just an expensive log store.

**Detection engineering** is the lifecycle that turns threat knowledge into tuned, measured rules: threat intel -> data-source mapping -> detection logic (platform-native or SIGMA) -> testing -> tuning -> deployment -> metrics. Treat detections as code (version control, peer review, CI). Favour multi-event, multi-source correlation and risk-based scoring over single-event rules.

**SIGMA** is the vendor-agnostic rule format that compiles to each platform's query language via pySigma/sigma-cli, so a detection written once is portable. **Normalisation standards** map vendor field names to a common schema:

| Standard | Platform | Shape |
|---|---|---|
| CIM | Splunk | Data models, accelerated field names |
| ECS | Elastic | Hierarchical (`source.ip`, `process.name`) |
| ASIM | Sentinel | Query-time unifying parsers |
| UDM | Chronicle/SecOps | Entity-centric security schema |
| OCSF | Cross-platform | Open, AWS-originated, growing adoption |

**Alert triage** runs in tiers: Tier 0 automated (SOAR enrichment, dedup, known-FP suppression), Tier 1 validate-and-route, Tier 2 investigate, Tier 3 hunt. **SOC metrics** keep it honest: MTTD (< 1 hour for critical), MTTR (< 4 hours for critical), alert fidelity (> 80%; below 50% is alert fatigue), ATT&CK coverage (> 60% for top tactics), automation rate (> 40% for mature SOCs).

**SOAR** adds value when alert volume exceeds analyst capacity and the triage steps are codifiable. It does not replace human judgement, good detection engineering, or a defined manual process: automating a bad process just makes it faster. Automate in this order of return: phishing triage, IOC enrichment, alert dedup, then containment (account disable, endpoint isolate, IP/domain block) with approval gates.

**Anti-patterns:** collect-everything-detect-later (cost with no value), one-alert-per-threat (noise), SIEM-as-archive (no detections), copy-paste vendor rules (no tuning), ignoring the data pipeline (bad normalisation), SOAR over immature process, single-vendor lock-in (use SIGMA for portability).

## Reference router

| Need | Load |
|---|---|
| SIGMA rule structure/modifiers/backends, ATT&CK mapping, detection quality tiers, detection-as-code layout, SOC maturity model | `references/detection-engineering.md` |
| Collection methods, parsing (regex/grok/CEF/LEEF), the five normalisation standards in depth, enrichment, indexing/storage trade-offs, retention by compliance, onboarding priority (P1-P4), ingestion-cost tactics | `references/normalisation-and-onboarding.md` |
| When-to-use SOAR, playbook patterns (enrichment/triage/containment/notification/full-lifecycle), automation maturity model, ROI metrics, integration architecture | `references/soar-automation.md` |
| SIEM platform comparison + decision tree, SOAR platform comparison + selection guide, pairing SOAR to SIEM | `references/platform-selection.md` |
| Six-step forensic procedure, cross-platform query patterns (SPL/KQL/AQL) for seven use cases, raw-syslog analysis without a SIEM (rsyslog/syslog-ng, grep/awk/sort), vendor syslog formats (Cisco/JunOS/EOS), severity/confidence thresholds, report templates | `references/network-log-forensics.md` |

## Cross-references

- `graylog-log-investigation`: Graylog hands-on (query language, streams, pipelines, index sets); the Elastic-Stack-as-log-backend comparison lives there too.
- `grafana-dashboards`, `prometheus-configuration`, `zabbix-templates-and-triage`: metrics-side triage; metrics point the time window, logs supply the evidence.
- `endpoint-detection-response`, `network-detection-response`: sensor tooling whose telemetry feeds SIEM detections and SOAR containment.
- `oncall-runbooks`: every alert should name the runbook to open; SOAR notification steps carry the runbook URL.
- `systematic-debugging`: the investigation log and timeline feed straight into root-cause analysis.
- `secrets-hygiene`: SIEM/SOAR API tokens, service-account credentials, and integration secrets live in the secret store, never in playbooks or dashboard URLs.
- `compliance-benchmark-audit`: retention windows and audit-trail requirements (PCI DSS 10.7, HIPAA, SOX) that drive storage tiers.
- `utc-timestamps`: correlation and timeline accuracy depend on UTC, NTP-synchronised event times; skewed clocks corrupt every conclusion.

## Red flags

- About to recommend "collect everything" without mapping each source to a detection.
- About to ship single-event detections instead of correlated, risk-scored rules.
- About to automate a response action that has no manual playbook and no approval gate.
- About to compare events across sources that were never normalised to a common schema.
- About to assert a timeline from devices whose clocks are not NTP-synchronised.
- About to quote a platform-specific query as if it were portable; the methodology is portable, the syntax is not.
- About to put a SIEM/SOAR API token in a saved-search URL, a playbook, or a dashboard export.
- About to claim a detection programme is "covered" without an ATT&CK coverage measurement.

## Bottom line

Normalise before you correlate, tune before you trust, and measure before you claim coverage. Detections are code; playbooks codify a process you already run by hand. Pick the platform for your cloud, volume, and maturity, not the brochure. When investigating, build the timeline from NTP-true timestamps and write down the evidence as you go.
