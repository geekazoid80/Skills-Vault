---
name: bsd-firewall-audit
description: Use for any audit, change review, or compliance pass on a pfSense or OPNsense firewall (both FreeBSD-based, both built on the `pf` packet filter with a single `config.xml`), whether standalone or a CARP HA pair. Triggers include "audit this pfSense firewall", "review OPNsense rules", "pfSense any-any rule", "pf ruleset audit", "port forward exposes internal host", "webGUI reachable from WAN", "anti-lockout rule on WAN", "SSH exposed on the firewall", "OPNsense API key audit", "pfSense REST API access", "Suricata not enabled", "Snort ruleset stale", "pfBlockerNG DNSBL gap", "Unbound DNS rebinding protection", "outbound NAT too broad", "1:1 NAT review", "floating rule quick match", "config.xml backup not encrypted", "AutoConfigBackup missing", "CARP failover not syncing", "pfsync state sync", "XMLRPC config sync drift", "OpenVPN weak cipher", "WireGuard peer audit", "IPsec PSK", "firewall certificate expiry", "self-signed webGUI certificate", "pfSense CE end of life", "OPNsense Business Edition update channel", "compliance audit on pfSense / OPNsense". Covers pfSense CE and pfSense Plus (Netgate) and OPNsense CE and OPNsense Business Edition, the `pf` ruleset (WAN / LAN / floating rules, aliases, default-deny, NAT and port-forward), the security-services layer (Suricata / Snort IDS-IPS, pfBlockerNG or built-in blocklists, Unbound DNS hardening, DHCP hardening, package / plugin posture), VPN and certificate hygiene (OpenVPN, WireGuard, IPsec, the certificate manager), update currency and `config.xml` backup integrity, and CARP / pfsync / XMLRPC HA posture. Per-distro deltas are called out inline throughout (default IDS engine, blocklist tooling, menu paths, API model, `config.xml` schema nuance). Six-step audit procedure, severity table, three decision trees. Diagnose-first; read-only `config.xml` export, webGUI, `pfctl` show commands, or REST API GET before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Authored with reference to the MIT-licensed danielrosehill/Claude-Slash-Commands opnsense-audit baseline; CIS pfSense / OPNsense benchmarks cited, not reproduced.
license: MIT
metadata:
  version: 1.0.0
---

# BSD firewall audit (pfSense and OPNsense)

Policy-audit-driven analysis of pfSense and OPNsense firewall rules and security posture. Unlike generic firewall checklists that only look for open ports and default-deny, this skill evaluates the FreeBSD / `pf` security architecture the two platforms share: the `pf` ruleset with per-interface and floating rules, aliases and NAT, the security-services layer (IDS/IPS, DNS filtering, DNS and DHCP hardening, package / plugin posture), VPN and certificate hygiene, the single `config.xml` that holds the entire configuration (and its backup exposure), and CARP-based high availability with XMLRPC configuration sync.

pfSense and OPNsense are ~90% the same audit surface: OPNsense began as a pfSense fork, both run FreeBSD, both use `pf`, both store the whole configuration in one `config.xml`. The deltas that matter (default IDS engine, DNS-blocklist tooling, package vs plugin system, the REST API model, and menu paths) are flagged inline as `[pfSense]` / `[OPNsense]` throughout. Covers pfSense CE 2.7.x and pfSense Plus 24.x+ and OPNsense 24.x / 25.x+.

> **Skill marker**: When applying this skill, begin your reply with `[skill: bsd-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (single device or CARP pair, distro and edition, interface topology, version) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Platform and architecture**
   - pfSense or OPNsense? Which edition: pfSense CE or pfSense Plus (Netgate appliance / subscription), OPNsense CE or OPNsense Business Edition?
   - Standalone or a CARP HA pair (primary + secondary with XMLRPC config sync and pfsync state sync)?
   - Which major / minor version, and is it a supported (non-EOL) build?
   - Interface / zone layout: WAN, LAN, DMZ, VPN, and any additional or VLAN interfaces.

2. **Audit driver**
   - Compliance pass, post-incident review, migration baseline, or rule cleanup?
   - Specific concerns (admin-plane exposure, IDS/IPS coverage, NAT / port-forward exposure, config backup, CARP sync)?

3. **Evidence and access**
   - Read-only route: an exported `config.xml` backup (the single richest artefact), webGUI admin, an SSH shell (`pfctl` show commands), or the REST API. `[OPNsense]` has a first-class REST API (per-user key / secret); `[pfSense]` Plus 24.03+ ships an official REST API, CE has none by default (only a third-party package).
   - `config.xml` holds private keys, IPsec PSKs, and credential material; treat the export as a secret (see `secrets-hygiene`). Confirm it is handled and stored accordingly before it leaves the box.
   - Logs, IDS alerts, or CARP status available?

---

## Scope and when to use

- Post-change rule review after rule additions, interface changes, or a major version upgrade.
- `pf` ruleset audit verifying default-deny, per-interface and floating rule intent, alias hygiene, and NAT / port-forward exposure.
- Security-services audit: IDS/IPS (Suricata / Snort) coverage and ruleset currency, DNS filtering (pfBlockerNG or built-in blocklists), Unbound DNS hardening, DHCP hardening, and package / plugin posture.
- Admin-plane exposure review: webGUI HTTPS and port, anti-lockout rule, SSH posture, API keys, console access, and privilege / group separation.
- VPN and certificate audit: OpenVPN, WireGuard, and IPsec configuration, and the certificate manager (expiry, weak keys / hashes, the webGUI certificate).
- Update currency and `config.xml` backup integrity: edition / update-channel posture, patch status, and encrypted off-box backup.
- CARP HA posture check: VIP and pfsync state sync, XMLRPC configuration sync, version parity, and dedicated sync interface.
- Quarterly or annual compliance audit requiring per-rule justification.
- Pre-upgrade baseline before a major version change.

For mixed-vendor estate work, run `acl-rule-analysis` first for the cross-vendor methodology pass, then this skill for the pfSense / OPNsense deep-dive. Sibling Stage 3 specialists: `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `cisco-firewall-audit`, `checkpoint-firewall-audit`, `sophos-firewall-audit`. For IPsec / OpenVPN / WireGuard site-to-site and remote-access VPN deep dives see `vpn-tunnel-troubleshooting`.

## Prerequisites

- Read-only access: an exported `config.xml` backup, or a webGUI admin account, or an SSH shell for `pfctl` show commands, or a REST API key (OPNsense, or pfSense Plus).
- Topology knowledge: which interfaces exist (WAN, LAN, DMZ, VPN, VLANs), their function, and expected inter-interface traffic.
- Knowledge of expected security-service assignments (which interfaces should carry IDS/IPS, which rules should carry DNS filtering, whether Unbound should enforce DNSSEC / DNS-over-TLS).
- Whether IDS/IPS runs in inline (IPS, blocking) or legacy (IDS, alert-only) mode, and which rulesets are subscribed.
- Awareness of the edition and update channel: pfSense CE vs Plus, OPNsense CE vs Business Edition, which determines patch cadence and signing.
- Running configuration saved (the audit evaluates the active `config.xml`, not staged webGUI edits that have not been applied).

## Procedure

Follow the six steps in order. The flow moves from admin-plane exposure through the `pf` ruleset and security-service coverage, VPN and certificate hygiene, update currency and backup, and finally CARP HA.

The single richest evidence artefact is the exported `config.xml`: it contains the entire configuration (rules, NAT, aliases, users, certificates, VPN, packages) in one XML file. The webGUI mirrors it; an SSH shell gives the live compiled ruleset via `pfctl -sr` (rules), `pfctl -sn` (NAT), and `pfctl -sa` (everything); `[OPNsense]` and `[pfSense]` Plus expose read endpoints over the REST API. Because `config.xml` holds private keys and PSKs, treat every export as read-only secret evidence, not something to paste into a transcript. Command / entity blocks below name the artefact to read; treat every one as read-only evidence collection before any change.

The XML element names shown below follow the pfSense lineage (the base firewall config OPNsense inherited: `filter`, `nat`, `aliases`, `system`, `cert`, `ca`, `virtualip`). On `[OPNsense]`, newer subsystems, especially the WireGuard plugin and 25.x OpenVPN instances, nest under an `<OPNsense>` namespace rather than the flat legacy element, and exact paths shift between versions. Navigate by config area (webGUI, filter rules, NAT, VPN, certificates), not by a literal XPath, and confirm the element on the box.

### Step 1: admin-plane exposure inventory

```
config.xml: <system><webgui>          # protocol, port, ssl-certref
config.xml: <system><ssh>             # SSH enable, port, key-only
config.xml: <system><user> / <group>  # accounts, privileges, groups
config.xml: <system><enableserial> / console
config.xml: <system><webgui><auth>    # 2FA / TOTP where configured
pfctl -sr | head                      # confirm the compiled anti-lockout rule
```

Evaluate:

- **webGUI exposure:** confirm the webGUI uses HTTPS (not HTTP), ideally on a non-default port, and is bound to LAN / management interfaces only. A webGUI reachable from the WAN interface is a Critical admin-plane exposure; remote administration belongs behind a VPN.
- **Anti-lockout rule:** both platforms auto-generate an anti-lockout rule that permits webGUI and SSH from the LAN so an operator cannot lock themselves out. Confirm it is scoped to the management interface and never applies on WAN. `[pfSense]` System > Advanced can disable it; `[OPNsense]` Firewall > Settings > Advanced. If disabled, confirm an explicit management rule exists.
- **SSH posture:** if SSH is enabled, confirm key-only authentication (password auth disabled), a restricted source, and no WAN exposure. SSH open to WAN with password auth is a Critical finding.
- **API keys:** `[OPNsense]` per-user API key / secret pairs and `[pfSense]` Plus API tokens should be scoped to the least privilege the automation needs, tied to a dedicated account, and rotated. An API key on a full-admin account reachable from WAN is a High finding.
- **Privilege and group separation:** confirm role separation (admins vs read-only / operator groups) rather than every operator sharing the `admins` group. `[OPNsense]` supports built-in TOTP 2FA; verify it is enabled on admin accounts where policy requires it.
- **Console / serial:** confirm the console menu is password-protected (physical / serial access otherwise bypasses webGUI auth).

### Step 2: `pf` ruleset rule-by-rule analysis

```
config.xml: <filter><rule>            # per-interface + floating rules, in order
config.xml: <nat> / <outbound> / <onetoone>   # port-forward, outbound, 1:1 NAT
config.xml: <aliases><alias>          # host / network / port / URL-table aliases
pfctl -sr ; pfctl -sn                 # live compiled rules + NAT (SSH)
```

`pf` evaluates rules per interface. Floating rules can be evaluated first and, when marked `quick`, match-and-stop before interface rules; ordinary rules are last-match unless `quick` is set. Each interface has an implicit default-deny for inbound traffic not explicitly permitted. Evaluate against:

- **Overly permissive rules:** an `allow` rule with source `any`, destination `any`, and port `any` on an interface carrying untrusted traffic is a Critical finding. On the WAN interface, any inbound `allow any` defeats the default-deny posture.
- **Port-forward exposure:** a destination-NAT (port forward) that exposes an internal host to the WAN must have a tightly scoped associated firewall rule (specific source where possible, specific destination host and port). A port forward with an `allow any` source, or exposing RDP / SMB / a database port to the internet, is Critical. Confirm whether the auto-added associated rule or a manual rule governs it.
- **Outbound NAT scope:** review outbound NAT mode (automatic, hybrid, or manual). A manual outbound NAT rule with an overly broad source can masquerade traffic that should be denied; confirm the source networks are intended.
- **1:1 NAT:** review any 1:1 NAT mappings for internal hosts fully exposed on a public address without a restrictive firewall rule.
- **Alias hygiene:** aliases (host, network, port, and URL-table) keep rules readable, but a stale or overly broad alias silently widens every rule that references it. Enumerate aliases and confirm membership is current; a URL-table alias pulling from an unreachable feed can fail open or stale.
- **Rule logging and action:** confirm `block` vs `reject` is intentional (reject reveals the firewall; block is silent), and that boundary deny rules and the default deny log for visibility. Floating `quick` rules that short-circuit interface rules should be reviewed for unintended reach.
- **Disabled and stale rules:** disabled rules still occupy the rulebase and create audit confusion. Rules with no matches over 90+ days are cleanup candidates (cross-check `acl-rule-analysis` staleness bands).

### Step 3: security-service coverage audit

Goal: untrusted traffic is inspected and filtered, not merely permitted.

- **IDS/IPS:** confirm intrusion detection / prevention is enabled on the interfaces carrying untrusted traffic, and note the mode. `[OPNsense]` ships Suricata built-in (Services > Intrusion Detection), inline IPS mode recommended. `[pfSense]` runs Suricata or Snort as a package (Services menu once installed); confirm one is installed and enabled. Legacy / alert-only mode detects but does not block; inline / IPS mode blocks. Verify rulesets are subscribed and current (ET Open / ET Pro for Suricata, Snort VRT for Snort) and that the enabled rule categories match the traffic. No IDS/IPS on an internet-facing interface is a High finding.
- **DNS filtering:** `[pfSense]` typically uses pfBlockerNG (DNSBL for domain blocklists plus IP feeds); `[OPNsense]` uses Unbound's built-in blocklists (Services > Unbound DNS > Blocklist) or a plugin. Confirm blocklists are enabled, feeds are current, and the resolver actually enforces them.
- **Unbound DNS hardening:** confirm DNSSEC validation is enabled, DNS-rebinding protection is on, and, where required, outbound DNS is forwarded over TLS rather than clear UDP/53. Confirm clients cannot bypass the resolver to external DNS (a NAT or block rule for outbound 53 / 853 to non-firewall resolvers).
- **DHCP hardening:** review DHCP scopes; where policy requires it, confirm static mappings and that unknown clients are denied a lease on sensitive segments.
- **Package / plugin posture:** `[pfSense]` packages and `[OPNsense]` plugins (`os-*`) extend the firewall but also extend its attack surface. Enumerate installed packages / plugins, flag unmaintained or unnecessary ones, and confirm they are updated with the base system.

Summarise coverage: which interfaces carry IDS/IPS, whether DNS filtering is enforced, and the gaps.

### Step 4: VPN and certificate hygiene

```
config.xml: <openvpn> / <wireguard> / <ipsec>
config.xml: <cert> / <ca>              # certificate manager: certs + CAs
```

- **OpenVPN:** confirm strong data ciphers (AES-GCM), TLS authentication or `tls-crypt` on the control channel, certificate-based (not shared-key) auth for remote access, and that the server is not needlessly reachable on a predictable WAN port without additional protection.
- **WireGuard:** now a kernel module on both platforms. Confirm each peer's allowed-IPs are scoped (not `0.0.0.0/0` inbound), keys are current, and the listen port and firewall rule are intended.
- **IPsec:** prefer IKEv2; confirm certificate or strong-PSK authentication, modern proposals (no DES / 3DES / MD5 / DH group 1-2), and that mobile / remote-access phase-2 selectors are not overly broad.
- **Certificate manager:** enumerate CAs and certificates. Flag expired or soon-to-expire certificates, weak keys (RSA < 2048) or weak signature hashes (SHA-1), and confirm the webGUI uses a proper certificate rather than the factory self-signed one where policy requires it. The webGUI certificate, VPN server certificates, and their issuing CA all live here.

### Step 5: update currency and `config.xml` backup integrity

- **Version and EOL:** confirm the installed version is a supported, patched build. `[pfSense]` CE and Plus track separately (CE community cadence vs Plus / Netgate signed releases); `[OPNsense]` CE vs Business Edition (Business trails CE with extra stabilisation and commercial signing). An EOL or several-versions-behind build is a High finding; note pending security fixes.
- **Patches:** `[pfSense]` System Patches package applies targeted fixes between releases; confirm required patches are applied. `[OPNsense]` applies fixes through its update channel; confirm the firewall is current on its channel.
- **`config.xml` backup:** confirm an automated, encrypted, off-box backup exists. `[pfSense]` AutoConfigBackup encrypts the config to Netgate's cloud (free with a Netgate account, on both CE and Plus); `[OPNsense]` supports scheduled backups to Nextcloud / Google Drive and local encrypted exports. A backup that is unencrypted, or that never leaves the box, is a Medium finding: `config.xml` contains private keys and PSKs, so an unencrypted backup is a credential-exposure risk (see `secrets-hygiene`).
- **Backup exposure:** confirm backup destinations and any backup credentials are controlled, and that old plaintext `config.xml` copies are not left on operator workstations or shares.

### Step 6: CARP HA and logging posture

```
config.xml: <virtualip>               # CARP VIPs
config.xml: <hasync> / XMLRPC sync config
config.xml: <syslog>                  # remote syslog targets
pfctl -si                             # filter status and counters (SSH; pfctl -ss for states)
```

Check:

- **CARP VIPs and failover:** confirm CARP virtual IPs are configured on the shared interfaces, VHIDs are unique, and advertising frequency / skew makes the intended node primary. Outbound NAT and port forwards should reference the CARP VIP, not a node's real address, so failover preserves them.
- **State sync (pfsync):** confirm pfsync is enabled on a dedicated sync interface so existing connections survive a failover.
- **Configuration sync (XMLRPC):** the primary pushes configuration to the secondary over XMLRPC. Confirm sync is enabled, the synced sections are correct, and the secondary is actually receiving updates (config drift means the standby enforces a different ruleset).
- **Version parity:** both nodes MUST run the same version. A mismatch breaks XMLRPC sync and causes inconsistent enforcement after failover.
- **Dedicated sync interface:** confirm pfsync and XMLRPC use a dedicated interface, not the WAN or a data interface.
- **Logging:** confirm remote syslog forwarding is configured (firewall logs, IDS alerts, DHCP, authentication) so logs survive the box and feed investigation. Local-only logs are lost if the device is compromised or fails.

## Config backup and edition / update-channel posture (brief)

The edition and update channel materially change patch cadence and signing, and the `config.xml` backup is the recovery point for the entire firewall. Touch points relevant to an audit:

- **Edition sets the patch cadence.** `[pfSense]` CE follows a community release cadence and can lag security fixes; pfSense Plus (Netgate subscription / appliance) ships signed releases with vendor support. `[OPNsense]` CE moves fast; OPNsense Business Edition trails CE with extra stabilisation and commercial signing. Record which edition and channel a device tracks before judging its currency.
- **`config.xml` is the whole firewall and it holds secrets.** One file carries rules, NAT, users, certificates, private keys, and VPN PSKs. An encrypted, off-box, automated backup is the recovery baseline; an unencrypted or on-box-only backup is both a recovery gap and a credential-exposure risk.
- **Do not confuse "saved" with "applied".** A webGUI change staged but not applied is not in the running ruleset; audit the applied `config.xml`, and on a CARP pair confirm the secondary received the synced change.

## Severity classification

| Finding | Severity | Rationale |
|---|---|---|
| `pf` rule with source `any` + destination `any` + port `any` + action allow on an untrusted interface | Critical | Fully open rule; default-deny defeated on that interface. |
| Port forward exposing an internal host to WAN with an `allow any` source (or exposing RDP / SMB / a database port) | Critical | Internal service exposed to the internet without restriction. |
| webGUI reachable from the WAN interface | Critical | Management plane exposed to the internet. |
| SSH open to WAN with password authentication | Critical | Remote shell open to internet credential brute force. |
| No IDS/IPS on an internet-facing interface | High | Untrusted traffic passes without intrusion detection or prevention. |
| IDS/IPS in legacy / alert-only mode where blocking is intended | High | Threats detected but not blocked. |
| API key on a full-admin account reachable from WAN | High | Over-privileged automation credential exposed. |
| Anti-lockout rule disabled with no explicit management rule | High | Risk of lockout, or an unscoped management path. |
| EOL or several-versions-behind firmware | High | Unpatched known vulnerabilities. |
| Weak VPN crypto (DES / 3DES / MD5 / DH group 1-2, or OpenVPN shared-key for remote access) | High | VPN confidentiality / integrity weakened. |
| CARP configuration out of sync (XMLRPC drift) or version mismatch between nodes | High | Standby enforces a different ruleset; failover inconsistency. |
| Overly broad outbound NAT or 1:1 NAT exposing an internal host | High | Traffic masqueraded or a host exposed beyond intent. |
| Stale IDS/IPS rulesets or blocklist feeds | High | Detection matching on outdated signatures / feeds. |
| Unbound without DNSSEC or DNS-rebinding protection | Medium | Weaker DNS integrity; rebinding exposure. |
| DNS filtering (pfBlockerNG / blocklists) absent where required | Medium | No domain-level blocking of malicious / unwanted destinations. |
| Certificate expired / weak key / SHA-1 signature | Medium | Trust cannot be validated; weak cryptographic assurance. |
| Default self-signed webGUI certificate where a CA-signed one is required | Medium | Admin session trust cannot be validated. |
| `config.xml` backup unencrypted or on-box only | Medium | No controlled recovery point; credential-exposure risk. |
| Unmaintained package / plugin installed | Medium | Extra attack surface without maintenance. |
| Disabled rules left in the production rulebase | Medium | Audit confusion; stale configuration; cleanup recommended. |
| Boundary deny rules not logging | Medium | Denied traffic and reconnaissance invisible to investigation. |
| Rules with zero matches >90 days | Low | Unused rules; cleanup candidates. |

### Security-service coverage maturity

| Coverage | Maturity | Guidance |
|---|---|---|
| IDS/IPS inline on all untrusted interfaces + DNS filtering + hardened Unbound | Mature | Maintain; review rulesets and feeds quarterly. |
| IDS/IPS on the WAN edge but gaps on inter-segment interfaces, or alert-only mode | Developing | Extend to inter-segment interfaces; move to inline where blocking is intended. |
| No IDS/IPS, or detection without DNS filtering | Immature | Systematic security-service rollout needed, starting at the internet edge. |

## Decision trees

### Port-forward / NAT exposure remediation

```
Port forward (destination NAT) to an internal host
├── Source of the associated firewall rule?
│   ├── `any` (whole internet) -> CRITICAL: scope to known sources or front with VPN
│   ├── Specific networks -> acceptable; confirm they are still current
│   └── No matching restrictive rule at all -> CRITICAL: the forward is wide open
│
├── What service is exposed?
│   ├── RDP / SMB / database / management -> CRITICAL: never expose directly; use VPN
│   ├── Web service -> confirm it is patched + behind IDS/IPS; consider a reverse proxy / WAF
│   └── Other -> justify the exposure and scope the source
│
└── Does the forward reference the CARP VIP (HA pair)?
    ├── Yes -> survives failover
    └── No (points at a node's real IP) -> breaks on failover; repoint to the VIP
```

### IDS/IPS coverage remediation

```
Interface carrying untrusted traffic
├── IDS/IPS enabled on it?
│   ├── No -> HIGH: enable Suricata [OPNsense built-in / pfSense package] or Snort [pfSense]
│   ├── Yes, legacy / alert-only -> HIGH (if blocking intended): switch to inline / IPS mode
│   └── Yes, inline -> correct
│
├── Rulesets current?
│   ├── Stale / unsubscribed -> HIGH: subscribe + schedule updates (ET Open/Pro, Snort VRT)
│   └── Current -> confirm enabled categories match the traffic
│
└── DNS filtering present?
    ├── None -> MEDIUM: enable pfBlockerNG [pfSense] or Unbound blocklists [OPNsense]
    └── Present -> confirm feeds are current and enforced by the resolver
```

### Admin-plane exposure

```
Management service reachable from WAN?
├── webGUI (HTTPS) on WAN -> CRITICAL: bind to LAN / management; use VPN for remote admin
├── SSH on WAN -> CRITICAL: disable or restrict to allowed source; key-only auth
├── API endpoint on WAN -> HIGH: restrict source; scope the key; dedicated least-privilege account
└── Ping on WAN -> LOW: informational; often left for reachability tests
│
├── webGUI certificate?
│   ├── Factory self-signed (where CA-signed required) -> MEDIUM: install a proper certificate
│   └── CA-signed, unexpired -> correct
│
└── Admin authentication?
    ├── Shared `admins` group for all operators -> enable role separation
    └── 2FA / TOTP available but off on admin accounts -> enable where policy requires [OPNsense built-in]
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
BSD FIREWALL (pfSense / OPNsense) SECURITY AUDIT REPORT
=======================================================
Device: [hostname] | Distro: [pfSense / OPNsense] | Edition: [CE / Plus / Business]
Version: [x.y.z] | Supported: [yes / EOL]
Deployment: [standalone / CARP HA pair (+ secondary)]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[config.xml current and applied; no in-flight staged change; CARP secondary in sync.]

ADMIN-PLANE EXPOSURE:
- webGUI: [protocol / port / bound interface | WAN-facing? ]
- SSH: [off / on | key-only? | source]
- Anti-lockout rule: [present + LAN-scoped / disabled]
- API: [OPNsense keys / pfSense Plus tokens / none] | privilege: [scoped / full-admin]
- Privilege separation: [roles / shared admins] | 2FA: [on / off / n/a]

RULEBASE SUMMARY:
- Filter rules: [n] (allow: [n] | block/reject: [n] | disabled: [n] | floating: [n])
- Aliases: [n] (stale / broad: [list])
- Port forwards: [n] (WAN-exposed: [list]) | outbound NAT: [auto / hybrid / manual] | 1:1: [n]

SECURITY SERVICES:
- IDS/IPS: [Suricata / Snort | inline / legacy | interfaces covered] | rulesets: [current / stale]
- DNS filtering: [pfBlockerNG / Unbound blocklists / none] | feeds: [current / stale]
- Unbound: [DNSSEC on/off | rebinding protection on/off | DoT forwarding]
- Packages / plugins: [count | unmaintained: list]

VPN / CERTIFICATES:
- OpenVPN / WireGuard / IPsec: [present | cipher / proposal notes]
- Certificate manager: [expiring / weak-key / SHA-1 certs | webGUI cert]

CURRENCY / BACKUP:
- Version / EOL: [build | supported?] | patches: [applied / pending]
- config.xml backup: [encrypted off-box / unencrypted / on-box only / none]

CARP HA STATUS:
- CARP VIPs: [configured / issue] | pfsync: [on dedicated iface / issue]
- XMLRPC config sync: [in sync / drift] | version parity: [matched / mismatched]

EVIDENCE: [config.xml extract refs / pfctl output / webGUI screenshots / REST API GET]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Rule / object: [name / interface / position] | Src -> Dst: [..] | Service: [..]
Issue: [problem] -> Recommendation: [remediation]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list, including match-count and CARP-sync verification]
ROLLBACK: [config.xml restore ref or per-rule revert step]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **Auditing the staged config, not the applied one:** a webGUI change that is saved but not applied is not in the running ruleset. Audit the applied `config.xml`, and on a CARP pair confirm the secondary received it.
- **Trusting the anti-lockout rule blindly:** it is a convenience that permits webGUI / SSH from LAN. Confirm it is scoped to the management interface and never widened to WAN; if disabled, confirm an explicit management rule exists.
- **Missing floating-rule precedence:** floating rules with `quick` are evaluated before interface rules and match-and-stop. An audit that reads only interface rules can miss a floating rule that already permits or blocks the traffic.
- **Crediting a port forward as safe because "it is just a port forward":** the exposure is set by the associated firewall rule's source scope, not by the NAT itself. Read the rule, not just the mapping.
- **Treating IDS/IPS as on when it is in legacy mode:** alert-only detects without blocking. Confirm inline / IPS mode where blocking is intended.
- **Ignoring `config.xml` as a secret:** the backup carries private keys and PSKs. An unencrypted backup on an operator laptop is a credential exposure, not just a recovery convenience.
- **Assuming pfSense and OPNsense are identical:** they share ~90% of the surface, but the default IDS engine, DNS-blocklist tooling, package / plugin system, and REST API model differ. Confirm which platform and edition before quoting a menu path or a default.
- **Version-upgrade impact:** a major upgrade can change package compatibility and defaults. Export `config.xml` before upgrading; post-upgrade verify rules, NAT, IDS/IPS bindings, and CARP sync preserved, and upgrade HA nodes in sequence.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the pfSense / OPNsense specialist. Apply the nine-element response contract to every state-changing recommendation.
- `acl-rule-analysis` -- vendor-agnostic ACL / rulebase methodology, hit-count staleness bands, severity-pattern catalogue. Run first for cross-vendor estate work, then this skill for the `pf` deep-dive.
- `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `cisco-firewall-audit`, `checkpoint-firewall-audit`, `sophos-firewall-audit` -- sibling Stage 3 specialists; sequence vendor-by-vendor when auditing a mixed estate.
- `vpn-tunnel-troubleshooting` -- IPsec / OpenVPN / WireGuard site-to-site and remote-access VPN, IKE state-machine analysis. This skill stops at the firewall-side VPN configuration and certificate hygiene.
- `network-detection-response` -- when IDS/IPS visibility and east-west segmentation overlap with NDR and micro-segmentation questions.
- `bgp-analysis`, `igp-routing-analysis` -- when a firewall or NAT change risks routing or gateway-failover behaviour, pause and run those skills first.
- `secrets-hygiene` -- the `config.xml` export, VPN PSKs and private keys, API keys, and SNMP / backup credentials all fall under the patterns there.
- `completion-gate` Layer 3 -- every state-changing change requires fresh post-check evidence (config backup ref recorded, match-count and CARP-sync deltas confirmed, ruleset currency re-verified) before claiming "rule deployed".
- `plan-time-tooling` -- every state-changing audit recommendation fires `engineering:deploy-checklist` at plan time.
- `systematic-debugging` -- Phase 1 boundary evidence (which interface, which rule, which NAT mapping, which floating rule) before any change.
- `oncall-runbooks` -- incident classification when audit findings overlap with active incidents.

## Red flags (about-to-act warnings)

- About to expose the webGUI or SSH on the WAN interface "temporarily" for remote administration; use a VPN instead.
- About to add a port forward with an `any` source, or expose RDP / SMB / a database port directly to the WAN.
- About to disable the anti-lockout rule without first confirming an explicit management rule exists.
- About to switch IDS/IPS to legacy / alert-only "to reduce noise" (this removes the block).
- About to delete a rule with a non-zero match count without identifying the traffic source.
- About to apply a `config.xml` change on a CARP pair without confirming the secondary syncs.
- About to upgrade one CARP node and leave the pair on mismatched versions.
- About to store or send an unencrypted `config.xml` backup (it contains private keys and PSKs).
- About to trust that pfSense and OPNsense behave identically on a point where they differ (IDS engine, blocklist tooling, API model); confirm the platform first.
- About to skip the version / EOL check because the firewall "feels fine".

## Bottom line

Audit the FreeBSD / `pf` architecture, not just the open ports. The architecture is the `pf` ruleset (per-interface plus floating rules, aliases, NAT, default-deny) plus the security-services layer (IDS/IPS, DNS filtering, Unbound and DHCP hardening, package posture) plus VPN and certificate hygiene, with the single `config.xml` holding the entire configuration (and its secrets) and CARP / pfsync / XMLRPC providing HA. Diagnose-first via a read-only `config.xml` export, the webGUI, `pfctl` show commands, or a REST API GET; treat the config export as a secret; map every state-changing recommendation onto the nine-element response contract. Severity rankings drive remediation cadence (CRITICAL 30 d, HIGH 90 d, clean 180 d). The two audit smells most specific to pfSense / OPNsense are a wide-open port forward (the NAT looks innocuous; the associated rule's source is what exposes the host) and an unencrypted `config.xml` backup (the whole firewall, keys included, in one file); check both first. Confirm which platform and edition you are on before quoting any default or menu path.
