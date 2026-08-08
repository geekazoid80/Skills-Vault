---
name: wireless-security-audit
description: "Use for any wireless LAN security audit, posture review, or compliance pass across Cisco WLC (AireOS) and Catalyst 9800 (IOS-XE-WLC), Aruba (AOS Mobility Controller and AOS-CX wireless gateway), Cisco Meraki, and Juniper Mist. Triggers include \"wireless security audit\", \"WLAN security review\", \"WPA3 posture\", \"WPA2 to WPA3 migration\", \"802.1X audit\", \"EAP-TLS validation\", \"PEAP audit\", \"rogue AP triage\", \"evil twin detection\", \"WIDS / WIPS posture\", \"Protected Management Frames\", \"PMF audit\", \"RADIUS reachability for wireless\", \"RADIUS certificate expiry\", \"guest SSID isolation\", \"captive portal posture\", \"SSID inventory\", \"VLAN to SSID mapping\", \"wireless segmentation review\", \"Mist SSID security review\", \"Catalyst 9800 audit\", \"AireOS to C9800 migration\", \"Meraki Air Marshal audit\", \"Aruba ClearPass posture\", \"WPA3 transition mode sunset\", \"WIPS containment legality\", \"wireless DoS attack detection\", \"wireless RF security\", \"co-channel interference review\", \"perimeter signal leakage\", \"PCI DSS 4.0 wireless\", \"HIPAA wireless audit\", \"WLAN compliance review\". Six-step audit procedure (SSID policy inventory, authentication and encryption audit, 802.1X / RADIUS validation, rogue AP assessment, RF security posture review, report). Three threshold tables (Encryption Strength Tiers from WEP through WPA3-Enterprise 192-bit, Rogue AP Severity Classification with wired-connected and evil-twin tiers, RF Signal Thresholds for SNR and channel utilisation). Two decision trees (SSID Security Triage with encryption-mode routing, Authentication Method Upgrade Path from Open through WPA3-Enterprise). Six-platform OS-honest vendor tags: `[AireOS]` (Cisco legacy WLC: 5520 / 8540 / 3504 / vWLC), `[IOS-XE-WLC]` (Catalyst 9800 family: C9800-CL / -40 / -80 / -L), `[Aruba AOS]` (Mobility Controller / Virtual MC; AOS 8.x), `[Aruba AOS-CX]` (CX switches as wireless gateways; partial coverage; many features still require AOS Mobility Controller), `[Meraki]` (Dashboard API only; cloud-managed), `[Mist]` (Juniper Mist Cloud API). Diagnose-first; read-only `show` / GUI / API queries throughout; no state-changing commands. Maps onto `multi-vendor-network-ops` nine-element response contract for any production-impacting recommendation. Pairs with `incident-response-network` for rogue-AP IR handoff and post-incident SSID posture review; `acl-rule-analysis` for wired-side enforcement of wireless segmentation (VLAN-to-SSID mapping, inter-VLAN ACL between wireless and corporate); `secrets-hygiene` for RADIUS shared-secret and API-token discipline; `incident-response-lifecycle` for NIST 800-61 process wrapping when a wireless incident is formally declared. Out of scope: general WLAN troubleshooting that is not security-scoped (use `incident-response-network` or vendor docs); client-side supplicant configuration (vendor docs); wired ACL audits (use `acl-rule-analysis`); consumer-grade WLAN. Customised from vahagn-madatyan/netsec-skills-suite/wireless-security-audit (Apache-2.0); six-platform OS-honest tag split applied (upstream covered only Cisco WLC AireOS / Aruba AOS / Meraki); `cli-reference.md` kept and extended with vault-authored columns for `[IOS-XE-WLC]`, `[Aruba AOS-CX]`, `[Mist]`; `security-standards.md` kept with em-dash and US-to-UK spelling cleanup."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Wireless LAN security audit

Policy-audit-driven analysis of wireless network security posture across enterprise wireless controllers. Evaluates SSID configuration policy, authentication and encryption strength, 802.1X / RADIUS validation, rogue AP exposure, and RF security: the five domains that determine wireless network risk. The sixth step compiles findings into a severity-classified report.

Where platforms diverge, sections use inline OS-honest labels:

- **[AireOS]**: Cisco legacy WLC software (5520, 8540, 3504, vWLC).
- **[IOS-XE-WLC]**: Catalyst 9800 family running wireless-flavour IOS-XE (C9800-CL, C9800-40, C9800-80, C9800-L).
- **[Aruba AOS]**: Aruba Mobility Controller / Virtual MC on AOS 8.x.
- **[Aruba AOS-CX]**: AOS-CX switches acting as wireless gateways (partial coverage; many audit commands return to AOS Mobility Controller for full feature scope).
- **[Meraki]**: Cisco Meraki cloud-managed wireless (Dashboard API only; no CLI).
- **[Mist]**: Juniper Mist cloud-managed wireless (Mist Cloud API; no CLI).

Shared concepts apply to all platforms unlabelled. Consult `references/security-standards.md` for 802.1X / EAP state machine, WPA3 requirements, and rogue AP classification tiers. Consult `references/cli-reference.md` for read-only commands and API endpoints across all six platforms organised by audit category.

> **Skill marker**: When applying this skill, begin your reply with `[skill: wireless-security-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the wireless estate (controller platform mix, software versions, AP count, RADIUS infrastructure, RF environment, compliance regime) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Controller estate**
   - Which platforms are in scope: legacy AireOS, Catalyst 9800 (IOS-XE-WLC), Aruba Mobility Controller, AOS-CX wireless gateway, Meraki, Mist, or a mix?
   - Software versions per platform (AireOS 8.10.x is the final supported branch; IOS-XE 17.9+ for C9800; AOS 8.10+ for Mobility Controller; AOS-CX 10.13+ for wireless gateway; Mist is rolling cloud release).
   - HA / cluster topology (active-standby WLC pair, N+1 redundancy, Meraki / Mist cloud-failover, intra-cluster L3 mobility).
   - AP count per site and total fleet size (drives audit pagination strategy on cloud platforms).

2. **RADIUS and PKI baseline**
   - Primary and secondary RADIUS server addresses; EAP method baseline (EAP-TLS, PEAP, EAP-TTLS); shared-secret rotation cadence.
   - Server certificate chain trust path (internal CA vs public CA), validity windows, and renewal automation status.
   - Per-SSID dynamic VLAN policy (Tunnel-Private-Group-ID return) and the controller-side VLAN catalogue.

3. **RF site-survey baseline**
   - Site-survey artefacts available (channel plan, AP placement diagram, expected coverage cells, neighbouring AP inventory).
   - Approved-neighbour-AP list maintained for WIPS rogue classification (reduces false positives).
   - Wireless containment policy: monitoring-only or active deauthentication; jurisdictional legal review status for active containment.

---

## Scope and when to use

- Annual wireless security audit as part of infrastructure security review.
- Post-deployment validation of new SSID policies or controller upgrades.
- Incident response when a rogue AP, evil twin, or unauthorised wireless access is suspected.
- Compliance assessment requiring wireless security evidence (PCI DSS 4.0 § 11.2.1, HIPAA Technical Safeguards, NIST SP 800-153, ISO 27001 A.13.1.3).
- Pre-migration assessment before WPA2 to WPA3 upgrade across the wireless fleet.
- Pre-migration assessment before AireOS to Catalyst 9800 cutover (architecture change to tag-based config model).
- After RF redesign, office relocation, or new building buildout.
- Periodic rogue AP sweep to validate WIDS / WIPS detection effectiveness.
- Guest network isolation verification following network segmentation changes.
- Post-incident wireless posture review (after an SSID password leak, RADIUS compromise, or rogue AP discovery).

When the work is broader than wireless security (mixed wired and wireless audit, multi-domain segmentation review), use `multi-vendor-network-ops` for the umbrella entry point and `acl-rule-analysis` for the wired-side companion; return here for the wireless-specific deep-dive. For wireless RF or general WLAN troubleshooting (poor performance, client roaming, AP join failures) that is not security-scoped, this skill is the wrong shape; consult vendor docs or the relevant operational skill.

## Prerequisites

- **Read-only platform access**:
  - **[AireOS]** SSH or HTTPS to WLC management interface; analyst privilege level (no `config terminal` required).
  - **[IOS-XE-WLC]** SSH to C9800 management; user role with `show` privileges; optional NETCONF / RESTCONF read access for programmatic data collection.
  - **[Aruba AOS]** SSH to Mobility Controller; analyst role with `show` privileges; optional Aruba Central API for fleet-wide collection.
  - **[Aruba AOS-CX]** SSH to switch with read-only role; many audit commands route to the Mobility Controller (see Note on Platform Differences in `references/cli-reference.md`).
  - **[Meraki]** Dashboard API key with read-only organisation scope (`X-Cisco-Meraki-API-Key` header); rate limit 10 requests / second per organisation.
  - **[Mist]** API token with read-only role at Org or Site scope (`Authorization: Token <token>` header); regional API endpoint per Org location (`api.mist.com`, `api.eu.mist.com`, `api.gc1.mist.com`, `api.ac2.mist.com`).
- **Inventory of expected SSIDs**: which SSIDs should exist, their intended purpose (corporate / guest / IoT / voice / management), and the required security policy per SSID. The audit's findings hinge on comparing actual against expected.
- **RADIUS infrastructure documentation**: server addresses, expected EAP methods, certificate chain trust path, shared-secret rotation cadence, and any per-SSID RADIUS attribute policy (dynamic VLAN, dynamic ACL, session-timeout, idle-timeout).
- **RF design documentation or site survey data**: channel plan, AP placement, expected coverage cell boundaries, perimeter-AP power policy.
- **VLAN-to-SSID mapping**: which VLAN each SSID lands clients on, inter-VLAN firewall or ACL rules between wireless VLANs and corporate / production VLANs.
- **WIDS / WIPS policy**: containment enabled or monitoring-only; approved-neighbour-AP list (if maintained); legal review status for active containment in the operating jurisdiction.
- **Evaluating the running configuration**: not pending changes. Note explicitly when a config deploy is queued (Meraki Dashboard pending push, Mist Site-config override merge, FMC deploy task, AOS commit-pending state).

## Procedure

Follow this audit flow sequentially. Each step builds on findings from the prior step. The procedure adapts the policy-audit shape for wireless: SSID inventory then authentication / encryption then 802.1X then rogue AP then RF then report.

### Step 1: SSID policy inventory

Collect all configured SSIDs and their security posture across every controller in scope.

Use the commands listed in `references/cli-reference.md` § "SSID Configuration Audit" for the platform-specific syntax. For each SSID, record:

- **Name and status**: enabled or disabled (disabled SSIDs still consume configuration and may indicate decommissioned services; flag for cleanup).
- **Security mode**: Open, WPA2-Personal, WPA2-Enterprise, WPA3-Personal, WPA3-Enterprise, WPA3-Transition.
- **Authentication method**: PSK, 802.1X, MAC-auth, captive portal, open.
- **VLAN assignment**: which VLAN clients land on post-authentication (static per SSID or dynamic via RADIUS Tunnel-Private-Group-ID).
- **Broadcast status**: hidden SSIDs provide negligible security benefit (SSIDs are disclosed in probe responses and association frames).
- **Per-platform model differences**:
  - **[IOS-XE-WLC]** Catalyst 9800 uses a tag-based config model: WLAN profile (security policy) and Policy profile (VLAN, QoS, ACL) are independent objects bound via Policy tag. Audit BOTH the WLAN profile AND the bound Policy profile per SSID. An SSID may appear "secure" at the WLAN profile but land clients on a wrong VLAN via the Policy profile.
  - **[AireOS]** uses an integrated WLAN config (security + VLAN in one object); the IOS-XE-WLC tag split is the post-migration model.
  - **[Meraki]** and **[Mist]** are cloud-managed; SSID config lives at Org / Network level with optional Site override (Mist) or Network override (Meraki). Audit BOTH the inherited config AND any per-site override.

Flag immediately:

- Open (no encryption) SSIDs: Critical unless explicitly designated guest with captive portal and VLAN isolation (see Step 1 cross-check against Step 5 Guest network section).
- WPA2-Personal (PSK) SSIDs in enterprise environments: PSK shared across all clients enables credential sharing and offline dictionary attacks.
- SSIDs with no VLAN assignment: clients may land on a default VLAN with unintended access.
- **[IOS-XE-WLC]** SSIDs bound to a Policy profile that points at a non-existent VLAN (Policy profile validation does not catch this at config time).

### Step 2: Authentication and encryption audit

Evaluate each SSID's encryption and authentication configuration against the Encryption Strength Tiers in Severity Classification.

Use the commands listed in `references/cli-reference.md` § "Authentication and Encryption Audit" for platform-specific syntax. For enterprise SSIDs, verify:

- **WPA3-Enterprise** preferred; **WPA2-Enterprise** (AES / CCMP) minimum acceptable baseline.
- **Protected Management Frames (PMF)** enabled: prevents deauthentication attacks that force client disconnection and credential re-entry. Mandatory on WPA3; optional on WPA2 (enable everywhere it's supported).
- **TKIP disabled**: TKIP has known cryptographic weaknesses; CCMP or GCMP-256 only.
- **Key management**: SAE for WPA3-Personal; 802.1X with FT (Fast Transition / 802.11r) for enterprise roaming if voice or video clients in scope.

For WPA3-Transition mode SSIDs, document:

- Transition mode is a temporary migration step: it allows WPA2 clients that cannot support WPA3 to coexist with WPA3 clients, but WPA2 clients in transition mode do not benefit from SAE or PMF protections.
- An attacker can force a downgrade by impersonating the AP and advertising only WPA2 capability (downgrade attack).
- Set a target sunset date for transition mode based on client fleet WPA3 adoption rate; when WPA2 client population drops below 5%, transition to WPA3-only.

### Step 3: 802.1X / RADIUS validation

Validate the 802.1X authentication chain: supplicant -> authenticator -> RADIUS server.

Use the commands listed in `references/cli-reference.md` § "802.1X / RADIUS Validation" for platform-specific syntax. Verify each component:

**RADIUS server reachability**:

- Primary and secondary RADIUS servers configured for redundancy.
- RADIUS server state shows active / responding (not timeout / unreachable).
- Shared secret matches between controller and RADIUS server.
- Ports correct: UDP 1812 (authentication), UDP 1813 (accounting). RadSec / RADIUS-over-TLS on TCP 2083 if used.

**EAP method validation** (consult `references/security-standards.md` § "EAP Method Types" for full matrix):

- **EAP-TLS** (mutual certificate) for highest security; requires PKI infrastructure for client certificates and an issuing CA chain trusted by the RADIUS server.
- **PEAP** (MSCHAPv2) as acceptable alternative; server certificate required; client trusts server cert.
- **EAP-TTLS** similar to PEAP with broader inner-method support.
- **LEAP** deprecated; flag as Critical if still in use (offline dictionary attack feasible).

**Certificate validity**:

- RADIUS server certificate expiration date and renewal automation status.
- Trusted CA chain validity (intermediate CA expiration is a common silent failure).
- A RADIUS server certificate expiring during the audit window or within 90 days is High severity (an expired cert breaks all 802.1X authentication for the affected SSID).

**Dynamic VLAN assignment**:

- RADIUS should return Tunnel-Private-Group-ID attribute for VLAN placement per user / device.
- Verify that the returned VLAN exists on the controller and maps to the correct network segment.
- Test with sample authentications if possible: a valid 802.1X exchange that lands a client on the wrong VLAN is a segmentation failure, not an authentication failure, and produces no visible error to the user.

**RADIUS accounting**:

- Accounting enabled (needed for session tracking and compliance evidence).
- Accounting server reachable and receiving records.
- Accounting interim-update interval set per compliance need (typical 10 min for PCI DSS evidence).

### Step 4: Rogue AP assessment

Evaluate rogue AP detection, classification, and response posture.

Use the commands listed in `references/cli-reference.md` § "Rogue AP Detection" for platform-specific syntax. Assess:

**Detection coverage**:

- All managed APs scanning for rogues (on-channel monitoring during off-channel scan windows, or dedicated monitor-mode APs at higher coverage cost).
- Detection covers both 2.4 GHz and 5 GHz bands.
- If 6 GHz (Wi-Fi 6E) APs deployed, verify 6 GHz rogue detection capability; not all platform releases support 6 GHz WIDS at launch.

**Classification accuracy**:

- Review rogue AP list for misclassifications: neighbouring APs classified as rogues create alert fatigue; actual rogues classified as neighbours create blind spots.
- Verify wired-side correlation: controller checks switch MAC tables to determine if a rogue AP is connected to the corporate LAN. Wired-connected rogues bridge the wireless and wired networks, bypassing perimeter controls; Critical severity.
- Evil twin classification (rogue AP spoofing a managed SSID): Critical severity; immediate containment and SOC alert.

**Containment policy**:

- Is WIPS containment enabled (active deauthentication of rogue clients)?
- If enabled, containment limited to wired-connected rogues only (to avoid interfering with legitimate neighbouring APs in adjacent tenants).
- Legal review of active containment approved for the operating jurisdiction (active deauth has legal implications in some jurisdictions; FCC Part 15 and equivalent regulations).

**Rogue AP metrics**:

- Total rogues detected, classified, and unclassified.
- Rogues with clients associated: higher priority than idle rogues (active client exfiltration risk).
- Rogues on the same channels as managed SSIDs: higher interference risk and higher evil-twin viability.
- Time from detection to classification: delays increase exposure window; target < 15 min for managed sites.

### Step 5: RF security posture review

Assess radio frequency configuration for security implications.

Use the commands listed in `references/cli-reference.md` § "RF Security Assessment" for platform-specific syntax. Evaluate:

**Channel and power configuration**:

- Non-overlapping channels used (2.4 GHz: 1, 6, 11 only). Co-channel interference increases retry rates and degrades performance.
- Transmit power appropriate for coverage cell design; over-powered APs leak signal beyond physical boundaries (parking-lot attack surface).
- Auto-channel and auto-power enabled for dynamic adjustment (preferred for most deployments; static channel plans are reserved for high-density auditoria or RF-engineered environments).

**Coverage security**:

- APs near building perimeter use directional antennas or reduced power to minimise external signal leakage.
- No coverage holes where clients could be forced to associate with rogue APs (clients seek any available AP when legitimate signal drops below usable thresholds; see RF Signal Thresholds in Severity Classification).
- Band steering encourages 5 GHz / 6 GHz association; reduces 2.4 GHz range-based exposure.

**Channel utilisation**:

- High utilisation (> 80%) indicates congestion: degrades performance and may push clients to weaker / rogue APs.
- DFS channel events tracked: frequent radar detections in 5 GHz DFS channels cause channel changes that disrupt service.

**Guest network RF isolation** (cross-check against Step 1 VLAN findings):

- Guest SSID on same AP hardware as corporate is acceptable IF VLAN isolation verified at Step 1 (the guest SSID lands clients on a dedicated VLAN with no routing to internal networks).
- Guest bandwidth limits configured to prevent WAN saturation.
- Client isolation (peer-to-peer blocking) enabled on guest SSIDs (prevents lateral movement between guest clients on the same SSID).
- Captive portal enforcement: HTTPS redirect, valid portal certificate, session timeout / re-authentication interval.

### Step 6: Report

Compile findings into the Report template below. Prioritise by severity:

- Critical findings require immediate remediation (within 24 hours; consider activating incident-response-lifecycle for formal severity classification if business-impact thresholds met).
- High findings within 30 days.
- Medium findings within 90 days.
- Low findings on the next regular maintenance cycle.

Include specific SSIDs, VLAN IDs, controller hostnames, and AP MAC addresses in each finding for actionable remediation. Reference the procedure step that surfaced each finding.

## Severity classification

### Encryption Strength Tiers

| Configuration | Tier | Severity if used | Notes |
|---|---|---|---|
| WPA3-Enterprise (192-bit mode) | Tier 1 | n/a | CNSA-grade; SAE + GCMP-256 + PMF mandatory |
| WPA3-Enterprise | Tier 1 | n/a | SAE + CCMP-128 / GCMP-256 + PMF mandatory |
| WPA2-Enterprise (AES / CCMP) | Tier 2 | n/a | Acceptable baseline for enterprise |
| WPA3-Personal (SAE) | Tier 2 | n/a | Acceptable for non-802.1X SSIDs |
| WPA3-Transition | Tier 3 | Medium | Temporary; WPA2 clients lose PMF / SAE protection; downgrade attack feasible |
| WPA2-Personal (AES) | Tier 3 | Medium | PSK shared across all clients; offline dictionary attack risk |
| WPA2 (TKIP) | Tier 4 | High | TKIP deprecated; known cryptographic weaknesses |
| WEP | Tier 5 | Critical | Broken; trivially cracked in minutes; replace immediately |
| Open (no encryption) | Tier 5 | Critical | No confidentiality; acceptable only with captive portal AND VLAN isolation |

### Rogue AP Severity Classification

| Condition | Severity | Response time |
|---|---|---|
| Wired-connected rogue AP (on corporate LAN) | Critical | Immediate: contain and physically locate; activate `incident-response-network` |
| Evil twin (spoofing managed SSID) | Critical | Immediate: contain; SOC alert; activate `incident-response-lifecycle` |
| Rogue AP with associated clients | High | 24 hours: classify and contain or approve |
| Unclassified rogue AP (no wired correlation) | Medium | 72 hours: classify as neighbouring or rogue |
| Known neighbouring AP (from adjacent tenant) | Low | Document; no action unless interference |

### RF Signal Thresholds

| Metric | Good | Acceptable | Poor |
|---|---|---|---|
| SNR (voice) | >= 30 dB | 25 to 30 dB | < 25 dB |
| SNR (data) | >= 25 dB | 20 to 25 dB | < 20 dB |
| Channel utilisation | < 40% | 40 to 70% | > 70% |
| Noise floor | < -90 dBm | -90 to -85 dBm | > -85 dBm |
| Co-channel interference | 0 overlapping APs | 1 overlapping | > 1 overlapping |

## Decision trees

### SSID Security Triage

```
SSID encryption mode?
|
+-- Open (no encryption)
|   |
|   +-- Guest SSID with captive portal + VLAN isolation?
|   |   +-- Yes -> MEDIUM: acceptable if isolation verified
|   |   |       (verify VLAN separation, bandwidth limits, client isolation)
|   |   +-- No  -> CRITICAL: unencrypted with network access
|   |           (immediate: enable WPA2-Enterprise minimum or disable SSID)
|   +-- IoT SSID?
|       -> CRITICAL regardless: IoT must use WPA2-PSK minimum + dedicated VLAN
|
+-- WPA2-Personal (PSK)
|   |
|   +-- Enterprise environment?
|   |   +-- Yes -> HIGH: migrate to WPA2-Enterprise (802.1X)
|   |   +-- No (small office) -> MEDIUM: acceptable with strong PSK + rotation policy
|   +-- PSK shared with > 20 users?
|       -> HIGH: PSK compromise risk; migrate to 802.1X
|
+-- WPA2-Enterprise (AES)
|   |
|   +-- PMF enabled?
|   |   +-- No  -> MEDIUM: enable PMF (required for deauth attack protection)
|   |   +-- Yes -> baseline acceptable; evaluate WPA3 upgrade timeline
|   +-- 802.1X auth validated? -> proceed to Step 3
|
+-- WPA3-Transition
|   |
|   +-- Transition timeline defined?
|       +-- Yes -> LOW: monitor WPA2 client percentage; sunset when < 5%
|       +-- No  -> MEDIUM: define sunset date (transition mode is temporary)
|
+-- WPA3-Enterprise
    |
    +-- 192-bit mode?
        +-- Yes -> Optimal: CNSA-grade compliance
        +-- No  -> Strong: standard WPA3-Enterprise sufficient for most
```

### Authentication Method Upgrade Path

```
Current auth method?
|
+-- Open / MAC auth only
|   -> Upgrade to WPA2-Enterprise + 802.1X (Priority: CRITICAL)
|      If no RADIUS infrastructure: deploy RADIUS first
|
+-- WPA2-Personal (PSK)
|   -> Upgrade path depends on scale:
|      +-- < 10 devices  -> WPA3-Personal (SAE) acceptable
|      +-- >= 10 devices -> WPA2-Enterprise + 802.1X
|          (deploy RADIUS, enable 802.1X on SSID, push supplicant config via MDM / GPO)
|
+-- WPA2-Enterprise (PEAP / MSCHAPv2)
|   -> Current: acceptable baseline
|      Next upgrade: EAP-TLS (mutual cert) for passwordless auth
|      Requires: PKI infrastructure, client cert deployment (MDM / GPO)
|
+-- WPA2-Enterprise (EAP-TLS)
|   -> Current: strong
|      Next upgrade: WPA3-Enterprise with PMF
|      Verify client fleet WPA3 support before transition
|
+-- LEAP
    -> CRITICAL: deprecated; vulnerable to offline dictionary attacks
       Immediate: replace with PEAP or EAP-TLS
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
WIRELESS SECURITY AUDIT REPORT
==============================
Controller(s): [hostname(s) / org name]
Platform(s): [AireOS 8.10.x / IOS-XE-WLC 17.9 / AOS 8.10 / AOS-CX 10.13 / Meraki Dashboard / Mist Cloud]
Sites audited: [count / names]
Audit date: [UTC timestamp]
Performed by: [operator / agent]
Auditor scope: [read-only; no state-changing commands executed]

ASSUMPTIONS (element 1 of nine-element contract):
- [explicit assumptions about controller config baseline, RADIUS PKI trust, RF design]

RISK CATEGORY (element 2):
- [audit-only / investigative; no production-mutating actions]

EVIDENCE (element 3):
- Read-only commands and API endpoints used (cite per-step):
  - Step 1: [list]
  - Step 2: [list]
  - Step 3: [list]
  - Step 4: [list]
  - Step 5: [list]

SSID INVENTORY (Step 1):
- Total SSIDs configured: [count]
- Enabled SSIDs: [count]
- Encryption breakdown:
  - WPA3-Enterprise: [n]
  - WPA3-Personal: [n]
  - WPA2-Enterprise: [n]
  - WPA2-Personal: [n]
  - WPA3-Transition: [n]
  - Open: [n]
  - Other / legacy: [n]

AUTHENTICATION SUMMARY (Step 3):
- SSIDs using 802.1X: [n] / [total enabled]
- RADIUS servers: [count]; primary [IP]; secondary [IP]
- RADIUS server status: [all reachable / issues noted]
- EAP method baseline: [EAP-TLS / PEAP / other]
- RADIUS server certificate expiration: [date]; days until expiry [n]
- Dynamic VLAN assignment: [enabled / verified for sample SSIDs]

ROGUE AP SUMMARY (Step 4):
- Rogues detected: [total]
- Classification: [n] rogue, [n] interfering, [n] neighbouring, [n] unclassified
- Wired-connected rogues: [n] (Critical if > 0)
- Containment status: [enabled / disabled]; rogues contained: [n]
- Mean time from detection to classification: [minutes]

RF POSTURE (Step 5):
- APs audited: [count]
- Channel utilisation average: [%]
- APs with SNR < 20 dB: [n]
- Perimeter APs with high external leakage: [n]
- DFS event rate (5 GHz): [events / week]

GUEST NETWORK (cross-cut Step 1 + Step 5):
- Guest SSIDs: [count]
- VLAN isolation verified: [yes / no]
- Bandwidth limits configured: [yes / no]
- Client isolation enabled: [yes / no]
- Captive portal: [yes / no]; HTTPS redirect: [yes / no]

FINDINGS:
1. [Severity] [Category] : [Description]
   SSID: [name]
   Current config: [encryption / auth / VLAN]
   Issue: [specific problem]
   Recommendation: [specific remediation]

RECOMMENDATION (element 4):
- [prioritised action list by severity]

PRE-CHECKS (element 5):
- [verifications before applying any remediation]

EXECUTION GUIDANCE (element 6):
- [steps to apply each remediation]

POST-CHECKS (element 7):
- [verifications after each remediation]

ROLLBACK (element 8):
- [rollback steps per change]

ESCALATION (element 9):
- [vendor TAC, internal SOC, compliance officer triggers]

NEXT AUDIT: [Critical findings: 30 days; High: 90 days; clean: 180 days]
```

## Common failure modes

### Tag-based config drift on Catalyst 9800

**Symptom**: `[IOS-XE-WLC]` an SSID appears secure at the WLAN profile (correct WPA3-Enterprise, PMF mandatory, 802.1X bound) but clients land on the wrong VLAN or with the wrong ACL.

**Diagnosis**: Catalyst 9800 uses a tag-based config model where WLAN profile (security) and Policy profile (VLAN + QoS + ACL) are independent objects. The Policy tag binds a WLAN profile to a Policy profile per AP join profile. Drift between WLAN profile and bound Policy profile is silent: each object validates independently. Audit BOTH objects per SSID, not just the WLAN profile.

**Resolution**: enumerate Policy tags, then for each tag, list the bound WLAN profiles and the bound Policy profile; verify the Policy profile VLAN matches the intent. `show wireless tag policy detailed <tag-name>` shows the full binding.

### Aruba AOS-CX wireless gateway feature gap

**Symptom**: `[Aruba AOS-CX]` an audit command runs on the AOS Mobility Controller but returns "command not supported" or empty output on an AOS-CX gateway.

**Diagnosis**: AOS-CX wireless gateway is a partial feature set vs the AOS Mobility Controller. Many WLAN audit commands (rogue AP detail, deep RF stats, full WIDS event history) require routing to the upstream AOS Mobility Controller. AOS-CX as wireless gateway is most viable for small branch deployments where the full AOS feature surface is not needed.

**Resolution**: route the audit command to the AOS Mobility Controller for unsupported categories; document the AOS-CX feature gap in the audit report. Future audits should plan for the AOS Mobility Controller as the primary collection point with AOS-CX gateways as secondary.

### Mist API token scope vs Org / Site role boundary

**Symptom**: `[Mist]` an API call returns 403 Forbidden despite the token being valid and within rate limits.

**Diagnosis**: Mist API tokens carry a scope (Org-level or Site-level) AND a role (read / write / admin). An Org-scoped read-only token cannot fetch Site-level config overrides without explicit Site role. A Site-scoped token cannot read Org-level templates that the Site inherits from. Effective wireless config (`/sites/{site_id}/wlans/derived`) requires Site read scope minimum.

**Resolution**: issue an Org-level read-only token AND a Site-level read-only token, or issue an Org-level token with Site-inheritance read permission. Document the token scope in the audit report; rotate after the audit per `secrets-hygiene`.

### RADIUS certificate silent expiry

**Symptom**: all 802.1X authentication fails simultaneously at midnight UTC with no prior warning; total wireless outage for enterprise SSIDs.

**Diagnosis**: RADIUS server certificate expired. The renewal automation (ACME, NDES auto-enrollment, manual cert deployment cadence) failed or was never configured. Intermediate CA expiration is the more common silent-failure mode (root CA changes are tracked; intermediates often are not).

**Resolution**: check certificate expiration on RADIUS server AND any intermediate CAs in the chain at audit time. Flag any expiration within 90 days as High. For the immediate outage: restore the previous certificate from backup or renew via emergency cert issuance; document in audit report.

### Rogue AP false-positive fatigue

**Symptom**: large rogue AP list with most entries flagged as alerts but operationally treated as noise; SOC analysts no longer investigate rogue alerts.

**Diagnosis**: WIDS classification policy not tuned for the environment. Adjacent tenants' APs flagged as rogues; managed APs from a partner organisation flagged as rogues. False-positive rate above 30% indicates the classification needs the approved-neighbour-AP list maintained.

**Resolution**: maintain the approved-neighbour-AP list (per BSSID and per OUI); tune classification rules to demote known-neighbour APs from rogue to neighbour. Re-baseline the rogue list quarterly. False-positive rate target: < 10% after baseline.

### WPA3-Transition mode permanent residency

**Symptom**: WPA3-Transition mode SSID with no defined sunset date; WPA2 client population trending up rather than down over time.

**Diagnosis**: WPA3-Transition mode treated as a permanent state rather than a migration step. The downgrade-attack risk persists indefinitely. WPA2 clients in transition mode lack SAE and PMF; the only security benefit over plain WPA2-Enterprise is the operational convenience of supporting both client populations on one SSID.

**Resolution**: define a sunset date in the audit report. Run a WPA2-client census via the controller (which clients connected with WPA2 vs WPA3 in the last 30 days); communicate the sunset date to client owners; track migration weekly until WPA2 population drops below 5%; then disable WPA2 fallback (WPA3-only).

## Cross-references

- `incident-response-network`: network-forensics arm for wireless security incidents. When a wireless audit surfaces a True Positive Critical finding (wired-connected rogue, evil twin, RADIUS compromise), hand off to capture wireless client lists, association tables, AP join logs, and any controller-side packet captures before volatile evidence ages out. Pairs with `oncall-runbooks` (generic incident container) and `incident-response-lifecycle` (NIST 800-61 process layer).
- `incident-response-lifecycle`: NIST 800-61 process layer. Wraps wireless-security-audit findings into severity classification, four-role assignment (Incident Commander, Technical Lead, Comms Lead, Scribe), escalation matrix, communications across audiences, and post-mortem facilitation when an audit finding triggers formal incident declaration (Critical finding with business-impact thresholds met).
- `acl-rule-analysis`: wired-side complement. Wireless segmentation policies (VLAN-to-SSID mapping, inter-VLAN ACL between guest and corporate, IoT-VLAN isolation) require wired-side ACL enforcement to be effective. Use after Step 1 and Step 5 to validate the wired side of any wireless segmentation finding.
- `siem-log-analysis`: SIEM-equipped log investigation for wireless events (RADIUS auth failures, rogue AP alerts, WIDS containment actions). Use when the wireless platform forwards events to a SIEM and the audit needs cross-controller correlation or historical trend analysis.
- `network-log-analysis`: no-SIEM raw-syslog companion to siem-log-analysis. Wireless controllers forward syslog with vendor-specific message formats; use this skill when investigating wireless events without a SIEM in scope.
- `oncall-runbooks`: every wireless incident playbook (RADIUS outage, mass rogue alert, WIDS containment misfire) should have a runbook URL that the on-call engineer can follow at 3 AM. Wireless-specific runbooks reference findings and remediations from this skill.
- `bgp-analysis`, `igp-routing-analysis`: when wireless segmentation drift is symptomatic of a wider routing-policy issue (dynamic VLAN landing on a VLAN with missing routes), load the appropriate IGP / BGP specialist.
- `multi-vendor-network-ops`: umbrella entry-point skill. The nine-element response contract (assumptions, risk category, evidence, recommendation, pre-checks, execution guidance, post-checks, rollback, escalation) applies to any production-impacting recommendation surfaced by a wireless audit.
- `secrets-hygiene`: RADIUS shared secrets, controller admin credentials, Meraki / Mist API tokens, captive portal certificates: all live in a secret store, not in audit reports or screenshots. Rotate after any incident with credential-exposure suspicion. The "Probing the credential store" subsection applies whenever an audit needs to confirm a credential exists without exfiltrating its value.
- `utc-timestamps`: all wireless audit timestamps in reports must be UTC. Controllers often display local time in the GUI; normalise to UTC for cross-team correlation.
- `cite-sources`: when wireless audit reports cite external standards (NIST SP 800-153, PCI DSS 4.0, IEEE 802.11i-2004), cite the source with date and identifier.
- `completion-gate` Layer 3: post-audit verification. After remediation, re-run the audit step that surfaced the finding to confirm closure (the suspect SSID should now show the expected encryption mode; the wired-connected rogue should no longer appear on the corporate LAN).
- `humanise-comms`: wireless audit reports go to mixed audiences (network engineers, security analysts, executives, compliance officers, regulators). Match the audience; the executive summary differs from the engineer-level findings detail.
- `documented-limits-are-starting-points`: vendor-published limits for AP count per controller, client count per AP, rogue list size, and WIDS event history depth are starting points for the audit's RF and capacity sections, not absolutes; the operational ceiling is usually lower under realistic traffic.

## Red flags (about-to-act warnings)

- **Enable active WIDS containment without legal review.** Active deauthentication of rogue clients has legal implications in some jurisdictions (FCC Part 15 and equivalent regulations forbid interference with unlicensed devices not on your network). Verify organisational policy AND legal counsel approval before enabling automatic containment; document the policy in the audit report.
- **Recommend SSID changes from this skill.** This is an audit skill, not a change skill. Recommendations (disable an Open SSID, migrate from PSK to 802.1X, switch from WPA2-Transition to WPA3-only) need a change ticket, peer review, client-impact assessment, and execution discipline; hand off to the appropriate change-verification or vendor-specific operational skill for the actual config change.
- **Trust the controller's rogue classification without spot-check.** Misclassifications create blind spots (real rogues classified as neighbours) and alert fatigue (neighbours classified as rogues). Sample 5 to 10 entries per audit; verify each against the wired-side correlation and against the approved-neighbour-AP list.
- **Ignore the AireOS-to-IOS-XE-WLC config-model gap during a migration audit.** AireOS uses integrated WLAN config; IOS-XE-WLC uses tag-based separation (WLAN profile + Policy profile + AP join profile + RF profile + Site tag + Policy tag + RF tag). A migrated SSID may appear at security parity on the WLAN profile but land clients incorrectly via the Policy profile binding. Always audit BOTH the WLAN profile AND the bound Policy profile per SSID post-migration.
- **Treat Meraki Air Marshal classifications as authoritative without local context.** Meraki Air Marshal applies cloud-side classification rules that may not match the local environment (adjacent tenants, partner offices, expected neighbouring APs). Maintain a Meraki Air Marshal allow-list per network; review monthly.
- **Audit Mist with an Org-only API token.** Mist Site-level config overrides Org-level templates; an Org-only token misses Site-specific findings. Use Site-level read access (or a token with Site-inheritance read) for any audit that includes per-site SSID policy.
- **Skip the cross-check between Step 1 (SSID VLAN assignment) and Step 5 (Guest network isolation).** A guest SSID that appears isolated at the wireless layer (VLAN tag set, client isolation enabled) may still route to corporate networks via misconfigured inter-VLAN firewall rules. The wireless-only audit cannot validate this; the wired-side check belongs in `acl-rule-analysis`. Always note when the wired-side validation is OUT of scope for the current audit.
- **Paste RADIUS shared secret in an audit report.** Shared secrets are credentials. Audit reports end up in tickets, document repositories, and email; the shared secret should be referenced ("rotated 2026-Q1; cadence quarterly") not pasted. Per `secrets-hygiene`.
- **Treat WPA3-Transition as a permanent state.** Transition mode is a migration step; the downgrade-attack risk is real and persistent. Every WPA3-Transition SSID needs a sunset date in the audit report.
- **Skip the post-audit verification re-run.** Findings closed without re-running the procedure step that surfaced them are claims, not verifications; per `completion-gate` Layer 3.

## Bottom line

Wireless LAN security audit is a six-step procedure: SSID policy inventory, authentication / encryption audit, 802.1X / RADIUS validation, rogue AP assessment, RF security posture, report. The diagnostic reasoning is platform-independent; only command syntax diverges. Six platforms covered: Cisco AireOS, Cisco IOS-XE-WLC (Catalyst 9800), Aruba AOS Mobility Controller, Aruba AOS-CX wireless gateway (partial coverage), Cisco Meraki, Juniper Mist. Audit is read-only; recommendations hand off to the appropriate change-verification skill. Critical findings (wired-connected rogue, evil twin, expired RADIUS certificate, LEAP still in use, WEP still in use) require immediate remediation and may trigger `incident-response-lifecycle` activation. The wired-side validation of wireless segmentation belongs in `acl-rule-analysis`; this skill notes the boundary but does not cross it.
