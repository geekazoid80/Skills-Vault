---
name: zscaler
description: "Use for Zscaler Zero Trust Exchange configuration, operations, and policy audit. Covers ZIA (Zscaler Internet Access: secure web gateway, URL filtering, SSL/TLS inspection, cloud firewall, cloud sandbox, CASB, DLP), ZPA (Zscaler Private Access: App Connectors, application segments, server groups, access policies, device posture, Browser Access), ZDX (Zscaler Digital Experience: endpoint probes, network path analysis, experience scoring), the Zscaler Client Connector (ZCC) and its tunnel modes (Z-Tunnel 1.0/2.0, packet filter, split tunnel), the Zero Trust Exchange node (ZEN) and single-pass architecture, the ZPA broker and persistent App Connector tunnel, Nanolog Streaming Service (NSS) log export to SIEM, the ZIA and ZPA REST APIs (obfuscated-key session auth, OAuth 2.0 client credentials, cloud base URLs, rate limits, pagination), and the adjacent platform pieces (Zscaler Browser Isolation, Deception, SSMA, Posture Control CNAPP, ThreatLabZ). Also carries a read-only policy-audit lens: URL-filter rule ordering and shadow detection, SSL-inspection bypass gaps, cloud-firewall any-any and shadowed rules, ZPA segment over-scoping, access-policy posture enforcement, and connector health and redundancy. When not to use: for vendor-neutral SASE/SSE and zero-trust DESIGN, posture assessment, maturity scoring, and platform selection (Zscaler versus Prisma Access versus FortiSASE versus Netskope) see sase-sse; for zero-trust IDENTITY governance (IdP, MFA, conditional access, PAM, IGA) see identity-access-management; for IPsec or SSL-VPN tunnel diagnosis see vpn-tunnel-troubleshooting; this skill owns Zscaler configuration and operations. References architecture.md, zia-and-zpa.md, api-and-automation.md. Triggers include \"Zscaler\", \"ZIA\", \"ZPA\", \"ZDX\", \"Zscaler Internet Access\", \"Zscaler Private Access\", \"Zscaler Digital Experience\", \"Zero Trust Exchange\", \"App Connector\", \"application segment\", \"server group\", \"ZPA access policy\", \"Z-Tunnel\", \"ZCC\", \"Zscaler Client Connector\", \"ZEN\", \"Zscaler enforcement node\", \"SSL inspection bypass\", \"URL filtering policy\", \"cloud firewall rule\", \"cloud sandbox\", \"Zscaler CASB\", \"Zscaler DLP\", \"Nanolog\", \"NSS feed\", \"Zscaler API\", \"Zscaler audit\", \"Zscaler policy review\", \"Browser Access\", \"Zscaler posture profile\", \"provisioning key\", \"Zscaler Browser Isolation\", \"Zscaler Deception\". For SASE/SSE and zero-trust DESIGN, assessment, and platform selection see sase-sse."
license: MIT
metadata:
  version: 1.0.0
---

# Zscaler Zero Trust Exchange

> **Skill marker**: When applying this skill, begin your reply with `[skill: zscaler]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Zscaler configuration, operations, and policy audit across the Zero Trust Exchange: ZIA for internet-bound traffic, ZPA for private-application access, and ZDX for digital-experience monitoring. It assumes the design decision (Zscaler is the right platform, and which pillar to adopt first) has already been made; for that decision, for a zero-trust posture assessment, or for a platform comparison, see `sase-sse`. The depth here is the policy model, the App Connector and tunnel mechanics, the API automation, and the read-only audit lens that keeps a deployment safe and within least-privilege.

## Overview

The Zero Trust Exchange is Zscaler's cloud platform: every user session is brokered through a Zscaler Enforcement Node (ZEN), inspected once (single-pass), and forwarded, so there is no appliance in the data path and no implicit network trust. The three products a deployment usually runs are:

- **ZIA (Zscaler Internet Access)**: the outbound security stack (secure web gateway, URL filtering, SSL/TLS inspection, cloud firewall, cloud sandbox, CASB, DLP) for traffic leaving to the internet and SaaS.
- **ZPA (Zscaler Private Access)**: ZTNA for private applications. App Connectors dial outbound to the Zscaler cloud, so the application is never exposed and the user reaches a named app, not the network.
- **ZDX (Zscaler Digital Experience)**: end-to-end experience monitoring from the endpoint through the ISP path to the application, so a slowness complaint can be pinned to the device, the path, or the app.

The Zscaler Client Connector (ZCC) is the endpoint agent that steers traffic into ZIA and ZPA and runs the ZDX probes. Offices without ZCC steer via GRE/IPsec tunnel or a PAC file.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (which Zscaler cloud, which products are licensed, the IdP, the EDR, the current remote-access model) before advising. Only ask for what is not already covered.

Before configuring or auditing, establish:

1. **Which product and which task.** ZIA policy (URL, firewall, SSL, DLP, CASB, sandbox), ZPA access (segments, policies, connectors, posture), ZDX monitoring, ZCC steering, or the API/automation surface. Classify first; the depth lives in different references.
2. **The cloud name.** `zscaler.net`, `zscalerone.net`, `zscalertwo.net`, `zscloud.net`, and the gov and beta clouds each have their own API base URL. Getting this wrong points every API call at the wrong tenant.
3. **The steering model.** ZCC (remote users), GRE/IPsec tunnel (offices), or PAC file, and whether split tunnel is in use. This drives where policy is enforced and what bypasses it.
4. **The identity and posture substrate.** ZIA and ZPA policy both lean on the IdP (SAML/OIDC, SCIM provisioning) and the device-posture signal (EDR, MDM, disk encryption). If those are weak, the policy layer cannot compensate.
5. **Read-only versus change.** An audit uses read-only API scope and never activates a pending policy push. A configuration change needs a maintenance window and a rollback plan.

## When to use

- Building or tuning a ZIA policy: URL filtering rules, SSL inspection and its bypass list, cloud firewall rules, DLP engines and dictionaries, CASB app controls, sandbox policy.
- Designing ZPA access: application segments and server groups, access policies with posture conditions, App Connector groups and high availability, Browser Access for unmanaged devices.
- Deploying or sizing an App Connector, or diagnosing connector health, version drift, or redundancy gaps.
- Configuring ZCC tunnel mode and split-tunnel bypass, or steering an office via GRE/IPsec.
- Setting up ZDX monitoring and using it to triage a "this app is slow" complaint.
- Exporting logs to a SIEM via NSS, or automating policy retrieval and change through the ZIA/ZPA REST APIs.
- Running a read-only policy audit: rule ordering and shadows, inspection blind spots, segment over-scoping, posture enforcement, connector redundancy.

## When not to use

- **Vendor-neutral SASE/SSE and zero-trust DESIGN, posture assessment, maturity scoring, or platform selection** (Zscaler versus Prisma Access versus FortiSASE versus Netskope, Cloudflare, Cato): use `sase-sse`. That umbrella decides whether Zscaler fits and how the architecture should look; this skill builds and operates it. Reciprocal reference.
- **Zero-trust IDENTITY governance** (IdP selection, MFA rollout, conditional access, privileged access management, identity governance and administration): use `identity-access-management`. Zscaler consumes the IdP and SCIM feed; it does not own the identity platform.
- **IPsec or SSL-VPN tunnel diagnosis** (phase-1/phase-2, SSL-VPN client faults on a legacy concentrator): use `vpn-tunnel-troubleshooting`. This skill owns ZPA as the VPN replacement, not the diagnosis of the tunnel it replaces.
- **Endpoint posture and EDR depth** (the device-health signal a ZPA policy consumes): use `endpoint-detection-response`.
- **Storing the ZIA API key, ZPA client secret, SCIM bearer token, or admin credentials**: use `secrets-hygiene`. Never inline a live secret in a saved API call, a runbook, or a config file.

This skill **owns Zscaler configuration and operations**. Route design, selection, identity, and VPN diagnosis out per the list above; keep everything ZIA/ZPA/ZDX/ZCC here.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / platform | Zero Trust Exchange, ZEN topology, single-pass inspection, Z-Tunnel protocol, ZPA broker, App Connector persistent tunnel and sizing, ZDX pipeline, NSS log architecture, Browser Isolation, Deception, SSMA, Posture Control | `references/architecture.md` |
| ZIA + ZPA operations | URL filtering, SSL inspection, cloud firewall, sandbox, CASB, DLP, application segments, server groups, access policies, device posture, Browser Access, App Connector deployment, ZCC tunnel modes and split tunnel, the audit lens and thresholds | `references/zia-and-zpa.md` |
| API + automation | ZIA obfuscated-key session auth, ZPA OAuth 2.0, cloud base URLs, policy and connector endpoints, key response fields, rate limits, pagination, secret-store discipline | `references/api-and-automation.md` |

## Core model (condensed)

**Single-pass inspection at the nearest ZEN.** ZIA traffic is decrypted once and inspected by every engine (URL, App-ID, IPS, anti-malware, DLP, CASB, sandbox) in parallel, then re-encrypted and forwarded. There is no service chain of appliances, so latency overhead is small and every control sees the same decrypted stream. SSL inspection is therefore the load-bearing control: a do-not-inspect rule is a blind spot for every downstream engine at once.

**ZPA is app access, not network access.** The App Connector makes an outbound-only tunnel to the Zscaler cloud, so the private network needs no inbound firewall rule and the application is never internet-exposed. A user reaches a named application segment, brokered per session against identity plus device posture; there is no lateral movement because there is no network to move across. Deploy 2+ connectors per group for high availability; a single-connector group is a single point of failure.

**Policy is ordered and top-down, on both sides.** ZIA URL/firewall/SSL rules and ZPA access policies all evaluate in order, first match wins. A broad allow above a specific block is a bypass; a rule fully covered by an earlier, broader rule is shadowed and never fires. Order review is the first audit step on any rulebase.

**Steering decides what is even seen.** ZCC (Z-Tunnel 2.0 over DTLS, falling back to TCP/443) steers remote users; offices use GRE/IPsec or PAC. Split-tunnel bypass (for example Microsoft 365 Optimize endpoints per Microsoft's guidance) routes chosen traffic directly, off Zscaler. Anything bypassed is uninspected by design, so the bypass list is a security decision, not just a performance one.

**Least privilege is the through-line.** Wildcard application segments, `1-65535` port ranges, access policies with no posture condition, any-any firewall rules, and uninspected-yet-allowed URL categories are the recurring findings. Narrow the segment, pin the ports, bind a posture profile, and inspect what you allow.

## Reference router

| Need | Load |
|---|---|
| Zero Trust Exchange platform, ZEN and data-centre topology, single-pass processing, Z-Tunnel 2.0/DTLS, ZPA broker session flow, App Connector persistent tunnel and sizing, ZDX pipeline, NSS log architecture and feed formats, Browser Isolation, Deception, SSMA, Posture Control CNAPP, ThreatLabZ | `references/architecture.md` |
| ZIA policy (URL, SSL inspection, cloud firewall, sandbox, CASB, DLP), ZPA (application segments, server groups, access policies, device posture, Browser Access, App Connector deployment), ZDX operations and troubleshooting, ZCC tunnel modes and split tunnel, the read-only audit lens with threshold guidance | `references/zia-and-zpa.md` |
| ZIA session auth (obfuscated key), ZPA OAuth 2.0 client credentials, per-cloud base URLs, ZIA and ZPA endpoint tables, key response fields, rate limits, pagination, secret handling | `references/api-and-automation.md` |

## Cross-references

- `sase-sse`: the vendor-neutral SASE/SSE and zero-trust design and platform-selection umbrella. Decides whether Zscaler fits; this skill builds it. Reciprocal reference.
- `prisma-access`: Palo Alto Prisma Access operations, the sibling SASE vendor skill. Consult when comparing or migrating between the two platforms.
- `fortisase`: Fortinet FortiSASE operations, the sibling SASE vendor skill.
- `identity-access-management`: the IdP, MFA, conditional access, and SCIM substrate that ZIA and ZPA policy consume.
- `vpn-tunnel-troubleshooting`: IPsec and SSL-VPN tunnel diagnosis. This skill owns ZPA as the replacement; that owns the legacy tunnel while it exists.
- `endpoint-detection-response`: the device-posture and EDR signal a ZPA access policy consumes.
- `secrets-hygiene`: the ZIA API key, ZPA client secret, and SCIM bearer token live in the secret store, never inline in a saved API call or runbook.

## Red flags

- About to enable SSL inspection with no plan for the inspection CA rollout, the bypass list (banking, medical, government, certificate-pinned apps), or the privacy implications.
- A URL category that is both allowed and excluded from SSL inspection: a content-blind egress path. The highest-value ZIA finding.
- A cloud firewall any-any permit rule that is not the explicit default-deny at the bottom of the rulebase, or any rule with logging disabled.
- A ZPA application segment using a wildcard domain or a `1-65535` port range as a shortcut for incomplete app discovery.
- A ZPA access policy with no identity condition (default-allow) or no posture profile: unverified devices reaching internal apps.
- A ZPA connector group with a single connector, or connectors more than two versions behind the current release.
- Leaving the old VPN as a full-network fallback after ZPA is live, which preserves the lateral-movement path the migration was meant to remove.
- Backhauling internet traffic through a data-centre firewall after adopting ZIA, negating the latency and scale benefit of the cloud edge.
- Pasting an obfuscated API key, ZPA client secret, or admin password into a saved API URL or a committed file instead of the secret store.
- Running an audit against the wrong cloud base URL, or using write scope (activating a pending policy push) during a read-only review.

## Bottom line

Zscaler brokers every session through the nearest node and inspects it once, so SSL inspection coverage and rule ordering are where security is won or lost on the ZIA side, and least-privilege segments plus posture-bound access policies are where it is won on the ZPA side. Steer deliberately (what you bypass is uninspected by design), deploy connectors in redundant pairs, and pin your API calls to the correct cloud. Bring the platform decision and the zero-trust assessment from `sase-sse`, route identity to `identity-access-management`, and keep every credential in the secret store.

## Reference files

- `references/architecture.md`: the Zero Trust Exchange platform, ZEN and global data-centre topology, single-pass inspection and its latency budget, Z-Tunnel 2.0 over DTLS and TCP fallback, the ZPA broker session flow, the App Connector persistent tunnel and sizing table, the ZDX collection pipeline, NSS log architecture and feed formats, and the adjacent platform pieces (Browser Isolation, Deception, SSMA, Posture Control CNAPP, ThreatLabZ).
- `references/zia-and-zpa.md`: the operational configuration depth for ZIA (traffic flows, SSL inspection, URL filtering, cloud firewall, sandbox, CASB, DLP) and ZPA (application segments, server groups, access policies, device posture, Browser Access, App Connector deployment), ZDX operations and troubleshooting, ZCC tunnel modes and split tunnel, and the read-only policy-audit lens with threshold guidance and prioritisation.
- `references/api-and-automation.md`: ZIA session authentication with the obfuscated API key, ZPA OAuth 2.0 client-credentials flow, per-cloud base URLs, the ZIA and ZPA endpoint tables with key response fields, rate limits and backoff, pagination, and the secret-store discipline for API credentials.
