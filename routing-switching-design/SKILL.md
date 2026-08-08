---
name: routing-switching-design
description: "Use for vendor-neutral routing and switching design, architecture selection, and platform comparison across campus and data-centre networks. Owns the decisions that survive any one vendor or release: campus topology selection (collapsed core, three-tier, routed access, SD-Access fabric), data-centre topology selection (spine-leaf, super-spine, multi-site DCI, ACI), VLAN design strategy and broadcast-domain sizing, STP variant selection and root placement, first-hop gateway redundancy selection (HSRP / VRRP / GLBP), switching redundancy selection (StackWise, StackWise Virtual, vPC, MLAG, EVPN multihoming / ESI-LAG), underlay routing-protocol choice (eBGP vs OSPF vs IS-IS), ECMP and VXLAN MTU design, VRF and segmentation design, and vendor platform selection (Cisco IOS-XE, Cisco NX-OS, Arista EOS, Aruba AOS-CX, Juniper Junos, Cisco Meraki). The organising idea is choosing the right topology, redundancy model, and platform for a given scale and traffic pattern, north-south versus east-west, before any configuration. References campus-architecture.md, switching-and-redundancy.md, datacenter-architecture.md, platform-selection.md. Triggers include \"routing and switching design\", \"campus network design\", \"three-tier vs collapsed core\", \"spine-leaf vs three-tier\", \"VLAN design\", \"VLAN strategy\", \"STP design\", \"spanning-tree variant\", \"RSTP vs MST\", \"root bridge placement\", \"first-hop redundancy\", \"HSRP vs VRRP\", \"StackWise vs vPC\", \"MLAG vs vPC\", \"switch stacking\", \"data centre fabric design\", \"spine-leaf design\", \"underlay protocol choice\", \"eBGP vs OSPF underlay\", \"ECMP design\", \"VRF design\", \"network segmentation design\", \"VXLAN MTU\", \"SD-Access\", \"routed access layer\", \"campus vs data centre\", \"which switch platform\", \"Cisco vs Arista vs Juniper\", \"Catalyst vs Nexus\", \"Aruba AOS-CX\", \"Meraki vs Catalyst\", \"L2 vs L3 boundary\". For protocol *troubleshooting and change review* see igp-routing-analysis (OSPF / EIGRP / IS-IS diagnostics) and bgp-analysis (BGP diagnostics); for EVPN-VXLAN fabric *troubleshooting* see evpn-vxlan-fabric; for diagnose-first multi-vendor network operations and the production-change response contract see multi-vendor-network-ops. This skill owns the design and selection layer; those own the diagnostics."
license: MIT
metadata:
  version: 1.0.0
---

# Routing and switching design and platform selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: routing-switching-design]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for routing and switching *design*: choosing a topology, a redundancy model, a segmentation strategy, and a platform before any configuration is written. It owns the reasoning that survives a vendor swap or a release upgrade: how to size and bound Layer 2, when a campus should be three-tier versus collapsed core versus routed access, when a data centre should be spine-leaf versus three-tier, which redundancy technology fits which layer, and which vendor platform fits a given scale and operating model. Per-vendor command syntax and protocol-level troubleshooting live in sibling skills; the depth here is the architecture choice that outlasts them.

## When to use

- Designing a campus network and choosing the topology (collapsed core, three-tier, routed access, SD-Access fabric) for a given endpoint count and growth path.
- Designing a data-centre network and choosing the fabric (spine-leaf, super-spine, multi-site DCI, ACI) and the underlay routing protocol.
- Setting a VLAN strategy: function-based segmentation, broadcast-domain sizing, native-VLAN and trunk-pruning hygiene.
- Choosing a spanning-tree variant (RSTP / Rapid PVST+ / MST) and placing root bridges, or deciding to eliminate STP with a routed design.
- Selecting a first-hop gateway redundancy protocol (HSRP / VRRP / GLBP) and a switching redundancy model (StackWise / StackWise Virtual / vPC / MLAG / ESI-LAG).
- Designing VRF-based segmentation and route leaking, ECMP fan-out, and VXLAN MTU.
- Comparing and selecting a vendor platform (Cisco IOS-XE, Cisco NX-OS, Arista EOS, Aruba AOS-CX, Juniper Junos, Cisco Meraki) against a scale, feature, and operating-model requirement.

## When not to use

- **OSPF / EIGRP / IS-IS troubleshooting, change review, or protocol-level design** (adjacency not forming, area design depth, redistribution loops, LSA / LSP walking): use `igp-routing-analysis`. This skill chooses *whether* the underlay is OSPF or IS-IS; that skill diagnoses and tunes it.
- **BGP troubleshooting, peering policy review, or path-selection analysis** (neighbour stuck in Idle, route-reflector design depth, community / local-pref policy): use `bgp-analysis`. This skill chooses eBGP as the underlay; that skill makes it work.
- **EVPN-VXLAN fabric troubleshooting** (silent host, VTEP unreachable, missing route type 2 / 3 / 5, anycast-gateway mismatch, DF election): use `evpn-vxlan-fabric`. This skill selects spine-leaf and the underlay; that skill audits and fixes the running fabric.
- **Diagnose-first production operations across mixed vendors**, including the 9-element production-change response contract (assumptions / risk / evidence / pre-checks / execution / post-checks / rollback / escalation): use `multi-vendor-network-ops`. This skill is design-time; that skill is operate-time.
- **Per-vendor CLI syntax and configuration** (the exact Catalyst, Nexus, Arista, Aruba, Junos, or Meraki commands): the per-vendor command surface is refer-only here; `multi-vendor-network-ops` carries the operating commands.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Campus architecture | collapsed core vs three-tier vs routed access vs SD-Access, layer roles, scale tiers, root placement, first-hop redundancy | `references/campus-architecture.md` |
| Switching + redundancy | VLAN strategy, broadcast-domain sizing, STP variant + guards, StackWise / vPC / MLAG / ESI-LAG selection | `references/switching-and-redundancy.md` |
| Data-centre architecture | spine-leaf vs super-spine vs multi-site vs ACI, underlay protocol choice, ECMP, VXLAN MTU, VRF / segmentation design | `references/datacenter-architecture.md` |
| Platform selection | which vendor and platform family, feature parity, redundancy and management model, API / telemetry | `references/platform-selection.md` |

## Core model (condensed)

**Bound Layer 2, route everything else.** A broadcast domain is a failure domain. Keep VLANs small (rule of thumb: under ~500 hosts), push the L3 boundary as close to the edge as the design allows, and never stretch a VLAN across a WAN by trunking; extend Layer 2 between sites only with a deliberate overlay (VXLAN), never by accident. The modern campus trend is the routed access layer, which moves the L3 boundary to the access switch and removes STP from the data path entirely.

**STP is a safety net, not an architecture.** Design so that spanning tree has nothing to do in steady state. Choose a rapid variant (RSTP, Rapid PVST+, or MST), place root bridges explicitly at the distribution layer with set priorities, and protect the topology with PortFast plus BPDU Guard on edge ports and Root Guard on uplinks. In a data centre, eliminate STP by going routed spine-leaf.

**Pick redundancy per layer.** First-hop gateway redundancy (HSRP / VRRP / GLBP) covers the host default gateway; switch redundancy (StackWise at access, StackWise Virtual / vPC / MLAG at distribution and DC leaf, ESI-LAG for standards-based multihoming) covers the device and link. They solve different problems; a design needs both, matched to the platform.

**Underlay choice is a scaling decision.** For a modern spine-leaf fabric, eBGP is the default: explicit policy, AS-path loop prevention, and clean horizontal scale. OSPF suits smaller fabrics where simplicity wins; IS-IS suits very large fabrics that want fast convergence without LSDB flooding storms. Whatever the choice, put BFD on fabric links and size ECMP for the spine count, and remember VXLAN adds 50 bytes so fabric MTU must be raised (typically 9214).

**Platform follows topology and operating model, not the other way round.** Campus breadth and wired-plus-wireless integration point to Cisco IOS-XE; mature DC VXLAN/EVPN with vPC points to Cisco NX-OS; cloud-scale fabric automation points to Arista EOS; OVSDB and on-box analytics point to Aruba AOS-CX; service-provider routing and the commit model point to Juniper Junos; distributed sites with no on-site engineer point to cloud-managed Meraki. Choose the operating model first, then the platform that fits it.

**Anti-patterns:** stretching VLANs across sites over trunks instead of an overlay; relying on default STP priorities and letting the lowest MAC win the root election; designing first-hop and switch redundancy as if they were the same thing; choosing EIGRP in a multi-vendor environment (it is Cisco-only); forgetting VXLAN MTU and silently fragmenting the fabric; buying a platform before the topology and operating model are decided.

## Reference router

| Need | Load |
|---|---|
| Campus topology selection (collapsed core / three-tier / routed access / SD-Access), layer roles and scale tiers, STP root placement at design level, first-hop redundancy selection | `references/campus-architecture.md` |
| VLAN design strategy and broadcast-domain sizing, native-VLAN and trunk hygiene, STP variant selection and guards, switching redundancy selection (StackWise / StackWise Virtual / vPC / MLAG / ESI-LAG) | `references/switching-and-redundancy.md` |
| Data-centre fabric selection (spine-leaf / super-spine / multi-site DCI / ACI), underlay routing-protocol choice, ECMP design, VXLAN MTU, VRF and segmentation design | `references/datacenter-architecture.md` |
| Vendor and platform selection across IOS-XE / NX-OS / EOS / AOS-CX / Junos / Meraki: feature parity, redundancy and management model, API and telemetry, decision matrix | `references/platform-selection.md` |

## Cross-references

- `igp-routing-analysis`: OSPF / EIGRP / IS-IS diagnostics, area-design depth, and redistribution. This skill chooses the IGP; that skill troubleshoots and tunes it. Reciprocal.
- `bgp-analysis`: BGP peering, path-selection, and policy diagnostics. This skill chooses eBGP as the fabric underlay; that skill makes the peering work.
- `evpn-vxlan-fabric`: EVPN-VXLAN data-centre fabric audit and troubleshooting. This skill selects the spine-leaf topology and underlay; that skill audits and fixes the running overlay-plus-underlay system.
- `multi-vendor-network-ops`: the diagnose-first operating entry point and the 9-element production-change response contract. This skill is design-time; that skill is operate-time, and owns the per-vendor operating CLI.
- `wireless-ops`: campus design routinely integrates wired and wireless; this skill owns the switching fabric, that owns the WLAN.
- `network-source-of-truth`: a designed topology becomes the intended state a SoT (NetBox / Nautobot / Infrahub) records and reconciles against.
- `secrets-hygiene`: management-plane credentials, API tokens, and TACACS/RADIUS secrets for the chosen platform live in the secret store, never in a config template.

For SD-WAN and DDI (DNS / DHCP / IPAM) design, and for load-balancer design, see the SD-WAN, DNS, and load-balancing families; cloud-network design is owned by `cloud-network-design`. Those are adjacent network design concerns referenced here in prose, not duplicated.

## Red flags

- About to stretch a VLAN across a WAN over a trunk instead of a deliberate VXLAN overlay.
- About to rely on default spanning-tree priorities, letting the lowest-MAC switch become root by accident.
- About to design a data-centre fabric on STP instead of a routed spine-leaf that eliminates it.
- About to size a VXLAN fabric without raising MTU for the 50-byte encapsulation overhead.
- About to specify EIGRP in a multi-vendor design, when it is Cisco-proprietary and OSPF or BGP is the portable choice.
- About to treat first-hop gateway redundancy and switch / link redundancy as interchangeable rather than complementary.
- About to select a vendor platform before the topology, scale, and operating model are decided.
- About to answer a protocol-troubleshooting question here instead of routing it to igp-routing-analysis, bgp-analysis, evpn-vxlan-fabric, or multi-vendor-network-ops.

## Bottom line

Design routing and switching by bounding Layer 2, routing everything else, and keeping spanning tree as a safety net rather than an architecture. Choose the campus topology by scale and the data-centre fabric by east-west growth, pick redundancy per layer (first-hop plus switch), and select the underlay protocol as a scaling decision with BFD and the right MTU. Decide the operating model before the platform, then let the platform follow the topology. This skill owns those choices; once the design is running, igp-routing-analysis, bgp-analysis, evpn-vxlan-fabric, and multi-vendor-network-ops own the diagnostics.
