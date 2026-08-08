# Prisma Access architecture: compute locations, PAN-OS pipeline, GlobalProtect, ZTNA 2.0, and management planes

How Prisma Access is built as a distributed PAN-OS cloud fabric, how a packet flows through a compute location, how mobile users and private applications connect, and how the two management planes differ. This is the reference for architecture and deployment questions; configuration and operations live in `operations.md`, API and CLI in `api-and-automation.md`.

## Compute-location (PoP) architecture

Each Prisma Access compute location is a fully instantiated PAN-OS firewall cluster running in Palo Alto's cloud infrastructure. There are 100-plus compute locations globally; anycast routing steers each user or tunnel to the nearest one.

```
Prisma Access Compute Location (PoP)
|
+-- Ingress Controller
|     - Receives traffic from GlobalProtect clients and IPsec tunnels (branch, service connection)
|     - Anycast routing to the nearest compute location
|     - Load balancing across firewall cluster nodes
|
+-- Firewall Cluster (PAN-OS)
|     - Multiple PAN-OS instances per location (HA plus scale-out)
|     - App-ID engine
|     - Content-ID engine (Threat Prevention, URL, DNS, WildFire, DLP)
|     - User-ID mapping
|     - Security policy enforcement
|
+-- WildFire Forwarding
|     - Suspicious files forwarded to the nearest WildFire cloud instance
|     - Inline blocking: hold the file until verdict, or allow with a retroactive verdict
|
+-- Egress
      - Direct peering with SaaS providers (M365, Google, Salesforce)
      - Public internet for general web traffic
      - Private-app return path via service-connection tunnels
```

The operational consequence: you never manage a PoP as a box. You declare intent centrally (Strata Cloud Manager or Panorama) and the fabric instantiates it across every location. Capacity, redundancy, and failover between nodes are Palo Alto's responsibility; policy correctness and coverage are yours.

## PAN-OS processing pipeline

Within each compute-location node, PAN-OS processes packets through a strict pipeline. Understanding the order explains why App-ID and decryption placement matter.

```
Packet arrives
  v
Interface ingress and decapsulation (GRE / IPsec / DTLS)
  v
Security zone determination
  v
Session lookup
  v  (new session)
App-ID classification
  v
User-ID lookup (identify user from source IP or GlobalProtect token)
  v
Security policy lookup (match rule on zone, app, user, destination)
  v
Profile application:
  - Threat Prevention (IPS / AV / spyware)
  - URL Filtering (if web traffic)
  - WildFire (if file transfer)
  - DNS Security (if DNS)
  - DLP (if enabled)
  v
NAT (if applicable)
  v
Egress interface and re-encapsulation
  v
Forwarding to destination
```

### App-ID deep packet inspection

App-ID identifies applications through techniques applied in sequence:

1. **Application signatures:** a known pattern at a fixed offset in the first few packets.
2. **Application protocol decoding:** parse the application protocol to extract the app identity.
3. **Heuristics:** behavioural patterns (traffic timing, packet sizes) for encrypted apps.
4. **Context:** protocol context, for example SSL/TLS with an SNI that identifies the app.

For encrypted traffic, App-ID uses the TLS SNI (destination hostname maps to application), JA3/JA3S handshake fingerprinting (identifies specific clients and apps), and behavioural heuristics for apps that obfuscate their identity. PAN-OS also carries App-ID for QUIC/HTTP/3 (used by many Google and YouTube services) and can enforce policy on QUIC or block it to force fallback to HTTPS.

### Content-ID processing

Content-ID handles all content inspection within an App-ID-identified session, scanning in a stream (as data arrives) rather than buffering whole files, which reduces latency.

- **Threat Prevention:** vulnerability protection (CVE-based exploit signatures), anti-spyware (C2 and DNS-tunnelling patterns), antivirus (multiple engines plus ML-based malware detection), and WildFire integration for unknown files.
- **URL Filtering:** PAN-DB category lookup against a 40-billion-plus URL database, real-time cloud lookup for newly seen URLs, and inline ML for phishing detection that does not need a prior category.

## GlobalProtect gateway architecture

### Gateway types

- **Prisma Access external gateway:** cloud-hosted in the compute locations, handles all remote and mobile connections, deployed automatically when Prisma Access is configured for mobile users.
- **Internal gateway (on-premises, optional):** a physical or virtual PAN-OS firewall that handles connections when the user is on the corporate network and provides HIP enforcement for internal access. Not required for Prisma Access; only needed for on-prem segmentation.

### Connection flow

```
User endpoint (GlobalProtect agent)
  1. Portal discovery: the agent queries the portal (cloud GP portal or internal)
  2. Portal returns: a list of gateways (external = Prisma Access, internal = on-prem)
  3. Gateway selection: the agent pings gateways and selects the lowest RTT
  4. Authentication: IdP auth (SAML) returns an identity token
  5. HIP collection: the agent collects device-posture data
  6. Tunnel establishment: IPsec / SSL tunnel to the selected gateway
  7. IP assignment: the agent receives a VPN IP from the Prisma Access pool
  8. Traffic flows: split tunnel or full tunnel per the forwarding profile
```

### HIP processing

The GlobalProtect agent collects Host Information Profile (HIP) data: OS version and patch level, disk-encryption status (BitLocker/FileVault), antivirus vendor and definition age, host-firewall status, patch-management level (Windows Update / WSUS / SCCM), and custom checks (registry keys, file existence, running processes such as an EDR agent).

HIP match objects define conditions centrally, for example:

```
HIP Object: "Compliant-Windows"
  Match: OS family = "Windows" AND
         Disk Encryption = "Enabled" AND
         Antivirus last update < 3 days AND
         EDR process running = true
```

Those objects feed security policy so a compliant device gets full access and a non-compliant device gets limited access or is blocked. The policy structure and tuning live in `operations.md`.

## ZTNA 2.0 policy engine

### Service-connection architecture

Service connections are IPsec tunnels from the infrastructure hosting private applications to the nearest compute location.

```
Private application (10.100.0.x)
  |
[Application server (AD, SAP, and so on)]
  |
[IPsec-capable router or firewall]
  |  IPsec IKEv2 tunnel, outbound to Prisma Access
  v
Prisma Access compute location
  |
[Security policy enforcement]
  |
  v  (matching allowed session)
GlobalProtect user at a remote location
```

Configure two service connections to different compute locations for redundancy. Routing on the customer side is BGP or static; Prisma Access advertises its routes back to the customer via BGP. An application segment is defined by hostname, IP, ports, and an App-ID (a custom application-override where the app is not in the default catalogue), bound to a named service connection.

### Continuous-trust verification

ZTNA 2.0 re-evaluates access throughout the session, which is the substantive difference from connect-then-trust ZTNA 1.0:

- **Inline session monitoring:** App-ID keeps inspecting within an allowed session; if the traffic shifts to a different application than authorised (for example a web session showing signs of SSH tunnelling), the session is blocked. Threat Prevention watches for exploit traffic within the allowed session.
- **Dynamic policy updates:** a policy change takes effect on the next packet of an active session, not only on new sessions. User-risk signals from Cortex XDR can revoke access mid-session.
- **Session context:** time-based re-authentication when a session exceeds its policy limit, and behavioural triggers such as a sudden data-volume spike prompting inspection or alerting.

## Panorama versus Strata Cloud Manager

One management plane per tenant. They are not used simultaneously against the same Prisma Access tenant; pick one and keep it authoritative.

**Use Panorama if:** there is an existing large PAN-OS deployment already on Panorama, complex on-prem-plus-cloud policy inheritance is required, a regulatory requirement mandates an on-premises management plane, or advanced automation via the Panorama XML API is in place.

**Use Strata Cloud Manager (SCM) if:** it is a new Prisma Access deployment, AI-assisted policy recommendations are wanted (Strata Copilot, Security Score, Best Practice Check, Change Impact Analysis), a simpler cloud-native experience is preferred, or Prisma SD-WAN integration is in scope (SCM provides unified SASE management).

### Management architecture

```
Panorama-managed:
Admin -> Panorama (on-prem or cloud-hosted) -> Prisma Access Cloud Services plugin
           |                                       |
      Device Groups                          Compute locations treated as
      (on-prem NGFWs)                         virtual firewalls
           |
      Shared policies and objects apply to both on-prem and Prisma Access

SCM-managed:
Admin -> Strata Cloud Manager (cloud SaaS) -> Prisma Access
                    |
              AI Security Assistant (Strata Copilot), Security Score,
              Best Practice Check, Change Impact Analysis
```

### Policy inheritance in Panorama

Device Groups allow hierarchical policy: a `Shared` group applies to all firewalls (for example block known-bad URL categories, allow M365), a `Prisma-Access-Production` device group inherits Shared and adds ZTNA and remote-user internet rules, and an `On-Prem-Firewalls` device group inherits Shared and adds data-centre east-west and server-zone rules. The inheritance order is what lets one baseline cover both cloud and on-prem consistently.

## Cortex Data Lake integration

All Prisma Access logs are forwarded automatically to Cortex Data Lake for retention and analytics. Log types include traffic, threat, URL, DNS, authentication, GlobalProtect, HIP match, decryption, and ADEM. Default retention is 30 days, configurable up to a year with additional storage.

Key Traffic-log fields (used by the audit and by SIEM correlation): `time_generated`, `src`, `dst`, `srcloc`, `dstloc`, `from` (source zone), `to` (destination zone), `proto`, `app` (App-ID name), `rule`, `action`, `bytes_sent`, `bytes_received`, `session_end_reason`, `srccountry`, `dstcountry`. Cortex Data Lake can forward to Microsoft Sentinel (Cortex Sentinel connector) and Splunk (the Palo Alto Splunk app). Cortex Query Language examples are in `api-and-automation.md`.

## WildFire sandbox flow

```
File encountered by Prisma Access (download, email attachment, and so on)
  v
Hash lookup in the WildFire cloud verdict cache
  |                                   |
  v cache hit                         v cache miss
Return the known verdict            Submit to WildFire for analysis
(milliseconds)                        v
                                    Detonation environments: Windows 10/7, macOS, Linux, Android
                                      v
                                    Behavioural analysis: process activity, network connections,
                                    file-system and registry changes, memory, API calls
                                      v
                                    ML plus signature analysis
                                      v
                                    Verdict: Benign / Grayware / Malware / Phishing
                                      v
                                    Verdict cached and distributed to all subscribers within ~5 minutes
```

**Hold (blocking) mode** holds file delivery until the verdict (a 30-to-90-second spinner during detonation); best for high-security environments. **Inline (non-blocking) mode** delivers the file immediately and applies the verdict retroactively (terminating the session and caching the file as malicious if it turns out bad); better experience, a slight risk window. Best practice: inline blocking for executables and macro-enabled Office documents, allow-through for known-benign types (images, plain text), and monitor grayware verdicts for manual review.

## ADEM architecture detail

ADEM (Autonomous Digital Experience Management) monitors end-to-end user experience on PAN-OS telemetry, comparable in role to Zscaler ZDX.

**Endpoint probes:** the GlobalProtect agent runs lightweight probes every 5 minutes: an HTTP GET to monitored endpoints, a DNS query to the application FQDN, an ICMP traceroute to the Prisma Access gateway, and an ICMP traceroute to the application server. Telemetry is sent to Cortex Data Lake via the control plane. **Synthetic test agents** deployed in the compute locations test application-side performance independently of user-device issues.

**Root-cause algorithm** (worked example):

```
User Experience Score drops (say 95 -> 55)
  v
Compare device metrics (CPU / WiFi):     no change
Compare user-to-PoP latency:             increased by 80 ms
Compare PoP-to-app latency:              no change
Compare app response time:               no change
  v
Root cause: the ISP / network path between the user and the Prisma Access PoP
  v
ADEM maps the specific ISP (BGP AS) causing the increase
  v
Alert: "Users connecting via ISP AS12345 experiencing high latency"
Recommendation: consider ADEM path redirection or an alternate PoP
```

The Experience Score is calculated per user and per application on a 1-to-100 scale, aggregated to site, region, and enterprise views. ADEM classifies each degradation as device-side, network/ISP, PoP, or application, which is what makes the triage in `operations.md` fast.
