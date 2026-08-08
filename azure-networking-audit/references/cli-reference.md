# Azure CLI reference: VNet networking audit commands

Read-only Azure CLI commands organised by audit step for VNet networking assessment. All commands are non-modifying (`show`, `list`, `list-effective-*`, `show-effective-*`). No command creates, modifies, or deletes resources.

Access method: Azure CLI with an authenticated session (`az login` completed). Commands assume the target subscription is set via `az account set --subscription <id>` or `--subscription` is appended. Output format defaults to JSON; append `--output table` for human-readable output during interactive audits.

See `../SKILL.md` for the six-step audit procedure, threshold tables, decision trees, and the folded VNet architecture model (packet flow, NSG evaluation order, Azure Firewall pipeline, ExpressRoute routing, VNet peering constraints, UDR and effective-routes model).

## Step 1: VNet inventory and design

| Function | Command |
|----------|---------|
| List all VNets in subscription | `az network vnet list --output table` |
| Single VNet details | `az network vnet show --name <vnet> --resource-group <rg>` |
| VNet address spaces | `az network vnet show --name <vnet> --resource-group <rg> --query "addressSpace.addressPrefixes"` |
| All subnets in VNet | `az network vnet subnet list --vnet-name <vnet> --resource-group <rg>` |
| Single subnet details | `az network vnet subnet show --vnet-name <vnet> --name <subnet> --resource-group <rg>` |
| Subnet delegations | `az network vnet subnet show --vnet-name <vnet> --name <subnet> --resource-group <rg> --query "delegations"` |
| Service endpoints on subnet | `az network vnet subnet show --vnet-name <vnet> --name <subnet> --resource-group <rg> --query "serviceEndpoints"` |
| Private Endpoints in RG | `az network private-endpoint list --resource-group <rg>` |
| DDoS protection plan | `az network ddos-protection list --output table` |
| VNet DDoS setting | `az network vnet show --name <vnet> --resource-group <rg> --query "enableDdosProtection"` |

## Step 2: NSG rules and security

| Function | Command |
|----------|---------|
| List all NSGs in subscription | `az network nsg list --output table` |
| Single NSG details | `az network nsg show --name <nsg> --resource-group <rg>` |
| NSG custom rules | `az network nsg rule list --nsg-name <nsg> --resource-group <rg> --output table` |
| NSG rules with defaults | `az network nsg rule list --nsg-name <nsg> --resource-group <rg> --include-default --output table` |
| NSG subnet associations | `az network nsg show --name <nsg> --resource-group <rg> --query "subnets[].id"` |
| NSG NIC associations | `az network nsg show --name <nsg> --resource-group <rg> --query "networkInterfaces[].id"` |
| Effective NSG rules for NIC | `az network nic show-effective-nsg --name <nic> --resource-group <rg>` |
| Effective security rules (list form) | `az network nic list-effective-nsg --name <nic> --resource-group <rg>` |

### Application Security Groups

| Function | Command |
|----------|---------|
| List ASGs | `az network asg list --output table` |
| ASG details | `az network asg show --name <asg> --resource-group <rg>` |
| NICs in an ASG | `az network nic list --query "[?ipConfigurations[?applicationSecurityGroups[?contains(id, '<asg-name>')]]]"` |

## Step 3: Azure Firewall and policies

| Function | Command |
|----------|---------|
| List Azure Firewalls | `az network firewall list --output table` |
| Firewall details | `az network firewall show --name <fw> --resource-group <rg>` |
| Firewall IP configuration | `az network firewall ip-config list --firewall-name <fw> --resource-group <rg>` |
| Firewall policy details | `az network firewall policy show --name <policy> --resource-group <rg>` |
| Rule collection groups | `az network firewall policy rule-collection-group list --policy-name <policy> --resource-group <rg>` |
| Rule collection group detail | `az network firewall policy rule-collection-group show --name <group> --policy-name <policy> --resource-group <rg>` |
| Firewall threat intel mode | `az network firewall show --name <fw> --resource-group <rg> --query "threatIntelMode"` |
| IDPS configuration | `az network firewall policy show --name <policy> --resource-group <rg> --query "intrusionDetection"` |
| Firewall log settings | `az monitor diagnostic-settings list --resource <firewall-resource-id>` |

## Step 4: Connectivity (ExpressRoute, VPN, peering)

| Function | Command |
|----------|---------|
| List ExpressRoute circuits | `az network express-route list --output table` |
| Circuit details | `az network express-route show --name <circuit> --resource-group <rg>` |
| Circuit provisioning status | `az network express-route show --name <circuit> --resource-group <rg> --query "{ServiceProviderStatus:serviceProviderProvisioningState, CircuitStatus:circuitProvisioningState}"` |
| ExpressRoute peerings | `az network express-route peering list --circuit-name <circuit> --resource-group <rg>` |
| Peering route tables | `az network express-route list-route-tables --name <circuit> --resource-group <rg> --peering-name AzurePrivatePeering --path primary` |
| VPN Gateways | `az network vnet-gateway list --resource-group <rg> --output table` |
| VPN Gateway details | `az network vnet-gateway show --name <gw> --resource-group <rg>` |
| VPN connections | `az network vpn-connection list --resource-group <rg> --output table` |
| VPN connection status | `az network vpn-connection show --name <conn> --resource-group <rg> --query "connectionStatus"` |
| VNet peering list | `az network vnet peering list --vnet-name <vnet> --resource-group <rg> --output table` |
| VNet peering details | `az network vnet peering show --vnet-name <vnet> --name <peering> --resource-group <rg>` |
| Peering transit settings | `az network vnet peering show --vnet-name <vnet> --name <peering> --resource-group <rg> --query "{AllowGatewayTransit:allowGatewayTransit, UseRemoteGateways:useRemoteGateways, AllowForwardedTraffic:allowForwardedTraffic}"` |

## Step 5: UDR and route tables

| Function | Command |
|----------|---------|
| List route tables | `az network route-table list --output table` |
| Route table details | `az network route-table show --name <rt> --resource-group <rg>` |
| Routes in table | `az network route-table route list --route-table-name <rt> --resource-group <rg> --output table` |
| BGP propagation setting | `az network route-table show --name <rt> --resource-group <rg> --query "disableBgpRoutePropagation"` |
| Effective routes for NIC | `az network nic show-effective-route-table --name <nic> --resource-group <rg>` |
| Route table associations | `az network route-table show --name <rt> --resource-group <rg> --query "subnets[].id"` |

### Route table notes

- Azure evaluates routes in order: UDR routes, then BGP routes, then system routes. More-specific prefixes take precedence within each category.
- System routes are auto-created for the VNet address space (next-hop VirtualNetwork), `0.0.0.0/0` (next-hop Internet), and the RFC 1918 ranges (next-hop None when no peering covers them).
- UDR routes with next-hop "None" drop matching traffic; use for blocking specific routes without an NSG rule.
- `disableBgpRoutePropagation: true` prevents ExpressRoute and VPN Gateway learned routes from being injected into the subnet.

## Step 6: Resource optimisation

| Function | Command |
|----------|---------|
| Orphaned NICs (no VM) | `az network nic list --query "[?virtualMachine==null]" --output table` |
| Unassociated public IPs | `az network public-ip list --query "[?ipConfiguration==null]" --output table` |
| All public IPs | `az network public-ip list --output table` |
| Application Gateway list | `az network application-gateway list --output table` |
| App Gateway capacity | `az network application-gateway show --name <gw> --resource-group <rg> --query "sku"` |
| Azure Advisor network recs | `az advisor recommendation list --category Cost --query "[?category=='Cost' && impactedField=='Microsoft.Network']"` |
| Network Watcher status | `az network watcher list --output table` |

## Identity and access verification

| Function | Command |
|----------|---------|
| Current subscription | `az account show --output table` |
| Current user identity | `az ad signed-in-user show` |
| Role assignments on subscription | `az role assignment list --scope /subscriptions/<sub-id> --output table` |
| Check specific permission | `az role assignment list --assignee <user-or-sp-id> --scope /subscriptions/<sub-id> --query "[].roleDefinitionName"` |
