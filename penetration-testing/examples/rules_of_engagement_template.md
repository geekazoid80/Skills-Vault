# Rules of Engagement: [Engagement Name]

**This document must be signed by an authorised representative of the target
organisation before any active technique begins. No active technique proceeds
on a draft, a verbal approval, or an "implied" authorisation.**

## 1. Parties

- **Client / target organisation**: [name]
- **Client authorising signatory**: [name, title, contact]
- **Testing party**: [name of internal team or third-party firm]
- **Escalation contact** (reachable throughout the time window): [name, phone, email]

## 2. Scope

### In scope
- IP ranges / CIDRs: [list]
- Domains / subdomains: [list]
- Applications: [name, URL, environment: production or staging]
- Physical locations (if Physical channel included): [address(es)]
- Phone numbers / extensions (if Telecommunications channel included): [list]
- SSIDs / wireless networks (if Wireless channel included): [list]

### Explicitly out of scope
- [List anything adjacent that might be assumed in-scope but is not; third-party
  SaaS the client doesn't control, a specific production database, a partner's
  network reachable via a VPN, etc.]

## 3. Channels (OSSTMM)

| Channel | In scope? | Notes |
|---|---|---|
| Human | Yes / No | |
| Physical | Yes / No | |
| Wireless | Yes / No | |
| Telecommunications | Yes / No | |
| Data Networks | Yes / No | |

## 4. Time window

- Start: [date, time, timezone]
- End: [date, time, timezone]
- Blackout windows (no testing during these times): [list, or "none"]

## 5. Allowed techniques

- Exploitation level authorised: [ ] Identification only  [ ] Proof-of-concept exploitation  [ ] Full exploitation with lateral movement (specify boundary)
- Social-engineering pretexts require pre-approval: Yes / No
- Denial-of-service or availability-impacting techniques: **excluded by default**; explicit written exception required, listed here if granted: [ ]
- Physical intrusion methods authorised (if Physical in scope): [list: badge cloning, tailgating, lock bypass, etc.]

## 6. Data handling

- Evidence storage method and encryption: [describe]
- Evidence retention period post-report: [duration]
- Evidence destruction method and confirmation process: [describe]
- Handling of any credentials or PII discovered during testing: per `secrets-hygiene` discipline; never stored in plaintext, never included in the report body.

## 7. Emergency stop condition

If testing causes unexpected impact (service disruption, unintended lockout, data
corruption):

1. Testing stops immediately on the affected target.
2. The escalation contact above is notified within [X] minutes.
3. [Any additional incident-response coordination required, cross-reference the
   client's own `incident-response-lifecycle` process if applicable.]

## 8. Reporting

- Report delivery date: [date]
- Report recipients: [names/roles]
- Re-test commitment for high/critical findings: [date or "to be scheduled"]

## 9. Signatures

| Role | Name | Signature | Date |
|---|---|---|---|
| Client authorising signatory | | | |
| Testing party lead | | | |
