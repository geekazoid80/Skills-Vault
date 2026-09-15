---
name: penetration-testing
description: "Use for OSSTMM-informed vulnerability-assessment and penetration-testing (VA/PT) engagement methodology: scoping an authorised penetration test or red-team exercise, writing rules of engagement (RoE), structuring a VA/PT report, applying OSSTMM's channel model (Human, Physical, Wireless, Telecommunications, Data Networks) and RAV (Risk Assessment Value) trust scoring, and running the phased methodology from reconnaissance through enumeration, authorised proof-of-concept exploitation, post-exploitation impact assessment, and reporting. Covers written-authorisation-first discipline, scope and time-window definition, allowed-technique boundaries, non-destructive exploitation validation, business-risk framing of findings, and remediation hand-off. References osstmm-model-and-scoping.md, engagement-phases.md, reporting-and-remediation.md; ships a rules-of-engagement template and an OSSTMM RAV score calculator. Triggers include \"penetration test\", \"pentest\", \"pen test\", \"red team\", \"red teaming\", \"OSSTMM\", \"rules of engagement\", \"RoE\", \"RAV score\", \"attack simulation\", \"adversary simulation\", \"exploitation validation\", \"proof of concept exploit\", \"VA/PT\", \"vulnerability assessment and penetration testing\". NOT for standing vulnerability-management programme operations (see vulnerability-management); NOT for the active scanning syntax itself once a scope is authorised (see nmap-scanning); NOT for web-application-specific OWASP Top 10 / ASVS testing depth (see application-security and its DAST/SAST/SCA children); NOT for the tactical external recon/OSINT sweep (see external-attack-surface-recon, this skill's recon-phase companion); NOT for ATT&CK-technique detection-coverage engineering (see attack-technique-mapping). This skill will not proceed with any active technique against a target without confirmed written authorisation naming scope, time window, and allowed techniques."
license: MIT
metadata:
  version: 1.0.0
---

# Penetration testing

> **Skill marker**: When applying this skill, begin your reply with `[skill: penetration-testing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for VA/PT engagement methodology, informed by OSSTMM (the Open Source Security Testing Methodology Manual). It owns the reasoning that survives any one tool or target: how an engagement is scoped and authorised, how OSSTMM's channels and trust-scoring model apply, the phased flow from recon to reporting, and the non-negotiable authorisation gate before any active technique. Tool-specific mechanics (active scanning syntax, a specific EASM platform, a specific scanner's API) live in the per-tool skills this one routes to.

## When to use

- Scoping a penetration test, red-team exercise, or adversary-simulation engagement, authorised or being authorised.
- Writing rules of engagement: scope, time window, allowed and disallowed techniques, escalation contact, data-handling rules.
- Applying OSSTMM's channel model to decide what an engagement actually covers (a "network pentest" request often silently excludes Physical and Human channels; make that explicit).
- Scoring residual trust/risk OSSTMM-style (porosity, controls, limitations → RAV).
- Running authorised, non-destructive exploitation to validate that a finding is real and exploitable, not just theoretically CVSS-scored.
- Structuring a VA/PT report: executive summary, technical findings, business-risk framing, remediation hand-off.

## When not to use

- **Standing vulnerability-management programme operations** (scan cadence, SLAs, ticket lifecycle on assets already in inventory): use `vulnerability-management`. This skill scopes and runs a bounded, authorised engagement; that one runs the ongoing programme.
- **Active host/port/service scanning mechanics** (nmap syntax, NSE scripts, scope-enforcement in the tool itself): use `nmap-scanning`. This skill decides *when and why* an active scan happens within an authorised engagement; that skill owns *how*.
- **Web-application-specific testing depth** (OWASP Top 10 categories, ASVS verification levels, DAST/SAST/SCA tooling): use `application-security` and its children. This skill's exploitation phase for a web target routes there rather than re-deriving AppSec methodology.
- **The tactical external recon/OSINT sweep itself** (subdomain enumeration, passive DNS, fingerprinting): use `external-attack-surface-recon`, this skill's recon-phase companion.
- **ATT&CK-technique detection-coverage engineering**: use `attack-technique-mapping`. An adversary-emulation engagement that deliberately chains ATT&CK techniques should still route the coverage-scoring question there.
- **Validating a third-party vendor's pentest report before acting on it**: that is a separate discipline (re-verifying someone else's findings against live state before trusting a vendor's severity rating); this skill is for running an engagement, not auditing one already delivered.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| OSSTMM model + scoping | channels (Human/Physical/Wireless/Telecommunications/Data Networks), RAV/porosity/controls/limitations, scope definition, rules-of-engagement structure | `references/osstmm-model-and-scoping.md` |
| Engagement phases | recon → enumeration → exploitation (PoC only) → post-exploitation impact → the authorisation gate at each transition | `references/engagement-phases.md` |
| Reporting + remediation | report structure, severity and business-risk framing, evidence handling, remediation hand-off to vulnerability-management | `references/reporting-and-remediation.md` |

## Core model (condensed)

**Written authorisation is the precondition, not a formality.** No active technique against any target proceeds without confirmed written authorisation naming the scope, the time window, the allowed techniques, and an escalation contact. This applies equally to an external consultant, an internal red team, and this skill itself: refusing to proceed without confirmation is the correct behaviour, not excessive caution. Where an organisation's own authorisation record lives is estate-specific; check for a local companion skill or standing document before assuming a target is cleared.

**OSSTMM measures security operationally, across channels, not as a single pass/fail.** A "penetration test" request is frequently scoped, by default, to only the Data Networks channel. OSSTMM names four others worth making explicit even when out of scope: Human (social engineering, phishing), Physical (badge/tailgating, hardware access), Wireless (Wi-Fi, Bluetooth, RF), and Telecommunications (VoIP, PBX). State explicitly which channels are in scope and which are deliberately excluded; an unstated exclusion reads later as a missed finding, not a scoping decision.

**Trust is porosity minus controls, adjusted for limitations.** OSSTMM's RAV (Risk Assessment Value) is a way to make "how secure is this" a number instead of a feeling: count the attack surface (porosity, meaning visible/reachable/trusted access points), count the operational controls actually present (the ten OSSTMM control classes: authentication, indemnification, resilience, subjugation, continuity, non-repudiation, confidentiality, privacy, integrity, alarm), and discount for known limitations (vulnerabilities, weaknesses, concerns, exposures, anomalies). See `references/osstmm-model-and-scoping.md` and the bundled `rav_score_calculator.py` for the mechanics; the point is not certification-grade OSSTMM compliance, it is a repeatable, defensible way to talk about residual trust rather than a bare severity adjective.

**Exploitation proves impact; it does not chase root.** Once a vulnerability is identified, authorised exploitation to proof-of-concept level demonstrates real impact (data access achieved, privilege gained, lateral path opened) without causing damage: no destructive payloads, no data exfiltration beyond a redacted proof sample, no persistence left behind, no availability impact. `rapid7-vulnerability-management` explicitly frames its Metasploit integration the same way (authorised exploitability validation only); this skill's exploitation phase holds the same line regardless of tooling.

**A finding is not done until it is a business-risk statement, not a CVSS number.** The report's executive summary translates "CVE-2026-XXXXX, CVSS 9.8" into what an attacker could actually do to the business (data exposed, service disrupted, financial/compliance impact) and what it costs to fix. Technical findings carry the CVSS/technical detail for the people who will remediate; the two audiences need different documents, not one document skimmed two ways.

**Anti-patterns:** running any active technique on an assumption of "implied" authorisation; scoping silently to Data Networks and never stating the excluded channels; treating exploitation as a trophy hunt (root/domain-admin) instead of a proof-of-impact exercise; a report that is a raw scanner export with a cover page; skipping the remediation hand-off so findings die in a PDF nobody re-checks.

## Reference router

| Need | Load |
|---|---|
| OSSTMM channels, RAV/porosity/controls/limitations conceptually, scope definition, rules-of-engagement structure | `references/osstmm-model-and-scoping.md` |
| Recon → enumeration → exploitation (PoC only) → post-exploitation impact assessment, the authorisation gate at each phase transition | `references/engagement-phases.md` |
| Report structure, severity/business-risk framing, evidence handling, remediation hand-off | `references/reporting-and-remediation.md` |
| Fill-in-the-blank rules of engagement | `examples/rules_of_engagement_template.md` |
| OSSTMM RAV score calculator | `scripts/rav_score_calculator.py` |

## Cross-references

- `nmap-scanning`: the active host/port/service scanning mechanics used during an authorised engagement's enumeration phase. This skill decides when it fires within an engagement; that skill owns the tool syntax and scope-enforcement.
- `external-attack-surface-recon`: this skill's reconnaissance-phase companion for the tactical OSINT/subdomain-enumeration sweep.
- `vulnerability-management`: the destination for remediation tracking once findings are reported; also the standing programme this skill's bounded engagement complements rather than replaces.
- `nvd-cve`: CVE lookup behind any finding that maps to a known vulnerability.
- `application-security` (and `dynamic-application-security-testing` / `static-application-security-testing` / `software-composition-analysis`): web-application-specific testing depth when the engagement scope includes an application.
- Any finding that originated from an automated scan rather than manual validation gets re-verified against live state before it appears in the report as confirmed, the same discipline `vulnerability-management` and `nvd-cve` already expect of scan output generally.
- `rapid7-vulnerability-management`: names the same "authorised exploitability validation only" boundary for its Metasploit integration; consistent framing, different context (standing VM programme versus a bounded engagement).
- `attack-technique-mapping`: for an adversary-emulation engagement structured around specific ATT&CK techniques, cross-reference the coverage-mapping model so the engagement also produces a validated coverage data point, not just a findings list.
- `compliance-benchmark-audit`: when the engagement exists to satisfy a compliance requirement (PCI DSS's mandated annual pentest, SOC 2, ISO 27001), that skill owns the framework-requirement side; this skill owns running the engagement itself.
- `secrets-hygiene`: any credentials used for authenticated testing, or discovered during the engagement, are handled per that skill, never written into the report in plaintext.

## Red flags

- About to run any active technique without confirmed written authorisation naming scope, time window, and allowed techniques.
- About to assume a channel (Physical, Human, Wireless, Telecommunications) is out of scope without stating that exclusion explicitly.
- About to run exploitation beyond proof-of-concept: destructive payloads, real data exfiltration, persistence left in place, or any availability impact.
- About to hand over a report that is a raw scanner export with a cover page, with no business-risk framing or remediation hand-off.
- About to treat "the client asked for a pentest" as authorisation for whatever technique seems useful, rather than confirming the specific RoE.
- About to skip re-verification of an automated scan's findings before including them in the report as confirmed.

## Bottom line

Nothing active happens without written authorisation naming scope, time window, and technique boundaries; that gate is the methodology's spine, not paperwork around it. Use OSSTMM's channel model to make scope explicit rather than silently Data-Networks-only, and its RAV thinking to talk about residual trust as a number instead of an adjective. Move recon → enumeration → proof-of-concept exploitation → impact assessment → reporting in that order, prove impact without causing damage, and close with a report that gives executives a business-risk story and engineers a remediation list, handed off to `vulnerability-management` to track to closure.
