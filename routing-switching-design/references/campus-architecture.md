# Campus architecture selection

The campus is where users, phones, cameras, access points, and IoT attach to the network. Campus design is the discipline of choosing a topology that bounds failure domains, scales with the endpoint count, and keeps the Layer 2 / Layer 3 boundary in the right place. This reference covers topology selection, the role of each layer, root-bridge placement at the design level, and first-hop gateway redundancy selection. Protocol troubleshooting belongs to `igp-routing-analysis` and `bgp-analysis`; per-vendor CLI belongs to `multi-vendor-network-ops`.

## The hierarchical model

The classic campus splits into three functional layers. Whether they are separate boxes or collapsed depends on scale.

| Layer | Role | Design rules |
|---|---|---|
| Access | Endpoint attachment; PoE; port security; first L2 hop | Keep ports dumb and consistent; PortFast + BPDU Guard on every edge port; one access switch (or stack) per wiring closet |
| Distribution | Aggregation; L2/L3 boundary; policy and route summarisation | This is where Layer 2 ends and Layer 3 begins in a traditional design; place STP root here; summarise routes upward |
| Core | High-speed transit between distribution blocks | Route only, no policy, no STP; keep it simple and fast; exists to forward, not to decide |

The L2/L3 boundary is the single most important design decision. In a traditional design it sits at distribution. In a routed-access design it moves down to the access layer, which removes spanning tree from the data path entirely.

## Topology selection

| Topology | Endpoint scale | Description | When to choose |
|---|---|---|---|
| Collapsed core | under ~500 | Core and distribution combined into one pair of switches; access attaches directly | Small site, single wiring area, cost-sensitive; two switches carry both roles |
| Three-tier | ~500 to ~10,000 | Distinct access, distribution, and core; STP bounded within each distribution block | Multi-closet campus, multiple buildings, room to grow; the default for a medium-to-large campus |
| Routed access | any | L3 pushed to the access switch; each access switch is an L3 node; no STP in the data path | Modern greenfield; fast convergence, no STP dependence, equal-cost paths up to distribution |
| SD-Access / fabric | any | VXLAN overlay with a control plane (LISP in Cisco SD-Access), group-based policy, automated provisioning | Large campus that needs micro-segmentation, policy mobility, and automation; trades simplicity for capability |

### Choosing between them

- **Start with the endpoint count and the growth path.** A site that will stay under 500 endpoints does not need a separate core. A site that will grow into multiple buildings should be three-tier from the start so the core can be added without re-architecting.
- **Decide where Layer 2 must extend.** If endpoints in the same subnet must appear on multiple access switches (legacy clustering, certain medical or industrial gear), the L2/L3 boundary stays at distribution. If every access switch can be its own subnet, routed access is cleaner and converges faster.
- **Decide whether policy must follow the user.** If users must keep the same security policy regardless of where they plug in, a fabric (SD-Access) earns its complexity. If policy is port- or VLAN-based and static, a fabric is over-engineering.

## STP root placement at design level

Spanning tree should have nothing to do in steady state, but it must be designed deliberately so that when it does act, it acts predictably. The protocol-level troubleshooting lives in `multi-vendor-network-ops`; the design rules are:

- **Place the root at the distribution layer**, never at access and never by accident. Set the priority explicitly (primary root low, e.g. 4096; secondary root next, e.g. 8192). Relying on the default priority lets the switch with the lowest MAC win, which is rarely the one you want.
- **Load-balance VLANs across the distribution pair** when running a per-VLAN variant: one distribution switch is root for even VLANs, the other for odd VLANs, so both uplinks carry traffic.
- **Protect the edge:** PortFast plus BPDU Guard on access ports (err-disable on any BPDU), Root Guard on distribution-to-access where a downstream switch must never become root.
- **In a routed-access or fabric design, there is no STP root to place** because Layer 2 does not extend between switches; this is the design's main attraction.

Variant selection (RSTP vs Rapid PVST+ vs MST) is covered in `references/switching-and-redundancy.md`.

## First-hop gateway redundancy selection

Hosts have a single default gateway. First-hop redundancy protocols (FHRP) make that gateway survive the loss of a switch. This is distinct from switch / link redundancy (covered in `references/switching-and-redundancy.md`); a campus design needs both.

| Protocol | Standard | Load sharing | When to choose |
|---|---|---|---|
| HSRP | Cisco | Active/standby per group (manual load share by alternating active across VLANs) | Cisco-only environment; the long-standing default on IOS-XE |
| VRRP | IETF (RFC 5798) | Active/backup per group | Multi-vendor environment, or when standards compliance matters |
| GLBP | Cisco | Active/active across up to 4 gateways automatically | Cisco-only, when automatic per-host load sharing across multiple gateways is wanted without per-VLAN tuning |

### Design notes

- On a distribution pair, **align the FHRP active with the STP root** for the same VLAN so the active gateway and the forwarding path agree; a mismatch sends traffic across the inter-distribution link unnecessarily.
- With a logical-stacking technology (StackWise Virtual, vPC, MLAG) the distribution pair presents as one logical gateway and FHRP becomes simpler or unnecessary; the redundancy is in the stack, not the protocol. This interaction is the reason redundancy must be designed as a whole, not protocol by protocol.
- In a routed-access design, the gateway is the access switch itself and FHRP is replaced by equal-cost routing upward; there is no shared default gateway to protect.

## Scale and growth checklist

- Size the access layer by ports per closet and PoE budget, not just switch count.
- Size the distribution block so a single block stays within the STP and broadcast-domain limits; add blocks rather than growing one block unbounded.
- Keep the core route-only and oversize its bandwidth; it is the hardest layer to upgrade later.
- Decide the L2/L3 boundary once and document it; moving it later is a re-architecture, not a change.
- Plan the wireless integration alongside the wired design (`wireless-ops`); access-point density and controller placement affect access-layer uplink sizing.
