---
name: proofpoint-enterprise
description: "Use for Proofpoint Enterprise (the people-centric Email Protection platform, not the Essentials SMB line) configuration, operations, and read-only audit. Covers Email Protection / Secure Email Gateway (SEG / PPS) inbound and outbound mail flow, policy routes and filter rules, the six quarantine folders and End User Digest; Targeted Attack Protection (TAP) attachment sandboxing and Dynamic Delivery; Enterprise URL Defense v2/v3 rewriting, time-of-click analysis, and URL Isolation; Threat Response Auto-Pull (TRAP) post-delivery remediation, abuse-mailbox automation, and the M365 Graph / Google Gmail integration; Nexus People Risk Explorer, Very Attacked People (VAP), and the attack index; Email Fraud Defense (EFD) DMARC management, supplier risk, and lookalike-domain monitoring; Emerging Threats / Nexus threat intelligence; Smart Search message investigation; email DLP and Proofpoint Encryption. Also carries a read-only audit lens: policy-route and rule ordering and shadow detection, TAP allow-on-timeout posture, URL Defense coverage gaps, TRAP automation-rule confidence thresholds, VAP-to-policy binding, DMARC enforcement stance, and quarantine hygiene, with a threshold table and remediation decision trees. When not to use: for the Proofpoint Essentials SMB / MSP SaaS tenant model (organisation -> domain -> user -> alias, End User Digest self-service, per-tenant Sender Lists, delisting via Sender Support) see proofpoint-essentials, which explicitly is NOT the Enterprise line; for vendor-neutral sender-side deliverability (SPF, DKIM, DMARC rollout, warmup, suppression) see smtp-deliverability; for Microsoft-native email security (Exchange Online Protection, Defender for Office 365 Safe Attachments / Safe Links, ZAP) see defender-for-office-365. This skill owns Proofpoint Enterprise configuration and operations. References architecture.md, operations.md, api-and-automation.md. Triggers include \"Proofpoint Enterprise\", \"Proofpoint SEG\", \"Proofpoint PPS\", \"Email Protection\", \"Proofpoint TAP\", \"Targeted Attack Protection\", \"Proofpoint URL Defense\", \"URL Isolation\", \"Proofpoint TRAP\", \"Threat Response Auto-Pull\", \"Proofpoint VAP\", \"Very Attacked People\", \"Nexus People Risk\", \"attack index\", \"Email Fraud Defense\", \"Proofpoint DMARC\", \"Proofpoint EFD\", \"Emerging Threats\", \"Proofpoint Nexus\", \"Proofpoint Smart Search\", \"Proofpoint quarantine\", \"Proofpoint SIEM API\", \"Proofpoint People API\", \"Proofpoint TRAP API\", \"attachment defense\", \"Dynamic Delivery\". For the Essentials SMB / MSP tenant model see proofpoint-essentials; for Microsoft-native email security see defender-for-office-365."
license: MIT
metadata:
  version: 1.0.0
---

# Proofpoint Enterprise

> **Skill marker**: When applying this skill, begin your reply with `[skill: proofpoint-enterprise]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Proofpoint Enterprise configuration, operations, and read-only policy audit across the people-centric Email Protection platform: the Secure Email Gateway (SEG, also called PPS, the Proofpoint Protection Server), Targeted Attack Protection (TAP), Enterprise URL Defense and URL Isolation, Threat Response Auto-Pull (TRAP), Nexus People Risk Explorer and Very Attacked People (VAP), Email Fraud Defense (EFD), Nexus threat intelligence, and Smart Search. It is the Enterprise counterpart to `proofpoint-essentials`, which owns the SMB / MSP Essentials SaaS product; the two products share a name and a URL-Defense concept but not a tenant model, an admin UI, an API surface, or a policy engine, so do not carry assumptions across (the boundary is stated reciprocally under When not to use and Cross-references).

## Overview

Proofpoint Enterprise is a people-centric email security suite built from separately licensed modules that share a gateway and a threat-intelligence backbone:

- **Email Protection (SEG / PPS)**: the core inline gateway. The organisation's MX points at Proofpoint (`*.pphosted.com`), mail is filtered through an ordered engine stack (connection reputation, anti-virus, anti-spam, content, authentication), then delivered to the backend mailbox provider (M365, Google Workspace, on-prem Exchange). Outbound mail relays through the same gateway for DLP, encryption, and signing.
- **Targeted Attack Protection (TAP)**: cloud sandbox detonation for attachments and the analysis engine behind URL Defense, powered by Nexus threat intelligence.
- **Enterprise URL Defense + URL Isolation**: rewrites URLs at delivery, re-checks them at time of click, and optionally renders risky pages in a remote isolation browser.
- **Threat Response Auto-Pull (TRAP)**: post-delivery remediation. Pulls a message that turned malicious after delivery out of every mailbox that received it, and automates the abuse mailbox.
- **Nexus People Risk Explorer / VAP**: the people-centric model. Ranks who is actually attacked (the Very Attacked People) so policy and training follow the risk, not the org chart.
- **Email Fraud Defense (EFD)**: DMARC management, supplier risk, and lookalike-domain monitoring.
- **Smart Search**: the message-trace and investigation database.

The through-line is people-centric: TAP tells you which threats are landing, Nexus tells you who they land on, and TRAP + URL Defense + policy act on that. An audit follows the same thread: are the controls bound to the people most attacked, and is anything allowed that is never inspected.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (which modules are licensed, cloud versus on-prem PPS deployment, the backend mailbox provider, the IdP, the current DMARC stance) before commanding the platform. Only ask the user for what is not already covered.

Classify the request first, because the depth lives in different references:

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / platform | SEG mail-flow and filtering stack, TAP sandbox and Nexus intelligence, URL Defense v2/v3 encoding and click-time flow, TRAP integration architecture, VAP / attack-index model, EFD DMARC processing, deployment models (cloud versus on-prem PPS) | `references/architecture.md` |
| Operations + audit | Policy routes and filter rules, quarantine folders and End User Digest, TAP dashboards and allow-on-timeout, TRAP playbooks and abuse mailbox, URL Defense config and isolation, DMARC enforcement, DLP and encryption, plus the read-only audit lens with thresholds and decision trees | `references/operations.md` |
| API + automation | TAP SIEM API, TAP People (VAP) API, TRAP API, auth models, endpoint tables, key response fields, rate limits, pagination, secret-store discipline | `references/api-and-automation.md` |

Then establish:

1. **Which module and which task.** SEG policy, TAP / URL Defense tuning, TRAP remediation, VAP / people-risk analysis, EFD / DMARC, or the API surface. Classify before acting.
2. **The deployment model.** Cloud (Proofpoint-hosted, the common case) or on-prem PPS appliances / VMs, and which regional cluster (US, EU, APAC) for data residency.
3. **The backend and the integrations.** M365 (Graph), Google Workspace (Gmail API), or on-prem; TRAP needs an app registration or service account with the right scope, and that scope is a security decision.
4. **The identity and people substrate.** VAP and Nexus lean on directory identity; policy that follows the risk needs the VAP feed wired to the groups the policy targets.
5. **Read-only versus change.** An audit uses read-only API scope and never releases a message, pulls a message, or activates a policy change. A configuration change needs a maintenance window and a rollback path.

## When to use

- Building or tuning SEG policy: policy routes, filter rules and their ordering, quarantine-folder routing, spam-threshold and disposition tuning.
- Configuring TAP: attachment-defense file coverage, sandbox allow-on-timeout posture, Dynamic Delivery, malicious / suspicious dispositions.
- Configuring Enterprise URL Defense: rewrite scope, time-of-click blocking, the bypass list, and URL Isolation for risky categories or VAP users.
- Running TRAP: manual and automated remediation, confidence-threshold automation rules, the abuse-mailbox workflow, and the M365 / Google integration.
- Analysing people risk: pulling the VAP list, reading the attack index, and binding stricter policy or training to the most-attacked users.
- Managing EFD: DMARC report processing, moving a domain from monitor to quarantine to reject, supplier-risk and lookalike-domain monitoring.
- Investigating a message in Smart Search, exporting TAP / TRAP events to a SIEM, or automating any of the above through the APIs.
- Running a read-only policy audit: rule ordering and shadows, TAP timeout posture, URL Defense coverage gaps, TRAP threshold sanity, VAP-to-policy binding, DMARC stance, quarantine hygiene.

## When not to use

- **Proofpoint Essentials, the SMB / MSP SaaS product**: use `proofpoint-essentials`. That is a different product line with its own tenant model (reseller -> organisation -> domain -> user -> alias), its own admin UI and Sender Support portal, its own five-type quarantine and End User Digest self-service, and its own per-tenant Sender Lists and delisting flow. It explicitly warns it is NOT the Enterprise line, and this skill does NOT cover the Essentials tenant model. Route SMB / MSP questions, `ppe-hosted.com` bounce triage, Sender Lists, and Essentials delisting there. Reciprocal reference.
- **Vendor-neutral sender-side deliverability** (SPF, DKIM, DMARC four-phase rollout, IP warmup, suppression, list hygiene, the abstraction interface): use `smtp-deliverability`. That owns the sender-side baseline; this skill owns what changes when Proofpoint Enterprise is the destination filter or the platform you operate.
- **Microsoft-native email security** (Exchange Online Protection, Defender for Office 365 Safe Attachments, Safe Links, zero-hour auto purge, attack simulation training): use `defender-for-office-365`. Consult it when comparing or running Proofpoint alongside the Microsoft stack, or when locking M365 so mail cannot bypass the Proofpoint gateway.
- **Storing the TAP service credentials, the People API key, the TRAP API token, or the M365 app-registration secret / Google service-account key**: use `secrets-hygiene`. Never inline a live secret in a saved API call, a runbook, or a config file.

This skill **owns Proofpoint Enterprise configuration and operations**. Route the Essentials product, vendor-neutral deliverability, and the Microsoft-native stack out per the list above; keep everything SEG / TAP / TRAP / URL Defense / Nexus / EFD / Smart Search here.

## Core model (condensed)

**The gateway is an ordered engine stack, and order is load-bearing.** SEG filters inbound mail through connection reputation, anti-virus, anti-spam, TAP sandbox (if licensed), URL Defense (if licensed), content policies, and authentication, in that sequence. Policy routes decide which policy applies to which traffic; filter rules within a route evaluate top-down with an action precedence (block > quarantine > discard > encrypt > deliver). A broad rule above a specific one shadows it; rule-order review is the first audit step on any rulebase.

**People-centric means the controls should follow the VAP, not the title.** Nexus ranks users by an attack index that weights sophistication, not raw volume, so the Very Attacked People are often not the executives. The high-value move is to bind stricter controls (force-sandbox all attachments, URL Isolation, tighter click policy) to the VAP group, and the high-value finding is a VAP list that no policy references.

**TAP verdicts and TRAP close the loop after delivery.** A URL benign at delivery can weaponise later; URL Defense re-checks at click time, and TRAP pulls a message that turned malicious out of every mailbox that received it (including forwarded copies) via the M365 Graph or Gmail API. TRAP automation rules gate on a confidence score: auto-remediate high confidence, queue medium for an analyst. A threshold set too loose auto-pulls false positives; too tight leaves malicious mail sitting.

**Allow-on-timeout and the URL Defense bypass list are the blind-spot controls.** If TAP sandbox detonation times out, the policy either holds the message or delivers it; "deliver on timeout" is a time-sensitive-attack bypass. The URL Defense bypass list (SSO URLs that break when rewritten, banking partners with signature validation) is uninspected by design, so it is a security decision, not just a compatibility one.

**DMARC enforcement is a staged rollout, never a flip.** EFD ingests aggregate reports, maps every sending source, then moves a domain monitor -> quarantine -> reject only once legitimate streams are aligned. Flipping to reject with an unmapped stream kills legitimate mail; the sender-side alignment work belongs to `smtp-deliverability`.

## Cross-references

- `proofpoint-essentials`: the SMB / MSP Essentials SaaS product, a different Proofpoint product line. Owns the Essentials tenant model, Sender Lists, End User Digest self-service, and Sender Support delisting; this skill does not. Reciprocal reference; route Essentials work there.
- `defender-for-office-365`: Microsoft-native email security (EOP, Safe Attachments, Safe Links, ZAP). Sibling in the same skill family; consult when comparing, layering, or locking M365 to the Proofpoint gateway.
- `smtp-deliverability`: vendor-neutral sender-side discipline (SPF, DKIM, DMARC rollout, warmup, suppression). Provides the sender-side baseline that EFD enforcement depends on; this skill adds the Proofpoint-destination specifics.
- `secrets-hygiene`: the TAP service credentials, People API key, TRAP token, and the M365 app-registration secret / Google service-account key live in the secret store, never inline in a saved API call or runbook.
- `siem-soar-investigation`: TAP SIEM-API events, URL-Defense click logs, and TRAP audit trails feed the SIEM; a SOAR playbook can drive TRAP remediation. That skill owns the investigation and automation workflow; this one owns the Proofpoint side of the feed.

## Red flags

- A SEG filter rule ordered so a broad allow shadows a specific block, or a policy route that sends traffic to a policy that no longer matches the intent.
- TAP allow-on-timeout set to deliver rather than hold: a sandbox timeout becomes a delivery path for a time-sensitive attack.
- A URL Defense bypass-list entry that is broader than it needs to be (a wildcard domain, an internal category) turning a compatibility fix into a standing uninspected path.
- URL Defense rewriting disabled globally to fix a single vendor's link compatibility, instead of a scoped per-sender or per-domain exception.
- A TRAP automation rule that auto-remediates on a low confidence score (false-positive mailbox deletions) or one so tight that confirmed-malicious mail waits in an analyst queue past its SLA.
- The TRAP M365 app registration granted broader Graph permission than `Mail.ReadWrite` needs, or a Google service account with wider domain-wide-delegation scope than the Gmail-modify and directory-read it uses.
- A Very Attacked People list that no policy, training assignment, or URL Isolation rule references: the people-centric signal collected but not acted on.
- Moving an EFD-managed domain to DMARC `reject` before every legitimate sending stream is mapped and aligned; legitimate mail dies at enforcement.
- Releasing a virus, phish, or malicious-attachment quarantine, or pulling a message via TRAP, during what was scoped as a read-only audit.
- Pasting a TAP service secret, a People API key, a TRAP token, or an M365 / Google integration credential into a saved API URL, a runbook, or a committed file.
- Assuming Proofpoint Essentials documentation, tenant model, or Sender Support flow applies to Enterprise; the products diverge.
- Backhauling all inbound mail through an on-prem PPS cluster after the estate has moved to the cloud gateway, or the reverse, without a mail-flow validation and a rollback MX.

## Bottom line

Proofpoint Enterprise is a people-centric suite: the SEG gateway filters in an ordered engine stack where rule order is load-bearing, TAP and Nexus tell you which threats land and on whom, and URL Defense + TRAP act after delivery. Win security by binding the strictest controls to the Very Attacked People, holding (not delivering) on sandbox timeout, keeping the URL Defense bypass list tight, gating TRAP automation on a sane confidence threshold, and staging DMARC enforcement rather than flipping it. Bring the sender-side deliverability baseline from `smtp-deliverability`, route the Essentials SMB product and the Microsoft-native stack to their own skills, and keep every credential in the secret store. Verify every change against Smart Search and the TAP / TRAP audit trail before claiming done.

## Reference files

- `references/architecture.md`: the module map and licensing split, SEG mail flow and the ordered filtering stack, cloud versus on-prem PPS deployment and regional clusters, TAP attachment sandboxing and Dynamic Delivery, URL Defense v2/v3 encoding and the time-of-click flow with URL Isolation, TRAP integration architecture (M365 Graph and Google Gmail), the Nexus / VAP / attack-index people-centric model, Email Fraud Defense DMARC processing and supplier risk, and Nexus / Emerging Threats intelligence.
- `references/operations.md`: policy-route and filter-rule configuration, the quarantine folders and End User Digest, TAP dashboards and allow-on-timeout posture, TRAP playbooks and the abuse-mailbox workflow, URL Defense configuration and isolation, DMARC enforcement staging, email DLP and Proofpoint Encryption, and the read-only audit lens with a threshold table and remediation decision trees.
- `references/api-and-automation.md`: the TAP SIEM API, the TAP People (VAP) API, and the TRAP API, their auth models with placeholder tokens only, per-endpoint tables with key response fields, rate limits and backoff, pagination, and the secret-store discipline for Proofpoint API credentials.
