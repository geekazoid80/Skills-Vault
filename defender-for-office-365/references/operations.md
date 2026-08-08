# Microsoft Defender for Office 365 operations and audit

This is the operational depth: how to configure the policies, how to hunt in Threat Explorer, how to run quarantine and submissions, how Attack Simulation Training works, and the read-only audit lens with thresholds and decision trees. The management surface is the Microsoft Defender portal (`security.microsoft.com`) under Email and collaboration, plus Exchange Online PowerShell for scripted review.

## Policy configuration

### Preset security policies first

The Standard and Strict preset security policies apply Microsoft's maintained recommended settings across anti-spam, anti-malware, anti-phishing, Safe Attachments, and Safe Links in one place, and they always evaluate above custom policies. Reach for them before hand-building custom policies.

- **Strict** for high-value users: executives, IT admins, finance approvers, and anyone in the impersonation and priority-account lists.
- **Standard** for the general population.
- Presets are defined by recipient conditions (users, groups, domains). A user can match both; Strict wins where they overlap.

Rollback is easy: disabling the preset returns the tenant to its prior state, which is why presets are the low-risk way to raise a baseline.

Indicative preset differences (confirm against the current Configuration Analyzer, Microsoft tunes these):

| Setting | Standard | Strict |
|---|---|---|
| Bulk complaint level (BCL) threshold | 6 | 5 |
| Spam action | Move to Junk | Quarantine |
| High-confidence spam | Quarantine | Quarantine |
| Phishing action | Quarantine | Quarantine |
| Anti-phishing threshold | More Aggressive | Most Aggressive |
| Safe Attachments | Block | Block |

### The Configuration Analyzer

The Configuration Analyzer (Defender portal, Email and collaboration, Policies and rules, Threat policies, Configuration analyzer) compares every live policy against the Standard and Strict baselines and lists each setting weaker than the baseline, with a one-click path to align it. Run it first on any audit and after any custom-policy change. It is the fastest way to find the gap between what the tenant thinks it enforces and what it actually enforces.

### Safe Attachments policy

Set the action to Block (or Dynamic Delivery for the latency win, which behaves as Block on a malicious verdict). Enable the SharePoint, OneDrive, and Teams protection separately if collaboration coverage is wanted. Monitor is a short baselining posture only, because it delivers malware.

### Safe Links policy

Enable URL scanning for email, Teams, and Office apps. Turn on scanning for internal senders. Disable click-through so users cannot proceed past the block page. Keep tracking on for investigation telemetry. Keep the do-not-rewrite list lean, each entry is a permanent unscanned path.

### Anti-phishing policy

Enable spoof intelligence. Populate impersonation protection: named protected users (executives and finance, up to 60 per policy), protected domains (your own plus key partners), and mailbox intelligence with its protection action. Set the advanced phishing threshold (Aggressive for general, higher for VIPs). Turn on the safety tips (unauthenticated-sender indicator, first-contact, "via").

### Anti-spam and anti-malware policy

Anti-spam: set the bulk threshold (lower is stricter), the high-confidence-spam and phish actions (quarantine for the stricter posture), and enable spam, phish, and bulk ZAP. Anti-malware: enable the common attachments filter, keep malware ZAP on, and quarantine rather than delete so investigation is possible. Configure the outbound spam policy with an admin alert when a user is blocked for sending spam, which is a strong account-compromise signal.

### Policy priority

Custom policies of the same type evaluate in priority order, lowest number first, first match wins, so put user-specific policies above the organisational default. Preset security policies sit above all custom policies regardless. This ordering is the usual reason a custom policy "never fires".

## Threat Explorer and Real-time detections

Threat Explorer (Plan 2) and Real-time detections (the Plan 1 read-only subset) are the hunting surface over recent mail. Defender portal, Email and collaboration, Explorer (or Real-time detections).

### Views and retention

Views: All email, Malware, Phish, and Campaigns (Plan 2). Retention is roughly 30 days for Threat Explorer and 7 days for Real-time detections; message trace holds summary data around 90 days with full detail for a shorter window; Advanced Hunting holds 30 days of KQL-queryable data.

### Filtering

Filter on sender IP, sender and recipient address and domain, subject, URL domain, file name and hash, detection technology (Safe Attachments, Safe Links, impersonation, spoof, campaign, AIR), delivery action (Delivered, Blocked, Replaced, Quarantine), and delivery location (Inbox, Junk, Quarantine, Deleted, External).

### The investigation workflow

1. Filter to isolate the suspect messages (for a campaign: same subject or attachment hash or sender across many recipients).
2. Open the details panel for headers, authentication, URLs, and attachments.
3. Click through to the Email entity page for the full picture: authentication results (SPF/DKIM/DMARC/compauth), per-URL verdicts and clicks, attachment detonation results, the delivery timeline (original location, ZAP action, current location), and related alerts and incidents.
4. Take action: move to inbox, junk, or deleted; quarantine; or trigger AIR (Plan 2).

Filtering on delivery action Replaced or current location Quarantine with original location Inbox surfaces what ZAP pulled.

## Quarantine, quarantine policies, submissions, and user reported messages

### Quarantine and quarantine policies

Quarantine holds spam, phish, malware, and policy-matched mail. A quarantine policy controls what end users can do with their own quarantined mail (view, release, request release, report) and whether they receive a quarantine notification (the digest). Give users at least a notification and a request-release path for spam and bulk, so false positives surface without a helpdesk ticket; keep malware and high-confidence phish admin-only. Quarantine with no user visibility means every false positive is invisible until someone complains.

### Submissions

The submissions portal (Defender portal, Actions and submissions, Submissions, or `submissions.microsoft.com`) reports false positives and false negatives to Microsoft, which improves detection tenant-wide and globally. Submit the missed phish and the wrongly-quarantined legitimate mail rather than only releasing it, so the verdict is corrected at the source.

### User reported messages

When users report with the built-in Report button or the Microsoft Report Message and Report Phishing add-ins, reports land in the user-reported view and can auto-trigger AIR. Configure the user-reported settings: where reports go (to Microsoft, to a reporting mailbox, or both), and the post-report message the user sees. A well-run report flow is a primary AIR trigger, so it is worth wiring properly.

### Tenant Allow/Block List (TABL)

TABL is for temporary, scoped overrides during investigations: block or allow a domain, sender, URL, or file hash. Allow entries should be rare and expire; every standing allow is an unscanned path. Review and prune regularly. TABL is not a substitute for fixing a policy.

## Attack Simulation Training (Plan 2)

Runs benign simulated phishing to measure susceptibility and assign training. Defender portal, Email and collaboration, Attack simulation training.

- **Techniques**: credential harvest, malware attachment (simulated), link in attachment, drive-by URL, OAuth consent grant.
- **Flow**: pick a technique, pick or build a payload, target users (all, a department, previous clickers), schedule, and auto-assign training to those who fall for it.
- **Metrics**: compromise rate (clicked or submitted), repeat offenders, training completion, and trend over time.

Use it to prioritise training and to justify a Strict preset for the highest-risk groups; the repeat-offender list is a good candidate for tighter policy.

## Read-only audit lens

An MDO audit is read-only: read policy through Exchange Online PowerShell and the Graph, read Threat Explorer, and never release quarantine, submit to Microsoft, or activate a policy. Start with the Configuration Analyzer, then walk the thresholds below.

### Audit threshold table

| Control | Healthy | Finding | Why it matters |
|---|---|---|---|
| Configuration Analyzer | No settings below Standard for general, below Strict for VIPs | Any setting weaker than the target preset | The one-click gap report; drift here is the headline |
| Safe Attachments action | Block or Dynamic Delivery | Monitor or Off | Monitor and Off deliver malware |
| Safe Attachments for SPO/ODB/Teams | On where collaboration is used | Off | Stored malicious files are undetonated |
| Safe Links click-through | Disabled | Allowed | Users can bypass the block page |
| Safe Links internal senders | On | Off | A compromised internal mailbox is unfiltered |
| Do-not-rewrite / Tenant Allow list | Short, reviewed, dated | Long, unreviewed | Every entry is a permanent unscanned path |
| Impersonation protection (users) | Priority accounts named | Empty | Display-name executive fraud unprotected |
| Impersonation protection (domains) | Own plus key partners named | Empty | Lookalike-domain fraud unprotected |
| Spoof intelligence | On | Off | Forged senders unscored |
| Phish / spam / malware ZAP | All on | Any off | Post-delivery malicious mail never pulled |
| Preset vs custom | Preset carries the baseline | Custom expected to override a preset | Presets always win; the custom rule never fires |
| Quarantine policy | Users get a notification and request-release for spam | No user visibility | False positives invisible, helpdesk load |
| Enhanced filtering (SEG in front) | Connector configured | Absent | MDO filters the SEG IP, spoof and IP detection blinded |

### Remediation decision trees

**Safe Attachments finding**

```
Action == Off?
  yes -> highest priority: enable, set to Block or Dynamic Delivery
Action == Monitor?
  is this a deliberate, time-boxed baselining window?
    yes -> confirm the end date, note it, re-audit at end
    no  -> move to Block or Dynamic Delivery (Monitor delivers malware)
Action == Block/Dynamic Delivery?
  SPO/ODB/Teams protection on where collaboration is used?
    no -> recommend enabling for stored-file coverage
```

**Impersonation protection finding**

```
Any protected users named?
  no -> add executives, finance approvers, and other high-value targets
Any protected domains named?
  no -> add your own domains plus key partner domains
Mailbox intelligence on with a protection action?
  no -> enable; it is the contact-graph model that catches first-contact fraud
Priority accounts in a Strict preset?
  no -> move VIPs to Strict for the higher threshold
```

**Post-delivery coverage finding**

```
Phish / spam / malware ZAP all on?
  any off -> enable the missing switch
Delivered-then-malicious mail visible in Threat Explorer?
  yes -> confirm ZAP acted (delivery action Replaced / location Quarantine)
       -> if not pulled, check the 7-day window and whether the user moved it
Quarantine visible to users?
  no -> add a quarantine policy with notification and request-release for spam/bulk
```

**Preset-versus-custom finding**

```
Custom policy expected to enforce something a preset does not?
  remember presets evaluate above all custom policies
  -> if the setting matters, raise the preset (or move the users out of the preset scope)
  -> do not expect the custom policy to override the preset; it will not fire
Run the Configuration Analyzer to confirm the effective settings
```

## Verification before claiming done

Per `completion-gate`, "configured MDO" is not a finish line. Before the chunk closes:

- [ ] Configuration Analyzer shows no settings below the target preset (Standard for general, Strict for VIPs).
- [ ] Safe Attachments in Block or Dynamic Delivery; SPO/ODB/Teams protection on where collaboration is used.
- [ ] Safe Links click-through disabled, internal-sender scanning on, do-not-rewrite list reviewed.
- [ ] Impersonation protection populated with priority users and domains; mailbox intelligence on with an action.
- [ ] Phish, spam, and malware ZAP all on.
- [ ] Quarantine policy gives users a notification and request-release for spam and bulk.
- [ ] User-reported messages wired to a destination and (Plan 2) triggering AIR.
- [ ] If a SEG fronts the tenant: enhanced filtering connector configured and inbound acceptance restricted to the SEG IPs.
- [ ] Tenant Allow/Block List reviewed; standing allow entries justified and dated.
