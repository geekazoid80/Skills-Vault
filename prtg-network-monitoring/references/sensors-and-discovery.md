# PRTG auto-discovery, device templates, and the sensor catalogue

How PRTG discovers devices and applies templates, and the sensor types available for each monitoring need.

## Auto-discovery

### Process

1. PRTG scans an IP range via ICMP (ping sweep).
2. For responsive hosts, it attempts an SNMP/WMI connection.
3. It identifies the device type (router, switch, server, printer, and so on).
4. It applies a **device template**: a pre-defined sensor set for that device type.
5. It creates the device with the recommended sensors.

### Device templates

Pre-defined sensor configurations for common device types:

- **Cisco Router**: ping, SNMP traffic (per interface), CPU, memory, uptime.
- **Windows Server**: ping, WMI CPU, WMI memory, WMI disk, WMI service.
- **VMware Host**: ping, VMware sensor (CPU, memory, datastore per host).
- **Generic SNMP Device**: ping, SNMP uptime, SNMP system info.
- **Custom templates**: build your own for standardised deployments.

### Schedule

- One-time scan or recurring (daily, weekly).
- IP-range-based or SNMP/CDP/LLDP neighbour-based.
- Configurable: which subnets, which sensor types, which device templates.

Without templates, auto-discovery creates inconsistent sensor sets. Define a template per device type before discovering at scale, and review and disable unnecessary sensors immediately after discovery.

## Sensor catalogue

### SNMP sensors

| Sensor | Monitors |
|---|---|
| SNMP Traffic | Interface in/out bandwidth |
| SNMP CPU Load | Device CPU utilisation |
| SNMP Memory | Device memory utilisation |
| SNMP Disk Free | Disk space (servers) |
| SNMP Custom | Arbitrary OID polling |
| SNMP Trap Receiver | Incoming SNMP traps |
| SNMP Custom Table | Table-based OID walks |
| SNMP Uptime | Device uptime counter |

### WMI sensors (Windows)

| Sensor | Monitors |
|---|---|
| WMI CPU | Per-core CPU utilisation |
| WMI Memory | Physical and virtual memory |
| WMI Disk Space | Per-volume disk usage |
| WMI Process | Specific process CPU/memory |
| WMI Service | Windows service state |
| WMI Event Log | Windows event-log entries |

WMI polling is resource-intensive on both PRTG and the target host. Prefer SNMP for network devices; use WMI only for Windows-specific metrics.

### Flow sensors

| Sensor | Monitors |
|---|---|
| NetFlow v5 | NetFlow v5 traffic analysis |
| NetFlow v9 | NetFlow v9 traffic analysis |
| IPFIX | IPFIX flow analysis |
| sFlow | sFlow traffic analysis |
| Packet Sniffer | Protocol-level packet capture |

Flow sensors count toward the sensor limit and may require a higher licence tier. Verify licensing before deploying them.

### HTTP / web sensors

| Sensor | Monitors |
|---|---|
| HTTP | URL availability and response time |
| HTTP Advanced | Response-content verification (regex) |
| HTTP Full Web Page | Full page-load time (all resources) |
| SSL Certificate | Certificate expiry and validity |
| REST Custom | REST API endpoint with assertions |

### Custom sensors

| Sensor | Method |
|---|---|
| EXE/Script | Run PowerShell/VBScript/EXE on the probe |
| EXE/Script Advanced | Same, with multi-channel output |
| SSH Script | Execute a script on a Linux host via SSH |
| Python Script Advanced | Run a Python script on the probe |
| REST Custom | Query a REST API, parse the JSON/XML response |

## Polling intervals

The default 60-second interval is unnecessary for most sensors. Use 5-minute intervals for capacity metrics and 60 seconds only for critical availability. Aggressive intervals multiply load on both PRTG and the monitored devices for no benefit.
