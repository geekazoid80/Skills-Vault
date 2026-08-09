# EVPN-VXLAN overlay design and platform selection

Design-time reference for the **overlay** half of a data-centre fabric: the EVPN control-plane and VXLAN (or Geneve) data-plane design choices, and the SDN-platform / operating-model decision (Cisco ACI vs VMware NSX vs open standards-based BGP-EVPN). It is the design counterpart to the diagnostic body of `evpn-vxlan-fabric`.

**Boundary (read first).** This reference owns EVPN-overlay design and SDN-platform selection only. The **generic** fabric-design surface, spine-leaf vs super-spine topology selection, underlay routing-protocol choice (eBGP / OSPF / IS-IS), ECMP sizing, VXLAN fabric MTU (9214), and VRF / segmentation design, is owned by `routing-switching-design/references/datacenter-architecture.md`; go there for those decisions. Running-state **troubleshooting** (silent hosts, missing route types, anycast-gateway mismatch, DF election, replication-mode drift) is owned by the `evpn-vxlan-fabric` SKILL.md body. This reference does not repeat any of that; it covers the overlay-and-platform design decisions neither of those owns.

---

## Overlay control-plane and data-plane design choices

The underlay gives you loopback reachability; the overlay design decides how tenant reachability and routing behave on top of it. These are choices made at design time, before the first VTEP is provisioned.

### Symmetric vs asymmetric IRB

Integrated Routing and Bridging (IRB) is how a fabric routes between tenant subnets across VTEPs. Two models exist, and the choice is fabric-wide; mixing them is a design error.

| Model | How it works | Trade-off |
|---|---|---|
| **Symmetric IRB** (recommended default) | Both ingress and egress leaves route; inter-subnet traffic rides a per-VRF **L3 VNI** between them. Every leaf needs only the L3 VNI plus its locally attached L2 VNIs. | Scales cleanly: a leaf carries state only for the subnets it actually serves. The modern default for NX-OS / EOS / Junos EVPN fabrics. |
| **Asymmetric IRB** | The ingress leaf both routes and bridges; it must have every destination L2 VNI configured locally even for subnets with no local host. | Simpler conceptually, but every leaf must carry every VNI, so state grows with the whole tenant, not with what the leaf serves. Avoid at scale. |

Design rule: pick **symmetric IRB** unless a specific platform constraint forces otherwise, and apply it uniformly. An L3 VNI must exist on every leaf that has a tenant SVI (the SKILL.md body diagnoses the failure when one is missing).

### Anycast gateway design

Every leaf serving a tenant subnet advertises the **same** gateway IP and the **same** anycast MAC, so a host keeps the same default gateway wherever it lands. This is what makes workload mobility seamless. Design decisions:

- Distributed anycast gateway (gateway on every leaf) is the fabric default; it keeps first-hop routing local and avoids hair-pinning tenant traffic to a central router. Centralised gateways (routing only at border leaves) exist for legacy interop but reintroduce the hair-pin and a failure choke-point; choose them only for a deliberate reason.
- Fix the anycast IP and MAC per subnet in the intent source of truth up front; an MAC that differs by even one bit between leaves causes intermittent host ARP-cache invalidation during moves (a classic, hard-to-find fault the body troubleshoots).

### ARP / ND suppression design

EVPN Type-2 routes carry MAC and MAC+IP bindings, so a leaf can answer a host's ARP or ND request locally from its EVPN database instead of flooding it fabric-wide. Enable suppression per L2 VNI as a design default: it is the single largest reduction in BUM traffic a fabric gets. The only reason to leave it off is a transient debug window, scoped to one VNI.

### BUM replication design

Broadcast, unknown-unicast, and multicast (BUM) frames need a replication method, chosen per L2 VNI and kept consistent across every leaf serving that VNI:

- **Ingress Replication (IR)**: the ingress VTEP unicasts a copy to every other interested VTEP (learned from Type-3 routes). No multicast in the underlay; simplest to operate; replication cost grows with VTEP count. The common default for small and medium fabrics.
- **PIM-SM (ASM or SSM) underlay multicast**: BUM rides an underlay multicast tree, so the ingress VTEP sends one copy. Scales better for many-VTEP, high-BUM fabrics, at the cost of running and monitoring multicast in the underlay.

Design rule: standardise one method per VNI fabric-wide. A VNI where some leaves run IR and others run PIM-SM has undefined BUM forwarding (silent hosts); the body treats that mismatch as a Critical finding.

---

## Platform and operating-model selection (ACI vs NSX vs open EVPN)

The overlay can be delivered by a controller-driven fabric (Cisco ACI), a host-based SDN overlay (VMware NSX), or a standards-based switch-built fabric (open BGP-EVPN on NX-OS / EOS / Junos). They solve different operating models, not just different vendors. Decide this before committing to hardware.

| Dimension | Cisco ACI | VMware NSX | Open EVPN (NX-OS / EOS / Junos) |
|---|---|---|---|
| Control model | APIC controller cluster; intent / policy abstraction over the fabric | Manager + host agents; overlay in the hypervisor | No controller; each leaf configured directly or via automation (Ansible, Terraform, AVD) |
| Policy hierarchy | Tenant > VRF > Bridge Domain > EPG > Contract | T0 > T1 gateway > Segment > DFW groups / rules | VRF > VNI > interface > ACL |
| Data-plane encap | VXLAN | Geneve (variable-length options; not VXLAN-interoperable without a translating gateway) | VXLAN |
| Micro-segmentation | Contracts (whitelist between EPGs; deny by default) | Distributed Firewall in the hypervisor kernel at the vNIC, with tag / name / OS-based dynamic groups and L7 context | None built in; VRFs plus ACLs at the leaf, or a host / service firewall |
| Underlay ownership | IS-IS auto-provisioned by APIC; operators do not touch it | Not managed by NSX; the physical switches are a separate design (MTU, ECMP, routing) | Operator-owned end to end |
| Best fit | Teams that want controller-driven intent and policy abstraction and will operate the controller | VM-centric estates wanting kernel-level east-west segmentation that scales with host count | Teams that value standards, multi-vendor freedom, and already run strong automation |

Selection guidance:

- **Open EVPN** is the simplest to reason about and the least locked-in; it suits an organisation with mature automation that does not need controller-driven policy abstraction. Segmentation is coarser (VRF + ACL) unless paired with a host-based firewall.
- **ACI** earns its controller when the operating model genuinely wants a single point of intent and contract-based zero-trust segmentation baked into the fabric, and the team is prepared to run APIC as a first-class system.
- **NSX** decouples the overlay from the switches entirely and puts micro-segmentation in the hypervisor, which is compelling for a VM-heavy estate; but it does **not** remove the physical-network design (see the anti-patterns below). Its Geneve data plane does not interoperate with VXLAN VTEPs without a gateway.

Route the per-platform *implementation* out to the vendor's own tooling; this reference stops at the selection and operating-model decision.

---

## EVPN Multi-Site and DCI design patterns

When a fabric spans more than one site, the interconnect (DCI) is its own design decision. The generic "when to go multi-site at all" call is in `routing-switching-design/references/datacenter-architecture.md`; this covers **how** the overlay stitches across sites.

| Pattern | Use case | Overlay mechanism |
|---|---|---|
| Stretched L2 | VM mobility across sites | ACI Multi-Site, NSX Federation stretched segments; L2 VNI extended over the DCI |
| L3 DCI | Independent failure domains | EVPN Type-5 prefix re-origination at border gateways; no L2 stretch |
| Active-active DC | Maximum availability | GSLB in front of independent fabrics joined by an L3 interconnect |
| DR / BC | Disaster recovery | Async replication plus a deliberately scoped stretched VLAN for failover only |

Platform realisations:

- **Open EVPN Multi-Site**: Border Gateways (BGWs) join separate fabrics; Type-5 routes are re-originated at the site boundary; each site runs its own Route Reflectors and the BGWs peer between sites. No controller, so automation must enforce cross-site consistency.
- **ACI Multi-Pod** keeps one APIC cluster across pods over an Inter-Pod Network (single failure domain, campus-scale); **ACI Multi-Site** uses separate APIC clusters orchestrated by Nexus Dashboard Orchestrator over an Inter-Site Network (independent failure domains, geographically distributed).
- **NSX Federation**: a Global Manager pushes stretched segments, groups, and gateway-firewall policy to per-site Local Managers.

Design rule: **prefer L3 DCI over stretched L2 whenever possible.** Stretching L2 across sites enlarges the failure domain and pushes latency-sensitive BUM traffic across the WAN; treat any L2 stretch as a deliberate, documented decision, never a convenience.

---

## Overlay and platform design anti-patterns

- **Choosing the fabric platform before the requirements.** ACI, NSX, and open EVPN answer different needs; settle segmentation, automation, multi-site, and operational-maturity priorities first, then pick.
- **Assuming NSX replaces the physical network.** NSX overlays ride on physical switches; the underlay still needs proper ECMP, MTU, and QoS design. NSX removes none of that (the underlay MTU decision itself lives in `routing-switching-design/references/datacenter-architecture.md`).
- **Mixing ACI mode and standalone NX-OS in one pool.** A Nexus 9000 in ACI mode cannot run standard NX-OS CLI; an estate that wants both must keep separate switch pools.
- **Over-engineering multi-site.** L3 DCI with independent failure domains is almost always more resilient than a stretched L2; do not stretch by default.
- **Ignoring east-west security.** Perimeter firewalls inspect north-south only; a fabric needs micro-segmentation (ACI contracts, NSX DFW, or host-based firewalls) for east-west traffic between workloads.
- **Inconsistent IRB or replication mode.** Symmetric on some leaves and asymmetric on others, or IR on some and PIM-SM on others for the same VNI, produces undefined forwarding; standardise fabric-wide at design time.

---

## Attribution and references

Re-authored and genericised from the MIT-licensed `chrishuffman5/domain-expert` `plugins/networking/skills/dc-fabric` (SKILL.md + `references/concepts.md`); the per-vendor implementation subdirs (`cisco-aci`, `sonic`, `dent`, `vmware-nsx`) are not folded, and the `containerlab` lab-tooling subdir is out of scope for this fold. Standards are cited, not reproduced: RFC 7432 (BGP MPLS-based EVPN), RFC 8365 (network virtualisation overlay with EVPN), RFC 9135 (EVPN IRB). Vendor operating-model details (Cisco ACI, VMware NSX) are summarised from the vendors' public design documentation for selection purposes; consult the vendor docs for configuration.
