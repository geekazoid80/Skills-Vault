# Platform selection, architecture, and integration

Profiles of the main monitoring platforms, a decision method for choosing among them, the common monitoring-architecture patterns, and how the pieces integrate into a complete stack.

## Platform profiles

### SolarWinds NPM

- **Type**: on-premises enterprise NMS.
- **Strengths**: comprehensive SNMP monitoring, SQL-backed, NetPath, PerfStack correlation, a large module ecosystem.
- **Considerations**: high cost (per-module licensing), a Windows/IIS/SQL dependency, complex deployment.
- **Best for**: mid-to-large enterprises with on-premises infrastructure and a dedicated monitoring team. Named here as routing context; deep per-vendor depth is not yet in this vault.

### LibreNMS

- **Type**: open-source self-hosted NMS.
- **Strengths**: free, 10,000+ device definitions, auto-discovery, Oxidized config backup, Grafana integration, distributed polling.
- **Considerations**: self-managed (hosting, updates, scaling), community support, no commercial SLA without a third party.
- **Best for**: budget-conscious organisations, homelab to mid-enterprise, teams comfortable with self-hosted open source. Named here as routing context; deep per-vendor depth is not yet in this vault.

### PRTG

- **Type**: on-premises plus SaaS NMS with sensor-based licensing.
- **Strengths**: free 100-sensor tier, auto-discovery, visual maps, quick setup, predictable sensor-based pricing.
- **Considerations**: Windows-based on-premises, sensor count grows quickly, limited flow analytics.
- **Best for**: SMB to mid-market wanting quick deployment with predictable costs. Deep depth: `prtg-network-monitoring`.

### Kentik

- **Type**: SaaS flow analytics plus BGP plus synthetic.
- **Strengths**: massive-scale flow analytics, BGP monitoring, DDoS detection, AI insights, natural-language queries.
- **Considerations**: high enterprise pricing, flow-centric (limited SNMP relative to a traditional NMS), focused on traffic analysis.
- **Best for**: service providers, large enterprises with heavy traffic-analysis needs, DDoS-sensitive environments. Deep depth: `kentik-network-monitoring`.

### Cacti

- **Type**: open-source self-hosted graphing and polling (RRDtool-based).
- **Strengths**: free, mature SNMP graphing, template-driven, plugin ecosystem (thresholding, weathermaps), low resource footprint.
- **Considerations**: graphing-first (alerting via plugin), dated UI, manual scaling.
- **Best for**: budget-conscious SNMP graphing, homelab to mid-enterprise. Deep depth: `cacti-network-monitoring`.

### Zabbix

- **Type**: open-source self-hosted monitoring that straddles general infrastructure and SNMP NMS.
- **Strengths**: free, templates and low-level discovery, agent and agentless, flexible triggers, dependent items.
- **Considerations**: configuration learning curve, database sizing at scale.
- **Best for**: teams wanting one platform for servers and network devices. Deep depth: `zabbix-templates-and-triage`.

### Nagios

- **Type**: open-source check-based monitoring (and commercial Nagios XI).
- **Strengths**: mature, vast plugin library, simple check model.
- **Considerations**: check-centric rather than metric-centric, dated core, configuration overhead. Named here as routing context.

### ThousandEyes

- **Type**: SaaS synthetic monitoring plus internet intelligence.
- **Strengths**: a global cloud-agent network, path visualisation, Internet Insights outage detection, SD-WAN integration.
- **Considerations**: high consumption-based cost, no SNMP/device monitoring, focused on connectivity and SaaS.
- **Best for**: organisations reliant on SaaS, multi-ISP environments. Named here as routing context; deep per-vendor depth is not yet in this vault.

## Decision method

1. **Identify the dominant paradigm.** Device health leans SNMP NMS (LibreNMS, PRTG, SolarWinds, Zabbix, Cacti). Traffic analysis leans flow (Kentik). User experience leans synthetic (ThousandEyes). Most real networks need more than one.
2. **Fix the budget and licensing model.** Open-source self-hosted (LibreNMS, Cacti, Zabbix, Nagios) trades licence cost for operational effort; sensor-priced (PRTG) is predictable; per-module or consumption (SolarWinds, Kentik, ThousandEyes) scales with the estate.
3. **Fix the deployment posture.** On-premises (SolarWinds, Zabbix, LibreNMS, Cacti, PRTG) versus SaaS (Kentik, ThousandEyes, PRTG Hosted Monitor).
4. **Match scale.** Small estates run a single open-source poller; thousands of devices across sites need distributed polling or a SaaS platform built for scale.
5. **Decide on a stack, not a single tool.** A complete deployment commonly combines an NMS, a flow platform, a synthetic platform, and a unifying dashboard.

## Monitoring architecture patterns

### Single-site

```
[Devices]  -> SNMP/ICMP   -> [NMS Server]
[Routers]  -> NetFlow/sFlow -> [Flow Collector]
[NMS Server] -> Alerts -> [Notification Channels]
```

### Multi-site with distributed polling

```
[Site A Devices] -> [Remote Poller A] --HTTPS--> [Central NMS]
[Site B Devices] -> [Remote Poller B] --HTTPS--> [Central NMS]
[Central NMS] -> Dashboards, Alerts, Reports
```

### Hybrid cloud

```
[On-Prem Devices] -> SNMP            -> [NMS (on-prem)]
[Cloud VPCs]      -> VPC Flow Logs   -> [Flow Platform (SaaS)]
[SaaS Apps]       -> Synthetic Tests -> [Synthetic Platform (SaaS)]
[All Platforms]   -> Unified Dashboard / Alert Aggregation
```

## Integration patterns

### NMS + flow + synthetic (complete stack)

- **NMS** (LibreNMS / PRTG / SolarWinds / Cacti / Zabbix): device health, availability, interface metrics.
- **Flow** (Kentik / NTA): traffic analysis, application visibility, DDoS.
- **Synthetic** (ThousandEyes): user experience, path analysis, SaaS monitoring.
- **Dashboard** (Grafana): unified visualisation across all data sources.

### SIEM integration

Forward NMS alerts and syslog to the SIEM (`siem-soar-investigation`), correlate network events with security events, and enrich security investigations with network context (which IPs communicated, when, how much).

### ITSM integration

Auto-create incidents from critical alerts (ServiceNow, Jira Service Management), link an alert to the affected CI in the CMDB, and track mean-time-to-resolution for network incidents.
