# Platform selection

This reference compares the major routing and switching platforms and gives a selection method. The principle is that platform follows topology and operating model, not the other way round: decide the topology (campus or data centre) and how the network will be operated (CLI, controller, or cloud dashboard) first, then choose the platform that fits. Per-vendor configuration syntax is refer-only here and in `multi-vendor-network-ops`.

## Platform positioning

| Platform | Best for | Key strengths | Operating model |
|---|---|---|---|
| Cisco IOS-XE | Campus, branch / WAN, SD-Access | Broadest campus portfolio (Catalyst), wired-plus-wireless integration, StackWise | CLI + Catalyst Center (DNA Center) |
| Cisco NX-OS | Data-centre spine-leaf, VXLAN/EVPN | vPC, mature VXLAN/EVPN, ACI option, Nexus Dashboard | CLI + Nexus Dashboard (NDFC) |
| Arista EOS | Cloud-scale and hyperscaler data centre | Sysdb resilience, CloudVision, AVD automation, eAPI programmability | CLI + CloudVision (CVP / CVaaS) |
| Aruba AOS-CX | Campus and mid-size DC with on-box analytics | Linux / OVSDB architecture, NAE on-box analytics, VSX active-active, REST API | CLI + Aruba Central (cloud) |
| Juniper Junos | Service-provider and enterprise routing, DC | Commit model (candidate config, rollback, commit confirmed), MPLS depth, Apstra fabric automation | CLI + Apstra / Mist |
| Cisco Meraki | Distributed sites with no on-site engineer | Cloud-managed dashboard, AutoVPN, zero-touch provisioning, unified MX/MS/MR | Cloud dashboard + Dashboard API v1 |

## Feature parity that affects selection

| Capability | IOS-XE | NX-OS | Arista EOS | Aruba AOS-CX | Juniper Junos |
|---|---|---|---|---|---|
| EIGRP | Yes | Yes | No | No | No |
| EVPN-VXLAN | Yes (campus from 17.12+) | Yes (most mature for DC) | Yes (most mature for DC) | Yes | Yes (ERB / CRB modes) |
| Segment Routing | SR-MPLS, SRv6 | SR-MPLS, SRv6 | SR-MPLS | SRv6 (preview) | SR-MPLS, SRv6 |
| Multi-chassis pair | StackWise Virtual | vPC | MLAG | VSX | (MC-LAG / EVPN MH) |
| BFD | Yes | Yes | Yes | Yes | Yes |

Selection consequences:

- **EIGRP is Cisco-only.** Never base a multi-vendor design on it; choose OSPF or BGP for portability. If an existing network runs EIGRP and must stay multi-vendor, plan a migration (owned by `igp-routing-analysis`).
- **For a DC VXLAN/EVPN fabric, NX-OS and Arista EOS are the most mature**, with IOS-XE strong for campus EVPN from 17.12 onward and Junos strong where MPLS and service-provider features matter.
- **The multi-chassis redundancy technology is vendor-specific** (StackWise Virtual / vPC / MLAG / VSX); selecting the platform selects the redundancy model, so make the two choices together (`references/switching-and-redundancy.md`).

## Management and automation model

| Platform | Management platform | API | Telemetry | Save / rollback |
|---|---|---|---|---|
| Cisco IOS-XE | Catalyst Center | RESTCONF / NETCONF | gNMI / MDT | `write memory`; `configure replace` |
| Cisco NX-OS | Nexus Dashboard (NDFC) | NX-API | gRPC / gNMI | `copy run start`; `checkpoint` / `rollback` |
| Arista EOS | CloudVision | eAPI (JSON-RPC) | gNMI + Sysdb | `write memory`; `configure checkpoint` |
| Aruba AOS-CX | Aruba Central | REST API (versioned) | NAE on-box | checkpoint / rollback |
| Juniper Junos | Apstra / Mist | NETCONF / PyEZ | gNMI | commit model (candidate / active, `commit confirmed`) |
| Cisco Meraki | Meraki Dashboard | Dashboard API v1 | Dashboard analytics | Dashboard-managed (no device CLI) |

The management model is often the deciding factor:

- **Junos commit model** (candidate configuration, atomic commit, `commit confirmed` auto-rollback) is a strong reason to choose Juniper where change safety is paramount.
- **Arista eAPI and AVD** suit teams that automate the fabric as code at scale.
- **Meraki has no device CLI**; everything is the dashboard or the API. That is the point for distributed retail / branch estates with no on-site engineer, and the disqualifier for teams that need deep protocol customisation.

## Selection method

1. **Classify the network.** Campus, data centre, branch / distributed, or service-provider edge. This narrows the field immediately (Meraki for distributed branch, NX-OS/EOS for DC fabric, IOS-XE for campus, Junos for SP routing).
2. **Fix the operating model.** CLI-driven, controller-driven, automation-as-code, or cloud-dashboard. A team that wants zero on-site touch chooses cloud-managed; a team that automates everything chooses the most programmable platform.
3. **Check feature must-haves.** EVPN maturity for a DC fabric, EIGRP only if locked into Cisco, MPLS / SR for an SP edge, on-box analytics for lean operations.
4. **Match the redundancy model** (`references/switching-and-redundancy.md`) since it is platform-specific.
5. **Prefer one platform per role over a mix.** A consistent campus platform and a consistent DC platform are easier to operate than a heterogeneous estate; introduce a second vendor deliberately (for resilience or cost), not by drift.

## Quick decision guide

| If the priority is... | Lean toward |
|---|---|
| Broadest campus portfolio, wired + wireless | Cisco IOS-XE (Catalyst) |
| Mature DC VXLAN/EVPN with vPC | Cisco NX-OS |
| Cloud-scale DC fabric, automation-as-code | Arista EOS |
| On-box analytics, OVSDB, active-active campus / DC | Aruba AOS-CX |
| Change-safety commit model, MPLS / SP routing | Juniper Junos |
| Distributed sites, zero on-site engineering | Cisco Meraki |

When the requirement is genuinely cross-vendor (translation, parity questions, or operating a mixed estate), the operating discipline and per-vendor command surface live in `multi-vendor-network-ops`.
