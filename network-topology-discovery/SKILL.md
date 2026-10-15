---
name: network-topology-discovery
description: "Use for building or validating a network topology map from the devices themselves: iterative discovery from a seed device using CDP and LLDP neighbours, MAC table and ARP correlation, and routing table analysis, on Cisco (IOS-XE / NX-OS), Juniper (JunOS) and Arista (EOS). Triggers include \"map the network\", \"discover topology\", \"CDP LLDP neighbours\", \"what is connected to this switch\", \"undocumented devices\", \"rogue device\", \"network diagram is stale\", \"post-acquisition inventory\", \"blast radius before maintenance\", \"L2 path between two hosts\", \"asymmetric link\", \"unresolved MAC\", \"find the next hop\". Read-only, layer by layer from L2 adjacency to L3 boundaries. NOT for reconciling devices against a NetBox, Nautobot or Infrahub record (network-source-of-truth), NOT for active network or port scanning (nmap-scanning), NOT for routing-protocol diagnosis (bgp-analysis, igp-routing-analysis), NOT for link error and optics diagnosis (interface-health)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network topology discovery

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-topology-discovery]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Iterative discovery that builds a topology map layer by layer. Unlike a threshold-based health check, it works outward from a seed device: find neighbours, correlate MAC and ARP tables, read routing boundaries, and consolidate one adjacency model across L2 and L3.

Commands are labelled **[Cisco]**, **[JunOS]** or **[EOS]** where syntax diverges; unlabelled statements apply to all three. Syntax was written from vendor documentation and was not run against devices while authoring, so confirm it on the release and platform you operate. Command syntax is in `references/cli-reference.md`; the full discovery methodology and data model are in `references/discovery-workflow.md`.

**Posture.** Every step is read-only (`show` commands over SSH). Nothing in this skill changes device state. The risks are scope and credentials, not configuration: crawl only inside the agreed scope, and only to devices you are authorised to log in to.

## When to use

- Building or validating a network diagram in an unfamiliar environment.
- A post-acquisition inventory where documentation is missing or stale.
- Pre-change impact analysis: mapping the blast radius before maintenance.
- Incident response: working out the L2 and L3 path between two endpoints.
- Auditing discovered topology against the intended design.
- Finding rogue or undocumented devices on the network.
- Capacity planning: mapping which links carry which paths.
- Migration planning: inventorying devices and links in a domain.

## When not to use

- **Discovered state versus a source-of-truth record** (NetBox, Nautobot, Infrahub): use `network-source-of-truth`. This skill produces the observed map; that one reconciles it with the intended model and tickets the differences. Feed the output of this skill into that one.
- **Active scanning of hosts, subnets or ports:** `nmap-scanning`. This skill reads what devices already know and sends nothing to endpoints.
- **A peer or adjacency that is down for protocol reasons:** `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`.
- **Errors, flaps or optics on a link found during discovery:** `interface-health`.
- **Wireless controllers and access-point fleets:** `wireless-ops`.
- **Deciding which monitoring platform should keep a topology map:** `network-monitoring-selection`.

## Prerequisites

- SSH or console access to the seed device (read-only privilege is enough).
- Credentials that work across the devices in scope. If credential sets differ, identify them up front; do not try one device's credentials against devices outside the agreed list.
- CDP and/or LLDP enabled somewhere in the network (at least one is required). CDP is Cisco-proprietary; JunOS speaks LLDP only, so use LLDP as the primary protocol in a mixed environment.
- A defined scope: a site, a VRF, a management subnet or an administrative domain, so the crawl does not expand without limit.
- A tracker for discovered devices (spreadsheet, CMDB export or text file) so no device is visited twice.
- Credentials handled per `secrets-hygiene`: never paste them into the conversation, and redact any captured output that contains secrets.

## Procedure

Work outward from the seed. Each step feeds the next.

### Step 1: Seed device identification

Pick a device with broad neighbour visibility (a core or distribution switch, or a router) and confirm access. Collect its identity.

- **[Cisco]** `show version | include hostname|uptime|Software`, `show cdp neighbors | count`, `show lldp neighbors | count`
- **[JunOS]** `show version | match "Hostname|Model|Junos"`, `show lldp neighbors | count`
- **[EOS]** `show version | include hostname|uptime|model`, `show lldp neighbors | count`

Record hostname, platform, software version, management IP and neighbour count. The neighbour count sets expectations for Step 2. Enter the device in the tracker as "discovered".

### Step 2: L2 neighbour discovery

Collect every CDP and LLDP neighbour.

- **[Cisco]** `show cdp neighbors detail`, `show lldp neighbors detail`
- **[JunOS]** `show lldp neighbors detail`
- **[EOS]** `show lldp neighbors detail`, `show lldp neighbors | include System`

For each neighbour record remote hostname, platform, management IP, local interface, remote interface and advertised capabilities (Router, Switch, Phone, AP); the capability field tells you the role without logging in. New devices enter the tracker as "pending" and become the next seeds; known devices are skipped.

### Step 3: MAC address table analysis

- **[Cisco]** `show mac address-table`, `show mac address-table count`
- **[JunOS]** `show ethernet-switching table`, `show ethernet-switching table summary`
- **[EOS]** `show mac address-table`, `show mac address-table count`

Classify ports by how many MACs they learn:

- **Trunk-like ports** (many MACs) usually face other switches and should already appear as neighbours.
- **Access ports** (one or a few) face end hosts.
- **Ports with none** are unused or silent; check admin and oper state.
- **An access port with an excessive count** (over about 100) points to a hub, an unmanaged switch, a virtualisation host bridging many VMs, or a misconfigured trunk.

Flag any MAC on an unexpected port: it identifies undocumented devices and cabling errors.

### Step 4: ARP table correlation

- **[Cisco]** `show ip arp`, `show ip arp vrf [name]`
- **[JunOS]** `show arp no-resolve`, `show arp interface [intf]`
- **[EOS]** `show ip arp`, `show ip arp vrf [name]`

Record IP, MAC, interface, VLAN and age, and join MACs from Step 3 to IPs. A MAC with no ARP entry is an L2-only device or a host on another subnet behind a trunk. An ARP entry with an incomplete MAC is a host that did not answer (offline, filtered, duplicate IP, wrong VLAN).

### Step 5: Routing table analysis

- **[Cisco]** `show ip route summary`, `show ip route`, `show ip route vrf [name]`
- **[JunOS]** `show route summary`, `show route protocol [ospf|bgp|static]`, `show route table [routing-instance].inet.0`
- **[EOS]** `show ip route summary`, `show ip route`, `show ip route vrf [name]`

Identify:

- **Connected subnets**, which are this device's L3 boundary.
- **Next-hop routers**, which you can tie to a physical interface and MAC through ARP.
- **Routing protocol neighbours**, which reveal L3 adjacency even where CDP and LLDP are off.
- **The default route**, which points at the next layer upstream.
- **VRFs**, each a separate routing domain; repeat discovery per VRF.

A next-hop with no ARP entry is an inactive or unreachable peer; flag it.

### Step 6: Topology consolidation

Merge L2 and L3 data into one model.

1. **Confirm each link from both ends.** A link seen from A to B should appear in B's table pointing at A. A link seen from one end only is a disabled protocol on the other end, a unidirectional link or a stale entry.
2. **Deduplicate** using the local-port and remote-port pair.
3. **Resolve L2 and L3 overlap:** a trunk seen in CDP/LLDP that also carries several ARP subnets is one physical link with several L3 paths.
4. **Classify devices** from advertised capabilities and routing participation: core router, distribution switch, access switch, firewall, wireless controller, endpoint.
5. **Mark the perimeter:** devices with no further neighbours, or whose neighbours fall outside scope.
6. **Flag anomalies:** undocumented devices, asymmetric links, unexpected routing peers, MACs on the wrong VLAN.

The expansion order that keeps a crawl small (core and distribution first, routers before switches, access layer last) and the data model are in `references/discovery-workflow.md`.

## Threshold tables

These measure how complete and how fresh the topology data is, not device health.

### Discovery completeness

| Metric | Complete | Partial | Incomplete |
|---|---|---|---|
| CDP/LLDP neighbours versus expected | 100% | 80 to 99% | under 80% |
| MACs with an ARP resolution | over 90% | 70 to 90% | under 70% |
| Next-hops with an ARP entry | 100% | 80 to 99% | under 80% |
| Links confirmed from both ends | over 95% | 80 to 95% | under 80% |
| Devices with the routing table collected | 100% | over 80% | under 80% |

### Data freshness

| Source | Fresh | Ageing | Stale |
|---|---|---|---|
| CDP holdtime remaining | over 120 s | 60 to 120 s | under 60 s |
| LLDP TTL remaining | over 90 s | 30 to 90 s | under 30 s |
| ARP entry age | under 5 min | 5 to 20 min | over 20 min |
| MAC entry age | recent activity | over 5 min since seen | over 15 min |
| Routing table | converged | reconverging | incomplete |

Report completeness in the output. A map that is 70% confirmed is useful, but only if it says so.

## Decision trees

### Expected neighbour is missing

```
Expected neighbour not in the CDP/LLDP table
├── Interface admin up and oper up?
│   ├── No: fix the interface state first
│   └── Yes: continue
├── CDP/LLDP enabled on the local interface?
│   ├── [Cisco] show cdp interface [intf]
│   ├── [JunOS] show lldp detail | match [intf]
│   ├── [EOS] show lldp local-info interface [intf]
│   ├── Disabled: recommend enabling it (a change request, not part of this run)
│   └── Enabled: continue
├── Enabled on the remote device?
│   ├── Cannot verify without access: log in only if the remote is inside the agreed scope and you are authorised
│   └── Disabled on the remote: recommend enabling it, or use MAC and ARP as a fallback
├── VLAN mismatch?
│   ├── Access VLAN differs between ends: fix the assignment
│   └── Trunk pruned: add the VLAN to the trunk
└── Physical layer?
    ├── Check interface errors: see interface-health
    └── Unidirectional link: check fibre Tx and Rx and SFP seating
```

### Unresolved MAC address

```
MAC present but no ARP entry
├── On a trunk port?
│   ├── Yes: the MAC is behind a downstream switch; discover that switch
│   └── No: it is on an access port
├── Is the MAC's VLAN routed on this device?
│   ├── No: the ARP entry lives on another gateway; check the owner of the SVI or IRB
│   └── Yes: continue
├── Spanning-tree state of the port
│   ├── Blocking or discarding: learned before the block
│   └── Forwarding: continue
└── The device may have no IP at all
    └── An L2-only device (unmanaged switch, printer still in DHCP timeout)
```

### Asymmetric routing view

```
A route is visible from device A but not from device B (or with another next-hop)
├── Same VRF?
│   ├── No: separate routing domains; route leaking is needed
│   └── Yes: continue
├── Routing adjacency between A and B?
│   ├── None: protocol not configured, or filtered
│   └── Up: continue
├── Route filters or distribute-lists?
│   ├── [Cisco] show ip protocols | section Routing
│   ├── [JunOS] show policy [name]
│   ├── [EOS] show ip protocols | section Routing
│   └── A filter blocks the prefix: adjust the policy
├── A redistribution boundary?
│   └── The prefix is not redistributed between protocols
└── Summarisation hiding the specific route?
    └── Check area summarisation and aggregates
```

## Report template

```
NETWORK TOPOLOGY DISCOVERY REPORT
===================================
Seed device: [hostname]
Scope: [site | VRF | subnet range | domain]
Discovery time (UTC): [start] to [end]
Performed by: [name or team]

SUMMARY
- Devices discovered: [n]
- Routers [n] | Switches [n] | Firewalls [n] | Other [n]
- Links mapped: [n] (confirmed from both ends [n], one end only [n])
- Subnets identified: [n]
- VRFs encountered: [list]

DEVICE INVENTORY
| Hostname | Platform | Mgmt IP | Role | Discovered by |
|---|---|---|---|---|
| [name] | [model] | [ip] | [role] | [CDP / LLDP / ARP / routing] |

LINK MAP
| Device A | Port A | Device B | Port B | Type | Speed |
|---|---|---|---|---|---|
| [name] | [intf] | [name] | [intf] | [trunk / access / routed] | [1G / 10G / ...] |

ANOMALIES
1. [Severity] [Category]: [description]
   Observed: [what was found]
   Expected: [what the design says]
   Impact: [map accuracy / security / operations]
   Action: [recommended follow-up]

COMPLETENESS
- CDP/LLDP coverage: [%] of expected neighbours
- ARP resolution: [%] of MAC entries
- Links confirmed from both ends: [%]

RECOMMENDATIONS
- [Prioritised actions]

NEXT DISCOVERY: [refresh interval based on how fast this network changes]
```

## Troubleshooting

### No CDP neighbours on JunOS

CDP is Cisco-proprietary and not supported on JunOS. Use LLDP. Enabling it is a configuration change, so raise it as a change request: LLDP on globally and per interface (`set protocols lldp interface all` on JunOS), and LLDP alongside CDP on the Cisco and EOS neighbours so the two sides can exchange data.

### LLDP shows stale neighbours

An entry lives for its TTL (120 s by default) after the neighbour disappears. If a dead neighbour lingers, check for a recent power-off, reboot, pulled cable or LLDP disabled on the far interface. Wait out the TTL or clear the table.

### Thousands of MACs on an access port

A hub, an unmanaged switch, a virtualisation host with many VMs on one interface, or a misconfigured trunk. Check the port's intended role. If it should be an access port, find what is behind it, and consider port security to cap MAC learning.

### ARP entries show "Incomplete"

The device sent an ARP request and got no reply: the host is offline, blocks ARP, collides with another IP, or sits on the wrong VLAN. Confirm the host is up and in the right VLAN.

### An unexpected default route appears

Possible causes: a rogue DHCP server handing out gateways, an unplanned static route, or redistribution pulling in a default from another domain. Trace the source with `show ip route 0.0.0.0` and, if the protocol is OSPF or BGP, find which peer advertises it.

## Cross-references

- `network-source-of-truth`: take the observed map from this skill and reconcile it with NetBox, Nautobot or Infrahub; discrepancies are reported and ticketed, never auto-corrected.
- `interface-health`: the next step for any link in this map that shows errors, flaps or low optical power.
- `igp-routing-analysis`, `bgp-analysis`, `evpn-vxlan-fabric`: protocol-depth diagnosis for the routing adjacencies and boundaries found in Step 5.
- `routing-switching-design`: how the discovered topology compares with sound campus and datacentre design.
- `change-verification`: use this skill's map to scope the blast radius of a change before it starts.
- `nmap-scanning`: active host and service discovery, under its own scope and authorisation rules; this skill never scans.
- `network-monitoring-selection`: choosing a platform that keeps the topology current once the first map exists.
- `multi-vendor-network-ops`: the diagnose-first entry point for general network work.
- `secrets-hygiene`: credentials and captured device output.

## Red flags

- About to crawl to a neighbour that is outside the agreed scope because it showed up in a CDP table.
- About to try the same credentials on devices nobody authorised you to log in to.
- About to treat one-sided links as confirmed.
- About to build the map from CDP alone in an environment with JunOS or other non-Cisco gear.
- About to publish a topology with no completeness figure.
- About to treat a stale ARP or MAC entry as current attachment.
- About to "fix" an anomaly found during discovery (enable LLDP, shut a port) from within the discovery run; findings go to a change request.
- About to paste raw `show` output into a ticket without redacting secrets.

## Bottom line

Start from one seed, stay inside scope, read only. Join L2 neighbours, MAC and ARP, and routing into one model, confirm links from both ends, and report how complete and how fresh the map is. Anomalies are findings for a change request, not things to fix mid-crawl.

## Provenance

Re-authored from the Apache-2.0 `network-topology-discovery` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; vendor commands, completeness and freshness tables, decision trees and report template kept; scope, credential and source-of-truth guidance added for this vault.
