# FortiSASE architecture

How the FortiSASE fabric is put together: the cloud PoPs, the three ways traffic reaches them, the FortiClient endpoint agent and EMS, the secure-internet-access chain (SWG plus FWaaS), the secure-private-access path (ZTNA), the thin edge FortiGate and SD-WAN convergence, SSL/TLS inspection, and the FortiGuard and logging services that sit behind it all.

## The fabric: Points of Presence

FortiSASE runs the security stack in a fabric of cloud Points of Presence (PoPs) distributed by region. Each PoP terminates endpoint and thin edge traffic, applies the inspection profiles, and queries FortiGuard for real-time ratings. Endpoints and edges connect to the nearest PoP; geo-steering and PoP load balancing distribute load. Because inspection happens at the PoP, PoP capacity and regional coverage are real constraints: too many endpoints on one PoP degrades performance, and an underserved region adds latency. A degraded PoP means the traffic homed to it is at risk, so PoP status is the first thing tenant discovery records.

## Three ways traffic reaches the fabric

FortiSASE steers traffic to a PoP three ways, and most estates run a mix:

1. **FortiClient endpoint agent (agent-based).** The FortiClient agent on a roaming or remote device tunnels its internet-bound traffic to the nearest PoP for SWG and FWaaS inspection, and brokers ZTNA access to private applications. The agent also reports device posture to FortiClient EMS. This is the steering method for remote and hybrid users.

2. **Thin edge FortiGate (site-based).** A lightweight FortiGate at a branch site tunnels site traffic (IPsec or SSL) to the nearest PoP. It converges SD-WAN path selection with the security overlay, so branch internet traffic is inspected in the cloud rather than backhauled. This is the steering method for sites.

3. **Secure private access / ZTNA (access proxy).** Rather than steer outbound traffic, the ZTNA access proxy brokers inbound access to named private applications, verifying identity and device posture per request. This replaces full-network VPN for private-app access.

The two service faces map onto these: **secure internet access** (SWG plus FWaaS) inspects outbound traffic from agent and thin edge; **secure private access** (ZTNA) brokers inbound access to private apps.

## FortiClient and FortiClient EMS

**FortiClient** is the endpoint agent: it steers traffic, enforces the local endpoint firewall, and reports device posture. **FortiClient EMS (Endpoint Management Server)** is the management and posture authority. EMS:

- Deploys and configures FortiClient across the fleet.
- Evaluates compliance rules per endpoint group (OS patch level and minimum version, AV real-time protection and signature currency, vulnerability scan results, endpoint firewall state, disk encryption).
- Assigns a **ZTNA posture tag** based on the compliance result, which the ZTNA access proxy consumes as an access condition.
- Detects **on-fabric vs off-fabric**: whether the endpoint is on the corporate network (may use a local FortiGate) or remote (routes through the FortiSASE SWG). Misconfigured detection creates security gaps where off-fabric traffic bypasses cloud inspection.

EMS integrates with FortiSASE over a sync. A healthy sync is recent (under 15 minutes); a stale or disconnected EMS means FortiSASE is enforcing ZTNA against posture tags it can no longer trust. EMS is the single source of the device-posture signal, so its health gates the whole secure-private-access story.

## Secure internet access: SWG plus FWaaS

The secure-internet-access chain is a FortiOS security stack delivered from the PoP. The profiles:

- **Web filter** (`webfilter/profile`): FortiGuard URL categories, each with an explicit action (allow, block, monitor, warning, authenticate); Safe Search enforcement; file-type and content filtering. Categories left at default create unintended access.
- **Application control** (`application/list`): application categories set to block, monitor, or allow, with per-application overrides. High-risk categories (P2P, proxy, remote-access, botnet) should be blocked; the action for unknown applications should be deliberate.
- **DNS filter** (`dnsfilter/profile`): blocking at the DNS layer, a lightweight first line.
- **Antivirus** (`antivirus/profile`) and **IPS** (`ips/sensor`): malware and exploit inspection.
- **Inline CASB** (`casb/profile`) and **DLP** (`dlp/sensor`): SaaS control and data-loss prevention, where licensed.

These profiles enforce only when **bound to a firewall policy** (FWaaS). FWaaS is the cloud-delivered L7 firewall: an accept policy without AV, IPS, web-filter, and application-control profiles bound passes traffic uninspected, which is the single most common secure-internet-access gap. The policy also governs logging (`logtraffic all` or `utm`) and the SSL inspection profile.

## Secure private access: ZTNA access proxy

ZTNA in FortiSASE is delivered by an **access proxy**. The pieces:

- **Access proxy** (`firewall/access-proxy`): the ZTNA rule set. Each rule pairs an application definition with access conditions.
- **API gateway** rules within the access proxy: URL maps to real backend servers, with the service, persistence, SAML server, and the required ZTNA tags.
- **Virtual host** (`access-proxy/virtual-host`): the ZTNA server (backend) definitions.
- **Device categories** (`user/device-category`): the posture tags.
- **User groups** and **SAML/LDAP** integration (`user/group`, `user/saml`, `user/ldap`): the identity source.

The zero-trust discipline: every rule should require **identity** (user or group membership, via the SAML/LDAP IdP) plus a **device posture tag** (from EMS), not source IP. A rule keyed on source IP admits any device from that network and defeats the model. Rules evaluate top-down, so more specific rules must precede broader ones, or the broad rule shadows the specific one. MFA is enforced at the IdP for sensitive applications.

## Thin edge FortiGate and SD-WAN convergence

A **thin edge** is a FortiGate at a branch, registered to FortiSASE and tunnelling site traffic (IPsec or SSL) to the nearest PoP. It converges SD-WAN with the security overlay: SD-WAN chooses the WAN path by SLA (latency, jitter, packet loss against health-check targets), and the chosen path still delivers traffic into the security overlay. The design points:

- **Tunnel state** is the site's protection. A down tunnel means the site's traffic is not going through FortiSASE. Prefer **dual-tunnel redundancy** to a second PoP so a single PoP or path failure does not strand the site.
- **SD-WAN SLA failover must not bypass inspection.** Confirm that when SD-WAN steers to an alternate path, the traffic still enters the security overlay rather than egressing locally uninspected.
- **Cloud-vs-edge policy consistency.** The thin edge can carry local firewall rules that conflict with or override the centralised cloud policy. Cloud-first is the intent; local overrides are drift to reconcile.
- **Firmware currency.** A thin edge more than one major FortiOS version behind the recommended target carries unpatched vulnerabilities.

The thin edge FortiGate's FortiSASE-managed role is in scope here. Its standalone on-premises firewall configuration, audited independently of FortiSASE, belongs to `fortigate-firewall-audit`.

## SSL/TLS inspection

Inspection depth decides whether the security stack can see encrypted traffic:

- **Deep inspection** decrypts, inspects, and re-encrypts: AV, IPS, web filter, and application control all see the payload.
- **Certificate inspection** reads only the certificate and SNI: the stack sees connection metadata but not the payload, so AV and IPS are effectively blind on HTTPS.

Deep inspection requires the **FortiSASE inspection CA certificate** distributed to every managed endpoint (via EMS or MDM); without it, endpoints hit TLS errors or bypass inspection. Exemption lists (banking, medical, government, certificate-pinned apps) are legitimate but each broad exemption (a whole category or a wildcard domain) reduces coverage and needs a documented justification. Deep inspection also costs PoP CPU, so inspection scope is a capacity decision as well as a security one.

## FortiGuard services

FortiGuard is the cloud intelligence behind the profiles: AV signatures, IPS signatures, web-filter and DNS-filter ratings, application-control definitions, and (where licensed) inline CASB and DLP. Two independent failure modes:

- **Subscription**: an unlicensed or expired service cannot enforce, regardless of configuration.
- **Currency**: a licensed service with stale signatures under-detects. Expected cadence is roughly AV daily (under 24 hours), the rest weekly (under 7 days).

PoPs query FortiGuard in real time for web-filter and DNS ratings; degraded FortiGuard connectivity forces fallback to cached data and reduces detection of newly categorised threats.

## FortiAnalyzer Cloud and logging

FortiSASE forwards logs to **FortiAnalyzer Cloud** (or an on-premises FortiAnalyzer). The coverage that matters: traffic logs, UTM logs (AV, IPS, web filter, application control), event logs, and ZTNA logs, from every component (SWG, ZTNA, thin edges, endpoints). A missing log type is an investigation blind spot. Retention is set to the compliance requirement (commonly 90 to 365 days), and alert policies should at minimum cover malware detection, IPS critical severity, ZTNA authentication failures, thin edge tunnel down, FortiGuard update failures, and endpoint compliance drops.
