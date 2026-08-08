---
name: fortisase
description: "Use for Fortinet FortiSASE configuration, operations, and security-posture auditing. Covers the FortiClient endpoint agent and FortiClient EMS integration (compliance rules, ZTNA posture tags, on-fabric vs off-fabric detection), secure private access (ZTNA application gateways, access proxy rules, posture-tag enforcement, identity-based access), secure internet access (Secure Web Gateway URL and application control, DNS filter, inline CASB, FWaaS firewall policy and UTM profile binding), SSL/TLS deep-inspection deployment and the inspection CA, SD-WAN convergence with FortiGate thin edges (tunnel health, overlay SLA, cloud-vs-edge policy consistency, firmware currency), FortiGuard subscription and signature currency, FortiAnalyzer Cloud logging, the FortiCloud IAM bearer-token auth model and the FortiOS CMDB/monitor REST API, and the read-only audit flow with threshold tables and remediation prioritisation. When not to use: for SASE/SSE and zero-trust DESIGN, assessment, and platform selection (whether FortiSASE fits, single-vendor vs best-of-breed, the maturity model) see sase-sse; for zero-trust IDENTITY governance (IdP, MFA, conditional access, PAM, IGA) see identity-access-management; for IPsec/SSL-VPN tunnel diagnosis see vpn-tunnel-troubleshooting; for on-premises FortiGate firewall policy auditing (distinct from cloud FortiSASE) see fortigate-firewall-audit; for the device-posture EDR signal see endpoint-detection-response. This skill owns FortiSASE configuration and operations. References architecture.md, operations.md, api-and-automation.md. Triggers include \"FortiSASE\", \"Fortinet SASE\", \"FortiClient\", \"FortiClient EMS\", \"FortiSASE ZTNA\", \"access proxy\", \"ZTNA posture tag\", \"secure private access\", \"secure internet access\", \"FortiSASE SWG\", \"secure web gateway FortiSASE\", \"FortiSASE FWaaS\", \"thin edge\", \"FortiSASE SD-WAN\", \"FortiSASE PoP\", \"FortiGuard\", \"FortiAnalyzer Cloud\", \"FortiCloud API\", \"FortiSASE audit\", \"FortiSASE policy\", \"FortiSASE endpoint compliance\", \"SSL deep inspection FortiSASE\"."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# FortiSASE

> **Skill marker**: When applying this skill, begin your reply with `[skill: fortisase]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Fortinet FortiSASE configuration, operations, and security-posture auditing. It assumes the design decision (FortiSASE is the right platform for this estate, single-vendor SASE over best-of-breed SSE) has already been made; for that decision, the zero-trust maturity assessment, and the platform comparison, see `sase-sse`. The depth here is the FortiSASE-specific architecture: the FortiClient endpoint agent and EMS, the Secure Web Gateway and FWaaS policy chain, the ZTNA access proxy, the thin edge FortiGate and its SD-WAN overlay, and the FortiCloud plus FortiOS REST APIs that drive and audit all of it.

## Overview

FortiSASE is Fortinet's cloud-delivered SASE service. It converges the security stack an on-premises FortiGate would run (web filter, application control, IPS, antivirus, DNS filter, DLP, inline CASB, SSL inspection) with a cloud fabric of Points of Presence (PoPs), and steers traffic to it three ways:

- **FortiClient endpoint agent** for roaming and remote users (agent-based steering), managed through FortiClient EMS which also supplies the device-posture signal.
- **Thin edge FortiGate** at branch sites, tunnelling site traffic (IPsec or SSL) to the nearest PoP and converging SD-WAN with the security overlay.
- **Secure private access (ZTNA)** through an access proxy that grants identity-aware, application-level access to private resources, replacing full-network VPN.

The two service faces are **secure internet access** (SWG plus FWaaS: outbound web and application traffic inspected in the cloud) and **secure private access** (ZTNA: inbound access to named private applications). FortiClient posture tags are the connective tissue: EMS evaluates compliance, tags the endpoint, and the ZTNA access proxy consumes the tag as an access condition.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (existing FortiGate footprint, FortiClient EMS deployment, IdP, SD-WAN posture, compliance drivers) before advising. Only ask the user for information not already covered.

Before configuring or auditing, establish:

1. **Which steering methods are in play.** FortiClient agent, thin edge, ZTNA, or a mix. The audit and configuration surface differs per method.
2. **The FortiClient EMS integration.** EMS server address, ZTNA tag definitions, compliance rule sets, endpoint group assignments. EMS is the posture source; without a healthy EMS sync, ZTNA enforcement is blind.
3. **The FortiGuard subscription set.** Which services are licensed (AV, IPS, Web Filter, Application Control, DNS Filter, Inline CASB, DLP). An unlicensed service cannot enforce.
4. **The tenant topology.** PoP regions, thin edge inventory and firmware targets, licensed vs connected endpoints, SD-WAN SLA definitions.

## When to use

- Configuring or reviewing Secure Web Gateway profiles: web filter URL categories, application control, DNS filter, and their binding to FWaaS firewall policies.
- Building or auditing ZTNA access proxy rules: posture-tag enforcement, identity-based access, application definitions, rule ordering.
- Validating thin edge FortiGate integration: tunnel health, SD-WAN overlay SLA, cloud-vs-edge policy consistency, firmware currency.
- Assessing FortiClient endpoint compliance: EMS sync health, compliance rules, ZTNA tag assignment, on-fabric vs off-fabric detection.
- Deploying or reviewing SSL/TLS deep inspection: profile coverage, the inspection CA distribution, exemption lists.
- Verifying FortiGuard subscription status and signature currency across services.
- Checking FortiAnalyzer Cloud logging coverage and alert policy completeness.
- Driving any of the above through the FortiCloud and FortiOS REST APIs.

## When not to use

- **SASE/SSE and zero-trust DESIGN, maturity assessment, or platform selection** (whether FortiSASE fits, single-vendor vs best-of-breed, the five-pillar maturity model, VPN-to-ZTNA architecture): `sase-sse` owns the design and the selection; this skill builds and operates the platform once chosen.
- **Zero-trust IDENTITY governance** (IdP selection, MFA rollout, conditional access, privileged access management, identity governance): `identity-access-management`. FortiSASE consumes the identity source (SAML/LDAP/RADIUS); it does not govern it.
- **IPsec or SSL-VPN tunnel diagnosis** (phase-1/phase-2 negotiation, client faults): `vpn-tunnel-troubleshooting`. This skill covers the thin edge tunnel's role in the overlay, not the low-level tunnel debug.
- **On-premises FortiGate firewall auditing**: `fortigate-firewall-audit`. FortiSASE (cloud SASE) is a distinct product from an on-prem FortiGate appliance; do not conflate them. Route an on-prem FortiGate policy audit there. This skill covers the thin edge FortiGate only in its FortiSASE-managed, SD-WAN-convergence role.
- **The endpoint EDR/posture signal in depth** (how the device-health signal a ZTNA policy consumes is produced): `endpoint-detection-response`. This skill covers FortiClient compliance as consumed by FortiSASE.

## Core model (condensed)

**Posture tags are the spine of secure private access.** FortiClient reports to EMS; EMS evaluates compliance rules (OS patch level, AV running, vulnerability count, firewall on, disk encryption) and assigns a ZTNA tag; the tag propagates to FortiSASE; the access proxy rule requires the tag. A ZTNA rule without a posture-tag condition admits non-compliant devices, which defeats the control. Track the posture-tag coverage ratio (rules with a tag requirement over total ZTNA rules).

**Secure internet access is only as good as its UTM binding and its inspection depth.** An SWG or FWaaS accept policy without antivirus, IPS, web-filter, and application-control profiles bound passes traffic uninspected. And a policy using certificate-inspection instead of deep-inspection sees only connection metadata on HTTPS: AV and IPS never see the payload. The two failure modes compound; audit binding and inspection depth together, not separately.

**The thin edge tunnel is the site's protection.** A thin edge whose tunnel to the PoP is down means that site's traffic is not going through FortiSASE at all. Verify tunnel state, prefer dual-tunnel redundancy to a second PoP, keep firmware within N-1 of the recommended target, and confirm SD-WAN SLA failover does not steer traffic around the security overlay.

**FortiGuard currency and EMS sync are the two silent-failure surfaces.** A licensed-but-stale FortiGuard service or a disconnected EMS both look healthy at a glance while enforcement quietly degrades. Check signature age against the service's expected cadence (AV daily, most others weekly) and EMS last-sync recency (under 15 minutes healthy).

**Everything is FortiCloud-authenticated and FortiOS-shaped underneath.** Tenant and topology data comes from the FortiSASE management API (`/api/v1/fortisase/*`); the security policy, UTM profiles, and inspection settings come from the FortiOS CMDB REST API (`/api/v2/cmdb/*`) that FortiSASE exposes, with monitor endpoints (`/api/v2/monitor/*`) for live status. Auth is a FortiCloud IAM bearer token with a limited TTL; read-only IAM scopes are enough for an audit.

**Anti-patterns:** a ZTNA rule keyed on source IP instead of identity plus posture tag; an SWG accept policy with no UTM profiles bound; certificate-inspection where deep-inspection is required; the inspection CA not distributed to endpoints (TLS errors or silent bypass); a thin edge on single-tunnel with no redundant PoP; firmware more than one major version behind; a FortiGuard service licensed but with stale signatures; EMS disconnected while ZTNA rules still trust its tags; overly broad SSL-inspection exemptions; log types missing from FortiAnalyzer Cloud creating investigation blind spots.

## Reference router

| Need | Load |
|---|---|
| FortiSASE architecture: PoPs, the three steering methods, FortiClient EMS, the SWG/FWaaS chain, the ZTNA access proxy, thin edge and SD-WAN convergence, SSL inspection, FortiGuard, FortiAnalyzer Cloud | `references/architecture.md` |
| Operations and the read-only audit flow: the nine-step audit sequence, threshold tables, decision trees, the report template, troubleshooting recipes | `references/operations.md` |
| API and automation: FortiCloud IAM auth and token refresh, the FortiSASE management endpoints, the FortiOS CMDB/monitor endpoints, response structures, pagination, rate limiting, error handling, secret discipline | `references/api-and-automation.md` |

## Cross-references

- `sase-sse`: the vendor-neutral SASE/SSE and zero-trust design and platform-selection umbrella. Decides whether FortiSASE fits; this skill builds and operates it. Reciprocal reference.
- `zscaler`, `prisma-access`: sibling per-vendor SASE operations skills for the other platforms in the family; consult when comparing or migrating between vendors.
- `fortigate-firewall-audit`: on-premises FortiGate firewall policy auditing, a distinct product from cloud FortiSASE. The thin edge FortiGate's non-FortiSASE local configuration routes there.
- `identity-access-management`: the identity substrate (IdP, MFA, conditional access, PAM, IGA) that FortiSASE ZTNA consumes as its SAML/LDAP/RADIUS source.
- `vpn-tunnel-troubleshooting`: IPsec and SSL-VPN tunnel diagnosis. This skill owns the thin edge tunnel in its overlay role; that owns the low-level tunnel debug.
- `endpoint-detection-response`: the device-posture signal a ZTNA policy consumes (the Device pillar of zero trust). FortiClient compliance here; EDR depth there.
- `secrets-hygiene`: FortiCloud API credentials, the FortiSASE API token, and thin edge admin credentials live in the secret store, never inline in a saved API call or a runbook.

## Red flags

- About to accept a ZTNA access proxy rule that keys on source IP instead of identity plus a device posture tag.
- About to leave an SWG or FWaaS accept policy with no antivirus, IPS, web-filter, or application-control profile bound.
- About to rely on certificate-inspection where deep-inspection is required, so AV and IPS never see the HTTPS payload.
- About to enable deep inspection without distributing the FortiSASE inspection CA to endpoints (TLS errors or silent inspection bypass).
- About to sign off a thin edge on a single tunnel with no redundant PoP, or firmware more than one major version behind the recommended target.
- About to treat a FortiGuard service as protective because it is licensed, without checking signature age against its expected cadence.
- About to trust ZTNA posture tags while FortiClient EMS is disconnected or its last sync is stale.
- About to write a broad SSL-inspection exemption (a whole category or a wildcard domain) without a documented business justification.
- About to paste a FortiCloud credential or FortiSASE API token into a saved API URL or runbook instead of the secret store.

## Bottom line

FortiSASE converges the FortiGate security stack into a cloud fabric and steers traffic to it by FortiClient agent, thin edge, and ZTNA access proxy. Secure private access lives or dies by posture-tag enforcement, so verify EMS is healthy and every ZTNA rule requires identity plus a tag. Secure internet access lives or dies by UTM binding and inspection depth, so audit both together. Keep thin edge tunnels up and redundant, firmware current, FortiGuard signatures fresh, and FortiAnalyzer Cloud receiving every log type. Drive it all through the FortiCloud and FortiOS REST APIs with read-only scopes for an audit. Bring the platform decision from `sase-sse`, route on-prem FortiGate auditing to `fortigate-firewall-audit`, and keep every credential in the secret store.

## Reference files

- `references/architecture.md`: the FortiSASE fabric (PoPs and regions), the three traffic-steering methods, FortiClient and FortiClient EMS, the Secure Web Gateway and FWaaS policy chain, the ZTNA access proxy and posture tags, thin edge FortiGate and SD-WAN convergence, SSL/TLS inspection design, FortiGuard services, and FortiAnalyzer Cloud logging.
- `references/operations.md`: the read-only security-posture audit (nine-step sequence from tenant discovery through logging), threshold tables (SWG coverage, ZTNA enforcement, thin edge health, FortiClient compliance, FortiGuard currency), decision trees for gap prioritisation, the report template, and troubleshooting recipes (FortiCloud auth, tunnel flapping, EMS sync delays, FortiGuard connectivity, ZTNA tag propagation, PoP capacity).
- `references/api-and-automation.md`: FortiCloud IAM bearer-token auth and refresh, the FortiSASE management API endpoints, the FortiOS CMDB and monitor endpoints, common response structures, pagination, rate limiting and backoff, error-code handling, and secret-store discipline for the credentials involved.
