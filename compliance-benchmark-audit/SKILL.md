---
name: compliance-benchmark-audit
description: Use for vendor-neutral governance, risk, and compliance (GRC) and technical benchmark auditing. Covers control frameworks (SOC 2, ISO 27001:2022, PCI DSS v4.0, HIPAA Security Rule, NIST CSF 2.0, NIST SP 800-53 Rev 5), risk management (qualitative 5x5 likelihood-by-impact, FAIR quantitative risk, the four treatment options), compliance automation and evidence collection, audit readiness and the audit lifecycle, third-party / vendor risk management (TPRM), policy management and attestation, the GRC maturity model, and configuration-baseline auditing (CIS Benchmarks, Level 1 vs Level 2 profiles, compliance scoring, gap analysis, priority-ranked remediation). The organising idea is framework-vs-benchmark thinking and map-once-comply-many control mapping. References frameworks.md, risk-and-tprm.md, benchmark-auditing.md, automation-and-evidence.md, platform-selection.md. Triggers include "GRC", "governance risk compliance", "compliance programme", "SOC 2", "SOC 2 Type II", "ISO 27001", "ISO 27001:2022", "PCI DSS", "PCI DSS v4.0", "HIPAA", "NIST CSF", "NIST 800-53", "FISMA", "FedRAMP", "CMMC", "control framework", "compliance framework", "risk register", "risk assessment", "risk treatment", "FAIR", "annualised loss expectancy", "CIS benchmark", "CIS hardening", "configuration baseline", "compliance audit", "audit readiness", "audit evidence", "evidence collection", "control mapping", "gap analysis", "POA&M", "TPRM", "third-party risk", "vendor risk", "vendor security questionnaire", "SIG", "CAIQ", "policy management", "policy attestation", "compliance automation", "continuous compliance", "GRC platform", "Vanta", "Drata", "OneTrust". For device-level CIS hardening of specific network firewalls see cisco-firewall-audit, fortigate-firewall-audit, palo-alto-firewall-audit, and checkpoint-firewall-audit; for AWS VPC and wireless audit evidence see aws-networking-audit and wireless-security-audit; for the SIEM retention and audit-trail requirements that compliance drives (PCI DSS 10.7, HIPAA, SOX) see siem-soar-investigation; for the identity controls every framework tests (MFA, access reviews, least privilege, deprovisioning) see identity-access-management; for credential and token handling in compliance-platform integrations see secrets-hygiene; for UTC-correct evidence timestamps see utc-timestamps. Cloud security posture (CSPM / CNAPP) and vulnerability-management programmes are adjacent concerns owned by their own families.
license: MIT
metadata:
  version: 1.1.0
---

# Compliance, benchmark, and GRC auditing

> **Skill marker**: When applying this skill, begin your reply with `[skill: compliance-benchmark-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for governance, risk, and compliance (GRC) and for technical benchmark auditing. It owns the reasoning that survives any one framework or platform: how control frameworks differ from configuration benchmarks, how risk decides which controls matter, how one mapped control set satisfies many frameworks, how audits run, what makes evidence defensible, and when a GRC automation platform earns its keep. Platform-specific tooling (Vanta integrations, Drata Autopilot, OneTrust privacy modules, ServiceNow GRC, Archer) is named only as routing context; the depth here is the methodology that outlasts a tooling change.

## When to use

- Standing up or maturing a compliance programme (SOC 2, ISO 27001, PCI DSS, HIPAA, NIST CSF) and choosing which controls to build.
- Mapping one control set across multiple frameworks so evidence is collected once, not per framework.
- Running a risk assessment: qualitative 5x5 scoring, FAIR quantitative analysis, and choosing a treatment (mitigate / accept / transfer / avoid).
- Auditing a system against a configuration benchmark (CIS) or a control catalogue (NIST SP 800-53), scoring it, and prioritising remediation.
- Preparing for an external audit: scoping, evidence collection, the fieldwork cycle, and what makes evidence pass.
- Assessing third-party / vendor risk (tiering, questionnaires, continuous monitoring) and running policy management and attestation.
- Deciding whether to automate compliance with a GRC platform, and which class of platform fits.

## When not to use

- **Device-level CIS hardening of a specific firewall** (the exact Cisco / FortiOS / PAN-OS / Check Point commands): use the firewall-audit skills. This umbrella owns the benchmark *methodology*; the per-vendor config audit lives there.
- **Cloud security posture management** (CSPM / CNAPP, misconfiguration scanning across a cloud estate): handled by the `cloud-security-posture` family. Compliance consumes its findings as evidence; it does not own the scanning.
- **Vulnerability scoring and remediation programmes** (CVSS / EPSS, scan-to-patch workflow): the `vulnerability-management` family. A framework requires vuln management; the programme itself lives there.
- **The mechanics of the controls themselves** (how to configure MFA, how to run a SIEM, how to encrypt data): those are owned by `identity-access-management`, `siem-soar-investigation`, and the relevant infrastructure skills. This skill decides *which* controls a framework needs and *how to prove* they work, not how to build each one.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Framework / compliance | which controls for SOC 2 / ISO 27001 / PCI / HIPAA / NIST CSF, TSC mapping, Annex A structure, cross-framework mapping | `references/frameworks.md` |
| Risk + third-party risk | 5x5 risk scoring, FAIR quantitative, treatment options, maturity model, vendor tiering, SIG/CAIQ, policy lifecycle | `references/risk-and-tprm.md` |
| Technical benchmark audit | CIS benchmark assessment, NIST 800-53 control-family check, scoring, gap analysis, priority-ranked remediation | `references/benchmark-auditing.md` |
| Automation + evidence | compliance automation patterns, cloud/identity/endpoint integrations, audit lifecycle, evidence quality | `references/automation-and-evidence.md` |
| Platform selection | which GRC platform, manual vs automated, when a platform earns its keep, selection factors | `references/platform-selection.md` |

## Core model (condensed)

GRC has three pillars that pull in one direction: **governance** sets the rules and accountability (policies, roles, board oversight), **risk** decides which rules matter (identify, assess, treat), and **compliance** proves to an outside party that the rules are followed. Controls exist to treat risk; evidence exists to prove the controls work.

**A framework is not a benchmark.** A control framework (SOC 2, ISO 27001, NIST CSF, PCI DSS) is an *organisational control set* you attest to: it says "enforce logical access control". A benchmark (CIS) is a *technical configuration baseline* you measure a specific system against: it says "set SSH to v2 only, disable Telnet". They meet in evidence: a benchmark scan result is evidence for a framework control. Confusing the two is the most common GRC error: a green CIS scan proves one control on one system, not that the programme is compliant.

**Map once, comply many.** A single well-designed control usually satisfies the same requirement in several frameworks: MFA on production maps to SOC 2 CC6, ISO 27001:2022 A.8.5, PCI DSS Req 8, and NIST IA-2 at once. Build a control set, map it to every framework you need, and collect each piece of evidence once. The alternative, running each framework as a separate project, multiplies effort and produces contradictory evidence.

**Risk comes before controls.** Score risk as likelihood times impact on a qualitative 5x5 matrix for triage; reach for FAIR (frequency of loss events times magnitude of loss, expressed in money) when a control-investment decision needs a dollar figure. Then choose a treatment: mitigate, accept (with a documented owner and expiry), transfer, or avoid.

**Evidence is the currency.** Good evidence is complete (covers the whole audit period), accurate (no cherry-picking), timely (generated while the control operated), traceable (who tested what, when), and authoritative (from the system of record, not a hand-built spreadsheet). Auditors test evidence, not intentions. Point-in-time assessments (SOC 2 Type I) prove design; period assessments (SOC 2 Type II, ISO surveillance) prove the control operated continuously, which is why continuous evidence collection beats an annual scramble.

**Anti-patterns:** treating compliance as an annual checkbox scramble; collecting evidence retroactively for a period the control was not actually operating; running every framework as a separate project instead of one mapped control set; buying a GRC platform before defining the control set it is meant to automate; accepting risk informally with no owner or expiry; reading a passing benchmark scan as a compliant programme.

## Reference router

| Need | Load |
|---|---|
| SOC 2 Trust Service Criteria, ISO 27001:2022 themes and new controls, PCI DSS v4.0 requirements, HIPAA safeguards, NIST CSF 2.0 functions, cross-framework mapping | `references/frameworks.md` |
| Risk methodology (5x5), FAIR quantitative model and worked example, the four treatment options, GRC maturity model, TPRM (vendor tiering, SIG/CAIQ, continuous monitoring), policy hierarchy and attestation | `references/risk-and-tprm.md` |
| CIS benchmark assessment method (profile selection, plane-by-plane audit, scoring, gap analysis), NIST SP 800-53 control-family assessment (AC/AU/CM/IA/SC/SI), severity tables, remediation prioritisation, report template | `references/benchmark-auditing.md` |
| Compliance automation patterns (pull / push / agent), cloud + identity + endpoint integration categories, the six-stage audit lifecycle, evidence quality standards and red flags | `references/automation-and-evidence.md` |
| GRC platform landscape (Vanta, Drata, OneTrust, ServiceNow GRC, Archer as routing context), manual vs automated decision, selection factors | `references/platform-selection.md` |

## Cross-references

- `cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`: device-level CIS hardening for specific firewall platforms. This umbrella owns the benchmark methodology; those own the per-vendor configuration audit that produces the evidence.
- `aws-networking-audit`, `wireless-security-audit`: sibling audit skills whose output is evidence for infrastructure and network controls.
- `siem-soar-investigation`: the log retention and audit-trail requirements compliance drives (PCI DSS 10.7, HIPAA, SOX); a SIEM is the evidence source for logging and monitoring controls. Reciprocal reference.
- `identity-access-management`: the identity controls almost every framework tests, MFA, access reviews, least privilege, joiner-mover-leaver deprovisioning. Compliance asks whether they exist and operate; IAM is how they are built.
- `secrets-hygiene`: GRC-platform API tokens and read-only service accounts live in the secret store, never in a script or saved query; least-privilege read-only roles for evidence collection.
- `utc-timestamps`: audit evidence must carry accurate UTC timestamps; auditors flag undated screenshots and clock-skewed logs.
- `systematic-debugging`: when a control passes on paper but fails in reality, trace the gap from claimed state to actual state.
- `oncall-runbooks`: incident-response controls (PCI DSS 12.10, ISO 27001:2022 A.5.24) need a runbook the audit can actually see exercised.

Vulnerability scoring and remediation programmes are owned by the `vulnerability-management` family; cloud security posture (CSPM / CNAPP) is owned by the `cloud-security-posture` family. Compliance consumes the findings of both as evidence but does not own the scanning.

## Red flags

- About to treat a passing CIS benchmark scan as framework compliance, when it is evidence for one control on one system.
- About to collect audit evidence retroactively to cover a period the control was not actually operating.
- About to attest to a framework with no mapped control set, so every new framework restarts from zero.
- About to buy a GRC automation platform before defining the control set it is meant to automate.
- About to accept a risk informally, with no documented owner, no expiry, and no reassessment date.
- About to send a vendor a bespoke questionnaire when a standard SIG or CAIQ would carry the same answer with less fatigue.
- About to store evidence as undated screenshots or hand-built spreadsheets instead of system-generated, timestamped reports.
- About to put a GRC-platform API token in a script, a saved query, or a dashboard export instead of the secret store.

## Bottom line

Governance sets the rules, risk decides which rules matter, and compliance proves you follow them. Build one control set, map it to every framework you need, and collect each piece of evidence once and continuously. A framework is an organisational claim; a benchmark is a technical measurement; evidence is what the auditor actually tests. Score risk before spending on controls, automate evidence before buying a platform to display it, and never confuse a green scan with a compliant programme.
