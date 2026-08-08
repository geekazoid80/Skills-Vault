# Azure Networking Reference

> Prices are US East, pay-as-you-go unless noted. Verify at https://azure.microsoft.com/pricing/.

---

## 1. VNet Architecture

### Hub-Spoke Topology

The recommended enterprise network topology on Azure:

```
                    Hub VNet
          ┌─────────────────────────┐
 On-prem  │  Azure Firewall / NVA   │
 ←VPN/ER→ │  Shared Services        │
          │  (DNS, Bastion, ADDS)   │
          └────┬───────┬───────┬────┘
          Peer │  Peer │  Peer │
        ┌──────┘       │       └──────┐
        ▼              ▼              ▼
   Spoke 1 (Prod) Spoke 2 (Dev) Spoke 3 (DMZ)
```

- **Hub:** Centralised firewall, VPN/ExpressRoute gateway, Bastion, shared DNS. Azure Firewall Standard ~$912/mo + $0.016/GB; Premium ~$1,825/mo (TLS inspection, IDPS).
- **Spokes:** Workload VNets peered to hub. Inter-spoke and outbound traffic routes through hub firewall via UDRs.
- **Alternative:** Azure Virtual WAN for >30 spokes or multi-region automated routing (~$547/mo per hub + $0.02/GB transit).

### VNet Peering

| Type | Data Transfer Cost | Latency |
|------|-------------------|---------|
| Same-region | Free | Sub-ms |
| Cross-region (global) | $0.01/GB each direction | 1 to 10ms |

Peering is non-transitive: Spoke A <-> Hub <-> Spoke B requires hub firewall/NVA or explicit Spoke A <-> Spoke B peering. Cross-region peering adds up for chatty workloads; co-locate dependent services.

### Private Endpoints

Project Azure PaaS services (Storage, SQL, Key Vault) into your VNet with a private IP:

- **Cost:** $0.01/hr per endpoint (~$7.30/mo) + data processing rates.
- **Security:** Eliminates public internet exposure. Traffic stays on Microsoft backbone.
- **DNS:** Requires Private DNS Zones for `*.privatelink.<service>.net`. Centralise in hub VNet linked to all spokes.
- **On-prem access:** Resolvable via VPN or ExpressRoute when Private DNS Zones are linked and conditional forwarders point to 168.63.129.16 (or Azure DNS Private Resolver).
- **When to use:** Any PaaS service accessed from VNet resources in production. Non-negotiable for compliance.

### Service Endpoints vs Private Endpoints

| Aspect | Service Endpoints | Private Endpoints |
|--------|------------------|-------------------|
| Cost | Free | $7.30/mo per endpoint |
| Traffic path | Optimised but public IP space | Fully private within VNet |
| On-prem access | Not accessible | Yes, via VPN/ExpressRoute |
| DNS changes | None | Requires Private DNS Zones |

Use Private Endpoints for production and on-prem connectivity. Service Endpoints acceptable for dev/test.

### Network Security Groups (NSGs)

Stateful packet filters at subnet or NIC level:

- Rules evaluated by priority (100 to 4096; lower number = higher priority).
- Default: allow VNet-to-VNet, allow outbound internet, deny all inbound from internet.
- **Best practice:** Apply at subnet level. Use Application Security Groups (ASGs) for role-based rules without tracking IPs.
- **Cost:** Free. No per-rule or per-evaluation charge.

### NSG Rule Auditing Workflow

When auditing security posture or verifying NSG compliance:

1. Run `azure_audit_nsg_compliance` to check against CIS Azure Foundations Benchmark (rules 6.1 to 6.4).
2. Run `azure_list_nsgs` to identify orphaned NSGs (associated with no subnet or NIC).
3. For each flagged NSG, call `azure_get_nsg_rules` to review custom and default rules sorted by priority.
4. Call `azure_get_effective_security_rules` on critical NICs to see the aggregated effective rule set (accounts for both subnet-level and NIC-level NSGs).
5. Report findings by severity with remediation steps and orphan count.

### Subnet Design

- `/24` (256 addresses) is common. Azure reserves 5 per subnet.
- Dedicate subnets for: AKS, App Service VNet integration, Firewall, Gateway, Bastion, Private Endpoints.
- AKS with Azure CNI (non-overlay) needs substantial IP space.
- Never use subnets smaller than `/27`.

---

## 2. Application Gateway vs Front Door vs Traffic Manager

### Comparison

| Feature | App Gateway v2 | Azure Front Door | Traffic Manager |
|---------|---------------|------------------|-----------------|
| Scope | Regional | Global | Global |
| Layer | L7 (HTTP/S) | L7 (HTTP/S) | DNS-based |
| WAF | Yes | Yes | No |
| CDN | No | Yes (integrated) | No |
| Failover speed | N/A (regional) | Seconds (anycast) | DNS TTL (30 to 300s) |
| Private backends | Yes (VNet) | Yes (Private Link) | No |

### Cost

| Service | Fixed Cost/mo | Variable |
|---------|-------------|----------|
| App Gateway v2 Standard | ~$175 | $6/CU/month |
| App Gateway v2 WAF | ~$262 | $9/CU/month |
| Front Door Standard | ~$35 | $0.01 to $0.065/GB |
| Front Door Premium | ~$330 | Higher per-GB + Private Link |
| Traffic Manager | $0.54/endpoint/mo | $0.75/M DNS queries |

### When to Use Each

- **App Gateway:** Regional L7 load balancing, WAF, or SSL offload within a single region.
- **Front Door:** Multi-region web apps needing global routing, CDN, WAF, instant failover. Default for multi-region.
- **Traffic Manager:** Non-HTTP multi-region services, or DNS-level routing. Cheapest but slowest failover.
- **Common pattern:** Front Door (global) -> App Gateway per region (regional WAF/routing) -> backends. Most resilient but most expensive.

---

## 3. ExpressRoute

Dedicated private connectivity from on-premises to Azure.

### Cost Structure

| Component | Cost (approx) |
|-----------|---------------|
| Circuit (1 Gbps, metered) | ~$436/mo |
| Circuit (1 Gbps, unlimited data) | ~$1,700/mo |
| VNet Gateway (ErGw1Az) | ~$219/mo |
| VNet Gateway (ErGw3Az, high perf) | ~$1,314/mo |
| Outbound data (metered) | $0.025/GB |
| **Total minimum** | **~$655/mo + carrier charges** |

### ExpressRoute vs Site-to-Site VPN

| Aspect | ExpressRoute | VPN |
|--------|-------------|-----|
| Path | Private carrier network | Encrypted over internet |
| Bandwidth | 50 Mbps to 100 Gbps | Up to 10 Gbps |
| Latency | Predictable, low | Variable |
| Reliability | SLA 99.95% | Best-effort |
| Cost | $655+/mo + carrier | ~$140/mo (VpnGw1AZ) |

VPN is 5 to 10x cheaper and sufficient for most small/medium workloads. ExpressRoute justified for:
- Latency-sensitive apps (SAP, real-time databases).
- Bandwidth >10 Gbps.
- Compliance prohibiting public internet transit.
- M365 traffic optimisation for large enterprises.

### ExpressRoute Global Reach

Connect two on-prem sites via Microsoft backbone. ~$0.05/GB additional.

### ExpressRoute Operations Workflow

When asked to check ExpressRoute status or verify hybrid connectivity:

1. Call `azure_get_expressroute_status` to review circuit provisioning state and peering configuration.
2. Call `azure_get_expressroute_routes` to inspect the learned route table for a specific peering (confirms routes are being advertised from on-prem).
3. Call `azure_get_vpn_gateway_status` for any parallel VPN gateway (connection status, BGP peers, bytes transferred).
4. Report: circuit health, learned route count, tunnel status, bytes transferred.

Key fields to verify in `azure_get_expressroute_status`:
- `circuitProvisioningState`: must be `Enabled`.
- `serviceProviderProvisioningState`: must be `Provisioned`.
- `peeringState` per peering (AzurePrivatePeering / AzurePublicPeering / MicrosoftPeering): must be `Connected`.

---

## 4. VPN Gateway

| SKU | Max throughput | Cost/mo (approx) |
|-----|---------------|-----------------|
| VpnGw1AZ | 650 Mbps | ~$140 |
| VpnGw2AZ | 1 Gbps | ~$280 |
| VpnGw3AZ | 1.25 Gbps | ~$560 |

- Zone-redundant (`AZ` suffix) SKUs are required for 99.99% SLA.
- Supports BGP for dynamic routing; recommended over static routing for site-to-site.
- Call `azure_get_vpn_gateway_status` to review gateway config, connections, and BGP neighbour state.

---

## 5. DDoS Protection

| Tier | Cost | Protection |
|------|------|------------|
| Infrastructure (default) | Free | Basic L3/L4 for all public IPs |
| Network Protection | ~$2,944/mo per VNet (100 public IPs) | Adaptive tuning, metrics, DDoS response team, cost guarantee |
| IP Protection | ~$199/mo per public IP | Same as Network but per-IP. No response team or cost guarantee |

- Free tier handles most volumetric attacks.
- IP Protection for 1 to 14 public IPs. Beyond ~15 IPs, Network Protection is cheaper.
- Network Protection reimburses scale-out costs during verified attacks.

---

## 6. Azure DNS

### Public Zones

- $0.50/month per zone + $0.40 per million queries.
- Alias records for Azure resources (auto-updates, no dangling DNS).

### Private DNS Zones

- $0.25/month per zone + $0.40 per million queries.
- Essential for Private Endpoint resolution.
- **Pattern:** Host in hub VNet, link to all spokes. Centralises management.
- With custom DNS servers: configure conditional forwarders for `*.privatelink.*` to 168.63.129.16, or use Azure DNS Private Resolver ($0.18/hr inbound + $0.09/hr outbound).

### Private Endpoint DNS Considerations

Split-horizon DNS is the most common misconfiguration when adding Private Endpoints:

- If your on-prem DNS resolves `storageaccount.blob.core.windows.net` via its own forwarder but does NOT forward `privatelink.blob.core.windows.net` to 168.63.129.16 (or the Azure DNS Private Resolver inbound endpoint), on-prem clients will receive the public IP instead of the private IP.
- Verify with: `nslookup <storage-account>.blob.core.windows.net` from within the VNet (should return 10.x.x.x) and from on-prem (should also return 10.x.x.x if forwarders are correct).
- Use `azure_get_private_endpoints` to list all Private Endpoints with their DNS zone associations and verify each endpoint has a corresponding A record in the matching Private DNS Zone.
- Use `azure_get_dns_zones` to enumerate both public and private zones and cross-check record sets.

---

## 7. Route Tables and User-Defined Routes

- UDRs override Azure's default system routes.
- Common pattern: default route (0.0.0.0/0) pointing to Azure Firewall private IP in hub VNet forces all spoke egress through the firewall.
- Apply route tables to subnets, not individual NICs (except for NVA scenarios).
- Use `azure_get_route_tables` to retrieve route tables, UDR entries, and effective routes for a given NIC.
- Never apply a UDR to the GatewaySubnet that points back at a firewall; this creates a routing loop for on-prem traffic.

---

## 8. Azure Firewall

| SKU | Cost/mo (approx) | Key capabilities |
|-----|-----------------|-----------------|
| Standard | ~$912 | Network/application rules, threat intel, DNAT |
| Premium | ~$1,825 | All Standard + TLS inspection, IDPS, URL categories |

- Deploy in a dedicated `AzureFirewallSubnet` (/26 minimum).
- Use Firewall Policy (preferred) over classic rule collections; supports rule groups and inheritance.
- Call `azure_list_firewalls` to enumerate deployed firewalls with SKU and policy associations.
- Call `azure_get_firewall_policy` to inspect rule collections, threat-intel mode, and IDPS settings.

---

## 9. Load Balancer

| SKU | Cost/mo (approx) | Notes |
|-----|-----------------|-------|
| Basic | Free | No SLA, no AZ support. Avoid for production. |
| Standard | ~$18 + $0.005/GB | Zone-redundant, supports HA ports, private/public |

- Call `azure_list_load_balancers` to get frontend IPs, backend pool summaries, and health probe configuration.
- Call `azure_get_lb_backend_health` to check per-member health state in a backend pool; useful when traffic is not reaching backends.

---

## 10. Network Watcher

Network Watcher is a regional service that must be enabled per region before any diagnostics are available.

| Capability | What it answers |
|------------|----------------|
| IP Flow Verify | "Would NSG rule X allow/deny this packet?" |
| Next Hop | "Where does traffic to destination Y go from this NIC?" |
| Connection Monitor | Continuous latency and reachability between endpoints |
| NSG Flow Logs | Per-rule allow/deny traffic logs (sent to Storage or Traffic Analytics) |
| Packet Capture | On-demand or triggered packet capture on a VM NIC |
| Topology | Visual map of resources in a VNet |

### Network Watcher Workflow

1. Call `azure_get_network_watcher_status` to confirm Network Watcher is enabled in the target region and to list active connection monitors and flow log configurations.
2. Use IP Flow Verify (via the portal or `az network watcher test-ip-flow`) to diagnose NSG allow/deny decisions before editing rules.
3. Use Next Hop to verify UDR effectiveness: confirm traffic destined for on-prem or a peered VNet is taking the expected path and not being black-holed by a misconfigured UDR.
4. Enable NSG Flow Logs and route to a Log Analytics workspace for Traffic Analytics; this provides visualisation of top talkers, blocked flows, and geo-distribution.
5. Connection Monitor is preferred over ad-hoc ping for ongoing SLA measurement between application tiers or across hybrid links.

---

## 11. MCP Tool Reference

The following read-only tools are available via the `azure-network-ops` MCP server.

**Auth requirements:** `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`. Uses `DefaultAzureCredential` (service principal or Azure CLI fallback). All operations are List/Get only; no create, modify, or delete.

**Rate limits:** Azure ARM allows ~1,200 reads per 5 minutes per tenant; the server auto-retries on HTTP 429.

### VNet Topology

| Tool | What It Does |
|------|-------------|
| `azure_list_subscriptions` | List all accessible Azure subscriptions |
| `azure_list_vnets` | List all VNets with address space, subnet/peering count |
| `azure_get_vnet_details` | Full VNet details: subnets (NSG, route table, delegations), peerings, DNS |
| `azure_get_vnet_peerings` | VNet peering status with traffic forwarding settings |

### NSG Security

| Tool | What It Does |
|------|-------------|
| `azure_list_nsgs` | List all NSGs with association info and orphan detection |
| `azure_get_nsg_rules` | All rules (custom + default) sorted by priority |
| `azure_get_effective_security_rules` | Effective aggregated rules for a NIC |
| `azure_audit_nsg_compliance` | CIS Azure Foundations Benchmark audit (rules 6.1 to 6.4) |

### Hybrid Connectivity

| Tool | What It Does |
|------|-------------|
| `azure_get_expressroute_status` | Circuit status, peering config, provisioning state |
| `azure_get_expressroute_routes` | Learned route table for a peering |
| `azure_get_vpn_gateway_status` | Gateway config, connections, BGP settings |

### Firewall and Load Balancing

| Tool | What It Does |
|------|-------------|
| `azure_list_firewalls` | List Azure Firewalls with SKU and policy association |
| `azure_get_firewall_policy` | Policy details: rule collections, threat intel, IDPS |
| `azure_list_load_balancers` | List LBs with frontend/backend/probe summary |
| `azure_get_lb_backend_health` | Backend pool health per member |
| `azure_get_app_gateway_health` | App GW config, WAF, backend health; Front Door routing |

### Supporting Services

| Tool | What It Does |
|------|-------------|
| `azure_get_route_tables` | Route tables, UDRs, effective routes for a NIC |
| `azure_get_network_watcher_status` | Network Watcher availability, connection monitors, flow logs |
| `azure_get_private_endpoints` | Private Endpoints with DNS zone associations |
| `azure_get_dns_zones` | DNS zones (public/private) and record sets |
