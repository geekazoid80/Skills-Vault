# Azure DNS diagnostics

## Resolution failure classification

Before running any diagnostic command, classify the failure type. This determines where to look first.

| Symptom | Likely cause | First check |
|---|---|---|
| Private endpoint returns public IP | Private DNS zone not linked to VNet, or wrong zone name | `az network private-dns zone list` + VNet link status |
| Azure VM cannot resolve on-prem domain | Outbound endpoint not set up, ruleset not linked to VNet, or rule domain mismatch | Forwarding ruleset + VNet link |
| On-prem cannot resolve Azure private endpoint | Inbound endpoint not reachable, or conditional forwarder misconfigured on on-prem side | NSG on inbound subnet + on-prem forwarder config |
| DNSSEC validation failure | DS record not published at parent registrar after DNSSEC was enabled | Retrieve DS record via CLI, verify at registrar |
| Traffic Manager failover not working | Health probe failure, TTL too high, or endpoint disabled | Traffic Manager endpoint health in portal/CLI |
| FQDN rules in Azure Firewall not matching | DNS proxy not enabled on the firewall | Check `az network firewall show` DNS proxy status |
| Record not found in private zone | VNet not linked, record not created, or wrong zone suffix | List VNet links + list record sets |

## Diagnostic tools

### nslookup (cross-platform quick check)

```bash
# Query Azure public DNS directly
nslookup example.com ns1-01.azure-dns.com

# Check private zone from within a VNet (using Azure DNS wire server)
nslookup myapp.internal.example.com 168.63.129.16

# Check private endpoint resolution
nslookup mydb.database.windows.net
# Expected: CNAME to mydb.privatelink.database.windows.net, then private IP

# Check Traffic Manager profile
nslookup myapp.trafficmanager.net
```

### dig (Linux/Mac, detailed query)

```bash
# Query a specific Azure nameserver
dig @ns1-01.azure-dns.com example.com A

# Check DNSSEC chain (public zone)
dig +dnssec +multi example.com A
dig @ns1-01.azure-dns.com example.com DNSKEY
dig @ns1-01.azure-dns.com example.com DS

# Check from inside a VNet via Azure DNS wire server
dig @168.63.129.16 myapp.internal.example.com

# Check private endpoint CNAME chain
dig @168.63.129.16 mydb.database.windows.net +trace

# Check Traffic Manager
dig myapp.trafficmanager.net
```

### PowerShell (Windows, Azure VMs)

```powershell
# Resolve from within an Azure VM
Resolve-DnsName myapp.internal.example.com
Resolve-DnsName mydb.database.windows.net

# Check DNSSEC
Resolve-DnsName example.com -DnsSecOk -Type A

# Force query to specific server
Resolve-DnsName myapp.internal.example.com -Server 168.63.129.16
```

## Diagnosing private endpoint DNS failures

Private endpoint resolution failures nearly always follow one of three patterns.

**Pattern 1: No private DNS zone linked to VNet**

```bash
# List private DNS zones and their VNet links
az network private-dns zone list -g MyRG -o table

az network private-dns link vnet list -g MyRG \
    -z privatelink.database.windows.net -o table
```

Check that the zone exists and that the VNet hosting the VM (or the VNet the query originates from) has a link. Resolution-only links (no autoregistration) are sufficient for private endpoint resolution.

**Pattern 2: Wrong zone name**

Verify the zone name matches the service exactly. For SQL Database it must be `privatelink.database.windows.net`, not `privatelink.sql.azure.com` or similar. Refer to the zone-name table in `references/architecture.md`.

**Pattern 3: Correct zone, A record missing or pointing to wrong IP**

```bash
# List record sets in the private DNS zone
az network private-dns record-set list -g MyRG \
    -z privatelink.database.windows.net -o table

# Show a specific record set
az network private-dns record-set a show -g MyRG \
    -z privatelink.database.windows.net -n mydb
```

When using Azure Private Endpoint with `privateDnsZoneGroups` (auto-created via portal or Terraform `azurerm_private_endpoint` with `private_dns_zone_group`), the A record should be created automatically. If it is missing, check whether the DNS zone group is configured correctly on the private endpoint resource.

```bash
# Inspect private endpoint DNS configuration
az network private-endpoint show -g MyRG -n myPrivateEndpoint \
    --query "customDnsConfigs" -o table

az network private-endpoint show -g MyRG -n myPrivateEndpoint \
    --query "privateDnsZoneGroups" -o table
```

## Diagnosing Azure DNS Private Resolver failures

### Inbound endpoint: on-prem cannot reach Azure private DNS

1. Check the inbound endpoint exists and has an IP assigned:

```bash
az dns-resolver inbound-endpoint list -g MyRG \
    --dns-resolver-name myResolver -o table
```

2. Verify the inbound subnet NSG allows UDP/TCP 53 from the on-prem source IP range:

```bash
az network nsg rule list -g MyRG --nsg-name inbound-subnet-nsg -o table
```

3. Test from on-prem:

```bash
nslookup mydb.privatelink.database.windows.net <inbound-endpoint-ip>
```

If the query times out, suspect the NSG or a firewall between on-prem and the Azure VNet. If it returns NXDOMAIN, the private DNS zone is not linked to the resolver's VNet.

4. Check private DNS zone links on the resolver's VNet:

```bash
az network private-dns link vnet list -g MyRG \
    -z privatelink.database.windows.net -o table
# Confirm the resolver's VNet is in the linked VNets list
```

### Outbound endpoint: Azure VMs cannot resolve on-prem domains

1. Check the forwarding ruleset and rules:

```bash
az dns-resolver forwarding-ruleset list -g MyRG -o table

az dns-resolver forwarding-rule list -g MyRG \
    --ruleset-name myRuleset -o table
# Verify: correct domain suffix (with trailing dot), enabled, correct target IPs
```

2. Check the ruleset is linked to the VM's VNet:

```bash
az dns-resolver vnet-link list -g MyRG \
    --ruleset-name myRuleset -o table
```

3. Test from the Azure VM:

```bash
nslookup host.corp.internal 168.63.129.16
# 168.63.129.16 is the Azure DNS wire server; it will pick up the forwarding ruleset
# if the VM's VNet is linked
```

4. Verify the outbound endpoint subnet NSG allows outbound UDP/TCP 53 to the on-prem DNS server IPs:

```bash
az network nsg rule list -g MyRG --nsg-name outbound-subnet-nsg -o table
```

5. Confirm the on-prem DNS servers (listed in the forwarding rule) accept queries from the outbound endpoint's subnet IP range.

## Diagnosing DNSSEC failures

**Symptom**: resolvers report `SERVFAIL` or `BOGUS` for the zone after DNSSEC was enabled.

1. Confirm DNSSEC config exists and retrieve the DS records:

```bash
az network dns dnssec-config show -g MyRG -z example.com \
    --query "signingKeys[].delegationSignerInfo" -o table
```

2. Check whether the DS record appears at the parent zone:

```bash
dig @a.gtld-servers.net example.com DS   # for .com TLD
# or query the parent's nameservers directly
```

If the DS record is absent, publish it at the domain registrar. If it is present but different from what `az network dns dnssec-config show` returns, the DS record is stale (possibly from a key rollover); update the DS record at the registrar.

3. Validate the chain of trust from a public resolver:

```bash
dig +dnssec example.com A @1.1.1.1
# Look for the 'ad' (Authentic Data) flag in the response
```

A SERVFAIL with DNSSEC indicates the validator found an inconsistency. A missing `ad` flag from a validating resolver means validation is not completing.

## Diagnosing Traffic Manager health probe failures

```bash
# Show endpoint health status
az network traffic-manager endpoint show -g MyRG \
    --profile-name myProfile -n eastus-ep --query endpointMonitorStatus

# List all endpoints and their monitor status
az network traffic-manager endpoint list -g MyRG \
    --profile-name myProfile -o table
```

Common causes for `CheckingEndpoint` or `Degraded` status:
- HTTP/HTTPS probe path returning a non-200 status code.
- SSL certificate mismatch (custom header required for SNI-based hosting).
- Firewall or NSG blocking Traffic Manager probe source IP ranges. Azure publishes the Traffic Manager probe IP ranges in the `AzureTrafficManager` service tag; allow these in the NSG/firewall.
- TCP probe: the port is closed or filtered.

```bash
# Check Traffic Manager profile monitoring settings
az network traffic-manager profile show -g MyRG -n myProfile \
    --query monitorConfig
```

## Diagnosing Azure Firewall DNS proxy failures

**Symptom**: FQDN-based network or application rules not matching, or FQDN resolution failing for VMs with VNet DNS set to the firewall IP.

1. Confirm DNS proxy is enabled:

```bash
az network firewall show -g MyRG -n myFW \
    --query "additionalProperties.Network\\.DNS\\.EnableProxy"
# Should return "true"
```

2. Confirm VNet DNS server is set to the Azure Firewall private IP:

```bash
az network vnet show -g MyRG -n myVNet --query dhcpOptions
```

3. Test DNS resolution through the firewall from a VM in the VNet:

```bash
nslookup *.database.windows.net <firewall-private-ip>
```

4. Check Azure Firewall diagnostic logs (DNS Proxy log category) in Log Analytics:

```kusto
AzureDiagnostics
| where Category == "AzureFirewallDnsProxy"
| project TimeGenerated, msg_s
| order by TimeGenerated desc
| take 50
```

5. Check the upstream DNS servers configured on the firewall; 168.63.129.16 must be reachable from the firewall subnet.

## Checking DNS record propagation

After creating or modifying a public DNS record, allow the TTL to expire before expecting all resolvers to reflect the change. To confirm the authoritative answer before TTL expiry, query the zone's Azure nameservers directly:

```bash
# Query authoritative Azure nameserver directly (bypasses cache)
dig @ns1-01.azure-dns.com www.example.com A +short

# Check current TTL on a record set
az network dns record-set a show -g MyRG -z example.com -n www --query ttl
```

For private zones, records are available immediately to VMs in linked VNets because there is no TTL-based caching at the zone level. If a VM is caching an old result, flush the local DNS cache:

```bash
# Linux (systemd-resolved)
sudo resolvectl flush-caches

# Windows
ipconfig /flushdns
```

## Common errors and fixes

| Error / symptom | Cause | Fix |
|---|---|---|
| `az network private-dns link vnet create` fails with "VNet already has auto-registration" | A second auto-registration link was attempted on a VNet that already has one | Set `--registration-enabled false` for the new link; auto-registration allows only one zone per VNet |
| Private endpoint A record not created | `privateDnsZoneGroups` not configured on the private endpoint | Add a DNS zone group to the private endpoint or create the A record manually |
| `az dns-resolver forwarding-ruleset create` fails | Outbound endpoint not yet provisioned | Wait for outbound endpoint to reach `Succeeded` state before creating the ruleset |
| Forwarding rule not matching | Domain suffix missing trailing dot | All domain names in forwarding rules must end with a trailing dot (e.g., `corp.internal.`) |
| DNSSEC SERVFAIL after enabling | DS record not published at registrar | Retrieve DS record from `az network dns dnssec-config show` and add to registrar |
| Traffic Manager shows `Degraded` | Probe blocked by NSG | Add `AzureTrafficManager` service tag to NSG allow rules on port 80/443 |
| Azure Firewall FQDN rule not working | DNS proxy disabled | Enable DNS proxy on the firewall; restart any affected VMs to pick up DNS server update |
