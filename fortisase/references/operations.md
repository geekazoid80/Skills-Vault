# FortiSASE operations and security-posture audit

The read-only audit flow for a FortiSASE tenant, the threshold tables that turn observations into severities, decision trees for prioritising gaps, a report template, and the troubleshooting recipes for the recurring operational faults. The audit is read-only: query, evaluate, report, recommend. It never mutates tenant configuration.

## The audit flow

Run the steps in order; each builds on the prior findings. All endpoints below are read-only (`GET`); auth and the full endpoint reference are in `api-and-automation.md`.

### Step 1: Tenant and topology discovery

Authenticate to the FortiSASE API via FortiCloud IAM, then enumerate the tenant: PoPs and their status, thin edge sites and registration state, licensed vs connected endpoints, and license expiration. Record tenant name and region, PoP locations and health, thin edge count and status, endpoint utilisation, and license dates. Flag any PoP in a degraded state and license utilisation above 90% (approaching the endpoint limit prevents new connections).

### Step 2: Secure Web Gateway policy audit

Retrieve web filter, application control, DNS filter, antivirus, IPS, and (if licensed) inline CASB profiles. For each web filter profile, check that all FortiGuard URL categories have an explicit action, Safe Search enforcement where required, and content filtering. For application control, check high-risk categories (P2P, proxy, remote-access, botnet) are blocked, per-application overrides do not contradict category policy, and unknown-application handling is deliberate. Verify AV and IPS profiles are bound to the SWG firewall policies: an SWG policy without AV and IPS binding passes internet-bound traffic uninspected for malware and exploits, a Critical finding.

### Step 3: ZTNA access proxy assessment

Retrieve the access proxy rules, virtual host (server) definitions, device categories (posture tags), and user groups. For each rule check: posture-tag enforcement (rules without a tag admit non-compliant devices, High); identity-based access (user or group, not source IP alone); application definitions (correct backends, no overly broad or wildcard definitions); rule ordering (specific before broad; identify shadow rules that never match); authentication method (SAML/LDAP/RADIUS integration, MFA for sensitive apps). Calculate the posture-tag coverage ratio (rules with a tag requirement over total); below 80% signals insufficient device-compliance enforcement.

### Step 4: Firewall (FWaaS) policy review

Audit the firewall policies governing both SWG and ZTNA flows. Flag overly permissive policies (`srcaddr all`, `dstaddr all`, `service ALL`, `action accept`) as Critical. Verify every accept policy binds AV, web filter, application control, IPS, and an SSL inspection profile, and calculate the binding coverage. Detect shadow rules (a broad earlier rule masking a later one), disabled policies (audit clutter), logging gaps (`logtraffic disable` on security-relevant policies), and schedule-based policies that open windows during off-schedule periods.

### Step 5: Thin edge FortiGate integration

For each thin edge: verify registration and tunnel state (a down tunnel means the site is unprotected, Critical); review SD-WAN SLA definitions and confirm failover does not bypass inspection; compare the edge local firewall policy against the cloud policy for drift; check firmware against the recommended target (more than one major version behind is High); and verify dual-tunnel redundancy to a second PoP (single-tunnel is a single point of failure).

### Step 6: SSL/SSH inspection configuration

Retrieve the SSL/SSH inspection profiles and CA certificates. Identify which policies use deep-inspection vs certificate-inspection (certificate-only cannot inspect the encrypted payload). Review exemption lists for overly broad entries. Confirm the FortiSASE inspection CA is distributed to all managed endpoints (without it, endpoints hit TLS errors or bypass inspection). Check protocol coverage (HTTPS, SMTPS, IMAPS, POP3S, FTPS) and the PoP capacity headroom for deep inspection.

### Step 7: FortiClient endpoint compliance

Retrieve EMS status, endpoint compliance summary, ZTNA tag assignments, and endpoint groups. Verify EMS is connected and syncing (last sync under 15 minutes). Review the compliance rules per group (OS patch level, AV status, vulnerability scan, endpoint firewall, disk encryption). Confirm compliance evaluation results in correct ZTNA tag assignment, so non-compliant endpoints receive a tag that restricts ZTNA access; flag missing or stale tags. Verify on-fabric vs off-fabric detection. Calculate the endpoint compliance percentage; below 85% indicates systemic issues needing a remediation campaign.

### Step 8: FortiGuard service validation

Verify subscription status and signature currency per service against the cadence below. Check FortiGuard server connectivity from each PoP (degraded connectivity forces cached-data fallback and reduces detection of newly categorised threats). Confirm automatic updates are working; check for update failures in the last 7 days and identify the root cause (connectivity, license, service outage).

### Step 9: Logging and analytics

Verify FortiAnalyzer Cloud (or on-prem FortiAnalyzer) is connected and receiving logs from every component. Confirm all log types are forwarded (traffic, UTM, event, ZTNA); a missing type is an investigation blind spot. Verify retention meets the compliance requirement. Review alert policies for coverage of malware detection, IPS critical severity, ZTNA authentication failures, thin edge tunnel down, FortiGuard update failures, and endpoint compliance drops.

## Threshold tables

### SWG policy coverage

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| URL categories with explicit action | >90% | 70-90% | <70% |
| AV profile bound to SWG policies | 100% | 80-99% | <80% |
| IPS sensor bound to SWG policies | 100% | 80-99% | <80% |
| Application control profile bound | >95% | 75-95% | <75% |
| High-risk app categories blocked | 100% | 80-99% | <80% |
| SSL deep inspection on internet policies | >80% | 50-80% | <50% |

### ZTNA tag enforcement

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| ZTNA rules with posture-tag requirement | >90% | 70-90% | <70% |
| Endpoint posture-tag compliance rate | >85% | 65-85% | <65% |
| ZTNA rules with user/group restriction | 100% | 80-99% | <80% |
| MFA enforcement on sensitive apps | 100% | 80-99% | <80% |
| ZTNA tag propagation latency | <5 min | 5-15 min | >15 min |

### Thin edge health

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| Tunnel status | Up (all edges) | 1-2 edges degraded | Any edge down |
| Firmware currency | Current or N-1 | N-2 | >N-2 or EOL |
| SD-WAN SLA compliance | >95% | 80-95% | <80% |
| Dual-tunnel redundancy | All edges dual | >80% dual | <80% dual |
| Policy consistency (cloud vs edge) | 100% match | Minor drift | Major drift |

### FortiClient compliance

| Metric | Normal | Warning | Critical |
|---|---|---|---|
| Endpoints compliant (all rules) | >90% | 75-90% | <75% |
| OS patch currency (<30 days) | >90% | 70-90% | <70% |
| AV signatures current (<24h) | >95% | 80-95% | <80% |
| Vulnerability scan (no critical) | >90% | 75-90% | <75% |
| EMS sync status | Connected, <15min | Connected, 15-60min | Disconnected or >60min |

### FortiGuard service currency

| Service | Expected status | Maximum signature age |
|---|---|---|
| FortiGuard Antivirus | Active, licensed | 24 hours |
| FortiGuard IPS | Active, licensed | 7 days |
| FortiGuard Web Filter | Active, licensed | 7 days |
| FortiGuard Application Control | Active, licensed | 7 days |
| FortiGuard DNS Filter | Active, licensed | 7 days |
| FortiGuard Inline CASB | Active (if licensed) | 7 days |
| FortiGuard DLP | Active (if licensed) | 7 days |

## Decision trees

### SWG / FWaaS policy gap prioritisation

```
SWG policy gap identified
├── Missing AV/IPS profile on an accept policy?
│   ├── Policy carries internet-bound traffic?
│   │   ├── Yes -> CRITICAL: bind AV + IPS now; verify SSL deep inspection is active
│   │   └── No (internal SaaS only) -> HIGH: bind AV + IPS
│   └── Policy actively used (hit count > 0)?
│       ├── Yes -> prioritise remediation
│       └── No -> evaluate for removal
├── URL category not explicitly actioned?
│   ├── High-risk (malware, phishing, C2) -> CRITICAL: set to block now
│   └── Business-relevant -> allow with logging; otherwise block or monitor
├── Application control gap?
│   ├── High-risk categories (P2P, proxy, botnet) not blocked -> CRITICAL: block them
│   ├── Unknown applications allowed -> HIGH: set unknown to monitor or block
│   └── Override contradicts category policy -> MEDIUM: align override
└── SSL inspection gap?
    ├── No deep inspection on internet policies -> HIGH: deploy deep inspection; distribute CA
    ├── Excessive exemptions -> MEDIUM: justify each exemption
    └── CA not deployed to all endpoints -> HIGH: deploy via EMS or MDM
```

### ZTNA access policy remediation

```
ZTNA access policy finding
├── Rule missing a posture-tag requirement?
│   ├── High-sensitivity app (financial, PII, admin console) -> CRITICAL: add tags now
│   │   (require OS-patched + AV-current + compliant; block non-compliant with redirect to remediation)
│   ├── Medium (internal tools) -> HIGH: add tags within 7 days
│   └── Low (public info) -> MEDIUM: add tags within 30 days
│   Interim: enable enhanced logging on untagged rules; watch for non-compliant access
├── Rule missing user/group restriction?
│   ├── Source-IP only -> HIGH: migrate to identity-based (SAML/LDAP), scope by group
│   └── Allows all users -> MEDIUM: scope to required groups
├── Shadow rule detected?
│   ├── Shadow more restrictive than the matching rule -> reorder: restrictive above broad
│   └── Shadow redundant -> remove; document in the change log
└── Authentication insufficient?
    ├── No MFA on sensitive apps -> HIGH: enable MFA via the SAML IdP
    └── Single-factor only -> MEDIUM: plan MFA rollout
```

### Thin edge posture improvement

```
Thin edge finding
├── Tunnel down?
│   ├── Single edge -> check WAN link, IPsec/SSL config, PoP availability
│   └── Multiple edges -> PoP outage (check status page) or failed config push (check FortiCloud sync)
│   -> CRITICAL: restore tunnel; the site is unprotected
├── Firmware outdated?
│   ├── N-1 -> LOW: schedule in a maintenance window
│   ├── N-2 -> MEDIUM: upgrade within 30 days
│   └── >N-2 or EOL -> HIGH (CRITICAL if a known CVE is being exploited): urgent upgrade
├── Policy inconsistency (cloud vs edge)?
│   ├── Local rules override cloud policy -> HIGH: align or remove
│   ├── Edge missing cloud security profiles -> MEDIUM: push consistent profiles
│   └── Edge allows traffic outside cloud policy -> HIGH: restrict; enforce cloud-first
└── No dual-tunnel redundancy?
    ├── Business-critical site -> HIGH: add a secondary tunnel to an alternate PoP
    └── Non-critical -> MEDIUM: plan dual-tunnel
```

## Report template

```
FORTISASE SECURITY POSTURE AUDIT REPORT
Tenant: [name]   Region: [primary]   Service tier: [license level]
Audit date: [timestamp]   Performed by: [operator/agent]

TENANT TOPOLOGY
- PoPs: [count] ([list with status]); degraded: [count or none]
- Thin edge sites: [registered]/[total]
- Licensed endpoints: [used]/[total] ([utilisation %]); license expiry: [date]

SWG / FWaaS
- Web filter profiles: [count]; URL categories explicit: [n]/[total] ([%])
- Application control profiles: [count]; high-risk blocked: [yes/no + gaps]
- Policies with full UTM binding (AV+IPS+WebFilter+AppCtrl): [n]/[total] ([%])
- SSL deep inspection coverage: [n]/[internet-bound total] ([%])
- Inline CASB: [yes/no]

ZTNA
- Access proxy rules: [count]; with posture tag: [n]/[total] ([%])
- With user/group restriction: [n]/[total] ([%]); MFA on sensitive: [n]/[total] ([%])
- Shadow rules: [count]; auth sources: [SAML/LDAP/RADIUS + status]

THIN EDGE
- Tunnels up: [n]/[total]; down: [list]; dual-tunnel: [n]/[total] ([%])
- Firmware current (N-1): [n]/[total]; outdated (>N-2/EOL): [list + versions]
- SD-WAN SLA compliance: [%]; policy consistency issues: [count + sites]

ENDPOINT COMPLIANCE
- Managed endpoints: [count]; EMS sync: [status + last sync]
- Fully compliant: [n]/[total] ([%])
- Non-compliant: OS overdue [n], AV stale [n], critical vulns [n], firewall off [n]
- ZTNA tags correct: [n]/[total] ([%]); on/off-fabric issues: [count or none]

FORTIGUARD
- AV/IPS/WebFilter/AppCtrl/DNS: [active or expired + signature version + age] each
- Inline CASB / DLP: [active/expired/not licensed]
- Connectivity: [all PoPs connected / degraded]; update failures (7d): [count or none]

LOGGING
- FortiAnalyzer Cloud: [connected/disconnected]; log types: [traffic/UTM/event/ZTNA]
- Retention: [days]; alert policies: [count]; missing coverage: [list]

FINDINGS (per finding: severity, component, detail, impact, recommendation)
REMEDIATION ROADMAP
- Immediate (0-24h): [Critical]   Short-term (1-7d): [High]
- Medium-term (7-30d): [Medium]   Long-term (30-90d): [Low + improvements]
NEXT AUDIT: [Critical present: 30d | High only: 90d | clean: 180d]
```

## Troubleshooting

### FortiCloud API authentication failures

FortiCloud bearer tokens have a limited TTL (typically 1 hour); implement refresh for long-running audits. The API user needs read-only IAM scope on FortiSASE resources: insufficient permissions return `403` on resource endpoints even when authentication succeeds, so verify role assignments rather than re-checking credentials. If MFA is enforced on the account, API auth may need a service account or an API-specific account. FortiCloud enforces rate limits (roughly 60 requests/minute); apply exponential backoff on `429` and respect `Retry-After`.

### Thin edge tunnel flapping

Tunnels that repeatedly establish and drop point at the underlay. Check the WAN interface for errors, packet loss, or saturation. Suspect MTU: IPsec adds overhead, so a path MTU that is too small fragments packets and destabilises the tunnel (set the tunnel MTU to 1400 or clear the DF bit). Behind NAT, thin edges need NAT-T (UDP 4500) permitted and a NAT session timeout longer than the IPsec DPD interval. Aggressive DPD (5 seconds) on high-latency links causes false positives; use 30 seconds with a retry count of 3.

### FortiClient EMS sync delays

Verify EMS can reach the FortiSASE cloud endpoints on 443; check the EMS host firewall and any upstream proxy. Large endpoint populations (over 10,000) can delay a full sync, so confirm incremental sync is working. Ensure the EMS version is compatible with the current FortiSASE release; a mismatch causes sync failures or partial data. Expired or untrusted TLS certificates on the EMS-to-FortiSASE path cause silent sync failures.

### FortiGuard connectivity behind a proxy

If the environment requires an outbound proxy, configure FortiGuard to use it for updates, with proxy authentication if required. FortiGuard needs DNS resolution for its update and rating domains, so verify DNS on all PoPs and thin edges. It uses HTTPS (443) and may use UDP for rating queries; ensure the ports are permitted. FortiGuard uses anycast and regional servers, so confirm the nearest server is reachable and not blocked by geo-IP restrictions.

### ZTNA tag propagation delays

Tags flow FortiClient -> EMS -> FortiSASE, and each hop adds latency; normal propagation is under 5 minutes, and beyond 15 minutes indicates a pipeline problem. Check the EMS-to-FortiSASE sync interval (a long default is too slow for time-sensitive enforcement), the PoP-level tag cache TTL, and the FortiClient compliance-evaluation frequency (default every 5 minutes; increasing it shortens the gap between a compliance change and the tag update).

### PoP capacity and performance

Too many endpoints on one PoP degrades performance; enable PoP load balancing or geo-steering to distribute them. Deep inspection is CPU-heavy per session, so on a constrained PoP evaluate exemptions for high-bandwidth, low-risk, already-secured SaaS. Time-zone traffic spikes (start of business) can saturate a PoP; review capacity planning and pre-scaling where supported. Some regions have limited PoP presence, so endpoints there see higher latency; match FortiSASE regional coverage to the endpoint geographic distribution.
