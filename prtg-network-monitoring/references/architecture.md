# PRTG architecture: sensor model, licensing, deployment, and probes

How PRTG is built and licensed, the on-premises versus SaaS deployment choice, and how remote probes extend monitoring to where the devices are.

## The sensor-based model

Everything monitored in PRTG is a **sensor**: one sensor monitors one metric on one device.

- 1 SNMP Traffic sensor = in/out traffic on 1 interface.
- 1 Ping sensor = availability of 1 device.
- 1 WMI CPU sensor = CPU of 1 Windows host.
- 1 HTTP sensor = 1 URL.
- 1 NetFlow receiver = flow data from 1 source.

The sensor is also the licence unit, so the number of sensors, not the number of devices, determines cost and capacity.

### Licensing tiers

| Tier | Sensors | Use case |
|---|---|---|
| Free | 100 | Small network, evaluation |
| 500 | 500 | Small business |
| 1,000 | 1,000 | SMB |
| 2,500 | 2,500 | Mid-market |
| 5,000 | 5,000 | Enterprise |
| XL1 / XL5 | 10,000 / 50,000 | Large enterprise |
| Unlimited | No cap | Largest deployments |

### Sensor-count optimisation

- Disable auto-discovered sensors you do not need (every interface becomes a sensor).
- Use device templates to deploy only the sensors relevant to each device type.
- Where appropriate, one ping sensor per device group rather than per device.
- Pause sensors on decommissioned devices rather than leaving them active.

## On-premises architecture

- **Core Server**: Windows Server (2016/2019/2022) running the PRTG Core Service. Holds configuration, the database, and the web interface.
- **Local Probe**: runs on the core server and monitors the local network.
- **Remote Probes**: Windows agents at remote sites that connect to the core over TLS.
- **Database**: an embedded proprietary database; no external SQL server is required.
- **Web Interface**: a built-in HTTPS web server.

## PRTG Hosted Monitor (SaaS)

- The core server is hosted and managed by Paessler; no on-premises server infrastructure.
- Remote probes on the internal network connect outbound to the cloud core.
- Internal networks are monitored without exposing SNMP to the internet.
- Same sensor model and UI as on-premises, with automatic updates, backups, and infrastructure management.

## Remote probe architecture

```
[Remote Site A]
  [Devices] -> [Remote Probe A] --TLS (port 23560)--> [PRTG Core (HQ or Cloud)]

[Remote Site B]
  [Devices] -> [Remote Probe B] --TLS--> [PRTG Core]

[HQ]
  [Devices] -> [Local Probe] -> [PRTG Core]
  [PRTG Core] -> [Web Interface] -> [Admin Browser]
```

### Probe use cases

- Monitor remote sites without running SNMP over the WAN.
- Monitor a DMZ from an isolated probe.
- Monitor cloud VPCs from a cloud-hosted probe.
- Reduce WAN bandwidth (the probe polls locally and sends summaries to the core).

Remote probes need outbound TLS on port 23560 to the core. A firewall blocking that port causes probe disconnection and data gaps. PRTG on-premises has no native core-server HA; plan VM-level HA or clustering, or use Hosted Monitor for managed availability.
