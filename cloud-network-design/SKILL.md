---
name: cloud-network-design
description: "Use for vendor-neutral cloud network design, topology comparison, and architecture selection across AWS, Azure, and GCP. Owns the cross-cloud reasoning that survives any one provider: virtual-network scoping (AWS VPC regional vs Azure VNet regional vs GCP VPC global), CIDR allocation strategy across on-prem and multiple clouds, subnet architecture and reserved-IP deltas, security-control model comparison (stateful Security Groups / NSGs / GCP firewall rules vs stateless NACLs, and the org-to-instance layering), transit-hub selection (Transit Gateway vs Virtual WAN vs Network Connectivity Center), hub-and-spoke vs multi-account landing-zone patterns, hybrid connectivity selection (VPN vs Direct Connect / ExpressRoute / Cloud Interconnect, BGP design), private service access comparison (PrivateLink vs Private Link vs Private Service Connect), centralised egress control, and multi-cloud connectivity patterns (VPN mesh, colo interconnect, cloud exchange). References provider-comparison.md, connectivity-and-transit.md, design-and-cidr.md. Triggers include \"cloud network design\", \"cloud networking\", \"VPC design\", \"VNet design\", \"VPC vs VNet\", \"multi-cloud networking\", \"hybrid cloud connectivity\", \"CIDR planning across clouds\", \"Transit Gateway vs vWAN\", \"transit hub selection\", \"security groups vs NSGs\", \"stateful vs stateless cloud security\", \"PrivateLink vs Private Link vs PSC\", \"private service access\", \"cloud egress control\", \"hub and spoke cloud\", \"landing zone network\", \"VPC peering vs transit gateway\", \"Direct Connect vs ExpressRoute vs Cloud Interconnect\", \"multi-cloud connectivity pattern\", \"cloud CIDR strategy\", \"non-overlapping address space\". This skill owns the cross-cloud design and selection layer only. For read-only per-cloud network configuration audit see aws-networking-audit, azure-networking-audit, and gcp-networking-audit; for which cloud to use at all and cross-cloud strategy see cloud-platform-selection; for cloud DNS see the DNS family; for cloud load balancing see the load-balancer family; for cloud security posture and CNAPP see cloud-security-posture; for on-prem routing and switching design see routing-switching-design."
license: MIT
metadata:
  version: 1.0.0
---

# Cloud network design and topology selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: cloud-network-design]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for cloud network *design*: choosing a virtual-network topology, a CIDR strategy, a security-control model, a transit architecture, and a hybrid-connectivity approach across AWS, Azure, and GCP before any provider console is touched. It owns the cross-cloud reasoning that outlasts a single provider or a single service rename: how to allocate non-overlapping address space across on-prem and multiple clouds, when to reach for a transit hub instead of peering, how the three providers' security-group and firewall models actually differ, and which private-service-access construct fits a given exposure requirement. Per-provider configuration audit and the rest of each provider's operational surface live in sibling skills; the depth here is the architecture choice that spans all three.

## When to use

- Comparing AWS VPC vs Azure VNet vs GCP VPC architecture, scoping, and subnet models for a design.
- Planning a CIDR allocation strategy across on-premises and one or more clouds so nothing overlaps and peering stays possible.
- Choosing a transit architecture: Transit Gateway vs Virtual WAN vs Network Connectivity Center, or transit hub vs point-to-point peering at scale.
- Selecting a hybrid-connectivity approach (VPN vs Direct Connect / ExpressRoute / Cloud Interconnect) and designing the BGP route exchange.
- Comparing the security-control models (stateful Security Groups / NSGs / GCP firewall rules vs stateless NACLs) and designing the org-to-instance layering.
- Choosing a private-service-access construct (PrivateLink / Private Link / Private Service Connect) for exposing a service without full network connectivity.
- Designing centralised internet egress (managed NAT plus firewall) and a hub-and-spoke or multi-account landing-zone layout.
- Planning multi-cloud connectivity: VPN mesh vs colo interconnect vs cloud-exchange virtual cross-connect.

## When not to use

- **Read-only audit of a live per-cloud network's configuration** (Security Group / NSG / firewall-rule review, route-table validation, flow-log forensics, connectivity posture): use `aws-networking-audit` (and its Azure and GCP parity siblings landing in this family). This skill chooses the topology and controls; those audit the running network against them.
- **Which cloud to use at all, and cross-cloud strategy** (AWS vs Azure vs GCP selection criteria, Well-Architected cross-cloud, migration 7 Rs, FinOps practice): use `cloud-platform-selection`. This skill designs the network *within and between* chosen clouds; that one decides the clouds.
- **The rest of a provider's operational surface** (compute, serverless, storage, database, messaging, IAM, observability): use `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops`. Those cross-refer here for cloud-network depth.
- **Cloud DNS design and operations** (zones, records, split-horizon, private resolvers): use `dns-network-ops` for the design layer and `route53-dns-ops` / `azure-dns-ops` / `cloudflare-dns-ops` for the per-provider surface.
- **Cloud load balancing** (ALB / NLB / Application Gateway / Cloud Load Balancing selection and configuration): use `load-balancer-selection` and `aws-load-balancing`.
- **Cloud security posture, CSPM, and CNAPP** (control-catalogue mapping, public-exposure findings, misconfiguration scanning): use `cloud-security-posture`, `aws-security-hub`, or `defender-cloud`. This skill designs the network plane; those grade its posture.
- **On-prem campus and data-centre routing and switching design**: use `routing-switching-design`; for cloud-edge zero-trust and SASE/SSE, use `sase-sse` (and `prisma-access` / `zscaler`).

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Provider comparison | VPC vs VNet vs GCP VPC scope and subnets, reserved-IP deltas, security-control models, flow-log comparison, shared-responsibility split | `references/provider-comparison.md` |
| Connectivity + transit | transit-hub selection (TGW / vWAN / NCC), hybrid connectivity (VPN vs dedicated line, BGP design), private service access (PrivateLink / Private Link / PSC) | `references/connectivity-and-transit.md` |
| Design + CIDR | non-overlapping CIDR allocation, VPC design patterns (single / hub-and-spoke / landing zone), subnet sizing, egress control, security-group hygiene, network-cost awareness, common pitfalls | `references/design-and-cidr.md` |

## Core model

- **The virtual network is customer-designed; the fabric is provider-run.** Under the shared-responsibility split, the provider owns the physical network, backbone, and control plane; the customer owns CIDR allocation, subnet and route design, the security-group and firewall rules, hybrid connectivity, and flow-log analysis. Design decisions live entirely on the customer side.
- **Scope is the first cross-cloud difference.** An AWS VPC and an Azure VNet are regional with AZ-scoped (AWS) or region-spanning (Azure) subnets; a GCP VPC is global with regional subnets, so cross-region communication is native in GCP but needs peering or a transit hub in AWS and Azure. This one fact reshapes multi-region design.
- **Plan CIDR before the first network exists.** Overlapping address space is the most common and most expensive multi-cloud mistake: it blocks peering and forces NAT or re-IP after the fact. Allocate non-overlapping RFC 1918 ranges across on-prem and every cloud, and record them in a central IPAM.
- **Peering is non-transitive; use a transit hub at scale.** VPC/VNet peering is O(n^2) and does not chain. Beyond a handful of networks, a Transit Gateway / Virtual WAN / Network Connectivity Center hub with route-table segmentation is the design, not an optimisation.
- **Prefer private service access over broad connectivity.** PrivateLink / Private Link / Private Service Connect expose a single endpoint instead of a whole network, shrinking blast radius; reach for them before opening peering for service-to-service exposure.
- **Security is layered, not a single security group.** Org policy, managed network firewall, subnet controls, and instance-level groups each catch what the others miss; a design that relies solely on security groups is under-built.

## Reference router

- Cross-cloud construct comparison, security-control models, flow-log deltas, shared-responsibility detail → `references/provider-comparison.md`.
- Transit-hub selection, hybrid connectivity and BGP, private service access → `references/connectivity-and-transit.md`.
- CIDR strategy, VPC design patterns, subnet sizing, egress, security-group hygiene, network-cost awareness, pitfalls → `references/design-and-cidr.md`.

## Cross-references

- `aws-networking-audit`: read-only AWS VPC configuration audit. This skill designs the AWS network; that audits the running one and owns AWS networking depth. Its `references/design-and-cost.md` is the shared home for AWS VPC design and networking cost.
- Forward placeholders (landing in this same cloud-network family): `azure-networking-audit` and `gcp-networking-audit`, the read-only Azure VNet / GCP VPC configuration-audit siblings of `aws-networking-audit`. They become live cross-refs once adopted.
- `cloud-platform-selection`: cross-cloud strategy and which-cloud selection. Pair when a network design raises a strategic question (should this workload be on this cloud at all, multi-cloud egress-cost analysis, lock-in).
- `aws-cloud-ops` / `azure-cloud-ops` / `gcp-cloud-ops`: the rest of each provider's operational surface; they cross-refer here for cloud-network depth.
- `dns-network-ops` (+ `route53-dns-ops` / `azure-dns-ops` / `cloudflare-dns-ops`): cloud DNS design and operations, referenced here in prose for split-horizon and private resolution, not duplicated.
- `load-balancer-selection` / `aws-load-balancing`: cloud load-balancer selection and configuration.
- `cloud-security-posture` / `aws-security-hub` / `defender-cloud`: cloud security posture and CNAPP; this skill designs the network plane, those grade its posture.
- `routing-switching-design`: on-prem campus and data-centre design; the on-prem counterpart to this skill.
- `sase-sse` / `prisma-access` / `zscaler`: cloud-edge zero-trust and SASE/SSE, the secure-access layer in front of cloud networks.
- `secrets-hygiene`: provider API credentials and VPN pre-shared keys for any hybrid design live in the secret store, never in a template.

## Red flags

- About to allocate cloud CIDRs without checking they do not overlap on-prem or each other, foreclosing peering before the first workload lands.
- About to design a 10-plus-VPC estate on point-to-point peering instead of a transit hub, accepting an O(n^2) mesh that will not scale.
- About to open a full peering connection just to reach one service, when PrivateLink / Private Link / PSC would expose only an endpoint.
- About to treat AWS inter-AZ data transfer as free (it is charged both directions), spreading chatty services across AZs and paying for it.
- About to rely on security groups alone, skipping the org, network-firewall, and subnet layers.
- About to leave SSH (22) or RDP (3389) open to `0.0.0.0/0` instead of a bastion or session-manager path.
- About to run a single NAT gateway in one AZ as the egress for a multi-AZ design, creating a single point of failure and a bandwidth choke.
- About to assume a GCP global VPC removes the need for regional NAT and firewall design (subnets, NAT, and firewall rules are still regional).

## Bottom line

Cloud network design is the cross-cloud layer: scope, CIDR, transit, connectivity, and the security-control model, chosen before any provider console is opened. Get the address plan and the transit decision right first, layer the security controls, and route per-provider audit, cloud selection, DNS, load balancing, and posture to their owning skills.
