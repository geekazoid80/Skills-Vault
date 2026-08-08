# Juniper Mist wireless operations

Mist is an AI-native cloud networking platform built from the ground up as a SaaS service. Unlike legacy platforms adapted for cloud management, Mist's management plane, AI/ML pipeline, and monitoring engine are all cloud-native microservices hosted on AWS. The platform manages wireless, wired (Juniper EX switches), and WAN (Session Smart Routers) from a single dashboard.

## Mist cloud architecture

**Infrastructure**:
- Multi-region AWS deployment (NA, EU, APAC) for data sovereignty compliance.
- Microservices: each function (monitoring, configuration, AI/ML, analytics, firmware) scales independently.
- APs and switches stream telemetry every second to the cloud event pipeline.
- ML pipeline runs dedicated anomaly detection, root-cause analysis, and predictive analytics models.

**Tenancy model**:
- Organisation (Org): top-level tenant; contains all sites, devices, users.
- Site: physical location; contains APs, switches, WAN devices.
- Site Group: logical grouping of sites for configuration inheritance.
- Network Template: reusable network configuration applied to sites or site groups.

**Data forwarding**: APs forward data locally (bridge to VLAN) by default. Optional: tunnel traffic to Mist Edge for centralised policy enforcement. Split-tunnel: corporate traffic to Mist Edge, guest traffic bridged locally. No on-premises controller for the data plane in the default model.

**Zero-touch provisioning (ZTP)**:
1. Device powers on; obtains IP via DHCP.
2. Resolves Mist cloud address via DNS or DHCP option.
3. Establishes HTTPS connection to Mist cloud.
4. Admin claims device to Org/Site via dashboard (or pre-claimed via activation code).
5. Mist pushes site configuration; device begins operation.

## Marvis AI assistant

Marvis is a purpose-built AI engine for network operations, not a generic chatbot:

**Natural-language troubleshooting**: query "Why is Wi-Fi slow at Building 3 Floor 2?" and Marvis correlates RF metrics, client statistics, SLE data, switch port status, and WAN SLA to identify root cause.

**Cross-domain correlation**: a single client issue traverses wireless, wired, and WAN checks simultaneously. Marvis correlates across all three to surface a single root cause, reducing MTTR by 50-80% compared to manual troubleshooting.

**Marvis Actions categories**:

| Category | Examples |
|---|---|
| AP Health | AP offline, AP rebooting, AP high utilisation |
| Connectivity | DHCP failure, DNS failure, authentication failure, gateway unreachable |
| RF | High co-channel interference, non-Wi-Fi interference, coverage hole |
| Switch | Port flapping, PoE failure, STP topology change, missing VLAN |
| WAN | Link down, SLA violation, path failover, high latency |
| Security | Rogue AP, unauthorised client, anomalous traffic pattern |

**Agentic workflows (2025-2026)**: Marvis can autonomously investigate and resolve routine issues spanning wired/wireless/WAN. For routine issues (AP channel change, reboot trigger), Marvis can act autonomously with admin approval. Complex issues escalate to a human operator with full diagnostic context.

## Marvis Minis

Marvis Minis are virtual network sensors that run on Mist APs and simulate complete client connections:

**How they work**:
1. Associate to the configured SSID.
2. Authenticate (802.1X, PSK, or open).
3. Obtain IP via DHCP (measures response time).
4. Resolve a configured DNS domain (measures response time).
5. Reach the default gateway (ping).
6. Reach a configured application URL (HTTP GET).

Results: pass/fail status and latency measurements per step. Failed steps include error detail (timeout, rejection, unreachable). Results feed into SLE metrics, Marvis AI anomaly detection, and the Org Insights NOC dashboard.

**Configuration**:
- Select the SSID to test; configure authentication credentials.
- Set test interval and alert threshold (trigger alert after N consecutive failures).
- Define custom application URL for application-specific reachability testing.
- Configure per site or per AP via Mist dashboard.

Minis are included with the platform but must be configured explicitly. Without Minis, proactive monitoring is limited to reactive alerts.

## Service Level Expectations (SLEs)

SLEs are Mist's measurable KPI framework. Each SLE has a target percentage and classifiers that break down root causes of failures.

**Wireless SLEs**:

| SLE | What it measures | Target example |
|---|---|---|
| Successful Connects | Percentage of connection attempts that succeed | Over 99% |
| Time to Connect | Duration of association + DHCP + authentication | Under 5 seconds |
| Throughput | Per-client throughput vs expected baseline | Over 10 Mbps |
| Coverage | Signal strength adequate for service | RSSI over -72 dBm |
| Roaming | Successful fast roaming events | Over 99% |
| Capacity | Channel utilisation vs threshold | Under 70% |
| AP Availability | AP uptime percentage | Over 99.9% |

**Wired SLEs**:

| SLE | What it measures |
|---|---|
| Switch Availability | Switch uptime and reachability |
| PoE Compliance | Power delivery within specification |
| AP Affinity | AP connected to expected switch and port |
| VLAN Compliance | Correct VLANs configured on AP switch ports |

**SLE classifiers**: each SLE failure is attributed to a root-cause classifier. Example for "Successful Connects" failures: authentication timeout, DHCP failure, association rejection, RADIUS unreachable, network misconfiguration. Fix the specific classifier, not just the aggregate percentage. Historical trends show improvement or degradation over time.

SLE thresholds are customisable per site or per SSID. Default thresholds are tuned from global telemetry across all Mist deployments.

## AP families

| Family | Wi-Fi standard | Bands | Key features |
|---|---|---|---|
| AP12 | Wi-Fi 6 | 2.4/5 GHz | Entry-level indoor; cost-effective |
| AP21 | Wi-Fi 6 | 2.4/5 GHz | General-purpose indoor enterprise |
| AP32 | Wi-Fi 6E | 2.4/5/6 GHz | First 6 GHz Mist AP |
| AP41 | Wi-Fi 6 | 2.4/5 GHz | General indoor enterprise |
| AP43/45 | Wi-Fi 6E | 2.4/5/6 GHz | High-density indoor; flagship 6E |
| AP63/64 | Wi-Fi 6E outdoor | 2.4/5/6 GHz | Outdoor/ruggedised; IP67 |

All Mist APs include: integrated BLE radio, USB port for IoT sensors, cloud-managed with zero-touch provisioning.

## Mist Edge

Mist Edge is an on-premises appliance (physical or virtual) for scenarios requiring centralised policy enforcement without an on-premises controller:

**Tunnel termination**: APs tunnel SSID traffic to Mist Edge via IPsec or GRE. Mist Edge decapsulates and forwards to local VLANs or WAN. Per-SSID configuration: corporate SSIDs tunnelled, guest SSIDs bridged locally.

**ZTNA connector**: Mist Edge acts as an application proxy for private resources. Clients authenticate via Mist identity; access granted per-application. No full VPN required; replaces VPN for specific application access. Integrates with identity providers (Okta, Azure AD, Google Workspace).

**RadSec proxy**: Mist Edge receives RADIUS from APs and forwards to an on-premises RADIUS/NPS/ClearPass server over TLS (RadSec). Simplifies firewall rules: a single Mist Edge IP rather than all AP IPs needing RADIUS access.

**Guest isolation**: dedicated internet path for guest SSIDs via Mist Edge; configurable bandwidth limits and content filtering.

**Mist Edge models**: physical appliance (dedicated hardware for high throughput), virtual appliance (VM on ESXi/KVM), clustered (multiple instances for HA and load balancing).

Deploy Mist Edge only when centralised policy enforcement or ZTNA is genuinely required; many deployments work well with local bridging.

## Wired Assurance

Wired Assurance extends Mist AI to Juniper EX switch management:
- **ZTP**: EX switches claim to Mist cloud via DHCP/DNS; no manual configuration.
- **AI-driven insights**: port anomalies, STP issues, PoE problems detected automatically.
- **Marvis Actions for switches**: suggested fixes for switch events.
- **CableSim**: virtual cable testing identifies cable/transceiver issues.
- **Unified dashboard**: switches, APs, and WAN devices visible in a single Mist dashboard.

Supported switches: EX2300, EX3400, EX4100, EX4300, EX4400, EX4650 series. Mist pushes configuration via NETCONF; Junos CLI also accessible for manual diagnostics.

**Key capabilities**:
- AP-Switch Affinity: Mist tracks which AP connects to which switch port; detects cabling errors.
- PoE Compliance: monitors per-port PoE delivery; alerts when APs are under-powered.
- VLAN Compliance: verifies switch port VLANs match expected configuration.

Mist's cross-domain correlation is most powerful with Wired Assurance enabled. Wireless-only deployments limit Marvis's ability to identify root causes involving switch ports.

## WAN Assurance

WAN Assurance integrates Juniper Session Smart Router (SSR) into the Mist AI platform:
- **SD-WAN**: SSR routers managed from Mist dashboard alongside wireless and wired.
- **Application-aware routing**: per-application SLA steering across WAN links (MPLS, broadband, LTE).
- **AI operations**: Mist AI detects WAN anomalies and correlates with wireless/wired issues.
- **Marvis Minis in WAN**: simulates user flows through WAN paths to detect issues proactively.
- **Session-based routing**: SSR uses session identity for routing, not tunnel encapsulation; zero-trust WAN model.

Cross-domain WAN correlation example: client Wi-Fi throughput degraded, AP RF is healthy, switch port is healthy, WAN link has a latency spike on the SSR. Marvis identifies WAN ISP latency as the root cause and recommends SSR path failover to the backup WAN link.

## BLE and location services

**vBLE (Virtual BLE)**: Mist's patented directional BLE technology uses a 16-element software-defined BLE antenna array in each AP to create directional beams. Multiple APs compute angle-of-arrival for BLE tag signals and triangulate position with sub-metre accuracy (1-3 metres). No external BLE beacons needed.

**Wi-Fi location**: RSSI triangulation combined with AI for 3-5 metre accuracy. Works with any Wi-Fi client (no BLE required). Adequate for zone-level location (room, area) but not precise positioning.

**Use cases**: asset tracking (BLE tags on equipment), wayfinding (turn-by-turn indoor navigation), proximity services (zone-entry/exit events), contact tracing (historical location data).

vBLE location requires accurate floor maps imported into Mist with correct scale and AP placement. Without floor maps, location accuracy degrades significantly.

## Mist REST API

```
GET  /api/v1/orgs/{org_id}/sites                    # List sites
GET  /api/v1/sites/{site_id}/devices                 # List APs and switches
GET  /api/v1/sites/{site_id}/stats/devices           # Device statistics
GET  /api/v1/sites/{site_id}/stats/clients           # Client statistics
POST /api/v1/sites/{site_id}/wlans                   # Create WLAN
GET  /api/v1/orgs/{org_id}/sles/{sle_metric}         # SLE data
POST /api/v1/sites/{site_id}/devices/claim           # Claim device
```

**Webhooks**: Mist streams events via webhook for real-time integration. Events include client connect/disconnect, AP status change, alert triggers, Marvis Action events. Integrations: ServiceNow, PagerDuty, Slack, custom event handlers.

**API token scope**: Mist tokens carry an Org-level or Site-level scope AND a role (read/write/admin). An Org-scoped read-only token cannot fetch Site-level config overrides without explicit Site role. Use an Org-level token with Site-inheritance read permission, or issue separate Org and Site read tokens for comprehensive monitoring.

## Common pitfalls

1. **Treating Mist like a traditional controller-based platform**: Mist is cloud-native. Embrace SLE-driven operations and Marvis AI instead of replicating on-premises controller CLI workflows.
2. **Ignoring SLE classifiers**: a 95% Successful Connects SLE is meaningless without the classifier showing "5% failure = DHCP timeout". Fix the classifier, not the aggregate percentage.
3. **Deploying without Wired Assurance**: cross-domain correlation is most powerful with wireless + wired + WAN visibility. Wireless-only limits Marvis root-cause analysis.
4. **Over-relying on Mist Edge**: Mist Edge is needed for tunnel termination and ZTNA; many deployments work well with local bridging. Only deploy Mist Edge when genuinely required.
5. **Not configuring Marvis Minis**: Minis are included but require explicit configuration. Without Minis, proactive monitoring is limited to reactive alerts.
6. **BLE deployment without floor maps**: vBLE location requires accurate floor maps with correct scale and AP placement.
7. **Expecting precise Wi-Fi location**: Wi-Fi-based location provides 3-5 metre accuracy (zone-level only). Sub-metre accuracy requires BLE tags with vBLE.
8. **Org-only API token for site-level audit**: Site-level config overrides are not visible with an Org-only token. Use Site-level read access or a token with Site-inheritance read for full visibility.
9. **Cloud connectivity requirements**: Mist requires outbound HTTPS (port 443) from APs to the Mist cloud. If internet connectivity fails, APs continue forwarding but lose management, monitoring, and Marvis AI.
