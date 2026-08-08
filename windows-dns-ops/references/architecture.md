# Windows DNS architecture

## AD-integrated zones

When the DNS Server role runs on a Domain Controller, zones can be stored in Active Directory rather than flat zone files. AD-integrated zones provide:

- **Multi-master updates**: any DC running DNS can accept dynamic updates; there is no single primary to reach.
- **Automatic replication**: zone data travels via the AD replication topology, not DNS zone transfers.
- **Secure-only dynamic updates**: only authenticated domain computers (via GSS-TSIG) can register records.
- **Encrypted storage**: zone data is stored as AD DS objects, protected by AD access controls.
- **Fault tolerance**: zone data survives the loss of any individual DC because every DNS-enabled DC holds a full copy.

File-based primary zones remain valid for standalone Windows DNS servers, for zones that must be secondary to a non-Windows authoritative server, or when a zone must be transferred to a non-Windows secondary via AXFR/IXFR.

### Replication scopes

The replication scope controls which Domain Controllers receive zone data.

| Partition | Scope | Typical use |
|---|---|---|
| `ForestDnsZones` | All DCs in the forest running DNS | Cross-domain zones; `_msdcs.forest-root`; conditional forwarders shared across domains |
| `DomainDnsZones` | All DCs in the domain running DNS | Default for domain-local zones; forward and reverse lookup zones for the domain |
| Domain partition | All DCs in the domain (with or without DNS role) | Legacy Windows 2000 compatibility; avoid for new deployments |
| Custom application partition | Admin-defined subset of DCs | Selective replication when not all DNS servers should hold a zone |

```powershell
# Create a zone with Forest scope (shared across all domains in the forest)
Add-DnsServerPrimaryZone -Name "shared.example.com" -ReplicationScope "Forest"

# Change an existing zone's replication scope
Set-DnsServerPrimaryZone -Name "example.com" -ReplicationScope "Domain"
```

### Secure dynamic updates and GSS-TSIG

In AD-integrated zones, set dynamic updates to "Secure only". This restricts record registration to authenticated domain members using GSS-TSIG (Generic Security Services TSIG, built on Kerberos). Non-domain machines cannot register or modify records.

DHCP servers that register records on behalf of clients must be authorised in AD (added to the "DnsUpdateProxy" security group, or configured with a dedicated DHCP service account) to avoid ownership conflicts with client-registered records.

## Zone types

| Type | Storage | Use |
|---|---|---|
| Primary (AD-integrated) | AD DS objects | Standard for DC-hosted authoritative zones; preferred |
| Primary (file-based) | `.dns` zone file | Standalone server; source for non-Windows secondaries |
| Secondary | File only | Read-only replica via AXFR/IXFR from a non-Windows primary |
| Stub | AD or file | Holds SOA + NS + glue only; used for delegation discovery and conditional delegation |
| Conditional forwarder | AD or file | Forwards queries for a specific namespace to designated servers; stores no authoritative records |
| Reverse lookup | AD or file | PTR records in `in-addr.arpa` or `ip6.arpa` zones |

```powershell
Add-DnsServerPrimaryZone -Name "example.com" -ReplicationScope "Domain"
Add-DnsServerSecondaryZone -Name "partner.com" -ZoneFile "partner.com.dns" -MasterServers 10.1.1.53
Add-DnsServerStubZone -Name "remote.example.com" -MasterServers 10.2.0.53 -ReplicationScope "Forest"
Add-DnsServerConditionalForwarderZone -Name "cloud.internal" -MasterServers "10.0.0.4" -ReplicationScope "Forest"
```

## Forwarders

### Global forwarders

Global forwarders receive all queries that the DNS server cannot resolve locally (no local zone match, no cache hit). They replace or supplement root hints.

```powershell
Set-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4" -UseRootHint $True
```

`-UseRootHint $True` means: if all configured forwarders fail to respond, fall back to iterative resolution via root hints. Without this, a forwarder outage causes total resolution failure for non-local names.

### Conditional forwarders

Conditional forwarders send queries for a specific namespace to designated servers. They are essential for hybrid cloud DNS (routing private-link names to Azure DNS resolver endpoints, or routing AWS Route 53 private zone names to Route 53 resolver inbound endpoints).

```powershell
# Forward Azure Private Link names to Azure DNS Private Resolver
Add-DnsServerConditionalForwarderZone `
    -Name "privatelink.database.windows.net" `
    -MasterServers "10.0.0.4" `
    -ReplicationScope "Forest"

# Forward an AWS private hosted zone to Route 53 inbound resolver endpoint
Add-DnsServerConditionalForwarderZone `
    -Name "internal.aws.example.com" `
    -MasterServers "10.1.0.10","10.1.0.11" `
    -ReplicationScope "Forest"
```

Using `-ReplicationScope "Forest"` ensures the conditional forwarder is AD-replicated to all DNS servers in the forest, avoiding the need to configure each server manually.

## DNS policies and zone scopes (Server 2016 and later)

DNS policies allow query behaviour to be customised based on attributes of the incoming query: client subnet, query type, FQDN, time of day, transport protocol, or server interface IP. All DNS policy configuration is PowerShell-only; the DNS Manager GUI does not display or manage policies.

### Key objects

| Object | Purpose | Cmdlet prefix |
|---|---|---|
| Client subnet | Named group of IPv4/IPv6 subnets | `Add-DnsServerClientSubnet` |
| Zone scope | Separate instance of a zone with independent records | `Add-DnsServerZoneScope` |
| Recursion scope | Controls whether recursion is enabled for a client group | `Add-DnsServerRecursionScope` |
| Query resolution policy | Routes queries to a zone scope based on match criteria | `Add-DnsServerQueryResolutionPolicy` |
| Zone transfer policy | Restricts zone transfer targets by client subnet | `Add-DnsServerZoneTransferPolicy` |

### Split-horizon DNS via zone scopes

Zone scopes allow the same zone to hold different record sets for different client groups. Internal clients receive internal IP addresses; external clients (or a different subnet) receive different addresses or are denied resolution.

```powershell
# Define client subnets
Add-DnsServerClientSubnet -Name "InternalSubnet" -IPv4Subnet "10.0.0.0/8"

# Create a zone scope for internal records
Add-DnsServerZoneScope -ZoneName "contoso.com" -Name "InternalScope"

# Add an internal-only record to the internal scope
Add-DnsServerResourceRecord -ZoneName "contoso.com" -A -Name "app" `
    -IPv4Address "10.0.0.50" -ZoneScope "InternalScope"

# Internal clients get the InternalScope answer
Add-DnsServerQueryResolutionPolicy -Name "InternalPolicy" -Action ALLOW `
    -ClientSubnet "eq,InternalSubnet" -ZoneScope "InternalScope,1" `
    -ZoneName "contoso.com" -ProcessingOrder 1

# All other clients get the default zone scope (external record or NXDOMAIN)
Add-DnsServerQueryResolutionPolicy -Name "ExternalPolicy" -Action ALLOW `
    -ZoneScope "contoso.com,1" -ZoneName "contoso.com" -ProcessingOrder 2
```

### Other policy use cases

- **Geo-location routing**: different client subnets (by geography) receive different IP addresses from different zone scopes.
- **DNS sinkholing**: a policy with `-Action IGNORE` or a zone scope pointing to a sinkhole IP handles queries for malicious domains.
- **Recursion control**: a recursion scope with `AllowRecursion = $False` prevents external clients from using the server as an open resolver.
- **Time-of-day routing**: policies can match on `-TimeOfDay` to change resolution behaviour during maintenance windows.

## DNSSEC on Windows

Windows DNS supports DNSSEC signing on primary zones (both file-backed and AD-integrated). DNSSEC on Windows uses a designated Key Master server; for AD-integrated zones the Key Master signs the zone and distributes signing keys to other DCs via AD replication.

### Key types

| Key | Signs | Lifetime (default) | Rollover method |
|---|---|---|---|
| KSK (Key Signing Key) | DNSKEY RRset only | 755 days | Double-signature; DS record at parent must be updated manually |
| ZSK (Zone Signing Key) | All other record sets | 90 days | Prepublish method; fully automatic |

Recommended algorithm: ECDSAP256/SHA-256 with NSEC3 (prevents zone walking).

### Signing a zone

```powershell
# Sign with default settings (ECDSAP256, NSEC3)
Invoke-DnsServerZoneSign -ZoneName "example.com" -SignWithDefault -Force

# View signing settings
Get-DnsServerDnsSecZoneSetting -ZoneName "example.com"

# Configure NSEC3 parameters
Set-DnsServerDnsSecZoneSetting -ZoneName "example.com" `
    -NSec3RandomSaltLength 8 -NSec3Iterations 50

# View trust anchors
Get-DnsServerTrustAnchor -ZoneName "example.com"
```

### Trust anchors

For an AD-integrated signed zone, trust anchors (DNSKEY and DS records) are stored in the forest's DNS application partition and replicated to all DNS-enabled DCs automatically. Standalone servers store trust anchors in `TrustAnchors.dns`.

### KSK rollover (manual DS update required)

KSK rollover uses the double-signature method: the new KSK is published alongside the old one; both sign the DNSKEY RRset during the overlap period. The DS record at the parent zone must be updated manually to reference the new KSK. Failing to update the DS record causes DNSSEC validation failures for all resolvers that validate the zone.

## Aging and scavenging

Aging and scavenging remove stale dynamically-registered records from zones. Without scavenging, decommissioned hosts leave dangling A and PTR records indefinitely.

### How it works

Every dynamically-registered record receives a timestamp. The aging lifecycle has two intervals:

- **No-refresh interval** (default 7 days): during this window, timestamp refreshes are suppressed to reduce AD write traffic.
- **Refresh interval** (default 7 days): during this window, the record must be refreshed by the registering client. If not refreshed by the end of this interval, it becomes eligible for scavenging.

Total time before a record becomes eligible: no-refresh interval + refresh interval = 14 days by default.

Manually created records have a timestamp of 0 and are never eligible for scavenging unless `dnscmd /ageallrecords` is run (use with caution).

### Enabling scavenging

Scavenging must be enabled at both the server level and at each zone individually; either alone is insufficient.

```powershell
# Enable at server level and set the scavenging cycle
Set-DnsServerScavenging -ScavengingState $True -ScavengingInterval 7.00:00:00

# Enable at zone level
Set-DnsServerZoneAging -ZoneName "contoso.com" -Aging $True `
    -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00

# Verify
Get-DnsServerScavenging
Get-DnsServerZoneAging -ZoneName "contoso.com"
```

## Version notes (Server 2022 / 2025)

### Windows Server 2022

- **Client-side DoH**: Windows 11 and Server 2022 clients can resolve DNS over HTTPS using a configured DoH resolver. This is client-side only; the DNS Server role itself does not serve DoH in Server 2022.
- **DNSSEC key storage**: improved key storage provider support; better performance for signed zone operations.
- **Azure Arc integration**: hybrid monitoring of on-premises DNS servers via Azure Arc (requires outbound HTTPS connectivity to Azure Arc management endpoints).
- **DNS Policies**: all DNS policy features introduced in Server 2016 remain fully supported.
- **Not in 2022**: the DNS Server role does not listen on port 443 or serve DNS over HTTPS; that requires Server 2025.

### Windows Server 2025

- **Server-side DoH (public preview)**: the DNS Server role can receive DNS queries over HTTPS (port 443). Introduced via KB5075899 (February 2026 update). Disabled by default; requires opt-in registration for the public preview.
- **DoH configuration approach**:

```powershell
# General approach (exact cmdlets depend on KB5075899 update being installed):
# 1. Install KB5075899 on the DNS server.
# 2. Opt in to the public preview.
# 3. Bind a valid TLS certificate to the DNS service.
# 4. Enable the DoH endpoint via new DnsServer PowerShell cmdlets.
# 5. Clients point to: https://<dns-server-fqdn>/dns-query
```

- **Current DoH limitations**: upstream forwarder queries from the DNS server to external resolvers remain unencrypted on port 53 even with server-side DoH enabled. Encrypted upstream forwarding is planned for a future update.
- **Not recommended for production**: server-side DoH is in public preview; do not deploy in production environments until GA.
- **All 2022 and earlier features carry forward**: DNS policies, AD-integrated zones, DNSSEC, scavenging, and the full DnsServer PowerShell module are unchanged.
- **Firewall consideration**: enabling DoH requires TCP/443 inbound to the DNS server. If another HTTPS service (IIS, for example) already uses port 443 on the same server, there is a conflict to resolve before enabling the DoH endpoint.
