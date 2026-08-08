---
name: attack-surface-management
description: "Use for vendor-neutral external attack surface management (EASM / ASM) design: discovering unknown internet-facing assets, attributing them to the organisation, and reducing external exposure from the attacker's outside-in perspective. Covers the discovery methods (domain and subdomain enumeration, certificate transparency logs, IP range and BGP/ASN ownership, WHOIS/RDAP, passive DNS, internet-wide scan data, web crawling, and asset correlation), the asset types found (subdomains, cloud-assigned IPs, exposed services and open ports, SSL/TLS certificates including expired ones, public cloud storage, code repositories, shadow IT and acquired-company assets), attribution and false-positive reduction, EASM versus traditional vulnerability management, the core workflows (initial seed-and-discovery, attribution review and asset acceptance, continuous monitoring and drift detection, the EASM-to-VM feedback loop, attack surface reduction), exposure-management (CTEM) positioning, and EASM platform selection (Microsoft Defender EASM, Palo Alto Cortex Xpanse, CrowdStrike Falcon Surface, Censys, Shodan). The organising idea is discover from the attacker's outside-in perspective, attribute what is genuinely yours, feed exposed assets back to vulnerability management for credentialed scanning and remediation, and continuously reduce what is needlessly exposed. References discovery-and-attribution.md, workflows-and-integration.md, platform-selection.md. Triggers include \"attack surface management\", \"ASM\", \"EASM\", \"external attack surface\", \"internet-exposed assets\", \"internet-facing assets\", \"shadow IT discovery\", \"unknown assets\", \"subdomain enumeration\", \"certificate transparency\", \"passive DNS\", \"asset discovery\", \"asset attribution\", \"exposure management\", \"attack surface reduction\", \"Shodan\", \"Censys\", \"Defender EASM\", \"Cortex Xpanse\", \"Falcon Surface\". For managing and scanning the known assets EASM discovers see vulnerability-management; for active host, port, and service scanning see nmap-scanning; for the Microsoft Defender EASM platform see defender-easm; for the CVE lookup behind an exposed-service finding see nvd-cve; for security-driven network detection and IDS/IPS see network-detection-response; for credential and API-token handling see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Attack surface management

> **Skill marker**: When applying this skill, begin your reply with `[skill: attack-surface-management]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for external attack surface management (EASM). It owns the reasoning that survives any one platform: how internet-facing assets are discovered from the outside, how to attribute a discovery to the organisation without drowning in false positives, how EASM feeds vulnerability management, and how to reduce the surface. Platform-specific operations (a Defender EASM inventory, an Xpanse remediation flow) live in the per-vendor skills. Managing and scanning the known assets EASM surfaces is the job of `vulnerability-management`.

## When to use

- Standing up an EASM capability: seeds, discovery cadence, attribution, asset acceptance.
- Discovering unknown internet-facing assets: shadow IT, forgotten dev environments, misconfigured cloud endpoints, acquired-company estate.
- Reducing external exposure: deciding what should not be public and tracking exposure debt.
- Designing the EASM-to-VM feedback loop so a newly discovered exposed host gets scanned and remediated.
- Preparing for a CVE drop: knowing immediately which exposed services are affected.
- Selecting an EASM platform (Defender EASM, Xpanse, Falcon Surface, Censys) for a given environment.

## When not to use

- **Managing and scanning known assets** (credentialed vulnerability scans, prioritisation, SLAs on assets already in inventory): use `vulnerability-management`. This skill discovers and attributes; that one assesses and remediates.
- **Active host, port, and service scanning of a defined scope** (running nmap against your own ranges, NSE scripts): use `nmap-scanning`. EASM discovers from internet-wide data outside-in; nmap probes a scope you already own.
- **A specific EASM platform's configuration and operations** (a Defender EASM inventory build, an Xpanse API workflow): use `defender-easm` for Microsoft; other EASM platforms are named here as routing context only.
- **Reading the CVE behind an exposed-service finding**: use `nvd-cve` for the lookup, then `vulnerability-management` to prioritise.
- **Security-driven network detection and IDS/IPS** (detecting scanning and intrusion against you): use `network-detection-response`. This skill measures your external exposure; NDR detects attacks on the internal network.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Discovery + attribution | enumeration methods, certificate transparency, ASN/WHOIS, internet-wide scan data, asset types, attributing a discovery to the org, false-positive reduction | `references/discovery-and-attribution.md` |
| Workflows + integration | initial seed-and-discovery, asset acceptance, continuous monitoring, drift detection, the EASM-to-VM loop, surface reduction, CTEM | `references/workflows-and-integration.md` |
| Platform selection | Defender EASM vs Xpanse vs Falcon Surface vs Censys vs Shodan, evaluation criteria, routing | `references/platform-selection.md` |

## Core model (condensed)

**Discover from the attacker's outside-in perspective.** Your CMDB is not your attack surface. Attackers scan the whole internet and find what you have forgotten: development environments left running, shadow IT stood up by a business unit, misconfigured cloud resources with public endpoints, assets from an acquisition not yet inventoried, expired certificates, and services that were meant to be internal. EASM replicates that view, starting from what you know (domains, IP ranges, ASNs, company names) and enumerating outward.

**Attribution is the hard part, not discovery.** Enumeration is cheap; deciding which of the thousands of discovered hosts are genuinely yours is the work. Tie discoveries back through certificate subjects, WHOIS and ASN ownership, technology fingerprints, and content, and review before accepting an asset into the monitored inventory. A high false-positive rate poisons the whole programme: teams stop trusting the alerts.

**EASM and VM are complementary, not competing.** EASM answers "what is exposed"; VM answers "how vulnerable is it". The value is the integration: EASM discovers an exposed host, attributes it, and feeds it to the scanner, which runs a credentialed assessment, and the finding enters VM with a standard SLA. EASM without that loop is an inventory nobody acts on.

**Continuous, not scheduled.** The external surface changes daily. Re-scan all discovered assets continuously and alert on the deltas: a new asset, a newly opened port, an SSL certificate about to expire, a new vulnerability on an exposed service, or drift where a service that was closed is open again.

**Reduce the surface, do not just catalogue it.** The outcomes that matter are shutting down services that should not be public, hardening what must stay exposed (MFA, current patches, proper TLS), tracking exposure debt so you know exactly what is exposed and why, and being ready when a new CVE drops to answer in minutes whether any exposed service is affected.

**Anti-patterns:** treating the CMDB as the attack surface; accepting discoveries without attribution review (false-positive flood); building an inventory with no feedback loop into VM; scheduled instead of continuous monitoring; cataloguing exposure without ever reducing it.

## Reference router

| Need | Load |
|---|---|
| Discovery methods (domain/subdomain enumeration, certificate transparency, IP/ASN, WHOIS/RDAP, passive DNS, internet-wide scan data, web crawling, correlation), asset types discovered, attribution and false-positive reduction | `references/discovery-and-attribution.md` |
| Initial discovery and asset acceptance, continuous monitoring and drift detection, the EASM-to-VM feedback loop, attack surface reduction, exposure management (CTEM) | `references/workflows-and-integration.md` |
| EASM platform profiles (Defender EASM, Cortex Xpanse, Falcon Surface, Censys, Shodan), evaluation criteria, decision method, routing | `references/platform-selection.md` |

## Cross-references

- `vulnerability-management`: the destination of every confirmed exposed asset. Reciprocal reference: this skill discovers and attributes; that one scans, prioritises, and remediates. Together they are the discovery-plus-assessment halves of exposure management.
- `nmap-scanning`: active scanning of a scope you own, complementary to outside-in discovery; useful to confirm and detail an exposed service EASM surfaced.
- `nvd-cve`: the CVE lookup behind an exposed-service finding (is this exposed version affected by a known CVE).
- `defender-easm`: Microsoft Defender EASM platform configuration and operations. This umbrella decides whether it fits; that skill builds it. Xpanse, Falcon Surface, and Censys are named as routing context.
- `network-detection-response`: detects scanning and intrusion against the internal network; this skill measures the external exposure those attacks would target.
- `secrets-hygiene`: EASM platform API tokens and the credentials for any integration live in the secret store, never inline.

## Red flags

- About to treat the asset inventory or CMDB as the complete attack surface.
- About to accept discovered assets into monitoring with no attribution review (the false-positive flood that kills trust).
- About to build an EASM inventory with no feedback loop into vulnerability management.
- About to run EASM on a monthly schedule when the external surface changes daily.
- About to catalogue exposure indefinitely without ever shutting anything down.
- About to put an EASM platform API token inline in a script instead of the secret store.

## Bottom line

Discover from the attacker's outside-in view, because the forgotten and the shadow assets, not the ones in your CMDB, are the real attack paths. Spend the effort on attribution, not enumeration, so the inventory stays trustworthy. Feed every confirmed exposed asset into `vulnerability-management` for scanning and remediation; that loop is the point. Monitor continuously, alert on the deltas, and measure success as exposure reduced, not assets listed. Route per-platform operations to `defender-easm` and the CVE prioritisation back to `vulnerability-management`.
