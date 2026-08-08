# ZIA and ZPA operations, plus the audit lens

The operational configuration depth for ZIA (internet access), ZPA (private access), ZDX (experience monitoring), and the ZCC endpoint agent, followed by the read-only policy-audit lens with threshold guidance. Platform mechanics are in `architecture.md`; the API surface is in `api-and-automation.md`.

## ZIA: Zscaler Internet Access

### Traffic flows

**Remote user with ZCC:**
```
Endpoint -> ZCC intercepts -> encrypted Z-Tunnel to nearest ZIA node
-> ZIA processing (URL filter, SSL inspect, malware scan, DLP, CASB)
-> internet / SaaS destination
```

**Office with GRE/IPsec tunnel:**
```
Office devices -> default route to gateway -> GRE/IPsec tunnel to ZIA node
-> ZIA processing -> internet / SaaS destination
```

### SSL inspection

ZIA intercepts HTTPS for inspection; without it, no downstream engine can read encrypted payloads. Configuration lives in Policy -> SSL Inspection.

- **Bypass categories.** Zscaler ships pre-built bypass categories for financial services, healthcare, government, privacy-sensitive sites, and certificate-pinned applications. Add your own bypasses by URL category, specific domain/URL, or destination IP, scoped to all users or specific groups.
- **Custom CA.** Organisations can inspect with their own internal CA instead of Zscaler's; the custom CA certificate must be trusted by every endpoint OS.
- **The trade-off.** Every bypass is a blind spot for URL filtering, malware, DLP, and CASB simultaneously. Bypass only where compliance or certificate pinning requires it, and document each exception.

### URL filtering

- **Categories.** Zscaler maintains 200+ URL categories, updated in real time by ThreatLabZ.
- **Policy structure.** Priority-ordered rules; each is a condition (URL category, user/group, time) mapped to an action (allow, block, caution, override). `Caution` shows a warning page but lets the user continue.
- **Custom categories.** Built from specific domains/URLs, URL keywords, or IP ranges.
- **Overrides.** Explicit allow/deny lists take precedence over category classification.
- **Block-page customisation.** Custom HTML for the block page, including an IT contact and a ticket link.

### Cloud firewall

- **L4 firewall.** TCP/UDP port and protocol rules; blocks outbound non-standard ports.
- **L7 firewall.** Application-aware; block a specific application even when it tunnels over an allowed port (for example allow HTTPS but block BitTorrent over it).
- **DNS control.** Blocks malicious domains at resolution time.
- **IPS.** Intrusion prevention with Zscaler-managed rules.

Rules follow the familiar NGFW shape: source user/group -> destination IP/domain/country -> application -> protocol -> action. A tight outbound policy (allow only known protocols, block direct-IP destinations, block suspicious geographies) is an effective malware-C2 control.

### Cloud sandbox

Unknown files are detonated in the cloud before delivery. Supported types include Office documents, PDFs, executables, scripts, archives, and mobile packages.

- **Tiers.** Advanced Threat Protection (signature plus heuristics, included in standard ZIA) and Advanced Cloud Sandbox (full behavioural detonation, a premium add-on).
- **Policy.** Submit all unknown files or only suspicious ones; on a malicious verdict block the download; on an inconclusive verdict allow-and-log or hold-and-wait.

### CASB (inline)

Applied automatically whenever ZIA inspects SaaS traffic.

- **Shadow-IT discovery.** ZIA logs all cloud-app usage and scores each app for business, data, and regulatory risk, broken down by department and trended over time.
- **Tenant restrictions.** Enforce corporate-tenant-only access to M365 by adding the tenant-restriction header to that traffic.
- **Application controls.** Per-app and per-activity controls (for example allow upload to corporate storage, block upload to personal storage; allow "view" but block "download"), with predefined controls for hundreds of popular SaaS apps.

### DLP

- **Engines.** Pattern-based (credit cards, national IDs, health data), Exact Data Match (hash matching against indexed sensitive data), Document Fingerprinting (match against template documents), and ML classification (source code, financial data, M&A documents).
- **Policy.** Define the engine (what to detect), then a rule (engine plus location plus action), across the web, email (needs integration), and endpoint channels.
- **Actions.** Allow-with-log, block, allow-after-justification (the user enters a reason), quarantine for admin review, or encrypt.

## ZPA: Zscaler Private Access

### Application segments and server groups

- **Server group.** A set of App Connectors that can reach a set of applications.
- **Application segment.** Defines the reachable applications: hostnames/IPs, port/protocol pairs, and the domain names the App Connectors resolve for private names. Associated with one or more server groups.

```
Name: Internal HR System
Hostnames: hrapp.internal.corp.example
Ports: 443/TCP
Server Group: DataCenter-Connectors
```

Keep segments narrow: a wildcard domain exposes every subdomain and a `1-65535` port range exposes every service on the host. Both are usually a shortcut for incomplete application discovery, not a deliberate choice.

### Access policies

An access policy answers "who can reach which application, under what conditions", evaluated top-down.

```
Rule: Finance Team -> SAP access
Criteria:
  - User: group = "Finance"
  - Device: posture = compliant (enrolled, EDR active)
  - Conditions: business hours (optional)
Action: Allow
Application: SAP-Production (application segment)
```

- **Device posture.** ZPA integrates with CrowdStrike, Microsoft Defender, Carbon Black, Jamf, and Intune to check EDR presence, patch level, disk encryption, and MDM enrolment as part of the access decision.
- **Identity condition.** Every policy should carry an explicit identity condition (SCIM group or IdP attribute). A policy with none is default-allow.

### Browser Access (agentless)

For users who cannot install ZCC (contractors, BYOD), Browser Access provides HTML5 web access to internal applications through a Zscaler-hosted portal, with no agent. It offers less device-posture visibility, so reserve it for lower-sensitivity applications.

### App Connector deployment

An App Connector is a VM in the same network segment as the private applications. It supports VMware, Hyper-V, AWS, Azure, GCP, Docker, and bare-metal Linux (Amazon Linux 2, RHEL/CentOS, Ubuntu, Debian).

```bash
# AWS example: launch from the Zscaler AMI (m5.large minimum for production)
# Provisioning key is issued in the ZPA Admin Portal; treat it as a secret.
export PROVISIONING_KEY="$ZPA_PROVISIONING_KEY"      # from the secret store, never inline
/opt/zscaler/bin/zpa-connector register --key "$PROVISIONING_KEY"
/opt/zscaler/bin/zpa-connector status
```

- Security group: outbound 443/TCP to the ZPA cloud, egress only; no inbound rules.
- Route the private application subnets through the connector.

## ZDX: operations and troubleshooting

ZDX turns a subjective "the app is slow" into an attributable finding. The pattern is to walk the Experience Score from the device outward.

**"Microsoft Teams is slow" (single user):**
1. Device CPU/RAM: normal.
2. Wi-Fi signal: weak.
3. Path to the ZIA node: high latency.
4. Conclusion: the user is on a crowded Wi-Fi channel; the fix is local, not the platform.

**"Salesforce is slow for many London users":**
1. Experience Score trend: dropped at a specific time.
2. Path data: ISP latency spike for one provider.
3. Zscaler point-of-presence health: normal.
4. Path from the point of presence to Salesforce: normal.
5. Conclusion: an ISP-level issue affecting that provider's customers; the fix is with the ISP.

## ZCC: tunnel modes and split tunnel

- **ZIA tunnel mode.** Z-Tunnel 1.0 (HTTP CONNECT proxy, HTTP proxied and non-HTTP bypassed), Z-Tunnel 2.0 (default, all traffic over DTLS), or packet-filter mode (route all IP traffic, needed for non-TCP such as ICMP and UDP).
- **ZPA tunnel mode.** Separate from ZIA; ZCC runs both tunnels at once, ZIA for internet and ZPA for private apps.
- **Split tunnel (recommended).** Route only corporate traffic through Zscaler and send low-risk SaaS direct (for example the Microsoft 365 Optimize endpoints per Microsoft's guidance), which cuts processing load and latency. Configured via PAC file or forwarding profile.
- **Full tunnel.** All traffic through Zscaler: highest security, most latency.
- **Bypass list.** Specific IP ranges or domains that skip ZCC entirely (VoIP, internal split DNS). Anything bypassed is uninspected by design.

## The read-only policy-audit lens

When the task is to audit rather than change, work read-only (never activate a pending policy push) and move ZIA policy first, then ZPA policy and connectors, then the shared identity and posture layer. The recurring findings and rough thresholds:

### ZIA URL filtering
- **Rule ordering.** A broad allow above a specific block is a bypass; identify order that permits what a later rule intends to deny.
- **Over-permissive allow.** Rules allowing all categories, or unclassified buckets like `Miscellaneous`/`Other`, without justification.
- **High-risk categories allowed.** `Anonymizer`, `Peer-to-Peer`, `Malware` allowed against the acceptable-use policy: high priority.
- **Caution actions.** Click-through `Caution` on non-business categories: convert to block.
- **Scope.** Rules scoped to Any location and Any department apply globally; confirm that is intentional.

### ZIA SSL inspection
- **Do-not-inspect rules.** Each is a blind spot; quantify what share of categories is excluded.
- **Both allowed and uninspected.** A category that is allowed and also SSL-bypassed is the highest-risk finding: content-blind egress. Add inspection or block the category.
- **Certificate coverage.** Inspection needs the Zscaler (or custom) root CA on every endpoint; track deployment coverage and exceptions.
- **Location-level disable.** A whole site with inspection off is critical.

### ZIA cloud firewall
- **Any-any permit.** Flag as critical unless it is the explicit default-deny at the bottom; verify the action is a block/drop.
- **Shadowed rules.** A rule fully covered by an earlier, broader rule never fires and confuses the rulebase.
- **Logging.** Rules with logging disabled create investigation blind spots.
- **Granularity.** Prefer specific IP/service groups over Any/Any source and destination; narrow broad network services (avoid `1-65535`).

### ZIA DLP
- **Engine activation.** A disabled engine protects nothing.
- **Dictionary coverage.** Confirm dictionaries cover the regulated data types the compliance framework requires (PCI card numbers, HIPAA identifiers, GDPR personal data).
- **Bypass gaps.** An SSL-bypassed category is also a DLP blind spot; cross-check.

### ZPA application segments
- **Wildcard domains.** `*.example.com` exposes every subdomain; confirm intent or narrow to specific FQDNs.
- **Large port ranges.** Ranges over ~100 ports (or `1-65535`) grant access to every service; pin to the application ports.
- **Segment-group assignment.** Every segment should belong to a segment group for governable policy.
- **Protocol scope.** Both TCP and UDP where only one is needed widens the surface.

### ZPA access policies
- **Default-allow.** A policy with no identity condition grants unrestricted access: critical. Add a SCIM group or IdP attribute condition.
- **Missing posture.** A policy with no posture profile lets unmanaged devices reach internal apps; scale the required posture to the application's sensitivity.
- **Ordering.** Top-down like the firewall; a broad allow above a restrictive rule bypasses it.

### ZPA connector health
- **Status.** Flag any connector not enabled (disabled or error).
- **Version drift.** More than two versions behind the current release risks missing patches.
- **Redundancy.** A connector group with a single connector is a single point of failure; deploy a second.
- **Provisioning keys.** Flag expired keys, keys at max usage, and unused keys that suggest stalled deployments.

### Shared identity and posture
- **IdP.** Active status, current SAML/OIDC metadata, SCIM last-sync within about 24 hours, and unexpired signing certificates.
- **Posture profiles.** Device-trust (MDM/UEM enrolment or certificate), minimum OS version, disk encryption, and endpoint-security status; cross-reference against the access policies to find any that require no posture.

### Rough threshold guidance

| Area | Normal | Warning | Critical |
|---|---|---|---|
| SSL: categories both allowed and uninspected | 0 | 1 to 3 | more than 3 |
| SSL: locations with inspection disabled | 0 | 1 to 2 | more than 2 |
| Firewall: any-any permit rules (non-default) | 0 | 1 | more than 1 |
| Firewall: shadowed / unreachable rules | 0 | 1 to 5 | more than 5 |
| ZPA: access policies requiring a posture profile | over 90% | 60 to 90% | under 60% |
| ZPA: access policies with default-allow | 0 | 1 | more than 1 |
| ZPA: connector groups with a single connector | 0 | 1 to 2 | more than 2 |
| ZPA: connector version drift (versions behind) | 0 to 1 | 2 | more than 2 |

Prioritise in this order: SSL inspection blind spots and cloud-firewall any-any first (content-blind or unrestricted egress), then ZPA default-allow and missing-posture policies (unverified access to internal apps), then over-broad segments and connector redundancy, then rule-hygiene cleanup (shadowed and disabled rules) during a maintenance window.
