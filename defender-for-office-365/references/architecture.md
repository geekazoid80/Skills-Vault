# Microsoft Defender for Office 365 architecture

The MDO stack sits on top of Exchange Online Protection (EOP). EOP is the always-on baseline every Exchange Online mailbox has; MDO Plan 1 and Plan 2 add the sandbox, the URL rewrite, the impersonation model, and the investigation surface. Understanding the pipeline order and where each control sits is what lets you reason about why a message was delivered, held, replaced, or pulled after the fact.

## The inbound filtering pipeline

Inbound mail moves through sequential stages, and later stages depend on earlier ones.

```
Internet
  -> EOP connection filtering (IP reputation, allow/block list)
    -> EOP anti-malware (signature and heuristic scan)
      -> EOP anti-spam (content analysis, bulk threshold)
        -> Safe Attachments detonation (Plan 1+)
          -> Safe Links delivery-time rewrite (Plan 1+)
            -> Anti-phishing (spoof intelligence, impersonation, mailbox intelligence)
              -> Delivery to the Exchange Online mailbox
                -> ZAP (continuous, post-delivery)
```

Two order facts matter most. Anti-malware runs before anti-spam, so a malware verdict is never filed in Junk (it goes to quarantine). And ZAP runs continuously after delivery, so a message delivered clean can be pulled minutes or hours later when new intelligence arrives. Safe Links click-time protection is not in this delivery pipeline at all; it runs when the user clicks, which is the whole point of it.

### EOP connection filtering

The first line, at the IP and connection level before any content inspection.

- **IP block list**: rejected at SMTP with a 550, never accepted.
- **IP allow list**: bypasses content filtering, so use it sparingly; it skips spam and malware scanning for that IP.
- **Safe list**: Microsoft-curated known-good senders (large consumer providers) that skip some checks.

When a third-party gateway (a SEG) fronts the tenant, configure enhanced filtering (the skip-listing connector) so EOP sees the true originating IP through the SEG rather than filtering on the SEG IP. Without it, IP reputation and spoof intelligence are effectively blind, and an inbound connector must also restrict acceptance to the SEG IPs so a direct-to-tenant send cannot bypass the gateway.

### EOP anti-malware and the common attachments filter

EOP runs multiple anti-malware engines in parallel. On top of content scanning, the common attachments filter blocks a Microsoft-maintained list of executable and script extensions by extension alone, regardless of content (for example `.exe`, `.dll`, `.vbs`, `.js`, `.bat`, `.cmd`, `.hta`, `.lnk`, `.iso`, `.jar`, `.scr`, `.msi`). Organisations can extend the list. Blocking by extension is cheap and catches the obvious payloads before any sandbox work.

## Safe Attachments detonation pipeline

Safe Attachments detonates unknown or suspicious attachments in an isolated VM to catch zero-day malware that signature scanning misses.

```
Message arrives with attachment
  -> EOP signature and heuristic scan
    -> unknown or suspicious? -> Safe Attachments detonation
      -> clone message, strip attachment
        -> Dynamic Delivery: send body now with a placeholder
           Static modes (Block/Replace): hold the whole message
          -> detonate in an isolated VM (Windows plus Office, PDF readers, archive tools)
             behavioural analysis: file, network, and registry activity
            -> verdict: clean / malicious / error
              -> clean: swap the real attachment back in (Dynamic Delivery)
                        or release the held message (static)
                 malicious: quarantine the attachment, notify admin
                 error: deliver the original (fail-open by design)
```

### The action modes

- **Off**: no detonation.
- **Monitor**: detonate and record, but still deliver. Useful for a short baselining window; not a steady-state posture, because malware is delivered.
- **Block**: block malicious attachments, deliver clean ones. The safe operating mode.
- **Replace**: strip the attachment, deliver the body with a notice.
- **Dynamic Delivery**: deliver the body immediately with a placeholder, swap the real attachment in once the verdict is clean. This is the recommended mode because it removes the user-visible delay while keeping full protection.

### Detonation coverage and limits

Detonation covers Office documents, PDFs, common archives (one level deep), executables and scripts (where not already blocked by the common attachments filter). Limits worth knowing: password-protected archives cannot be opened, so they are delivered and flagged for review; very large files can time out; and some obfuscation techniques evade behavioural analysis. On a detonation error the original is delivered (fail-open), which is a deliberate availability trade-off.

### Safe Attachments for SharePoint, OneDrive, and Teams

A separate toggle applies the same detonation engine to files stored in SharePoint, OneDrive, and Teams, not just mail attachments. A malicious file already sitting in a document library is blocked from download and open. This is the collaboration half of "email and collaboration security"; it is off unless explicitly enabled.

## Safe Links URL analysis

Safe Links rewrites URLs at delivery and re-checks them at click time, so a link that was clean when the mail arrived but was weaponised afterwards is still caught.

### Delivery-time rewrite

Every URL in the message body is rewritten to a Safe Links proxy URL in the EOP pipeline before delivery. The rewrite is cosmetic to the user; the original destination is preserved inside the proxy URL.

### Click-time processing

```
User clicks the rewritten link
  -> request hits the Safe Links service (tied to the tenant identity)
    -> real-time check:
       reputation lookup, follow redirect chains, detonate if unknown
      -> safe: redirect to the original URL
         malicious: show the block page
         unknown/scanning: hold for the detonation result
```

Clicks are logged and surface in Threat Explorer (the URL clicks view): user, URL, click time, verdict, and action. That telemetry is why "do not track user clicks" should stay off, and why click-through (letting the user proceed past the block page) should be disabled for real protection.

### The load-bearing settings

- **URLs in email**: scan all inbound URLs (on).
- **URLs in Teams and in Office apps**: extend the same click-time check to Teams links and to links in Word, Excel, and PowerPoint (desktop 16.x and the user signed in with their M365 identity).
- **Safe Links for internal senders**: on, so a compromised internal mailbox is still filtered.
- **Real-time URL scanning** and wait-for-scan: on for the highest protection.
- **Do not rewrite the following URLs**: keep this list lean; every entry is a permanent, unscanned path.

## Anti-phishing architecture

Anti-phishing is where impersonation and spoofing are handled, and they are two different mechanisms.

### Impersonation protection (Plan 1+)

- **User impersonation**: a list of named protected users (up to 60 per policy). Put executives, finance approvers, and other high-value targets here. A message whose display name or address resembles a protected user but comes from elsewhere triggers the policy action.
- **Domain impersonation**: protected domains (your own plus key partner domains). Lookalike domains trigger the action. Detection covers character substitution (`m1crosoft.com`), addition (`microsoftt.com`), deletion (`microsof.com`), subdomain tricks (`microsoft.com.attacker.com`), and Unicode homoglyphs (Cyrillic `a` for Latin `a`).
- **Mailbox intelligence**: a machine-learning model that builds each user's contact graph (who they normally correspond with, how often, response patterns). Mail that deviates sharply scores higher for phishing. This is the control that catches a first-contact "CEO" who has never emailed the target before.

Safety tips shown to users back these up: the unauthenticated-sender indicator (a question mark for SPF/DKIM/DMARC failure), the "via" tag when the display-name sender does not match the From domain, the first-contact tip, and the unusual-characters tip.

### Spoof intelligence and composite authentication

Composite authentication (`compauth`) is Microsoft's meta-verdict combining SPF, DKIM, DMARC, and its own reputation and sending-history signals, visible in the `Authentication-Results` header as `compauth=pass/fail reason=xyz`. It lets a large, established sender that lacks perfect formal authentication still pass on reputation, and conversely flags a domain whose formal records pass but whose behaviour looks forged. Spoof intelligence categorises domain pairs that are spoofing your domains and feeds the Tenant Allow/Block List spoofed-senders view, where legitimate forwarding or bulk scenarios are allowed and known spoofing sources are blocked.

### Advanced phishing thresholds

A four-level dial (Standard, Aggressive, More Aggressive, Most Aggressive). Higher catches more and false-positives more. A common starting point is Aggressive for the general population and More Aggressive or Most Aggressive for a Strict-preset VIP group.

## ZAP (Zero-hour Auto Purge)

ZAP retroactively removes mail that was delivered clean but later judged malicious.

- **How it works**: a message is delivered, new intelligence arrives (a fresh signature, a URL block, a malware verdict), ZAP scans recently delivered mail (a rolling window, seven days by default) and moves matches (to Junk for spam, to quarantine for phish and malware depending on policy).
- **Limits**: it cannot touch mail older than the window, cannot act if the user already moved the message out of the inbox, cannot remove from Sent Items, and needs the mailbox in Exchange Online (not on-premises).
- **Reading ZAP in Threat Explorer**: filter on a delivery action of Replaced or a current delivery location of Quarantine where the original location was Inbox.

Phish ZAP, spam ZAP, and malware ZAP are separate switches on the anti-spam and anti-malware policies; leaving any off is a coverage gap.

## AIR (Automated Investigation and Response), Plan 2

AIR runs playbook-driven investigations off an alert, scopes the compromise, and takes or recommends remediation.

### Triggers and flow

An alert (a user-reported phish, a high-confidence phish or malware verdict, or a signal from another Defender XDR component) starts an investigation. AIR expands scope (searches for related mail by sender, subject, URL, attachment hash), collects evidence, makes a per-entity determination (malicious, suspicious, clean), and generates remediation actions. Actions are gated by the automation level: no automation (all manual), semi-automated (the default: routine actions run, the rest await approval), or full automation (Plan 2 plus Defender XDR).

### Evidence and remediation

Evidence types collected include related email messages, URLs, attachments, recipient mailboxes, IP addresses, and users who interacted. Remediation actions generated include soft-deleting the malicious mail from every affected mailbox, blocking the sender domain or IP in the Tenant Allow/Block List, and marking URLs malicious in Safe Links. The malware playbook adds device correlation when Defender for Endpoint is integrated (was the attachment opened on a device), account-compromise review, and a lateral-movement check (did the user forward the payload internally).

## Defender XDR and SIEM integration

Inside a Defender XDR deployment, MDO alerts correlate with Defender for Endpoint (device), Defender for Identity (on-premises AD), and Entra ID alerts into unified incidents. Advanced Hunting exposes MDO tables (`EmailEvents`, `EmailUrlInfo`, `EmailAttachmentInfo`, `EmailPostDeliveryEvents`, `UrlClickEvents`) to KQL for cross-signal hunting, and the Defender XDR connector streams alerts and hunting data to Microsoft Sentinel for long-term retention and correlation. Route the SIEM correlation work to `siem-soar-investigation`; route the device-side depth to `endpoint-detection-response`.

## EOP versus Plan 1 versus Plan 2 capability matrix

| Capability | EOP | Plan 1 | Plan 2 |
|---|---|---|---|
| Anti-spam | Yes | Yes | Yes |
| Anti-malware and common attachments filter | Yes | Yes | Yes |
| Spoof intelligence and composite authentication | Yes | Yes | Yes |
| Anti-phishing (basic) | Yes | Yes | Yes |
| Safe Attachments (email) | No | Yes | Yes |
| Safe Links (email) | No | Yes | Yes |
| Safe Attachments (SharePoint / OneDrive / Teams) | No | Yes | Yes |
| User and domain impersonation protection | No | Yes | Yes |
| Mailbox intelligence | No | Yes | Yes |
| Real-time detections | No | Yes (read-only) | Yes |
| Threat Explorer | No | No | Yes |
| Automated Investigation and Response (AIR) | No | No | Yes |
| Attack Simulation Training | No | No | Yes |
| Campaign views | No | No | Yes |
| Priority account protection | No | No | Yes |
| Advanced Hunting (MDO tables) | No | No | Yes |

**Licence mapping (indicative, confirm against current Microsoft licensing):**

- **EOP**: Exchange Online Plan 1 and 2, and Microsoft 365 Business Basic, Standard, and Premium via Exchange.
- **Plan 1**: Microsoft 365 Business Premium, or E3 with the Defender for Office 365 Plan 1 add-on.
- **Plan 2**: Microsoft 365 E5 or E5 Security, or the Defender for Office 365 Plan 2 add-on on an E3 base. Plan 2 includes Plan 1.
