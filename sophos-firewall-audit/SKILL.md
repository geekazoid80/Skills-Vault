---
name: sophos-firewall-audit
description: Use for any audit, change review, or compliance pass on a Sophos Firewall (SFOS) running on an XG / XGS hardware appliance or SF-VM, whether standalone, HA active-passive, or Sophos Central-managed. Triggers include "audit this Sophos firewall", "review SFOS rules", "Sophos firewall rule any-any", "missing IPS policy on a rule", "Security Heartbeat not required", "Synchronized Security missing heartbeat", "red heartbeat still allowed", "ATP not set to log and drop", "Active Threat Response feed disabled", "Zero-Day Protection / Sandstorm coverage", "SSL/TLS inspection rule audit", "decryption profile", "web / app filter policy gap", "Sophos NAT rule audit", "SNAT / DNAT review", "port forward exposes internal host", "Sophos admin services exposed on WAN", "local service ACL exception", "device access profile audit", "SFOS login security lockout", "password complexity disabled", "WebAdmin certificate", "portal HTTPS port", "SNMPv3 posture", "Sophos Central management status", "scheduled backup missing", "syslog category coverage", "SFOS HA checksum", "auxiliary appliance sync", "firmware / pattern currency", "compliance audit on Sophos". Covers SFOS 19.x/20.x+ on XG / XGS hardware and SF-VM, zone-based firewall rules and rule groups with linked / separate NAT, the Sophos security-services suite (IPS, antivirus / malware, web and application filter, SSL/TLS inspection, ATP (Advanced Threat Protection) plus Active Threat Response threat feeds, Zero-Day Protection / Sandstorm), Security Heartbeat and Synchronized Security posture, admin-plane exposure (device access profiles, local service ACL exception, login security, WebAdmin and portal certificates), Sophos Central management, and HA active-passive posture. Six-step audit procedure, severity table, three decision trees. Diagnose-first; read-only XML API GET / GUI / exported-config queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Authored with reference to the vendor-official sophos/sophos-firewall-audit baseline (Apache-2.0).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Sophos firewall audit

Policy-audit-driven analysis of Sophos Firewall (SFOS) rules and security posture. Unlike generic firewall checklists that only look for open ports and default-deny, this skill evaluates the SFOS-specific security architecture: zone-based firewall rules with per-rule security-service binding, Security Heartbeat and Synchronized Security enforcement (the feature that most distinguishes SFOS from other NGFW platforms), Active Threat Response and Zero-Day Protection coverage, admin-plane exposure through device access profiles and the local service ACL, and Sophos Central management posture.

Covers SFOS 19.x / 20.x and later on XG and XGS hardware appliances and SF-VM virtual instances. For Sophos Central-managed estates the audit addresses central management status, group firmware, and cloud backup; see the brief subsection below.

> **Skill marker**: When applying this skill, begin your reply with `[skill: sophos-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Sophos estate (single device, HA pair, Central-managed group, zone topology, SFOS version) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Platform and architecture**
   - Standalone, HA active-passive, or an HA pair with an auxiliary appliance?
   - XG, XGS hardware, or SF-VM? SFOS major / minor version?
   - Managed device-local, or joined to Sophos Central (group management, Central reporting)?
   - Are endpoints managed by Sophos Central Endpoint / Intercept X (Security Heartbeat available) or not?

2. **Audit driver**
   - Compliance pass, post-incident review, migration baseline, or rule cleanup?
   - Specific concerns (Security Heartbeat enforcement, SSL/TLS inspection posture, ATP, admin-plane exposure)?

3. **Evidence and access**
   - Read-only access route: GUI admin, the SFOS XML API over HTTPS (`/webconsole/APIController`), or an exported backup (`tar` config)?
   - Is the API user restricted to an allowed-IP list, and is the audit host on it?
   - Log, ATP-event, or heartbeat telemetry available?

---

## Scope and when to use

- Post-change rule review after rule additions, zone changes, or an SFOS major upgrade.
- Firewall-rule audit verifying per-rule security-service binding (IPS, AV, web / app filter, SSL/TLS inspection) and zone-pair intent.
- Security Heartbeat audit, confirming rules that should require a healthy endpoint heartbeat actually do, and that missing / red heartbeat restricts access.
- Active Threat Response and Zero-Day Protection evaluation, confirming threat feeds are set to Log and Drop and Sandstorm submission is active.
- Admin-plane exposure review: device access profiles, local service ACL exception, admin services on the WAN zone, login-security lockout and password complexity, WebAdmin and portal certificates and ports.
- Sophos Central management posture check (join status, Central reporting, cloud backup, group firmware).
- HA active-passive posture check: firmware parity, configuration checksum, auxiliary sync, monitored ports.
- Quarterly or annual compliance audit requiring per-rule justification.
- Pre-upgrade baseline before an SFOS major version change.

For mixed-vendor estate work, run `acl-rule-analysis` first for the cross-vendor methodology pass, then this skill for the SFOS deep-dive. Sibling Stage 3 specialists: `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `cisco-firewall-audit`, `checkpoint-firewall-audit`. For IPsec / SSL-VPN site-to-site and remote-access VPN deep dives see `vpn-tunnel-troubleshooting`.

## Prerequisites

- Read-only administrative access: a GUI admin account, or an SFOS API user with the audit host on its allowed-IP list, or an exported configuration backup.
- Topology knowledge: which zones exist (LAN, WAN, DMZ, VPN, WiFi, and any custom zones), their function, and expected zone-pair traffic.
- Knowledge of expected security-service assignments per rule category (internet-bound, inter-zone, intra-zone, monitoring-only).
- Whether endpoints are Sophos-managed, which determines whether Security Heartbeat enforcement is available and expected.
- Awareness of the Central management model: device-local, or Central-joined with group policy and Central reporting.
- Running configuration committed (the audit evaluates the active configuration, not staged changes).

## Procedure

Follow the six steps in order. The flow moves from admin-plane exposure through zone and rule analysis to security-service coverage, Security Heartbeat enforcement, threat-response and management posture, and finally HA.

SFOS has no rich `show running-config` CLI in the IOS sense. The primary programmatic surface is the XML API (HTTPS to `/webconsole/APIController`), a full read / write interface; this audit uses only its read-only `<Get>` requests, mirrored by the GUI and by an exported backup. A `Set` or `Remove` request mutates configuration, so an over-scoped or compromised API account can rewrite the rulebase; scope the audit account to read and restrict it by allowed-IP. Command blocks below name the API entity to read; treat every one as read-only evidence collection before any change.

### Step 1: admin-plane exposure inventory

```
API Get: LocalServiceACL        # System > Administration > Device Access
API Get: SystemServices / Admin # admin services reachable per zone
API Get: DeviceAccessProfile    # System > Profiles > Device Access
API Get: AdminSettings / Login  # login security, password complexity
API Get: AdminSettings / Certificate  # WebAdmin cert, portal ports
```

Evaluate:

- **Local service ACL exception and admin services on WAN:** HTTPS (WebAdmin), SSH, Ping, User Portal, or VPN Portal reachable from the WAN zone is an admin-plane exposure. The vendor baseline expects no admin services on WAN (`admin_services: []`); any WAN-facing management service is a High or Critical finding depending on the service.
- **Device access profiles:** confirm role separation (Administrator, Read-Only, Audit Admin, Crypto Admin, Helpdesk, Security Admin). A single super-admin profile shared by all operators defeats least-privilege and accountability.
- **Login security:** verify account lockout after N failed attempts is enabled (the vendor example ships `BlockLogin: Enable`, `UnsuccessfulAttempt: 3`), and that password complexity is enabled. The shipped example has `PasswordComplexityCheck: Disable`, so an unaudited device very often has complexity off; that is a finding.
- **WebAdmin and portal certificates and ports:** verify the WebAdmin console uses a proper CA-signed certificate (not the factory default), and record the admin HTTPS port and the User / VPN portal ports. A default self-signed WebAdmin certificate is a Medium finding.

### Step 2: zone and firewall-rule rule-by-rule analysis

```
API Get: FirewallRule           # includes rule groups and rule position
API Get: FirewallRuleGroup
API Get: NATRule                # SFOS 18.0+ separates NAT from firewall rules (17.5 embedded NAT in the rule)
```

SFOS evaluates firewall rules top-down; first match wins. Rules are organised into rule groups; the group order plus the rule order within each group determines evaluation. Evaluate against:

- **Overly permissive rules:** source zone `Any` plus destination zone `Any` plus source / destination networks `Any` plus services `Any` plus action `Accept` is a Critical finding.
- **Missing security-service binding:** an Accept rule with no IPS policy, no web / app filter, no malware scanning, and no SSL/TLS inspection passes traffic uninspected (covered in Step 3).
- **Action and logging:** confirm Drop rules at zone boundaries log traffic for visibility; a silent Drop hides reconnaissance. Confirm the default Drop rule at the bottom logs.
- **Disabled rules:** disabled rules still occupy positions and create audit confusion. Flag for cleanup.
- **NAT hygiene:** review linked NAT and standalone NAT rules for overly broad masquerade or a destination-NAT (port-forward) that exposes an internal host to the WAN without a matching restrictive firewall rule and security-service binding.
- **Schedule-bound rules:** rules active only in a time window can create off-hours gaps; verify the window is intentional.

Rules with zero hits over 90+ days are cleanup candidates (cross-check with `acl-rule-analysis` staleness bands).

### Step 3: security-service coverage audit

For each Accept rule, verify the SFOS security services are bound. Goal: zero Accept rules carrying untrusted traffic without threat inspection.

- **IPS policy:** required on Accept rules carrying untrusted traffic. The vendor baseline expects named per-zone-pair IPS policies (for example LAN TO WAN, DMZ TO LAN, WAN TO DMZ) with IPS status Enable; an internet-bound rule set to `None` is a finding.
- **Malware / antivirus scanning:** required on web and email-carrying rules. Confirm the scan engine and whether dual-engine scanning is expected.
- **Web filter and application control:** required on rules permitting HTTP / HTTPS and on rules with broad service scope.
- **SSL/TLS inspection:** without a decryption rule and profile, AV, IPS, and web filtering see only metadata on HTTPS. Review the SSL/TLS inspection rules and their decryption profiles; note where inspection is deliberately bypassed (for example privacy-sensitive categories) and confirm the bypass is intentional, not a blanket exclusion.
- **ATP (Advanced Threat Protection):** the botnet / command-and-control detector, with a global policy of `Log only` or `Log and Drop`. The vendor baseline expects `Log and Drop`. `Log only` detects but does not block command-and-control callbacks; that is a Critical finding on any production device.
- **Active Threat Response / Sophos X-Ops threat feeds:** the SFOS 20+ umbrella of MDR / NDR and X-Ops threat feeds (distinct from ATP). Confirm the feeds are enabled and actioned, not merely subscribed.
- **Zero-Day Protection (Sandstorm):** verify file submission for detonation is active on the relevant rules and protocols.

Summarise coverage: count Accept rules with full security-service binding versus partial or none, and calculate the coverage ratio.

### Step 4: Security Heartbeat and Synchronized Security posture

This is the SFOS differentiator and the step most often skipped by a generic firewall audit.

```
API Get: FirewallRule           # inspect SourceSecurityHeartbeat / DestSecurityHeartbeat
API Get: SecurityHeartbeat / Central
```

Security Heartbeat links the firewall to Sophos-managed endpoints so a rule can require a healthy endpoint before permitting traffic, and can react when an endpoint reports a red (compromised) or missing heartbeat.

- **Heartbeat availability:** confirm the firewall is registered to Sophos Central and endpoints report heartbeat. If endpoints are not Sophos-managed, record that heartbeat enforcement is unavailable (not a finding, but it removes a control).
- **Minimum-health requirement on sensitive rules:** rules that reach sensitive destinations (server VLANs, management networks) should require a minimum source heartbeat status of Green. A rule permitting a managed endpoint to a sensitive destination with no heartbeat requirement is a gap.
- **Missing heartbeat handling:** verify how rules treat a missing heartbeat. Permitting an endpoint with no heartbeat where all endpoints should be managed can mask an unmanaged or evasive host.
- **Lateral-movement containment:** a red heartbeat should restrict the endpoint's east-west reach. Confirm the intended containment is expressed in rules rather than assumed.

A managed estate that has Security Heartbeat available but does not require it on any rule is leaving its most distinctive control unused; call it out as a High-value remediation even when no single rule is individually Critical.

### Step 5: threat feeds, currency, management, logging

```
API Get: ATP / ActiveThreatResponse
API Get: Pattern / Firmware currency   # via GUI Backup & firmware / Central
API Get: Central / CentralManagement
API Get: BackupRestore / ScheduledBackup
API Get: SyslogServer + NotificationList
```

- **Pattern and firmware currency:** verify IPS / AV / other pattern updates are recent and firmware is a supported, patched build. Stale patterns leave active security services matching on outdated signatures.
- **Sophos Central management:** the vendor baseline expects Central status Enable, Central reporting Enable, and cloud backup enabled where Central is in use. A device that should be Central-managed but is drifting device-local is a management-visibility gap.
- **Scheduled backup:** verify an automated backup (local, FTP, or mail) is scheduled at a sensible frequency and its destination is controlled. No scheduled backup is a Medium finding.
- **Logging coverage:** verify syslog and Central reporting cover the security-relevant categories the baseline enumerates (ATP events, AV, content filtering, admin and authentication events, system events, Heartbeat endpoint status, IPS anomaly and signature, WAF, Zero-Day Protection). Missing admin / authentication / ATP logging blinds later investigation.
- **Notifications:** verify email or SNMP alerting is enabled for the failure classes that matter (firmware, disk exhaustion, IPS signature-update failure, AV failure, RED down, HA events).
- **SNMPv3 and time:** verify SNMPv3 (not v1 / v2c) with authentication and an authorised-hosts list, and that time / NTP and timezone are correct (audit timestamps and certificate validity depend on it).

### Step 6: HA active-passive posture

```
API Get: HA / HighAvailability
```

Check:

- **HA mode:** SFOS HA is typically active-passive; record the mode and confirm it matches design intent.
- **Firmware parity:** both appliances MUST run the same SFOS build. A mismatch causes sync failures and inconsistent enforcement after failover.
- **Configuration sync / checksum:** verify configuration is in sync between primary and auxiliary. Drift means the standby may enforce different rules.
- **Dedicated HA link and monitored ports:** verify the HA control link is on a dedicated interface and that the correct data ports are monitored so a link failure triggers failover.
- **Load balancing vs failover:** for active-active-style configurations confirm session handling is understood; unsynchronised sessions drop on failover.

## Sophos Central-managed deployments (brief)

Sophos Central is the cloud console for managing Sophos Firewall groups. Full Central operational depth (group policy design, firmware ring management, Central reporting retention, XDR integration) is outside this skill's scope. Touch points relevant to a firewall audit:

- **Audit the firewall, not just Central.** The device's running configuration plus Central group policy may diverge. Read the device configuration and compare against the intended group posture.
- **Central status is a control, not just telemetry.** A device that has silently left Central management loses group firmware, cloud backup, and centralised reporting. Verify join status.
- **Group firmware discipline.** A group firmware push that succeeds on some devices and fails on others leaves an inconsistent estate; verify per-device firmware before drawing estate-wide conclusions.
- **Security Heartbeat depends on Central.** Heartbeat enforcement (Step 4) requires the firewall and endpoints to be registered to the same Central account; confirm registration before crediting heartbeat as a control.

## Severity classification

| Finding | Severity | Rationale |
|---|---|---|
| Rule with source / destination zone `Any` + networks `Any` + services `Any` + action `Accept` | Critical | Fully open rule; no restriction on zone, network, or service. |
| Accept rule carrying untrusted traffic with no IPS, AV, web / app filter, or SSL/TLS inspection | Critical | Traffic passes without threat inspection. |
| ATP (Advanced Threat Protection) global policy set to `Log only` (not Log and Drop) | Critical | Command-and-control callbacks detected but not blocked. |
| WebAdmin, SSH, or portal reachable from the WAN zone | Critical | Management plane exposed to the internet. |
| SSL/TLS inspection absent on internet-bound rules across the estate | High | AV / IPS / web filter see only metadata on HTTPS. |
| Security Heartbeat available (managed endpoints) but required on no rule | High | The platform's distinctive control is unused; managed-endpoint health not enforced. |
| Missing / red heartbeat still permitted to sensitive destinations | High | Compromised or unmanaged endpoint retains reach; lateral movement not contained. |
| IPS policy `None` on an internet-bound or inter-zone Accept rule | High | Untrusted traffic without intrusion prevention. |
| Login security lockout disabled | High | Admin console open to credential brute force. |
| Password complexity disabled | High | Weak admin / user credentials permitted (common on unaudited SFOS). |
| HA configuration out of sync / checksum mismatch | High | Primary and auxiliary may enforce different rules. |
| HA firmware version mismatch | High | Sync and enforcement inconsistency after failover. |
| Stale IPS / AV patterns or unsupported firmware | High | Active security services matching on outdated signatures. |
| Accept rule with partial security services (for example IPS but no AV) | Medium | Some inspection but a detection gap. |
| Default self-signed WebAdmin certificate in use | Medium | Admin session trust cannot be validated; MITM risk on management. |
| No scheduled backup configured | Medium | No automated recovery point. |
| Device drifted from Sophos Central management (should be joined) | Medium | Loss of central firmware, backup, and reporting; heartbeat at risk. |
| SNMP v1 / v2c in use instead of SNMPv3 | Medium | Community-string monitoring; weak authentication. |
| Disabled rules left in production rulebase | Medium | Audit confusion; stale configuration; cleanup recommended. |
| Boundary Drop rules not logging | Medium | Reconnaissance and denied traffic invisible to investigation. |
| Rules with zero hits >90 days | Low | Unused rules; cleanup candidates. |

### Security-service coverage maturity

| Coverage ratio | Maturity | Guidance |
|---|---|---|
| >90% Accept rules with full security-service binding | Mature | Maintain; review remaining gaps quarterly. |
| 60 to 90% Accept rules with binding | Developing | Prioritise internet-bound and inter-zone rules. |
| <60% Accept rules with binding | Immature | Systematic security-service binding campaign needed. |

## Decision trees

### Security-service gap remediation

```
Accept rule without security services
├── What traffic does this rule carry?
│   ├── Internet-bound -> CRITICAL: bind IPS + AV + web/app filter + SSL/TLS inspection
│   ├── Inter-zone (DMZ, server VLAN) -> HIGH: bind IPS + AV minimum
│   ├── Intra-zone management -> MEDIUM: bind IPS; AV optional
│   └── Monitoring / logging only -> LOW: evaluate if Accept is needed at all
│
├── SSL/TLS inspection present?
│   ├── No decryption rule -> security services see only metadata on HTTPS
│   │   └── Add an SSL/TLS inspection rule + decryption profile before crediting inspection
│   ├── Decryption with broad bypass list -> confirm each bypass is intentional
│   └── Decryption active -> full efficacy on encrypted traffic
│
└── ATP (Advanced Threat Protection) global policy?
    ├── Log only -> CRITICAL: raise to Log and Drop (blocks C2, not just logs)
    └── Then confirm Active Threat Response / X-Ops threat feeds are enabled and actioned
```

### Security Heartbeat enforcement

```
Are endpoints Sophos-managed (Central-registered)?
├── No -> heartbeat unavailable; note the missing control, not a rule finding
└── Yes -> heartbeat available; audit enforcement
    ├── Rule reaches a sensitive destination (server / management VLAN)?
    │   ├── Requires minimum source heartbeat = Green -> correct
    │   └── No heartbeat requirement -> GAP: add minimum-health requirement
    │
    ├── How is a missing heartbeat treated?
    │   ├── Restricted -> correct for a fully managed estate
    │   └── Permitted -> may mask an unmanaged / evasive host; evaluate
    │
    └── Does a red heartbeat restrict east-west reach?
        ├── Yes -> lateral-movement containment expressed
        └── No -> HIGH-value remediation: contain compromised endpoints in rules
```

### Admin-plane exposure

```
Management service reachable from WAN?
├── WebAdmin (HTTPS) on WAN -> CRITICAL: restrict to LAN / VPN / allowed-IP; use VPN for remote admin
├── SSH on WAN -> CRITICAL: disable or restrict to allowed-IP
├── User / VPN Portal on WAN -> expected for remote access; verify strong auth (MFA) + current portal cert
└── Ping on WAN -> LOW: informational; often left for reachability tests
│
├── WebAdmin certificate?
│   ├── Factory self-signed -> MEDIUM: install a CA-signed certificate
│   └── CA-signed, unexpired -> correct
│
└── Login security?
    ├── Lockout disabled -> HIGH: enable block-after-N-failures
    └── Password complexity disabled -> HIGH: enable complexity + minimum length
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
SOPHOS FIREWALL (SFOS) SECURITY AUDIT REPORT
============================================
Device: [hostname] | SFOS: [version] | Platform: [XG / XGS model / SF-VM]
Deployment: [standalone / HA active-passive (+ aux)]
Management: [device-local / Sophos Central group <name>]
Endpoints managed (Heartbeat available): [yes / no]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[Patterns current; Central last sync succeeded; no in-flight change.]

ADMIN-PLANE EXPOSURE:
- Admin services on WAN: [none / list]
- Device access profiles: [role separation present / single super-admin]
- Login security: [lockout on/off | complexity on/off]
- WebAdmin certificate: [CA-signed / factory self-signed] | ports: [admin / user / VPN]

RULEBASE SUMMARY:
- Firewall rules: [n] (Accept: [n] | Drop: [n] | Disabled: [n])
- Rule groups: [n]
- Rules with full security-service binding: [n] / [Accept count]
- SSL/TLS inspection rules: [n]

SECURITY SERVICES:
- IPS policies: [list per zone-pair + status]
- ATP (Advanced Threat Protection) policy: [Log and Drop / Log only]
- Active Threat Response / X-Ops feeds: [enabled + actioned / off]
- Zero-Day Protection (Sandstorm): [active / off]
- AV / web / app filter coverage: [counts]

SECURITY HEARTBEAT:
- Available: [yes / no]
- Rules requiring minimum heartbeat: [n]
- Missing-heartbeat handling: [restricted / permitted]
- Red-heartbeat containment: [expressed / assumed]

MANAGEMENT / CURRENCY:
- Central status: [enabled / drifted device-local]
- Pattern / firmware currency: [ages / build]
- Scheduled backup: [mode / frequency / none]
- Logging categories covered: [list gaps]

HA STATUS:
- Mode: [active-passive / standalone]
- Firmware parity: [matched / mismatched + versions]
- Config sync: [in sync / drift]
- HA link + monitored ports: [ok / issue]

EVIDENCE: [XML API GET extracts / GUI screenshots / exported config attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Rule: [name / position] | Zones: [src] -> [dst] | Services: [list]
Issue: [problem] -> Recommendation: [remediation]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list, including hit-count and heartbeat delta verification]
ROLLBACK: [config backup restore ref or per-rule revert step]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **Skipping Security Heartbeat:** a generic firewall audit checks rules and services but never looks at heartbeat enforcement, missing the SFOS control that most differentiates the platform. Always run Step 4 on a managed estate.
- **Auditing Central in isolation:** the group policy in Central may not match the device's running configuration. Read the device and compare.
- **Crediting SSL/TLS inspection without checking the bypass list:** a decryption rule with a broad bypass category list inspects far less than it appears to. Enumerate the bypasses.
- **Treating `Log only` ATP (Advanced Threat Protection) as protection:** detection without Drop leaves callbacks unblocked. Confirm the ATP policy is Log and Drop.
- **Reading the API as the whole truth:** an API user restricted by allowed-IP may silently return nothing from the wrong host; confirm the audit host is authorised before concluding a setting is absent.
- **Firmware-upgrade impact:** an SFOS major upgrade can change rule or profile schema and default services. Export the configuration backup before upgrading; post-upgrade verify security-service bindings preserved, rule order intact, and HA upgraded in sequence.
- **Default WebAdmin certificate left in place:** factory self-signed certificates are common on unaudited devices; flag for any internet-adjacent management interface.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the SFOS specialist. Apply the nine-element response contract to every state-changing recommendation.
- `acl-rule-analysis` -- vendor-agnostic ACL / rulebase methodology, hit-count staleness bands, severity-pattern catalogue. Run first for cross-vendor estate work, then this skill for the SFOS deep-dive.
- `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `cisco-firewall-audit`, `checkpoint-firewall-audit` -- sibling Stage 3 specialists; sequence vendor-by-vendor when auditing a mixed estate.
- `vpn-tunnel-troubleshooting` -- IPsec / SSL-VPN site-to-site and remote-access VPN, IKE state-machine analysis. This skill stops at SFOS-side firewall rules and portal exposure.
- `network-detection-response` -- when Security Heartbeat and east-west containment overlap with NDR visibility and micro-segmentation questions.
- `bgp-analysis`, `igp-routing-analysis` -- when a firewall change risks routing convergence (large rule or SD-WAN change), pause and run those skills first.
- `secrets-hygiene` -- API credentials, the API allowed-IP user, SNMP settings, Central service credentials, and portal certificates all fall under the patterns there.
- `completion-gate` Layer 3 -- every state-changing change requires fresh post-check evidence (configuration backup ref recorded, hit-count and heartbeat deltas confirmed, pattern currency re-verified) before claiming "rule deployed".
- `plan-time-tooling` -- every state-changing audit recommendation fires `engineering:deploy-checklist` at plan time.
- `systematic-debugging` -- Phase 1 boundary evidence (which rule, which zone pair, which service binding, which heartbeat requirement) before any change.
- `oncall-runbooks` -- incident classification when audit findings overlap with active incidents.

## Red flags (about-to-act warnings)

- About to enable SSL/TLS inspection on a zone pair without distributing the decryption CA to endpoints (will break TLS for users).
- About to require a minimum Security Heartbeat on a rule before confirming the affected endpoints are Sophos-managed (will block legitimate unmanaged hosts).
- About to open WebAdmin or SSH on the WAN zone "temporarily" for remote administration; use the VPN portal instead.
- About to delete a rule with a non-zero hit count without identifying the traffic source.
- About to upgrade an HA pair without the correct sequence, or with a firmware mismatch left in place.
- About to switch ATP (Advanced Threat Protection) to Log only to "reduce noise" (this removes the block).
- About to add an `Any Any Accept` rule at the top of a group as a temporary fix.
- About to disable login-security lockout or password complexity to speed up admin access.
- About to trust an API GET that returned empty without confirming the audit host is on the API user's allowed-IP list.
- About to skip the pattern / firmware currency check because the device "feels fine".

## Bottom line

Audit the SFOS architecture, not just the rules. The architecture is zone-based rules plus per-rule security-service binding plus Security Heartbeat enforcement plus Active Threat Response and Zero-Day Protection plus admin-plane exposure, with Sophos Central layering group policy and cloud backup on top. Diagnose-first via read-only XML API GET, GUI, or exported backup; audit BOTH the device and its Central posture; map every state-changing recommendation onto the nine-element response contract. Severity rankings drive remediation cadence (CRITICAL 30 d, HIGH 90 d, clean 180 d). The two audit smells most specific to Sophos are ATP (Advanced Threat Protection) left on Log only and Security Heartbeat available but unused; check both first.
