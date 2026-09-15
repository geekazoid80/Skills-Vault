---
name: attack-technique-mapping
description: "Use for MITRE ATT&CK-technique-mapped detection engineering: building or auditing detection coverage against the ATT&CK Enterprise (and Mobile/ICS) matrix, producing ATT&CK Navigator coverage layers, mapping telemetry data sources to techniques and sub-techniques, prioritising a detection-engineering backlog by technique prevalence and asset criticality, tagging new detection rules with technique IDs at authoring time, and validating claimed coverage with atomic tests (Atomic Red Team) or purple-team exercises rather than trusting vendor coverage claims. Covers matrix structure and sub-technique granularity, data-source-to-technique mapping, coverage heat-mapping (None/Partial/Good), cross-domain aggregation across endpoint, network, identity, and cloud telemetry, gap analysis and threat-intel-informed prioritisation, detection-rule-to-technique traceability, and the re-baseline discipline against ATT&CK's biannual matrix updates. References matrix-and-data-sources.md, coverage-and-prioritisation.md, validation-and-maturity.md. Triggers include \"MITRE ATT&CK\", \"ATT&CK matrix\", \"ATT&CK coverage\", \"ATT&CK Navigator\", \"technique mapping\", \"sub-technique\", \"detection coverage gap\", \"purple team\", \"atomic red team\", \"adversary emulation\", \"threat-informed defence\", \"TTPs\", \"tactics techniques and procedures\". NOT for platform-specific EDR, NDR, or SIEM/SOAR operations (see endpoint-detection-response, network-detection-response, siem-soar-investigation for the telemetry and rule-authoring mechanics this skill's coverage model sits above); NOT for CVE lookup or vulnerability scoring (see vulnerability-management, nvd-cve); NOT for AI/ML threat modelling (MITRE ATLAS and the OWASP Top 10 for LLM Applications are the sibling framework for that, named here as routing context only)."
license: MIT
metadata:
  version: 1.0.0
---

# Attack technique mapping

> **Skill marker**: When applying this skill, begin your reply with `[skill: attack-technique-mapping]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for MITRE ATT&CK-technique-mapped detection engineering. It owns the organising layer that survives any one platform: how detection coverage is scored against ATT&CK technique and sub-technique IDs, how the backlog is prioritised, and how a "Good" coverage claim is actually proven. Platform-specific telemetry pipelines and rule-authoring mechanics live in `endpoint-detection-response`, `network-detection-response`, and `siem-soar-investigation`, all three of which already assert "map detections to ATT&CK" as a discipline; this skill is the depth behind that assertion.

## When to use

- Standing up a threat-informed detection-engineering practice: mapping existing detections to ATT&CK techniques for the first time.
- Building or updating an ATT&CK Navigator coverage layer to communicate real detection coverage to stakeholders.
- Scoping technique gaps across EDR, NDR, and SIEM/SOAR telemetry, especially after a new adversary group's TTPs are published.
- Prioritising a detection-engineering backlog by technique prevalence and asset criticality.
- Validating a "we detect that" claim with an atomic test or a purple-team exercise rather than trusting a vendor's coverage marketing.
- Re-baselining coverage against ATT&CK's roughly twice-yearly matrix updates (new techniques, retired techniques, sub-technique splits).

## When not to use

- **Platform-specific EDR/NDR/SIEM operations** (telemetry pipelines, rule syntax, alert tuning): use `endpoint-detection-response`, `network-detection-response`, or `siem-soar-investigation`. This skill owns the ATT&CK-technique organising layer; those own the mechanics of the detections themselves.
- **CVE lookup and vulnerability scoring/prioritisation**: use `nvd-cve` and `vulnerability-management`. ATT&CK is about adversary behaviour, not software flaws.
- **AI/ML system threat modelling**: MITRE ATLAS is ATT&CK's sibling framework for AI/ML attacks, paired with the OWASP Top 10 for LLM Applications; named here as routing context only, not owned by this skill.
- **Cloud-specific attack-path tracing** (toxic combinations, IAM privilege chains): use `cloud-security-posture`, which already covers "MITRE ATT&CK for cloud" techniques in depth.
- **Incident response and forensics** once an ATT&CK-mapped technique is actually observed live: use `incident-response-lifecycle` / `incident-response-network`.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Matrix + data sources | tactics/techniques/sub-techniques, Enterprise vs Mobile vs ICS, data-source-to-technique mapping, ATT&CK Navigator mechanics | `references/matrix-and-data-sources.md` |
| Coverage + prioritisation | heat-mapping method (None/Partial/Good), cross-domain aggregation, gap scoring, threat-intel-informed prioritisation | `references/coverage-and-prioritisation.md` |
| Validation + maturity | atomic testing, purple-team cadence, detection-to-technique traceability, re-baseline discipline, maturity model | `references/validation-and-maturity.md` |

## Core model (condensed)

**A technique ID is the unit of account, not a vendor feature name.** "We have EDR" says nothing measurable. "We detect T1059.001 (PowerShell) with Good confidence, validated by atomic test in the last 90 days" does. Organise every coverage conversation around technique and sub-technique IDs.

**Data sources decide what's even detectable.** Before claiming coverage for a technique, confirm the telemetry that would prove it: process-creation logs for execution techniques, authentication logs for credential techniques, network flow for lateral movement. A technique with no data source behind it is a documentation gap, not a detection gap, and the fix differs (get the telemetry, versus write the rule).

**Coverage is a spectrum, not a checkbox.** Score each technique None / Partial / Good: None = no data source; Partial = data source exists but no tuned detection; Good = a tuned, validated detection with a known false-positive rate. Publish this as an ATT&CK Navigator layer so stakeholders see the real picture, not a marketing claim.

**Prioritise by what adversaries actually do, not by what's easy to detect.** Weight the gap-closing backlog by technique prevalence in current threat intelligence for your sector, plus the criticality of the assets a technique would compromise. A rare technique against a crown-jewel asset can outrank a common technique against a disposable one.

**Trust is earned by testing, not asserted by vendors.** A "Good" coverage claim must be validated: run an atomic test (Atomic Red Team or equivalent) or a purple-team exercise that actually executes the technique and confirms the alert fires. An untested "Good" entry is a Partial entry wearing a better label.

**Anti-patterns:** claiming coverage from a vendor's marketing matrix instead of your own validated telemetry; treating a Navigator layer as a one-off exercise instead of a living artefact re-baselined against matrix updates; prioritising by ease-of-detection instead of adversary prevalence and asset criticality; shipping a detection with no technique ID tag, which makes future coverage audits impossible.

## Reference router

| Need | Load |
|---|---|
| Matrix structure, sub-techniques, Enterprise/Mobile/ICS, data-source-to-technique mapping, Navigator layer mechanics | `references/matrix-and-data-sources.md` |
| Heat-mapping method, cross-domain aggregation, gap scoring, threat-intel-informed prioritisation | `references/coverage-and-prioritisation.md` |
| Atomic testing, purple-team cadence, detection-to-technique traceability, maturity model, re-baseline discipline | `references/validation-and-maturity.md` |

## Cross-references

- `endpoint-detection-response`: owns the EDR telemetry pipeline and detection-engineering mechanics this skill's coverage model sits above; that skill already asserts "map detections to ATT&CK" as a discipline, this skill is the depth behind it.
- `network-detection-response`: same relationship for NDR/IDS/IPS; cites specific technique IDs (T1021, T1210, T1570) for lateral movement that this skill's coverage model organises.
- `siem-soar-investigation`: SIGMA-based detection-engineering lifecycle and the "ATT&CK coverage > 60% for top tactics" SOC metric; this skill is the technique-mapping methodology behind that metric.
- `cloud-security-posture`: owns "MITRE ATT&CK for cloud" attack-path tracing in depth; reciprocal reference for cloud-specific technique coverage.
- `nvd-cve`: threat-intel-informed prioritisation draws on known-exploited-vulnerability data from here.
- MITRE ATLAS (no local skill yet): the AI/ML sibling framework, paired with the OWASP Top 10 for LLM Applications for AI-system threat modelling; named as routing context only.

## Red flags

- About to claim "we detect X" from a vendor datasheet instead of a validated technique-by-technique coverage layer.
- About to mark a technique "Good" coverage with no atomic test or purple-team validation behind it.
- About to build a Navigator layer once and never re-baseline it against a matrix update.
- About to prioritise the detection-engineering backlog by ease of implementation instead of technique prevalence and asset criticality.
- About to ship a new detection rule with no technique ID tag.
- About to treat this skill as the place to design the EDR/NDR/SIEM pipeline itself, rather than the technique-coverage layer that sits above it.

## Bottom line

Organise detection coverage around ATT&CK technique and sub-technique IDs, not vendor feature names. Confirm the data source before claiming a technique is even detectable, score coverage None/Partial/Good honestly, and never call it "Good" without an atomic test or purple-team exercise proving the alert fires. Prioritise the backlog by adversary prevalence and asset criticality, publish the result as a living Navigator layer, and re-baseline against every matrix update. Route the underlying telemetry and rule-authoring mechanics to `endpoint-detection-response`, `network-detection-response`, and `siem-soar-investigation`; this skill is the ATT&CK-technique organising layer above all three.
