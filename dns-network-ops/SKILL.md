---
name: dns-network-ops
description: "Use for DNS architecture, design, comparison, and cross-platform operations: authoritative vs recursive roles, zone types, record types, zone transfers (AXFR/IXFR/NOTIFY/TSIG), DNSSEC chain of trust, encrypted DNS (DoH/DoT/DoQ), DNS security (RPZ, sinkholing, DNS firewall, RRL), caching and TTL strategy, split-horizon, and hybrid cloud DNS. References: concepts.md, dnssec.md, dns-security-and-encryption.md, platform-architecture.md. Triggers include \"DNS\", \"name resolution\", \"DNSSEC\", \"zone transfer\", \"AXFR\", \"IXFR\", \"TSIG\", \"authoritative DNS\", \"recursive DNS\", \"DNS resolution flow\", \"record types\", \"SOA\", \"DoH\", \"DoT\", \"DoQ\", \"split-horizon\", \"split-brain DNS\", \"RPZ\", \"DNS firewall\", \"DNS sinkhole\", \"DNS security\", \"TTL strategy\", \"negative caching\", \"hybrid DNS\", \"DNS architecture\", \"DNS migration\". For platform-specific implementation route to the vendor skills in this family: bind-dns-ops, powerdns-ops, windows-dns-ops, coredns-ops, unbound-dns-ops, route53-dns-ops, azure-dns-ops, cloudflare-dns-ops. For broader routing/switching context see multi-vendor-network-ops; for IPAM and DNS source-of-truth see network-source-of-truth."
license: MIT
metadata:
  version: 1.0.0
---

# DNS network ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: dns-network-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the routing and architecture entry point for all DNS work. It owns the cross-platform, comparative, and conceptual layer: how resolution works, how to design zones and DNSSEC, how to choose between platforms, and how to combine them into resilient hybrid architectures. Platform-specific implementation (named.conf, PowerShell DNS, Route 53 routing policies, Cloudflare proxy mode) belongs in the vendor skills listed below.

## When to use

- Designing a DNS architecture: internal-only, split-horizon, hybrid cloud, or multi-provider resilience.
- Comparing platforms before a deployment or migration (Windows DNS vs BIND vs Route 53 vs Cloudflare and others).
- Explaining or troubleshooting DNS resolution end-to-end (stub, recursive, root, TLD, authoritative).
- Designing DNSSEC: key strategy (KSK/ZSK/CSK), chain of trust, DS records, NSEC vs NSEC3, algorithm choice.
- Planning DNS security layers: RPZ, sinkholing, DNS firewall, rate limiting, encrypted transport.
- Setting a TTL and caching strategy, including pre-migration TTL lowering and negative-caching tuning.
- Deciding between AXFR/IXFR and how to secure zone transfers with TSIG and ACLs.

## When not to use

- **Platform-specific configuration or troubleshooting**: route to the vendor skill (see "Vendor skills" below).
- **IP address management, DNS/DHCP source-of-truth, reconciliation**: use `network-source-of-truth`.
- **Mail authentication record design (SPF/DKIM/DMARC) beyond the DNS record mechanics**: use `smtp-deliverability`.
- **Certificate issuance and CAA strategy beyond the record itself**: use the relevant PKI skill.

## Authoritative vs recursive (the first classification)

Every DNS question resolves to one of two roles. Classify first; it determines the platform, the security model, and the failure mode.

| Role | Answers for | Exposure | Primary risks |
|---|---|---|---|
| Authoritative | Zones it is delegated (via NS + DS records) | Public (external zones) or internal | Zone data integrity, DNSSEC key management, zone-transfer security, single point of failure |
| Recursive (resolver) | Any name, by walking the delegation chain and caching | Internal clients only (never open to the internet) | Cache poisoning, open-resolver abuse (amplification), exfiltration via DNS, resolver outage |

The single most common production mistake is exposing a recursive resolver to the internet without access controls; it will be abused for DNS amplification attacks. Authoritative and recursive concerns rarely share a security model, so keep them separate in design.

## Platform selection

| Platform | Best for | Key strengths | Vendor skill |
|---|---|---|---|
| Windows DNS | AD environments, Windows-centric estates | AD-integrated zones, secure dynamic updates, DNS policies, PowerShell | `windows-dns-ops` |
| BIND | Linux authoritative or recursive, maximum flexibility | Views (split-horizon), RPZ, KASP DNSSEC, catalog zones | `bind-dns-ops` |
| PowerDNS | Database-backed authoritative, API-driven automation | SQL/LDAP backends, REST API, separate recursor product | `powerdns-ops` |
| CoreDNS | Kubernetes and cloud-native service discovery | Plugin chain, Kubernetes integration, lightweight | `coredns-ops` |
| Unbound | Validating, caching recursive resolver | DNSSEC validation, small footprint, privacy features | `unbound-dns-ops` |
| Route 53 | AWS-hosted applications, global traffic management | Alias records, routing policies, health checks, DNS Firewall | `route53-dns-ops` |
| Azure DNS | Azure-hosted estates, private DNS zones | Public + private zones, Azure DNS Private Resolver | `azure-dns-ops` |
| Cloudflare DNS | Internet-facing authoritative, DDoS protection | Anycast (300+ PoPs), one-click DNSSEC, proxy mode | `cloudflare-dns-ops` |

Quick decision guide:
- AD-integrated internal DNS: Windows DNS.
- Flexible on-prem authoritative or recursive on Linux: BIND (recursive: Unbound for a dedicated validating resolver).
- API-driven, database-backed authoritative: PowerDNS.
- Service discovery inside Kubernetes: CoreDNS.
- Managed authoritative tied to a cloud: Route 53 (AWS), Azure DNS (Azure), Cloudflare (cloud-agnostic, internet-facing).

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| DNS fundamentals | Resolution flow (stub/recursive/iterative), record types (A/AAAA/CNAME/NS/SOA/MX/SRV/CAA/PTR and DNSSEC types), zone transfers (AXFR/IXFR/NOTIFY/TSIG), caching and TTL strategy, negative caching, split-horizon implementation | `references/concepts.md` |
| DNSSEC | Chain of trust, KSK/ZSK/CSK key types, DS records, validation process, algorithm recommendations, NSEC vs NSEC3, key rollover failure modes | `references/dnssec.md` |
| DNS security and encryption | DoH/DoT/DoQ transport comparison, RPZ (triggers and actions), DNS sinkholing, cloud DNS firewall, response rate limiting (RRL) | `references/dns-security-and-encryption.md` |
| Platform architecture | Cross-platform feature matrix, DNS architecture patterns (internal-only, split-horizon, hybrid cloud, multi-provider), DNS security layers by platform | `references/platform-architecture.md` |

## Vendor skills

For platform-specific implementation, configuration, and troubleshooting, route to the vendor skill. These ship across the DNS family PRs.

| Request pattern | Route to |
|---|---|
| AD-integrated zones, DNS policies and scopes, PowerShell DNS, aging/scavenging, Windows DoH | `windows-dns-ops` |
| named.conf, zone files, views, RPZ, KASP, catalog zones, BIND DoT | `bind-dns-ops` |
| PowerDNS authoritative, SQL/LDAP backends, REST API, PowerDNS Recursor | `powerdns-ops` |
| CoreDNS plugin chain, Kubernetes service discovery, Corefile | `coredns-ops` |
| Unbound validating resolver, forward zones, DNSSEC validation, privacy hardening | `unbound-dns-ops` |
| Route 53 hosted zones, routing policies (weighted/latency/geo/failover), health checks, DNS Firewall, Resolver endpoints | `route53-dns-ops` |
| Azure public/private DNS zones, Azure DNS Private Resolver, conditional forwarding | `azure-dns-ops` |
| Cloudflare DNS, proxy vs DNS-only mode, Foundation DNS, 1.1.1.1, secondary DNS | `cloudflare-dns-ops` |

## Cross-references

- `network-source-of-truth`: IPAM, DNS/DHCP source-of-truth, and reconciliation. Owns the record-of-intent for zones that this skill operates. Use it when DNS records are driven from a source-of-truth platform (InfraHub, Nautobot, NetBox).
- `multi-vendor-network-ops`: umbrella for mixed network operations. The production-change contract (assumptions, risk, evidence, pre-checks, execution, post-checks, rollback, escalation) applies to any production DNS change, especially DNSSEC key rollover and TTL changes.
- `bgp-analysis`: anycast DNS (Cloudflare, root/TLD operators, internal anycast resolvers) depends on BGP advertisement of the service prefix; use when diagnosing anycast DNS reachability or PoP selection.
- `smtp-deliverability`: SPF/DKIM/DMARC and MX record design from the mail-deliverability angle; this skill covers the DNS record mechanics, that skill covers the policy.
- `secrets-hygiene`: TSIG keys, DNSSEC private keys, cloud DNS API tokens, and dynamic-update credentials; never inline in scripts or commit to zone repositories.
- `utc-timestamps`: SOA serials (when using the YYYYMMDDnn convention), DNSSEC key timing (publish/activate/retire), and DNS query logs must be reasoned about in UTC.
- `oncall-runbooks`: DNS incident runbooks (DNSSEC rollover failure, resolver outage, zone-transfer break, cache poisoning response).

## Red flags

- **Open recursive resolver on the internet.** Never expose a recursive resolver without access controls; it becomes a DNS amplification weapon. Bind recursion to internal ACLs only.
- **DNSSEC without monitoring.** Key rollover failures and DS desynchronisation cause total zone unavailability, not graceful degradation. Monitor KSK/ZSK validity and parent DS records before and during every rollover.
- **Low TTL with no reason.** Low TTLs multiply query load on authoritative servers. Lower TTL only ahead of a planned change, then raise it again afterwards.
- **Split-horizon inconsistency.** Internal and external views must resolve shared services consistently. Mismatches produce intermittent, hard-to-diagnose failures.
- **Single DNS server per zone.** Always run at least two authoritative servers per zone. Single-server DNS is a critical single point of failure.
- **Stale records.** Enable aging/scavenging (Windows) or manage zone files and automation (BIND/PowerDNS) so retired hosts do not leave dangling records, including dangling CNAMEs that enable subdomain takeover.

## Bottom line

Classify the request as authoritative or recursive first, then as conceptual or platform-specific. For conceptual and design work, load the matching reference. For implementation, route to the vendor skill. Treat DNSSEC key rollover and TTL changes as change-controlled production operations under the `multi-vendor-network-ops` contract.
