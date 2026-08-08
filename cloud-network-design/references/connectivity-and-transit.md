# Connectivity and transit architecture

Transit-hub selection, hybrid connectivity, and private service access across the three clouds. Load this for "how do I connect these" and "which transit service" questions.

## Transit architecture

| Aspect | AWS | Azure | GCP |
|---|---|---|---|
| Hub service | Transit Gateway (TGW) | Virtual WAN (vWAN) | Network Connectivity Center (NCC) |
| Max attachments | 5,000 per TGW | Varies by hub type | Hub + spokes model |
| Routing | TGW route tables | vWAN routing policies | NCC route tables |
| Segmentation | Multiple route tables | Routing-intent policies | Per-spoke export filters |
| Cross-region | TGW peering (non-transitive) | Multi-hub vWAN | Native (global VPC) |
| Firewall integration | TGW + Network Firewall | Secured Virtual Hub | NCC + Cloud Armor |

The design rule: **VPC/VNet peering is non-transitive and O(n^2)**. Below a handful of networks, peering is fine. At ten or more, or wherever an environment will grow, start with a transit hub and segment with route tables (Dev / Staging / Prod isolation). The hub also gives you a single place for centralised routing, security inspection, and logging.

### Per-hub notes

- **AWS Transit Gateway**: regional hub for VPCs, VPNs, and Direct Connect; route tables provide segmentation; inter-region is TGW peering (non-transitive, static routes); priced per-attachment-hour plus per-GB processed.
- **Azure Virtual WAN**: managed hub-and-spoke at scale; hub types Basic (S2S VPN only) and Standard (VPN + ExpressRoute + P2S + Azure Firewall); a Secured Virtual Hub adds an integrated Azure Firewall; routing-intent can force all traffic through it; multi-hub auto-routes hub-to-hub.
- **GCP Network Connectivity Center**: hub-and-spoke for GCP and hybrid; spoke types are VPN tunnels, Interconnect VLANs, SD-WAN appliances, and VPC networks; VPC spokes give transitive routing between VPCs via the hub; export filters control route propagation.

## Hybrid connectivity

| Aspect | VPN (IPsec) | Dedicated line |
|---|---|---|
| Setup time | Minutes | Weeks to months |
| Bandwidth | 1-10 Gbps | 1-100 Gbps |
| Latency | Variable (internet path) | Consistent (private path) |
| Encryption | Always (IPsec) | Optional (MACsec on DX / ER) |
| Cost | Low (pay per hour) | High (port + cross-connect fees) |
| Redundancy | Easy (multiple tunnels) | Requires redundant circuits |
| Use case | Dev/test, low-bandwidth, backup | Production, latency-sensitive, high-bandwidth |

Per-provider dedicated options: AWS Direct Connect (1/10/100G), Azure ExpressRoute (50M-100G), GCP Cloud Interconnect (10/100G). VPN throughput: AWS site-to-site ~1.25 Gbps, Azure VPN Gateway 1-10 Gbps, GCP HA VPN 3 Gbps per tunnel.

### BGP design for hybrid

- Use BGP for dynamic route exchange between on-prem and cloud rather than static routes.
- Advertise summary routes from cloud to on-prem; do not leak individual /24s.
- Use AS-path prepending to steer traffic across redundant connections.
- Set BGP hold timers and enable BFD for fast failover.
- Document the ASNs: on-prem ASN, cloud provider ASNs, and the private ASN ranges in use.

For the on-prem BGP peering itself (neighbour states, policy, path selection), `bgp-analysis` owns the diagnostics; for cloud DNS in hybrid environments (split-horizon, conditional forwarding, private zones) the DNS family owns the design and per-provider surface. This reference covers the cloud-side selection only.

## Private service access

| Aspect | AWS PrivateLink | Azure Private Link | GCP Private Service Connect |
|---|---|---|---|
| Consumer | Interface Endpoint (ENI) | Private Endpoint (NIC) | Consumer Endpoint (forwarding rule) |
| Producer | NLB-backed service | Standard LB-backed service | ILB-backed service |
| DNS | VPC-local to private IP | Private DNS Zone | Service Directory integration |
| Cross-account/project | Yes | Yes | Yes |
| Cross-region | Yes | Yes | Yes |
| For managed services | Gateway (S3/DDB) + interface endpoints | Private endpoints for PaaS | PSC for Google APIs |

Prefer private service access over peering for exposing a service: the consumer sees only a private endpoint, not the provider's whole network, which shrinks the blast radius and lets the provider gate access by approval workflow.

## Multi-cloud connectivity patterns

- **VPN mesh**: IPsec tunnels between each cloud's VPN gateway (AWS VPN to Azure VPN Gateway, AWS VPN to GCP HA VPN, and so on); BGP-based dynamic routing over static; bandwidth capped by tunnel capacity (1-10 Gbps). Use for low-bandwidth, cost-sensitive links.
- **Dedicated interconnect via colo**: establish presence at a colocation facility (Equinix, Megaport, etc.); Direct Connect, ExpressRoute, and Cloud Interconnect all terminate there; cross-connect between providers at the colo for low-latency, high-bandwidth links. Use for production, latency-sensitive workloads.
- **Cloud exchange / virtual interconnect**: a managed fabric (Megaport, Equinix Fabric) providing virtual cross-connects between providers without a physical colo presence; pay-per-use with flexible bandwidth. Use for agile multi-cloud without long-term infrastructure commitment.
