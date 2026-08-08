# Data-centre architecture selection

This reference owns the data-centre design surface: fabric topology selection, underlay routing-protocol choice, ECMP design, VXLAN MTU, and VRF / segmentation design. It is design-time guidance. The EVPN-VXLAN control-plane and data-plane *troubleshooting* (silent hosts, missing route types, anycast-gateway mismatch, DF election) belongs to `evpn-vxlan-fabric`; underlay protocol diagnostics belong to `bgp-analysis` and `igp-routing-analysis`.

## Why the data centre is different

Campus traffic is mostly north-south (client to server, server to internet). Data-centre traffic is mostly east-west (server to server, tier to tier, replication, storage). A topology that bounds north-south latency well can be terrible for east-west, which is why the data centre converged on the spine-leaf fabric: every leaf is one hop from every other leaf through the spine, so east-west latency and bandwidth are uniform and predictable.

## Fabric topology selection

| Topology | Scale | Description | When to choose |
|---|---|---|---|
| Spine-leaf (2-tier) | up to ~48 leaf pairs | Every leaf connects to every spine; no leaf-to-leaf or spine-to-spine links; VXLAN/EVPN overlay on an eBGP underlay | The default modern DC fabric; uniform east-west, horizontal scale by adding leaves |
| Super-spine (3-tier) | beyond a single spine layer | A super-spine tier interconnects multiple spine-leaf pods | When one pod's spine count is exhausted; scale by adding pods |
| Multi-site DCI | multiple fabrics | Border gateways interconnect separate fabrics with controlled L2/L3 extension | Two or more data centres needing workload mobility and disaster recovery |
| ACI | policy-driven single fabric | Intent-based fabric with a controller and an endpoint-group / contract policy model | When the operating model is policy-and-controller-driven and the team wants intent abstraction over CLI |

### Choosing between them

- **Default to two-tier spine-leaf.** It is the right answer for the large majority of data centres: predictable east-west performance, scale by adding leaves, no STP in the fabric.
- **Add a super-spine only when a pod outgrows its spine layer.** Do not build three tiers prematurely; the extra tier adds latency and cost for scale you may not reach.
- **Choose multi-site DCI when workloads must move between data centres** or survive the loss of one; design the L2 extension deliberately (border gateways, Type-5 re-origination) and never stretch a VLAN by accident.
- **Choose ACI when the operating model wants policy abstraction and a single point of intent**, and the team is prepared to operate the controller; otherwise a standards-based EVPN-VXLAN fabric on NX-OS, EOS, or Junos is simpler to reason about.

## Underlay routing-protocol choice

The underlay carries reachability between the loopbacks that the VXLAN tunnels and the EVPN control plane ride on. The choice is a scaling decision.

| Underlay | Best for | Trade-offs |
|---|---|---|
| eBGP | Modern spine-leaf (the recommended default) | Explicit policy control, AS-path loop prevention, scales cleanly; each switch gets an AS, more config but more control |
| OSPF | Smaller fabrics that value simplicity | Easy to stand up; LSDB size and flooding become a concern at large scale; no built-in policy |
| IS-IS | Very large fabrics | Fast convergence, avoids LSDB flooding storms; the preferred underlay on some NX-OS designs |

### Design notes

- **Pick eBGP unless there is a reason not to.** It is the industry default for spine-leaf because policy and loop prevention come for free and it scales horizontally without flooding concerns. The peering design depth is in `bgp-analysis`; the choice is made here.
- **Put BFD on every fabric link.** Without it, failover waits on protocol hold timers (seconds); with hardware-offloaded BFD, failure detection is sub-second. This applies whatever the underlay.
- **Use point-to-point link types** so there is no designated-router election delay on fabric links (relevant when the underlay is OSPF).
- The EVPN *overlay* control plane (BGP-EVPN, route types 1 to 5, symmetric IRB, anycast gateway) is selected here as part of choosing spine-leaf, but its configuration and troubleshooting live in `evpn-vxlan-fabric`.

## ECMP design

Equal-cost multi-path is what makes a spine-leaf fabric use every spine.

- **Size maximum-paths to the spine count** so a leaf load-balances across all spines; a fabric with four spines needs at least four ECMP paths configured, and large fabrics commonly run 64 to 128.
- **Forwarding is per-flow, hash-based** on a 5-tuple (source / destination IP, protocol, source / destination port), so a single flow always takes one path and ordering is preserved; load spreads across flows, not within one.
- **Prefer resilient hashing** where available so that adding or removing a path reshuffles the minimum number of flows rather than rehashing everything.

## VXLAN MTU

VXLAN encapsulation adds 50 bytes (outer Ethernet 14 + outer IP 20 + outer UDP 8 + VXLAN header 8). If the fabric MTU is not raised, encapsulated frames are fragmented or dropped.

- **Raise fabric-link MTU to accommodate the overhead**, typically to 9214 (jumbo) so a full 9000-byte payload still fits after encapsulation.
- **Set it consistently on every fabric link and VTEP.** A single link left at 1500 silently breaks large flows while small packets pass, which is a classic intermittent fabric fault (diagnosed in `evpn-vxlan-fabric`).

## VRF and segmentation design

VRFs create isolated routing tables on shared hardware; in a fabric they are how tenants and security zones are kept apart.

- **Each VRF has its own RIB and FIB**, and traffic cannot cross a VRF boundary without explicit route leaking or a firewall. This is the design primitive for multi-tenancy, compliance isolation, and management separation.
- **VRF-lite** is segmentation without MPLS labels: simple, common in enterprise data centres and campuses that need a few isolated routing domains.
- **In an EVPN fabric, each tenant VRF maps to an L3 VNI**, and inter-subnet routing within a tenant happens through that L3 VNI with an anycast gateway on every leaf. The mapping is a design decision; the running-state troubleshooting is in `evpn-vxlan-fabric`.
- **Decide route leaking deliberately.** Shared services (DNS, monitoring, backup) often need reachability from many tenant VRFs; design the leaking (or a shared-services VRF behind a firewall) rather than letting it grow ad hoc.

## Selection checklist

- Confirm the traffic is east-west-dominant before committing to spine-leaf; a small server room with north-south traffic may not need a fabric at all.
- Choose two-tier first; add super-spine or multi-site only when scale or resilience demands it.
- Default the underlay to eBGP with BFD; raise MTU for VXLAN before the first VTEP comes up.
- Size ECMP to the spine count from day one.
- Map tenants and zones to VRFs up front; retrofitting segmentation into a flat fabric is painful.
- Choose the platform (NX-OS, EOS, Junos QFX, or a DPU-capable leaf) alongside the fabric, per `references/platform-selection.md`.
