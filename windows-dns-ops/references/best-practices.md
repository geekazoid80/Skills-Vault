# Windows DNS best practices

## Resilience

- Run at minimum **two DNS-enabled DCs per AD site**. A single DNS server is a critical point of failure for all AD-dependent authentication, Group Policy, and name resolution. Clients configured with a single DNS server lose all AD-dependent services if that server is unavailable.
- Configure clients (via DHCP or Group Policy) with a **site-local DC as the primary DNS server** and a secondary DC at the same or an adjacent site. Sending all queries to a remote DNS server adds latency and creates a WAN dependency.
- Use **AD-integrated zones** wherever the DNS server runs on a DC. AD-integrated zones replicate zone data automatically via AD replication topology; there is no single primary to protect. File-based primary zones on a single server are a single point of failure for zone write access.
- For zones that need a non-Windows secondary (for a partner or internet-facing zone), ensure the secondary configuration includes TSIG authentication and ACL restrictions on zone-transfer requests.

## Forwarder design

- Use **conditional forwarders for specific namespaces**: partner domains, Azure private-link zones, AWS Route 53 private hosted zones, and any internal namespace not resolved by the local AD DNS.
- Use **global forwarders for internet resolution**: route non-local queries to a pair of reliable public resolvers (your ISP's, or a reputable public service). Always enable `UseRootHint $True` as a fallback so a forwarder outage does not prevent all internet resolution.
- Set an appropriate **forwarder timeout** (default 3 seconds). If a forwarder is unresponsive, the DNS server waits the full timeout before trying the next forwarder or falling back to root hints.
- For hybrid environments: **forward Azure Private Link zones** (`privatelink.*.windows.net`, `privatelink.*.azure.com`, etc.) to Azure DNS Private Resolver inbound endpoints (not to 168.63.129.16, which is only reachable from within Azure VNets).
- **AD-replicate conditional forwarders** by using `-ReplicationScope "Forest"` or `"Domain"`. Without a replication scope, each DNS server must be configured manually; any new DC added to DNS will not have the forwarder until explicitly configured.

```powershell
# Internet forwarders with root-hints fallback
Set-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4" -UseRootHint $True

# Azure Private Link forwarding (AD-replicated across the forest)
Add-DnsServerConditionalForwarderZone `
    -Name "privatelink.database.windows.net" `
    -MasterServers "10.0.0.4","10.0.0.5" `
    -ReplicationScope "Forest"
```

## Secure dynamic updates

- Always set AD-integrated zones to **"Secure only" dynamic updates**. This ensures only authenticated domain members (using GSS-TSIG / Kerberos) can register or modify records. Unauthenticated computers cannot forge entries for other hosts.
- For DHCP-registered records, use a **dedicated DHCP service account** (not the built-in DHCP server or "DnsUpdateProxy" group for new deployments). Configure the DHCP server with this account so records are owned by a consistent principal and not orphaned when a client is decommissioned.
- Audit ownership of dynamic records periodically. Records owned by a decommissioned machine account can only be updated by domain admins or via a `dnscmd /RecordDelete` operation.

## Scavenging configuration

- Set the **scavenging interval equal to the DHCP lease duration plus one day**. This ensures a client whose lease has expired (and therefore whose record has not been refreshed) is eligible for deletion before a new client claims the same IP, while active clients still have time to refresh.
- Enable scavenging at **both the server level and each zone**: `Set-DnsServerScavenging` enables the server-level cycle; `Set-DnsServerZoneAging` enables it per zone. Either alone is insufficient; scavenging runs only when both are active.
- **Do not enable scavenging on zones with purely static records** unless you understand the risk. Zones that contain only manually-created records (timestamp = 0) are safe by default because static records are exempt; but if `dnscmd /ageallrecords` has been run, or if any records have been set with explicit timestamps, those records become eligible.
- **Designate one server per zone as the scavenging server**. In AD-integrated zones, only one server runs scavenging for a given zone at a time (determined internally). Verify which server is performing scavenging via event ID 2501/2502 in the DNS Server event log.
- Treat **`dnscmd /ageallrecords`** as a dangerous operation. It sets the current timestamp on all records in the zone, including manually-created static records that would otherwise be exempt. Use only when deliberately migrating a zone from file-based to AD-integrated and wanting to seed aging timestamps, and only after a full review of every record in the zone.

```powershell
# Server-level: enable scavenging every 7 days
Set-DnsServerScavenging -ScavengingState $True -ScavengingInterval 7.00:00:00

# Zone-level: enable aging with default 7-day intervals
Set-DnsServerZoneAging -ZoneName "contoso.com" -Aging $True `
    -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00

# Verify both levels
Get-DnsServerScavenging
Get-DnsServerZoneAging -ZoneName "contoso.com"
```

## DNSSEC operational guidance

- Use **ECDSAP256/SHA-256** for new zone signings. It is the most widely supported modern algorithm and produces smaller signatures than RSA equivalents.
- Enable **NSEC3** with a random salt to prevent zone enumeration (zone walking). Avoid NSEC unless a specific validator is known to not support NSEC3.
- **Distribute trust anchors** to all validating resolvers in the forest. For AD-integrated signed zones, trust anchors replicate automatically. For file-based zones or external trust anchors, use `Add-DnsServerTrustAnchor`.
- **Monitor KSK rollover events** and DS record synchronisation at the parent zone. KSK rollover requires a manual update of the DS record at the parent; there is no automated notification mechanism in Windows DNS. Schedule a calendar reminder for each KSK rollover.
- Consider **hardware KSP (TPM or HSM)** for KSK storage in high-security environments where private key exfiltration is a concern.
- For DNSSEC key material, apply `secrets-hygiene`: private keys must never be exported to scripts, checked into version control, or stored in plaintext.

```powershell
# Sign a zone with ECDSAP256 and NSEC3 (default settings)
Invoke-DnsServerZoneSign -ZoneName "example.com" -SignWithDefault -Force

# Review current DNSSEC settings
Get-DnsServerDnsSecZoneSetting -ZoneName "example.com"

# View trust anchors (to confirm distribution)
Get-DnsServerTrustAnchor -ZoneName "example.com"
```

## Split-brain DNS via DNS policies

- Use DNS policies (Server 2016 and later) rather than running separate internal and external DNS servers where possible. Zone scopes let the same zone return different records to different client groups from a single server.
- **Always use `-ProcessingOrder`** when creating query resolution policies to ensure deterministic evaluation. Lower numbers are evaluated first.
- DNS policies are **PowerShell-only**: if other administrators use DNS Manager (GUI) to manage the server, document all policies explicitly; they will be invisible in the GUI and could be accidentally countered by GUI-based zone changes.
- After creating policies, **verify with `Resolve-DnsName`** from both an internal and external client (or simulate with `Resolve-DnsName -Server <ip> -Name <fqdn>` from a machine in each subnet).

## Monitoring and diagnostics

- In production, monitor **DNS event IDs 4000-4019** in the DNS Server event log. Events 4000, 4007, and 4015 indicate AD connectivity problems that affect zone availability.
- Use **`Get-DnsServerStatistics`** to baseline query rates, cache hit ratios, and recursion counts. Deviations indicate load changes, misconfiguration, or DNS abuse.
- Enable **debug logging selectively** in production (logging all queries on a busy server can produce gigabytes of log data quickly). Prefer targeted logging: enable queries and answers logging for a specific investigation, then disable when done.

```powershell
# Targeted debug logging for troubleshooting
Set-DnsServerDiagnostics -Queries $True -Answers $True `
    -SendPackets $True -ReceivePackets $True

# Full debug logging (lab or short-term production investigation)
Set-DnsServerDiagnostics -All $True -LogFilePath "C:\DNS_Debug.log" -MaxMBFileSize 500

# Disable all debug logging when done
Set-DnsServerDiagnostics -All $False
```

## Security hardening

- **Restrict zone transfers**: use ACLs and TSIG keys. For AD-integrated zones, zone transfers to non-DC servers should be restricted by zone ACL or disabled if no secondaries are required.
- **Disable recursion for untrusted clients** using a DNS recursion scope policy. Internal clients should be the only hosts able to use the server as a resolver.
- **Use PowerShell consistently** rather than mixing `dnscmd` and PowerShell. DNS policies created with PowerShell are invisible to `dnscmd`; mixing tools creates inconsistent state that is hard to audit.
- **Audit the forwarder chain** periodically. Forwarders pointing to stale IP addresses (retired resolvers, decommissioned partner DNS servers) cause silent resolution failures for specific namespaces.
- **Integrate DNS event logs with your SIEM** (Graylog, Splunk, or equivalent). DNS query logs are a high-value signal for detecting data exfiltration via DNS tunnelling, C2 beaconing, and malware C2 domain lookups.

## Upgrade and migration guidance

- **From file-based primary to AD-integrated**: change the zone type in DNS Manager or via `ConvertTo-DnsServerPrimaryZone -ReplicationScope "Domain"`. After conversion, run `Set-DnsServerZoneAging` to enable aging; consider `dnscmd /ageallrecords` only if migrating from a long-standing file-based zone with many static records that need aging timestamps set.
- **From Server 2019 to Server 2022/2025**: DNS zones replicate automatically after DC promotion. DNS Policies, scavenging settings, DNSSEC configuration, and forwarders carry forward. Server-side DoH (2025) is opt-in and requires KB5075899; it does not activate automatically on upgrade.
- **Multi-DC upgrades**: upgrade DCs in a rolling fashion. DNS continues to function from remaining DCs during each upgrade window. Verify replication health with `repadmin /replsummary` and `dcdiag /test:dns` after each DC is promoted at the new OS level.
