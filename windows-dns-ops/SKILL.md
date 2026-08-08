---
name: windows-dns-ops
description: "Use for Windows Server DNS implementation, configuration, and troubleshooting: AD-integrated zones, replication scopes (ForestDnsZones, DomainDnsZones), zone types (primary/secondary/stub), conditional forwarders, global forwarders, DNS policies and zone scopes (split-horizon, geo-routing, sinkholing), PowerShell DNS module (Add-DnsServerPrimaryZone, Add-DnsServerConditionalForwarderZone, Get-DnsServerResourceRecord, Add-DnsServerQueryResolutionPolicy, Set-DnsServerScavenging, Invoke-DnsServerZoneSign), secure dynamic updates (GSS-TSIG, AD authenticated), aging and scavenging, DNSSEC on Windows (KSK/ZSK, Key Master, NSEC3), and Windows DoH (client-side DoH on Server 2022, server-side DoH public preview on Server 2025). References: architecture.md, best-practices.md. Triggers include: Windows DNS, AD-integrated zones, DNS policies, zone scopes, Add-DnsServerPrimaryZone, Add-DnsServerSecondaryZone, Add-DnsServerStubZone, Add-DnsServerConditionalForwarderZone, Add-DnsServerClientSubnet, Add-DnsServerZoneScope, Add-DnsServerQueryResolutionPolicy, Get-DnsServerResourceRecord, Set-DnsServerForwarder, Set-DnsServerScavenging, Set-DnsServerZoneAging, Invoke-DnsServerZoneSign, Get-DnsServerDnsSecZoneSetting, Get-DnsServerTrustAnchor, Set-DnsServerDiagnostics, DnsServer module, DnsServer PowerShell, dnscmd, secure dynamic update, GSS-TSIG, aging, scavenging, conditional forwarder, global forwarder, ForestDnsZones, DomainDnsZones, DNS replication scope, Key Master DNS, Windows Server 2022 DNS, Windows Server 2025 DNS, Windows DoH, DoH server preview, DNS over HTTPS Windows, zone scope, split-brain Windows DNS, DNS sinkholing Windows, geo-routing DNS. For DNS architecture design, DNSSEC design, cross-platform comparison, and conceptual DNS topics see dns-network-ops. Active Directory domain-services design beyond DNS is out of scope."
license: MIT
metadata:
  version: 1.0.0
---

# Windows DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: windows-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Windows Server DNS implementation: configuring zones, forwarders, DNS policies, aging/scavenging, DNSSEC, and PowerShell automation. It handles the Windows DNS Server role across Server 2016 through Server 2025. Architecture decisions, cross-platform comparisons, and conceptual DNS topics belong in `dns-network-ops`.

## When to use

- Creating or managing AD-integrated zones, secondary zones, stub zones, conditional forwarders, or reverse lookup zones on Windows DNS Server.
- Configuring DNS policies and zone scopes for split-horizon DNS, geo-location routing, DNS sinkholing, or recursion control.
- Setting up or troubleshooting secure dynamic updates and DHCP registration in AD environments.
- Configuring aging/scavenging to remove stale dynamically-registered records.
- Signing zones with DNSSEC, managing key rollovers, or distributing trust anchors on Windows.
- Automating DNS management with the DnsServer PowerShell module.
- Diagnosing DNS resolution failures via Windows event IDs, debug logging, or `Get-DnsServerStatistics`.
- Configuring client-side DoH (Server 2022) or the server-side DoH public preview (Server 2025).
- Forwarding queries to hybrid cloud DNS (Azure DNS Private Resolver, AWS Route 53 Resolver endpoints).

## When not to use

- **DNS architecture design, platform selection, or cross-platform comparison**: use `dns-network-ops`.
- **DNSSEC chain-of-trust design, key-type rationale, or NSEC vs NSEC3 decisions**: use `dns-network-ops`.
- **BIND, PowerDNS, CoreDNS, Unbound, Route 53, Azure DNS, or Cloudflare**: use the matching vendor skill.
- **IPAM, DNS/DHCP source-of-truth, or zone record reconciliation against an authoritative inventory**: use `network-source-of-truth`.
- **Active Directory domain-services design** (site topology, DC placement, forest/domain structure, trust relationships): out of scope. DNS on DCs is in scope; AD DS design is not.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | AD-integrated zones, replication scopes, zone types, DNS policies and zone scopes, DNSSEC on Windows (KSK/ZSK, Key Master, NSEC3), aging/scavenging internals, PowerShell cmdlet reference, version notes (Server 2022 / 2025 including DoH) | `references/architecture.md` |
| Best practices | Forwarder design (conditional + global), split-brain via policies, secure dynamic updates, scavenging configuration, DNSSEC operational guidance, resilience, monitoring, security hardening | `references/best-practices.md` |

## Quick Windows DNS classification

Before diving into configuration, answer two questions:

1. **Is the DNS server a Domain Controller?** If yes, use AD-integrated zones (not file-based primary). AD-integrated zones give multi-master updates, automatic replication, secure-only dynamic updates, and encrypted zone storage. File-based primary zones are for standalone servers or Windows DNS acting as a secondary to a non-Windows primary.

2. **Do internal and external clients need different answers for the same name?** If yes, use DNS policies with zone scopes (Server 2016 and later; PowerShell only). This is Windows' mechanism for split-horizon DNS. BIND uses views; Windows uses zone scopes under a policy.

## Key PowerShell cmdlets (summary)

```powershell
# Zone creation
Add-DnsServerPrimaryZone -Name "example.com" -ReplicationScope "Forest"
Add-DnsServerSecondaryZone -Name "partner.com" -ZoneFile "partner.com.dns" -MasterServers 10.1.1.53
Add-DnsServerConditionalForwarderZone -Name "cloud.internal" -MasterServers "10.0.0.4" -ReplicationScope "Forest"

# Record management
Add-DnsServerResourceRecord -ZoneName "example.com" -A -Name "www" -IPv4Address "10.0.0.10"
Get-DnsServerResourceRecord -ZoneName "example.com" -RRType "A"

# Forwarders
Set-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4" -UseRootHint $True

# DNS policies (split-horizon)
Add-DnsServerClientSubnet -Name "InternalSubnet" -IPv4Subnet "10.0.0.0/8"
Add-DnsServerZoneScope -ZoneName "example.com" -Name "InternalScope"
Add-DnsServerQueryResolutionPolicy -Name "InternalPolicy" -Action ALLOW `
    -ClientSubnet "eq,InternalSubnet" -ZoneScope "InternalScope,1" `
    -ZoneName "example.com" -ProcessingOrder 1

# Scavenging
Set-DnsServerScavenging -ScavengingState $True -ScavengingInterval 7.00:00:00
Set-DnsServerZoneAging -ZoneName "example.com" -Aging $True

# DNSSEC
Invoke-DnsServerZoneSign -ZoneName "example.com" -SignWithDefault -Force
Get-DnsServerDnsSecZoneSetting -ZoneName "example.com"

# Diagnostics
Get-DnsServerStatistics
Set-DnsServerDiagnostics -Queries $True -Answers $True
```

## Key event IDs

| Event ID | Description |
|---|---|
| 4000 | Cannot open Active Directory; zone data unavailable |
| 4007 | Cannot find AD; AD-integrated zones disabled |
| 4013 | Waiting for AD DS initialisation |
| 4015 | Critical error from Active Directory |
| 1014 (DNS Client) | Name resolution timed out |

## Cross-references

- `dns-network-ops`: DNS architecture, cross-platform comparison, DNSSEC design, record types, zone-transfer mechanics, TTL strategy; the conceptual foundation for all work done in this skill.
- `multi-vendor-network-ops`: production-change contract (assumptions, risk, evidence, pre-checks, execution, post-checks, rollback, escalation) applies to any production DNS change, especially DNSSEC key rollover and scavenging activation.
- `secrets-hygiene`: DNSSEC private keys, TSIG keys, and cloud DNS API tokens; never inline in scripts or committed to source control.
- `utc-timestamps`: SOA serial conventions (YYYYMMDDnn) and DNSSEC key timing must be reasoned in UTC.
- `oncall-runbooks`: DNS incident runbooks (DNSSEC rollover failure, scavenging accidentally deleting live records, AD replication break affecting zone data).
- `systematic-debugging`: structured fault-isolation approach when DNS resolution failures span multiple layers (client NRPT, DNS server policy, AD replication, forwarder chain).
- `network-source-of-truth`: IPAM and DNS record-of-intent; use when DNS records are driven from a source-of-truth platform (NetBox, Nautobot, InfraHub).

## Red flags

- **Scavenging enabled at zone level but not server level (or vice versa).** Scavenging is silently inactive unless enabled at both the server and each zone. Always verify both with `Get-DnsServerScavenging` and `Get-DnsServerZoneAging`.
- **Scavenging interval shorter than the DHCP lease duration.** Records are deleted before leased clients can refresh them. Set: scavenging period = DHCP lease duration + 1 day.
- **DNS policies configured but invisible to non-PowerShell admins.** DNS policies do not appear in DNS Manager (GUI). A policy can silently redirect or block queries with no indication to an admin using only the GUI.
- **Conditional forwarder not AD-replicated.** Without `-ReplicationScope`, conditional forwarders must be configured manually on every DNS server. AD-replicating the forwarder ensures consistency across all DCs.
- **DNSSEC KSK rollover without updating the DS record at the parent zone.** The DS update is manual; failing it causes DNSSEC validation failures for all resolvers that validate the zone.
- **`dnscmd /ageallrecords` run on live zones without review.** This makes all records (including manually created static records, normally exempt) eligible for scavenging. Stale-looking static records can be deleted.
- **Single DNS server per AD site.** A single DNS server is a critical point of failure for all AD-dependent authentication and name resolution. Run at minimum two DNS-enabled DCs per site.

## Bottom line

Classify first: is the server AD-joined, and do you need split-horizon? Those two answers determine zone storage (AD-integrated vs file-based) and policy configuration. Use the DnsServer PowerShell module for all new automation; avoid mixing `dnscmd` and PowerShell. Treat DNSSEC key rollover, scavenging activation, and DNS policy changes as production operations under the `multi-vendor-network-ops` change contract.
