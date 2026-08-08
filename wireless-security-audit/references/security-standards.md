# Wireless security standards reference

Reference document covering 802.1X / EAP authentication, WPA security standards, rogue AP classification, WIDS / WIPS capabilities, and RF security fundamentals. Supports the wireless security audit procedure in SKILL.md.

## 802.1X / EAP Authentication

### Authentication state machine

802.1X port-based access control uses three roles:

1. **Supplicant**: wireless client requesting network access.
2. **Authenticator**: wireless controller / AP acting as enforcement point.
3. **Authentication Server**: RADIUS server validating credentials.

State flow:

```
Supplicant                Authenticator              RADIUS Server
    |                          |                          |
    |--- EAPOL-Start --------> |                          |
    |<-- EAP-Request/Identity  |                          |
    |--- EAP-Response/Identity>|                          |
    |                          |--- Access-Request -----> |
    |                          |<-- Access-Challenge ---- |
    |<-- EAP-Request/Method    |                          |
    |--- EAP-Response/Method ->|                          |
    |                          |--- Access-Request -----> |
    |                          |<-- Access-Accept ------- |
    |<-- EAP-Success           |                          |
    |                          | [Port Authorized]        |
```

### EAP method types

| Method | Auth mechanism | Certificate required | Security level |
|---|---|---|---|
| EAP-TLS | Mutual certificate | Client + Server | Highest: mutual PKI authentication |
| PEAP (MSCHAPv2) | Server cert + password | Server only | High: encrypted tunnel protects credentials |
| EAP-TTLS | Server cert + inner method | Server only | High: similar to PEAP, broader inner-method support |
| EAP-FAST | PAC + inner method | Optional (PAC provisioning) | High: Cisco-originated, handles environments without PKI |
| LEAP | Password challenge | None | Deprecated: vulnerable to offline dictionary attacks |

### 802.1X failure modes

| State | Indicator | Cause |
|---|---|---|
| RADIUS timeout | Client stuck at "connecting" | Server unreachable, wrong shared secret, or firewall blocking UDP 1812 / 1813 |
| Certificate rejected | EAP-TLS failure after cert exchange | Expired cert, untrusted CA, hostname mismatch |
| Inner auth failure | PEAP / TTLS tunnel established but access denied | Wrong username / password, account locked, NPS / FreeRADIUS policy mismatch |
| VLAN assignment missing | Client authenticates but no network access | RADIUS not returning Tunnel-Private-Group-ID attribute |
| Dynamic ACL failure | Client authenticates but restricted | RADIUS ACL attribute references non-existent ACL on controller |

## WPA Security Standards

### WPA3-Enterprise (192-bit mode)

WPA3-Enterprise with 192-bit mode provides CNSA-grade security:

- **Key exchange**: SAE (Simultaneous Authentication of Equals) replaces PSK 4-way handshake; resistant to offline dictionary attacks.
- **PMF (Protected Management Frames)**: mandatory; prevents deauthentication attacks, disassociation floods.
- **Cipher suite**: GCMP-256 (vs CCMP-128 in WPA2).
- **Key derivation**: 384-bit ECDH + 384-bit ECDSA.
- **RADIUS requirement**: TLS 1.2+ with EAP-TLS for the full 192-bit chain.

### WPA3-Personal

- SAE replaces PSK; forward secrecy, no offline dictionary attacks.
- PMF mandatory; prevents deauth / disassoc attacks.
- Transition mode allows WPA2 clients to coexist (reduces security; WPA2 clients remain vulnerable).

### WPA2 to WPA3 transition

| Configuration | Security posture | Compatibility |
|---|---|---|
| WPA3-only | Highest; full PMF, SAE | WPA3 clients only |
| WPA3-Transition | Reduced; WPA2 clients lack PMF / SAE | WPA2 + WPA3 clients |
| WPA2-Enterprise (AES) | Baseline; no PMF, PSK vulnerable to offline attack | Broadest device support |
| WPA2-Personal (TKIP) | Deprecated; TKIP has known weaknesses | Legacy only |

**Transition mode risk**: when WPA3-Transition is enabled, an attacker can force a downgrade by impersonating the AP and advertising only WPA2 capability. This is acceptable only as a temporary migration step.

## Rogue AP classification

### Classification tiers

| Classification | Definition | Threat level | Response |
|---|---|---|---|
| **Managed** | AP in the controller's inventory, authorised and configured | None | Normal operation |
| **Neighbouring** | Known AP from adjacent organisation (e.g. neighbouring office) | Low | Monitor; no action unless interference |
| **Interfering** | Unmanaged AP on same channel causing co-channel interference | Medium | Investigate; classify or reclassify |
| **Rogue** | Unauthorised AP connected to the wired network | Critical | Immediate containment and physical removal |
| **Honeypot / Evil Twin** | AP spoofing a legitimate SSID to capture credentials | Critical | Immediate containment; alert SOC; incident response |

### Rogue detection methods

- **Controller-based**: managed APs scan for unknown BSSIDs during off-channel scans or on dedicated monitor-mode APs.
- **Wired-side correlation**: controller checks if the rogue AP's MAC appears on the wired network via switch port MAC tables; confirms whether the rogue is connected to the corporate LAN.
- **WIPS containment**: when a rogue is classified as wired-connected and unauthorised, WIPS can send deauthentication frames to clients associated with the rogue (active containment). This requires explicit policy approval.

## WIDS / WIPS capabilities

### Detection categories

| Category | Examples | Detection method |
|---|---|---|
| Rogue AP | Unauthorised APs, evil twins | Off-channel scanning, wired correlation |
| Ad-hoc networks | Client-to-client bridging | Frame type analysis |
| DoS attacks | Deauth floods, auth floods, CTS / RTS abuse | Frame rate anomaly detection |
| Encryption attacks | TKIP MIC failure, KRACK replay | Protocol state analysis |
| Reconnaissance | Probe request storms, passive sniffing | Behavioural analysis |

### Containment mechanisms

- **Deauthentication containment**: send deauth frames to clients of the rogue AP; effective but impacts any client connected to that BSSID.
- **Wired containment**: block the rogue's switch port (requires integration with wired infrastructure).
- **Channel change**: move legitimate APs away from the rogue's channel to reduce interference impact.

**Legal note**: active wireless containment (deauth frames) may have legal implications in some jurisdictions. Verify organisational policy and legal counsel before enabling automatic containment.

## RF security best practices

### Channel and power management

- **Minimum signal-to-noise ratio (SNR)**: 25 dBm for voice, 20 dBm for data; below these thresholds, clients may roam to rogue or interfering APs due to weak legitimate signal.
- **Channel isolation**: use non-overlapping channels (1, 6, 11 for 2.4 GHz; full channel set for 5 GHz / 6 GHz). Co-channel interference increases retry rates and degrades performance.
- **Transmit power control (TPC)**: match AP power to coverage cell design; over-powering creates cell overlap and co-channel interference. Under-powering creates coverage holes where clients may associate with rogues.
- **DFS channels**: Dynamic Frequency Selection channels (5 GHz) must vacate on radar detection; avoid DFS channels in areas near airports or weather radar.

### Coverage design security

- **Perimeter signal leakage**: APs near building exteriors should use directional antennas or reduced power to minimise signal outside the physical boundary. External signal enables parking-lot attacks.
- **Coverage holes**: areas without adequate legitimate coverage allow rogue APs to serve clients. Validate coverage with site survey tools.
- **Band steering**: encourage 5 GHz / 6 GHz association where possible; 2.4 GHz has longer range (higher exterior leakage risk) and more interference.

## Guest network isolation

### Segmentation requirements

- **VLAN separation**: guest traffic on a dedicated VLAN with no routing to internal networks. Verify firewall / ACL rules between guest VLAN and production VLANs.
- **Bandwidth limits**: rate-limit guest clients to prevent bandwidth exhaustion of shared WAN links. Typical: 5 to 20 Mbps per client, 50 to 100 Mbps per SSID.
- **Client isolation**: prevent guest-to-guest lateral communication (L2 isolation / peer-to-peer blocking). Important for captive portal pre-auth and post-auth states.
- **Captive portal**: force authentication or acceptance of terms before granting internet access. Verify HTTPS redirect, certificate validity, and portal timeout / re-authentication interval.
- **DNS restrictions**: consider DNS filtering on guest network to block malicious domains. Guest DNS should not resolve internal hostnames.
- **Session timeout**: enforce maximum session duration (4 to 12 hours typical) and re-authentication requirements.
