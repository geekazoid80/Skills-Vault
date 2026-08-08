# RF design and wireless fundamentals

Vendor-neutral RF principles apply across all enterprise wireless platforms. The platform manages the RF mechanics (RRM, AirMatch, Auto-RF); the design determines whether the platform has anything useful to optimise. Poor AP placement cannot be corrected by software alone.

## Wi-Fi standards overview

| Standard | Marketing name | Bands | Max PHY rate | Key features |
|---|---|---|---|---|
| 802.11ac Wave 2 | Wi-Fi 5 | 5 GHz | 3.5 Gbps | Downlink MU-MIMO (4x4), 160 MHz channels |
| 802.11ax | Wi-Fi 6 | 2.4/5 GHz | 9.6 Gbps | OFDMA, UL MU-MIMO (8x8), BSS Coloring, TWT, 1024-QAM |
| 802.11ax | Wi-Fi 6E | 2.4/5/6 GHz | 9.6 Gbps | Same as Wi-Fi 6; extended to 6 GHz (1.2 GHz new spectrum); no legacy clients; WPA3 mandatory |
| 802.11be | Wi-Fi 7 | 2.4/5/6 GHz | 46 Gbps | MLO, 320 MHz channels, 4096-QAM, 16x16 MU-MIMO, preamble puncturing; WPA3 mandatory |

As of 2026, 6 GHz client adoption is growing but not universal. Design for dual-band (5 + 6 GHz) operation; do not retire 5 GHz yet. 6 GHz provides the best capacity and least interference for capable clients.

## 802.11ax (Wi-Fi 6 and Wi-Fi 6E) key improvements

**OFDMA (Orthogonal Frequency Division Multiple Access)**: subdivides each channel into Resource Units (RUs) allocated to different clients simultaneously. A single OFDM symbol can serve multiple clients. The most important improvement for dense environments with many small-packet clients (IoT, voice, ACKs).

| Channel width | Maximum simultaneous users (OFDMA) |
|---|---|
| 20 MHz | 9 users |
| 40 MHz | 18 users |
| 80 MHz | 37 users |
| 160 MHz | 74 users |

**MU-MIMO**: up to 8x8 downlink and 8x8 uplink MU-MIMO (802.11ac was 4x4 DL only). Uplink MU-MIMO is new in 802.11ax; improves airtime efficiency when multiple clients transmit simultaneously.

**BSS Coloring (Spatial Reuse)**: assigns each BSS a 6-bit colour value. Same-colour transmissions apply standard CCA thresholds; different-colour transmissions apply relaxed OBSS-PD thresholds (up to -62 dBm), allowing concurrent transmissions when inter-BSS interference is weak. Reduces co-channel interference in dense deployments.

**TWT (Target Wake Time)**: clients negotiate specific wake schedules with the AP. Reduces battery consumption by 5-10x for low-duty-cycle IoT sensors and spreads client contention over time.

**1024-QAM**: 25% throughput improvement over 256-QAM but requires SNR over 35 dB. Only benefits clients physically close to the AP.

**Wi-Fi 6E (6 GHz extension)**:
- 1.2 GHz of new spectrum (5.925-7.125 GHz in the US; varies internationally).
- Up to 59 non-overlapping 20 MHz channels; 7 non-overlapping 160 MHz channels.
- No legacy clients: only 802.11ax and newer devices operate on 6 GHz.
- No DFS requirements: no radar coexistence needed.
- WPA3 mandatory: no WPA2 permitted in 6 GHz.

**6 GHz regulatory modes**:
- LPI (Low Power Indoor): default for indoor APs; lower transmit power; no AFC required.
- SP (Standard Power): higher transmit power permitted when using AFC (Automated Frequency Coordination). AFC is a cloud service that checks AP location against incumbent user databases and authorises specific channels and power levels.
- VLP (Very Low Power): for portable/mobile devices; lowest power; no AFC required.

## 802.11be (Wi-Fi 7) key improvements

**MLO (Multi-Link Operation)**: the headline Wi-Fi 7 feature. A single client maintains simultaneous connections across multiple bands (2.4 + 5 + 6 GHz) or multiple channels within a band. Benefits: bandwidth aggregation across links; latency-sensitive frames steered to the least-congested link in real-time; seamless band steering without disassociation; resilience when one link experiences interference. MLO replaces vendor-specific band-steering hacks with a standards-based mechanism.

**320 MHz channels**: available in 6 GHz only. Doubles channel width from Wi-Fi 6E's maximum 160 MHz. Only 3 non-overlapping 320 MHz channels in 6 GHz; practical in low-density deployments with clean 6 GHz RF.

**4096-QAM**: 20% throughput improvement over 1024-QAM. Requires SNR over 40 dB; only effective at very short range.

**Preamble Puncturing**: allows a wide channel (160 or 320 MHz) to continue operating when a portion is occupied by interference. The punctured sub-channel is excluded; the rest continues. Critical for 320 MHz operation where finding a completely clean 320 MHz block is difficult.

**Wi-Fi 7 security requirements**: WPA3-Enterprise mandatory for enterprise deployments; WPA3-Personal (SAE with SAE-EXT-KEY / GCMP-256) for personal networks; no WPA2 in Wi-Fi 7 certified deployments.

## Channel planning

### 2.4 GHz

Only 3 non-overlapping 20 MHz channels in the Americas: **1, 6, 11**.

Rules:
- Never use 40 MHz channels in enterprise: only 1.5 non-overlapping channels result, creating massive co-channel interference.
- Maximum 3 APs can operate on non-overlapping channels in the same coverage area.
- 2.4 GHz penetrates walls better than 5/6 GHz: useful for legacy devices; a liability for interference range.
- Disable 2.4 GHz radios on a subset of APs in high-density areas; use remaining 2.4 GHz radios for legacy device coverage only.
- In EMEA: channels 1, 5, 9, 13 may be used depending on the regulatory domain.

### 5 GHz

| Sub-band | Channels (20 MHz) | DFS required | Notes |
|---|---|---|---|
| UNII-1 (5.150-5.250 GHz) | 36, 40, 44, 48 | No | Indoor-only in some regions; most reliable for dense deployments |
| UNII-2 (5.250-5.350 GHz) | 52, 56, 60, 64 | Yes | Radar detection required |
| UNII-2e (5.470-5.725 GHz) | 100-144 | Yes | Large channel pool; DFS radar events common near airports |
| UNII-3 (5.725-5.850 GHz) | 149, 153, 157, 161, 165 | No | Higher power allowed; good for outdoor |

**DFS (Dynamic Frequency Selection)**:
- Required on UNII-2 and UNII-2e channels to protect radar systems.
- Channel Availability Check (CAC): AP scans for radar before transmitting (60 seconds).
- If radar is detected during operation: AP vacates the channel within 10 seconds (Channel Move Time).
- Non-Occupancy Period: AP cannot return to the channel for 30 minutes.
- Near airports, military bases, or weather radar installations: DFS channels may be frequently vacated. Design with sufficient non-DFS channel capacity as a fallback.

**Channel width guidance**:
- 20 MHz: maximum channel reuse; best for very high-density environments.
- 40 MHz: good balance for most enterprise deployments.
- 80 MHz: higher per-client throughput; fewer non-overlapping channels.
- 160 MHz: only 2 non-overlapping channels without DFS; use selectively.

### 6 GHz

- 59 non-overlapping 20 MHz channels; 29 at 40 MHz; 14 at 80 MHz; 7 at 160 MHz; 3 at 320 MHz.
- No DFS required.
- AFC required for Standard Power mode.
- PSC (Preferred Scanning Channels): 5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229. Wi-Fi 6E/7 clients scan PSCs first; AP should operate on PSCs to reduce client discovery time.
- Higher free-space path loss than 5 GHz (~2 dB more at 6.5 GHz vs 5.5 GHz); higher wall penetration loss; plan for smaller coverage cells or more APs.

## MIMO, MU-MIMO, and OFDMA

**MIMO**: multiple antennas at both transmitter and receiver for spatial multiplexing (multiple independent data streams) or spatial diversity (reliability via beamforming). Notation: NxM (N transmit x M receive antennas).

**MU-MIMO**: AP serves multiple clients simultaneously:
- Downlink MU-MIMO (802.11ac Wave 2+): AP beamforms to spatially separate clients. A 4x4 AP can serve four 1x1 clients simultaneously.
- Uplink MU-MIMO (802.11ax+): multiple clients transmit to the AP simultaneously via trigger frames.
- Limitation: requires spatial separation between clients; closely co-located clients cannot be served simultaneously.

**OFDMA vs MU-MIMO**:
- OFDMA divides the channel in the frequency domain (different sub-carriers to different clients).
- MU-MIMO divides the channel in the spatial domain (different beams to different clients).
- They are complementary and operate simultaneously.
- OFDMA excels for small packets (IoT, voice, ACKs); MU-MIMO excels for large data transfers.

## Roaming protocols

Without optimisation, a roam can take 500-1000 ms (full 802.1X reauthentication). This is unacceptable for voice (over 50 ms is noticeable) and real-time applications.

**802.11k (Neighbour Report)**: AP provides client with a list of neighbouring APs and their channels. Client targets specific channels for scanning rather than scanning all channels. Reduces scan time from approximately 200 ms to approximately 20 ms. Universally supported by modern clients; safe to enable everywhere.

**802.11v (BSS Transition Management)**: AP can suggest or direct clients to roam. BSS Transition Management Request tells the client to move to a specific AP. Disassociation Imminent warns the client it will be disconnected. Improves sticky-client behaviour. Client may ignore suggestions (advisory, not mandatory). Universally supported; safe to enable everywhere.

**802.11r (Fast BSS Transition / FT)**: pre-computes the PMK at neighbouring APs before roaming. Reduces 4-way handshake to 2 messages during reassociation. Roam time drops to approximately 20-50 ms. Compatibility warning: some older clients (Windows 7, older iOS, legacy VoIP phones, barcode scanners) do not support 802.11r and will fail to connect. Test with your client device fleet before enabling. Enable with OKC as fallback.

**OKC (Opportunistic Key Caching)**: vendor-specific fast roaming mechanism (predates 802.11r). Client caches the PMK-R0 and derives PMK-R1 for new APs in the same mobility domain. Avoids full 802.1X reauthentication. Widely supported by Cisco, Aruba, and most enterprise platforms. Functions as a fallback when 802.11r is not supported.

**Roaming best practices**:
1. Enable 802.11k everywhere (safe, widely supported).
2. Enable 802.11v everywhere (safe, improves sticky client behaviour).
3. Enable 802.11r selectively: test with your client fleet first.
4. Maintain OKC as fallback for clients that do not support 802.11r.
5. Design AP placement for -67 dBm overlap at roaming boundaries.
6. Validate roaming paths with active survey tools and actual client devices.

## WPA3 overview

**WPA3-Personal (SAE)**: replaces WPA2-Personal PSK with Simultaneous Authentication of Equals. Dragonfly key exchange resists offline dictionary attacks (each authentication requires a live exchange with the AP). Forward secrecy: a compromised password does not decrypt previously captured traffic.

**WPA3-Enterprise**: builds on WPA2-Enterprise (802.1X) with mandatory PMF. Standard mode (128-bit): CCMP-128 encryption with mandatory PMF; appropriate for most enterprise networks. Suite B (192-bit mode): GCMP-256 encryption, HMAC-SHA-384, ECDSA-384 certificates; required for government/high-security; demands compatible RADIUS infrastructure.

**OWE (Opportunistic Wireless Encryption)**: encrypts connections on open (no-password) networks using Diffie-Hellman per-client key exchange. Prevents passive eavesdropping on guest/public networks without requiring a password. Does not provide authentication. Ideal for guest SSIDs where password-free access is desired but eavesdropping protection is needed.

**PMF (Protected Management Frames / 802.11w)**: protects deauthentication, disassociation, and action frames. Prevents deauth flood attacks. Required for WPA3; optional (but strongly recommended) for WPA2.

## Site survey methodology

### Phase 1: requirements gathering

Before placing APs or opening a survey tool:
- Number of concurrent users and device types per area.
- Application requirements: voice (under 50 ms roam, under 100 ms jitter), video (over 5 Mbps per stream), data (varies by application).
- Coverage requirements by area type (office, conference room, warehouse, outdoor).
- Security requirements (WPA3 mandate, NAC, guest isolation).
- Regulatory domain and local regulations (FCC, ETSI, etc.).

### Phase 2: predictive design

Import floor plans with accurate scale into a survey tool (Ekahau, Hamina, iBwave):

| Material | Approximate attenuation per wall |
|---|---|
| Drywall (standard) | 3-4 dB |
| Glass (standard) | 2-3 dB |
| Glass (low-e / tinted) | 6-8 dB |
| Concrete block | 12-15 dB |
| Brick | 8-12 dB |
| Metal (elevator, server room) | 20+ dB |
| Wood door | 3-4 dB |
| Concrete floor/ceiling | 15-20 dB |

Coverage targets: -67 dBm RSSI for voice/video; -72 dBm for data; -75 dBm for basic connectivity. SNR targets: over 25 dB for reliable operation; over 35 dB for 1024-QAM.

Design for capacity, not just coverage. Modern wireless design is density-driven: more lower-power APs outperform fewer higher-power APs in dense environments.

### Phase 3: passive survey (on-site validation)

Walk the facility with survey equipment (Ekahau Sidekick, Wi-Fi scanner) measuring the actual RF environment:
- Identify noise sources: microwave ovens (2.4 GHz), Bluetooth, ZigBee, cordless phones, radar.
- Measure neighbouring AP interference (co-channel and adjacent channel).
- Verify wall attenuation matches the predictive model; adjust the model if measurements diverge significantly.
- Document areas with poor coverage or high interference.

### Phase 4: active survey (post-deployment)

Connect to the deployed network and measure actual performance:
- Test throughput at representative locations (iPerf or survey tool throughput test).
- Test roaming along expected movement paths; validate fast roaming handoff latency.
- Measure DHCP/DNS response times.
- Validate application performance (voice call quality, video streaming, business application latency).

### Phase 5: ongoing optimisation

- Monitor RRM/AirMatch changes and validate effectiveness.
- Review client connection statistics (retry rates, data rates, roaming failures).
- Re-survey after significant building changes (renovation, furniture rearrangement, new walls).
- Adjust AP placement, channel, and power settings based on real-world data.

## AP placement best practices

- **Height**: mount APs at 3-4 metres (10-13 feet) above floor level. Too high disperses the antenna pattern; too low creates coverage holes in adjacent areas.
- **Orientation**: mount internal-antenna APs horizontally (antenna plane parallel to floor). External-antenna APs per manufacturer guidance.
- **Cell overlap**: target -67 dBm at cell edge for voice/video. Adjacent AP coverage should overlap at -67 dBm for seamless roaming.
- **Co-channel separation**: minimum 19 dB signal separation between co-channel APs. RRM/AirMatch handles this dynamically; proper placement is the foundation.

## Band strategy

**2.4 GHz**: use for legacy device coverage only (IoT sensors, barcode scanners, older medical devices). Minimise transmit power. Disable 2.4 GHz radios on a subset of APs in high-density areas. Never use 40 MHz on 2.4 GHz in enterprise.

**5 GHz**: primary band for most clients. 40 or 80 MHz channels. Use all available channels including DFS unless radar events are frequent at the specific site.

**6 GHz**: dedicated band for Wi-Fi 6E/7 capable clients. AFC for standard-power operation. 80 or 160 MHz channels viable due to abundant spectrum. Design for smaller cell sizes than 5 GHz.

**Band steering**: enable on all platforms to push dual-band clients to 5/6 GHz. Monitor 2.4 GHz client count; high 2.4 GHz residency often indicates IoT/legacy devices that are 2.4 GHz-only.

## Data rate configuration

Disabling low data rates improves airtime efficiency by reducing the time weak-signal frames occupy the channel:
- **2.4 GHz**: disable 1, 2, 5.5 Mbps; set 11 Mbps as minimum mandatory. Consider 12 or 24 Mbps mandatory in dense environments.
- **5 GHz**: disable rates below 12 Mbps; set 12 or 24 Mbps as minimum mandatory.
- **6 GHz**: all clients support 802.11ax rates; default rates are appropriate.

Raising minimum data rates reduces effective cell size. Validate that coverage is maintained after any rate change. A cell that shrinks below the design coverage target requires additional APs or a rollback of the rate change.

## Common design pitfalls

1. **Designing for coverage instead of capacity**: in dense environments, more lower-power APs outperform fewer higher-power APs. More APs provide more spatial reuse and higher aggregate throughput.
2. **40 MHz channels on 2.4 GHz**: only 3 non-overlapping 20 MHz channels exist in 2.4 GHz. 40 MHz channels create massive co-channel interference. Never use 40 MHz on 2.4 GHz in enterprise.
3. **Ignoring client capabilities**: the AP advertises Wi-Fi 6E/7, but if clients only support Wi-Fi 5/6, the advanced features provide no benefit. Survey the client fleet before designing for 6E/7.
4. **6 GHz without WPA3 readiness**: 6 GHz requires WPA3; RADIUS/NAC infrastructure must support WPA3-Enterprise or WPA3-Personal before 6 GHz SSIDs will function.
5. **Over-relying on RRM/AirMatch without a baseline design**: automated RF management optimises within the constraints of AP placement. Poor placement cannot be corrected by software.
6. **Forgetting DFS impact near radar sources**: near airports, weather radar, or military installations, DFS channels may be frequently vacated. Design with sufficient non-DFS channel capacity as a fallback.
7. **Single-band SSIDs without considering the client population**: band restrictions per SSID can force specific client types to the correct band, but test before applying in production.
8. **Skipping roaming validation**: fast roaming (802.11k/v/r) must be tested with actual client devices. Some legacy clients do not support 802.11r and will fail to reconnect after a roam.
