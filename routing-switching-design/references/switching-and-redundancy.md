# Switching design and redundancy selection

This reference owns the Layer 2 design surface: VLAN strategy and broadcast-domain sizing, trunk and native-VLAN hygiene, spanning-tree variant selection and the protection features, and the selection of switch / link redundancy technologies. It is design-time guidance; spanning-tree and port-channel *troubleshooting* belong to `multi-vendor-network-ops`, and per-vendor command syntax is refer-only here.

## VLAN design strategy

A VLAN is a broadcast domain and therefore a failure domain. The strategy is to keep them bounded and segmented by function.

### Principles

- **Bound the broadcast domain.** Keep a VLAN under roughly 500 active hosts; large flat VLANs spread broadcast and failure across everything in them. Match the subnet to the VLAN (a /24 for a standard VLAN, a larger prefix only when deliberately sizing a big segment).
- **Segment by function, not by convenience.** Separate VLANs for data, voice, management, guest, IoT, and server traffic. Function-based segmentation is what lets policy (ACLs, firewall rules, QoS) attach to a whole class of traffic.
- **One subnet per VLAN.** Avoid secondary subnets on a single VLAN; they complicate troubleshooting and break the one-to-one mental model.

### VLAN roles

| VLAN role | Purpose | Notes |
|---|---|---|
| Data | User workstation traffic | The primary production segment |
| Voice | VoIP phones | QoS-marked, separated from data; usually auto-assigned by the phone's CDP/LLDP |
| Management | Switch and router management plane | Restricted, ACL-protected, never the same as user data |
| Native | Untagged traffic on a trunk | Change it away from VLAN 1; pick a dedicated unused VLAN |
| Guest | Untrusted visitor access | Isolated, internet-only, no path to internal resources |
| IoT | Cameras, sensors, building systems | Segmented and firewall-controlled; these devices are rarely patched |

### Trunk and native-VLAN hygiene

- **Never carry user data on VLAN 1**, and change the native VLAN on trunks away from VLAN 1 to a dedicated unused VLAN. VLAN 1 cannot be deleted and is a common attack and misconfiguration vector.
- **Prune trunks to the VLANs that actually need to traverse them.** Allowing all VLANs on every trunk widens the broadcast scope and the STP topology unnecessarily.
- **Make the native VLAN match on both ends of a trunk.** A native-VLAN mismatch silently merges two broadcast domains and is a frequent source of hard-to-find loops and leakage.

## Spanning-tree variant selection

Choose a rapid-converging variant and design so the protocol idles in steady state. Root-bridge placement at the design level is covered in `references/campus-architecture.md`; the protocol-level diagnostics live in `multi-vendor-network-ops`.

| Variant | Standard | Instances | Convergence | When to choose |
|---|---|---|---|---|
| STP (802.1D) | IEEE | One (all VLANs) | 30 to 50 s | Legacy only; avoid in new designs |
| RSTP (802.1w) | IEEE | One (all VLANs) | Under ~6 s | Single common topology across all VLANs; multi-vendor where per-VLAN STP is not needed |
| Rapid PVST+ | Cisco | Per VLAN | Under ~6 s | Cisco campus that wants per-VLAN root placement and load balancing |
| MST (802.1s) | IEEE | Configurable (VLAN groups) | Under ~6 s | Large VLAN counts; maps many VLANs to a few instances to cut CPU and state; multi-vendor |

### Selection guidance

- **Default to Rapid PVST+ in a Cisco campus** with a manageable VLAN count, because per-VLAN root placement enables uplink load balancing across the distribution pair.
- **Choose MST when the VLAN count is large** (hundreds), because running a separate instance per VLAN wastes switch CPU and state; MST maps VLAN groups onto a handful of instances. MST is also the portable choice in a multi-vendor Layer 2 domain.
- **Choose RSTP only when a single topology suits all VLANs** and per-VLAN control is unnecessary.
- **Choose none of the above** when the design is routed access or routed spine-leaf; the best spanning tree is the one that has no Layer 2 to span.

### Protection features (design defaults)

| Feature | Where to apply | Effect |
|---|---|---|
| PortFast | Edge / access ports only | Skips listening and learning so hosts get a link immediately |
| BPDU Guard | Edge / access ports (with PortFast) | Err-disables the port if any BPDU arrives; stops a rogue switch |
| Root Guard | Distribution-facing-down, toward access | Prevents a downstream switch from becoming root |
| Loop Guard | Non-edge links | Stops a unidirectional link failure from creating a loop |
| BPDU Filter | Use with extreme caution | Suppresses BPDUs; misapplied it creates loops, so prefer BPDU Guard |

## Switch and link redundancy selection

This is distinct from first-hop gateway redundancy (HSRP / VRRP / GLBP, covered in `references/campus-architecture.md`). Switch redundancy makes the device and its uplinks survivable; a design needs both, matched to the platform and layer.

| Technology | Platform | Members | Layer | What it gives |
|---|---|---|---|---|
| StackWise | Cisco IOS-XE (Catalyst 9200/9300) | up to 8 | Access | Physical stack managed as one switch; single control plane |
| StackWise Virtual | Cisco IOS-XE (Catalyst 9400/9500/9600) | 2 | Distribution / core | Two chassis as one logical switch; multi-chassis EtherChannel downstream |
| vPC | Cisco NX-OS (Nexus 9000) | 2 | DC leaf / distribution | Active-active to a dual-homed device without a peer-link in the data path |
| MLAG | Arista EOS | 2 | DC leaf / distribution | Active-active multi-chassis link aggregation, Arista equivalent of vPC |
| EVPN MH / ESI-LAG | NX-OS / EOS / Junos / others | 4+ | DC leaf | Standards-based multihoming, no peer-link, signalled by EVPN Type-1/Type-4 |

### Selection guidance

- **At the access layer, prefer physical stacking (StackWise or vendor equivalent)** so a closet's switches present as one and uplinks bundle into one EtherChannel; it is the simplest survivable access unit.
- **At distribution / DC leaf, choose the vendor's logical-pair technology:** StackWise Virtual on Catalyst, vPC on Nexus, MLAG on Arista. They all turn a pair of boxes into one logical L2/L3 node so downstream devices dual-home with a single LAG and no spanning-tree-blocked link.
- **Prefer EVPN multihoming (ESI-LAG) in a modern EVPN-VXLAN fabric** because it is standards-based, scales past two members, and removes the proprietary peer-link; the fabric design that goes with it is in `references/datacenter-architecture.md`, and its troubleshooting is in `evpn-vxlan-fabric`.
- **Match the redundancy technology to the platform.** vPC and MLAG are not interchangeable across vendors; the choice of redundancy model and the choice of platform are made together (`references/platform-selection.md`).

### Design notes

- A multi-chassis pair (StackWise Virtual / vPC / MLAG) usually lets downstream devices use a single LAG with all links forwarding, which removes the STP-blocked uplink that a plain dual-homed design wastes.
- Align the redundancy model with the first-hop gateway design: a logical pair often presents one gateway, simplifying or removing FHRP.
- Keep the inter-chassis link (peer-link / stack link) sized for the worst-case orphan-traffic and failover load, not just steady state.
