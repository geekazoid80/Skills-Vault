# Cisco Secure Client (AnyConnect) remote-access deep-dive

Deep reference for Cisco Secure Client, formerly AnyConnect Secure Mobility Client: the endpoint remote-access VPN, its module architecture, authentication, per-session access control (DAP), split tunnelling, Always-On, Trusted Network Detection, posture, deployment, and troubleshooting. The main `vpn-tunnel-troubleshooting` body covers site-to-site IPsec, WireGuard, and DMVPN/ADVPN; this reference is the endpoint remote-access counterpart. Load it when the question is AnyConnect/Secure Client specifically (DAP, TND, Always-On, per-app VPN, SAML SSO, ISE/Umbrella integration, DART).

## Rebranding

- AnyConnect 4.x became Cisco Secure Client 5.x in 2022.
- Package names moved from `anyconnect-*` to `cisco-secure-client-*`.
- The profile XML still uses the AnyConnect schema for backward compatibility, and the headend CLI still uses `anyconnect` in many commands.
- Current release as of early 2026: 5.1.14 (MR14, cloud management default, flexible deploy).

## VPN protocols

### SSL/TLS with DTLS (primary)

- **TLS (TCP 443)**: control channel and data fallback. TLS 1.2 minimum; TLS 1.3 on ASA 9.10.1+.
- **DTLS (UDP 443)**: preferred data transport. Avoids TCP-over-TCP retransmission and gives roughly 30 to 50 per cent throughput improvement over TLS-only. DTLS 1.0 by default; DTLS 1.2 on ASA 9.10.1+.
- Flow: the client connects over TCP/443 (TLS), the headend advertises DTLS parameters in the TLS channel, the client opens a UDP/443 DTLS session in parallel, data rides DTLS with control on TLS, and data falls back to TLS automatically if UDP/443 is blocked.

### IPsec/IKEv2

- Supported on FTD headends. IKEv2 for key exchange, ESP tunnel for data.
- Better throughput than SSL for high-volume flows. IKEv2 is attempted first where configured, then falls back to SSL.

## Module architecture

| Module | Function | Typical licence |
|---|---|---|
| VPN | Core remote access | Base |
| Umbrella Roaming Security | DNS-layer security off-network | Umbrella subscription |
| AMP Enabler | Deploy Cisco Secure Endpoint | Secure Endpoint |
| ISE Posture | Endpoint compliance for ISE NAC | ISE Premier |
| Secure Firewall Posture | Posture for ASA/FTD (formerly HostScan) | Secure Client Plus/Premier |
| NVM | Endpoint flow telemetry (IPFIX) | NVM |
| ZTA | Per-app zero-trust access | Cisco Secure Access |
| Start Before Login | VPN before Windows login | Included |

## Headend platforms

| Platform | Protocols | Management |
|---|---|---|
| Cisco ASA | SSL/DTLS, IKEv2 | ASDM, CLI, CDO |
| Cisco FTD | SSL/DTLS, IKEv2 | FMC, FDM, CDO |
| Catalyst SD-WAN | SSL (client VPN) | vManage |
| Cisco Secure Access | Cloud ZTNA + VPN | Dashboard |

The headend (ASA vs FTD) and its version decide which features are available; identify it first when triaging.

## Authentication

- **SAML 2.0 (recommended for SSO)**: Azure AD/Entra ID, Okta, Ping Identity. The profile setting `<UseExternalBrowser>true</UseExternalBrowser>` enables the system browser for true SSO (biometric, hardware tokens, existing sessions) rather than the embedded browser.
- **Certificate + SAML (dual auth)**: `authentication saml certificate` on the tunnel-group satisfies both device trust (certificate) and user identity (SAML).
- **RADIUS with MFA (Duo)**: a Duo Authentication Proxy intercepts RADIUS, does primary AD auth, then a second factor (push, TOTP, SMS).
- **LDAP / Active Directory**: direct bind for user auth and group lookup.

## DAP (Dynamic Access Policies)

DAP adjusts per-session access based on endpoint attributes and group membership, evaluated after authentication:

1. The user authenticates.
2. The ASA evaluates all DAP records against the user and endpoint attributes.
3. Matching records are merged/aggregated.
4. The final policy applies ACLs, group policies, bookmarks, or terminates the session.

Key attributes include `endpoint.os.version`, `endpoint.av.product-name`, `endpoint.disk.encrypted`, `endpoint.anyconnect.clientversion`, `aaa.ldap.memberOf`, and `aaa.radius.class`. A common pattern is to terminate the session when disk encryption is absent (`action terminate` on a record conditioned on `endpoint.disk.encrypted = false`).

**Watch:** DAP takes precedence over group policy, so a split-tunnel or ACL problem that "should work" per the group policy is often a DAP override. Check DAP before the group policy.

## Split tunnelling

- **Include (tunnel specified)**: only named subnets ride the VPN, everything else goes local. `split-tunnel-policy tunnelspecified` with a `split-tunnel-network-list`.
- **Exclude (exclude specified)**: all traffic rides the VPN except named destinations. `split-tunnel-policy excludespecified`.
- **Dynamic (FQDN-based)**: exclude domains by name, for example `anyconnect-custom dynamic-split-exclude-domains value "zoom.us,*.microsoft.com"`, so SaaS traffic bypasses the tunnel.
- **Per-app VPN (mobile)**: on iOS/Android only named apps use the VPN, configured via MDM.

## Always-On VPN and Trusted Network Detection

**Always-On** auto-connects the VPN and blocks traffic when it is disconnected (or fails open, per policy):

```xml
<AlwaysOn>true</AlwaysOn>
<AllowVPNDisconnect>false</AllowVPNDisconnect>
<CaptivePortalRemediationBrowserFailover>true</CaptivePortalRemediationBrowserFailover>
```

Configure captive-portal remediation, or hotel and airport captive portals will lock users out.

**Trusted Network Detection (TND)** auto-connects or disconnects based on network trust, using DNS domain match, DNS server match, or a trusted HTTPS server probe. It is client-side only (no headend config), triggers only on network-change events, and does not tear down a manually initiated VPN. The ZTA module pauses on a trusted network.

```xml
<TrustedNetworkPolicy>Disconnect</TrustedNetworkPolicy>
<UntrustedNetworkPolicy>Connect</UntrustedNetworkPolicy>
<TrustedDNSDomains>corp.example.com</TrustedDNSDomains>
<TrustedDNSServers>10.1.0.1,10.1.0.2</TrustedDNSServers>
```

## Posture

- **Secure Firewall Posture (HostScan)**: checks OS version, AV presence and definitions, personal firewall, disk encryption, registry keys, and process presence; results are evaluated in DAP on the ASA.
- **ISE Posture**: full ISE-based compliance with RADIUS CoA for dynamic policy. The client checks compliance, ISE returns Compliant / Non-Compliant / Unknown, CoA pushes the updated policy, and non-compliant endpoints hit a remediation portal or quarantine. Requires ISE Premier.

## Deployment

- **Web deploy**: the user browses to the headend (for example `https://vpn.example.com`) and downloads the client. `anyconnect image disk0:/cisco-secure-client-*.pkg 1` plus `anyconnect enable` under `webvpn`.
- **Pre-deploy (MDM/SCCM/GPO)**: silent MSI/PKG install, for example `msiexec /package cisco-secure-client-*-core-vpn-predeploy-k9.msi /quiet /norestart`, with separate module MSIs (ISE posture, etc.).

## Platform support (5.1.x, indicative)

Windows 10/11 x64 fully supported; Windows 11 ARM64 native binaries with Start Before Login; macOS 12 to 15 via the Network Extension framework; Linux (RHEL, Ubuntu) core VPN plus select modules; iOS 16+ per-app VPN, IKEv2, SSL; Android 10+ SSL/DTLS. Note that web deploy from 5.1.0.x fails on ARM64 Windows 11; use pre-deploy or 5.1.1+.

## Troubleshooting

**DART (Diagnostic and Reporting Tool)** is the primary tool: it collects all module logs plus system info into a zip. Windows `%ProgramFiles%\Cisco\Cisco Secure Client\DART\dartui.exe`; macOS `/Applications/Cisco/DART.app`.

Common issues:

- **Certificate invalid**: the headend certificate is not trusted; deploy the CA via GPO/MDM or use a public certificate.
- **DTLS unavailable**: UDP/443 is blocked, so it falls back to TLS with a large throughput drop; open UDP/443 on the firewall and NAT path.
- **Split tunnel not working**: DAP is overriding the group policy; check `show vpn-sessiondb detail anyconnect filter name <user>` and the DAP records.
- **SAML failure**: check IdP metadata, signing-certificate expiry, and clock sync.
- **Connection stuck**: check TCP/443 and UDP/443 reachability; run DART for `vpn.log`.

ASA debug and show commands (read-only show first, per the skill's diagnose-first rule):

```
show vpn-sessiondb anyconnect                          ! active sessions
show vpn-sessiondb detail anyconnect filter name <user>
show webvpn group-policy                                ! group-policy summary
show run tunnel-group <name>
debug webvpn anyconnect 255                             ! Secure Client protocol
debug webvpn saml 25                                    ! SAML flow
debug aaa authentication 255                            ! AAA events
debug aaa authorization 255                             ! authorization / DAP
```

## Common pitfalls

1. **DTLS blocked by a corporate firewall**: many firewalls block UDP/443; performance collapses in TLS-only mode. Ensure UDP/443 is open.
2. **DAP overriding split tunnel**: DAP rules take precedence over group policy; check DAP first when split tunnelling misbehaves.
3. **SAML certificate expiry**: SAML signing certificates expire; set renewal reminders (this is credential lifetime, so it also falls under `secrets-hygiene`).
4. **Always-On with captive portals**: without `CaptivePortalRemediationBrowserFailover`, hotel/airport portals lock the user out.
5. **ARM64 Windows 11 web deploy**: fails on 5.1.0.x; use pre-deploy or upgrade to 5.1.1+.

## Attribution and references

Re-authored and genericised from the MIT-licensed `chrishuffman5/domain-expert` `plugins/networking/skills/cisco-secure-client` (SKILL.md + `references/architecture.md`); the upstream's agent-persona framing was removed and the technical content retained. Cisco product behaviour, CLI syntax, and version specifics are summarised from Cisco's public Secure Client, ASA, FTD, and ISE documentation and cited, not reproduced; confirm exact syntax and per-version feature support against the Cisco configuration guides for your headend and release.
