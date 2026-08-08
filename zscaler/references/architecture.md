# Zscaler Zero Trust Exchange architecture

The platform underneath ZIA, ZPA, and ZDX: the enforcement-node topology, single-pass inspection, the Z-Tunnel protocol, the ZPA broker and App Connector tunnel, the ZDX pipeline, log export, and the adjacent capabilities. This is the "how it is built" reference; configuration and operations live in `zia-and-zpa.md`.

## Zero Trust Exchange platform

The Zero Trust Exchange (ZTE) is Zscaler's unified cloud, run across 150+ data centres worldwide. Every function (ZIA, ZPA, ZDX) is delivered from the same node fabric, so a session is brokered at the edge nearest the user rather than backhauled to an appliance.

```
Zscaler Zero Trust Exchange
- ZIA (internet-bound traffic)
  - Secure Web Gateway (URL filtering, SSL/TLS inspection)
  - Cloud Firewall (L4 to L7 enforcement, DNS control, IPS)
  - Cloud Sandbox (advanced threat protection)
  - CASB (SaaS visibility and control)
  - DLP (data loss prevention)
- ZPA (private-application access)
  - App Connectors (deployed in the private network)
  - ZPA broker / Supercluster (policy and tunnel brokering in the cloud)
  - Zscaler Client Connector (endpoint agent)
  - Browser Access (agentless, clientless)
- ZDX (digital-experience monitoring)
  - Endpoint probes (via the ZCC agent)
  - Network path analysis
  - Application performance monitoring
- Posture Control (workload and cloud posture: CSPM, CIEM, CNAPP)
```

## Data-centre and enforcement-node topology

**Zscaler Enforcement Node (ZEN).** Each ZEN is a full stack that can process ZIA, ZPA, and ZDX. Nodes are named by city and number (for example `nyc1`, `lon1`). Every metro has multiple nodes; traffic goes to the nearest available one and fails over to the next-nearest on node failure.

**Traffic steering to the nearest node.**
- ZCC agent: DNS resolution of the gateway hostname returns the nearest node.
- Office GRE/IPsec tunnel: configured to a primary point of presence with a secondary for failover.
- PAC file: returns a proxy pointing at the nearest node.

**Backbone and superclusters.** A private backbone interconnects major ZENs and carries ZPA broker traffic and telemetry, not customer content (content is processed at the edge ZEN). Selected ZENs act as superclusters for the ZPA broker function: authentication, policy lookup, and App Connector tunnel termination.

**Direct peering.** Zscaler peers directly with Microsoft, Google, Salesforce, ServiceNow, and many other SaaS providers at internet exchanges, so SaaS traffic can exit Zscaler's network straight to the provider without transiting the public internet.

## Single-pass inspection

All ZIA traffic at a ZEN is processed in a single pass: TLS is terminated once, then every engine inspects the same decrypted stream in parallel, and the combined verdict drives the action.

```
Traffic arrives at ZEN
  -> Connection admission control (tenant quota, rate limiting)
  -> TLS termination / SSL inspection (decrypt HTTPS, verify server cert)
  -> Protocol detection (HTTP/1.1, HTTP/2, WebSocket, FTP, DNS, generic TCP)
  -> Parallel inspection:
       URL filter + DNS control | App-ID + CASB | IPS
       Anti-malware            | DLP            | Sandbox (async)
  -> Policy decision (combine all verdicts)
  -> Action: allow / block / quarantine / isolate
  -> TLS re-encryption
  -> Forward to destination
```

**Latency budget (typical targets):**
- Connection setup plus TLS: 10 to 30 ms.
- URL/app classification: under 2 ms when cached; a miss adds a cloud lookup of roughly 5 ms.
- Anti-malware scan of a clean file: under 5 ms.
- DLP scan: 5 to 20 ms depending on content size.
- Total overhead target: under 50 ms for non-sandboxed traffic.

The design consequence: because every engine reads the same decrypted stream, a do-not-inspect (SSL bypass) rule blinds all of them at once. Inspection coverage is the single most important ZIA health metric.

## Z-Tunnel protocol

**Z-Tunnel 2.0** encapsulates all endpoint traffic in a DTLS (Datagram TLS) tunnel over UDP/443, falling back to TCP/443 where UDP is blocked.

```
ZCC client
  -> ZCC interceptor (kernel driver on Windows/macOS/Linux) intercepts all IP traffic
  -> applies the forwarding profile: route to ZIA, route to ZPA, or go direct
  -> ZIA-bound traffic: DTLS tunnel on UDP/443 (fallback TCP/443)
  -> nearest ZEN (via DNS anycast) decapsulates, processes, forwards
```

- **Z-Tunnel 1.0**: an HTTP CONNECT proxy. HTTP(S) is proxied; non-HTTP traffic is bypassed. Legacy.
- **Z-Tunnel 2.0 (default)**: all traffic tunnelled via DTLS. Better coverage and better performance, because DTLS over UDP avoids the TCP-in-TCP retransmit problem of a TCP-based tunnel.
- **TCP/443 fallback**: many networks block UDP; ZCC detects this and wraps Z-Tunnel 2.0 in TLS over TCP/443, at some performance cost.

## ZPA broker architecture

ZPA never puts the user on the network. The broker correlates two pre-authenticated tunnels: the user-side ZCC tunnel and the App Connector's persistent outbound tunnel.

```
Phase 1: Authentication
  ZCC -> Zscaler IdP proxy -> customer IdP (Okta / Entra ID) -> SAML/OIDC assertion
  ZCC receives the identity assertion plus a ZPA session token

Phase 2: Policy lookup
  ZCC -> ZPA supercluster -> policy engine
  "User X, device Y, wants application segment Z"
  Device-posture check: ZCC reports device-health signals
  Decision: allow / deny / allow with conditions

Phase 3: Tunnel establishment
  Source side: ZCC to ZPA cloud (already established)
  Destination side: ZPA cloud to App Connector (pre-established persistent tunnel)
  Session correlation: match the source session to the destination session

Phase 4: Data path
  ZCC -> ZPA edge (nearest ZEN) -> App Connector -> private application
```

**Why ZPA traffic is not SSL inspected.** ZPA builds an end-to-end encrypted tunnel from the user to the application; the broker routes it at the network level and does not decrypt content, so the application's own TLS stays intact. Optional DLP scanning of ZPA traffic exists as a separate feature (ZPA Inspection) for organisations that need it.

### App Connector persistent tunnel

App Connectors hold a persistent outbound tunnel to ZPA enforcement nodes.

```
App Connector VM
  -> outbound TCP/443 to the ZPA cloud (egress only)
  -> ZPA enforcement node (supercluster)
  -> session correlation when a user requests the app
  -> ZCC <-> ZPA edge <-> supercluster <-> App Connector <-> application
```

- Zero inbound ports on the connector's firewall, which shrinks the attack surface.
- The tunnel is always ready, so access is near-instant when a user requests it.
- On a tunnel drop the connector re-establishes with a retry-and-backoff loop.

### App Connector sizing

| Traffic volume | vCPU | RAM | Network |
|---|---|---|---|
| Small (under 100 concurrent users) | 2 | 4 GB | 1 Gbps |
| Medium (100 to 500 concurrent users) | 4 | 8 GB | 2.5 Gbps |
| Large (500+ concurrent users) | 8 | 16 GB | 10 Gbps |

Always deploy 2+ connectors per group; ZPA load-balances across the healthy connectors and fails over automatically.

## ZDX collection pipeline

ZDX measures experience from the endpoint outward, so a slowness complaint can be attributed to the device, the ISP path, or the application.

- **Probes.** The ZCC agent runs synthetic probes (HTTP GET, DNS lookup, traceroute) on a configurable interval (default around every 5 minutes) and ships the results to the ZDX cloud for aggregation and scoring.
- **Device metrics.** CPU and RAM utilisation, Wi-Fi signal strength and interference, and ZCC/tunnel performance.
- **Network-path metrics.** Hop-by-hop latency (traceroute), ISP identification and performance, packet loss, the path to the Zscaler point of presence, and the path from the point of presence to the application.
- **Application metrics.** DNS resolution time, TCP connect time, TLS handshake time, time to first byte, and total page-load time.

The output is an Experience Score per user and per application, which is the entry point for the triage flows in `zia-and-zpa.md`.

## Logging and analytics

### Nanolog Streaming Service (NSS)

NSS is a dedicated Zscaler cloud service that aggregates logs from every ZEN and streams them to a customer SIEM in near real time.

| Feed | Format | Representative fields |
|---|---|---|
| Web | LEEF / CEF / Zscaler JSON | Time, user, URL, category, action, bytes, threat name |
| Firewall | CEF / Zscaler JSON | Source IP, destination IP, port, protocol, rule, action, bytes |
| DNS | Zscaler JSON | Query, response, category, action |
| DLP | Zscaler JSON | User, file, rule, matched content type, action |
| Sandbox (ATP) | Zscaler JSON | File hash, file name, verdict, threat classification |

Common downstream targets are Splunk, Microsoft Sentinel, IBM QRadar, generic syslog (CEF), and S3/Azure Blob for later ingestion. For smaller deployments, logs can be pulled through the API (Cloud Activity Log) instead of streamed.

## Adjacent capabilities

**Zscaler Browser Isolation (ZBI).** Renders web content in a disposable cloud browser and streams only pixels to the user, so page code never runs on the device. Wired into ZIA as an action (allow / block / isolate) for chosen URL categories; used for unmanaged-device access, high-risk categories, and zero-day browser-exploit containment, with clipboard/download/print controls in the isolated session.

**Zscaler Deception.** Deploys lures (fake credentials and connections on real endpoints) and decoys (fake servers). Any interaction with a decoy is definitionally malicious, so it produces high-fidelity, low-false-positive alerts. Decoys can sit behind ZPA so that legitimate access is impossible and any touch is unambiguous.

**SSMA (Secure Service Mesh for Apps).** Extends ZPA to workload-to-workload (app-to-app) access. App Connectors at each workload segment, service-to-service policy in the same ZPA engine as user-to-app, and mTLS between connectors, replacing VPC peering and security-group sprawl with application-level policy.

**Posture Control (CNAPP).** Zscaler's cloud-native application protection platform. CSPM scans AWS/Azure/GCP for misconfiguration (public buckets, permissive security groups, unencrypted databases) against CIS/SOC 2/PCI/HIPAA/NIST benchmarks; CIEM analyses cloud IAM for unused permissions and privilege-escalation paths. Findings can feed ZIA/ZPA policy, for example quarantining a flagged workload.

**ThreatLabZ.** Zscaler's threat-research function, processing hundreds of billions of daily transactions into IP-reputation, URL-categorisation, phishing-detection, malware, and botnet-C2 feeds pushed to every ZEN. Customers can request URL re-categorisation or a malware-verdict review through the Admin Portal.
