# Cross-cloud provider comparison

The constructs that differ across AWS, Azure, and GCP, and the shared-responsibility split that decides who designs what. Load this for comparison and "how does X differ across clouds" questions.

## Shared-responsibility model for networking

**Provider owns**: physical network (routers, switches, cabling, data-centre interconnects), the global backbone and inter-region links, edge DDoS protection, the virtual-network overlay infrastructure, and control-plane/API availability.

**Customer owns**: virtual-network design and CIDR allocation, subnet architecture and routing, the security groups / NACLs / NSGs / firewall rules, hybrid connectivity (VPN, Direct Connect, ExpressRoute, Interconnect), DNS configuration and resolution, application-level (TLS) encryption, and network monitoring plus flow-log analysis.

**Shared**: encryption in transit (provider encrypts the backbone; customer configures TLS), DDoS mitigation (provider absorbs volumetric; customer configures WAF rules), and patching (provider patches infrastructure; customer patches any network virtual appliances they run).

Every design decision in this skill sits on the customer side of that line.

## Virtual-network fundamentals

| Aspect | AWS VPC | Azure VNet | GCP VPC |
|---|---|---|---|
| Scope | Regional | Regional | Global |
| Subnets | AZ-scoped | Regional (AZ-aware) | Regional |
| Reserved IPs per subnet | 5 | 5 | 4 |
| Additional address space | Up to 5 secondary CIDRs | Multiple address spaces | Multiple subnets per VPC |
| IPv6 | Dual-stack | Dual-stack | Dual-stack |
| Default isolation | VPC isolated | VNet isolated | VPC isolated |
| Cross-region reach | Peering or Transit Gateway | Peering or Virtual WAN | Native (global VPC) |

The scope row is the one that reshapes multi-region design: a GCP VPC is global, so resources in different regions of one VPC communicate without peering (firewall rules and NAT are still regional); AWS and Azure need a peering or transit hub to cross regions.

### Reserved IP addresses per subnet

- **AWS** (5): `.0` network, `.1` router, `.2` DNS, `.3` future use, `.255` broadcast.
- **Azure** (5): `.0` network, `.1` gateway, `.2`-`.3` DNS, `.255` broadcast.
- **GCP** (4): `.0` network, `.1` gateway, second-to-last broadcast, last reserved.

### AZ distribution

- **AWS**: subnets are AZ-scoped; create matching subnets in at least two AZs for HA.
- **Azure**: subnets span all AZs in the region; zone redundancy comes from zone-redundant resources, not subnet placement.
- **GCP**: subnets are regional; VMs in different zones of one subnet talk directly.

## Security-control models

| Layer | AWS | Azure | GCP |
|---|---|---|---|
| Instance-level (stateful) | Security Groups | NSGs at NIC | VPC Firewall Rules |
| Subnet-level | NACLs (stateless) | NSGs at subnet | VPC Firewall Rules (tag-based) |
| Organisation-level | Firewall Manager | Azure Policy + Firewall Manager | Hierarchical Firewall Policies |
| Managed firewall | AWS Network Firewall | Azure Firewall (Standard/Premium) | Cloud Armor (L7) |
| WAF | AWS WAF | Azure WAF (AFD / App Gateway) | Cloud Armor |
| DDoS | Shield Standard/Advanced | DDoS Protection Standard | Cloud Armor (always-on) |
| Group abstraction | SG references | Application Security Groups | Network tags / service accounts |

### Stateful vs stateless

- **Stateful** (Security Groups, NSGs, GCP firewall rules): connection state is tracked, so allowed outbound traffic gets its return automatically; rules are allow-only (AWS SG, GCP) or allow/deny (Azure NSG); applied per instance or NIC; can reference other groups (AWS SG references, Azure ASGs) instead of IPs.
- **Stateless** (AWS NACLs): each packet is evaluated independently, so both directions must be allowed explicitly; numbered rules, first match wins; applied per subnet (AWS only; Azure and GCP have no direct equivalent); support allow and deny. Use for coarse subnet-level blocking.

Confusing the two is a classic source of "return traffic mysteriously blocked" incidents.

### Layered security

```
Organisation:   AWS SCPs / Azure Policy / GCP Org Policies
Network:        AWS Network Firewall / Azure Firewall / Cloud Armor
Subnet:         AWS NACLs / Azure NSG on subnet / GCP hierarchical FW
Instance:       AWS Security Groups / Azure NSG on NIC / GCP FW rules (tags)
Application:    host firewall (iptables / Windows FW) / WAF
```

Design at multiple layers; never rely on security groups alone.

## Flow-log comparison

| Aspect | AWS VPC Flow Logs | Azure NSG Flow Logs | GCP VPC Flow Logs |
|---|---|---|---|
| Scope | VPC, subnet, or ENI | NSG (subnet or NIC) | VPC, subnet, or VM |
| Destination | CloudWatch, S3, Firehose | Storage Account, Log Analytics | Cloud Logging, BigQuery, Pub/Sub |
| Default aggregation | 10-minute windows | 1-minute windows | 5-second to 15-minute (configurable) |
| Sampling | All flows | All flows | Configurable rate |
| Extra fields | src/dst, ports, protocol, action, bytes | + tuple hash | + RTT samples |

Flow logs serve security forensics (unauthorised access, lateral movement), traffic analysis for design optimisation, data-transfer cost hunting, compliance evidence, and connectivity troubleshooting. The per-cloud audit siblings (`aws-networking-audit` and its Azure/GCP parity siblings) own the read-only forensic analysis of these logs; this skill owns the design decision of what to capture and where to send it.
