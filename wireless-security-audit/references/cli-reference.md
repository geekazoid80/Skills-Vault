# Wireless controller CLI / API reference

Read-only commands and API endpoints for wireless security audit across six platforms: Cisco AireOS, Cisco IOS-XE-WLC (Catalyst 9800), Aruba AOS Mobility Controller, Aruba AOS-CX wireless gateway, Cisco Meraki, and Juniper Mist. Organised by audit category matching the procedure steps in SKILL.md.

All commands are read-only (`show` / `display` / `GET`). No configuration changes.

Per-vendor-family table grouping (Cisco platforms / Aruba platforms / cloud platforms) keeps each table at a readable width vs a single 7-column table.

## SSID Configuration Audit

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| List all SSIDs | `show wlan summary` | `show wlan summary` |
| SSID detail (security, VLAN, auth) | `show wlan <id>` | `show wlan id <id>` (security at WLAN profile) + `show wireless profile policy detailed <name>` (VLAN at bound Policy profile) |
| SSID status (enabled / disabled) | `show wlan summary` (Status column) | `show wlan summary` (Status column) |
| VLAN assignment | `show wlan <id>` -> Interface field | `show wireless profile policy detailed <name>` -> VLAN field |
| Broadcast SSID / hidden | `show wlan <id>` -> Broadcast SSID | `show wlan id <id>` -> Broadcast SSID field |
| Policy tag binding | n/a (integrated config model) | `show wireless tag policy summary` + `show wireless tag policy detailed <tag-name>` |
| RF tag binding | n/a (integrated config model) | `show wireless tag rf summary` + `show wireless tag rf detailed <tag-name>` |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| List all SSIDs | `show wlan ssid-profile` | `show wlan ssid-profile` (subset; route to AOS MC for full list if gateway is downstream) |
| SSID detail (security, VLAN, auth) | `show wlan ssid-profile <name>` | `show wlan ssid-profile <name>` (limited; AOS MC has fuller output) |
| SSID status (enabled / disabled) | `show wlan virtual-ap` | n/a (use AOS MC) |
| VLAN assignment | `show wlan virtual-ap` -> VLAN | `show wlan virtual-ap` -> VLAN (gateway-bridged) |
| Broadcast SSID / hidden | `show wlan ssid-profile <name>` -> Hide SSID | `show wlan ssid-profile <name>` -> Hide SSID |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| List all SSIDs | `GET /networks/{networkId}/wireless/ssids` | `GET /orgs/{org_id}/wlans` (Org templates) + `GET /sites/{site_id}/wlans` (Site overrides) |
| SSID detail (security, VLAN, auth) | `GET /networks/{networkId}/wireless/ssids/{number}` | `GET /sites/{site_id}/wlans/derived` (effective config after Org / Site merge) |
| SSID status (enabled / disabled) | Response field `enabled` in SSID endpoint | Response field `enabled` in WLAN endpoint |
| VLAN assignment | Response field `vlanId` in SSID endpoint | Response field `vlan_id` in WLAN endpoint |
| Broadcast SSID / hidden | Response field `visible` in SSID endpoint | Response field `hide_ssid` in WLAN endpoint |
| Per-site override (multi-site) | Network-scope inheritance from organisation defaults | `GET /sites/{site_id}/wlans/derived` shows the effective post-merge config |

## Authentication and Encryption Audit

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| Encryption mode (WPA2 / WPA3) | `show wlan <id>` -> Security Policies | `show wlan id <id>` -> Security Policies section |
| Auth method (PSK / 802.1X / Open) | `show wlan <id>` -> Authentication | `show wlan id <id>` -> Auth Key Management |
| PMF status | `show wlan <id>` -> PMF | `show wlan id <id>` -> PMF |
| Key management (AKM) | `show wlan <id>` -> AKM | `show wlan id <id>` -> AKM (e.g. dot1x, sae, ft-dot1x) |
| Cipher suite | `show wlan <id>` -> Encryption Cipher | `show wlan id <id>` -> Cipher (e.g. ccmp, gcmp256) |
| FT (Fast Transition / 802.11r) | `show wlan <id>` -> Fast Transition Support | `show wlan id <id>` -> Fast Transition |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| Encryption mode (WPA2 / WPA3) | `show wlan ssid-profile <name>` -> WPA version | `show wlan ssid-profile <name>` -> WPA version |
| Auth method (PSK / 802.1X / Open) | `show wlan ssid-profile <name>` -> Authentication | `show wlan ssid-profile <name>` -> Authentication |
| PMF status | `show wlan ssid-profile <name>` -> Management Frame Protection | `show wlan ssid-profile <name>` -> Management Frame Protection |
| Key management (AKM) | `show wlan ssid-profile <name>` -> Key Management | `show wlan ssid-profile <name>` -> Key Management |
| Cipher suite | `show ap wlan-encryption-stats` | n/a (use AOS MC) |
| FT (Fast Transition / 802.11r) | `show wlan ssid-profile <name>` -> 802.11r | n/a (use AOS MC) |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| Encryption mode (WPA2 / WPA3) | Response field `encryptionMode` in SSID endpoint | Response field `auth.type` in WLAN endpoint (values: open, psk, wpa2-psk, wpa3-psk, eap, wpa3-eap, wpa3-enterprise-192) |
| Auth method (PSK / 802.1X / Open) | Response field `authMode` in SSID endpoint | Response field `auth.type` in WLAN endpoint |
| PMF status | Response field `wpa3` settings in SSID endpoint | Response field `auth.pmf` in WLAN endpoint (values: disabled, optional, required) |
| Key management (AKM) | Implicit in `encryptionMode` and `wpa3` fields | Response field `auth.key_format` (variants per auth type) |
| Cipher suite | Implicit in `encryptionMode` | Implicit in `auth.type` |
| FT (Fast Transition / 802.11r) | Response field `dot11r.enabled` (when 802.1X) | Response field `auth.fast_roaming` |

## 802.1X / RADIUS Validation

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| RADIUS server list | `show radius summary` | `show aaa servers` (filtered for RADIUS) + `show running-config aaa` |
| RADIUS server status | `show radius auth statistics` | `show aaa servers` -> State / Throttle / Latency fields |
| RADIUS accounting | `show radius acct statistics` | `show aaa servers` -> Accounting block |
| EAP type observed (RADIUS side) | `show client detail <mac>` -> EAP Type | `show wireless client mac <mac> detail` -> EAP Type |
| Certificate auth status | `show certificate summary` | `show crypto pki certificate` |
| Timeout / retry config | `show radius summary` -> Timeout | `show aaa servers` -> Server-Tout |
| RadSec (RADIUS over TLS) | n/a (limited support) | `show running-config | section radsec` |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| RADIUS server list | `show aaa authentication-server all` | `show radius-server` (subset; AOS MC has fuller view) |
| RADIUS server status | `show aaa authentication-server radius statistics` | `show radius-server statistics` |
| RADIUS accounting | `show aaa accounting statistics` | n/a (use AOS MC) |
| EAP type observed (RADIUS side) | `show user <mac>` -> Authentication method | n/a (use AOS MC) |
| Certificate auth status | `show crypto pki certificate` | `show crypto pki certificate` |
| Timeout / retry config | `show aaa authentication-server radius` -> Timeout | `show radius-server` -> Timeout |
| RadSec (RADIUS over TLS) | `show aaa rfc-3576-server` (limited) | n/a (use AOS MC) |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| RADIUS server list | `GET /networks/{networkId}/wireless/ssids/{number}` -> `radiusServers` array | WLAN endpoint -> `auth_servers` array (per WLAN) |
| RADIUS server status | Dashboard: Wireless > Access Control > RADIUS servers (no API) | `GET /sites/{site_id}/stats/radius_servers` |
| RADIUS accounting | Response field `radiusAccountingEnabled` + `radiusAccountingServers` array | WLAN endpoint -> `acct_servers` array |
| EAP type observed (RADIUS side) | `GET /networks/{networkId}/clients/{clientId}` (limited; client-side only) | `GET /sites/{site_id}/clients/{client_mac}/events` (auth events) |
| Certificate auth status | Dashboard: Organisation > Certificates (no API) | `GET /orgs/{org_id}/certificates` |
| Timeout / retry config | SSID endpoint -> `radiusServers[].timeout` | WLAN endpoint -> `auth_servers_timeout` |
| RadSec (RADIUS over TLS) | n/a (Meraki uses internal Meraki Auth or external RADIUS over UDP) | WLAN endpoint -> `auth_servers[].radsec` (boolean per server) |

## Rogue AP Detection

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| Rogue AP summary | `show rogue ap summary` | `show wireless wps rogue ap summary` |
| Rogue AP detail | `show rogue ap detailed <mac>` | `show wireless wps rogue ap detailed <mac>` |
| Rogue classification | `show rogue ap summary` -> Class column | `show wireless wps rogue ap summary` -> Class |
| Rogue containment status | `show rogue ap summary` -> Containment | `show wireless wps rogue ap summary` -> Containment |
| Rogue client count | `show rogue ap clients <mac>` | `show wireless wps rogue client summary` |
| Wired-side correlation (RLDP) | `show rogue ap detailed <mac>` -> RLDP status | `show wireless wps rogue ap detailed <mac>` -> RLDP State |
| Adhoc rogue networks | `show rogue adhoc summary` | `show wireless wps rogue adhoc summary` |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| Rogue AP summary | `show wids-event` | n/a (use AOS MC) |
| Rogue AP detail | `show wids-event detail <id>` | n/a (use AOS MC) |
| Rogue classification | `show wids-event` -> Classification | n/a (use AOS MC) |
| Rogue containment status | `show wids containment` | n/a (use AOS MC) |
| Rogue client count | `show wids-event` -> Associated clients | n/a (use AOS MC) |
| Wired-side correlation | `show wids ap-classification-rules` | n/a (use AOS MC) |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| Rogue AP summary | `GET /networks/{networkId}/wireless/airMarshal` | `GET /sites/{site_id}/insights/rogues` |
| Rogue AP detail | Air Marshal event detail in response body | `GET /sites/{site_id}/insights/rogues/{rogue_bssid}` |
| Rogue classification | Response field `type` (allowed values: rogue, interferer, neighbor) | Response field `type` (values: rogue, neighbor, honeypot) |
| Rogue containment status | Air Marshal: containment status in response | `GET /sites/{site_id}/setting` -> `rogue.honeypot_enabled` and related fields |
| Rogue client count | Air Marshal response includes client details | `GET /sites/{site_id}/insights/rogue/{rogue_bssid}/clients` |
| Wired-side correlation | Air Marshal SSID matching against Meraki-managed SSID list | Mist marks rogue with `wired_mac` field when correlation succeeds |

## RF Security Assessment

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| Channel assignment | `show 802.11a` / `show 802.11b` | `show ap dot11 5ghz summary` / `show ap dot11 24ghz summary` / `show ap dot11 6ghz summary` |
| Transmit power | `show 802.11a` / `show 802.11b` | `show ap dot11 5ghz summary` -> Tx Power |
| Channel utilisation | `show 802.11a cleanair device ap` | `show ap dot11 5ghz cleanair air-quality summary` |
| AP radio status | `show ap summary` | `show ap summary` |
| Noise floor | `show 802.11a cleanair` | `show ap dot11 5ghz cleanair air-quality detail <ap-name>` |
| DFS events | `show 802.11a dfs` | `show ap dot11 5ghz dfs` |
| RF profile config | `show advanced 802.11a / b txpower` | `show ap rf-profile summary` + `show ap rf-profile detailed <profile-name>` |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| Channel assignment | `show ap radio-database` | n/a (use AOS MC) |
| Transmit power | `show ap radio-database` -> Power | n/a (use AOS MC) |
| Channel utilisation | `show ap arm-rf-summary` | n/a (use AOS MC) |
| AP radio status | `show ap database` | `show ap database` (gateway-bridged AP list) |
| Noise floor | `show ap arm-state` | n/a (use AOS MC) |
| DFS events | `show ap dfs-event` | n/a (use AOS MC) |
| RF profile config | `show rf 80211a-radio-profile` / `show rf 80211g-radio-profile` | n/a (use AOS MC) |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| Channel assignment | `GET /networks/{networkId}/wireless/rfProfiles` -> per-band channel settings | `GET /sites/{site_id}/rfdiags/ap_channel` (per-AP) |
| Transmit power | `GET /devices/{serial}/wireless/status` | `GET /sites/{site_id}/stats/devices` -> Tx Power per AP |
| Channel utilisation | `GET /networks/{networkId}/wireless/channelUtilizationHistory` | `GET /sites/{site_id}/stats/devices` -> `radio_stat.<band>.usage` |
| AP radio status | `GET /networks/{networkId}/devices` | `GET /sites/{site_id}/devices?type=ap` |
| Noise floor | `GET /networks/{networkId}/wireless/channelUtilizationHistory` -> noise data per AP | `GET /sites/{site_id}/stats/devices` -> `radio_stat.<band>.noise_floor` |
| DFS events | Dashboard: Wireless > Radio settings (no API) | `GET /sites/{site_id}/events/devices?type=dfs` |
| RF profile config | `GET /networks/{networkId}/wireless/rfProfiles` + `GET /networks/{networkId}/wireless/rfProfiles/{rfProfileId}` | `GET /orgs/{org_id}/rftemplates` + `GET /sites/{site_id}/setting` -> rftemplate_id |

## Client Assessment

### Cisco platforms

| Audit check | [AireOS] | [IOS-XE-WLC] |
|---|---|---|
| Connected clients | `show client summary` | `show wireless client summary` |
| Client detail | `show client detail <mac>` | `show wireless client mac <mac> detail` |
| Client protocol (WPA2 / WPA3) | `show client detail <mac>` -> Security | `show wireless client mac <mac> detail` -> Security |
| Client RSSI / SNR | `show client detail <mac>` -> RSSI | `show wireless client mac <mac> detail` -> RSSI / SNR |
| Guest portal clients | `show custom-web webauth-bundle` | `show running-config | section parameter-map` (web-auth params) |

### Aruba platforms

| Audit check | [Aruba AOS] | [Aruba AOS-CX] |
|---|---|---|
| Connected clients | `show user-table` | `show user-table` (gateway-bridged subset) |
| Client detail | `show user <mac>` | `show user <mac>` (limited; AOS MC has fuller view) |
| Client protocol (WPA2 / WPA3) | `show user <mac>` -> Auth type | n/a (use AOS MC) |
| Client RSSI / SNR | `show user <mac>` -> Signal / SNR | n/a (use AOS MC) |
| Guest portal clients | `show captive-portal` | n/a (use AOS MC) |

### Cloud platforms

| Audit check | [Meraki] | [Mist] |
|---|---|---|
| Connected clients | `GET /networks/{networkId}/wireless/clients` | `GET /sites/{site_id}/stats/clients` |
| Client detail | `GET /networks/{networkId}/clients/{clientId}` | `GET /sites/{site_id}/clients/{client_mac}/stats` |
| Client protocol (WPA2 / WPA3) | Client endpoint -> `status` field | Client stats -> `key_mgmt` field |
| Client RSSI / SNR | `GET /networks/{networkId}/wireless/clients/{clientId}/connectionStats` | Client stats -> `rssi` and `snr` fields |
| Guest portal clients | `GET /networks/{networkId}/wireless/ssids/{number}/splashSettings` | `GET /sites/{site_id}/wlans/{wlan_id}/portal` |

## Notes on platform differences

### Cisco AireOS vs IOS-XE-WLC (Catalyst 9800)

The migration from AireOS to IOS-XE-WLC is more than a syntax change: the config model changes from integrated WLAN config (one WLAN object holds security + VLAN + QoS) to a tag-based config model with independent objects bound via Policy / Site / RF tags.

- **WLAN profile**: security only (encryption, authentication, AKM, PMF).
- **Policy profile**: VLAN, QoS, session timeout, ACL.
- **AP join profile**: management plane settings (NTP server, mgmt VLAN, capwap timers).
- **RF profile**: radio band settings (channel, power, beam-forming).
- **Site tag**: binds AP join profile + flex profile to a Site.
- **Policy tag**: binds WLAN profile + Policy profile to a Site.
- **RF tag**: binds RF profile (2.4 GHz, 5 GHz, 6 GHz) to a Site.

An IOS-XE-WLC SSID audit must check BOTH the WLAN profile (security) AND the bound Policy profile (VLAN, ACL). Drift between them is silent: each object validates independently at config time, and the binding lookup happens at AP join time.

Cisco Catalyst 9800 Series Wireless Controller Software Configuration Guide (17.x) is the authoritative source; see chapters on Profiles and Tags and WLAN configuration.

### Aruba AOS Mobility Controller vs AOS-CX wireless gateway

AOS Mobility Controller (running ArubaOS 8.x) is the mature, full-featured WLAN platform: full WIDS / WIPS, ARM RF management, deep client visibility, mature rogue classification.

AOS-CX wireless gateway is a newer deployment model where an AOS-CX switch terminates CAPWAP tunnels from APs and provides VLAN bridging without a dedicated Mobility Controller. Suitable for small branch sites; many advanced WLAN features are not implemented or require routing back to a central AOS Mobility Controller. Audit commands marked `n/a (use AOS MC)` above route back to the controller.

Aruba AOS-CX Wireless Bridging deployment guide is the authoritative source for the gateway-mode feature set.

### Meraki: API-only automation

Meraki wireless management is cloud-based with no device-level CLI access. All automation uses the Meraki Dashboard API:

- Base URL: `https://api.meraki.com/api/v1`
- Authentication: API key via `X-Cisco-Meraki-API-Key` header
- Rate limit: 10 requests per second per organisation
- Air Marshal (rogue detection) requires the appropriate licence tier (Meraki MR Advanced or Enterprise)
- Pagination: use `Link` header with `next` rel for cursor-based pagination on list endpoints

Some operational data (RADIUS server health, certificate management, manual Air Marshal allow-list editing) is Dashboard-only with no API equivalent.

### Mist: API-only automation with regional endpoints

Mist wireless management is cloud-based with no device-level CLI access. All automation uses the Mist Cloud API:

- Base URL: regional, per Org location:
  - Global: `https://api.mist.com/api/v1`
  - EMEA: `https://api.eu.mist.com/api/v1`
  - APAC: `https://api.ac2.mist.com/api/v1`
  - Canada: `https://api.gc1.mist.com/api/v1`
- Authentication: `Authorization: Token <token>` header
- Rate limit: per-Org limits documented in Mist API docs; respect HTTP 429 backoff
- Org / Site scope: tokens carry Org-level OR Site-level scope; effective config (`/sites/{site_id}/wlans/derived`) requires Site read scope minimum

Mist API documentation (api.mist.com/api/v1/docs) is the authoritative source; the schema is OpenAPI-described.

### RFC 5424 syslog facility / severity (cross-platform)

All six platforms forward syslog using RFC 5424. Severity 0-7 (Emergency through Debug). Vendor defaults:

- AireOS: `local7` by default; configurable per syslog server.
- IOS-XE-WLC: `local7` by default (matches generic Cisco IOS-XE).
- Aruba AOS / AOS-CX: `local4` by default; configurable per logging-host.
- Meraki: cloud-side syslog forwarding via Network > Alerts; uses standard facility codes.
- Mist: cloud-side syslog forwarding via Site setting; uses standard facility codes.

For SIEM correlation across the wireless estate, use the SIEM-side Prerequisites in `siem-log-analysis`. For no-SIEM raw-syslog parsing, see `network-log-analysis`.
