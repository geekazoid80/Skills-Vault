# Azure DNS architecture

## Public zone infrastructure

### Anycast nameservers

Azure DNS hosts public authoritative zones on a globally distributed anycast network. Each zone is delegated four nameservers drawn from four different TLDs for resilience:

- `ns1-0x.azure-dns.com`
- `ns2-0x.azure-dns.net`
- `ns3-0x.azure-dns.org`
- `ns4-0x.azure-dns.info`

BGP anycast routes each query to the nearest Azure point of presence. No DNS infrastructure to provision or patch; the service is fully managed. Microsoft publishes a 100% SLA for valid DNS queries.

### Supported record types

| Type | Description | Zone apex |
|---|---|---|
| A | IPv4 address | Yes (direct or alias) |
| AAAA | IPv6 address | Yes (direct or alias) |
| CNAME | Canonical name | No (use Alias instead) |
| MX | Mail exchange | No alias |
| NS | Nameserver (auto-managed) | Auto |
| PTR | Reverse lookup | N/A |
| SOA | Start of authority (auto-managed) | Auto |
| SRV | Service locator | No alias |
| TXT | Text (SPF, DKIM, domain verification) | No alias |
| CAA | Certificate authority authorisation | No alias |

NS and SOA records are created automatically at zone creation and are managed by Azure DNS. Do not delete or overwrite them.

### Zone delegation

After creating a public zone, update the NS records at the domain registrar to point to the four Azure nameservers shown in the Azure portal or CLI output. Delegation propagates according to the parent zone's TTL (typically 24-48 hours for registrar-held zones).

```bash
# Create public zone
az network dns zone create -g MyRG -n example.com

# List assigned nameservers
az network dns zone show -g MyRG -n example.com --query nameServers -o tsv

# Add A record
az network dns record-set a add-record -g MyRG -z example.com -n www -a 203.0.113.1

# Add MX record
az network dns record-set mx add-record -g MyRG -z example.com -n @ \
    -e mail.example.com -p 10

# Add TXT record (SPF)
az network dns record-set txt add-record -g MyRG -z example.com -n @ \
    -v "v=spf1 include:spf.protection.outlook.com -all"

# List all record sets
az network dns record-set list -g MyRG -z example.com -o table
```

Terraform:

```hcl
resource "azurerm_dns_zone" "public" {
  name                = "example.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_dns_a_record" "www" {
  name                = "www"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["203.0.113.1"]
}

resource "azurerm_dns_txt_record" "spf" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  record {
    value = "v=spf1 include:spf.protection.outlook.com -all"
  }
}
```

## Alias records

Alias records are an Azure DNS extension that allows A, AAAA, or CNAME record sets to reference an Azure resource by resource ID rather than a static IP address.

```
┌─────────────────┐      auto-update      ┌────────────────────────┐
│  Alias record   │<─────────────────────>│  Azure resource        │
│  example.com A  │                        │  (Public IP, Traffic   │
│  (zone apex)    │                        │   Manager, CDN, etc.)  │
└─────────────────┘                        └────────────────────────┘
```

### Supported alias targets

| Target resource type | Record types |
|---|---|
| Azure Public IP | A, AAAA |
| Azure Traffic Manager profile | A, AAAA, CNAME |
| Azure CDN endpoint | A, AAAA, CNAME |
| Azure Front Door | A, AAAA, CNAME |
| Another record set in the same zone | A, AAAA, CNAME |

### Key properties

- **Zone apex support**: alias records can be placed at the zone root (`@`), solving the RFC restriction that prohibits CNAME at the apex.
- **Auto-updating**: when the target Azure resource's IP changes (e.g., reallocation of a Public IP), the DNS record reflects the new IP automatically.
- **No TTL override**: the TTL is inherited from the target resource.
- **Free query billing**: queries to alias records targeting Azure resources are not billed per query.

```bash
# Alias to Azure Public IP (zone apex)
az network dns record-set a create -g MyRG -z example.com -n @ \
    --target-resource "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/publicIPAddresses/myPIP"

# Alias to Traffic Manager profile
az network dns record-set a create -g MyRG -z example.com -n @ \
    --target-resource "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/trafficManagerProfiles/myTM"
```

Terraform:

```hcl
resource "azurerm_dns_a_record" "apex" {
  name                = "@"
  zone_name           = azurerm_dns_zone.public.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.main.id
}
```

## DNSSEC (public zones only)

Azure DNS manages DNSSEC signing automatically: key generation, algorithm selection, key rotation, and signing operations. The operator's responsibility is limited to publishing the DS record at the parent registrar.

```
Zone ──► Azure DNSSEC signing ──► Signed responses
               |
          Auto-managed:
          - Key generation
          - Key rotation (periodic)
          - Signing operations
```

Supported algorithms: ECDSAP256SHA256, ECDSAP384SHA384, ED25519.

DNSSEC is **not** supported on private DNS zones.

```bash
# Enable DNSSEC signing
az network dns dnssec-config create -g MyRG -z example.com

# Retrieve DS records for parent registrar
az network dns dnssec-config show -g MyRG -z example.com \
    --query "signingKeys[].delegationSignerInfo" -o table

# Disable DNSSEC signing
az network dns dnssec-config delete -g MyRG -z example.com
```

After enabling DNSSEC, copy the DS record values from the CLI output and add them manually at the domain registrar. Until the DS record is published at the parent, DNSSEC validation fails for resolvers that enforce it.

## Private zone architecture

Private DNS zones resolve only within Azure VNets. They are not publicly accessible.

### VNet links

```
┌──────────────────┐
│ Private zone     │
│ internal.corp    │
├──────────────────┤
│ VNet link 1      │───► VNet-A (autoregistration ON)
│ VNet link 2      │───► VNet-B (autoregistration OFF)
│ VNet link 3      │───► VNet-C (autoregistration OFF, cross-subscription)
└──────────────────┘
```

- A private zone can be linked to multiple VNets (same or different subscriptions, with appropriate RBAC).
- A VNet that has no link to a private zone cannot resolve records in that zone.
- VNet peering does NOT propagate private DNS; each VNet needing resolution requires its own explicit link.

```bash
# Create private zone
az network private-dns zone create -g MyRG -n internal.example.com

# Link VNet with autoregistration
az network private-dns link vnet create -g MyRG -z internal.example.com \
    -n mylink --virtual-network myVNet --registration-enabled true

# Link VNet without autoregistration (resolution-only)
az network private-dns link vnet create -g MyRG -z internal.example.com \
    -n resolutionlink --virtual-network myVNet2 --registration-enabled false

# Add A record manually
az network private-dns record-set a add-record -g MyRG -z internal.example.com \
    -n myapp -a 10.0.1.10

# List records
az network private-dns record-set list -g MyRG -z internal.example.com -o table
```

Terraform:

```hcl
resource "azurerm_private_dns_zone" "internal" {
  name                = "internal.example.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = true
}
```

### Autoregistration

When `registration_enabled = true` on a VNet link:

- New VMs in the linked VNet receive an A record automatically (`vm-name.zone-name`).
- Deleted VMs have their A records removed automatically.
- NIC IP changes are reflected automatically.
- **A VNet may have autoregistration enabled for exactly one private DNS zone.** A second autoregistration link on the same VNet fails.

### Private endpoint DNS integration

Azure services with Private Link use a `privatelink` CNAME chain:

```
mydb.database.windows.net
  -> CNAME: mydb.privatelink.database.windows.net
  -> A: 10.0.1.5 (from private DNS zone linked to VNet)
```

Without the linked private DNS zone, the CNAME resolves to the public IP address instead, and traffic does not traverse the private endpoint.

Common private DNS zone names per service:

| Service | Private DNS zone |
|---|---|
| Azure SQL Database | privatelink.database.windows.net |
| Azure Blob Storage | privatelink.blob.core.windows.net |
| Azure Key Vault | privatelink.vaultcore.azure.net |
| Azure Cosmos DB | privatelink.documents.azure.com |
| Azure App Service | privatelink.azurewebsites.net |
| Azure Monitor | privatelink.monitor.azure.com |
| Azure Container Registry | privatelink.azurecr.io |
| Azure Kubernetes Service | privatelink.<region>.azmk8s.io |

The full list is maintained in the Azure documentation under "Azure Private Endpoint DNS configuration".

## Azure DNS Private Resolver

The Private Resolver is a fully managed DNS proxy deployed inside a VNet. It replaces IaaS DNS VM patterns for hybrid DNS.

### Component architecture

```
┌───────────────────────────────────────────────────────────────┐
│                         Azure VNet                            │
│                                                               │
│  ┌──────────────────────┐   ┌────────────────────────────┐   │
│  │ Inbound subnet       │   │ Outbound subnet            │   │
│  │ (dedicated /28+)     │   │ (dedicated /28+)           │   │
│  │                      │   │                            │   │
│  │ Inbound endpoint     │   │ Outbound endpoint          │   │
│  │ IP: 10.0.1.4         │   │ IP: 10.0.2.4               │   │
│  └──────────┬───────────┘   └──────────┬─────────────────┘   │
│             |                          |                      │
│             |               ┌──────────┴──────────┐          │
│             |               │ DNS forwarding       │          │
│             |               │ ruleset              │          │
│             |               │                      │          │
│             |               │ corp.internal ->     │          │
│             |               │   10.10.0.53         │          │
│             |               │   10.10.0.54         │          │
│             |               │                      │          │
│             |               │ ad.contoso.com ->    │          │
│             |               │   10.10.0.53         │          │
│             |               └──────────────────────┘          │
└─────────────┴─────────────────────────────────────────────────┘
```

### Inbound endpoint

- Assigned a private IP within the VNet.
- On-premises DNS servers conditionally forward specific domain suffixes to this IP.
- The resolver answers using Azure Private DNS zones linked to the resolver's VNet.
- Use case: on-prem resolving Azure private endpoints (SQL Private Link, Key Vault Private Link, etc.).
- Capacity: up to 10,000 queries per second per endpoint; zone-redundant high availability.

### Outbound endpoint

- Used for conditional forwarding from Azure VMs to external DNS servers.
- Must be associated with at least one DNS forwarding ruleset.
- Use case: Azure VMs resolving on-premises Active Directory domains or corporate DNS.
- Source IP for forwarded queries comes from the outbound subnet.
- Capacity: up to 10,000 queries per second per endpoint.

### DNS forwarding ruleset

- A container for forwarding rules.
- Each rule maps a domain suffix to one or more target DNS server IP/port pairs.
- Most specific domain match wins (e.g., `sub.corp.internal.` wins over `corp.internal.`).
- Up to 1,000 rules per ruleset.
- Up to 2 rulesets per outbound endpoint.
- A ruleset can be linked to multiple VNets.
- **VNets must be explicitly linked to the ruleset** to receive the forwarding rules; unlinked VNets use Azure default DNS.

```bash
# Create Private Resolver
az dns-resolver create -g MyRG -n myResolver \
    --location eastus \
    --id "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/virtualNetworks/myVNet"

# Create inbound endpoint
az dns-resolver inbound-endpoint create -g MyRG --dns-resolver-name myResolver \
    -n inbound \
    --ip-configurations "[{private-ip-allocation-method:Dynamic,id:'/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/virtualNetworks/myVNet/subnets/inbound-subnet'}]"

# Create outbound endpoint
az dns-resolver outbound-endpoint create -g MyRG --dns-resolver-name myResolver \
    -n outbound \
    --subnet-id "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/virtualNetworks/myVNet/subnets/outbound-subnet"

# Create forwarding ruleset
az dns-resolver forwarding-ruleset create -g MyRG -n myRuleset \
    --outbound-endpoints "[{id:'/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/dnsResolvers/myResolver/outboundEndpoints/outbound'}]"

# Add forwarding rule
az dns-resolver forwarding-rule create -g MyRG --ruleset-name myRuleset \
    -n corp-internal --domain-name "corp.internal." \
    --target-dns-servers "[{ip-address:10.10.0.53,port:53},{ip-address:10.10.0.54,port:53}]"

# Link ruleset to VNet
az dns-resolver vnet-link create -g MyRG --ruleset-name myRuleset \
    -n mylink --id "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/virtualNetworks/myVNet"
```

Terraform:

```hcl
resource "azurerm_private_dns_resolver" "resolver" {
  name                = "my-resolver"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "inbound" {
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = azurerm_resource_group.main.location
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.inbound.id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "outbound" {
  name                    = "outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = azurerm_resource_group.main.location
  subnet_id               = azurerm_subnet.outbound.id
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "ruleset" {
  name                                       = "corp-forwarding"
  resource_group_name                        = azurerm_resource_group.main.name
  location                                   = azurerm_resource_group.main.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.outbound.id]
}

resource "azurerm_private_dns_resolver_forwarding_rule" "corp" {
  name                      = "corp-internal"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.ruleset.id
  domain_name               = "corp.internal."
  enabled                   = true
  target_dns_servers {
    ip_address = "10.10.0.53"
    port       = 53
  }
  target_dns_servers {
    ip_address = "10.10.0.54"
    port       = 53
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "vnet_link" {
  name                      = "vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.ruleset.id
  virtual_network_id        = azurerm_virtual_network.main.id
}
```

### Hybrid DNS patterns

**Pattern 1: On-premises to Azure private endpoints**

```
On-prem client -> On-prem DNS
  -> Conditional forwarder: *.privatelink.database.windows.net -> 10.0.1.4
  -> Inbound endpoint resolves via linked private DNS zone
  -> Returns: 10.0.1.5 (private endpoint IP)
```

Configure on-prem DNS (Windows DNS, BIND, Unbound, etc.) with a conditional forwarder for the relevant `privatelink.*` zone pointing to the Private Resolver inbound endpoint IP.

**Pattern 2: Azure VMs to on-premises Active Directory**

```
Azure VM -> 168.63.129.16 (Azure DNS wire server)
  -> Outbound endpoint -> forwarding ruleset
  -> Rule: ad.contoso.com -> 10.10.0.53
  -> On-prem DC responds with AD DNS records
```

**Pattern 3: Hub-spoke with centralised DNS**

```
Spoke VNets -> Hub VNet (forwarding ruleset linked)
  -> Private Resolver handles:
    - Azure private zones (inbound endpoint)
    - On-prem forwarding (outbound endpoint)
    - Internet DNS (Azure default via 168.63.129.16)
```

In a hub-spoke topology, deploy the Private Resolver in the hub VNet. Link the forwarding ruleset to each spoke VNet. Link private DNS zones to the hub VNet. This eliminates DNS infrastructure in spoke VNets.

## Traffic Manager

Traffic Manager provides DNS-based global traffic routing. It is DNS-only; no data-plane proxy. The client connects directly to the selected endpoint after receiving the DNS response.

### Routing methods

| Method | Use case | Key configuration |
|---|---|---|
| Priority | Active/passive failover | Priority value per endpoint (lower = higher priority) |
| Weighted | A/B testing, canary deployments | Weight 1-1000 per endpoint |
| Performance | Route to lowest-latency endpoint | Azure region per endpoint; Azure maintains latency tables |
| Geographic | Data sovereignty, regional content | Geographic region mapping per endpoint |
| Subnet | Enterprise network-based routing | CIDR ranges mapped to endpoints |
| Multivalue | Client-side load balancing | Returns up to 8 healthy endpoint IPs |

```bash
# Create Traffic Manager profile
az network traffic-manager profile create -g MyRG -n myProfile \
    --routing-method Performance \
    --unique-dns-name myapp-global \
    --ttl 60 \
    --protocol HTTPS --port 443 --path /health

# Add Azure endpoint
az network traffic-manager endpoint create -g MyRG \
    --profile-name myProfile \
    -n eastus-ep --type azureEndpoints \
    --target-resource-id "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/publicIPAddresses/myPIP-eastus" \
    --endpoint-status enabled

# Add external endpoint
az network traffic-manager endpoint create -g MyRG \
    --profile-name myProfile \
    -n westeu-ep --type externalEndpoints \
    --target myapp.westeurope.example.com \
    --endpoint-location westeurope \
    --endpoint-status enabled
```

### Health probes

- HTTP/HTTPS: checks status code (200 expected) and optional body-content match.
- TCP: checks port connectivity.
- Probe interval: 10-30 seconds.
- Tolerated consecutive failures before marking unhealthy: 0-9.
- Custom headers supported for host-based routing targets.

### Nesting

Combine routing methods using nested profiles:

```
Parent: Performance routing (select region)
  ├── Child EastUS: Weighted (canary split)
  │     ├── v1: weight 90
  │     └── v2: weight 10
  └── Child WestEU: Priority (failover)
        ├── primary: priority 1
        └── secondary: priority 2
```

A minimum child-endpoint count threshold determines parent health. Set it to match the expected minimum healthy child endpoints.

**Traffic Manager TTL consideration**: lower TTL means faster failover detection by clients, but significantly increases DNS query volume. Do not set TTL below 10 seconds.

## Azure Firewall DNS proxy

The Azure Firewall DNS proxy forwards DNS queries from VMs through the firewall to configured upstream DNS servers, enabling FQDN logging and FQDN-based rule evaluation.

### Architecture

```
Azure VM -> Azure Firewall (DNS proxy, private IP)
               |
          DNS logging (diagnostic logs: source IP, FQDN, resolved IPs, response code)
               |
          Custom DNS / Azure DNS (168.63.129.16)
```

### Configuration requirements

1. Enable DNS proxy on the Azure Firewall.
2. Set the VNet's custom DNS server to the Azure Firewall private IP.
3. Configure the firewall's upstream DNS (custom on-prem DNS and/or Azure DNS wire server 168.63.129.16).

```bash
# Enable DNS proxy
az network firewall update -g MyRG -n myFW \
    --enable-dns-proxy true \
    --dns-servers 10.0.0.53 168.63.129.16
```

### FQDN rules requirement

DNS proxy is **required** for:
- Network rules with FQDN targets (e.g., `*.database.windows.net` on TCP 1433).
- Application rules with FQDN targets.

Without DNS proxy enabled, Azure Firewall cannot resolve FQDNs in rules; the rules fail silently or block all matching traffic.

### DNS logging

Azure Firewall diagnostic logs capture per-query: source IP, queried FQDN, resolved IP addresses, DNS response code. Use these logs for compliance auditing, security monitoring, and DNS-based threat detection.

## RBAC for Azure DNS

DNS resources follow standard Azure RBAC. Built-in roles relevant to DNS:

| Role | Scope | Permissions |
|---|---|---|
| DNS Zone Contributor | Zone | Create/delete zones, manage all record sets in the zone |
| Private DNS Zone Contributor | Private zone | Create/delete private zones, manage VNet links and record sets |
| Network Contributor | Resource group / subscription | Broad network resource management (includes DNS) |
| Reader | Zone or resource group | Read-only access to DNS records |

Recommended pattern: grant `DNS Zone Contributor` to automation service principals scoped to specific DNS zones, not to the entire subscription. Avoid granting `Contributor` at the resource-group level for DNS-only automation.

```bash
# Assign DNS Zone Contributor to a service principal on a specific zone
az role assignment create \
    --assignee <service-principal-object-id> \
    --role "DNS Zone Contributor" \
    --scope "/subscriptions/<sub>/resourceGroups/MyRG/providers/Microsoft.Network/dnszones/example.com"
```
