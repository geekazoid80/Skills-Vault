---
name: azure-dns-ops
description: "Use for Azure DNS operations: public DNS zones (anycast nameservers, record types, zone delegation), private DNS zones, virtual-network links, autoregistration, Azure DNS Private Resolver (inbound endpoints, outbound endpoints, DNS forwarding rulesets, hybrid DNS flows), Alias records (zone apex, auto-updating Azure resource targets), DNSSEC on public zones (auto-managed key rotation), conditional forwarding from Azure to on-premises, Azure Firewall DNS proxy (FQDN rules, DNS logging), Traffic Manager DNS-based routing, RBAC for DNS resources, IaC (Terraform azurerm_dns_zone, azurerm_private_dns_zone, azurerm_private_dns_resolver; Bicep/ARM), and CLI (az network dns, az network private-dns, az dns-resolver). References: architecture.md, diagnostics.md. Triggers include \"Azure DNS\", \"Azure public DNS zone\", \"Azure private DNS zone\", \"private DNS zone\", \"virtual network link\", \"autoregistration\", \"Azure DNS Private Resolver\", \"Private Resolver inbound endpoint\", \"Private Resolver outbound endpoint\", \"DNS forwarding ruleset\", \"az network dns\", \"az network private-dns\", \"az dns-resolver\", \"Azure DNS Alias record\", \"zone apex alias\", \"Azure DNSSEC\", \"conditional forwarding Azure\", \"Azure Firewall DNS proxy\", \"Traffic Manager DNS\", \"privatelink DNS zone\", \"hybrid DNS Azure\", \"azurerm_dns_zone\", \"azurerm_private_dns_zone\", \"azurerm_private_dns_resolver\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops; for broader Azure platform operations see azure-cloud-ops."
license: MIT
metadata:
  version: 1.0.0
---

# Azure DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: azure-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Azure DNS implementation: public and private zone management, virtual-network links, autoregistration, the Azure DNS Private Resolver for hybrid DNS flows, Alias records at the zone apex, DNSSEC on public zones, Azure Firewall DNS proxy, Traffic Manager DNS routing, and IaC/CLI automation. The conceptual layer (resolution flow, DNSSEC design, cross-platform selection, hybrid DNS patterns) lives in `dns-network-ops`.

## When to use

- Creating or managing Azure public DNS zones: record sets, delegation, DNSSEC signing, Alias records at the zone apex.
- Creating or managing Azure private DNS zones: VNet links, autoregistration, private endpoint DNS integration.
- Designing or troubleshooting Azure DNS Private Resolver: inbound/outbound endpoints, DNS forwarding rulesets, hub-spoke hybrid DNS.
- Configuring conditional forwarding from Azure VMs to on-premises DNS (Active Directory, corporate domains).
- Setting up Azure Firewall DNS proxy for FQDN-based network or application rules.
- Configuring Traffic Manager profiles and routing methods (priority, weighted, performance, geographic, subnet, multivalue).
- Writing Terraform, Bicep, or ARM templates for any of the above.
- Using `az network dns`, `az network private-dns`, or `az dns-resolver` CLI commands.
- Troubleshooting DNS resolution failures in Azure (private endpoint not resolving, hybrid forwarding break, DNSSEC DS mismatch).

## When not to use

- **DNS architecture, DNSSEC design, or cross-platform selection**: use `dns-network-ops`.
- **Broader Azure platform operations** (compute, networking, IAM, cost management unrelated to DNS): use `azure-cloud-ops`.
- **Multi-vendor network operations** covering mixed on-prem/cloud environments: use `multi-vendor-network-ops`.
- **BIND, PowerDNS, Windows DNS, CoreDNS, or Unbound implementation**: use the respective vendor skill.
- **Route 53 or Cloudflare DNS**: use `route53-dns-ops` or `cloudflare-dns-ops`.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and configuration | Public zone infrastructure (anycast, record types, delegation); Alias records; DNSSEC (auto-managed, DS at registrar); private zones (VNet links, autoregistration, private endpoint DNS); Azure DNS Private Resolver (inbound/outbound endpoints, forwarding ruleset, hybrid patterns); Traffic Manager routing methods; Azure Firewall DNS proxy; Terraform/Bicep/ARM resources; az CLI | `references/architecture.md` |
| Diagnostics and troubleshooting | Diagnosing resolution failures (nslookup, dig, Test-DnsNameResolution); private endpoint DNS not returning private IP; Private Resolver endpoint connectivity; forwarding ruleset not matching; DNSSEC DS sync failures; Traffic Manager health probe failures; Azure Firewall DNS proxy not resolving FQDNs; NSG/subnet checks; Azure Monitor DNS metrics | `references/diagnostics.md` |

## Classify first

Before designing or troubleshooting, identify the zone type and the resolution direction:

| Zone type | Publicly resolvable | Record scope | DNSSEC |
|---|---|---|---|
| Public DNS zone | Yes | Internet-facing | Supported (auto-managed) |
| Private DNS zone | No | VNet-linked only | Not supported |

Resolution direction for hybrid:
- **On-prem to Azure** (resolving private endpoints): configure on-prem conditional forwarder to the Private Resolver inbound endpoint IP.
- **Azure to on-prem** (resolving AD, corporate domains): configure outbound endpoint plus DNS forwarding ruleset rule pointing at on-prem DNS servers.

## Core concepts

### Alias records

Azure Alias records are an Azure-specific DNS extension that allows an A, AAAA, or CNAME record set to reference an Azure resource directly. Key properties: zone apex support (solves the CNAME-at-apex restriction), auto-updating (IP changes on the target resource propagate without record edits), and free queries to Azure resource targets. Supported targets: Azure Public IP, Traffic Manager, CDN, Front Door, and other record sets in the same zone.

### Azure DNS Private Resolver

The Private Resolver is a managed DNS proxy inside a VNet. It replaces the older pattern of running IaaS DNS VMs. Two endpoint types:
- **Inbound endpoint**: assigns a private IP in your VNet; on-prem DNS conditionally forwards zones to this IP; the resolver uses Azure Private DNS zones linked to the VNet to answer.
- **Outbound endpoint**: associated with a DNS forwarding ruleset; forwards matching queries from Azure VMs to external (typically on-prem) DNS servers.

Endpoint subnets must be dedicated (minimum /28) and must not host other resources.

### Private endpoint DNS

Azure services with private endpoints use a `privatelink` subdomain CNAME chain. The CNAME (`mydb.privatelink.database.windows.net`) must resolve inside the VNet using a private DNS zone of the same name linked to the VNet. Without the linked private zone the public IP is returned, defeating the private endpoint. See `references/architecture.md` for the full zone-name table.

### DNSSEC (public zones only)

Azure DNS manages key generation, rotation, and signing automatically. The operator's only responsibility is to publish the DS record at the parent domain registrar after enabling DNSSEC. Forgetting the DS record causes DNSSEC validation failure for all resolvers that perform validation.

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC design (KSK/ZSK/CSK, chain of trust, NSEC vs NSEC3), cross-platform selection, hybrid DNS patterns, and the broader DNS family skill set.
- `azure-cloud-ops`: broader Azure platform operations (subscription, IAM, networking, cost management) that accompany DNS configuration.
- `multi-vendor-network-ops`: production-change contract (assumptions, pre-checks, execution, post-checks, rollback). Apply to every DNS zone delegation change, DNSSEC enablement, and Private Resolver deployment.
- `secrets-hygiene`: Azure DNS API tokens, service principal credentials, and any pre-shared keys used with on-prem DNS forwarding; never inline in scripts or IaC committed to repositories.
- `utc-timestamps`: DNS query logs, Traffic Manager probe logs, and DNSSEC key event logs must be reasoned in UTC.
- `systematic-debugging`: structured fault-isolation for complex Azure DNS failures (private endpoint not resolving, hybrid forwarding break, DNSSEC DS mismatch).
- `network-source-of-truth`: when DNS records are driven from a source-of-truth platform (InfraHub, Nautobot, NetBox), that skill owns the record-of-intent; this skill operates the resulting Azure DNS zones.

## Red flags

- **Private zone not linked to the VNet.** A private DNS zone is invisible to VMs in any VNet that has no link. VNet peering does NOT propagate DNS; each VNet needing resolution must have an explicit link.
- **Auto-registration enabled on more than one zone per VNet.** A VNet supports autoregistration for exactly one private DNS zone. Attempting a second auto-registration link fails.
- **Private Resolver endpoint subnet shared with other resources.** Inbound and outbound endpoint subnets must be dedicated. Placing other resources in these subnets causes deployment errors or unexpected routing behaviour.
- **DNSSEC enabled but DS record not published.** After enabling DNSSEC on a public zone the DS record must be manually added at the domain registrar. Without it, DNSSEC validation fails for all validating resolvers and the zone is effectively broken for DNSSEC-enforcing clients.
- **Traffic Manager TTL below 10 seconds.** Lower TTL increases failover speed but also increases DNS query volume significantly. Never set TTL below 10 s for Traffic Manager profiles.
- **Azure Firewall DNS proxy not enabled for FQDN rules.** FQDN-based network rules and application rules in Azure Firewall require DNS proxy to be enabled. Without it, FQDN resolution in rules fails silently.
- **Wrong privatelink zone name.** Each Azure service type has a specific `privatelink.*` zone name. Using an incorrect zone name means the CNAME chain resolves to the public IP instead of the private endpoint IP.
- **Forwarding ruleset not linked to the VNet.** A DNS forwarding ruleset attached to an outbound endpoint only applies to VNets explicitly linked to that ruleset. Unlinked VNets continue using Azure default DNS.

## Bottom line

Classify the zone type (public vs private) and the resolution direction (Azure-to-on-prem vs on-prem-to-Azure) before designing or troubleshooting. Load `references/architecture.md` for zone configuration, Private Resolver setup, Alias records, DNSSEC, Traffic Manager, Firewall DNS proxy, and IaC examples. Load `references/diagnostics.md` for CLI-driven troubleshooting, resolution failure diagnosis, and DNSSEC DS sync verification. Route architecture and design decisions to `dns-network-ops`. Treat zone delegation changes, DNSSEC enablement, and Private Resolver deployments as change-controlled operations under the `multi-vendor-network-ops` contract.
