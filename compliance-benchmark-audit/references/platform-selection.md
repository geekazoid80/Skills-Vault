# GRC platform selection

Routing context for the GRC automation platform landscape. This skill stays vendor-neutral; the platforms below are named so a request that mentions one can be placed, and so a selection decision has the field in view. The per-platform configuration depth is intentionally out of scope (the vendor agents are skipped / refer-only in this vault). The durable decision is *whether* and *what class* to automate, not which button to press in a given product.

---

## Manual vs automated: when a platform earns its keep

A GRC platform automates evidence collection and continuous monitoring; it does not create a control set, assign owners, or make a programme compliant. Sequence matters:

- **Stay manual (spreadsheets, shared drive)** when there is no control set yet, the framework count is one, and the team is small. A platform with nothing to automate is overhead.
- **Automate** once a mapped control set exists, the evidence burden is recurring (a SOC 2 Type II period, ISO surveillance), and integrations exist for the cloud / identity / endpoint estate. This is the Level 2 to Level 4 jump in the maturity model (see `risk-and-tprm.md`).

The anti-pattern is buying the platform first: it produces a tool configured around no controls, and the programme is no more compliant than before, just more expensive.

---

## The platform field (routing context)

| Platform | Sweet spot | Notable for |
|---|---|---|
| Vanta | SMB to mid-market SaaS automating SOC 2 / ISO 27001 / HIPAA / PCI | Fast time-to-audit, automated monitoring, trust centre / trust reports, vendor risk |
| Drata | SMB to mid-market SaaS, evidence-collection depth | Autopilot continuous evidence, personnel management and background checks, asset inventory automation |
| OneTrust | Privacy-led and larger organisations | Privacy management (GDPR / CCPA / DSAR), consent management, data mapping / RoPA, IT and third-party risk, AI governance |
| ServiceNow GRC (IRM) | Enterprises already on the Now Platform | Integrated risk management with native ITSM / SecOps integration; risk, policy/compliance, audit, vendor risk, continuous authorisation modules |
| Archer (RSA Archer) | Large enterprises, complex/operational risk | Highly configurable data model, quantitative risk, deep operational/IT risk, audit, third-party governance; on-prem or SaaS |

Rough shape of the field: **Vanta and Drata** are the automation-first, fast-to-audit choices for SaaS companies chasing a first SOC 2 or ISO certificate. **OneTrust** leads when privacy and consent are the centre of gravity rather than security attestation. **ServiceNow GRC** wins when the organisation already runs the Now Platform and wants risk and compliance integrated with existing ITSM and SecOps workflows. **Archer** suits large, risk-mature enterprises that need a deeply customisable model for operational and IT risk beyond a compliance checklist.

---

## Selection factors

- **Frameworks and time-to-audit.** Which frameworks must be supported now and next; how fast a first certificate is needed. Automation-first platforms shorten the first Type II.
- **Integration coverage.** Whether the platform has native integrations for your cloud (AWS / Azure / GCP), identity (Okta / Entra), and endpoint (Intune / Jamf / EDR) estate. Missing integrations mean manual evidence, which erodes the reason to automate.
- **Scope beyond compliance.** Privacy (favours OneTrust), enterprise operational risk (favours Archer), or platform-native workflow integration (favours ServiceNow) can outweigh raw automation speed.
- **Organisation size and maturity.** SMB/mid-market SaaS leans Vanta/Drata; large enterprise leans ServiceNow/Archer. Match the tool to the maturity level you are at, not the one you aspire to.
- **Total cost and configurability.** Configurable platforms (Archer, ServiceNow) carry implementation cost and need an owner; automation-first platforms trade flexibility for speed.
- **Evidence portability and read-only access.** Confirm evidence exports cleanly for auditors and that every integration uses a least-privilege, read-only identity held in the secret store (see `secrets-hygiene`). Avoid a platform that demands write access to systems it only needs to read.

Whatever the choice, the platform displays and automates the programme; it does not replace the control set, the owners, or the risk decisions that this skill's other references cover.
