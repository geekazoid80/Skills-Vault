---
name: evpn-vxlan-fabric
description: "Use for any audit, troubleshooting, change review, or design pass on an EVPN-VXLAN data-centre fabric (BGP-EVPN control plane, VXLAN data plane). Triggers include \"EVPN MAC/IP not reachable\", \"silent host\", \"asymmetric flooding\", \"VXLAN tunnel not coming up\", \"VTEP unreachable\", \"VTEP loopback inconsistent\", \"VNI to VLAN mapping wrong\", \"anycast gateway not consistent\", \"anycast gateway MAC mismatch\", \"ARP suppression broken\", \"missing route type 2\", \"missing route type 3\", \"missing route type 5\", \"type 5 route not redistributed\", \"ESI multihoming broken\", \"DF election\", \"split-horizon flood storm\", \"duplicate MAC move\", \"underlay BGP failed\", \"spine-leaf underlay outage\", \"overlay symptom but underlay healthy\", \"Ingress Replication vs PIM SM multicast\", \"L3 VNI vs L2 VNI\", \"tenant routed traffic broken between leaves\", \"RT-2 vs RT-5 selection\", \"data-centre fabric audit\", \"leaf-spine fabric documentation\". Covers multi-vendor: Cisco Nexus 9000 (NX-OS) and Catalyst 9000, Arista EOS, Juniper QFX (Junos), Cumulus Linux. EVPN route types 1 to 5 with focus on RT-2 (MAC + IP), RT-3 (Inclusive Multicast for BUM), RT-5 (IP Prefix). Six-section diagnostic flow plus dedicated multihoming sub-procedure. Diagnose-first; read-only show queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from automateyournetwork/netclaw/workspace/skills/evpn-vxlan-fabric (Apache-2.0); substantially expanded with multi-vendor command surface, route-type detail, threshold tables, decision trees, and the underlay-before-overlay iron rule."
license: Apache-2.0
metadata:
  version: 1.1.0
---

# EVPN-VXLAN fabric audit and troubleshooting

EVPN-VXLAN is the modern data-centre fabric pattern: BGP-EVPN as the control plane (advertising MAC, IP, multicast, and tenant-prefix reachability), VXLAN as the data plane (Layer 2 over IP encapsulation between Virtual Tunnel Endpoints, VTEPs). This skill audits and troubleshoots the joint underlay-plus-overlay system. Per-vendor commands are labelled **[NX-OS]**, **[EOS]**, **[Junos]**, **[Cumulus]**.

> **Skill marker**: When applying this skill, begin your reply with `[skill: evpn-vxlan-fabric]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the fabric design (underlay protocol, overlay BGP design, route-reflector or route-server placement, multi-pod / multi-site stitching) before diagnosing. Only ask the user for information not already covered or specific to this fabric.

Before diagnosing, understand:

1. **Fabric design**
   - Vendor(s) (Cisco NX-OS / IOS-XR, Arista EOS, Juniper QFX, Nokia SR OS, Cumulus Linux)?
   - Underlay protocol (OSPF, IS-IS, eBGP-unnumbered)?
   - Overlay BGP design (iBGP with RR, eBGP between leaf and spine)?
   - Single pod, multi-pod, or multi-site (EVPN domain stitching, DCI)?

2. **Symptom and scope**
   - Tenant-affecting (BUM blackhole, L2 stretch broken) or fabric-wide (underlay flap)?
   - Which EVPN route types are missing or unexpected (Type 1-5)?
   - When did the symptom start; what config or operational event correlates?

3. **Evidence**
   - Read-only access to underlay and overlay state on leaves and spines?
   - Recent change history (VTEP adds, tenant VRF / VNI mappings, policy edits)?

---

## Scope and when to use

- EVPN MAC / IP reachability issues (host on leaf-A cannot reach host on leaf-B in the same VNI).
- Silent hosts or asymmetric flooding complaints.
- Anycast gateway not consistent, ARP suppression not working.
- Leaf-spine underlay failures impacting overlay forwarding.
- VTEP not coming up; VXLAN tunnel established but no traffic; loopback IP inconsistency.
- VNI to VLAN mapping mistakes.
- Missing or wrong-vrf route advertisements (RT-2, RT-3, RT-5).
- Multihoming and Ethernet Segment (ESI) state issues; DF election; split-horizon.
- Inter-VRF or inter-tenant routing broken (L3 VNI not advertised, route-target mismatch).
- Data-centre fabric audit (compliance, documentation, capacity baseline).
- Pre-change validation before adding a leaf, changing tenant VNIs, or migrating from Ingress Replication to PIM SM (or vice versa).

For routing-protocol-specific issues underneath the fabric (BGP IPv4 unicast underlay flapping, OSPF underlay convergence), use `bgp-analysis` or `igp-routing-analysis` first; this skill builds on a healthy underlay.

## Fabric design and platform selection (progressive disclosure)

The body of this skill is diagnose-first: it audits and troubleshoots a running fabric. For the **design** decisions that precede a running fabric, the split is:

- **Generic fabric design** (spine-leaf vs super-spine topology, underlay protocol choice, ECMP sizing, VXLAN fabric MTU, VRF / segmentation) lives in `routing-switching-design/references/datacenter-architecture.md`.
- **EVPN-overlay and SDN-platform design** (symmetric vs asymmetric IRB, anycast-gateway / ARP-suppression / BUM-replication design, EVPN Multi-Site and DCI patterns, and the Cisco ACI vs VMware NSX vs open-EVPN platform and operating-model choice) lives in [`references/overlay-design-and-platform-selection.md`](references/overlay-design-and-platform-selection.md).

Reach for the design references when the question is "how should we build or extend this fabric"; stay in the body below when the question is "why is this fabric misbehaving".

## Prerequisites

- Read-only access to leaf and spine CLI / show commands (or NETCONF / EVPN APIs).
- Topology knowledge: spine count, leaf count, loopback IP per VTEP, RR (route-reflector) addresses or full-mesh BGP-EVPN, underlay routing protocol (eBGP unnumbered / iBGP / OSPF), multicast underlay (Ingress Replication vs PIM SM ASM / SSM).
- Tenant inventory: VRF names, L2 VNIs, L3 VNIs, route-target export / import, anycast gateway IP and MAC.
- For multihoming: ESI inventory (manual or LACP-derived), DF-election method (preference-based or modulo).
- For audit work: an intent source of truth (NetBox, Cisco ACI controller, Arista CloudVision, custom) to reconcile against discovered state.

## EVPN route types (the five you encounter)

| Route type | Use | Common failure mode |
|---|---|---|
| RT-1 (Ethernet Auto-Discovery) | Multihoming: per-ES auto-discovery + per-EVI A-D | Missing when ESI configured wrong; breaks split-horizon and DF election. |
| RT-2 (MAC / IP advertisement) | Per-host MAC and MAC+IP reachability | Most common audit subject; missing RT-2 means ARP / ND will never be suppressed and flooding takes over. |
| RT-3 (Inclusive Multicast) | BUM (broadcast / unknown unicast / multicast) replication; lists VTEPs interested in a VNI | Missing RT-3 means BUM packets never arrive; silent-host symptoms. |
| RT-4 (Ethernet Segment) | DF election among multihomed leaves | Required for ESI; missing breaks DF and causes duplicate frames. |
| RT-5 (IP Prefix) | Tenant prefix advertisement (subnet-level, route to a non-EVPN destination) | Inter-VRF or external-fabric routing breaks; check redistribute config. |

Reference: RFC 7432 (BGP MPLS-Based Ethernet VPN), RFC 8365 (NVO with EVPN), RFC 9135 (EVPN IRB).

## Diagnostic flow

The iron rule: **always validate the underlay before blaming the overlay.** Six sections in order; each builds on the prior.

### Section 1: underlay validation

VTEPs must be able to reach each other's loopbacks via the underlay routing protocol. If underlay is broken, every overlay symptom is misleading.

| Vendor | Commands |
|---|---|
| **[NX-OS]** | `show ip route <peer-vtep-loopback>` ; `show bgp ipv4 unicast summary` (if iBGP underlay) ; `show ospf neighbors` (if OSPF underlay) ; `ping <peer-vtep-loopback> source loopback0` |
| **[EOS]** | `show ip route <peer-vtep-loopback>` ; `show ip bgp summary` ; `show ip ospf neighbor` ; `ping <peer-vtep-loopback> source Loopback0` |
| **[Junos]** | `show route <peer-vtep-loopback>` ; `show bgp summary` ; `show ospf neighbor` ; `ping <peer-vtep-loopback> source <local-loopback>` |
| **[Cumulus]** | `vtysh -c 'show ip route <peer-vtep-loopback>'` ; `vtysh -c 'show ip bgp summary'` |

Confirm: every leaf can ping every other leaf's VTEP loopback; equal-cost paths are present; no flapping in BGP or OSPF.

### Section 2: BGP-EVPN control plane

| Vendor | Commands |
|---|---|
| **[NX-OS]** | `show bgp l2vpn evpn summary` ; `show bgp l2vpn evpn` ; `show nve peers` |
| **[EOS]** | `show bgp evpn summary` ; `show bgp evpn` ; `show vxlan vtep` |
| **[Junos]** | `show bgp summary` (look for evpn family) ; `show route table bgp.evpn.0` ; `show evpn database` |
| **[Cumulus]** | `vtysh -c 'show bgp l2vpn evpn summary'` ; `vtysh -c 'show bgp l2vpn evpn'` ; `vtysh -c 'show evpn vni'` |

Verify:

- Every leaf has a BGP-EVPN session to every spine / RR. State must be Established.
- Sessions are not flapping (`Last reset` should be old).
- The local leaf is advertising RT-2 for its locally-learned MACs (a leaf with attached hosts but no RT-2 advertisements is a control-plane bug; check `route-target` config and `vlan` to VNI mapping).
- The local leaf is receiving RT-2 / RT-3 / RT-5 from peers.

### Section 3: VTEP and VNI sanity

| Vendor | Commands |
|---|---|
| **[NX-OS]** | `show nve interface` ; `show nve vni` ; `show vxlan` |
| **[EOS]** | `show interfaces vxlan 1` ; `show vxlan vni` ; `show vxlan address-table` |
| **[Junos]** | `show interfaces vtep` ; `show ethernet-switching vxlan-tunnel-end-point remote` |
| **[Cumulus]** | `net show interface vxlan*` ; `bridge fdb show dev vni-<n>` |

Check:

- VTEP source IP matches the loopback advertised in the underlay (a VTEP using a different source IP than what BGP-EVPN advertises silently breaks data-plane forwarding).
- L2 VNI to VLAN mapping is consistent across leaves serving the same tenant.
- L3 VNI is configured on every leaf with a tenant SVI (otherwise inter-subnet routing through that leaf breaks).
- Replication mode (Ingress Replication vs PIM SM ASM / SSM) is consistent on the L2 VNI across all leaves.

### Section 4: anycast gateway consistency

Anycast gateway is the IP plus MAC the tenant SVI advertises as the default gateway. Every leaf serving the same tenant subnet must advertise the SAME anycast IP and the SAME anycast MAC. Inconsistency causes intermittent host-side ARP issues during VM moves.

| Vendor | Commands |
|---|---|
| **[NX-OS]** | `show fabric forwarding ip local-host-db vrf <vrf>` ; `show running-config interface vlan<n> all` (look for `fabric forwarding mode anycast-gateway`) |
| **[EOS]** | `show ip virtual-router` ; `show ip virtual-router mac-address` |
| **[Junos]** | `show interfaces irb.<n> | match address` ; `show evpn database extensive | match anycast` |

Confirm: same gateway IP on every leaf; same anycast MAC system-wide; ARP suppression enabled (so hosts only ARP locally; replies are answered by the leaf, not flooded fabric-wide).

### Section 5: MAC and ARP entry validation

Cross-check local MAC learning against EVPN advertisements.

| Vendor | Commands |
|---|---|
| **[NX-OS]** | `show mac address-table` ; `show l2route mac all` ; `show l2route mac-ip all` |
| **[EOS]** | `show mac address-table` ; `show vxlan address-table` |
| **[Junos]** | `show ethernet-switching table` ; `show evpn mac-table` |
| **[Cumulus]** | `bridge fdb show dev vni-<n>` ; `vtysh -c 'show evpn mac vni <n>'` |

Confirm: locally-learned MACs are also being advertised as RT-2; remote MACs (learned via EVPN) appear in the MAC table with the remote VTEP as the next hop. A MAC that flips between local and remote (MAC move) more than a few times in a short interval is a multihoming or loop indicator.

### Section 6: intent reconciliation

For audit work (vs incident triage), reconcile the discovered state against the intent source of truth (NetBox, ACI controller, Arista CloudVision, or YAML-in-git inventory):

- VLAN to VNI mapping.
- Tenant VRF to L3 VNI mapping.
- Route-target export / import.
- ESI assignments per multihomed access device.
- Underlay topology (which leaf connects to which spine on which interface).

Discrepancies are findings; surface in the report with severity per the table below.

## Multihoming sub-procedure (ESI)

Multihoming uses a shared Ethernet Segment Identifier (ESI) across two or more leaves attached to the same access device. RT-1 announces the ESI; RT-4 elects the Designated Forwarder (DF) per VNI per ES.

```
Multihoming flag-day check
├── Both leaves of the ES pair healthy (underlay + EVPN session)?
│   ├── No -> fix the unhealthy leaf first (Section 1 + 2)
│   └── Yes -> continue
│
├── ESI matches on both leaves (same ESI value, configured manually or LACP-derived)?
│   ├── No -> two singly-homed sessions; not multihoming. Fix ESI config.
│   └── Yes -> continue
│
├── RT-1 advertised by both leaves for the ESI?
│   ├── No -> route-target / EVI config mismatch
│   └── Yes -> continue
│
├── RT-4 (ES route) elects exactly one DF per VNI?
│   ├── Multiple leaves claim DF for the same VNI -> RT-4 not advertised by one leaf; check ES config
│   └── Yes -> continue
│
├── Access-side state healthy (LACP, port-channel, VLAN allowed)?
│   ├── No -> fix the access side
│   └── Yes -> continue
│
└── Symptom remains?
    ├── Duplicate frames -> split-horizon broken; check ES-import RT plumbing
    ├── Frames from one leaf only -> DF stuck; clear ES route to force re-election
    └── MAC-move flap -> host moved or LACP unstable; correlate with timestamp
```

## Severity table

| Finding | Severity | Rationale |
|---|---|---|
| Underlay broken between two VTEPs | Critical | Every overlay tenant on those leaves loses connectivity. |
| BGP-EVPN session down between leaf and spine / RR | Critical | Leaf cannot advertise or learn EVPN routes; tenant traffic to / from that leaf fails. |
| Anycast gateway IP or MAC inconsistent across leaves serving same subnet | Critical | Intermittent host-side ARP failures during VM moves; very hard to debug from the host side. |
| L2 VNI replication mode inconsistent (some leaves Ingress Replication, some PIM SM) | Critical | BUM forwarding is undefined; silent hosts. |
| L3 VNI missing on a leaf with tenant SVI | High | Inter-subnet routing through that leaf fails; traffic blackhole. |
| Route-target export / import mismatch on tenant VRF | High | Cross-tenant or inter-fabric routes leak or fail to propagate. |
| ESI mismatch on supposed multihomed pair | High | Two singly-homed sessions instead of one multihomed; LACP confusion possible. |
| MAC move flapping >5 in 60 s | High | Loop or unstable LACP; correlate with port flap timestamps. |
| ARP suppression disabled on tenant SVI | Medium | ARP traffic floods fabric-wide instead of being answered locally. |
| L2 VNI to VLAN mapping inconsistent across leaves | Medium | Hosts on different leaves but same intended VNI cannot communicate. |
| RT-5 not redistributed from local routing protocol | Medium | External routes invisible to tenant VRF. |
| Underlay equal-cost paths missing or asymmetric | Medium | Spine load distribution uneven; impacts capacity. |
| Stale ESI route after access device removed | Low | Cosmetic; will time out. Clear manually. |
| Leaf advertising default-only route into EVPN tenant VRF | Low to Medium | Verify intent; sometimes a hub-and-spoke tenant on purpose, sometimes a leak. |

## Decision tree: silent host or asymmetric flooding

```
Host on leaf-A cannot reach host on leaf-B (both supposedly in same VNI)
├── Underlay reachable? (Section 1)
│   ├── No -> fix underlay first; STOP
│   └── Yes -> continue
│
├── BGP-EVPN session up on both leaves? (Section 2)
│   ├── No -> fix EVPN session; STOP
│   └── Yes -> continue
│
├── Both leaves advertising RT-3 (Inclusive Multicast) for the VNI?
│   ├── No on one leaf -> that leaf is not joined to the VNI's BUM domain; check VNI config + replication mode
│   └── Yes -> BUM should be working; continue
│
├── Source leaf (A) advertising RT-2 for the local host's MAC?
│   ├── No -> local MAC learning is broken or RT-2 export RT mismatched
│   └── Yes -> continue
│
├── Destination leaf (B) receiving the RT-2 for that MAC?
│   ├── No -> route-reflection or import RT mismatch
│   └── Yes -> continue
│
├── L2 VNI to VLAN mapping consistent on both leaves?
│   ├── No -> fix the mapping
│   └── Yes -> continue
│
├── Anycast gateway consistent (if hosts in different subnets)?
│   ├── No -> Section 4 remediation
│   └── Yes -> continue
│
└── Symptom remains?
    ├── Asymmetric flooding -> check ARP suppression + RT-3 join state
    ├── No flood at all -> verify replication mode (PIM SM RP unreachable? Ingress Replication missing peers?)
    └── ARP works but TCP stalls -> MTU mismatch on overlay; underlay must support 1550+ MTU for default 1500 inside VXLAN
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
EVPN-VXLAN FABRIC AUDIT REPORT
================================
Fabric scope: [list leaves, spines, RRs]
Vendor / OS mix: [NX-OS X.Y, EOS A.B, Junos C.D, Cumulus E.F]
Underlay: [eBGP unnumbered / iBGP / OSPF] | Multicast: [Ingress Replication / PIM SM ASM / PIM SM SSM]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[Underlay routing stable; no in-flight tenant config change; intent source of truth is current.]

UNDERLAY HEALTH:
- Loopback reachability matrix (% leaf-pairs reachable): [n/total]
- Underlay BGP / OSPF flap count (last 24 h): [n]

CONTROL PLANE:
- BGP-EVPN sessions Established: [n] / [expected]
- Sessions flapping in last hour: [n]
- RT-2 advertisements per leaf: [list]
- RT-3 advertisements per L2 VNI: [list]
- RT-5 advertisements per tenant VRF: [list]

DATA PLANE / VTEP:
- VTEPs with mismatched source-IP vs underlay loopback: [n]
- L2 VNI mappings inconsistent across leaves: [list]
- L3 VNI gaps (leaves with tenant SVI but no L3 VNI): [list]
- Replication-mode inconsistency per L2 VNI: [list]

ANYCAST GATEWAY:
- Subnets with inconsistent gateway IP: [list]
- Subnets with inconsistent anycast MAC: [list]
- ARP suppression disabled on N tenant SVIs: [n]

MULTIHOMING (ESI):
- Multihomed access devices: [n]
- ESI mismatches: [list]
- DF stuck (multiple claimers): [list]

INTENT RECONCILIATION:
- VLAN-VNI mapping diffs against source of truth: [n]
- Tenant VRF-L3VNI diffs: [n]
- Route-target diffs: [n]

EVIDENCE: [show output, EVPN database extracts, BGP summary attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Component: [leaf / spine / VNI / tenant VRF / ESI]
Issue: [problem] -> Recommendation: [remediation]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout per item]
POST-CHECKS proposed: [list, including RT-2 / RT-3 advertisement re-verification]
ROLLBACK: [config snapshot ref or per-change revert]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **Blaming the overlay before validating the underlay.** Half of "EVPN broken" tickets are underlay BGP / OSPF flaps. Section 1 first, every time.
- **VTEP source-IP drift.** Operations team reassigns a loopback for some unrelated reason; the VXLAN tunnel encapsulation continues using the old IP for a while. Symptom: BGP-EVPN healthy but data plane silently broken. Fix: align `nve interface` source-loopback to the underlay-advertised loopback.
- **Replication-mode inconsistency.** Half the leaves use Ingress Replication, half use PIM SM. BUM frames orphaned. Standardise per fabric.
- **Anycast MAC differing by one bit between leaves.** Causes random ARP cache invalidation on hosts during moves. Hard to debug; verify via the consistency-check command.
- **L3 VNI missing on a leaf with tenant SVI.** Subnet-local traffic works; cross-subnet traffic to / from that leaf fails. Add the L3 VNI under the tenant VRF.
- **Route-target plumbing.** Forgetting `route-target both auto` (NX-OS) or its equivalent on a new tenant means RT-5 prefixes never make it across the fabric.
- **MAC move flap caused by loop on access side.** EVPN keeps re-advertising the MAC with new sequence numbers; correlates with port flaps; check spanning-tree state on the access side.
- **MTU mismatch.** Overlay traffic adds VXLAN header (50 to 54 bytes). The underlay MTU must be 1550+ to carry 1500-byte payloads. Symptom: ARP works, large transfers stall.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the EVPN-VXLAN fabric specialist. Apply the nine-element response contract to every state-changing fabric change.
- `bgp-analysis` -- underlay BGP IPv4 unicast flaps and the BGP-EVPN control-plane sessions both live there for protocol-level depth (best-path, timer, MD5 / TCP-AO).
- `igp-routing-analysis` -- underlay OSPF convergence (when underlay is OSPF instead of BGP).
- `routing-switching-design` -- design-time counterpart. Owns the generic fabric-design surface (spine-leaf vs super-spine topology, underlay protocol choice, ECMP, VXLAN fabric MTU, VRF / segmentation) in `references/datacenter-architecture.md`; this skill's `references/overlay-design-and-platform-selection.md` owns the EVPN-overlay and SDN-platform design that complements it.
- `acl-rule-analysis` -- when a tenant ACL on a leaf SVI breaks reachability that looks like an EVPN issue.
- `pyats-network-automation` -- Genie parsers exist for NX-OS / IOS-XE EVPN show output; useful for fleet anycast-gateway consistency scans.
- `cisco-firewall-audit`, `palo-alto-firewall-audit`, `fortigate-firewall-audit` -- when a tenant routes through a firewall pair attached to the fabric.
- `secrets-hygiene` -- BGP MD5 / TCP-AO keys, NETCONF credentials, NetBox tokens, ACI controller credentials all fall under the patterns there.
- `completion-gate` Layer 3 -- every state-changing fabric change requires fresh post-check evidence (RT-2 / RT-3 re-advertised, host MAC re-learned via EVPN, application-layer ping passes) before claiming "fabric healthy".
- `plan-time-tooling` -- every state-changing fabric recommendation fires `engineering:deploy-checklist` at plan time. EVPN-VXLAN changes are by definition production-mutating in a data centre.
- `systematic-debugging` -- Phase 1 boundary evidence (which leaf, which VNI, which RT, which ESI, which sequence number) before any change.
- `oncall-runbooks` -- incident classification for fabric outages.

## Red flags (about-to-act warnings)

- About to push a fabric config change without an approved change ticket (data-centre fabrics affect every tenant).
- About to clear a BGP-EVPN session without scoping the blast radius (all RT advertisements rebuild; transient flooding likely).
- About to change replication mode on a live L2 VNI (BUM forwarding will be undefined for the duration).
- About to change anycast gateway MAC on a live tenant subnet (every host's ARP cache invalidates).
- About to disable ARP suppression "to debug" without scoping (fabric-wide flooding burst possible).
- About to add a leaf without underlay validation first (will become an undetected single-VTEP island).
- About to migrate from Ingress Replication to PIM SM (or vice versa) without a maintenance window.
- About to remove an ESI member leaf without first failing host traffic over to the surviving leaf.

## Bottom line

Always validate the underlay before blaming the overlay. EVPN-VXLAN failures look exotic but resolve to a five-element checklist: underlay reachability; BGP-EVPN session health; route-type presence (RT-2 / RT-3 / RT-5 as appropriate); VTEP / VNI / replication mode consistency; anycast gateway and ARP-suppression consistency. Reconcile audit findings against the intent source of truth (NetBox, ACI, CloudVision); do not ship a fabric change without `engineering:deploy-checklist` and the nine-element response contract from `multi-vendor-network-ops`. RT-2 explains MAC reachability; RT-3 explains BUM; RT-5 explains tenant-prefix reachability; if your symptom does not map to one of those, look at the underlay first.
