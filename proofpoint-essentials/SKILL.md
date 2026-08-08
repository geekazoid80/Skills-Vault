---
name: proofpoint-essentials
description: "Use for any work involving Proofpoint Essentials (the SaaS email security gateway sitting in front of Microsoft 365 or Google Workspace tenants), either as a sender trying to deliver mail TO Proofpoint-protected recipients OR as an admin / MSP running Proofpoint Essentials for one or more customer organisations. Triggers include \"Proofpoint\", \"Proofpoint Essentials\", \"pphosted.com\", \"ppe-hosted.com\", \"Proofpoint blocked my email\", \"sa.local.dnsbl.proofpoint.com\", \"Proofpoint bounce\", \"Proofpoint quarantine\", \"End User Digest\", \"EUD\", \"Sender Lists\", \"Proofpoint whitelist\", \"Proofpoint blacklist\", \"Smart Send\", \"Email Continuity\", \"Proofpoint Sender Support\", \"delisted from Proofpoint\", \"Proofpoint URL Defense\", \"URL rewriting\", \"Proofpoint connection log\", \"Proofpoint message log\", \"Proofpoint policy\", \"Proofpoint encryption\", \"Proofpoint inbound\", \"Proofpoint outbound relay\", \"TLS required by Proofpoint\", \"Proofpoint TAP\", \"Proofpoint TRAP\", \"Proofpoint Archive\", \"Proofpoint DMARC\", \"Proofpoint MSP\", \"Proofpoint multi-tenant\". Sister to `smtp-deliverability` (which covers vendor-neutral sender-side discipline; this skill covers the Proofpoint specifics). Body covers: identification (MX lookup, bounce-text patterns), Proofpoint bounce code triage table, delisting flow (postmaster@pphosted.com, public Sender Support portal, the per-tenant whitelist that lives on the customer's admin not on Proofpoint's), TLS-required posture and how to verify outbound TLS readiness, the admin tenant model (organisation -> domain -> user -> alias hierarchy), the five quarantine types (spam / virus / phish / attachment / content) with release flow per type, End User Digest cadence and brand customisation, Sender Lists at organisation and per-user scope, inbound vs outbound filter policies, URL Defense rewrites and click-through investigation, Encryption add-on, DMARC / spoofing protection per-domain enforcement, Smart Send / Email Continuity for outbound during M365 outages, Archive (separate add-on with legal hold), six-step diagnostic flow when mail does not arrive, common operational tasks (release a quarantined message, whitelist a sender, investigate a missed phish, add a new domain, migrate off Proofpoint), MSP scope considerations. Self-authored from public Proofpoint Essentials documentation."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Proofpoint Essentials

Proofpoint Essentials is the SaaS email security gateway aimed at SMB and MSP customers. It sits in front of Microsoft 365 (most common) or Google Workspace, intercepts inbound mail, runs spam / phishing / malware / DLP / content checks, and delivers what survives to the actual mailbox. It can also relay outbound mail and (with the add-on) archive everything.

Proofpoint Essentials is a different product line from Proofpoint Enterprise / Targeted Attack Protection (TAP) / Threat Response Auto-Pull (TRAP) / Email Fraud Defense / Email Protection. The Essentials tenant model, admin UI, support portal, and policy surface are not the Enterprise ones. **Do not** carry assumptions across.

This skill is the companion to `smtp-deliverability`. That skill covers vendor-neutral sender-side discipline (SPF, DKIM, DMARC, warmup, suppression, abstraction interface). This skill covers what changes when Proofpoint is the destination filter or when you are the admin running Proofpoint Essentials for a customer.

> **Skill marker**: When applying this skill, begin your reply with `[skill: proofpoint-essentials]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Proofpoint Essentials tenant (mail-flow topology, MX posture, licence tier, on-prem versus cloud relay) before commanding the platform. Only ask the user for information not already covered or specific to this domain.

Before commanding the platform, understand:

1. **Topology and tenancy**
   - Which licence tier (Beginner, Business, Advanced, Professional)?
   - MX records pointed at Proofpoint (`*.pphosted.com` / `*.ppe-hosted.com`) or relayed through other infra first?
   - Single domain or multi-domain estate under the tenant?

2. **Mail flow direction and intent**
   - Inbound filtering, outbound relay, or both?
   - Office 365 / Exchange Online destination, Google Workspace, or on-prem Exchange / Postfix?
   - Connector / SmartHost configuration on the destination side?

3. **Change context**
   - Domain onboarding, policy tuning, false-positive triage, or DMARC alignment work?
   - Rollback path if a policy change blocks legitimate mail?

---

## Iron rules

1. **Do not paste customer data into Proofpoint Sender Support unredacted.** Subject lines, recipient addresses, headers (especially `Received:` chains and `X-`-prefixed Proofpoint diagnostic headers) are usually safe; message bodies, attachments, customer PII are not. Treat the public sender support portal as third-party.
2. **Outbound TLS is effectively required.** Many Proofpoint customers enforce opportunistic or required TLS on inbound. Senders without TLS get bounced or quarantined. Verify your sending infrastructure offers TLS 1.2 or 1.3 with a valid certificate.
3. **Whitelisting lives on the customer's tenant, not on Proofpoint's central system.** A sender being "added to Proofpoint" usually means the recipient organisation's admin added the sender to their organisation's Sender List. Public Sender Support can resolve IP-level reputation and global blocks, but per-tenant filtering decisions are not theirs to override.
4. **Always check the connection log AND the message log before claiming "the mail never arrived".** Proofpoint shows different evidence in each: connection log = SMTP-conversation-level (pre-acceptance); message log = post-acceptance journey (filtering, quarantine, delivery). A message rejected at SMTP time will appear only in connection log.
5. **Quarantine release is not the same as whitelisting.** Releasing a single message gets that message through; the next message from the same sender will hit quarantine again unless the sender is added to a Sender List.

## What Proofpoint Essentials actually is

Tenant model:

```
Proofpoint Essentials Cloud
  Reseller / Partner (MSP)
    Organisation (the customer; one tenant per customer)
      Domain (one or more; each with MX pointing to Proofpoint)
        User (each mailbox)
          Alias (additional addresses for the user)
```

For an end-customer admin, "the organisation" is what you administer. For an MSP, you sit at the partner level and administer multiple organisations. The UI surface is similar; the partner level adds tenant-switching, branding controls, and consolidated billing.

Mail flow (default):

```
Internet
  -> Proofpoint Essentials inbound MX (pphosted.com / ppe-hosted.com)
    -> Proofpoint filter pipeline (connection / sender / content / URL / attachment / DLP)
      -> Quarantine OR
      -> Delivery to backend mailbox provider (M365 / Workspace / on-prem) OR
      -> Reject (bounce)

Mailbox -> Outbound smarthost (optional; if outbound relay is enabled)
        -> Proofpoint outbound filter (DLP / encryption / signature)
          -> Delivery to internet
```

## Identifying when Proofpoint is the destination filter

When sending to a recipient and uncertain whether Proofpoint is in the path:

```bash
dig +short MX example.com
# Look for *.pphosted.com or *.ppe-hosted.com
# e.g. mx0a-001b2c01.pphosted.com.
```

Bounce-text patterns that confirm Proofpoint:

- `sa.local.dnsbl.proofpoint.com`
- `policy.local.dnsbl.proofpoint.com`
- `Sender's IP is blocked by Proofpoint`
- `pphosted.com` or `ppe-hosted.com` in the bouncing MTA hostname
- `Proofpoint Essentials` literal in the diagnostic-code text

If the MX is M365 or Workspace direct (`*.mail.protection.outlook.com`, `aspmx.l.google.com`), Proofpoint is not the filter.

## Proofpoint bounce code triage

Bounces from Proofpoint follow the SMTP enhanced status code convention with Proofpoint-specific text. The most common ones:

| Code | Likely cause | Action |
|---|---|---|
| `550 5.7.1 ... blocked using sa.local.dnsbl.proofpoint.com` | Sending IP on Proofpoint's spam reputation list | Sender Support portal or `postmaster@pphosted.com` for delisting; investigate underlying reputation issue (likely a sender-side compromise or warmup gap) |
| `550 5.7.1 ... blocked using policy.local.dnsbl.proofpoint.com` | Sending IP on Proofpoint's policy block list (often broader, country-based, or persistent abuse) | Sender Support; a policy block usually requires evidence of remediation, not just a request |
| `550 5.7.1 Sender domain is in DMARC reject and message failed alignment` | Recipient's tenant has Proofpoint DMARC enforcement on; your message did not pass DMARC alignment | Fix DMARC alignment at source (see `smtp-deliverability`); the recipient's admin can also add a per-domain exception, but the right fix is sender-side |
| `554 5.7.1 ... rejected by user / organisation rule` | Recipient organisation has a Sender List or content rule blocking this sender | Recipient's admin must whitelist; Proofpoint Sender Support cannot override per-tenant rules |
| `421 4.7.1 ... rate limited` | Sending too fast to one Proofpoint customer; throttling | Slow down; respect the temporary defer; check for warmup curve mismatch |
| `550 5.7.1 ... TLS required` | Recipient tenant enforces inbound TLS; your connection did not negotiate TLS | Enable TLS on the sending MTA; verify cert is valid |
| `554 5.7.1 ... message blocked by Proofpoint URL Defense` | A URL in the message hit URL Defense's block list | Check the URL against URL Defense (or the recipient's admin can release); if a legitimate URL was wrong-classified, request reclassification via the Proofpoint URL submission form |
| `552 5.3.4 ... message size exceeds limit` | Hit the recipient organisation's max message size (often 25 MB; configurable) | Resend smaller, or use a file-share link |
| `554 5.7.1 ... message blocked by content policy` | Recipient tenant has a content policy match (DLP, keyword, regex) | Investigate; the body or an attachment matched a policy. Often a false positive on legitimate content |

For any 5xx with Proofpoint diagnostic text, the headers of the bounce contain the Proofpoint message-trace ID. Proofpoint Sender Support and the recipient's admin can both look that ID up; share it when escalating.

## Delisting flow (when your sending IP is blocked at Proofpoint)

1. **Confirm it is actually a Proofpoint block, not the recipient's M365 / Workspace.** Re-read the bounce; check the diagnostic hostname.
2. **Find the root cause first.** If your IP is blocked, something earned it: a compromised mailbox, a shared-IP neighbour problem, a missing PTR record, a stale SPF, a forwarder loop. Delisting without root-cause fixing earns the same block back.
3. **Submit via the Proofpoint Sender Support portal.** Public form at https://support.proofpoint.com (look for "report a false positive" / "remove block" / "Sender Support"). Provide:
   - The blocked IP or domain.
   - A representative bounce (full headers and Proofpoint diagnostic).
   - Evidence of remediation (compromised account secured, MTA fixed, etc.).
   - A point-of-contact email at your organisation.
4. **Email path:** `postmaster@pphosted.com` is the documented contact for IP delisting. Set expectation in days, not hours.
5. **For per-tenant whitelisting:** Proofpoint cannot do this. The recipient organisation's admin must add the sender to their organisation's Sender List. Reach out to the recipient directly.

## TLS-required posture

To verify your sending MTA presents TLS to Proofpoint correctly:

```bash
# from the sending MTA
openssl s_client -starttls smtp -connect mx0a-001b2c01.pphosted.com:25 -servername mx0a-001b2c01.pphosted.com 2>&1 | head -30
# look for: TLS 1.2 or 1.3, valid certificate chain, no name mismatch
```

```bash
# external check (sender-side)
dig +short MX yourcustomer.com
swaks --to test@yourcustomer.com --from check@yourdomain.com --tls --tls-protocol tls1_2
# swaks will report TLS handshake details; the recipient should accept TLS
```

If your MTA does not offer TLS, fix it before anything else; modern Proofpoint customers reject plaintext connections from external senders.

## The admin side: tenant structure

When you administer Proofpoint Essentials for a customer (or as an MSP for many), the daily surface:

| Surface | What it controls |
|---|---|
| Organisation Settings | Branding, EUD cadence, default policies, support contact, multi-domain configuration |
| Domains | Each domain owned by the organisation; MX validation; outbound relay enable per domain |
| Users | One per mailbox; auto-provisioned from M365 / Workspace via directory sync, or manual |
| Aliases | Additional addresses for an existing user (`sales@`, `info@`); inherits the user's quarantine and EUD |
| Filter Policies | Inbound and outbound rule sets; default + per-domain or per-group overrides |
| Spam Sensitivity | Slider per organisation (default Medium); higher = more aggressive quarantine |
| Sender Lists | Allow + Block at organisation scope and per-user scope; supports domain, address, IP |
| Content Filters | DLP-style rules (keyword, regex, attachment type, metadata); usually inbound + outbound |
| URL Defense | URL rewriting on inbound mail; click-through inspection at click time |
| Connection Filter | Reputation, helo enforcement, RBL choices |
| Encryption | Outbound encryption (add-on); recipient receives a portal-link or pull notification |
| DMARC | Per-domain DMARC enforcement (reject / quarantine / monitor); outbound DKIM signing |
| Archive | Separate add-on; long-term retention; legal hold; e-discovery search |
| Connection Log | Last 30 days; SMTP-conversation-level evidence (accepted, rejected, deferred); pre-quarantine view |
| Message Log | Last 30 days; post-acceptance evidence (filter verdict, quarantine type, delivery, click events) |

For an MSP, the partner-level surface adds:

- Multi-organisation switcher.
- Bulk reporting across organisations.
- Branding inheritance (per-organisation EUD branding can override partner defaults).
- Consolidated billing.

## Quarantine: the five types and release flow

Quarantine is not one bucket. Proofpoint sorts inbound rejects into categories:

| Type | What lands here | Release flow |
|---|---|---|
| Spam | Standard unsolicited mail; the most common quarantine | EUD release; admin release; or whitelist sender to prevent future quarantine |
| Virus | Anti-virus signature match | Admin-only release (policy-controlled); investigate before releasing |
| Phish | Phishing-pattern match (URL Defense, Lookalike Domain, Display Name spoof) | Admin-only release; treat as a real phish until proven otherwise |
| Attachment | Attachment type or extension blocked by policy (`.exe`, `.scr`, `.iso`, etc.) | Admin release; consider the policy is correct |
| Content | DLP / keyword / regex match | Admin release; investigate whether the rule needs tuning |

End User Digest gives users self-service release for spam (and optionally phish, configurable). Virus / attachment / content go to admin queue by default.

When releasing, two outcomes possible:

- **Release this message only.** The next message from the same sender will hit quarantine again.
- **Release and add sender to Sender List.** Future messages bypass spam filtering. Only do this for genuinely-trusted senders; an indiscriminately-whitelisted sender is a phish vector.

## End User Digest (EUD)

The daily (or per-tenant cadence; configurable) email each user receives summarising their quarantined mail with one-click release / report buttons.

| Setting | Default | Notes |
|---|---|---|
| Cadence | Daily morning | Can be per-organisation or per-user; weekly is also offered (less useful) |
| Time of day | Per organisation timezone | Set to local working hours start |
| Includes | Spam by default | Phish optional; rarely include virus / attachment / content (admin-only by policy) |
| Brand | Default Proofpoint branding | Customisable per organisation; for MSPs, often set per customer brand |
| User actions | Release, Release and allow sender, Report not spam, Block sender | Each maps to an admin-side audit entry |

Common tuning: turn down digest to `weekly` for users who get very little spam (less noise); turn up `release and allow sender` adoption with a short user-training note (one well-released sender saves the admin from a future ticket).

## Sender Lists discipline

Two scopes:

- **Organisation Sender List:** applies to all users in the organisation. Used for trusted vendors, internal partner organisations, monitoring services.
- **Per-User Sender List:** applies to one user. Useful when a user has unique trusted senders (an executive's lawyer, a personal contact).

Both support address-level (`bob@vendor.com`), domain-level (`vendor.com`), and IP / CIDR (`198.51.100.0/24`).

**Block lists** are not a substitute for spam filtering. Adding a sender to the block list says "drop this; do not even quarantine". Use sparingly; an entry that should have been a spam-filter tune ends up as a permanent block-list entry that nobody reviews.

Periodic Sender List audit (quarterly): export, review, remove anything no longer needed. A neglected Allow list becomes the phish vector when the trusted vendor is breached.

## URL Defense

URL Defense rewrites every URL in inbound mail to a Proofpoint click-through URL. When the user clicks, Proofpoint inspects the destination at click time (not just at delivery time) and either passes through, blocks, or warns.

Trade-offs:

- Pros: catches URLs that were benign at delivery and weaponised later; gives admins per-click telemetry (the Click Log).
- Cons: breaks any URL-preview that depends on the original URL (some integrations); non-trivial UX impact when URL Defense incorrectly blocks; complicates link-tracking analytics in marketing emails.

Common operations:

- **Investigating a URL Defense block.** Check the Click Log; see the original URL and the verdict reasoning. If a false positive, submit via the Proofpoint URL submission form (or the in-product "Report False Positive" button on the warning page).
- **Whitelisting a domain in URL Defense.** Per-organisation; useful for internal tools whose links should not be rewritten.
- **Disabling URL Defense for a sender.** If a vendor's mail is unusable due to rewriting, scope a per-sender exception; do not disable URL Defense globally.

## DMARC and spoofing protection

Proofpoint Essentials provides per-domain DMARC enforcement on inbound mail (separate from your own outbound DMARC stance, which is governed by your DNS records and lives in `smtp-deliverability`).

When the recipient organisation's admin enables DMARC enforcement for `example.com`:

- Inbound mail with `From: someone@example.com` is checked against the published DMARC policy.
- If the policy is `reject` and the message fails, Proofpoint bounces it before delivery.
- The bounce code includes "DMARC reject" in the diagnostic text.

This protects the organisation against spoofing of their own domain. A separate setting protects against display-name spoofing (`From: "Bob Smith" <bob.smith.fake@gmail.com>` when Bob Smith is a known executive of `example.com`); this uses Proofpoint's Lookalike Domain detection.

For senders working with Proofpoint customers: get your DMARC right (per `smtp-deliverability`'s four-phase rollout), then your mail flows; otherwise it dies at Proofpoint's DMARC enforcement.

## Smart Send / Email Continuity

Add-on feature: when the customer's M365 (or Workspace) is unreachable, Proofpoint queues inbound mail and exposes a webmail interface so users can still read and reply during the outage. The replies go out via Proofpoint's outbound relay; when M365 returns, the queue drains.

Useful for organisations whose M365 outages would be visible to customers. Set up before the outage; not after. Test annually.

## Archive (separate add-on)

Long-term retention of inbound + outbound mail (often 7-10 years for compliance-driven customers). Includes:

- E-discovery search across the archived corpus.
- Legal hold (preserve specific mail beyond standard retention).
- User self-service search (limited; admin can extend).

Not enabled by default. Charged per user. If the customer requirement is regulatory archiving (financial services, healthcare, legal), Archive is usually the right tool; if it is just "we want to find old mail", M365 / Workspace native search is sometimes enough.

## Six-step diagnostic flow when mail does not arrive

When a sender or recipient says "the mail never arrived":

1. **Identify the destination filter.** `dig MX` on the recipient domain. If `*.pphosted.com` / `*.ppe-hosted.com`, Proofpoint is in the path. If not, this skill does not apply; route to `smtp-deliverability`.
2. **Check the Connection Log.** As the Proofpoint admin (or via the recipient's admin), search the connection log for the sender IP and timestamp window. If the message was rejected at SMTP time, this is where the evidence lives.
3. **Check the Message Log.** If the message was accepted, search the message log for sender, subject, or recipient. Verdict (delivered / quarantined / blocked) appears here, with the filter reason.
4. **Check the recipient's quarantine.** EUD might have it; admin queue might have it. Different release flow per quarantine type.
5. **Verify TLS.** If the sender claims to send TLS, `openssl s_client -starttls smtp` from outside to confirm the recipient's MX accepts TLS and presents a valid cert.
6. **Engage support if needed.** Escalate to Proofpoint Sender Support (sender-side issue) or to the recipient's admin (per-tenant policy issue). Always include the message-trace ID from the bounce or the Proofpoint message log.

## Common operational tasks

| Task | Path |
|---|---|
| Release a quarantined message | Admin UI -> Logs -> Quarantine -> select message -> Release (or Release + Allow sender) |
| Whitelist a sender | Admin UI -> Company Settings or User -> Sender Lists -> Allow -> add address / domain / IP |
| Investigate a missed phish | Message Log -> search for the phish; if delivered, check why filter let it through; tune Spam Sensitivity or add content rule; report to Proofpoint as a false negative via the Threat Reporter |
| Add a new domain | Domains -> Add -> validate ownership via TXT record -> point MX to Proofpoint -> validate inbound flow -> enable outbound relay if needed |
| Migrate off Proofpoint | Plan: parallel-MX during cutover; new filter receives copy via routing; verify; flip primary MX; keep Proofpoint as MX2 for 30 days as fallback; archive existing Proofpoint Archive if used (separate export) |
| Onboard a customer (MSP) | Partner UI -> Add Organisation -> create primary domain -> configure auth (M365 directory sync / SAML / local) -> set EUD cadence and brand -> seed Sender Lists from existing customer-known-good senders -> validate one test mail |
| Quarterly sender-list audit | Export Sender Lists per organisation -> review each entry against current vendors -> remove stale entries -> document review |

## Verification before claiming done

Per `completion-gate`, "set up Proofpoint" is not a finish line. Before the chunk closes:

- [ ] MX records for every protected domain point to Proofpoint Essentials hosts; verified via `dig MX` from outside the network.
- [ ] Outbound TLS verified end-to-end with `openssl s_client` or `swaks`; cert is valid; protocol is 1.2 or 1.3.
- [ ] EUD test received by at least one user account; release / report / allow buttons work end-to-end.
- [ ] Quarantine release tested for each of the five types (spam, virus simulated via EICAR, phish, attachment, content).
- [ ] Sender List audit baseline captured (export); review cadence calendared.
- [ ] DMARC posture per protected domain: documented; enforcement matches the customer's risk tolerance.
- [ ] Connection Log and Message Log accessible; sample search returns expected results.
- [ ] If migrating away: parallel-MX validated; cutover plan documented; rollback path tested.

## Cross-references

- `smtp-deliverability`: vendor-neutral sender-side discipline. Both fire when the conversation is "mail is not arriving"; this skill adds the Proofpoint specifics; that one provides the sender-side baseline.
- `humanise-comms`: when communicating with a customer about a quarantine release, a delisting request, or a phish investigation, the language matters as much as the technical fix.
- `secrets-hygiene`: Proofpoint admin credentials, API tokens (for directory sync and reporting integrations), and any customer-data exports live in the secret store. Never paste raw quarantine contents into chat tools.
- `oncall-runbooks`: a Proofpoint-specific runbook (filter outage, blocked-sender storm, quarantine flood) reads from this skill.
- `systematic-debugging`: when "Proofpoint blocked it" is the user's claim, run the four-phase loop; the connection log and the message log are the boundary evidence.
- `plan-time-tooling`: any chunk that changes Proofpoint policies in production (sensitivity, content rules, URL Defense, DMARC enforcement, MX cutover, organisation-level Sender List) is an `engineering:deploy-checklist` trigger.
- `completion-gate`: the verification checklist above is the layer-3 gate.
- `consumer-rollout`: when onboarding a new customer or domain, drop a "Required hooks" section into the customer's run-book covering EUD recipients, admin contacts, and emergency-release authority.

## Red flags

- About to delist an IP from Proofpoint without identifying the root cause that earned the block.
- About to add a sender to an organisation's Allow list without verifying the request came from a legitimate admin (social-engineering vector).
- About to release a virus / phish / attachment quarantine without investigating; "the user really wants it" is not sufficient justification.
- About to disable URL Defense globally to fix a single-vendor compatibility problem.
- About to flip MX to Proofpoint without a parallel-MX validation period and a documented rollback.
- About to enable Proofpoint DMARC enforcement at `reject` from `none` without going through the four-phase rollout in `smtp-deliverability` first; legitimate mail will die.
- About to commit a Proofpoint API token, M365 directory-sync service-account password, or customer organisation export into a tracked file.
- About to paste raw quarantine message bodies into Proofpoint Sender Support, ticketing, or chat tools.
- About to rely on EUD for users who do not actually read it (review release rates; if near zero, the digest is not the right control).
- About to skip the message-trace ID when escalating to Sender Support or the recipient's admin.
- About to use the public `postmaster@pphosted.com` for a per-tenant filtering issue (Proofpoint cannot fix; the recipient's admin must).
- About to migrate off Proofpoint without exporting the Archive (if Archive add-on was active); historical mail will be lost.
- About to assume Proofpoint Enterprise documentation applies to Essentials; the products diverge.

## Bottom line

Proofpoint Essentials is a SaaS gateway in front of M365 or Workspace. As a sender, mail to Proofpoint-protected recipients needs SPF / DKIM / DMARC right (per `smtp-deliverability`) plus TLS available; bounces refer to Proofpoint diagnostic text; delisting is via Sender Support, but per-tenant whitelisting is the recipient admin's call. As an admin or MSP, the daily surface is the message log, the connection log, the five-type quarantine, the EUD, the Sender Lists, and the policy rule sets; quarantine release and whitelisting are different actions; URL Defense and DMARC enforcement are powerful but easy to misconfigure. Verify every change with the connection-log + message-log evidence before claiming done.

## External resources

- Proofpoint Essentials documentation: https://help.proofpoint.com/Proofpoint_Essentials
- Proofpoint Sender Support: https://support.proofpoint.com (look for the Sender Support workflow)
- IP delisting contact: `postmaster@pphosted.com`
- URL submission (false positive / false negative): https://tools.proofpoint.com/urlsubmission
- Proofpoint Threat Reporter (Outlook add-in for users to report phish): documented in the admin UI; deploy via M365 Centralised Deployment.
