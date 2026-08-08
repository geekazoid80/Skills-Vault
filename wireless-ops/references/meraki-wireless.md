# Cisco Meraki wireless operations

Meraki is a fully cloud-managed wireless platform operated via the Meraki Dashboard and Dashboard API. There is no CLI on Meraki APs; all configuration, monitoring, and diagnostics are done through the Dashboard or the REST API. The Meraki MCP server exposes key Dashboard API operations as named tools.

## MCP server

- **Repository**: CiscoDevNet/meraki-magic-mcp-community
- **Transport**: stdio (Python via FastMCP) or HTTP
- **Required credentials**: `MERAKI_API_KEY`, `MERAKI_ORG_ID`

## Key operations and MCP tools

| Operation | Tool | What it does |
|---|---|---|
| List SSIDs | `getWirelessSSIDs` | All 15 SSIDs per network with auth type, VLAN, band settings, and broadcast visibility |
| Update SSID | `updateWirelessSSID` | **[WRITE]** Name, auth type, PSK, VLAN, band, splash configuration |
| Wireless settings | `getWirelessSettings` | Network-level wireless configuration |
| List RF profiles | `getWirelessRFProfiles` | RF profiles with band selection, power limits, and channel settings |
| Create RF profile | `createWirelessRFProfile` | **[WRITE]** New RF profile with band/power/channel config |
| Channel utilisation | `getWirelessChannelUtilization` | Per-AP channel utilisation over time |
| Signal quality | `getWirelessSignalQuality` | SNR and signal strength metrics over time |
| Connection stats | `getWirelessConnectionStats` | Success/failure rates, association, auth, DHCP stats |
| Client events | `getWirelessClientConnectivityEvents` | Per-client roaming, auth, deauth, and DHCP events |

All tools are invoked via the Meraki MCP server with JSON parameters.

**WRITE operations note**: `updateWirelessSSID` and `createWirelessRFProfile` change live configuration; treat as production-impacting changes. SSID changes disconnect all currently connected clients on that SSID. RF profile changes propagate to all APs assigned to the profile. Apply per change-control policy.

## Workflow: wireless health assessment

When asked "how is the Wi-Fi?":

1. **SSIDs**: `getWirelessSSIDs` : which SSIDs are enabled; auth types (PSK/802.1X/open); VLANs; band restrictions.
2. **Connection stats**: `getWirelessConnectionStats` : success/failure rates; association, auth, DHCP success percentages.
3. **Channel utilisation**: `getWirelessChannelUtilization` : congestion hotspots per AP and per channel.
4. **Signal quality**: `getWirelessSignalQuality` : SNR trends and signal strength over time.
5. **RF profiles**: `getWirelessRFProfiles` : power limits, channel width, band-steering configuration.
6. **Report**: wireless health summary with per-SSID and per-AP metrics; flag APs with utilisation over 70% or SNR below 20 dB.

## Workflow: client connectivity troubleshooting

When investigating "user X cannot connect to Wi-Fi":

1. **Find client**: `getNetworkClients` (from meraki-network-ops or Dashboard) filtered by MAC address.
2. **Client events**: `getWirelessClientConnectivityEvents` : look for authentication failures, DHCP issues, and roaming events in the event timeline.
3. **Connection stats**: `getWirelessConnectionStats` : compare network-wide failure rates to determine if the issue is client-specific or systemic.
4. **AP signal quality**: `getWirelessSignalQuality` for the AP serving this client : is SNR adequate?
5. **Channel utilisation**: `getWirelessChannelUtilization` for the same AP : is the channel congested?
6. **SSID config**: `getWirelessSSIDs` : verify auth settings, VLAN assignment, and band restrictions for the SSID the client is using.
7. **Report**: root-cause analysis with a specific fix recommendation. Distinguish client-specific failures (single client events) from systemic failures (elevated failure rates across the network).

## Workflow: RF optimisation

When optimising wireless performance:

1. **Current RF**: `getWirelessRFProfiles` : existing band/power/channel settings.
2. **Channel utilisation**: `getWirelessChannelUtilization` across all APs : identify congestion hotspots.
3. **Signal quality**: `getWirelessSignalQuality` : identify low-SNR areas.
4. **Connection stats**: `getWirelessConnectionStats` : failure hotspots correlated with RF data.
5. **Recommendation**: adjust RF profiles (channel width, power limits, band-steering thresholds) based on the above data.
6. **Apply**: `createWirelessRFProfile` or update the existing profile via the Meraki MCP server : apply per change-control policy.

## RF thresholds and decision points

| Metric | Good | Acceptable | Action needed |
|---|---|---|---|
| Channel utilisation | Under 50% | 50-70% | Over 70%: investigate congestion |
| SNR | Over 25 dB | 20-25 dB | Under 20 dB: coverage or interference issue |
| RSSI (data clients) | Over -67 dBm | -67 to -72 dBm | Under -72 dBm: coverage gap |
| Connection success rate | Over 98% | 95-98% | Under 95%: investigate by failure type |

Channel utilisation over 50% is a warning indicator; over 70% is critical and requires RF optimisation action.

## SSID configuration notes

Meraki supports up to 15 SSIDs per network. Each SSID is either enabled (broadcasting) or disabled:
- Disabled SSIDs still consume a configuration slot; flag unused disabled SSIDs for cleanup.
- SSID changes (auth type, VLAN, band restrictions) are network-wide and affect all APs in the network simultaneously.
- Band restrictions: SSIDs can be restricted to 2.4 GHz, 5 GHz, or 6 GHz (6E APs), or allowed on all bands.
- Splash pages (captive portal): Meraki supports click-through, sign-on, sponsored guest, and billing splash types; configured per SSID.

## RF profile configuration notes

RF profiles are assigned to APs and control radio behaviour:
- **Band selection**: enable/disable per band (2.4/5/6 GHz) per profile.
- **Channel width**: 20/40/80 MHz per band; 160 MHz on 6 GHz capable APs.
- **Power limits**: minimum and maximum transmit power per band.
- **Band steering**: encourage dual-band clients to connect to 5 or 6 GHz.
- **RX-SOP (Receive Start of Packet)**: raise the sensitivity threshold to ignore weak signals from distant APs; improves performance in dense environments.
- **Channel planning**: Meraki uses Auto-RF for dynamic channel assignment. Manual channel overrides are possible per AP for specific requirements.

RF profiles are network-wide: changes propagate to all APs assigned to that profile. Apply per change-control policy before modifying a production profile.

## Environment variables

- `MERAKI_API_KEY`: Meraki Dashboard API key (treat as a credential; store in a secret manager per `secrets-hygiene`; rotate after any credential-exposure incident).
- `MERAKI_ORG_ID`: Meraki organisation ID.

## Important operational rules

- **SSID changes affect all users**: changing auth type, VLAN assignment, or band settings on a live SSID disconnects all clients on that SSID. Treat as change-controlled; schedule during a maintenance window.
- **RF profile changes are network-wide**: modifications propagate to all APs in the network assigned to the affected profile. Assess impact across all sites before making changes.
- **Write operations require change control**: apply `updateWirelessSSID`, `createWirelessRFProfile`, and any Dashboard configuration push per change-control policy.
- **No CLI on Meraki APs**: all configuration and diagnostics are via Dashboard or API. Packet capture is available via Dashboard (Tools > Packet Capture) on a per-AP basis.
- **Rate limiting**: Meraki Dashboard API is rate-limited at 10 requests per second per organisation. Build appropriate delays into automation scripts.

## Common pitfalls

1. **Channel utilisation over 70% without RF action**: high channel utilisation degrades all clients on the affected AP. Investigate congestion cause (too many clients, too few APs, co-channel interference from neighbouring APs) before adjusting power or channel width.
2. **Single network for large geographically distributed deployments**: Meraki organises APs into Networks; RF profiles and SSID configs apply network-wide. For geographically distributed deployments with different RF requirements, use separate networks.
3. **Not reviewing event timeline before changing config**: `getWirelessClientConnectivityEvents` frequently reveals that the issue is DHCP or RADIUS, not wireless RF. Diagnose before changing wireless config.
4. **Enabling 6 GHz without WPA3**: Meraki 6 GHz SSIDs require WPA3; there is no WPA2 fallback in the 6 GHz band. Verify client fleet and RADIUS infrastructure WPA3 readiness before activating.
5. **Missing band restrictions for IoT SSIDs**: IoT devices often support 2.4 GHz only. Ensure IoT SSIDs are enabled on 2.4 GHz; disabling 2.4 GHz breaks IoT connectivity.
6. **Using Auto-RF in dense multi-AP environments without reviewing the result**: Auto-RF provides a good starting point but may not be optimal for high-density environments. Review channel utilisation and SNR after Auto-RF settles; override per-AP channels where needed.
