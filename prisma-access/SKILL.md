---
name: prisma-access
description: "Use for Palo Alto Networks Prisma Access (cloud-delivered SASE) configuration, operations, auditing, and troubleshooting. Covers ZTNA 2.0 private-application access, cloud FWaaS and SWG, the GlobalProtect mobile-user agent and HIP posture, remote-network and service-connection IPsec tunnels, threat-prevention profiles (antivirus, anti-spyware, vulnerability protection, WildFire, URL filtering, DNS security), SSL/TLS decryption coverage, inline and API CASB, ADEM (Autonomous Digital Experience Management), Prisma SD-WAN integration, management through Strata Cloud Manager and Panorama, Cortex Data Lake logging, and the Strata Cloud Manager and Prisma Access Insights REST APIs for read-only audit and automation. Includes a SASE posture-audit flow with threshold tables and remediation decision trees. Triggers include \"Prisma Access\", \"Palo Alto SASE\", \"GlobalProtect\", \"GlobalProtect Cloud Service\", \"ZTNA 2.0\", \"ADEM\", \"Autonomous DEM\", \"Strata Cloud Manager\", \"SCM\", \"Panorama Prisma Access\", \"Prisma Access remote network\", \"Prisma Access service connection\", \"Prisma Access mobile users\", \"Prisma Access decryption\", \"Prisma Access HIP\", \"Prisma Access WildFire\", \"Prisma SD-WAN\", \"CloudGenix ION\", \"Cortex Data Lake\", \"Prisma Access API\", \"Prisma Access audit\", \"Palo Alto cloud firewall\". For vendor-neutral SASE/SSE and zero-trust DESIGN, assessment, maturity scoring, and platform selection (which SASE to choose) see sase-sse; this skill OWNS Prisma Access configuration and operations once that platform decision is made. When not to use / route: for zero-trust IDENTITY governance (IdP, MFA, conditional access, PAM, IGA) see identity-access-management; for IPsec/SSL-VPN tunnel fault diagnosis see vpn-tunnel-troubleshooting; for auditing an on-premises PAN-OS hardware or VM firewall (distinct from cloud Prisma Access) see palo-alto-firewall-audit; for the device-posture and EDR signal a ZTNA policy consumes see endpoint-detection-response; for sibling SASE vendors see zscaler and fortisase. References architecture.md, operations.md, and api-and-automation.md."
license: MIT
metadata:
  version: 1.0.0
---

# Prisma Access

> **Skill marker**: When applying this skill, begin your reply with `[skill: prisma-access]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Palo Alto Networks Prisma Access configuration, operations, auditing, and troubleshooting. Prisma Access is the cloud-delivered SASE platform: ZTNA 2.0 private-application access, cloud FWaaS and secure web gateway, CASB, DNS security, DLP, and ADEM digital-experience monitoring, all running the PAN-OS engine across 100-plus global compute locations and managed through Strata Cloud Manager or Panorama. It assumes the platform decision (Prisma Access is the right SASE for this estate) has already been made; for that decision see `sase-sse`. The depth here is the deployment model, the policy and profile configuration, the mobile-user and branch connectivity, and the API automation and audit that keep a Prisma Access tenant healthy and inspecting all traffic.

Prisma Access reuses PAN-OS concepts (security zones, App-ID, Content-ID, User-ID, security profiles) but delivers them as a distributed cloud fabric, not a single appliance. That distinction is the recurring source of confusion, so hold it firmly: this skill is the cloud SASE service, `palo-alto-firewall-audit` is the on-premises firewall.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (existing PAN-OS firewalls, IdP, EDR, current remote-access model, licence tier, management plane) before advising. Only ask the user for what is not already covered.

Before configuring or auditing, establish:

1. **The management plane.** Strata Cloud Manager (SCM, cloud-native, recommended for new tenants) or Panorama (the Cloud Services plugin, for estates with an existing Panorama). One plane per tenant; the two are not run simultaneously against the same tenant. This decides where every change is made and which API you call.
2. **The deployment surfaces in use.** Mobile users (GlobalProtect agent), remote networks (branch IPsec), and service connections (private-app return path to a data centre or VPC). Each has its own policy folder and its own failure modes.
3. **The licence edition.** Business, Business Premium, or Enterprise determines which features (Advanced URL Filtering, ADEM, CASB, DLP) are even available. Do not design against a feature the licence does not carry.
4. **The intended security posture.** Which traffic must be decrypted and inspected, which App-IDs are allowed, and which Security Profile Group binds to each allow rule. Uninspected allow rules are the single most common finding.

## When to use

- Configuring ZTNA 2.0 private-application access: service connections, application definitions, and the continuous-verification policy structure.
- Building or reviewing security policy for mobile users and remote networks (App-ID rules, Security Profile Groups, decryption rules).
- Setting up GlobalProtect (portal and gateway config, connection modes, split versus full tunnel, HIP posture checks, always-on enforcement).
- Configuring remote-network and service-connection IPsec tunnels (IKE gateways, crypto profiles, BGP routing).
- Tuning threat-prevention profiles (antivirus, anti-spyware, vulnerability protection, WildFire, URL filtering, DNS security) and binding them into profile groups.
- Enabling and reading ADEM for end-user digital-experience monitoring and root-cause analysis.
- Auditing a Prisma Access tenant's posture (policy coverage, profile strength, decryption reach, tunnel and service-connection health) against threshold tables.
- Automating configuration reads and audit against the Strata Cloud Manager and Prisma Access Insights REST APIs.
- Troubleshooting GlobalProtect connectivity, tunnel flaps, BGP instability, decryption certificate errors, or compute-location capacity.

## When not to use

- **Vendor-neutral SASE/SSE and zero-trust DESIGN, maturity assessment, or platform selection** (which SASE to choose, ZTNA-versus-VPN architecture, the NIST 800-207 model): route UP to `sase-sse`. That umbrella decides whether Prisma Access fits and how the architecture should look; this skill builds and runs it once chosen.
- **Zero-trust IDENTITY governance** (IdP selection, MFA rollout, conditional access, privileged access management, identity governance): use `identity-access-management`. Prisma Access consumes identity from an IdP via SAML; it does not own the identity platform.
- **Diagnosing an IPsec or SSL-VPN tunnel fault in isolation** (phase-1/phase-2 negotiation, SSL-VPN client faults on a general tunnel): use `vpn-tunnel-troubleshooting`. This skill owns the Prisma Access remote-network and service-connection tunnels as part of the platform; the general tunnel-debugging depth lives there.
- **Auditing an on-premises PAN-OS firewall** (a hardware or VM NGFW, distinct from the cloud Prisma Access fabric): use `palo-alto-firewall-audit`. Prisma Access is cloud SASE; do not duplicate the on-prem firewall audit here, and do not treat a compute location as if it were a single manageable appliance.
- **The endpoint posture and EDR signal** a ZTNA policy or HIP profile consumes: use `endpoint-detection-response`.
- **Sibling SASE vendors**: `zscaler` (Zero Trust Exchange, ZIA/ZPA/ZDX) and `fortisase` (FortiClient, secure private access, SD-WAN convergence).

This skill OWNS Prisma Access configuration and operations.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / deployment | compute-location and PoP model, PAN-OS processing pipeline, GlobalProtect gateway architecture, ZTNA 2.0 policy engine, service-connection topology, Panorama versus SCM, Cortex Data Lake schema, WildFire and ADEM internals | `references/architecture.md` |
| Configuration + operations | security policy, threat-prevention profiles, GlobalProtect and HIP config, decryption, remote networks and service connections, CASB, ADEM operations, the posture-audit flow with threshold tables and decision trees, troubleshooting | `references/operations.md` |
| API + automation | SCM OAuth 2.0, config-API endpoints, Prisma Access Insights queries, pagination and rate limits, PAN-OS CLI for troubleshooting, Cortex Query Language, log forwarding, secret handling | `references/api-and-automation.md` |

## Core model (condensed)

**Prisma Access is PAN-OS delivered as a distributed cloud service, not an appliance.** Each compute location (PoP) is a full PAN-OS firewall cluster: App-ID identifies the application, Content-ID inspects it (Threat Prevention, URL, DNS, WildFire, DLP), User-ID maps the user. Anycast steers each user or tunnel to the nearest PoP. You never manage a PoP as a box; you manage intent centrally (SCM or Panorama) and the fabric enforces it everywhere.

**Three connectivity surfaces, three policy folders.** Mobile users reach the fabric through the GlobalProtect agent; branch sites through remote-network IPsec tunnels; private applications through service-connection IPsec tunnels back to the data centre or VPC. SCM scopes policy by folder (`Mobile Users`, `Remote Networks`, `Service Connections`, `Shared`). A rule in the wrong folder protects nothing.

**ZTNA 2.0 is continuous, app-level, inspected access.** Unlike connect-then-trust ZTNA 1.0, Prisma Access identifies the actual application with App-ID (not just port/protocol), re-evaluates trust on every transaction within the session, inspects all allowed traffic with Content-ID, and supports all ports and protocols (not just HTTP/S). Device posture from HIP and, if integrated, user-risk signals from Cortex XDR feed the policy continuously.

**Every allow rule needs a Security Profile Group, and inspection needs decryption.** An allow rule without a bound profile group passes traffic uninspected; that is the top audit finding. And a profile group only sees inside TLS if a decryption rule (SSL Forward Proxy) covers the flow and endpoints trust the forward-trust CA. Coverage of both is the real measure of protection, not the presence of a rule.

**The management plane is the source of truth; the API mirrors it.** SCM (or Panorama) holds the intended config; the Strata Cloud Manager config API reads it, and the Prisma Access Insights API reads operational telemetry (tunnel status, client versions, bandwidth). Audit reads the API; it does not mutate the fabric. Tokens are short-lived (roughly 15 minutes) and OAuth-scoped to the tenant TSG ID.

**Anti-patterns:** an allow rule with `application: any` and `service: any` (App-ID bypass, fully open); allow rules with no Security Profile Group (uninspected); internet-bound traffic left undecrypted (profiles see only metadata); split-tunnel branch traffic with no local security stack; a single service connection per data centre (single point of failure); GlobalProtect without always-on enforcement or HIP; TLS 1.0/1.1 permitted without inspection; a forward-trust CA approaching expiry unmonitored; funnelling all users through one compute location; treating a compute location as a manageable single appliance.

## Reference router

| Need | Load |
|---|---|
| Compute-location and PoP architecture, PAN-OS packet pipeline, App-ID and Content-ID internals, GlobalProtect gateway architecture and connection flow, HIP processing, ZTNA 2.0 policy engine and service-connection topology, Panorama versus SCM management, Cortex Data Lake log schema, WildFire sandbox flow, ADEM probe infrastructure and root-cause algorithm | `references/architecture.md` |
| Security-policy structure, threat-prevention profile tuning, GlobalProtect and HIP configuration, decryption policy, remote-network and service-connection setup, inline and API CASB, ADEM operations, the nine-step posture-audit flow, threshold tables, remediation decision trees, and troubleshooting recipes | `references/operations.md` |
| SCM OAuth 2.0 client-credentials flow, config-API endpoint catalogue, Prisma Access Insights query API, pagination, rate limits, error codes, PAN-OS CLI troubleshooting commands, Cortex Query Language examples, log-forwarding integration, and secret-store discipline | `references/api-and-automation.md` |

## Cross-references

- `sase-sse`: the vendor-neutral SASE/SSE and zero-trust design-and-selection umbrella. Decides whether Prisma Access fits; this skill builds and operates it. Reciprocal reference.
- `zscaler`, `fortisase`: sibling per-vendor SASE skills (Zscaler Zero Trust Exchange; Fortinet FortiSASE). Consult when comparing or migrating between platforms.
- `palo-alto-firewall-audit`: the on-premises PAN-OS firewall audit. Prisma Access is the cloud SASE fabric; that skill owns the hardware and VM NGFW. Keep the boundary sharp and do not duplicate.
- `identity-access-management`: the IdP, MFA, and conditional-access substrate Prisma Access consumes via SAML. Owns the identity platform; this skill owns the network-access side.
- `vpn-tunnel-troubleshooting`: general IPsec and SSL-VPN tunnel diagnosis. This skill owns Prisma Access remote-network and service-connection tunnels; that owns the general tunnel-fault depth.
- `endpoint-detection-response`: the device-posture and EDR signal HIP profiles and Cortex XDR integration consume (the Device pillar of zero trust).
- `secrets-hygiene`: SCM Service Account client secrets, Panorama API keys, and pre-shared keys are credentials; store them in the secret store, never inline them in a saved API call, runbook, or policy export.

## Red flags

- About to leave an allow rule with `application: any` and `service: any`: that bypasses App-ID entirely and is a fully open rule. Replace with named App-IDs and `application-default`.
- About to ship an allow rule with no Security Profile Group bound: traffic passes uninspected. Bind the full group (antivirus, anti-spyware, vulnerability protection, URL filtering, WildFire, file blocking) on internet-bound flows.
- About to rely on threat profiles while internet-bound traffic is undecrypted: profiles see only TLS metadata. Add SSL Forward Proxy decryption and distribute the forward-trust CA to endpoints.
- About to leave split-tunnel branch traffic breaking out locally with no security stack: that traffic is uninspected. Full-tunnel through Prisma Access, or add a local inspection control.
- About to stand up a single service connection per data centre: it is a single point of failure. Configure primary and secondary to different compute locations.
- About to deploy GlobalProtect without always-on enforcement or HIP posture checks: users can disable protection and non-compliant devices get full access.
- About to permit TLS 1.0/1.1 without inspection, or let the forward-trust CA drift toward expiry unmonitored: both silently break inspection. Block or decrypt legacy TLS and calendar the CA renewal.
- About to mix Panorama and SCM management on the same tenant, or audit the legacy Panorama API after a tenant has migrated to SCM: confirm which plane is authoritative first, or you act on stale config.
- About to treat a compute location as a single manageable appliance, or route this task to the on-prem firewall audit: Prisma Access is a distributed cloud fabric; on-prem PAN-OS auditing belongs in `palo-alto-firewall-audit`.
- About to paste a Service Account client secret, Panorama API key, or pre-shared key into a saved API URL or runbook instead of the secret store.

## Bottom line

Prisma Access is PAN-OS as a cloud service: you manage intent centrally and the fabric enforces it across every compute location, so the discipline is coverage, not device-by-device tuning. Bind a Security Profile Group to every allow rule and decrypt the traffic those profiles are meant to inspect, or the protection is illusory. Prefer ZTNA 2.0 (continuous, app-level, inspected) over connect-then-trust access, full-tunnel over unguarded split-tunnel, and redundant service connections over a single point of failure. Keep GlobalProtect always-on with HIP posture, watch tunnel and CA health, and confirm which management plane is authoritative before you change or audit anything. Bring the platform decision from `sase-sse`, keep the on-prem firewall work in `palo-alto-firewall-audit`, and hold every credential in the secret store.

## Reference files

- `references/architecture.md`: compute-location (PoP) architecture, the PAN-OS packet-processing pipeline, App-ID and Content-ID internals, GlobalProtect gateway architecture and the eight-step connection flow, HIP data collection and match objects, the ZTNA 2.0 policy engine and service-connection topology, continuous-trust verification mechanics, Panorama versus Strata Cloud Manager management and policy inheritance, the Cortex Data Lake log schema, the WildFire sandbox flow, and ADEM probe infrastructure with the root-cause algorithm.
- `references/operations.md`: security-policy rule structure for mobile users and remote networks, threat-prevention profile tuning, GlobalProtect and HIP configuration, SSL/TLS decryption policy, remote-network and service-connection setup, inline and API CASB, ADEM operations, the nine-step SASE posture-audit flow, threshold tables (policy coverage, profile strength, client compliance, service-connection health, decryption coverage), remediation decision trees, and the common troubleshooting recipes.
- `references/api-and-automation.md`: the Strata Cloud Manager OAuth 2.0 client-credentials flow and the legacy Panorama API key flow, the configuration-API endpoint catalogue, the Prisma Access Insights query API, pagination and rate limits, error codes, PAN-OS CLI troubleshooting commands, Cortex Query Language examples, log-forwarding integration, and the secret-store discipline for every credential involved.
