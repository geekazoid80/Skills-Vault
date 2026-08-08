---
name: vpn-tunnel-troubleshooting
description: Use for any VPN tunnel diagnosis, design review, or interop work covering IPsec / IKEv2 (Cisco IOS-XE / ASA / FTD; Juniper JunOS; PAN-OS; FortiOS; StrongSwan), WireGuard (Linux kernel module; userspace via wireguard-go / BoringTun; orchestrated via Tailscale / Headscale / Netmaker / Firezone / NetBird), DMVPN, ADVPN, route-based (VTI) vs policy-based (crypto map), crypto algorithm selection (CNSA 1.0 today; CNSA 2.0 post-quantum transition by 2033), and multi-vendor interop. Triggers include "VPN tunnel down", "IKE SA stuck", "MM_NO_STATE", "MM_KEY_EXCH stuck", "NO_PROPOSAL_CHOSEN", "TS_UNACCEPTABLE", "AUTHENTICATION_FAILED", "INVALID_KE_PAYLOAD", "Phase 2 not coming up", "proxy ID mismatch", "PFS mismatch", "encap counter zero", "decap zero", "tunnel flapping", "DPD declaring peer dead", "rekey failing", "NAT-T not activating", "MTU fragmentation", "WireGuard handshake stuck", "wg show no latest-handshake", "AllowedIPs overlap", "PersistentKeepalive missing", "wg key distribution at scale", "DMVPN phase 3 shortcuts", "ADVPN spoke-to-spoke", "VTI vs crypto map", "IKEv2 hybrid post-quantum", "ML-KEM-1024 transition", "FortiClient EMS endpoint posture", "AnyConnect remote access", "Tailscale ACL", "Netmaker mesh", "VPN architecture comparison", "site-to-site vs remote-access", "crypto algorithm 2025", "WireGuard reference config", "wg server config example", "wg client config example", "DPD failover test", "test peer-down DPD", "B2B tunnel stays down after peer DELETE", "always-on IPsec will not auto-recover", "closeaction=restart pairing", "dpdaction vs closeaction asymmetric recovery", "peer-initiated DELETE leaves charon silent", "ipsec statusall misread Connections vs Security Associations", "strongSwan tunnel down 8 hours after MikroTik link flap". Six-step IKE diagnostic procedure (vahagn) plus a WireGuard sub-procedure plus VPN technology selection / crypto suite tables. Diagnose-first; read-only `show` / `diagnose` / `wg show` queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite/vpn-ipsec-troubleshooting (Apache-2.0); IPsec deep-dive, WireGuard expert content, and VPN architecture umbrella folded from chrishuffman5/domain-expert/skills/networking/vpn (MIT). Cisco Secure Client (AnyConnect) remote-access deep-dive (DAP, TND, Always-On, per-app VPN, SAML SSO, ISE/Umbrella, DART) folded as references/cisco-secure-client-anyconnect.md; FortiClient EMS endpoint posture cross-referenced from fortigate-firewall-audit.
license: Apache-2.0
metadata:
  version: 1.3.0
---

# VPN tunnel troubleshooting (IPsec, WireGuard, DMVPN, ADVPN)

State-machine-driven diagnosis for VPN tunnels across the IPsec / IKEv2 family (Cisco / Juniper / PAN-OS / FortiOS / StrongSwan), WireGuard (kernel and userspace), and the dynamic-mesh derivatives (DMVPN, ADVPN). Reading the current SA or handshake state and mapping it to the negotiation phase isolates the failure domain without guesswork. Per-vendor commands are labelled **[Cisco]**, **[JunOS]**, **[PAN-OS]**, **[FortiGate]**, **[StrongSwan]**, **[WireGuard]**.

> **Skill marker**: When applying this skill, begin your reply with `[skill: vpn-tunnel-troubleshooting]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the VPN estate (technology mix, peer topology, hub-and-spoke versus full-mesh, crypto suite policy) before troubleshooting. Only ask the user for information not already covered or specific to this tunnel.

Before troubleshooting, understand:

1. **Tunnel technology and topology**
   - VPN technology (IPsec / IKEv2, IPsec / IKEv1 legacy, WireGuard, DMVPN, ADVPN, GRE+IPsec, SSL-VPN)?
   - Peer count (point-to-point, hub-and-spoke, mesh)?
   - Vendor(s) at each end (interop combinations matter)?

2. **Symptom and timing**
   - Phase 1 / Phase 2 negotiation failure, tunnel up but no traffic, or intermittent flap?
   - When did the symptom start; what correlates (config change, peer-end change, ISP path event)?
   - Affecting one peer or many?

3. **Evidence and crypto posture**
   - Read-only access to IKE / IPsec state on both ends (or just one)?
   - Crypto policy in use (CNSA, modern PFS group, legacy)?
   - Recent change history on either peer?

---

## Scope and when to use

- VPN tunnel reported down or not passing traffic.
- IKE SA stuck in a non-established state (MM_NO_STATE, AG_INIT_EXCH, SA_INIT_SENT, MM_KEY_EXCH).
- Phase 1 establishes but Phase 2 / Child SA fails.
- Tunnel established but encap / decap counters not incrementing.
- After config changes to crypto proposals, peer addresses, PSKs, certificates, or proxy IDs.
- Intermittent flapping, unexpected SA rekey failures, NAT-T issues, DPD premature failover.
- WireGuard handshake never completes (`wg show` shows no `latest-handshake`).
- WireGuard tunnel up but specific destinations unreachable (AllowedIPs scoping).
- Multi-vendor interop changes (proposal mismatch, PFS mismatch, traffic-selector mismatch, certificate EKU).
- Architecture / technology selection (IPsec vs WireGuard vs SSL VPN; site-to-site vs remote-access; full-mesh vs hub-spoke vs DMVPN / ADVPN).
- Crypto algorithm selection in the CNSA 1.0 / CNSA 2.0 (post-quantum) transition window.

For the firewall-side policy view of VPN traffic, see `cisco-firewall-audit` (ASA / FTD remote-access posture), `palo-alto-firewall-audit` (GlobalProtect zones), `fortigate-firewall-audit` (FortiClient EMS endpoint posture, FortiOS phase1 / phase2 interface). For the broader umbrella response contract, see `multi-vendor-network-ops`.

## Prerequisites

- SSH or console access to the VPN gateway (read-only privilege sufficient for diagnosis).
- At least one tunnel configured on the device.
- Knowledge of expected tunnel topology: peer IPs, protected networks (proxy IDs / traffic selectors / WireGuard AllowedIPs), intended crypto parameters, IKE version (IKEv1 vs IKEv2) per tunnel, route-based (VTI) vs policy-based (crypto map) intent.
- For WireGuard: knowledge of the public-key inventory (peer keys), AllowedIPs map per peer, ListenPort, NAT posture (PersistentKeepalive expectations).
- For DMVPN / ADVPN: knowledge of hub address(es), NHRP network ID, mGRE tunnel source / destination, dynamic-routing protocol over the tunnel (EIGRP / OSPF / BGP).

## VPN technology selection

When the question is architectural ("which VPN should we use?", "compare IPsec vs WireGuard for site-to-site"), apply this rough matrix before diving into per-technology troubleshooting.

| Aspect | IPsec / IKEv2 | WireGuard | Cisco Secure Client (AnyConnect) |
|---|---|---|---|
| Best for | Multi-vendor site-to-site, hub-spoke with dynamic routing, DMVPN / ADVPN, compliance estates | Linux-to-Linux site-to-site, dev / IT VPNs, container networking, mesh (Tailscale / Headscale / Netmaker / NetBird) | Enterprise remote access with full posture / NAC / ZTNA in a Cisco ecosystem |
| Configuration | Many knobs (proposals, transforms, DH groups, traffic selectors); proposal mismatch is the most common failure | Fixed crypto, no negotiation; key + AllowedIPs + Endpoint | Headend on ASA / FTD; client software on endpoints; SAML auth via system browser |
| Performance | Hardware acceleration on most enterprise platforms | Kernel-space; ChaCha20-Poly1305; ~near-wire-speed; 1-RTT handshake | DTLS for media efficiency |
| Auth | PSK (small estates), certificates (large estates), EAP for remote access | Public-key only; PSK adds post-quantum hedge; SSO via wrapper (Firezone, Tailscale, wg-access-server) | SAML / RADIUS / certificates with DAP for per-session policy |
| Transport | UDP/500 + UDP/4500 (or ESP protocol 50); often blocked by restrictive firewalls | UDP only; no native TCP fallback (use udp2raw / wstunnel / DERP) | TLS over TCP fallback to DTLS |
| Scale | Hundreds of S2S tunnels per hub; thousands of remote-access users | Millions of peers in mesh (Tailscale-style) | Thousands of concurrent users per headend |
| Native enterprise mgmt | Yes (FMC, Panorama, FortiManager) | No (key distribution requires orchestration beyond ~20 peers) | Yes (Cisco ISE / FMC / Umbrella) |

Rule of thumb: pick IPsec for cross-vendor compliance; pick WireGuard when both ends are Linux you control or when an orchestration platform is in scope; pick AnyConnect / GlobalProtect / FortiClient for endpoint VPN with full NAC / posture.

## Crypto algorithm selection

### CNSA 1.0 (use today)

| Component | Algorithm | Notes |
|---|---|---|
| IKE encryption | AES-256-GCM (or AES-256-CBC) | GCM preferred (AEAD; no separate integrity in proposal) |
| IKE integrity | SHA-384 (with CBC) | With GCM, use explicit PRF instead |
| PRF | PRF_HMAC_SHA2_384 | Required with AEAD encryption |
| DH group | Group 20 (ECP-384 / P-384) | Group 19 (P-256) minimum |
| ESP encryption | AES-256-GCM-16 | AEAD; no separate integrity |
| ESP integrity | SHA-256 / SHA-384 (with CBC only) | Not used with GCM |
| PFS | Group 20 (ECP-384) | Always enable PFS on Child SAs |

### CNSA 2.0 transition (by 2033)

| Component | Algorithm | Notes |
|---|---|---|
| Key exchange | ML-KEM-1024 (FIPS 203) | Hybrid: ML-KEM-1024 + ECP-384 during the transition window |
| Digital signatures | ML-DSA-87 (FIPS 204) | For certificate authentication |
| Hash / PRF | SHA-384 | Still compliant |

### Avoid (always)

DH groups 1, 2, 5, 22, 23, 24 (broken / weak); MD5 or SHA-1 for integrity / PRF; DES or 3DES; IKEv1 (disable where any peer supports IKEv2).

## Procedure (IPsec / IKEv2)

The six-step state-machine flow. Each step builds on prior data.

### Step 1: check IKE SA state

| Vendor | Command |
|---|---|
| **[Cisco]** | `show crypto isakmp sa` (IKEv1); `show crypto ikev2 sa` (IKEv2) |
| **[JunOS]** | `show security ike security-associations` |
| **[PAN-OS]** | `show vpn ike-sa` |
| **[FortiGate]** | `diagnose vpn ike gateway list` |
| **[StrongSwan]** | `swanctl --list-sas` |

Record each SA: peer address, IKE version, state, role (initiator / responder), lifetime remaining. Compare against expected topology; every configured peer should have an IKE SA. Missing SAs mean the tunnel was never initiated or was cleared.

For IKEv1 Cisco state names:

- **MM_NO_STATE** -- no exchange started, or failed at SA proposal.
- **MM_SA_SETUP** -- SA proposal accepted; DH exchange next.
- **MM_KEY_EXCH** -- DH complete; authentication next.
- **MM_KEY_AUTH** -- authenticated; completing.
- **QM_IDLE** -- Phase 1 complete; ready for Phase 2.

### Step 2: diagnose stuck or failed state

**IKEv1 Main Mode:**

- **MM_NO_STATE:** no response from peer. Check UDP/500 reachability, firewall permits IKE, peer has matching crypto map, peer IKE process running.
- **MM_SA_SETUP:** DH group mismatch. Align DH groups in proposals.
- **MM_KEY_EXCH:** authentication failure. PSK mismatch, certificate chain invalid, peer ID type mismatch (IP vs FQDN).
- **QM_IDLE with no Phase 2:** no interesting traffic, proxy ID mismatch, transform set mismatch.

**IKEv2 notify codes:**

- **No SA_INIT response:** peer unreachable on UDP/500 or 4500, or no matching IKE proposal.
- **NO_PROPOSAL_CHOSEN:** no overlapping crypto suite. Compare encryption, PRF, integrity, DH on both sides.
- **INVALID_KE_PAYLOAD:** DH group mismatch. Responder returns its preferred group; initiator should retry automatically.
- **AUTHENTICATION_FAILED:** PSK mismatch or certificate validation failure (chain, OCSP / CRL, SAN).
- **TS_UNACCEPTABLE:** traffic-selector (proxy ID) mismatch.

| Vendor | Detail command |
|---|---|
| **[Cisco]** | `show crypto isakmp sa detail`; `show crypto ikev2 sa detail` |
| **[JunOS]** | `show security ike security-associations detail` |
| **[PAN-OS]** | `show vpn ike-sa gateway <name>` |
| **[FortiGate]** | `diagnose vpn ike gateway list name <name>`; `diagnose debug application ike -1` |
| **[StrongSwan]** | `swanctl --log` |

### Step 3: verify crypto parameter alignment

| Parameter | Must match? | Notes |
|---|---|---|
| Encryption algorithm | Yes | AES-256-GCM preferred; identical on both sides. |
| Hash / integrity | Yes | SHA-256 / 384; not used with AEAD. |
| DH group | Yes | Group 19 / 20; align across vendors. |
| PRF (IKEv2) | Yes | Required with AEAD. |
| Authentication method | Yes | PSK, RSA-sig, ECDSA. |
| SA lifetime | Negotiable | Shorter wins; large discrepancies cause rekey issues. Stagger by 5 to 10% to avoid simultaneous rekey. |
| IKE version | Yes | Both peers same. |

### Step 4: validate Phase 2 / Child SA

| Vendor | Command |
|---|---|
| **[Cisco]** | `show crypto ipsec sa` |
| **[JunOS]** | `show security ipsec security-associations` |
| **[PAN-OS]** | `show vpn ipsec-sa` |
| **[FortiGate]** | `diagnose vpn tunnel list` |
| **[StrongSwan]** | `swanctl --list-sas` |

Verify SA state (active), SPI values (inbound and outbound present), proxy IDs / traffic selectors match intended protected networks, encapsulation mode, PFS. Common Phase 2 failures: transform set mismatch; proxy ID mismatch (most common multi-vendor interop failure); PFS DH group mismatch; no interesting traffic (policy-based).

### Step 5: assess tunnel health

Encap / decap counter analysis:

| Encap | Decap | Interpretation |
|---|---|---|
| Incrementing | Zero | Outbound traffic sent; nothing returned. Remote peer, routing, or ACL. |
| Zero | Incrementing | Receiving but not sending. Local routing or crypto-ACL. |
| Both incrementing | Tunnel passing traffic in both directions. |
| Both zero | Tunnel established but no matching traffic. Verify routing and proxy IDs. |
| Encrypt / decrypt errors rising | Crypto processing failures. Hardware engine? |
| Replay failures | Anti-replay window exceeded. Reordering, QoS, async routing. Increase window to 512 or 1024. |

DPD: verify probes are exchanged. DPD declaring peer dead indicates loss of reachability, not a crypto problem. NAT-T (UDP/4500) keepalive must be shorter than the NAT device's UDP session timeout (typical NAT timeout 60 to 300 s; keepalive 10 to 30 s).

### Step 6: route-based vs policy-based and dynamic-mesh patterns

Route-based VPN (VTI) creates a routable tunnel interface; supports dynamic routing (OSPF / BGP) over the tunnel; preferred over crypto map for new builds.

- **[Cisco IOS-XE]** `crypto ikev2 proposal` + `crypto ikev2 profile` + `crypto ipsec transform-set` + `crypto ipsec profile` + `interface Tunnel<n> ... tunnel mode ipsec ipv4 ... tunnel protection ipsec profile`.
- **[PAN-OS]** IKE Crypto Profile + IKE Gateway + IPsec Crypto Profile + IPsec Tunnel (binds to a `tunnel.<n>` interface).
- **[FortiOS]** `config vpn ipsec phase1-interface` plus `config vpn ipsec phase2-interface`. Route-based by default.
- **[StrongSwan]** `swanctl.conf` `connections{}` + `children{}`.

Dynamic-mesh VPNs:

- **DMVPN (Cisco):** mGRE + IPsec + NHRP + dynamic routing. Phase 1 = all via hub; Phase 2 = NHRP shortcuts; Phase 3 = NHRP shortcut routing for direct spoke-to-spoke. Scales to thousands of spokes.
- **ADVPN (Fortinet):** IKEv2 extensions for spoke-to-spoke shortcuts. Hub: `set auto-discovery-sender enable`; spoke: `set auto-discovery-receiver enable`. ADVPN 2.0 (FortiOS 7.6+) enhances shortcut management for multiple underlays.

## WireGuard troubleshooting

WireGuard's design is opposite to IPsec's: stateless, fixed crypto (Curve25519 + ChaCha20-Poly1305 + BLAKE2s + HKDF), no negotiation. Failures concentrate in three places: connectivity (UDP can reach the peer endpoint), key alignment (peer public keys match), and AllowedIPs (the routing-and-source-filter combo).

### Step W1: check handshake status

```
wg show
wg show wg0 latest-handshakes
wg show wg0 transfer
wg show wg0 endpoints
```

A peer with no `latest-handshake` value (or a value over 180 s old) is not connected. WireGuard rotates session keys every 180 s automatically; a fresh handshake on every keepalive interval is normal.

### Step W2: classify the failure

- **No handshake at all:** the initiator has not received a response. Check UDP reachability to the listed Endpoint; confirm the peer's `wg0` is up and ListenPort matches; confirm public-key alignment (each side's `[Peer] PublicKey` must match the other side's interface public key).
- **Handshake completes but traffic fails:** AllowedIPs mismatch. Check that each end's `AllowedIPs` includes the LAN subnets the peer should reach. AllowedIPs is BOTH the outbound routing entry AND the inbound source filter; a packet from a source not listed in the peer's AllowedIPs is dropped silently.
- **Behind NAT and goes silent after a few minutes:** missing PersistentKeepalive. Set `PersistentKeepalive = 25` on the NAT-side peer; the NAT mapping will expire otherwise.
- **Full tunnel and DNS leaks:** with `AllowedIPs = 0.0.0.0/0`, set `DNS = ...` in the `[Interface]` section so DNS goes through the VPN.
- **Throughput stalls on large transfers:** MTU. WireGuard overhead is ~60 bytes (20 IP + 8 UDP + 32 WG header + 16 Poly1305 tag). Set MTU to 1420 on standard Ethernet; 1432 on PPPoE; 1280 for IPv6 safe.
- **AllowedIPs overlap between two peers:** WireGuard cannot route to both. Each peer must have unique AllowedIPs.

### Reference configs (minimal)

When triaging a peer's config, comparing it against a known-good reference is faster than reading the failure backwards. Two skeletons follow; substitute real keys and addresses.

Server (`/etc/wireguard/wg0.conf` on the Linux gateway; assumes eth0 is the WAN-facing interface and the box NATs spoke traffic out to the internet):

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server_private>
MTU = 1420

PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <client_public>
PresharedKey = <psk>
AllowedIPs = 10.0.0.2/32
```

Client (full-tunnel; sends all traffic via the VPN; DNS forced through the tunnel to avoid leaks):

```ini
[Interface]
Address = 10.0.0.2/32
PrivateKey = <client_private>
DNS = 10.0.0.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = <server_public>
PresharedKey = <psk>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

For split-tunnel, narrow `AllowedIPs` on the client to the protected ranges only (e.g. `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16`); drop the DNS line if the host's normal resolver should keep handling everything outside the tunnel. `PersistentKeepalive = 25` is required on any NAT-side peer; drop it on peers that have a public IP and don't sit behind NAT.

### Step W3: useful operational commands

```
wg-quick up wg0                           # bring up from /etc/wireguard/wg0.conf
wg-quick down wg0                         # tear down
wg syncconf wg0 <(wg-quick strip wg0)     # reload config without restart
wg set wg0 peer <pubkey> endpoint <ip>:<port>
wg set wg0 peer <pubkey> remove
systemctl status wg-quick@wg0
```

WireGuard intentionally emits no logs of its own. Monitor via OS-level tools: `iptables -j LOG`, `tcpdump -i wg0`, kernel ring buffer (`dmesg | grep -i wireguard`).

### Step W4: management-platform considerations

| Platform | Use case | Note |
|---|---|---|
| Tailscale | Managed mesh; MagicDNS; ACLs; DERP relay | Proprietary; free tier; SSO out of the box |
| Headscale | Self-hosted Tailscale-compatible coordination | Open source; same client; no SSO without addons |
| Netmaker | Kernel-space mesh; REST API; ~8 Gbps | Open source; mesh design |
| Firezone | Web UI; OIDC / SAML; per-user policies | Open source; remote-access shape |
| NetBird | Zero-config mesh; STUN / TURN NAT traversal | Open source; SSO supported |

Without orchestration, manual key distribution becomes unmanageable beyond ~20 peers; choose a platform before scaling.

PSK for post-quantum hedge: add `PresharedKey = $(wg genpsk)` to each `[Peer]` block. The 256-bit symmetric key is mixed into the handshake derivation; even if Curve25519 is broken, the attacker still needs the PSK.

## Severity table (cross-technology)

| Finding | Severity | Rationale |
|---|---|---|
| IKE proposal includes DES / 3DES or DH group 1 / 2 / 5 | Critical | Broken cryptography; tunnel must be rebuilt with strong proposals. |
| IKE / Phase 2 mismatch on production tunnel | Critical | Tunnel is down; traffic affected. |
| WireGuard handshake never completes on production peer | Critical | Tunnel is down; traffic affected. |
| AEAD encryption with redundant integrity algorithm in IKE proposal | High | Some peers reject; remove integrity when using GCM (use explicit PRF). |
| PSK reused across multiple tunnels | High | One leak compromises every tunnel with the same key. |
| Certificate expiry within 30 days | High | Tunnel will drop on expiry; renewal automation required. |
| NAT-T disabled with NAT in path | High | Tunnel will not establish or will fail intermittently. |
| Encap incrementing, decap zero | High | Asymmetric path or remote-side return route broken. |
| Tunnel flapping due to DPD with healthy underlying path | Medium | DPD timer too aggressive or QoS deprioritising IKE. |
| Lifetime mismatch causing simultaneous rekey collisions | Medium | Stagger lifetimes by 5 to 10%. |
| WireGuard PersistentKeepalive missing on NAT-side peer | Medium | NAT mapping expires; tunnel becomes silently unreachable. |
| WireGuard AllowedIPs overlap between two peers | Medium | Routing ambiguous; one peer becomes unreachable. |
| MTU not adjusted for IPsec / WireGuard overhead | Medium | Small packets pass; large transfers stall. |
| Replay-failure counter rising | Low to Medium | Reordering, QoS, async routing; increase window. |
| Crypto map (policy-based) used instead of VTI for new build | Low | Operational debt; migrate to VTI. |
| IKEv1 in production where IKEv2 supported on both sides | Low to Medium | Phase out IKEv1. |

## Decision trees

### IKE SA state triage

```
VPN tunnel not working
├── No IKE SA exists
│   ├── Tunnel never configured? -> verify crypto map / IKE gateway config
│   ├── Peer unreachable? -> ping peer; check UDP/500 + UDP/4500 path
│   ├── No interesting traffic? -> (policy-based) verify crypto ACL matches
│   └── SA cleared / expired? -> check logs for delete or expiry events
│
├── IKE SA exists but NOT established
│   ├── IKEv1 MM_NO_STATE / AG_NO_STATE
│   │   ├── No response from peer -> UDP/500 blocked or peer not configured
│   │   └── Proposal mismatch -> compare ISAKMP policies on both sides
│   │
│   ├── IKEv1 MM_SA_SETUP (stuck) -> DH group mismatch; align DH groups
│   ├── IKEv1 MM_KEY_EXCH (stuck)
│   │   ├── PSK mismatch -> verify pre-shared keys
│   │   ├── Certificate failure -> chain, expiry, CRL
│   │   └── ID type mismatch -> peer ID (IP vs FQDN)
│   │
│   ├── IKEv2 NO_PROPOSAL_CHOSEN -> align enc, PRF, integrity, DH
│   ├── IKEv2 INVALID_KE_PAYLOAD -> initiator should retry with responder's preferred DH
│   ├── IKEv2 AUTHENTICATION_FAILED -> verify keys / cert chain / OCSP / CRL / SAN
│   └── IKEv2 TS_UNACCEPTABLE -> align proxy IDs / encryption domains
│
├── IKE SA established, no IPSec SA
│   ├── Transform set mismatch -> compare Phase 2 proposals
│   ├── Proxy ID mismatch -> compare local / remote network definitions
│   ├── PFS DH group mismatch -> align or disable PFS on both sides
│   └── No traffic trigger -> (policy-based) send matching traffic
│
└── Both SAs established, no traffic
    ├── Routing? -> verify routes point through tunnel interface (route-based) or ACL covers (policy-based)
    ├── Encap up, decap zero -> remote peer or return-path issue
    ├── Both counters zero -> no matching traffic; check ACL / policy
    └── Errors incrementing -> crypto engine, replay, MTU
```

### WireGuard handshake triage

```
WireGuard peer not passing traffic
├── No latest-handshake value
│   ├── Endpoint reachable on UDP? -> nc -u <endpoint-ip> <listen-port> from initiator
│   ├── Public-key alignment? -> each side's [Peer] PublicKey == the other's interface PublicKey
│   ├── PSK alignment? -> if either side has PresharedKey, both must have the same value
│   ├── ListenPort matches Endpoint? -> common typo on multi-port hosts
│   └── Behind NAT, no PersistentKeepalive? -> set PersistentKeepalive = 25 on the NAT-side peer
│
├── Handshake exists but no traffic
│   ├── AllowedIPs missing the destination? -> add the LAN subnet
│   ├── AllowedIPs filters source IP? -> packets from non-listed source IPs dropped silently; expand AllowedIPs or NAT before WG
│   ├── ip_forward = 1 on the hub? -> sysctl net.ipv4.ip_forward=1
│   └── PostUp / PostDown firewall rules wrong? -> iptables / nftables NAT rules required for non-mesh routing
│
└── Handshake works but throughput stalls on large transfers
    └── MTU mismatch -> set wg0 MTU to 1420 (Ethernet) / 1432 (PPPoE) / 1280 (IPv6)
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
VPN TUNNEL TROUBLESHOOTING REPORT
==================================
Device: [hostname]
Vendor: [Cisco | JunOS | PAN-OS | FortiGate | StrongSwan | WireGuard kernel | wireguard-go | BoringTun]
Technology: [IPsec IKEv1 | IPsec IKEv2 | WireGuard | DMVPN | ADVPN]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[Tunnel topology unchanged; peer reachable on tested ports; no in-flight crypto change.]

TUNNEL INVENTORY:
- Total configured tunnels: [n]
- IKE SAs established: [n] / [configured] | Failed / Missing: [n]
- IPsec SAs active: [n] / [configured]
- WireGuard peers with handshake <180s: [n] / [configured]

EVIDENCE: [show / diagnose / wg show / swanctl --list-sas output attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Tunnel: [peer address / tunnel name]
State: [IKE state / wg handshake age / counter delta]
Observed: [state, counter, or notify code]
Expected: [normal state]
Root cause: [diagnosis from decision tree]
Recommendation: [remediation]

CRYPTO PARAMETER SUMMARY:
- IKE: [encryption] / [PRF] / [integrity] / [DH] / [auth] / [lifetime]
- IPsec: [encryption] / [integrity] / [PFS] / [lifetime]
- Strength assessment: [meets CNSA 1.0 | gap details]

TUNNEL HEALTH:
- Encap / decap: [incrementing | flat | zero]
- Errors: [count + type]
- DPD: [active | disabled | peer-dead events]
- NAT-T: [active UDP/4500 | not detected | misconfigured]
- Last rekey: [timestamp] | Next rekey: [timestamp]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list]
ROLLBACK: [config revert ref or per-tunnel revert step]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT CHECK: CRITICAL -> 1 h; WARNING -> 8 h; HEALTHY -> 24 h.
```

## Common failure modes

- **Proxy ID / traffic selector mismatch** -- the most common multi-vendor interop failure. Each vendor expresses protected networks differently (Cisco crypto ACLs, JunOS address-book, PAN-OS proxy IDs in tunnel config, FortiGate phase2 selectors). Compare the effective local / remote network pairs; they must mirror.
- **AEAD plus integrity in same proposal** -- AES-GCM is AEAD; do not include a separate integrity algorithm in the same IKE proposal. Use an explicit PRF instead.
- **Crypto map vs VTI mixing** -- do not mix both approaches on the same interface or for the same peer.
- **NAT-T not enabled on both sides** -- IPsec fails when a NAT device is between peers. Enable NAT-T on every config; firewalls must allow UDP/500 plus UDP/4500.
- **Clock skew with certificates** -- certificate validation fails if time differs by more than 5 minutes. NTP is critical.
- **DPD premature failover on healthy paths** -- transient loss or QoS deprioritisation of IKE / ESP. Increase DPD retry count or interval; verify DSCP marking.
- **Untested DPD failover** -- shipping a tunnel without simulating peer failure misses cleanup-and-re-initiation bugs (orphaned SAs on the surviving peer, stale routes via the down tunnel, asymmetric state where one end thinks the tunnel is up and the other does not). Pre-prod verification: induce peer-down (interface shutdown on the remote, deny-ACL between peers, peer reboot) and confirm both ends detect the loss, clear the SA, and re-establish cleanly when reachability returns. Catches DPD configs that "look right" but never actually trigger.
- **Rekey storms** -- if a tunnel drops at SA expiry instead of rekeying: lifetime mismatch causing simultaneous rekey, IKE SA expired before IPsec SA rekey completed, or crypto engine busy. Stagger lifetimes by 5 to 10%.
- **MTU / fragmentation on IPsec** -- with AES-256 / SHA-256 in tunnel mode, overhead is approximately 73 bytes. Set tunnel interface MTU to 1400 and TCP MSS to 1360 if traffic requires near-MTU packets. **[Cisco]** `crypto ipsec df-bit clear` allows fragmentation; pre-fragmentation (before encryption) is preferred over post-fragmentation.
- **WireGuard key distribution at scale** -- without orchestration (Tailscale, Headscale, Netmaker, Firezone, NetBird) or config management (Ansible, Terraform), manual key exchange becomes unmanageable beyond ~20 peers.
- **WireGuard UDP blocked on path** -- no native TCP fallback. Use udp2raw or wstunnel to tunnel WG over TCP, or move to a Tailscale DERP-style relay.
- **Cisco Secure Client (AnyConnect) in scope** -- if the question is endpoint VPN with full posture / NAC / SAML, this skill provides the cross-platform context. For deep AnyConnect work (DAP, TND, Always-On, per-app VPN, ISE / Umbrella integration, DART), load `references/cisco-secure-client-anyconnect.md`.

## StrongSwan operational gotchas

Two strongSwan-specific failure modes that recur on always-on B2B tunnels (site-to-site, partner routing, modem-management paths). Both are vendor-specific to strongSwan / charon; they do not apply to Cisco / Juniper / PAN-OS / FortiOS IPsec stacks (which have their own equivalent quirks).

### closeaction=restart pairing on always-on tunnels

For any strongSwan IPsec tunnel that should "stay up", the conn template must include BOTH:

```
dpdaction=restart
closeaction=restart
```

strongSwan's recovery triggers are asymmetric and non-obvious:

- `dpdaction=restart` fires when **DPD detects a dead peer** (our keepalive gets no response). Useful for unilateral peer death, link blackhole, datapath loss.
- `keyingtries=%forever` only applies **while a current initiation attempt is failing**. It is NOT a heartbeat that keeps trying to reconnect from nothing.
- A **peer-initiated DELETE** (IKE_SA or CHILD_SA) is a clean, in-protocol notification. The peer is alive enough to send it, so DPD does not fire. Without `closeaction=restart`, charon processes the DELETE, removes the SAs, and goes silent. No auto-recovery. The tunnel sits dead until somebody runs `ipsec restart` or `ipsec up <conn>`.

Failure signature: partner-side device (commonly MikroTik on a ROS upgrade / daemon restart / link flap) goes briefly unresponsive, our side sends ~5 retransmits of an INFORMATIONAL, no reply, then peer comes back and DELETEs cleanly. Our charon honours the DELETE; all CHILD_SAs die with the parent. Tunnel stays down until manual restart.

**Apply:**
- Audit any existing `/etc/ipsec.conf` or `swanctl.conf` for B2B tunnels: if `dpdaction=restart` is set but `closeaction` is not, propose adding `closeaction=restart` to the same conn (or template).
- When authoring a new strongSwan B2B conn from scratch, include both lines by default.
- `ipsec update` applies the new closeaction value to existing conns non-disruptively; no need to restart charon or tear down live SAs to roll it out.

**Caveat:** do NOT use `closeaction=restart` with `reauth=yes`. strongSwan reauthentication is itself a delete-then-reestablish cycle, and closeaction would double-trigger. For `reauth=no` (the default for IKEv2 in strongSwan 5.x), pairing closeaction with dpdaction is purely beneficial.

### Reading `ipsec statusall` correctly

The output of `ipsec statusall` has two sections that are easy to confuse:

- The `Connections:` section lists conns **configured** in `ipsec.conf` / `swanctl.conf`. This is static config, NOT live state. A conn appearing here means it loaded; it does NOT mean the tunnel is up.
- Live state is the `Security Associations (X up, Y connecting):` line. `0 up, 0 connecting` means the tunnel is down AND charon is not even retrying (the closeaction trap above is one common cause).

When triaging a "tunnel down" report on strongSwan, always read the SA line first. A populated `Connections:` block with `0 up, 0 connecting` underneath looks healthy at a glance but is the exact signature of the closeaction failure mode.

## Cisco Secure Client / AnyConnect (progressive disclosure)

The body above covers site-to-site IPsec, WireGuard, and the dynamic-mesh derivatives. Endpoint remote-access with Cisco Secure Client (formerly AnyConnect) is a distinct surface with its own depth: SSL/DTLS vs IKEv2, the module architecture (VPN, Umbrella, ISE Posture, Secure Firewall Posture, NVM, ZTA), SAML SSO, Dynamic Access Policies (DAP), split tunnelling (include/exclude/dynamic/per-app), Always-On, Trusted Network Detection, posture, deployment, and DART troubleshooting.

For any AnyConnect/Secure Client task, load **`references/cisco-secure-client-anyconnect.md`**. The recurring trap it flags: DAP takes precedence over group policy, so a split-tunnel or ACL issue that "should work" is usually a DAP override, and UDP/443 blocked on the path silently drops the client to slow TLS-only mode. For the firewall-side policy view of the same headend, cross-reference `cisco-firewall-audit` (ASA/FTD).

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the VPN specialist. Apply the nine-element response contract to every state-changing tunnel change.
- `cisco-firewall-audit` -- ASA / FTD VPN review and AnyConnect remote-access posture (firewall-side policy view).
- `palo-alto-firewall-audit` -- GlobalProtect zone audit and firewall-side VPN policy.
- `fortigate-firewall-audit` -- FortiOS phase1 / phase2 interface, FortiClient EMS endpoint posture (firewall-side policy view).
- `bgp-analysis`, `igp-routing-analysis` -- when running BGP / OSPF over a tunnel, problems often look like VPN flapping but are routing-protocol issues.
- `acl-rule-analysis` -- crypto-ACL methodology when policy-based VPN is in use.
- `pyats-network-automation` -- Genie parsers exist for some IKE / IPsec show output; useful for fleet tunnel-health scans.
- `secrets-hygiene` -- PSKs, certificate private keys, RADIUS shared secrets, WireGuard private keys + PSKs all fall under the patterns there. Never paste a key into a chat transcript.
- `completion-gate` Layer 3 -- every state-changing tunnel change requires fresh post-check evidence (handshake or SA established, encap / decap counters moving, application-layer ping) before claiming "tunnel up".
- `plan-time-tooling` -- every state-changing recommendation fires `engineering:deploy-checklist` at plan time.
- `systematic-debugging` -- Phase 1 boundary evidence (peer reachable; UDP / IKE port open; key / cert valid; route present) before any change.
- `oncall-runbooks` -- incident classification when a VPN issue escalates to a customer-impacting incident.

## Red flags (about-to-act warnings)

- About to change a crypto proposal on a production tunnel without confirming both sides will agree on the new set.
- About to clear an IKE SA or `wg set ... remove peer` without scoping the blast radius (which sites, which apps, which users).
- About to roll a PSK on a tunnel without coordinating both ends in the same maintenance window.
- About to disable PFS to "fix" a TS_UNACCEPTABLE when the real issue is a proxy ID mismatch.
- About to extend AllowedIPs to `0.0.0.0/0` without DNS routing verification.
- About to enable IKEv1 to "be compatible" when the real fix is a vendor-side IKEv2 config tweak.
- About to use AES-128 or DH Group 14 for a new tunnel that could use AES-256-GCM and Group 20.
- About to deploy WireGuard at >20 peers without picking an orchestration platform.
- About to mix crypto map and VTI on the same peer relationship.
- About to upgrade certificate auth on a long-lived tunnel without renewal automation.

## Bottom line

Diagnose by state machine, not by guesswork. For IPsec / IKEv2 the FSM tells you exactly which leg is broken; for WireGuard the handshake age plus AllowedIPs scope tell the same story in two values. Pick the right technology for the architecture (cross-vendor compliance -> IPsec; Linux mesh -> WireGuard; enterprise endpoint -> AnyConnect / GlobalProtect / FortiClient). Use CNSA 1.0 today; plan the CNSA 2.0 hybrid transition. Map every state-changing recommendation onto the nine-element response contract; verify post-change with counter movement plus a real application-layer ping, not just SA-up.
