---
name: smtp-deliverability
description: Use for any SMTP / email-sending discipline work, deliverability triage, or new-sender bring-up. Triggers include "set up email sending", "configure SPF / DKIM / DMARC", "domain authentication", "DMARC rollout", "subdomain isolation", "transactional vs marketing email", "email landing in spam", "Gmail Promotions tab", "Microsoft junk", "warm up a new domain", "warm up dedicated IP", "sender reputation", "Google Postmaster", "Microsoft SNDS", "blocklist", "complaint rate", "bounce handling", "suppression list", "List-Unsubscribe", "one-click unsubscribe", "RFC 8058", "Google Yahoo Microsoft 2024 bulk sender rules", "CAN-SPAM", "GDPR email consent", "CASL", "switch email provider", "provider abstraction", "Resend", "SendGrid", "SES", "Postmark", "Mailgun", "Sparkpost". Covers domain-authentication setup (SPF 10-lookup limit, DKIM key length, progressive DMARC rollout p=none -> quarantine -> reject), subdomain-per-stream isolation (mail / notify / marketing on separate subdomains), provider abstraction (vendor-neutral interface), warmup curves for domain and IP, reputation monitoring, suppression-list state machine, bounce taxonomy, compliance baselines for CAN-SPAM / GDPR / CASL plus Google / Yahoo / Microsoft 2024 bulk-sender rules. Vendor-neutral; works with Resend / SES / SendGrid / Postmark / Mailgun / Sparkpost / on-prem Postfix or Exim. Folded from chunkydotdev/email-skills (MIT) and vibeeval/vibecosystem/email-infrastructure (MIT).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# SMTP and email deliverability

The technical counterpart to `humanise-comms`. That skill covers what the email **says**; this skill covers whether it **arrives**. Both fire when a project starts sending email; neither alone is enough.

Email deliverability is governed by three factors, in this order of importance: **authentication** (the receiving server can verify you), **reputation** (the receiving server has positive history with you), and **content + engagement** (recipients open, click, reply, do not mark as spam). Get authentication wrong and the other two never get a chance.

> **Skill marker**: When applying this skill, begin your reply with `[skill: smtp-deliverability]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the sending estate (subdomain strategy per stream, ESP list, DMARC reporting posture, BIMI plans) before making DNS or sender-policy changes. Only ask the user for information not already covered or specific to this stream.

Before changing DNS or sender policy, understand:

1. **Sending stream and identity**
   - Stream type (transactional, marketing, support, automated alerts)?
   - Sending subdomain plan (one subdomain per stream is the iron rule)?
   - ESP / relay involved (SendGrid, Postmark, Amazon SES, Postfix, others)?

2. **Authentication baseline**
   - Existing SPF, DKIM, DMARC records and their current policies (`p=none`, `quarantine`, `reject`)?
   - DMARC reporting destination and review cadence?
   - BIMI / MTA-STS posture (in place, planned, out of scope)?

3. **Change scope and risk**
   - Net-new domain, policy tightening (`none` to `quarantine`), or stream migration?
   - DNS change-control path (registrar, CDN, IaC)?
   - Rollback plan if a policy change causes legitimate mail to bounce?

### Scope boundary vs `gmail-workflows`

Sender-side infrastructure (SPF / DKIM / DMARC, subdomain isolation, warmup curves, suppression lists, Postmaster Tools, blocklist triage, ESP / provider abstraction) lives here. Gmail-client tasks against the user's own inbox (read a thread, search the inbox, draft a reply, manage labels, follow up after a meeting) live in `gmail-workflows`. The wired Gmail MCP only drafts; it does not send, which is a client-side constraint, not a deliverability one.

Use both skills when a chunk crosses the boundary. A common case: a customer complaint thread lands in the user's Gmail (`gmail-workflows` for the search-then-read and draft-reply) AND the complaint is about deliverability (`smtp-deliverability` for the diagnosis and any DNS / DMARC / suppression-list remediation).

---

## The iron rule: one subdomain per sending stream

Before any other technical work, decide the subdomain layout. Conflating streams on one domain is the most common single mistake.

| Stream | Subdomain (example) | What sends from here |
|---|---|---|
| Transactional | `mail.example.com` | Password reset, receipts, 2FA, account verification, order confirmations. Sent in response to a user action. Volume low to medium; engagement very high; near-zero complaints. |
| Notifications | `notify.example.com` | Comments, mentions, digests, low-frequency product updates. User opted in but did not directly trigger. Engagement medium. |
| Marketing / bulk | `marketing.example.com` | Newsletters, campaigns, promotions, re-engagement. Highest complaint risk. |
| Cold outreach | `outreach.example.com` (separate domain often safer) | Sales prospecting. The riskiest. Many programs use a separate root domain entirely so a deliverability hit cannot poison the brand domain. |

Each subdomain has its own SPF, DKIM, DMARC, and reputation. A bad campaign on `marketing.example.com` does not stop password resets on `mail.example.com`.

The apex domain (`example.com`) sends nothing. It exists for branding and for an enforcing DMARC policy that catches spoofing of the apex.

## Domain authentication: SPF, DKIM, DMARC

All three are DNS TXT records. All three are mandatory in 2024 and beyond for any sender doing more than ~5000 messages per day to Gmail or Yahoo (the bulk-sender rules below).

### SPF: which servers may send on your behalf

```
mail.example.com  TXT  "v=spf1 include:_spf.provider.com ~all"
```

- `v=spf1`: SPF version.
- `include:_spf.provider.com`: pull in your ESP's authorised servers.
- `~all`: soft-fail anything not listed (mark suspicious, do not reject). Use `-all` (hard fail) only after you are confident every legitimate sender is included.

**The 10-lookup limit.** SPF allows a maximum of 10 DNS lookups per evaluation. Each `include:` and `redirect:` counts. Each ESP `_spf.provider.com` is itself an `include:` chain that often eats 2-4 lookups. Stack three ESPs and you blow the limit; receivers then return PermError and your mail fails authentication.

Mitigations: SPF flattening (one TXT record listing the resolved IPs; needs automation to refresh), or move some streams to a different subdomain so each subdomain has its own 10-lookup budget.

### DKIM: cryptographic signature on every message

```
selector._domainkey.mail.example.com  TXT  "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSI..."
```

- `selector`: arbitrary string, lets you have multiple keys in flight (rotation, multiple ESPs).
- `k=rsa`: key type. RSA-2048 is the modern default; RSA-1024 is now considered weak; Ed25519 is supported by some receivers.
- `p=...`: the public key. The ESP signs outgoing mail with the private key.

Rotate DKIM keys at least annually. Run two selectors in parallel during rotation: publish the new selector, switch the ESP to sign with the new key, wait for in-flight mail to deliver, then remove the old selector.

### DMARC: policy for failed authentication

DMARC sits on top of SPF and DKIM. It tells receivers what to do when both fail, and it asks them to email you reports.

```
_dmarc.mail.example.com  TXT  "v=DMARC1; p=none; rua=mailto:dmarc-reports@example.com; adkim=s; aspf=s"
```

- `p=none`: monitor only. Catches misconfigurations before they block legitimate mail.
- `p=quarantine`: on failure, mark as spam.
- `p=reject`: on failure, refuse delivery.
- `rua=`: aggregate reports (daily summaries from receivers). Always set this; the reports are how you know rollout is safe.
- `adkim=s` / `aspf=s`: strict alignment (signing domain must exactly match From domain, not just be a parent). Use strict by default; relaxed (`r`) only when you have a good reason.

**Progressive rollout, never jump straight to reject.**

| Phase | Duration | Policy | What you do |
|---|---|---|---|
| 1 | Week 1-2 | `p=none` | Read aggregate reports daily. Identify every legitimate sender that fails alignment. Fix or whitelist each one. |
| 2 | Week 3-4 | `p=quarantine; pct=25` | Quarantine 25% of failures. Watch reports. Watch user complaints about missing mail. |
| 3 | Week 5-6 | `p=quarantine; pct=100` | All failures quarantined. Settle period. |
| 4 | Week 7+ | `p=reject` | Failures rejected. The destination state for any production sending domain. |

The apex domain (`example.com`) should be at `p=reject` from day one if it sends nothing; this prevents spoofing.

## Bulk-sender rules (Google, Yahoo, Microsoft; 2024 onward)

If you send more than ~5000 messages per day to a single major receiver, three rules apply. Microsoft adopted the same set in May 2025.

1. **Authenticate.** SPF, DKIM, DMARC all pass. DMARC at `p=quarantine` minimum (Google initially required only `p=none`; the floor is rising).
2. **One-click unsubscribe** (RFC 8058). The `List-Unsubscribe` header must include both `mailto:` and `https://` forms; the `https://` endpoint must accept a POST and unsubscribe in a single click without further interaction. The `List-Unsubscribe-Post: List-Unsubscribe=One-Click` header is mandatory.
3. **Spam complaint rate under 0.3%** (hard limit; aim for under 0.1%). Measured in the receiver's own postmaster tools (Google Postmaster Tools for Gmail, SNDS for Microsoft, no equivalent public tool for Yahoo).

A failure on any of the three at sustained scale results in throttling first, then outright rejection.

## Warmup: building reputation from zero

Mailbox providers track reputation per domain and per IP. A new domain with no history is **unknown** (not bad, but not trusted). Pushing thousands of messages from an unknown sender on day one looks indistinguishable from a freshly-registered spammer.

**Domain reputation matters more than IP reputation in 2024+.** Most senders use shared IP pools at their ESP, where IP reputation is amortised across many tenants. Domain reputation is yours alone.

### Domain warmup curve (transactional / shared IP)

Typical curve, per receiver, doubling daily within tolerance:

| Day | Daily volume target | Notes |
|---|---|---|
| 1-3 | 50 | Seed list of engaged opted-in recipients. |
| 4-7 | 100-500 | Watch deferral rate; back off if it climbs. |
| 8-14 | 500-2000 | Begin including production traffic. |
| 15-30 | 2000-10000 | Full production for a small sender. |
| 30+ | scale to need | High-volume senders continue ramping over 60-90 days. |

If deferrals climb above a few percent, **stop ramping and hold volume flat for 3-5 days**. Continuing to push through deferrals damages reputation. Reduce volume if needed, then resume the curve.

### Dedicated IP warmup

Add 2-3 weeks for a dedicated IP. Below ~100k messages per month per receiver, dedicated IPs are usually a deliverability **disadvantage** (insufficient volume to maintain warm reputation; idle IPs cool fast). Use shared IPs at smaller scale.

## Reputation monitoring

Set these up the same week the first message goes out.

| Tool | What it tells you | Setup cost |
|---|---|---|
| Google Postmaster Tools | Domain reputation (high / medium / low / bad) for Gmail; spam rate; auth pass rates; encryption rate; delivery errors. | TXT record verification; takes a few hours. |
| Microsoft SNDS | IP reputation for Microsoft (Outlook, Hotmail, Live). Per-IP daily volume, complaint rate, trap hits. | Account creation; per-IP request approval. |
| MXToolbox blocklist check | Whether your sending IPs or domain appear on Spamhaus, SORBS, Barracuda, etc. | Free; check weekly or on alert. |
| DMARC aggregate report tooling | Postmark DMARC Digests, Valimail, dmarcian (and many open-source options). Parses the daily XML reports into a readable dashboard. | Point `rua=` at the tool's address. |

Watch trends, not single days. Reputation moves slowly; one-day dips are noise, week-long dips are signals.

## Suppression-list discipline

Every email system needs a suppression list and the discipline to honour it. The state machine:

```
                    sent
                     |
            +--------+--------+
            |                 |
        delivered          bounced
            |              /     \
       +----+----+    soft       hard
       |         |    |             |
   complained  unsub  retry      SUPPRESS PERMANENTLY
       |         |    (3-5x with
       |         |    backoff)
       v         v        |
    SUPPRESS  SUPPRESS    |
                    if persistent
                          |
                          v
                       SUPPRESS PERMANENTLY
```

Categories that **always suppress**:

- Hard bounce (5xx SMTP code; address does not exist or domain blocks you).
- Spam complaint (FBL feedback; user clicked "report spam").
- Unsubscribe (one-click or otherwise).
- Manual addition (legal request, GDPR erasure, internal blocklist).

Soft bounces (4xx; mailbox full, greylisted, temporary defer) get retried with exponential backoff. After ~5 consecutive soft bounces over several days, treat as hard.

Suppression scope must include both **account** (your sender's own list) and **global** (across the entire platform if you operate one). Migrating ESPs requires migrating suppressions; otherwise day one you re-mail everyone who previously bounced or unsubscribed and your reputation collapses immediately.

## Provider abstraction

Pick one ESP, but write the integration so swap is one config change. The interface is small.

```ts
interface EmailProvider {
  send(message: EmailMessage): Promise<EmailResult>;
  sendBatch(messages: EmailMessage[]): Promise<EmailResult[]>;
}

interface EmailMessage {
  from: string;          // must match an authenticated subdomain
  to: string | string[];
  subject: string;
  html: string;
  text?: string;         // always include for accessibility + spam scoring
  replyTo?: string;
  headers?: Record<string, string>;
  tags?: Record<string, string>;
}
```

Reasons to swap: pricing change at scale, deliverability dispute, region requirement (EU data residency), feature gap (e.g. needing inbound parsing the current ESP does not support). Reasons not to swap as a fix: poor deliverability is rarely the ESP's fault and almost always the sender's authentication, content, or list hygiene.

Multi-provider failover (primary + secondary) is overkill for most senders and adds reputation-management complexity (now you have two reputations to maintain). Consider it only at high volume where minutes of ESP downtime cost real money.

## Compliance baselines (the three laws you will hit)

| | CAN-SPAM (US) | GDPR (EU / EEA / UK) | CASL (Canada) |
|---|---|---|---|
| Consent model | Opt-out (send until they unsubscribe) | Opt-in (consent before sending) | Opt-in (express or implied) |
| Applies to | Commercial email | All processing of personal data | Commercial electronic messages |
| Unsubscribe deadline | 10 business days | Without undue delay (~30 days) | 10 business days |
| Identification required | Physical postal address; clear sender ID | Identity of controller; purpose | Sender name; physical or email address |
| Penalty per violation | Up to $51,744 USD | Up to 4% of global annual revenue | Up to CAD $10M per violation |

Pragmatic posture: **use opt-in everywhere**. It satisfies all three at once. CAN-SPAM allows opt-out but the cost of also collecting opt-in is small; the cost of having to disentangle a mixed list later is large.

For transactional email, all three laws are largely silent. The line is whether the email is **in response to a user action** (transactional, exempt) or **commercially motivated outreach** (commercial, subject to the rules). A receipt that includes a "while you are here, browse these new products" promo block becomes commercial and triggers the unsubscribe requirement.

Keep transactional and commercial on **separate subdomains** (per the iron rule above) so a recipient who unsubscribes from marketing still receives password resets.

## Diagnostic flow when mail does not arrive

1. **Authentication first.** Send a test to `check-auth@verifier.port25.com` (or any modern equivalent: `mail-tester.com`, Postmark Spam Check, Google's "show original"). All three of SPF, DKIM, DMARC must pass and align. If not, fix this before anything else; nothing downstream matters.
2. **Receiver disposition.** Check the receiving inbox + spam + Promotions tab. "Lost" mail is usually filtered, not lost. Check Google Postmaster Tools / Microsoft SNDS for the receiving domain.
3. **Bounce log.** If the message bounced, the SMTP code tells you the category. 550 = address rejected; 5.7.1 = sender blocked; 4.7.0 = temporary defer; 5.1.1 = no such user. Search the exact code.
4. **Reputation.** If a single recipient is fine but a class of recipients fail, check whether your domain or IP is on a blocklist.
5. **Content scoring.** Use a content scorer (mail-tester.com gives a Spamassassin-style score). Common content traps: bare URLs without context, mismatched From / Reply-To domains, large image-to-text ratio, suspicious link shorteners, missing plain-text alternative.
6. **Engagement.** If everything else is fine but recipients still mark as spam: the content is unwanted. The fix is list hygiene and consent quality, not technical.

## Verification before claiming done

Per `completion-gate`, "set up email" is not a finish line. Before the chunk closes:

- [ ] SPF passes, DKIM signs, DMARC aligns. Verified by sending a test to a check-auth address (not by reading the DNS records and trusting them).
- [ ] DMARC at `p=none` for at least 14 days **with reports being read** before any policy advance.
- [ ] List-Unsubscribe header present and the one-click endpoint returns HTTP 200 within 5 seconds without a confirmation step.
- [ ] Suppression list wired to the ESP webhook (bounces, complaints, unsubscribes); a manual test bounce is suppressed end-to-end.
- [ ] Google Postmaster Tools verified for at least the apex domain and the active sending subdomain.
- [ ] Reverse DNS (`PTR`) on the sending IP matches the HELO hostname (relevant for self-hosted SMTP; ESPs handle this).
- [ ] If self-hosting (Postfix / Exim): TLS configured (1.2 minimum); no open relay (smoke-tested); no SMTP AUTH on the public port without TLS.

## Cross-references

- `humanise-comms`: writes what the email says (voice, structure, no em dashes, escalation contact). Both skills fire for any human-bound email; technical compliance with this skill plus voice compliance with that one is the minimum bar.
- `secrets-hygiene`: ESP API keys, DKIM private keys, SMTP AUTH credentials all live in the secret store. DKIM private keys never get committed; if one leaks, rotate the selector and revoke the old key.
- `plan-time-tooling`: any chunk that introduces a new sending subdomain or moves to a new ESP is an `engineering:deploy-checklist` trigger. Surface the DMARC rollout calendar, the warmup curve, and the suppression-migration plan in the chunk's Tooling block.
- `completion-gate`: the verification checklist above is the layer-3 gate. "Set up DKIM" without a signed-and-verified test send does not count.
- `forward-compatible-schemas`: the suppression-list schema is itself a contract. Adding fields is additive (safe). Removing categories or changing reason codes breaks consumers; sequence as add-new, migrate readers, then drop.
- `oncall-runbooks`: a deliverability incident has its own runbook (drop in inbox placement, blocklist hit, complaint rate spike). The triage flow above is a starting point.
- `consumer-rollout`: when a new sending capability ships (e.g. inbound parsing, transactional template engine), drop a "Required hooks" section into each consumer service's `AGENTS.md` so future scoping picks it up.

## Red flags

- About to send the first production batch from a brand-new domain without a warmup curve.
- About to set DMARC `p=reject` straight from `p=none` without the quarantine intermediate.
- About to send marketing and transactional mail from the same subdomain.
- About to commit a DKIM private key, ESP API key, or SMTP password into a tracked file or environment-baked image.
- About to use the apex domain (`example.com`) directly as the From address for bulk mail.
- About to fly past the SPF 10-lookup limit by stacking ESPs without flattening or splitting subdomains.
- About to migrate ESPs without porting the suppression list first.
- About to skip the List-Unsubscribe one-click endpoint and rely on a body link only (this fails the 2024 bulk-sender rules at scale).
- About to retry a hard bounce; about to keep mailing an unsubscribed address; about to silently drop GDPR erasure requests on the floor.
- About to mark a deliverability problem as "the ESP's fault" without first verifying authentication, reputation, and content scoring.
- About to disable DMARC reporting (`rua=`) "to reduce noise". The reports are how you find out something broke before it hurts.
- About to use a personal Gmail / Outlook account as the From for any production system mail. Both reject mail bearing their domain that does not originate from their servers.

## Bottom line

Authenticate with SPF + DKIM + DMARC, isolate streams onto subdomains, warm new domains and IPs gradually, monitor reputation continuously via Google Postmaster Tools and DMARC reports, suppress aggressively (hard bounce + complaint + unsubscribe = forever), keep an opt-in mindset for compliance, and verify with a real signed-and-aligned test send before claiming the setup is done.

## External resources

- RFC 7208 (SPF), RFC 6376 (DKIM), RFC 7489 (DMARC), RFC 8058 (one-click unsubscribe).
- Google Postmaster Tools: https://postmaster.google.com/
- Microsoft SNDS: https://sendersupport.olc.protection.outlook.com/snds/
- Bulk sender requirements (Google): https://support.google.com/mail/answer/81126
- Bulk sender requirements (Yahoo): https://senders.yahooinc.com/best-practices/
- mail-tester.com (content + auth scoring; free seven tests per day per IP).
