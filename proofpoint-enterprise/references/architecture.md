# Proofpoint Enterprise architecture

The platform underneath Email Protection: the module map, the SEG mail flow and ordered filtering stack, deployment models, TAP sandboxing and Nexus intelligence, URL Defense encoding and the click-time flow, TRAP integration, the people-centric VAP model, and Email Fraud Defense. This is the "how it is built" reference; configuration, operations, and the audit lens live in `operations.md`, and the programmatic surface lives in `api-and-automation.md`.

## Platform and module map

Proofpoint Enterprise is a suite of separately licensed modules that share the gateway and the Nexus threat-intelligence backbone:

```
Proofpoint Enterprise
|- Email Protection (SEG / PPS)     core gateway, anti-spam, anti-malware, policy engine
|- Targeted Attack Protection (TAP) attachment sandbox, URL Defense analysis engine
|- Enterprise URL Defense           URL rewrite, time-of-click, URL Isolation
|- Threat Response Auto-Pull (TRAP) post-delivery remediation, abuse-mailbox automation
|- Nexus People Risk Explorer       VAP, attack index, human-risk scoring
|- Email Fraud Defense (EFD)        DMARC management, supplier risk, lookalike domains
|- Email DLP                        outbound data-loss prevention
|- Email Encryption                 on-demand and policy-based encryption
|- Security Awareness Training      phishing simulation, coaching (adjacent, out of scope here)
```

Licensing matters for advice: a customer with SEG but no TAP has no sandbox and no URL Defense; a customer with TAP but no TRAP can detect a post-delivery-malicious message but cannot auto-pull it. Confirm which modules are licensed during the initial assessment before recommending a control that depends on one.

## SEG deployment models

### Cloud (Proofpoint-hosted)

The common case. Proofpoint runs regional clusters (US, EU, APAC, Canada, Australia); customer data is processed and stored in the selected region, which matters for GDPR and data residency. The design is active-active with automatic failover, so there is no customer-visible single point of failure in Proofpoint's infrastructure.

MX pattern is regional:

```
US:   mail.pphosted.com
EU:   eu-mail.pphosted.com
APAC: ap-mail.pphosted.com
```

### On-premises (PPS, the Proofpoint Protection Server)

Some regulated customers run Proofpoint on-prem as physical appliances (M-series) or virtual appliances (VMware ESXi, Hyper-V). Hardware sizing scales with mail volume.

```
Inbound MTA -> Proofpoint PPS cluster -> downstream MTA
                     |
              Proofpoint Spam Labs
              (cloud intelligence feeds, ~5 minute update cycle)
```

On-prem deployments still pull cloud-based threat intelligence from Proofpoint Spam Labs, so they are not air-gapped from the Nexus feed.

### Hybrid

Some estates run on-prem for one direction (inbound) and cloud for the other (outbound), or split by business unit. Establish the actual topology before commanding mail flow.

### Locking the backend so mail cannot bypass the gateway

Whichever model, the backend mailbox provider must accept mail only from Proofpoint, or an attacker can deliver straight to the mailbox and skip every control. For M365, create an inbound connector in the Exchange admin centre restricted to Proofpoint's published IP ranges with TLS required; the equivalent exists for Google Workspace and on-prem Exchange. This lock is the precondition for every SEG control being meaningful.

## SEG mail flow and the ordered filtering stack

SEG is an inline gateway: the MX points at Proofpoint, not the mailbox server.

```
Inbound:  Internet -> Proofpoint SEG (MX: *.pphosted.com) -> filtering -> backend (M365 / Google / on-prem)
Outbound: backend -> Proofpoint SEG (SMTP smarthost) -> Internet
```

The inbound filtering stack runs in order, and the order is load-bearing because each stage can dispose of a message before later stages see it:

1. **Connection-level filtering**: IP reputation, sender score, block lists (Cloudmark, Spamhaus, Proofpoint's own).
2. **Dynamic Reputation (DR)**: machine-learning IP and domain reputation, updated about every 5 minutes.
3. **Anti-virus**: multiple signature engines.
4. **Anti-spam**: machine learning plus rules, with a configurable spam threshold (score 0 to 100).
5. **TAP sandbox**: detonation for suspicious attachments, if TAP is licensed.
6. **URL Defense**: URL rewriting and analysis, if TAP is licensed.
7. **Content policies**: custom rules, DLP, regulatory compliance.
8. **Email authentication**: SPF, DKIM, DMARC verification and enforcement.

### Policy routes and filter rules

Policy is hierarchical:

- **Policy routes** decide which policy applies to which traffic, matched on sender domain, recipient domain, IP, and so on.
- **Filter rules** within a route are processed in priority order. A rule matches on sender, recipient, subject, body, attachments, headers, authentication result, or spam score, and takes an action: deliver, quarantine, block, tag subject, add header, redirect, discard, or encrypt.
- **Action precedence** when several rules match: block > quarantine > discard > encrypt > deliver. Higher severity wins.

Quarantine is foldered, not a single bucket: the default folders are Spam, Bulk, Adult, Virus, Impostor, and Phish, and custom folders can be created per policy. Users receive the End User Spam Digest (operations detail in `operations.md`).

## Targeted Attack Protection (TAP)

TAP adds sandboxing and URL analysis for threats that evade signature detection, powered by Nexus threat intelligence.

### Attachment defense

Supported detonation types include Office documents (`.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, macro-enabled variants), PDFs, archives (`.zip`, `.rar`, `.7z`, one level deep), executables (`.exe`, `.dll`), and scripts (`.js`, `.vbs`, `.ps1`, `.bat`).

Detonation flow:

1. Message arrives with an attachment.
2. Attachment submitted to the cloud sandbox across multiple OS environments.
3. Behavioural analysis: file-system, network, process, and registry activity.
4. Static analysis: code patterns, embedded URLs, macros.
5. Verdict returned: Malicious, Suspicious, or Clean.
6. Action applied per TAP policy.

**Dynamic Delivery** removes the user-perceived wait: the message body is delivered immediately while the attachment is held and released once the sandbox clears it, which is Proofpoint's equivalent of Microsoft's Safe Attachments dynamic delivery. Sandbox latency is typically 2 to 8 minutes; the allow-on-timeout posture (hold versus deliver) is the security decision covered in `operations.md`.

### Nexus threat intelligence

TAP is powered by Nexus, Proofpoint's research infrastructure that processes billions of messages daily:

- **NexusAI**: machine-learning models trained on millions of malicious samples daily plus global email telemetry.
- **Emerging Threats (ET Intelligence)**: Proofpoint acquired Emerging Threats in 2015; the ET Pro ruleset feeds Snort / Suricata IDS/IPS and is integrated into TAP for URL and attachment reputation.
- **Dynamic Reputation (DR)**: real-time IP and domain reputation, updated about every 5 minutes from spam-trap hits, malware command-and-control connections, phishing-page detections, and botnet indicators.

The TAP dashboard surfaces campaigns (attack volume over time, malware-family breakdown), indicators of compromise (IPs, domains, URLs, hashes, exportable to firewalls and threat-intel platforms), and people risk (the VAP list, described below).

## Enterprise URL Defense

URL Defense rewrites URLs at delivery and re-checks them at time of click, so a link benign at delivery but weaponised later is still caught.

### Encoding schemes

Version 2 (legacy):

```
https://urldefense.proofpoint.com/v2/url?u=<base64url-encoded-original>&d=<domain>&c=<campaign>&r=<recipient>&m=<message-id>&s=<signature>
```

Version 3 (current), more readable and preserving the original URL structure:

```
https://urldefense.com/v3/__<original-url>__;<tracking-token>
```

For investigation, a wrapped URL can be decoded: version 2 by base64url-decoding the `u=` parameter, version 3 by extracting the portion between the `__` delimiters. Proofpoint provides a decoder tool in the TAP portal.

### Time-of-click flow

```
User clicks a URL Defense link
  -> Proofpoint URL Defense service receives the request
  -> validate: is this a valid Proofpoint-wrapped URL for this tenant
  -> check the reputation cache (fast path, sub-100ms)
       hit  -> return cached verdict -> block / allow
       miss -> submit to NexusAI, follow the redirect chain,
               analyse the final destination, browser-emulate if needed,
               cache the verdict -> block / allow / warn
```

Redirect-chain analysis follows all redirects (including JavaScript and time-delayed redirects) to the final destination, which catches URL-shortener abuse and multi-hop chains. Geo-appropriate request headers expose phishing kits that serve malicious content only to victims in specific countries.

### URL Isolation

For risky categories or high-risk (VAP) users, URL Defense can hand the click to a remote isolation browser: the page renders in Proofpoint's cloud and only a safe visual stream reaches the endpoint, so a drive-by or credential-harvest page never touches the device. Isolation is the strictest click posture short of an outright block and is the natural control to bind to the VAP group.

## Threat Response Auto-Pull (TRAP)

TRAP automates post-delivery remediation: it removes a message from mailboxes after delivery once it is known malicious.

Trigger sources: a TAP malicious verdict on an already-delivered message, a manual analyst submission, an automated SIEM / SOAR playbook, or the Proofpoint threat-intelligence feed.

Remediation flow:

1. Malicious message identified by hash, message-ID, or TAP verdict.
2. TRAP queries the mail server for every mailbox holding the message.
3. TRAP connects via the backend API (Microsoft Graph for M365, Gmail API for Google, EWS / IMAP for on-prem).
4. Message moved to Deleted Items or permanently deleted per policy.
5. Forwarded copies also remediated.
6. Audit trail retained for every action.

### M365 integration (Microsoft Graph)

```
TRAP (Proofpoint cloud) -> Azure app registration (tenant ID, client ID, client secret)
                        -> Microsoft Graph API -> Exchange Online mailboxes
```

Least-privilege application permissions: `Mail.ReadWrite` and `Mail.Read` (application, not delegated), `MailboxSettings.Read` (to detect forwarding rules), and `User.Read.All` (to enumerate users during search). Granting more than this is a red flag; the token can read and delete mail across the whole tenant.

### Google Workspace integration

```
TRAP (Proofpoint cloud) -> Google service account (domain-wide delegation, JSON key)
                        -> Gmail API -> Google Workspace mailboxes
```

Least-privilege scopes: `https://www.googleapis.com/auth/gmail.modify` (move / label) and `https://www.googleapis.com/auth/admin.directory.user.readonly` (enumerate users).

### Abuse-mailbox automation

TRAP can process user-reported phishing from an abuse / phishing mailbox: it monitors the mailbox, analyses reported messages, auto-remediates confirmed-malicious ones from all mailboxes, routes uncertain ones to an analyst queue, and always sends the reporter feedback. Reporter accuracy can be tracked over time, which doubles as a security-awareness signal. Automation-rule thresholds live in `operations.md`.

## Nexus People Risk Explorer and VAP

Nexus integrates threat data with identity to quantify human risk, which is the people-centric core of the platform.

### Very Attacked People (VAP)

VAP identifies users disproportionately targeted by advanced threats (credential phishing, malicious attachments, targeted attacks), not by bulk spam. The calculation weights the volume of targeted attacks by sophistication, the share of attacks in the top percentile, the attack types (credential phishing, malware delivery, business email compromise), and the trend direction.

The point of VAP is that the most-attacked people are frequently not the executives, so binding policy and training to the VAP list, rather than to the org chart, is the people-centric move: force-sandbox all attachments for VAPs, apply URL Isolation, tighten their click policy, and prioritise them in incident response. The VAP feed is exposed via the People API (see `api-and-automation.md`) for integration with HR, PAM, and SIEM.

### Attack index

A normalised per-user severity score combining attack volume, sophistication (a TAP sandbox hit weighs more than a spam hit), trend direction, and a historical baseline. It enables comparison across departments and peer groups and is the number the CISO dashboard reports to the board. Privilege-escalation risk (a high-access account that is also high-VAP) is the highest-priority combination.

## Email Fraud Defense (EFD): DMARC management

EFD is the DMARC management module.

It ingests `rua=` aggregate reports from every receiving mail service (Google, Microsoft, Yahoo, and others), normalises them across providers, identifies every email stream sending on behalf of the domain, fingerprints sources to known services (ESP identification), and tracks the authentication pass rate per source over time. That mapping is the precondition for safe enforcement: a domain moves monitor -> quarantine -> reject only once every legitimate stream is identified and aligned.

The supplier-risk module monitors DMARC authentication for key suppliers and alerts when a supplier's DMARC degrades (a possible supplier compromise). Lookalike-domain monitoring watches DNS for newly registered domains that resemble the customer's or a supplier's domain (character substitution, new TLDs, subdomain lookalikes) and alerts on registration.

The sender-side DMARC rollout discipline (the four-phase move from `p=none` to `p=reject`, SPF and DKIM alignment) belongs to `smtp-deliverability`; EFD is where those reports are read and enforcement is staged on the Proofpoint side.

## Smart Search: the investigation database

Smart Search indexes message metadata for the retention period (default 30 days, extendable with the archiving add-on). Indexed fields include the envelope sender, header From, all recipients, subject, message-ID, timestamp, attachment names / types / hashes, extracted URLs, filtering verdicts and scores, disposition, and the TAP verdict. The message-details view shows the full routing headers, the SPF / DKIM / DMARC results, the policy route and rules that matched, the spam-score breakdown, the TAP verdict, the URL Defense click data, and every recipient of the same message. Smart Search is the trace that confirms a change did what was intended and the starting point for any investigation.
