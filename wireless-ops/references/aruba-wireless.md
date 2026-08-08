# Aruba wireless operations

HPE Aruba Networking wireless spans two distinct platform generations. AOS 8 uses an on-premises Mobility Controller; AOS 10 is cloud-first, managed via Aruba Central (HPE GreenLake) with no on-premises controller required. The two are not compatible architectures; migrating from AOS 8 to AOS 10 is a full platform migration, not an upgrade.

## AOS 10 architecture

**Cloud management plane (Aruba Central)**
Aruba Central is a multi-tenant SaaS platform hosted on AWS:
- Provisions APs, gateways, and switches via templates or per-device GUI.
- Manages firmware (compliance baselines, staged rollouts, rollback).
- Runs AirMatch RF optimisation across all sites globally.
- Provides REST API for automation; all GUI operations are API-accessible.
- APs and gateways connect outbound via HTTPS; no inbound firewall rules needed.

**AOS 10 AP**
AOs 10 APs are intelligent edge devices:
- Run full AOS 10 firmware (Linux-based); maintain local client state.
- Forward data locally (bridge to VLAN) by default; optionally tunnel to gateway.
- Cache auth state for survivability during Central or gateway outage.
- Manage via Aruba Central; also accessible via AP CLI for diagnostics.

**Aruba Gateway**
On-premises appliance providing security and SD-WAN:
- Stateful firewall with role-based policies (roles assigned by ClearPass).
- Deep packet inspection (DPI) for application identification and URL filtering.
- SD-WAN: multi-WAN link management with application-aware path selection.
- ZTNA (Zero Trust Network Access) for private application access without full VPN.
- Tunneled Node: extends gateway policy enforcement to wired switch ports via GRE.

**AP-Gateway tunnel**:
```
Client -> AP (802.11) -> GRE tunnel -> Gateway -> Role-based firewall / DPI / WAN
```
Corporate SSID traffic tunnelled to gateway for policy enforcement; guest traffic can be bridged locally. If gateway is unreachable, AP falls back to local bridging (configurable).

## AOS 10 deployment options

| Option | Description | When to use |
|---|---|---|
| AP only (no gateway) | APs bridge traffic directly to local VLANs; limited security features | Small offices, retail with basic security needs |
| AP + Gateway | Full enterprise; gateway provides firewall, DPI, ZTNA, SD-WAN | Enterprise campus, branches needing security enforcement |
| Micro-branch | Single AP performs AP and gateway functions | Remote offices, kiosks, small retail with 1-3 APs |

## AOS 10 vs AOS 8 comparison

| Feature | AOS 10 | AOS 8 |
|---|---|---|
| Management | Aruba Central (cloud) | On-prem Mobility Controller |
| Control plane | Cloud-based | MC-based (on-premises) |
| Data plane | Local at AP or Gateway | Tunnel to MC (centralised default) |
| RF management | AirMatch (cloud AI, daily batch) | ARM (on-prem, real-time) |
| SD-WAN | Integrated into Gateway | Separate SD-WAN licence |
| Licensing | Subscription via Central | Per-feature perpetual licences |
| Scale | Central manages thousands of APs | Per-MC limits (model-dependent) |

## AP families

| Series | Wi-Fi standard | Bands | Notes |
|---|---|---|---|
| AP 3xx (305, 315, 345) | Wi-Fi 6 | 2.4/5 GHz | Value tier; small-medium office; 802.3at PoE+ |
| AP 5xx (515, 535, 555, 575) | Wi-Fi 6 / 6E | 2.4/5/6 GHz (6E models) | Enterprise indoor; 802.3bt (PoE++) for full tri-band |
| AP 6xx (635, 655) | Wi-Fi 6E outdoor | 2.4/5/6 GHz | Outdoor/ruggedised; IP-rated |
| AP 730 | Wi-Fi 7 (802.11be) | 2.4/5/6 GHz | Flagship; MLO; 320 MHz; AOS 10.7+; 802.3bt required |

Wi-Fi 6E and 7 APs require 802.3bt (PoE++) for full tri-band operation; 802.3at causes the AP to disable the 6 GHz radio to stay within power budget.

## AirMatch

AirMatch is Aruba's cloud-based AI RF optimisation engine, replacing the on-prem ARM used in AOS 8:
- Collects RF telemetry continuously from all APs (channel utilisation, neighbour RSSI, noise floor, client counts).
- Runs a global optimisation computation in Central, considering all APs across all sites.
- Pushes the optimised channel and power plan to APs once per day during a configured maintenance window.
- Manages 5 GHz and 6 GHz independently; 2.4 GHz uses ARM-style management.
- AOS 10.7 adds enhanced 6 GHz optimisation and AFC (Automated Frequency Coordination) integration for standard-power 6 GHz.

**AirMatch vs ARM**:
- ARM (AOS 8): real-time, event-driven changes; local AP-to-AP decisions; can cause RF churn.
- AirMatch (AOS 10): batch daily optimisation; global view; stable RF; slower reaction to sudden interference.

**Configuration**: Central > Configuration > RF > AirMatch. Set maintenance window for off-peak hours. Exclude specific APs from AirMatch when static channel/power is required (e.g. regulated environments). View proposed plan vs current plan before application.

Mixing AirMatch-managed and manually-pinned APs on the same site creates suboptimal RF. Commit to one approach per site.

## ClearPass integration (ops context)

ClearPass is the NAC backend for enterprise Aruba deployments. In an ops context (not security audit):

**Authentication methods**:
- 802.1X (EAP-TLS, PEAP, EAP-TTLS) for managed and BYOD devices.
- MAC Authentication Bypass (MAB) for IoT/headless devices.
- Guest portal (self-registration, sponsor approval, social login).
- ClearPass OnBoard for automated BYOD certificate provisioning.

**Authentication flow**:
```
1. Client associates to SSID
2. AP/Gateway sends RADIUS Access-Request to ClearPass
3. ClearPass EAP exchange with client
4. ClearPass validates against AD/LDAP/local DB
5. ClearPass returns Access-Accept with RADIUS attributes:
   - Aruba-User-Role: <role-name>
   - Tunnel-Private-Group-ID: <vlan-id>
   - Filter-Id: <acl-name>
6. AP/Gateway applies returned attributes to client session
```

**ClearPass components**:
- Policy Manager: core authentication/authorisation engine (RADIUS, TACACS+).
- Guest: guest management portal.
- OnBoard: BYOD certificate provisioning.
- OnGuard: endpoint posture agent (antivirus, patch level, disk encryption).
- Device Insight: AI-driven device profiling and classification.

**HA**: deploy ClearPass in publisher/subscriber cluster (minimum 2 nodes). Publisher handles DB writes; subscribers handle authentication. Place subscribers near gateways for low-latency RADIUS.

**Profiling data sources**: DHCP fingerprinting, MAC OUI, HTTP User-Agent, SNMP, OnConnect active scanning. Feeds into enforcement policy: "if device profiled as IP camera, assign IoT-Camera role."

## Dynamic segmentation

Dynamic segmentation enforces consistent access policy regardless of connection method (wired or wireless):
- ClearPass assigns a role based on user identity, device type, and posture.
- Role maps to a firewall policy on the Aruba Gateway.
- Policy follows the user across APs, sites, and wired/wireless transitions.
- No VLAN-based segmentation required for policy; VLANs still used for IP addressing.

**Role design guidance**:

| Role | Access | Example devices |
|---|---|---|
| Employee | Full internal + internet | Corporate laptops, phones |
| Contractor | Limited internal + internet | Contractor laptops |
| IoT-Camera | NVR subnet only (ports 554/443) | IP cameras |
| IoT-Sensor | IoT platform API only (HTTPS) | Environmental sensors |
| Guest | Internet only (DNS, HTTP, HTTPS) | Visitor devices |
| Quarantine | Remediation portal only | Non-compliant endpoints |

**Tunneled Node (wired extension)**:
- Wired switch ports configured as tunneled nodes.
- Traffic GRE-tunnelled to Aruba Gateway for policy enforcement.
- Same ClearPass-driven role/policy as wireless clients.
- Supported on Aruba CX switches (6200, 6300, 6400, 8320, 8400 series); not on legacy ArubaOS switches.

## SSID design

Limit to 3-4 SSIDs per AP. Each SSID adds beacon management frame overhead:
- **Corporate** (802.1X with ClearPass, WPA3-Enterprise): employee and managed device access.
- **IoT** (MAB with ClearPass profiling, WPA2/WPA3): sensors, cameras, printers, HVAC.
- **Guest** (ClearPass guest portal, OWE or open with captive portal): visitor internet.
- **BYOD** (optional, 802.1X with ClearPass OnBoard): employee personal devices with conditional access.

Use dynamic segmentation rather than separate SSIDs per user group; a single corporate SSID with role-based policy avoids SSID proliferation while maintaining per-group access control.

**WPA3 migration path**:
1. Enable WPA2+WPA3 transition mode on existing corporate SSID.
2. Create WPA3-only SSID for 6 GHz (required by the 6 GHz standard).
3. Once client fleet supports WPA3, convert corporate SSID to WPA3-only.
4. Disable WPA2 transition mode.
Monitor ClearPass authentication logs for WPA2 vs WPA3 client distribution during transition.

## Aruba Central management best practices

**Group hierarchy**: use template groups with Jinja2-style variables for sites with more than 10 APs (repeatability and consistency). Use UI groups for simple deployments.

**Firmware management**: define firmware compliance baselines per device type; Central flags non-compliant devices. Stage rollouts by site group; validate before proceeding to next group.

**Monitoring and alerting**: configure Central alerts for AP down (immediate), gateway down (immediate), high channel utilisation (over 70% sustained for over 15 minutes), authentication failure spike (over 10% failure rate over 5 minutes), ClearPass unreachable (authentication will fail).

## Aruba Central API

```
GET  /monitoring/v2/aps              # AP inventory and status
GET  /monitoring/v2/clients          # Connected client details
POST /configuration/v1/devices       # Push configuration to devices
GET  /analytics/v2/rogue_aps         # Rogue AP detection data
GET  /monitoring/v2/networks         # Network health metrics
```

Authentication: OAuth2 token-based via API Gateway. Use pycentral (official Python SDK) for automation; handles token management, pagination, and error handling.

## AOS 8 to AOS 10 migration

AOS 10 is a different architecture, not an upgrade from AOS 8. Treat it as a greenfield deployment:
1. Verify AP hardware supports AOS 10 (check compatibility matrix).
2. Provision APs in Aruba Central (create site, add licences).
3. Convert APs: factory reset or push AOS 10 image via Mobility Controller; APs discover Central via DHCP option or DNS.
4. Recreate WLAN configuration in Central (does not migrate from Mobility Controller).
5. Recreate ClearPass policies (role names may differ in AOS 10).
6. Migrate site-by-site; validate before proceeding.
7. Decommission Mobility Controllers after all APs migrated.

**Pre-migration checklist**:
- Verify AP hardware compatibility with AOS 10.
- Procure Central subscription licences (per-AP subscription model).
- Verify ClearPass version compatibility with AOS 10.
- Document existing AOS 8 SSID, VLAN, ACL, and role configuration.
- Create equivalent config in Central; test in a pilot site first.
- Plan for client disruption during AP conversion (5-10 minutes per AP).

## Common pitfalls

1. **AP-only without understanding security limitations**: AP-only mode lacks stateful firewall, DPI, and ZTNA. Gateway is required if security policies need traffic inspection.
2. **AOS 8 to AOS 10 assumptions**: configuration does not migrate 1:1; plan as a greenfield deployment.
3. **ClearPass version compatibility**: check compatibility matrix before upgrading either component (AOS 10 role attributes and RADIUS attribute handling may change).
4. **AirMatch overrides**: manually pinning channels/power on some APs while AirMatch manages others creates suboptimal RF. Commit to one approach.
5. **Gateway capacity undersizing**: gateways have throughput limits for firewall/DPI. Size for actual traffic volume, not just AP count.
6. **6 GHz without WPA3**: 6 GHz SSIDs require WPA3; ClearPass and RADIUS infrastructure must support WPA3 authentication methods.
7. **Cloud dependency planning**: while APs continue forwarding during Central outage, new client authentication, config changes, and monitoring stop. Plan for graceful degradation.
8. **Tunneled Node switch compatibility**: verify switch model and firmware before designing wired segmentation.
