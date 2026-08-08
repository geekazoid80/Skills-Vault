# Cisco Catalyst 9800 wireless operations

The Catalyst 9800 WLC runs IOS-XE, the same operating system as Catalyst 9000 switches and ISR/ASR routers. This gives the WLC full routing protocol support, VRF, MQC QoS, and YANG/NETCONF/RESTCONF programmability alongside wireless controller functions.

## Hardware models

| Model | Max APs | Max clients | Form factor | Use case |
|---|---|---|---|---|
| C9800-L | 500 | 5,000 | 1RU small | Branch / small campus |
| C9800-40 | 2,000 | 32,000 | 1RU | Mid-size campus |
| C9800-80 | 6,000 | 64,000 | 2RU | Large campus / data centre |
| C9800-CL | 6,000 | 64,000 | Virtual (ESXi/KVM/AWS/Azure) | Cloud or virtualised environments |
| C9800 Embedded (EWC) | ~100 (cluster) | Varies | Catalyst 9100 AP-embedded | Ultra-small sites |

## Tag and profile model

C9800 uses a hierarchical tag and profile model, replacing AireOS's flat WLAN config. Every AP is assigned exactly one Site Tag, one Policy Tag, and one RF Tag.

```
Site Tag -------> AP Join Profile   (AP management: SSH, CDP, NTP, LED, country code, AP mode)
              --> Flex Profile       (FlexConnect: native VLAN, VLAN mapping, local auth fallback)

Policy Tag -----> WLAN Profile      (SSID name, security mode, QoS policy)
              --> Policy Profile     (VLAN, client ACL, AAA overrides, idle/session timeout)

RF Tag ---------> 2.4 GHz RF Profile
              --> 5 GHz RF Profile
              --> 6 GHz RF Profile
```

Key audit point: a WLAN Profile and its bound Policy Profile are independent objects. An SSID that looks secure at the WLAN Profile (WPA3-Enterprise, 802.1X) can still land clients on the wrong VLAN or ACL via a misconfigured Policy Profile. Always audit both objects per SSID.

## Deployment modes

**Centralised (Local Mode)**
APs tunnel both control and data via CAPWAP to the WLC. WLC handles all authentication, policy enforcement, and RF management. Best for campus deployments with reliable, low-latency LAN connectivity to the WLC.

**FlexConnect**
APs maintain a CAPWAP control tunnel to the WLC but switch client data locally (Local Switching sub-mode). Benefits: branch survivability during WAN outage (AP caches auth state in Standalone mode), reduced WAN bandwidth. VLAN mapping configured per FlexConnect Group. C9800-CL in public cloud requires FlexConnect with local switching.

**SD-Access Fabric**
APs operate in fabric mode with VXLAN encapsulation. The WLC acts as a fabric wireless controller (control plane only); Catalyst switches handle VXLAN and SGT tagging. Requires Catalyst Center for fabric provisioning and SGT policy. Best for large enterprises requiring micro-segmentation and consistent wired/wireless policy.

**Embedded WLC (EWC)**
WLC software embedded on a Catalyst 9100 AP. One AP acts as the primary WLC; supports up to approximately 100 APs. Seamless failover to standby EWC. Best for ultra-small sites without dedicated WLC hardware.

## AP families

| Family | Wi-Fi standard | Bands | Notes |
|---|---|---|---|
| CW9100 | Wi-Fi 6 (802.11ax) | 2.4/5 GHz | Value enterprise indoor; 802.3at PoE+ |
| CW9160/9162/9164/9166 | Wi-Fi 6E | 2.4/5/6 GHz | High-density; 6 GHz requires IOS-XE 17.9+; 802.3bt (PoE++) for full tri-band |
| CW9170/9172/9176/9178 | Wi-Fi 7 (802.11be) | 2.4/5/6 GHz | Wi-Fi 7 requires IOS-XE 17.15+; MLO, 320 MHz, 4096-QAM; 802.3bt required |
| CW9186 | Wi-Fi 7 outdoor | 2.4/5/6 GHz | IP67; stadium, outdoor campus, warehouse |

## Wi-Fi 7 on IOS-XE 17.15

IOS-XE 17.15 introduced 802.11be (Wi-Fi 7) support on CW9170/9178 APs:
- Multi-Link Operation (MLO): single client maintains simultaneous connections across 2.4 + 5 + 6 GHz; aggregates bandwidth and steers latency-sensitive frames to the least-congested link.
- 320 MHz channels in 6 GHz only (3 non-overlapping; use 160 or 80 MHz for denser AP deployments).
- 4096-QAM: 20% throughput gain over 1024-QAM but requires SNR over 40 dB.
- Enable via 802.11be Profile under Configuration / Tags and Profiles; Wi-Fi 7 is not on by default.
- 6 GHz SSIDs and Wi-Fi 7 certified SSIDs require WPA3; there is no WPA2 fallback.
- Older APs (CW9100, CW9160) continue operating normally on the same WLC.

Configuration snippet:
```
wireless profile dot11be <profile-name>
  mlo enable
  mlo-band-combination 5+6
```

## RRM (Radio Resource Management)

| Function | Description |
|---|---|
| DCA (Dynamic Channel Assignment) | Assigns non-overlapping channels across APs to minimise co-channel interference |
| TPC (Transmit Power Control) | Adjusts AP transmit power for optimal cell overlap (target -65 to -67 dBm at cell edge) |
| CHD (Coverage Hole Detection) | Increases power or alerts when coverage gaps detected via client RSSI reports |
| CleanAir | Classifies non-Wi-Fi interference sources (microwave, Bluetooth, ZigBee) using dedicated silicon |
| FRA (Flexible Radio Assignment) | Converts underutilised 2.4 GHz radios to 5 GHz on dual-radio APs |
| Load-Based CAC | Limits new associations when channel utilisation exceeds a configured threshold |

RRM groups: APs within a group have their RF decisions coordinated globally by the group leader. In multi-WLC deployments, RRM groups can span WLCs. Start with RRM defaults; tune only when a specific, measured problem exists.

RRM monitoring commands:
```
show ap dot11 5ghz group          ! RRM group leader and members
show ap dot11 5ghz channel        ! DCA channel assignments
show ap dot11 5ghz power          ! TPC power levels
show ap dot11 5ghz monitor        ! Recent channel/power change events
show ap dot11 5ghz cleanair air-quality summary
```

## WLAN and RF configuration best practices

**SSID count**: limit to 3-4 SSIDs per radio. Each SSID adds beacon overhead. Recommended set:
- Corp (WPA3-Enterprise, 802.1X with ISE): employee devices.
- IoT (MAB or 802.1X with EAP-TLS certificates): sensors, cameras, printers.
- Guest (CWA via ISE guest portal, WPA3-OWE or open): visitor internet.

**Data rate configuration**: disable low data rates to improve airtime efficiency. On 2.4 GHz, disable 1, 2, 5.5 Mbps; set 11 Mbps as minimum mandatory. On 5 GHz, disable rates below 12 Mbps. Raising minimum rates reduces cell size; re-validate coverage after changes.

**Band steering**: enable to push dual-band clients to 5/6 GHz. Configure FRA to convert underutilised 2.4 GHz radios to 5 GHz in dense environments.

**FlexConnect design**:
- Use FlexConnect Groups for VLAN consistency across branch APs.
- Enable split tunnelling: corporate traffic centrally switched, guest/internet traffic locally switched.
- Pre-download AP images to reduce WAN traffic during upgrades.
- Enable OKC within FlexConnect Groups for fast roaming between branch APs.

**RF profile tuning**: bind custom RF profiles to APs via RF Tags. Custom profiles have no effect until assigned via a tag. Avoid over-tuning: RRM defaults are optimised for most environments.

**QoS**: enable WMM on all SSIDs. Map voice to Platinum (AC_VO), video to Gold (AC_VI), data to Silver (AC_BE). Enable AVC for application-based classification.

## Radioactive tracing (RA Trace)

Radioactive Tracing provides detailed per-client event logging without enabling broad debug that impacts all clients. It is the primary troubleshooting tool on C9800.

**Via GUI**: Troubleshooting > Radioactive Trace > add client MAC > Start trace > reproduce > Stop > Generate log > Download.

**Via CLI**:
```
debug wireless mac <client-mac-address>
! Optionally limit duration:
debug wireless mac <client-mac-address> monitor-time 300
! After reproducing, collect:
show logging process wncd internal filter mac <client-mac-address>
! Or from flash:
dir bootflash:ra_trace/
more bootflash:ra_trace/ra_trace_MAC_<mac>_<timestamp>.log
! Disable when done:
no debug wireless mac <client-mac-address>
```

**Key log prefixes**:
- `[client-orch-sm]`: client state machine (authenticate, associate, run, delete).
- `[dot11]`: 802.11 association/authentication events.
- `[dot1x]`: 802.1X/EAP authentication events.
- `[aaa]`: RADIUS request/response.
- `[dhcp]`: DHCP DORA sequence.
- `[mobility]`: roaming events (L2 roam, L3 roam, anchor/foreign).
- `[policy]`: Policy Profile application, VLAN assignment, ACL.

**Successful join sequence**:
```
dot11 -> association request
dot1x -> EAP identity request
aaa   -> RADIUS Access-Request / Access-Accept
dot1x -> 4-way handshake complete
client-orch-sm -> state: RUN
dhcp  -> DHCP DISCOVER / OFFER / REQUEST / ACK
```

**Authentication failure**: look for `RADIUS Access-Reject`, then `EAP failure sent`, then `state: DELETE`.

**Roaming failure**: look for `FT key mismatch` or `PMK cache miss`, then `state: DELETE`.

## Client troubleshooting workflow

**Step 1: Identify the client**
```
show wireless client mac-address <mac> detail
```
Check: state (run/authenticate/associate), WLAN, AP name, channel, RSSI, SNR, data rate.

**Step 2: Check client statistics**
```
show wireless client mac-address <mac> stats
```
Look for: high retry rate (over 10% indicates RF issues), low data rates (client far from AP), packet errors.

**Step 3: Enable radioactive trace** (see above). Reproduce the issue; review for error events.

**Step 4: Check RF environment**
```
show ap name <ap-name> dot11 5ghz cleanair air-quality summary
show ap name <ap-name> auto-rf dot11 5ghz
```
Look for: channel utilisation over 50%, non-Wi-Fi interference, low SNR.

**Step 5: Verify infrastructure**
```
test aaa group <server-group> <username> <password> new-code   ! RADIUS reachability
show interfaces trunk                                           ! On connected switch
```

## Essential show commands

**AP management**
```
show ap summary
show ap name <ap-name> config general
show wireless stats ap join summary
show ap image
show ap uptime
```

**Client monitoring**
```
show wireless client summary
show wireless client mac-address <mac> detail
show wireless stats client delete reason
show wlan summary
```

**RF and radio**
```
show ap dot11 5ghz summary
show ap dot11 24ghz summary
show ap dot11 6ghz summary
show ap dot11 5ghz cleanair air-quality summary
```

**WLAN and policy**
```
show wlan summary
show wlan name <wlan-name>
show wireless profile policy detailed <policy-name>
show ap tag summary
show ap name <ap-name> tag
```

**WLC health**
```
show processes cpu sorted
show platform software status control-processor brief
show redundancy
show platform hardware throughput level
```

## AP join troubleshooting

**Discovery phase**: APs discover the WLC via DHCP option 43, DNS (CISCO-CAPWAP-CONTROLLER.localdomain), broadcast, or pre-configured primary/secondary/tertiary WLC.

```
show wireless stats ap discovery
show wireless stats ap join summary
```

| Symptom | Likely cause | Fix |
|---|---|---|
| AP not discovered | DHCP option 43 missing or DNS not resolving | Configure option 43 or DNS entry |
| AP stuck in Downloading | Image mismatch; slow link | Wait; check image pre-download with `show ap image` |
| AP joins then drops | Certificate expired; DTLS failure; MTU too low | Check certs; verify MTU at least 1500 on path |
| AP on wrong WLC | Primary/secondary/tertiary WLC misconfigured | Set correct WLC priority via `ap name <n> controller <wlc>` |

## HA and upgrade procedures

**SSO (Stateful Switchover)**: active/standby pair with RP connection; full client, AP, and config state replicated; sub-second failover; requires identical hardware and IOS-XE version.

**Rolling AP upgrade (no WLC downtime)**:
1. Stage new image: `ap image predownload`.
2. Configure AP upgrade groups (stagger by floor, building, or AP group).
3. Initiate rolling upgrade; each AP is offline 3-5 minutes during reboot; neighbouring APs provide overlap.
4. Monitor: `show ap image`.
5. Validate: AP join state, client counts, RF metrics post-upgrade.

**WLC HA upgrade**:
1. Pre-download image to standby.
2. Upgrade standby; verify it comes up healthy.
3. Force switchover to upgraded standby (now active).
4. Upgrade original active (now standby).
5. Verify both WLCs in HA SSO state.

**Pre-upgrade checklist**:
- Review release notes for known issues.
- Back up running config: `copy running-config bootflash:backup_<date>.cfg`.
- Verify maintenance window covers WLC reboot (10-15 min) plus AP stagger groups (3-5 min each).
- Notify stakeholders of expected wireless downtime per area.

## ISE integration

Cisco ISE provides the authentication and authorisation backend:
- **802.1X**: EAP-TLS, PEAP, EAP-TTLS; ISE as RADIUS server.
- **MAB**: MAC Authentication Bypass for IoT/headless devices.
- **Guest**: Central Web Authentication (CWA) via ISE guest portal.
- **BYOD**: My Devices portal with certificate provisioning.
- **Posture**: endpoint compliance checking via AnyConnect/Secure Client.
- **AAA Override**: ISE returns VLAN, ACL, SGT via RADIUS attributes that override Policy Profile defaults.

## Common pitfalls

1. **Mixing deployment modes per WLC**: all APs in a Site Tag should use the same mode (centralised or FlexConnect). Mixing creates unpredictable VLAN and policy behaviour.
2. **FlexConnect VLAN mismatch**: local VLAN on the FlexConnect AP must match the switch trunk config. Silent client failures result.
3. **Forgetting RF Tag assignment**: custom RF Profiles have no effect until bound via a custom RF Tag and assigned to APs.
4. **AireOS migration confusion**: C9800 tag/profile model is fundamentally different from AireOS flat config. Redesign using tags; do not replicate AireOS 1:1.
5. **Rolling upgrade without stagger**: configure AP upgrade groups. Upgrading all APs simultaneously causes a complete wireless outage.
6. **CleanAir without action**: enable CleanAir persistent device avoidance; raw detection without mitigation wastes the data.
7. **6 GHz AFC not configured**: for standard-power 6 GHz, AFC must be configured. Without AFC, APs operate in Low Power Indoor (LPI) mode with reduced coverage.
8. **Auditing only the WLAN Profile**: always audit both the WLAN Profile and the bound Policy Profile per SSID on C9800.
