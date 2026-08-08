# SASE / SSE concepts and architecture

Design-level depth for the SASE/SSE components and the zero-trust logical model. Vendor-neutral; platform-specific configuration lives in `zscaler`, `prisma-access`, and `fortisase`.

## NIST SP 800-207 logical model

NIST defines the zero-trust control plane as three logical components:

- **Policy Engine (PE)**: makes the access decision. It takes identity, device posture, behavioural context, and resource sensitivity, and produces allow, deny, or conditional.
- **Policy Administrator (PA)**: establishes and tears down the session. It issues and revokes the credentials and session tokens the enforcement point uses, on instruction from the PE.
- **Policy Enforcement Point (PEP)**: sits inline between the subject and the resource. Every request passes through it; it is the gatekeeper.

```
Subject (user + device)
        |
Policy Enforcement Point (PEP)
        | ^
Policy Administrator (PA) <-> Policy Engine (PE)
                                   ^
              [IdP, device compliance, threat intel,
               SIEM, PKI, continuous diagnostics]
```

The components map onto real products. The mapping below is illustrative, not an endorsement:

| NIST component | Typical realisation |
|---|---|
| Policy Enforcement Point | The cloud proxy PoP plus an endpoint agent or an application connector |
| Policy Administrator | The vendor cloud control plane |
| Policy Engine | The access-policy evaluation service |
| Data sources | IdP, EDR/posture, threat intelligence, DLP classification |

### Zero trust versus the traditional perimeter

The perimeter model trusts everything inside the firewall; a VPN simply extends that trusted zone, so a breach gives an attacker free lateral movement. Zero trust removes the implicit trust: every request is verified on identity, device, and context; access is micro-segmented to a specific application; and posture is re-evaluated continuously rather than once at connection.

### Micro-segmentation

Micro-segmentation divides the estate into small zones, each requiring authentication to enter, at one of three grains:

1. **Network-based**: VLANs and firewall rules between segments. Coarse.
2. **Host-based**: an agent on each workload enforces policy. Application-level.
3. **Application/identity-based**: access is granted to a named application, not a network segment. This is the ZTNA approach and the finest grain.

Traditional security focused on north-south (perimeter) traffic; zero trust addresses east-west (lateral movement) through service-mesh mTLS, ZTNA application connectors that only permit authorised user-to-application flows, and workload-segmentation agents.

## Software-Defined Perimeter (SDP)

SDP, specified by the Cloud Security Alliance, underpins many ZTNA products. Its defining mechanism is **Single Packet Authorization (SPA)**: the client proves identity before the server's address is revealed, so the application has no open ports for a scanner to find.

```
Client                         SDP Controller                Application (server)
  |-- 1. authenticate to IdP ------->|                              |
  |<- 2. short-lived token ----------|                              |
  |-- 3. encrypted SPA packet (token + HMAC, over UDP) ------------>|
  |                          server validates SPA with controller   |
  |                          firewall opens an ephemeral rule (seconds only)
  |-- 4. establish mTLS ------------------------------------------->|
  |<- 5. application response -------------------------------------|
```

SPA properties: the server has no open ports before a valid SPA; the packet carries a timestamp to prevent replay; the firewall rule is ephemeral (open for seconds, connection must establish quickly); there is no standing firewall-rule management.

## SASE architecture

### Points of Presence (PoPs)

SASE delivers the security stack from a global network of PoPs that act as distributed enforcement points. A usable PoP is close to users (a rule of thumb is under 20 ms, PoP in the same metro), peers directly with the major cloud and SaaS providers, is highly available (N+2 within a PoP, failover between PoPs), and runs the full security stack (TLS inspection, malware scan, DLP, CASB) in each PoP.

### Traffic steering

How traffic reaches the PoP is a design choice with security and coverage trade-offs:

| Method | Strength | Limitation |
|---|---|---|
| Endpoint agent | Strongest security, device-posture assessment, covers all apps | Needs software distribution; misses IoT/unmanaged |
| GRE/IPsec tunnel from a site | Covers all office traffic including IoT, no agents | Fixed bandwidth per tunnel, coarse per-user policy |
| PAC file / explicit proxy | No agent, quick to deploy | HTTP/HTTPS browser traffic only; user can bypass |
| DNS redirect | Instant, no agent | DNS-layer only; cannot inspect TLS; easy to bypass |

### Single-pass architecture

A traditional appliance chain re-reads and re-processes traffic at each hop (firewall, then IPS, then AV, then DLP, then proxy). Single-pass processing decrypts once and runs all engines together, which lowers latency (no re-encryption between stages), keeps policy consistent, and simplifies troubleshooting.

## SSE components in depth

### Secure Web Gateway (SWG)

The SWG secures internet-bound traffic: URL filtering by category, SSL/TLS inspection, anti-malware scanning of downloads, application control for SaaS, DNS-layer blocking, and bandwidth control. Deployment is a forward proxy (explicit, via PAC), a transparent proxy (tunnel or agent), or DNS-only (weakest, DNS-layer blocking only).

### SSL/TLS inspection

Because most web traffic is HTTPS, full SWG effectiveness needs inspection. The proxy terminates the client's TLS, validates the real server certificate against its own trust store, then presents the client a certificate it generates and signs with the customer's inspection CA. That CA must be installed as a trusted root on every managed device (via MDM or group policy) or users see certificate errors everywhere.

A bypass list is mandatory, not optional. Do not decrypt banking and financial sites (compliance, privacy), government sites, personal email and medical portals (privacy law), client-certificate mutual-TLS apps (the proxy cannot present the user's client certificate), or certificate-pinned mobile apps (pinning breaks). TLS 1.3 forward secrecy makes passive tap-based inspection mathematically impossible; only an active proxy with the CA on the endpoint works.

### Cloud Access Security Broker (CASB)

CASB gives visibility and control over SaaS. It works in three modes, and most enterprises run inline and API together:

- **Discovery (shadow IT)**: analyses proxy and firewall logs to enumerate the cloud apps in use (often well over a thousand in a large estate) and score them by risk from a cloud-app catalogue.
- **Inline (forward proxy)**: all SaaS traffic passes through, allowing real-time enforcement (block uploads to unsanctioned apps, allow view-only, block external sharing, separate corporate from personal tenant). For Microsoft 365, an inline CASB can inject a tenant-restriction header so the connection can only authenticate to the corporate tenant.
- **API (out-of-band)**: connects to the SaaS platform's API (Microsoft Graph, Google Workspace, Salesforce, Box) to scan stored content for PII, over-permissive sharing, malware, and misconfiguration. It cannot block in-flight traffic; it remediates after detection (remove a share link, quarantine, encrypt, alert, or a confirmed delete).

### Zero Trust Network Access (ZTNA)

ZTNA replaces VPN with identity-aware, application-level access. It comes agent-based (software on the endpoint that can assess device posture as part of the decision, the stronger option) or agentless (browser-based reverse proxy for contractors, BYOD, and partners, which cannot assess posture). The ZTNA-versus-VPN comparison and the ZTNA 1.0 versus 2.0 distinction are in `zero-trust-and-ztna.md`.

### Firewall as a Service (FWaaS)

FWaaS delivers next-generation firewall capability (L7 inspection, IPS, application control, DNS security, network sandboxing) from the cloud. It removes appliance maintenance and capacity planning, applies one policy across all locations and remote users, and stops the backhaul of cloud-bound traffic through an on-premises firewall. Remote users reach it by agent, sites by SD-WAN or GRE/IPsec tunnel.

## DLP in a SASE context

DLP runs at several points: email (a separate control point, see the email-security skills), web and SaaS egress (inline through the SWG and CASB), the endpoint (a local agent), and stored SaaS data (via the CASB API). Detection techniques span pattern matching (regex plus Luhn validation for cards), document fingerprinting (hashes of sensitive templates), exact data matching (an index of known structured values, very low false positives), and machine-learning classification (for source code and unstructured documents, higher false positives, use for discovery not blocking). Combining DLP with UEBA prioritises alerts by behaviour: a departing user moving large volumes to personal storage outranks a content match alone.

## UEBA

User and entity behaviour analytics feeds behavioural context into policy. It tracks time-of-day, application-usage, data-volume, geographic, and device patterns, and maintains a dynamic per-user risk score that can trigger step-up authentication, session termination, investigation-queue prioritisation, or tighter CASB rules. Its data comes from proxy logs, IdP events, endpoint telemetry, cloud-platform logs, and SIEM correlation.

## SD-WAN as the on-ramp

SD-WAN provides the optimised WAN connectivity that feeds the SASE security stack: path selection across MPLS, broadband, and 4G/5G by link quality; direct internet breakout at the branch for cloud-bound traffic; WAN optimisation; and an encrypted overlay. Single-vendor SASE builds SD-WAN and SSE as one platform (one agent, one policy, one console); best-of-breed combines a separate SD-WAN vendor with a separate security vendor and accepts the integration and dual-management cost.

## Identity integration

Zero trust depends entirely on a strong identity signal, so the IdP is the primary trust source (see `identity-access-management` for the identity platform itself). SASE platforms integrate with the IdP over SAML 2.0 (older, SSO-only, common in enterprise SaaS) or OIDC/OAuth 2.0 (JSON/JWT, modern, also carries API authorisation). They also consume the IdP's conditional-access decision: the IdP checks device compliance at authentication time, and the SASE platform applies continuous, session-level policy after. Device-posture signals feeding the decision include OS and patch level, disk encryption, EDR presence and health, MDM enrolment, screen-lock, jailbreak/root detection, and certificate-based device identity.
