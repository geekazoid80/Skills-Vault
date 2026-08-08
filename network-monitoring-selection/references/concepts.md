# Network monitoring protocol fundamentals: SNMP, flow, traps, syslog, topology

The vendor-neutral protocol foundation: how devices expose data (SNMP), how traffic is exported (flow), how events are pushed (traps and syslog), and how topology is discovered. Paradigm choice, golden signals, alerting, and platform selection each have their own reference; this one is the wire-level mechanics.

## SNMP (Simple Network Management Protocol)

### Architecture

- **Manager**: the NMS software that polls agents and receives traps.
- **Agent**: software on the monitored device that responds to polls and sends traps.
- **MIB (Management Information Base)**: the hierarchical tree of OIDs defining the available data points on a device.

### Versions

| Version | Authentication | Encryption | Identity | Use case |
|---|---|---|---|---|
| v1 | Community string (cleartext) | None | Community | Legacy only; avoid |
| v2c | Community string (cleartext) | None | Community | Isolated management networks only |
| v3 | USM (username + auth) | DES / AES | Username-based | Production standard |

### SNMPv3 security levels

- **noAuthNoPriv**: username only; no authentication, no encryption.
- **authNoPriv**: username plus authentication (MD5/SHA); no encryption.
- **authPriv**: username plus authentication plus encryption (DES/AES-128/AES-256). Use this in production.

### Key OIDs

| OID | Description |
|---|---|
| 1.3.6.1.2.1.1.1.0 | sysDescr: device description |
| 1.3.6.1.2.1.1.3.0 | sysUpTime: uptime in hundredths of a second |
| 1.3.6.1.2.1.1.5.0 | sysName: hostname |
| 1.3.6.1.2.1.2.2.1.* | ifTable: interface table (status, 32-bit counters) |
| 1.3.6.1.2.1.31.1.1.* | ifXTable: extended interface table (64-bit counters) |
| 1.3.6.1.4.1.* | enterprises: vendor-specific OIDs |

### Operations

- **GET**: retrieve a single OID value.
- **GET-NEXT**: retrieve the next OID in the tree (used for table walks).
- **GET-BULK** (v2c/v3): retrieve many OIDs in one request, replacing repeated GET-NEXT; dramatically faster for tables.
- **SET**: write a value to an OID (requires a write community or v3 write credentials).
- **TRAP**: an unsolicited notification from agent to manager (link down, threshold exceeded).
- **INFORM** (v2c/v3): an acknowledged trap, retransmitted until the manager confirms receipt.

### Polling considerations

- **Interval**: five minutes is standard for capacity metrics; sixty seconds for availability; sub-minute only where a dashboard truly needs it (use sparingly).
- **Bulk walks**: use GET-BULK for tables to cut polling time.
- **64-bit counters**: use ifXTable (ifHCInOctets / ifHCOutOctets) on gigabit-plus interfaces; 32-bit counters wrap too quickly to be reliable.
- **Timeout and retry**: two-to-five-second timeout with one-to-three retries; excessive retries increase load.
- **Scalability**: a single poller typically handles 500 to 2,000 devices depending on OID count and interval.

## Flow protocols

### NetFlow v5

Cisco proprietary; a fixed seven-tuple flow key (source and destination IP, source and destination port, protocol, ToS, ingress interface). Fixed record format, no extensibility, IPv4 only. Sampled or unsampled.

### NetFlow v9

Template-based, flexible record format. Supports IPv6, MPLS labels, and BGP AS numbers. Templates define field types and lengths; the collector must decode via the template. Cisco proprietary but widely supported.

### IPFIX (IP Flow Information Export)

IETF standard (RFC 7011), evolved from NetFlow v9. Template-based with enterprise-specific information elements, variable-length fields, and structured data types. Vendor-neutral; the recommended choice for new deployments.

### sFlow

Sampling-based (RFC 3176): samples one in N packets at a configurable rate, including a packet-header sample plus interface counters. Lower device overhead than NetFlow because it keeps no per-flow state. Multi-vendor; common on switches (Arista, Aruba, Dell, Brocade).

### VPC Flow Logs

Cloud-native flow records from AWS, Azure, and GCP virtual networks. Similar fields to NetFlow (source and destination IP, port, protocol, action, bytes) plus cloud-specific metadata (VPC ID, subnet, security group, ENI). Published to cloud storage or a streaming service.

### Flow enrichment

Raw flows become useful when enriched with:

- **BGP AS path**: source and destination AS, transit path.
- **Geographic data**: GeoIP lookup for location context.
- **Device metadata**: hostname, site, role tags.
- **Application mapping**: port-to-application beyond the IANA registry.
- **Custom tags**: business unit, customer, cost centre.

## SNMP traps and syslog

### SNMP traps

Unsolicited notifications from a device to the NMS. Common traps: linkDown, linkUp, coldStart, warmStart, authenticationFailure. Enterprise-specific traps cover vendor events (fan failure, power-supply loss, BGP peer change). INFORM (v2c/v3) is an acknowledged trap, retransmitted until the NMS confirms receipt.

### Syslog

Text-based logging (RFC 5424) over UDP 514, TCP 514, or TCP 6514 (TLS). Severity ranges from Emergency (0) to Debug (7); facility codes cover kernel, user, auth, and local0-7. Devices send logs in real time and the NMS correlates them with device state. Use cases: configuration-change detection, authentication events, protocol-state changes.

## Topology discovery

### Protocols

- **LLDP (Link Layer Discovery Protocol)**: IEEE 802.1AB; vendor-neutral neighbour discovery.
- **CDP (Cisco Discovery Protocol)**: Cisco proprietary, widely deployed.
- **SNMP-based**: walk the LLDP/CDP MIBs, or ARP/MAC/routing tables, to build topology.
- **BGP peering**: discover routing peers from BGP neighbour tables.

### Map types

- **Physical**: actual cable connections between devices (LLDP/CDP).
- **Logical**: L3 routing relationships (routing table, BGP).
- **Application**: traffic-flow paths between application tiers.
