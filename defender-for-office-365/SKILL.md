---
name: defender-for-office-365
description: "Use for Microsoft Defender for Office 365 (MDO) configuration, operations, and read-only policy audit. Covers the email and collaboration security stack layered on Exchange Online Protection (EOP): Safe Links (delivery-time rewrite and time-of-click protection), Safe Attachments (sandbox detonation, Dynamic Delivery, and the SharePoint/OneDrive/Teams variant), anti-phishing (spoof intelligence, user and domain impersonation protection, mailbox intelligence, composite authentication), anti-spam and anti-malware policies, preset security policies (Standard and Strict) with the Configuration Analyzer, Threat Explorer and Real-time detections, Attack Simulation Training, Automated Investigation and Response (AIR), quarantine with quarantine policies, user reported messages and the submissions portal, Zero-hour Auto Purge (ZAP), the Email entity page, Tenant Allow/Block List (TABL), the Plan 1 versus Plan 2 feature split, and the Microsoft Graph Security and Threat Submission APIs plus Exchange Online PowerShell for read-only audit. Also carries a read-only audit lens: preset-policy versus custom-policy drift, Configuration Analyzer gaps, Safe Attachments in Monitor rather than Block, Safe Links click-through allowed, impersonation protection unconfigured for priority accounts, ZAP disabled, and quarantine policies with no end-user visibility. When not to use: for endpoint EDR and device threat protection (Microsoft Defender for Endpoint, KQL device hunting, onboarding) see endpoint-detection-response; for external attack surface discovery (Defender EASM) see defender-easm; for zero-trust IDENTITY governance (Entra ID, MFA, conditional access, PAM, IGA) see identity-access-management; for a third-party email gateway in front of the tenant see proofpoint-enterprise or proofpoint-essentials; for vendor-neutral sender-side deliverability (SPF, DKIM, DMARC, warmup) see smtp-deliverability. This skill owns Microsoft Defender for Office 365 configuration and operations. References architecture.md, operations.md, api-and-automation.md. Triggers include \"Defender for Office 365\", \"Microsoft Defender for Office 365\", \"MDO\", \"Office 365 ATP\", \"Defender O365\", \"Safe Links\", \"Safe Attachments\", \"Dynamic Delivery\", \"anti-phishing policy\", \"impersonation protection\", \"spoof intelligence\", \"mailbox intelligence\", \"anti-spam policy\", \"anti-malware policy\", \"preset security policy\", \"Standard and Strict preset\", \"Configuration Analyzer\", \"Threat Explorer\", \"Real-time detections\", \"Email entity page\", \"Attack Simulation Training\", \"Automated Investigation and Response\", \"AIR\", \"ZAP\", \"zero-hour auto purge\", \"quarantine\", \"quarantine policy\", \"user reported messages\", \"submissions\", \"Tenant Allow/Block List\", \"TABL\", \"Exchange Online Protection\", \"EOP\", \"Defender O365 audit\", \"MDO policy review\", \"Plan 1 vs Plan 2\". For endpoint EDR see endpoint-detection-response; for external attack surface see defender-easm; for identity governance see identity-access-management."
license: MIT
metadata:
  version: 1.0.0
---

# Microsoft Defender for Office 365

> **Skill marker**: When applying this skill, begin your reply with `[skill: defender-for-office-365]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Microsoft Defender for Office 365 (MDO) configuration, operations, and read-only policy audit: the email and collaboration security stack that Microsoft layers on top of Exchange Online Protection (EOP). It assumes the platform decision (Microsoft-native email security rather than a third-party gateway in front of the tenant) has already been made; for a third-party gateway see `proofpoint-enterprise` or `proofpoint-essentials`, and for vendor-neutral sender-side deliverability see `smtp-deliverability`. The depth here is the detonation and filtering pipeline, the policy model with its preset baselines, Threat Explorer hunting and AIR, and the read-only audit lens that keeps a tenant at least-privilege and fully covered.

## Overview

MDO is the paid tier above EOP. EOP is the always-on baseline (connection filtering, anti-malware, anti-spam, spoof intelligence, basic anti-phishing) included with every Exchange Online mailbox; MDO Plan 1 and Plan 2 add the sandbox, the URL rewrite, the impersonation model, and the investigation surface. The pieces a tenant usually runs are:

- **Safe Attachments**: sandbox detonation of attachments (and the SharePoint, OneDrive, and Teams variant) before or alongside delivery, with Dynamic Delivery to hide the detonation latency.
- **Safe Links**: delivery-time URL rewrite plus time-of-click reputation and detonation, so a link that was clean at delivery is still checked when the user clicks it.
- **Anti-phishing**: user and domain impersonation protection, mailbox intelligence (the contact-graph model), and spoof intelligence with composite authentication.
- **Threat Explorer and Real-time detections**: the hunting and investigation surface over recent mail flow.
- **AIR (Automated Investigation and Response)**: playbook-driven investigation and remediation, Plan 2 only.
- **Attack Simulation Training**: benign simulated phishing to measure and train users, Plan 2 only.

ZAP (Zero-hour Auto Purge) runs continuously after delivery, retroactively pulling mail that turns malicious. Preset security policies (Standard and Strict) plus the Configuration Analyzer are the fastest route to a sound baseline.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (which licence tier, the mail-flow topology, whether a third-party gateway sits in front of the tenant, the IdP, the EDR) before advising. Only ask for what is not already covered.

Before configuring or auditing, establish:

1. **The licence tier.** EOP (every Exchange Online mailbox), Plan 1 (Business Premium, E3 with the Defender for Office 365 P1 add-on), or Plan 2 (E5, E5 Security). Safe Attachments, Safe Links, and impersonation protection need Plan 1; Threat Explorer, AIR, Attack Simulation Training, and campaign views need Plan 2. Getting the tier wrong means advising a capability the tenant does not have.
2. **The mail-flow topology.** MX pointed straight at `*.mail.protection.outlook.com`, or a third-party gateway (a SEG) in front. A SEG in front changes what MDO sees; enhanced filtering (the skip-listing connector) must be configured or MDO filters the SEG IP instead of the true sender.
3. **Preset versus custom policies.** Standard and Strict presets, custom Safe Attachments / Safe Links / anti-phish / anti-spam / anti-malware policies, or a mix. Presets always win over custom policies in evaluation order, which is a common source of "my custom rule never fires" confusion.
4. **The task class.** Policy configuration and tuning, threat investigation and hunting, incident response and remediation, or a read-only posture audit. The depth lives in different references.
5. **Read-only versus change.** An audit uses read-only Graph and Exchange Online scope and never releases from quarantine, submits to Microsoft, or activates a policy. A configuration change needs a change window and a rollback plan (presets make rollback easy: disable the preset, the prior state returns).

## When to use

- Building or tuning MDO policy: Safe Attachments action and Dynamic Delivery, Safe Links scope and click-through settings, anti-phishing impersonation lists and thresholds, anti-spam and anti-malware policy, quarantine policies and end-user release.
- Standing up a baseline fast with the Standard or Strict preset security policy, and running the Configuration Analyzer to find drift from Microsoft's recommended settings.
- Investigating in Threat Explorer or Real-time detections: isolating a phish campaign, tracing a message, reading the Email entity page, checking Safe Links click verdicts.
- Responding to an incident: triggering or approving AIR remediation, running ZAP outcomes down, purging a delivered campaign across mailboxes.
- Running Attack Simulation Training and reading the compromise and repeat-offender metrics.
- Handling quarantine, the submissions portal, and user reported messages: releasing, reporting false positives and negatives to Microsoft, tuning the report-message experience.
- Automating read-only audit and reporting through the Microsoft Graph Security API, the Threat Submission API, or Exchange Online PowerShell.
- Running a read-only policy audit: preset-versus-custom drift, Configuration Analyzer gaps, Safe Attachments still in Monitor, Safe Links click-through allowed, impersonation protection missing on priority accounts, ZAP disabled, quarantine with no user visibility.

## When not to use

- **Endpoint EDR and device threat protection** (Microsoft Defender for Endpoint: onboarding, device hunting with the KQL `DeviceEvents` tables, attack surface reduction rules, live response): use `endpoint-detection-response`. MDO correlates with Defender for Endpoint inside a Defender XDR incident, but it does not own the device side.
- **External attack surface discovery** (Microsoft Defender External Attack Surface Management, internet-facing asset inventory): use `defender-easm`.
- **Zero-trust IDENTITY governance** (Entra ID, MFA rollout, conditional access, privileged access management, identity governance and administration): use `identity-access-management`. MDO consumes the identity, and a compromised mailbox is an identity problem first; it does not own the identity platform.
- **A third-party email gateway in front of the tenant** (Proofpoint, Mimecast, and similar): use `proofpoint-enterprise` or `proofpoint-essentials`. When a SEG fronts the tenant, that skill owns the gateway; this skill owns the MDO layer behind it and the enhanced-filtering connector that joins them.
- **Vendor-neutral sender-side deliverability** (SPF, DKIM, DMARC authoring, warmup, suppression, the sender's own reputation): use `smtp-deliverability`. MDO enforces inbound DMARC and reads composite authentication; it does not author your outbound DNS.
- **Storing the Graph app secret, certificate, or admin credential**: use `secrets-hygiene`. Never inline a live secret in a saved API call, a runbook, or a config file.

This skill **owns Microsoft Defender for Office 365 configuration and operations**. Route endpoint, external attack surface, identity, third-party gateway, and sender-side deliverability out per the list above; keep everything MDO here.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / pipeline | EOP-then-MDO filtering order, Safe Attachments detonation pipeline and Dynamic Delivery, Safe Links rewrite and click-time flow, impersonation and spoof-intelligence model, mailbox intelligence, ZAP mechanics, AIR playbooks, Plan 1 versus Plan 2 matrix | `references/architecture.md` |
| Operations / audit | Policy configuration (Safe Attachments, Safe Links, anti-phish, anti-spam, anti-malware, presets, Configuration Analyzer), Threat Explorer hunting, quarantine and submissions and user reported messages, Attack Simulation Training, the read-only audit lens with a threshold table and decision trees | `references/operations.md` |
| API / automation | Microsoft Graph Security API, Threat Submission API, Exchange Online PowerShell for policy audit, OAuth app-registration auth, endpoint tables, throttling, secret-store discipline | `references/api-and-automation.md` |

## Core model (condensed)

**EOP is the floor; MDO is the paid ceiling.** Every mailbox already has EOP (connection filtering, anti-malware, anti-spam, spoof intelligence, basic anti-phish). MDO Plan 1 adds Safe Attachments, Safe Links, and user/domain impersonation protection; Plan 2 adds Threat Explorer, AIR, Attack Simulation Training, and campaign views. Advising a Plan 2 workflow to a Plan 1 tenant is the most common category error, so pin the tier before recommending.

**The pipeline is ordered, and later stages depend on earlier ones.** Inbound mail flows connection filtering, then anti-malware, then anti-spam, then Safe Attachments, then Safe Links rewrite, then anti-phishing and mailbox intelligence, then delivery, then ZAP continuously after delivery. Anti-malware runs before anti-spam so malware is never filed in Junk. The order is why a message can be delivered clean and pulled minutes later by ZAP.

**Safe Attachments detonates; Dynamic Delivery hides the wait.** Unknown attachments are detonated in an isolated VM. In a static mode the whole message is held until the verdict; Dynamic Delivery sends the body immediately with a placeholder and swaps the real attachment in once it is cleared, which removes the user-visible delay. Monitor delivers and only tracks (no blocking); Block is the safe operating mode. Safe Attachments for SharePoint, OneDrive, and Teams is a separate toggle that covers stored files, not just mail.

**Safe Links protects at click time, not just delivery.** URLs are rewritten to the Safe Links proxy at delivery, and re-checked (reputation plus detonation for unknown URLs) when the user clicks, so a link weaponised after delivery is still caught. The load-bearing settings are: scan internal senders on (catches a compromised internal account), click-through disabled (users cannot bypass the block page), and a lean do-not-rewrite list (every entry is a permanent blind spot).

**Impersonation and spoofing are two different controls.** Spoof intelligence and composite authentication (compauth, Microsoft's meta-verdict over SPF/DKIM/DMARC plus reputation) handle forged senders. Impersonation protection is a separate anti-phish setting: named protected users (up to 60 per policy, put your executives and finance approvers here) and protected domains, plus mailbox intelligence, the contact-graph model that scores mail against each user's normal correspondents. A tenant with impersonation protection left empty is unprotected against display-name and lookalike-domain CEO fraud even with spoof intelligence on.

**Presets beat custom policies, and the Configuration Analyzer finds the gaps.** The Standard and Strict preset security policies apply Microsoft's maintained recommended settings and always evaluate above custom policies. Strict for high-value users (executives, IT admins, finance), Standard for the general population is the usual split. The Configuration Analyzer compares live custom policy against the Standard and Strict baselines and lists every setting that is weaker; it is the first stop on any audit.

**Least privilege and full coverage are the through-line.** Safe Attachments stuck in Monitor, Safe Links click-through allowed, a long do-not-rewrite or Tenant Allow list nobody reviews, impersonation protection empty for priority accounts, ZAP disabled, quarantine with no end-user digest so users never see false positives: these are the recurring findings. Block what you detonate, close the click-through, prune the allow lists, name your VIPs, keep ZAP on, and give users a way to see quarantine.

## Reference router

| Need | Load |
|---|---|
| The EOP-then-MDO filtering pipeline and stage order, the Safe Attachments detonation pipeline and Dynamic Delivery, the Safe Links rewrite and click-time flow, the impersonation and spoof-intelligence and mailbox-intelligence model, ZAP mechanics and limits, AIR playbooks and evidence types, and the Plan 1 versus Plan 2 capability matrix | `references/architecture.md` |
| Policy configuration (Safe Attachments, Safe Links, anti-phish, anti-spam, anti-malware, the Standard and Strict presets, the Configuration Analyzer), Threat Explorer and Real-time detections hunting, quarantine and quarantine policies and submissions and user reported messages, Attack Simulation Training, and the read-only audit lens with a threshold table and remediation decision trees | `references/operations.md` |
| Microsoft Graph Security API (alerts, incidents), the Threat Submission API, Exchange Online PowerShell for policy audit, the OAuth app-registration flow with placeholder tokens, endpoint tables, throttling and backoff, pagination, and secret-store discipline | `references/api-and-automation.md` |

## Cross-references

- `proofpoint-enterprise`: the sibling third-party email-security skill from the same PR family; consult when a Proofpoint gateway fronts the tenant or when comparing or migrating between MDO and Proofpoint.
- `proofpoint-essentials`: the SMB and MSP Proofpoint gateway; same routing (that skill owns the gateway, this owns the MDO layer behind it).
- `endpoint-detection-response`: Microsoft Defender for Endpoint, the device EDR signal that MDO correlates with inside a Defender XDR incident.
- `identity-access-management`: the Entra ID, MFA, conditional access, and IGA substrate; a compromised mailbox is an identity incident first.
- `smtp-deliverability`: vendor-neutral SPF, DKIM, and DMARC authoring for your own outbound; MDO enforces inbound DMARC but does not write your DNS.
- `secrets-hygiene`: the Graph app secret, certificate, and admin credential live in the secret store, never inline in a saved API call or runbook.
- `siem-soar-investigation`: when MDO alerts stream to Microsoft Sentinel or another SIEM for correlation and long-term retention.

## Red flags

- Advising a Plan 2 workflow (Threat Explorer, AIR, Attack Simulation Training, campaign views) to a tenant that only has EOP or Plan 1.
- Safe Attachments left in Monitor rather than Block: malware is detonated and tracked but still delivered.
- Safe Links with click-through allowed, or internal-sender scanning off: users can bypass the block page, and a compromised internal account is unfiltered.
- A do-not-rewrite URL list or Tenant Allow list that has grown unreviewed: every entry is a permanent, unscanned path a breached vendor can ride.
- Impersonation protection empty for priority accounts: no named protected users or domains, so display-name and lookalike-domain executive fraud is unprotected even with spoof intelligence on.
- A third-party SEG in front of the tenant with no enhanced-filtering connector, so MDO filters on the SEG IP and every message looks internal (IP-based detection and spoof intelligence are blinded).
- ZAP disabled (phish, spam, or malware ZAP off): mail that turns malicious after delivery is never pulled.
- Custom policies expected to fire above a preset security policy: presets always win in evaluation order, so the custom rule silently never applies.
- Quarantine with no end-user digest or quarantine policy that hides messages from users: false positives are invisible and pile onto the helpdesk.
- Never running the Configuration Analyzer before declaring the baseline sound: it is the one-click gap report against Standard and Strict.
- Pasting a Graph app secret, certificate password, or admin credential into a saved API URL, a runbook, or a committed file instead of the secret store.
- Running an audit with write scope (releasing quarantine, submitting to Microsoft, activating a policy) during what was meant to be a read-only review.

## Bottom line

MDO layers a sandbox (Safe Attachments), a click-time URL check (Safe Links), an impersonation model (anti-phish plus mailbox intelligence), and an investigation surface (Threat Explorer, AIR) on top of the always-on EOP floor, with ZAP pulling mail that turns bad after delivery. Pin the licence tier before you advise, start from the Standard or Strict preset and run the Configuration Analyzer to close the gaps, keep Safe Attachments in Block and Safe Links click-through closed, name your priority accounts for impersonation protection, and give users a quarantine view so false positives surface. Route endpoint to `endpoint-detection-response`, external attack surface to `defender-easm`, identity to `identity-access-management`, a fronting gateway to `proofpoint-enterprise` or `proofpoint-essentials`, and keep every credential in the secret store.

## Reference files

- `references/architecture.md`: the EOP-then-MDO inbound filtering pipeline and why stage order matters, the Safe Attachments detonation pipeline with Dynamic Delivery and the SharePoint/OneDrive/Teams variant, the Safe Links delivery-rewrite and click-time processing flow, the anti-phishing impersonation and spoof-intelligence and mailbox-intelligence model with composite authentication, ZAP mechanics and its limits, the AIR playbooks and evidence and remediation types, and the EOP versus Plan 1 versus Plan 2 capability matrix.
- `references/operations.md`: policy configuration for Safe Attachments, Safe Links, anti-phishing, anti-spam, and anti-malware, the Standard and Strict preset security policies and the Configuration Analyzer, Threat Explorer and Real-time detections hunting with the Email entity page, quarantine and quarantine policies and the submissions portal and user reported messages, Attack Simulation Training, and the read-only policy-audit lens with a threshold table and remediation decision trees.
- `references/api-and-automation.md`: the Microsoft Graph Security API (alerts and incidents) and Threat Submission API, Exchange Online PowerShell for policy audit, the OAuth app-registration client-credentials flow with placeholder tokens only, the endpoint tables with key response fields, throttling and backoff, pagination, and the secret-store discipline for API credentials.
