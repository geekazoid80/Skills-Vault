# Design, CIDR, and cost

Address planning, VPC layout patterns, subnet sizing, egress, security-group hygiene, network-cost awareness, and the pitfalls that recur. Load this for "how should I lay this out" questions.

## CIDR planning

Overlapping address space is the most common and most expensive multi-cloud networking mistake: it blocks VPC/VNet peering and complicates routing, and fixing it after the fact needs NAT or re-IP'ing workloads. Plan before the first network exists.

- Allocate non-overlapping ranges across every environment (on-prem, AWS, Azure, GCP).
- Use RFC 1918 space; `10.0.0.0/8` gives the largest room.
- Reserve for growth, but do not over-allocate: a `/20` per VPC is often plenty; a `/16` each burns the plan fast.
- Record every allocation in a central IPAM.

Example allocation:

```
On-premises:  10.0.0.0/8
AWS:          172.16.0.0/12
Azure:        192.168.0.0/16
GCP:          100.64.0.0/10   (CGN range, or remaining 172.x)
```

## VPC design patterns

### Single VPC (simple)

One VPC with public (IGW-routed), private (NAT-routed), and data (no internet route) subnet tiers spread across two AZs. Use for a single application, a small team, limited blast-radius needs.

### Multi-VPC hub-and-spoke

A hub VPC holding the transit gateway / vWAN / NCC hub plus shared firewall, NAT, DNS, and VPN/DX termination; spoke VPCs for Production, Staging, Development, and Shared Services connect only to the hub. Use when multiple environments or teams need isolation with shared connectivity.

### Multi-account landing zone

Separate accounts/subscriptions/projects: a management account (org policy, centralised logging), a network account (transit gateway, Direct Connect / ExpressRoute, central DNS), production account(s) with VPCs attached to the hub, and non-production account(s) isolated via hub route tables. Use at enterprise scale for team isolation, billing separation, and security boundaries.

## Subnet sizing

| Purpose | Recommended size | Notes |
|---|---|---|
| Public (load balancers, NAT GW) | /24 | Keep small; minimise public exposure |
| Private (application servers) | /22 - /24 | Size to expected instance count |
| Data (databases, caches) | /24 | Few instances, high isolation |
| Container / K8s pods | /20 - /18 | Pods consume IPs rapidly |
| Management (bastion, monitoring) | /26 - /24 | Small, tightly controlled |

## Egress control

Centralise internet egress through managed NAT plus firewall so outbound traffic is logged, filtered, and threat-inspected in one place:

- **AWS**: NAT Gateway per AZ, optionally fronted by AWS Network Firewall.
- **Azure**: Azure Firewall, with all subnets force-tunnelled to it via UDRs.
- **GCP**: Cloud NAT per region.

One NAT gateway in a single AZ is a single point of failure and a bandwidth choke; deploy one per AZ.

## Security-group hygiene

- Avoid `0.0.0.0/0` in source or destination rules.
- Reference security groups (AWS), ASGs (Azure), or network tags (GCP) instead of raw IPs.
- Review and remove unused rules on a schedule (quarterly).
- Use service tags (Azure) or managed prefix lists (AWS) for cloud-service IP ranges.
- Least privilege: only the required ports and protocols.

## Network-cost awareness

| Cost factor | AWS | Azure | GCP |
|---|---|---|---|
| Inter-AZ traffic | Charged (both directions) | Free (same region) | Free (same region) |
| Inter-region traffic | Charged | Charged | Charged |
| NAT | Per-hour + per-GB | Included in Azure Firewall | Per-hour + per-GB |
| Transit hub | Per-attachment + per-GB | Per-hub + per-GB | Per-spoke + per-GB |
| VPN | Per-hour + per-GB | Per-hour + per-GB | Per-hour + per-GB |

The one that bites unexpectedly: **AWS charges for inter-AZ data transfer** (about $0.01/GB each direction), so architectures that spread chatty services across AZs pay for every cross-AZ hop. Azure and GCP do not charge for intra-region cross-AZ traffic. This is network-plane cost awareness for design trade-offs; deeper per-provider cost engineering and FinOps live in `cloud-platform-selection` and the per-provider cloud-ops skills, and AWS VPC networking cost specifically lives in `aws-networking-audit`'s `references/design-and-cost.md`.

## Common pitfalls

1. **Overlapping CIDRs**: the top multi-cloud mistake; plan before deploying the first VPC.
2. **Ignoring AWS inter-AZ transfer cost**: co-locate tightly coupled services or use placement groups.
3. **Confusing stateful vs stateless security**: return traffic silently blocked when NACL and Security Group models are mixed up.
4. **Not using transit hubs at scale**: peering is non-transitive; adopt TGW/vWAN/NCC from the start for any estate that will grow.
5. **Exposed management ports**: SSH (22) and RDP (3389) open to `0.0.0.0/0` is the most exploited misconfiguration; use bastions, SSM Session Manager, or Azure Bastion.
6. **NAT gateway as a bottleneck**: one per AZ for HA, not a single shared instance.
7. **GCP global-VPC misconception**: the VPC is global but subnets, NAT, and firewall rules are all still regional.
