# Proofpoint Enterprise operations and the audit lens

The operational configuration depth for SEG policy, quarantine and the End User Digest, TAP, URL Defense and isolation, TRAP, EFD / DMARC enforcement, DLP and encryption, followed by the read-only policy-audit lens with a threshold table and remediation decision trees. Platform mechanics are in `architecture.md`; the API surface is in `api-and-automation.md`. Every audit step below is read-only: never release a message, pull a message with TRAP, or activate a policy change during a review.

## SEG policy: routes, rules, quarantine

### Policy routes and filter rules

Build the route first (which traffic this policy governs: sender domain, recipient domain, IP), then the rules inside it. Rules evaluate in priority order, first match subject to the action precedence (block > quarantine > discard > encrypt > deliver). Keep specific rules above broad ones; a broad allow placed above a specific block silently wins and the block never fires.

Common tuning tasks:

- **Spam threshold**: the 0-to-100 spam score with a configurable quarantine cut. Raise it to quarantine more aggressively, lower it to reduce false positives; change it in small steps and confirm the effect in Smart Search before and after.
- **Disposition per folder**: route spam to the Spam folder, impostor / display-name spoof to Impostor, phishing to Phish, and so on, so the End User Digest and admin queues stay meaningful.
- **Custom quarantine folders**: create per-policy folders when a business unit needs a distinct review queue.

### Quarantine folders

The default folders are Spam, Bulk, Adult, Virus, Impostor, and Phish. Release flow depends on the folder:

| Folder | What lands here | Release |
|---|---|---|
| Spam | Standard unsolicited mail | End User Digest self-service or admin release |
| Bulk | Grey mail, marketing | Digest or admin release |
| Adult | Adult-content match | Admin release |
| Virus | AV signature match | Admin-only; investigate before release |
| Impostor | Display-name spoof, BEC pattern | Admin-only; treat as real until proven otherwise |
| Phish | Phishing pattern (URL Defense, lookalike) | Admin-only; treat as real phish until proven otherwise |

Releasing a single message is not the same as allowing the sender; the next message from the same sender hits quarantine again unless a policy or safe-sender entry changes. Never release a Virus, Impostor, or Phish message on "the user really wants it" alone.

### End User Digest

The scheduled email each user receives summarising their quarantined mail with one-click release / report actions. Cadence, time-of-day, and which folders are self-service (Spam by default; Phish and Virus stay admin-only by policy) are configurable per policy group. Review release rates: a digest with near-zero engagement is not an effective control and the messages should route to an admin queue instead.

## TAP operations

### Attachment defense and allow-on-timeout

Set the sandbox to cover the file types the estate actually receives (Office, PDF, archives, scripts, executables). The load-bearing setting is **allow-on-timeout**: if detonation times out, the policy either **holds** the message or **delivers** it.

- **Hold on timeout** (recommended): a time-sensitive attack that stalls the sandbox does not get delivered. The cost is a delayed message on a genuine timeout.
- **Deliver on timeout**: no delivery delay, but a bypass path for an attacker who can make detonation time out.

Use **Dynamic Delivery** to remove the user-perceived wait: deliver the body immediately, hold the attachment, release it once the sandbox clears. This lets you keep hold-on-timeout without a visible delay for clean mail.

Disposition per verdict: quarantine Malicious (recommended), and either quarantine or deliver-with-warning-tag for Suspicious depending on the group's risk tolerance (tighter for VAPs).

### TAP dashboard

Use the Campaigns view to see what is targeting the organisation, the IOC view to export indicators to firewalls and proxies, and the People view to read the VAP list. The dashboard is the read side; the act side is binding policy to what it shows.

## URL Defense and isolation

Configuration checklist:

- **Rewrite scope**: rewrite all URLs, not just suspicious ones, so the click-time check covers everything.
- **Time-of-click blocking**: on, so a link weaponised after delivery is still caught.
- **Follow redirects**: on.
- **Bypass list**: keep it as small and specific as possible. Legitimate entries are SSO URLs that break when rewritten and partner URLs with signature validation; each entry is uninspected by design, so scope it to the exact host, never a wildcard or a category.
- **URL Isolation**: bind it to risky categories and to the VAP group so a risky click renders in the remote isolation browser instead of on the endpoint.

To investigate a URL Defense block, read the click log for the original URL and the verdict reasoning; if it is a false positive, submit the URL for reclassification rather than adding it to the bypass list. Disable URL Defense only per-sender or per-domain for a genuine compatibility break, never globally.

## TRAP operations

### Automation rules and confidence thresholds

TRAP automation rules gate on a confidence score. The shape that works:

```
Rule: auto-remediate high-confidence malicious
  Condition: TAP verdict = Malicious AND confidence >= 90
  Action: move to Deleted Items (all mailboxes)
  Notify: security distribution list

Rule: analyst queue for medium confidence
  Condition: TAP verdict = Malicious AND confidence 60-89
  Action: create an analyst alert
  SLA: 4 hours

Rule: auto-release not-phish (abuse mailbox)
  Condition: abuse-mailbox report AND TAP verdict = Clean
  Action: move the message back to the inbox
  Notify reporter: "reviewed, not phishing"
```

The threshold is a two-sided risk: too loose (auto-remediate at a low confidence) deletes false positives out of user mailboxes; too tight leaves confirmed-malicious mail sitting past its SLA. Tune against the actual false-positive rate the estate sees, and keep the audit trail on for every remediation.

### Abuse-mailbox workflow

Point TRAP at the abuse / phishing mailbox, set the disposition rules (the malicious threshold for auto-remediation), configure reporter notifications, and set the escalation path for borderline cases. Track reporter accuracy over time; it feeds security-awareness targeting.

## EFD: staging DMARC enforcement

Never flip a domain straight to `reject`. The staged path:

1. **Monitor (`p=none`)**: EFD ingests aggregate reports and maps every sending stream. Do not advance until the map is complete and each stream's alignment is understood.
2. **Quarantine (`p=quarantine`)**: unaligned mail goes to quarantine, not the inbox. Watch for a legitimate stream you missed.
3. **Reject (`p=reject`)**: unaligned mail is rejected. Only when every legitimate stream is aligned.

The sender-side alignment work (SPF includes, DKIM signing, subdomain policy) belongs to `smtp-deliverability`; EFD is where the reports are read and the stance is advanced. Use the supplier-risk and lookalike-domain alerts as standing monitoring, not one-off checks.

## Email DLP and encryption

Outbound (and optionally inbound) DLP scans for sensitive data using built-in classifiers (credit-card via Luhn, national ID numbers, PHI / HIPAA indicators, PCI cardholder data, financial identifiers) and custom dictionaries. Actions: quarantine for review, block with an NDR, encrypt instead of block, tag, notify, or log-only for baselining. Start a new policy in log-only to measure the false-positive rate before switching to block or encrypt.

Encryption modes: push (recipient clicks a link to Proofpoint's secure reader portal), pull (recipient receives a TLS-wrapped attachment needing a password or M365 identity), and S/MIME or PGP where certificates exist. Auto-encryption can trigger on a DLP match (encrypt rather than block), a keyword in the subject, or a recipient domain on the encryption list.

## Read-only audit lens

An audit reads state and reports findings; it never releases, pulls, or activates. Work top-down through the areas below, then prioritise by the threshold table.

### What to check, per area

- **SEG rule ordering**: within each policy route, is any specific block shadowed by an earlier broad allow. Is any route pointing at a policy whose intent has drifted. Ordering is the first pass because a shadowed block is a silent bypass.
- **TAP timeout posture**: is allow-on-timeout set to hold or deliver. Deliver-on-timeout is a finding.
- **URL Defense coverage**: is rewrite scoped to all URLs or only suspicious. Is time-of-click blocking on. Walk the bypass list for wildcard or category-wide entries.
- **TRAP thresholds**: is the auto-remediate confidence sane (not too low), and is the medium-confidence queue serviced within SLA. Is the integration credential least-privilege.
- **VAP-to-policy binding**: does any policy, isolation rule, or training assignment reference the VAP list. A VAP list acted on nowhere is the headline people-centric finding.
- **DMARC stance**: per managed domain, is the domain at the right stage, and is there an unmapped stream blocking advance.
- **Quarantine hygiene**: are Virus / Impostor / Phish folders admin-only. Are release rates on the digest healthy.

### Threshold table

| Finding | Threshold / condition | Severity | First action |
|---|---|---|---|
| Shadowed SEG block rule | A specific block sits below a broad allow that fully covers it | High | Reorder so the specific rule precedes the broad one; confirm in Smart Search |
| TAP deliver-on-timeout | Allow-on-timeout = deliver | High | Switch to hold; enable Dynamic Delivery to hide the latency |
| URL Defense partial rewrite | Rewrite scope = suspicious-only, or time-of-click blocking off | High | Rewrite all URLs; enable time-of-click blocking |
| Broad URL Defense bypass | A bypass entry is a wildcard domain or a URL category | High | Narrow to the exact host, or remove and reclassify the false positive instead |
| TRAP threshold too loose | Auto-remediate confidence < 80, or no analyst SLA on the medium band | Medium-High | Raise the auto-remediate floor; set and staff an SLA |
| Over-scoped TRAP credential | Graph permission beyond Mail.ReadWrite / Mail.Read / MailboxSettings.Read / User.Read.All, or wider Google delegation than gmail.modify + directory readonly | High | Reduce to least privilege; rotate the credential |
| VAP list unused | No policy / isolation / training references the VAP group | Medium-High | Bind force-sandbox + URL Isolation to the VAP group |
| DMARC stalled or premature | At `reject` with an unmapped stream, or stuck at `none` with a clean map | Medium | Roll back a premature reject; advance a ready domain via smtp-deliverability |
| Quarantine folder mis-routed | Virus / Impostor / Phish self-service-releasable | Medium | Make them admin-only |
| Digest ignored | Near-zero release engagement | Low-Medium | Route those users' quarantine to an admin queue |

### Remediation decision trees

**A message the user expected did not arrive.**

```
Is the MX *.pphosted.com  ->  no  -> not Proofpoint Enterprise; route to smtp-deliverability / the actual filter
                          ->  yes
  Smart Search the message
    Disposition = blocked / rejected  -> read the rule / verdict that blocked it; if a false positive, fix the rule (do not just release)
    Disposition = quarantined         -> which folder; release per folder policy (admin-only for Virus / Impostor / Phish); allow sender only if genuinely trusted
    Disposition = delivered           -> the message reached the backend; check the mailbox provider (M365 / Google) and any backend rule, and whether TRAP pulled it post-delivery
    Not found                         -> was it accepted at all; check the connection-level evidence; a SMTP-time reject may not reach Smart Search
```

**A phish reached a mailbox (missed detection).**

```
Smart Search the message; read the TAP verdict
  Verdict = Clean at delivery, malicious later  -> URL Defense time-of-click should have caught the click; check click log; TRAP should auto-pull now
  No TAP verdict (attachment / URL not covered) -> extend TAP attachment-defense coverage; confirm URL Defense rewrites all URLs
  Delivered despite a Suspicious verdict         -> tighten the Suspicious disposition (quarantine, or deliver-with-warning only for low-risk groups)
Then: TRAP-remediate from all mailboxes (a change action, not part of a read-only audit), report the sample to Proofpoint as a false negative, and if the recipient is a VAP, bind stricter controls to the VAP group
```

**A TRAP auto-remediation deleted a legitimate message (false positive).**

```
Read the TRAP audit trail: which rule fired, at what confidence
  Confidence below a sane floor  -> raise the auto-remediate threshold; move that band to the analyst queue
  Correct confidence, bad verdict -> report the false positive to Proofpoint; restore the message from Deleted Items
Then: review whether the abuse-mailbox disposition rules are too aggressive
```
