# Prisma Access operations: policy, profiles, GlobalProtect, decryption, the posture audit, and troubleshooting

Day-to-day configuration and operations for a running Prisma Access tenant, plus the SASE posture-audit flow with threshold tables and remediation decision trees. Architecture and the packet pipeline live in `architecture.md`; the API and CLI live in `api-and-automation.md`.

## Security policy on Prisma Access

Prisma Access uses standard PAN-OS security-policy rules, familiar to anyone who has run a PAN-OS NGFW, but scoped per policy folder (`Mobile Users`, `Remote Networks`, `Service Connections`, `Shared`). A rule filed in the wrong folder protects nothing.

Rule structure for internet-bound mobile-user traffic:

```
Source Zone: Trust (internal users)
Source Address: any
Source User: domain\group or individual user
Destination Zone: Untrust (internet)
Destination Address: any
Application: web-browsing, ssl, google-drive (App-ID)
Service: application-default
Action: Allow
Profile Group: Best-Practice (AV, IPS, URL, DNS, WildFire, DLP)
```

App-ID on Prisma Access is the same engine as on PAN-OS NGFWs: it identifies 3,500-plus applications by behaviour (not port/protocol), classifies risk, category, subcategory, and technology, and updates weekly. URL Filtering uses PAN-DB (80-plus categories across 40-billion-plus URLs): block malware, phishing, command-and-control, grayware, and proxy-avoidance; monitor social-networking, video-streaming, and personal-email. DNS Security blocks queries to malicious and C2 domains, detects DNS tunnelling, and uses cloud ML for newly registered malicious domains.

### ZTNA 2.0 private-access policy

A ZTNA 2.0 rule combines identity, device posture, a specific App-ID, and inspection on the allowed traffic:

```
Security Policy Rule:
  Name: Finance-SAP-Access
  Source: User Group = "Finance-Users"
  Source Device: Device Posture = "Compliant" (HIP)
  Destination: Application = sap-erp (App-ID)
  Action: Allow
  Profile: ThreatPrevention-Strict (applied to the allowed traffic)
  DLP: DLP-Financial-Data (inspect for exfiltration)
```

The continuous-trust runtime signals (device posture re-evaluated at each attempt, Cortex XDR user-risk, behavioural anomalies) are described in `architecture.md`.

## Threat-prevention profiles

Bind these into a Security Profile Group and reference the group from every allow rule. An allow rule without a bound group passes traffic uninspected; that is the single most common finding.

- **Antivirus:** action `reset-both` or `drop` on all decoders (HTTP, SMTP, IMAP, POP3, FTP, SMB). Alert-only is insufficient.
- **Anti-spyware:** enable DNS sinkhole, block botnet domains, set critical/high/medium spyware severities to `reset-both` or `drop`.
- **Vulnerability protection:** `reset-both` on critical and high signatures; informational may stay `alert`. Review custom exceptions that weaken coverage.
- **WildFire:** forward all file types (PE, APK, Mac OS X, ELF, PDF, MS Office, JAR, Flash, Linux pkg); block malicious and grayware verdicts.
- **File blocking:** block high-risk types (EXE, DLL, BAT, SCR, MSI) on the relevant protocols.
- **URL filtering:** block the high-risk categories; enable Advanced URL Filtering (licence permitting) for inline ML on unknown URLs.

Palo Alto ships Best Practice profiles for immediate deployment (block criticals and highs, DNS sinkholing, block malware/phishing/C2 categories, block malicious WildFire verdicts). Treat those as the acceptable baseline and only diverge with documented justification.

## GlobalProtect configuration

- **Connection modes:** pre-logon (connects before user auth, for machine certificates and domain join), user-logon (the primary mode), and on-demand (manual; less secure, avoid for production).
- **Internal versus external gateways:** external is Prisma Access when off-network; the optional on-prem internal gateway serves on-network users. Trusted Network Detection decides which applies.
- **Split versus full tunnel:** full tunnel (all traffic through Prisma Access) is recommended for consistent inspection. Split tunnel excludes specific routes (for example M365 Optimize ranges direct); use it deliberately, not by default.
- **HIP enforcement:** bind HIP profiles so non-compliant devices get restricted access. HIP object and match details are in `architecture.md`.
- **Always-on VPN:** enforce always-on with no user-disable, or protect the disable override with a password. Authentication should be SAML with MFA.

## SSL/TLS decryption

Threat profiles only see inside TLS if a decryption rule covers the flow. SSL Forward Proxy decrypts internet-bound traffic; endpoints must trust the forward-trust CA or they get certificate errors.

- **Coverage:** decrypt internet-bound traffic from all mobile-user and remote-network sources for full inspection. Undecrypted flows limit profiles to metadata.
- **Exclusions:** keep them minimal and documented: technical (certificate pinning, mutual TLS) and compliance (financial, healthcare categories). Certificate-pinned apps (banking, some healthcare portals) break through Forward Proxy; add them to the exclusion list with justification.
- **CA distribution:** push the forward-trust CA via MDM, GPO, or the GlobalProtect client. Verify on sample devices. Monitor CA expiry: an expired CA fails all decrypted sessions.
- **TLS version:** block or decrypt-with-alert TLS 1.0 and 1.1; permit only 1.2 and 1.3 without a finding.

## Remote networks and service connections

- **Remote networks** are branch IPsec tunnels to a compute location. Verify the IKE/IPSec crypto meets standard (AES-256-GCM preferred, minimum AES-256-CBC), IKEv2, DH group 14 minimum (19/20 preferred), and aligned SA lifetimes. Validate BGP (peer ASN, advertised prefixes, filters) or static routing (next-hop reachability, subnet accuracy). Prefer full-tunnel; if split, ensure local breakout still traverses a security policy.
- **Service connections** are the private-app return path to a data centre or VPC. Verify tunnel stability (no recent flaps), correct BGP advertisement in both directions, bandwidth headroom, QoS alignment to business priority, and primary-plus-secondary redundancy to different compute locations. A single service connection is a single point of failure.

## Inline and API CASB

- **Inline CASB** runs on traffic as it flows through the compute location. App-ID extends to SaaS context (not just `ssl` but `google-drive-upload`, `dropbox-personal`, `github-enterprise`), so policy can allow an app's read operations while blocking upload or share. Sanctioned corporate tenants get full access; unsanctioned personal instances get view-only; unknown apps fall back to URL filtering. For M365, Prisma Access can inject tenant-restriction headers to enforce corporate-tenant access.
- **API CASB (SSPM)** connects to SaaS APIs to discover sensitive data (M365 SharePoint/OneDrive, Google Drive), detect over-permissive sharing, check SaaS security configuration, and remediate (remove sharing links, move files). Example SSPM checks: M365 MFA enforced and legacy auth blocked; Salesforce session and audit settings; GitHub branch protection and secret scanning.

## ADEM operations

Enable ADEM (licence permitting) for mobile users and configure application-performance targets for the critical SaaS apps (M365, Salesforce, ServiceNow). Read the dashboard for experience-score trends, the worst-experience users (bottom 10 percent), site-level aggregation to find offices with systemic issues, and the ISP path map per affected user. ADEM's automated classification (device-side, network/ISP, PoP, or application) is what makes triage fast; the root-cause algorithm is in `architecture.md`.

## SASE posture audit

A read-only posture audit of a Prisma Access tenant. Move from tenant inventory through per-surface policy analysis to logging and visibility. Every step reads the API (see `api-and-automation.md`); nothing here mutates the fabric.

1. **Tenant and infrastructure inventory.** Confirm tenant ID and TSG ID, list active compute locations for mobile users and remote networks, record the licence edition (it gates features), and note bandwidth allocation. Enumerate mobile-user regions and remote-network sites; flag any site showing tunnel-down.
2. **Security policy (mobile users).** For each rule: flag `application: any` with `action: allow` (App-ID bypass) as Critical; flag allow rules with no Security Profile Group (uninspected); evaluate `any`-to-`any` source/destination scope; prefer `service: application-default` over `service: any`; verify deny rules for known-bad categories precede broad allows. Compute the App-ID adoption ratio (target above 80 percent named App-IDs).
3. **Security policy (remote networks).** The Step 2 checks plus: IKE/IPSec crypto strength (IKEv2, AES-256-GCM, DH group 14 or better, sane SA lifetimes), BGP or static routing correctness, split-versus-full-tunnel posture, and per-site bandwidth versus usage.
4. **Threat-prevention profile assessment.** Retrieve profile groups and individual profiles; verify antivirus actions on all decoders, anti-spyware DNS sinkhole and severity actions, vulnerability-protection critical/high actions and custom exceptions, and WildFire file-type coverage and verdict actions. Confirm every allow rule in both folders references a group containing these profiles.
5. **URL filtering and DNS security.** Verify high-risk URL categories are blocked and Advanced URL Filtering is licensed and active; review custom categories for over-broad allow-lists; confirm DNS Security is applied with DGA, tunnelling, and newly-seen-domain categories set to sinkhole or block; check CASB SaaS controls if licensed.
6. **GlobalProtect client configuration.** Check client-version currency (within the current major minus one), split-versus-full-tunnel, HIP checks (OS patch, disk encryption, antivirus currency, host firewall, certificate validity), pre-logon tunnel where required, always-on enforcement with override protection, and SAML-with-MFA authentication.
7. **Service-connection validation.** Verify each tunnel is established and stable, on-prem routes advertised correctly in both directions, bandwidth headroom, QoS alignment, and primary-plus-secondary redundancy per data centre.
8. **Decryption policy review.** Identify which flows are decrypted (SSL Forward Proxy) and which bypass; review technical and compliance exclusions for minimality and justification; validate forward-trust CA distribution and expiry; verify TLS 1.0/1.1 handling.
9. **Logging and visibility.** Confirm all log types forward to Cortex Data Lake (missing types create blind spots), verify retention meets compliance, check ADEM is enabled with targets for critical SaaS, confirm any external SIEM forwarding is functional, and check alerts on tunnel-down, licence expiry, compute-location capacity, and high threat volume.

## Threshold tables

### Security policy coverage

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| App-ID adoption (named App-IDs / total allow rules) | above 80% | 50-80% | below 50% |
| Security Profile Group binding (allow rules with a group) | above 95% | 80-95% | below 80% |
| Rules with `application: any` and `service: any` | 0 | 1-3 | above 3 |
| Disabled rules in the rulebase | below 5% | 5-15% | above 15% |
| Shadowed or unreachable rules | 0 | 1-5 | above 5 |

### Threat-prevention profile strength

| Profile type | Normal | Warning | Critical |
|---|---|---|---|
| Antivirus, action on all decoders | reset-both / drop | alert on 1-2 decoders | alert-only or default unchanged |
| Anti-spyware, critical/high action | reset-both / drop | drop on critical only | alert-only |
| Anti-spyware, DNS sinkhole | Enabled | n/a | Disabled |
| Vulnerability protection, critical/high action | reset-both | drop on critical only | alert-only |
| WildFire, file types forwarded | All types | missing 1-2 | missing above 2 or disabled |
| File blocking, high-risk types | Blocked (EXE/DLL/BAT/SCR) | partial | not configured |
| URL filtering, high-risk categories | Block (malware/phishing/C2) | alert on some | allow or not configured |
| DNS Security, threat categories | Sinkhole / block | alert on some | not configured |

### GlobalProtect client compliance

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| Client-version currency (within major minus one) | above 95% | 80-95% | below 80% |
| HIP compliance rate | above 90% | 70-90% | below 70% |
| Always-on VPN enforcement | Enabled, no override | Enabled with override password | Disabled |
| Pre-logon tunnel (if required) | Configured, active | Configured, intermittent | Not configured |
| Authentication method | SAML with MFA | SAML without MFA | LDAP / password only |

### Service-connection health

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| Tunnel status | Up, stable above 7d | Flapping (above 2 changes/24h) | Down |
| Bandwidth utilisation | below 70% | 70-90% | above 90% |
| Redundancy | Primary plus secondary active | Single, backup configured | Single, no backup |
| BGP peer state | Established, routes exchanged | Established, missing routes | Down / not configured |
| Route advertisement accuracy | All expected prefixes | Missing non-critical | Missing critical prefixes |

### Decryption coverage

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| Internet-bound traffic decrypted | above 80% of sessions | 50-80% | below 50% |
| Decryption exclusion count | below 20 | 20-50 | above 50 |
| TLS 1.0/1.1 traffic | Blocked | Decrypted with alert | Permitted without inspection |
| Forward-trust CA validity | above 90 days to expiry | 30-90 days | below 30 days or expired |

## Remediation decision trees

### Mobile-user policy gap

```
Mobile-user allow rule identified
|
+- Has a Security Profile Group?
|   +- No -> HIGH: add a group
|   |    +- Internet-bound -> full group (AV+AS+VP+URL+WF+FB)
|   |    +- On-prem via service connection -> standard group (AV+AS+VP)
|   |    +- SaaS direct -> full group + URL filtering + CASB
|   +- Yes -> check completeness
|        +- Missing WildFire -> MEDIUM: add for zero-day coverage
|        +- Missing URL filtering -> MEDIUM: add for web-threat coverage
|        +- All present -> OK
|
+- Application = any?
|   +- Yes + service = any -> CRITICAL: fully open rule
|   |    -> read Insights traffic logs for actual apps, replace with named App-IDs
|   +- Yes + specific port -> HIGH: App-ID bypass on port
|   |    -> identify apps from logs, replace with named App-IDs + application-default
|   +- Named App-IDs -> OK
|
+- Decrypted?
|   +- No -> inspection limited to metadata -> add a decryption rule for this flow
|   +- Yes -> full inspection effective
|
+- HIP-enforced?
    +- No -> evaluate adding a HIP profile for device compliance
    +- Yes -> verify HIP checks match organisational policy
```

### Remote-network posture

```
Remote-network site identified
|
+- Tunnel status?
|   +- Down -> CRITICAL: restore connectivity
|   |    - check IKE phase 1 (peer IP, PSK, proposals)
|   |    - check IKE phase 2 (proxy IDs, encryption mismatch)
|   |    - verify the on-prem firewall allows IKE/NAT-T (UDP 500/4500)
|   +- Flapping -> HIGH: investigate stability (DPD, ISP, SA-lifetime alignment)
|   +- Stable -> continue to policy audit
|
+- Encryption strength?
|   +- Below minimum (3DES, DH group 2/5) -> HIGH: upgrade to AES-256-GCM, IKEv2, DH 19/20
|   +- Meets standard -> OK
|
+- Routing correct?
|   +- BGP: missing prefixes -> verify route filters and advertisements
|   +- Static: wrong next-hop -> correct the route
|   +- Present and accurate -> OK
|
+- Split or full tunnel?
|   +- Split without local security -> HIGH: uninspected-traffic risk; migrate to full or add local stack
|   +- Full, or split with local inspection -> OK
|
+- Bandwidth adequate?
    +- above 90% -> WARNING: upgrade allocation
    +- 70-90% -> monitor trend
    +- below 70% -> OK
```

### Threat-prevention strengthening

```
Threat-prevention profile audit
|
+- Using default (best-practice) profiles?
|   +- Yes -> acceptable baseline; review for org customisation
|   +- No, custom profiles exist
|       +- Weaker than defaults -> FINDING: strengthen to match or exceed
|       +- Stronger than defaults -> OK, document the customisations
|
+- Antivirus: any decoder alert-only? -> HIGH: change to reset-both
+- Anti-spyware: DNS sinkhole disabled? -> HIGH: enable. Critical/high = alert? -> HIGH: reset-both
+- Vulnerability protection: custom exceptions reducing coverage? -> review each; remove if no longer needed
+- WildFire: file types not forwarded? -> MEDIUM: add. Verdict = alert for malicious? -> HIGH: change to drop
```

## Troubleshooting

- **API authentication (SCM versus legacy).** SCM uses OAuth 2.0 client credentials with a Service Account bound to a TSG ID; the `scope` must include `tsg_id:<your_tsg_id>` or you get a 401. An expired client secret is regenerated in SCM under Identity and Access; the account needs at least an Auditor or View-Only Administrator role to read config. Legacy Panorama uses an API key; after a tenant migrates to SCM the legacy API can return stale config, so confirm the authoritative plane first. Full flows in `api-and-automation.md`.
- **Compute-location capacity.** If mobile connections are refused or performance degrades, check compute-location utilisation via Insights or ADEM, verify mobile-user regions are distributed geographically (do not funnel everyone through one region), and review per-location bandwidth allocation (insufficient allocation throttles before true capacity).
- **GlobalProtect client compatibility.** Cloud infrastructure updates independently of the client; clients more than two major versions behind may fail to connect. macOS system-extension requirements change across OS versions; Windows clients can conflict with third-party VPN or endpoint software; MDM-pushed profiles can override portal settings. Check the compatibility matrix and align MDM with portal/gateway config.
- **Service-connection BGP flapping.** Usually a hold-timer mismatch (Prisma Access defaults to a 90-second BGP hold time; align the on-prem peer), route oscillation from the on-prem side, an MTU mismatch (reduce to 1400 or lower for IPSec overhead), or over-aggressive DPD (use a 10-second interval, retry 3, as a baseline).
- **Decryption certificate distribution.** SSL Forward Proxy needs endpoints to trust the forward-trust CA; push it via MDM, GPO, or the GlobalProtect client and verify on sample devices. Monitor CA expiry and set renewal reminders (an expired CA fails all decrypted sessions). Certificate-pinned apps fail through Forward Proxy; add them to the exclusion list with documented justification.
