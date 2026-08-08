# Monitoring paradigms and golden signals

The four ways to monitor a network, what each is best for, and the golden signals that frame what to measure. Pick the paradigm from the question being asked, not from the platform already owned.

## The four paradigms

### 1. SNMP polling (device health)

The traditional NMS approach: poll devices at a regular interval for interface utilisation, errors and discards, CPU, memory, temperature, availability, and vendor-specific OIDs.

- **Best for**: infrastructure health, availability tracking, capacity planning.
- **Platforms**: SolarWinds NPM, LibreNMS, PRTG, Zabbix, Nagios, Cacti.

### 2. Flow analytics (traffic analysis)

Analyse traffic at the flow level (NetFlow, IPFIX, sFlow, VPC Flow Logs): source and destination, application, volume, and patterns. Supports anomaly detection, DDoS identification, and capacity planning by application and destination.

- **Best for**: traffic analysis, bandwidth planning, security investigation, DDoS detection.
- **Platforms**: Kentik, SolarWinds NTA, Plixer Scrutinizer, ntopng, Elastiflow.

### 3. Synthetic monitoring (user experience)

Active probes that simulate user transactions from controlled vantage points, measuring what a user would experience independent of real traffic: HTTP/HTTPS availability and performance, DNS resolution, hop-by-hop path analysis, scripted web transactions, BGP route visibility.

- **Best for**: SaaS and cloud application monitoring, ISP performance, end-user experience.
- **Platforms**: ThousandEyes, Catchpoint, Datadog Synthetics, Kentik Synthetics.

### 4. Packet capture (deep inspection)

Full or sampled packet capture for forensic analysis: protocol analysis and troubleshooting, application-performance metrics (TCP retransmits, latency), security forensics.

- **Best for**: troubleshooting complex issues, security investigation, compliance.
- **Platforms**: Wireshark, ExtraHop, Gigamon.

### Choosing among them

Most networks need SNMP polling plus flow analytics as the baseline. Add synthetic monitoring when users depend on SaaS or traverse multiple ISPs. Reach for packet capture only on the hard problems, where flow and SNMP cannot explain the behaviour. A complete stack combines all four with a unifying dashboard.

## Golden signals for the network

Adapted from Google's SRE golden signals:

| Signal | Network meaning | How to measure |
|---|---|---|
| **Latency** | Round-trip time, path delay | ICMP, synthetic tests, flow timestamps |
| **Traffic** | Bandwidth utilisation, flow volume | SNMP interface counters, flow analytics |
| **Errors** | Interface errors, discards, CRC, resets | SNMP error counters, syslog events |
| **Saturation** | CPU, memory, buffer utilisation, queue depth | SNMP device metrics, flow-based congestion signals |

Additional network-specific signals:

- **Availability**: device and interface up/down state (SNMP, ICMP).
- **Jitter**: variation in latency (synthetic probes, RTP monitoring).
- **Packet loss**: end-to-end loss rate (synthetic probes, flow analytics).
- **Path changes**: routing or forwarding-path modifications (BGP monitoring, traceroute).

Decide which signals matter for each service before choosing how to collect them. A SaaS-facing service cares about latency, packet loss, and path changes (synthetic); a data-centre core cares about traffic and saturation (SNMP plus flow).

## Synthetic monitoring detail

### Test types

**Network layer**: ICMP ping (reachability and RTT), TCP connect (port reachability and connection time), traceroute (hop-by-hop path and per-hop latency), MTU path discovery (detect MTU mismatches).

**Application layer**: HTTP/HTTPS (availability, response code, response time, certificate validity), DNS (resolution time, answer correctness, DNSSEC validation), page load (full browser render including JS/CSS/images), web transaction (multi-step scripted journeys such as login and submit), API (REST/GraphQL with response assertions), voice/RTP (MOS score, jitter, packet loss for VoIP).

**BGP**: route visibility (prefix, AS path, route changes) and hijack detection (unexpected origin AS or path change).

### Agent types

- **Cloud agents**: vendor-hosted in global data centres; the external perspective.
- **Enterprise agents**: customer-deployed inside internal networks; the internal perspective.
- **Endpoint agents**: installed on user devices; real user-path measurement.

### Path visualisation

Combines traceroute-like probing with BGP route data to show every hop from source to destination, including ISP routers. It identifies the specific hop introducing latency, loss, or a path change, and historical comparison correlates path changes with performance issues.
