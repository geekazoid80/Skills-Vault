---
name: cloudflare-dns-ops
description: "Use for Cloudflare DNS implementation, configuration, and operations: proxied (orange cloud) vs DNS-only (grey cloud) record modes, Anycast authoritative service, one-click DNSSEC with auto-managed keys, CNAME flattening at apex, Foundation DNS (Enterprise dedicated nameservers, three-group anycast, per-account DNSSEC rotation), secondary DNS (incoming/outgoing AXFR/IXFR), 1.1.1.1 public resolver (DoH/DoT/DoQ), DNS Firewall, page rules and redirect interaction with DNS, API v4 REST and Terraform management, Load Balancing health checks, DNS analytics via the Cloudflare DNS Analytics MCP server. References: architecture.md, analytics.md. Triggers include \"Cloudflare DNS\", \"proxied record\", \"orange cloud\", \"grey cloud\", \"DNS-only\", \"CNAME flattening\", \"Cloudflare DNSSEC\", \"Foundation DNS\", \"Cloudflare secondary DNS\", \"1.1.1.1\", \"Cloudflare DNS analytics\", \"Cloudflare API token\", \"Cloudflare zone\", \"cloudflare_record\", \"cloudflare provider\", \"DNS Firewall Cloudflare\", \"Cloudflare Load Balancing\", \"Cloudflare proxy mode\", \"Cloudflare zone transfer\", \"TSIG Cloudflare\", \"Cloudflare nameservers\", \"Cloudflare Anycast\", \"Cloudflare resolver\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops."
license: MIT
metadata:
  version: 1.0.0
---

# Cloudflare DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: cloudflare-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Cloudflare-specific DNS implementation and operations: zone setup, proxied vs DNS-only record decisions, DNSSEC enablement, Foundation DNS, secondary DNS configuration, 1.1.1.1 resolver integration, DNS Firewall, and API/Terraform management. The conceptual layer (DNS architecture, DNSSEC design, platform selection, cross-platform comparison) lives in `dns-network-ops`.

The single most important Cloudflare DNS concept is the proxy toggle: every A, AAAA, and CNAME record is either proxied (orange cloud, traffic flows through Cloudflare) or DNS-only (grey cloud, authoritative DNS only). Getting this classification right for each record drives every security, performance, and compatibility decision on the platform.

## When to use

- Setting up a Cloudflare zone: full setup (NS delegation), CNAME/partial setup, or secondary DNS.
- Deciding which records should be proxied (orange cloud) vs DNS-only (grey cloud).
- Enabling and verifying DNSSEC via the dashboard or API.
- Configuring Foundation DNS for Enterprise dedicated nameservers, three-group anycast, or per-account DNSSEC key rotation.
- Setting up secondary DNS: Cloudflare as secondary (incoming zone transfers from your primary), or Cloudflare as primary with outgoing transfers to a secondary.
- Configuring the 1.1.1.1 resolver: standard, Families filtering, DoH, DoT, or DoQ.
- Managing DNS Firewall to protect authoritative nameservers from DDoS.
- Writing Cloudflare DNS resources in Terraform (`cloudflare_record`, `cloudflare_zone_dnssec`).
- Querying zone and record data or pulling DNS analytics via the Cloudflare DNS Analytics MCP server.
- Troubleshooting Cloudflare DNS: proxied vs DNS-only mis-classification, DNSSEC DS mismatches, secondary DNS transfer failures, TTL surprises on proxied records.

## When not to use

- **DNS architecture, DNSSEC design, or cross-platform selection**: use `dns-network-ops`.
- **Broader Cloudflare platform (WAF, CDN, Zero Trust, Workers, R2, Pages)**: those are outside the scope of this DNS-focused skill; refer to Cloudflare platform documentation directly.
- **TSIG key or API token generation and secret handling**: apply `secrets-hygiene` alongside this skill.
- **AWS Route 53 or Azure DNS operations**: use `route53-dns-ops` or `azure-dns-ops` respectively.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and configuration | Anycast network, proxied vs DNS-only in depth, zone setup options (full/CNAME/secondary), CNAME flattening, DNSSEC (one-click, multi-signer RFC 8901, Foundation DNS per-account keys), Foundation DNS feature set, 1.1.1.1 resolver (standard and Families, encrypted transports), DNS Firewall, secondary DNS (AXFR/IXFR/TSIG, propagation SLAs), Load Balancing and health checks, page rules and redirect interaction, API v4 REST reference, Terraform provider resources, troubleshooting commands | `references/architecture.md` |
| DNS analytics | Zone and record listing, DNS query analytics, performance metrics, trend analysis via the Cloudflare DNS Analytics MCP server; tool reference (list_zones, get_zone, list_dns_records, get_dns_analytics, get_dns_performance, get_dns_trends); prerequisite environment variables; secrets-hygiene callout | `references/analytics.md` |

## Proxied vs DNS-only (the first classification)

Before configuring any record, decide the proxy mode. This affects reachability, security, and protocol compatibility.

| Mode | Visual | Traffic model | Suitable for | Not suitable for |
|---|---|---|---|---|
| Proxied | Orange cloud | Traffic routes through Cloudflare (WAF, CDN, DDoS, Workers) | A/AAAA/CNAME for HTTP/HTTPS services | MX, TXT, SRV, CAA, NS; non-HTTP traffic; records where origin IP must be returned |
| DNS-only | Grey cloud | Cloudflare serves authoritative DNS only; real IP returned | MX, TXT, SRV, CAA, NS; non-HTTP services; any record where WAF/CDN is not needed | None; this is the safe default when in doubt |

Key implications:
- Proxied records report TTL 300 regardless of the configured value. Custom TTLs only take effect on DNS-only records (minimum 60 s; 1 s for proxied is the platform minimum but overridden to 300 while proxied).
- Any DNS-only A or AAAA record exposes the origin IP. If an attacker discovers this IP, they can bypass Cloudflare proxy entirely. Audit all records for unintended origin leakage.
- CNAME flattening applies at the zone apex automatically: Cloudflare resolves the CNAME chain and returns A/AAAA records, solving the apex CNAME problem without Alias record support from the registrar.

## Zone setup options

| Setup | How | Plan requirement |
|---|---|---|
| Full (primary) | Change NS records at registrar to Cloudflare nameservers | All plans |
| CNAME / partial | Keep existing authoritative DNS; point specific subdomains via CNAME to `cdn.cloudflare.net` | Business / Enterprise |
| Secondary (incoming) | Cloudflare receives AXFR/IXFR from your primary; TSIG recommended | Enterprise |
| Primary with outgoing | Cloudflare is primary; sends zone transfers to external secondaries | Enterprise |

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC design, cross-platform selection, zone transfer concepts, and the broader DNS family skill set. Route architecture and design decisions there before choosing Cloudflare.
- `multi-vendor-network-ops`: production-change contract (assumptions, pre-checks, execution, post-checks, rollback). Apply to every DNSSEC enablement, proxy-mode toggle on a live service, and NS delegation cutover.
- `secrets-hygiene`: the Cloudflare API token (Zone:Read scope for analytics; Zone:DNS:Edit for record management) is a credential and must never be inlined in scripts, committed to repositories, or logged. Rotate on suspected exposure.
- `utc-timestamps`: DNS query analytics timestamps, DNSSEC key validity windows, and zone transfer logs must be reasoned in UTC.
- `systematic-debugging`: structured fault-isolation for Cloudflare DNS issues (DS mismatch, proxied vs DNS-only mis-classification, secondary zone transfer failure, TTL confusion).
- `bgp-analysis`: Cloudflare's Anycast infrastructure relies on BGP advertisement of the service prefix; use when diagnosing PoP selection or Anycast reachability at network layer.

## Red flags

- **Proxied record on a mail host.** Enabling the proxy on an MX-pointed hostname (e.g. `mail.example.com`) routes SMTP through HTTP-only proxy infrastructure. Mail delivery fails silently. MX targets and SMTP hosts must always be DNS-only.
- **Orange cloud on non-HTTP traffic.** Proxy mode only supports HTTP (port 80), HTTPS (port 443), and a limited set of alternative HTTP ports. SRV records, raw TCP/UDP services, and custom ports require DNS-only mode.
- **Origin IP leaked via a DNS-only A record.** If any A or AAAA record returns the real origin IP (intentionally or by accident), the DDoS protection and WAF of the proxied records can be bypassed by attacking the origin directly. Audit all grey-cloud records.
- **DNSSEC DS mismatch.** After enabling DNSSEC, the DS record at the parent registrar must match the value displayed by Cloudflare. A mismatch causes SERVFAIL for all validating resolvers. Verify with `dig DS example.com @8.8.8.8` before considering the rollout complete.
- **Secondary DNS without TSIG.** Zone transfers without TSIG authentication allow any host to request a copy of your zone. Always configure TSIG on both primary and Cloudflare secondary.
- **Multi-signer DNSSEC cleanup omitted.** After converting from pre-signed DNSSEC to Cloudflare-managed DNSSEC, leaving pre-signed mode active on the primary causes REFUSED responses from Cloudflare nameservers. Disable pre-signed mode on the primary after migration.
- **Expecting custom TTL on proxied records.** The platform overrides TTL to 300 for all proxied records. If downstream caches or monitoring depend on a specific TTL, switch to DNS-only or accept the 300 s floor.
- **API token scope too broad.** Cloudflare API tokens are scoped by zone and permission. Use Zone:Read for analytics; Zone:DNS:Edit for record management; never use a global API key in automation.

## Bottom line

Classify each DNS record as proxied (orange cloud) or DNS-only (grey cloud) before any other configuration decision. Load `references/architecture.md` for detailed zone setup, DNSSEC configuration, Foundation DNS, secondary DNS, and API/Terraform reference. Load `references/analytics.md` for DNS Analytics MCP server operations. Route architecture and design to `dns-network-ops`. Treat every NS delegation cutover, DNSSEC enablement, and proxy-mode change on a live service as a change-controlled production operation under the `multi-vendor-network-ops` contract.
