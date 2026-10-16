---
name: ipam-dns-audit
description: "Use for a read-only reconciliation audit of IP address management and DNS: comparing what the IPAM records (prefix hierarchy, reservations, VLAN mapping, DHCP scopes) with what the network actually shows (ARP, DHCP leases, DNS answers), and reporting subnet utilisation, forward and reverse DNS consistency, stale and orphaned records, duplicate IPs, overlapping subnets and DHCP scope exhaustion. Platform-agnostic, with API patterns for NetBox, Infoblox and BlueCat. Triggers include \"subnet is running out of addresses\", \"IPAM utilisation audit\", \"duplicate IP address\", \"IP conflict\", \"stale DNS records\", \"orphaned PTR\", \"forward and reverse DNS mismatch\", \"DHCP scope exhaustion\", \"overlapping prefixes\", \"IPAM does not match reality\", \"pre-migration IP audit\", \"IPv6 adoption coverage\". NOT for the NetBox, Nautobot or Infrahub platform operations or device-and-cable reconciliation (network-source-of-truth), NOT for running or tuning a DNS server (dns-network-ops, bind-dns-ops, windows-dns-ops, powerdns-ops, unbound-dns-ops), NOT for active host scanning (nmap-scanning), NOT for DNSSEC or resolver security design (dns-network-ops)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# IPAM and DNS reconciliation audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: ipam-dns-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

A methodology for measuring how far the recorded state of an address plan and its DNS has drifted from live reality, and what that drift costs. IPAM holds how address space should be allocated: prefix hierarchy, subnet assignments, VLAN mappings, static reservations and DHCP scopes. DNS holds the name-to-address mapping. ARP tables, DHCP leases and actual DNS answers show what the network really looks like. The gap between the two is the audit target: conflicts, orphaned records, exhaustion risk and stale entries.

**Posture.** Read-only. The skill reads the IPAM through its API or an export, queries authoritative DNS servers, and reads ARP and lease data. It changes no record, no zone and no scope. Any cleanup it recommends (deleting a stale record, reassigning an address, expanding a scope) goes through the owning team's change process. The one active step, a ping sweep, is covered by the scope rule below.

Command syntax and API patterns are in `references/cli-reference.md` (DNS query tools, ARP and neighbour tables, DHCP inspection, NetBox, Infoblox and BlueCat patterns). RFC allocation guidance, CIDR arithmetic, DNS record types and DHCP scope planning are in `references/subnet-dns-reference.md`.

## When to use

- A subnet looks nearly full and you need the real utilisation, not the IPAM's claim.
- Name resolution fails and you need forward and reverse consistency checked.
- Intermittent connectivity points to a duplicate IP.
- Before a data-centre move or re-addressing project, to audit allocations first.
- A DHCP scope health check against the IPAM's records.
- A compliance audit that needs IP accountability evidence.
- After IP moves, DNS updates or subnet resizing, to confirm the IPAM caught up.

## When not to use

- **Operating the IPAM platform itself, or reconciling devices, interfaces and cables against it:** `network-source-of-truth`. This skill audits the IP and DNS slice of what that platform records, and reads its API for the intended state.
- **Running, securing or tuning a DNS server:** `dns-network-ops` (concepts, DNSSEC, security) and the per-platform skills (`bind-dns-ops`, `windows-dns-ops`, `powerdns-ops`, `unbound-dns-ops`, `coredns-ops`, `route53-dns-ops`, `azure-dns-ops`, `cloudflare-dns-ops`).
- **Active host or port scanning:** `nmap-scanning`, which has its own scope allowlist and authorisation rules.
- **Mapping what is attached to a switch:** `network-topology-discovery`.
- **Cloud address-space design:** `cloud-network-design`.

## Prerequisites

- **IPAM access, read-only:** an API token or export. NetBox needs IPAM read permission, Infoblox needs WAPI read access to networks and records, BlueCat needs Address Manager read access.
- **DNS access:** the ability to query authoritative servers directly, not only a recursive resolver. A zone transfer (AXFR) is the most complete source but is often restricted; individual lookups against the authoritative server are the minimum.
- **Network device access, read-only:** to collect ARP tables and DHCP relay information (SNMP or SSH).
- **A defined scope:** target subnets, VRFs and zones, set before starting. Scope large estates by site, VRF or /16 aggregate.
- **A stated expectation of what the IPAM tracks:** every IP including DHCP dynamics, or static allocations only. That decides what counts as a gap.
- **Secrets:** API tokens and WAPI credentials handled per `secrets-hygiene`; never pasted into the conversation. Lease tables and DNS exports describe the internal network, so treat them as internal data when quoting them.
- **Active probing needs authorisation.** A ping sweep (`nmap -sn`, `fping`) is an active scan. Run any of them (`nmap -sn`, `fping`, `arp-scan`, an AXFR) only against ranges and servers you are authorised to probe, following the scope rules in `nmap-scanning`; prefer ARP, lease and authoritative-lookup data first.

## Procedure

Six steps in order. IPAM extraction and live discovery feed the diff, which feeds conflict detection and utilisation, which ends in the report.

### Step 1: IPAM inventory analysis

Extract the intended allocation.

- **Prefix hierarchy:** export the hierarchy per in-scope VRF. Every child must sit inside its parent aggregate. Find orphaned prefixes (no parent) and overlapping definitions in the same VRF.
- **VLAN-to-subnet mapping:** cross-reference VLANs with prefix VLAN fields. Flag VLANs with no subnet and subnets with no VLAN.
- **Reservations:** classify IPs as static, DHCP pool, reserved (gateways, HSRP or VRRP virtual IPs) or available. Confirm gateways are reserved, and look for IPs marked active with no device or interface record, which are orphaned allocations.
- **IPv4 exhaustion:** utilisation per subnet is assigned divided by usable addresses. Flag prefixes over the warning threshold and note the remaining contiguous free blocks.

### Step 2: Live subnet discovery

No single source shows every active address, so combine several.

- **ARP tables** from the layer 3 gateways, per in-scope subnet: each entry is a recently active IP. **[Cisco]** `show ip arp vrf [name]`; **[JunOS]** `show arp interface [intf]`; **[EOS]** `show ip arp vrf [name]`.
- **DHCP leases:** extract active leases and compare with the IPAM's scope definitions. A lease outside a defined scope indicates a misconfigured or rogue DHCP server.
- **Active probing (ping sweep, `arp-scan`, zone transfer), only where ARP and leases are incomplete and you are authorised:** routed subnets with no local layer 3 interface. A non-responding address is not necessarily free, because firewalls drop ICMP.
- **Duplicate IPs:** more than one MAC for the same IP in ARP, or rapidly alternating MACs, is an active conflict.

### Step 3: DNS record audit

DNS faults are often misdiagnosed as network faults.

- **Forward and reverse consistency:** every A record should have a PTR that points back to the same name, and every PTR a matching A. Test pairs with `dig +short [name] A` and `dig +short -x [ip]`.
- **Stale records:** an A record pointing at an address the IPAM shows as available or decommissioned is probably stale: confirm with the record's owner, because the IPAM may be the stale side. One pointing at an address with no ARP or lease activity in your retained history (90 days where history exists) may reference a removed host.
- **CNAME chains:** each must resolve to a valid target. Flag chains longer than two hops. A CNAME may not sit at a zone apex or alongside other record types at the same name (RFC 1034), and an MX target must be an A or AAAA record, not a CNAME (RFC 2181).
- **Delegation:** NS records for delegated zones must point at responding servers, and SOA serials should agree across primary and secondary servers.
- **TTLs:** infrastructure records (NS, MX, SOA) 3,600 to 86,400 seconds; records that move (load balancers, failover) 60 to 300; static host records about 3,600.

### Step 4: Conflict detection

These cause operational problems and outrank hygiene findings.

- **Overlapping subnets:** compare every prefix within each VRF, using a bitwise comparison to catch non-obvious overlaps such as `10.1.0.0/23` against `10.1.1.0/24`. Overlap across different VRFs can be legitimate.
- **Duplicate IP assignments:** two IPAM records for one IP in one VRF is a data conflict; two MACs on one IP in ARP is a live conflict. Both cause packet loss.
- **DNS conflicts:** several A records for one name without intentional round-robin, a CNAME beside other types, and PTRs with no forward record.
- **Orphaned PTRs:** reverse entries whose hostname has no forward record, or whose IP is unallocated. They accumulate after decommissions; find them by iterating PTRs and doing forward lookups.

### Step 5: Utilisation

- **Subnet utilisation:** `allocated / usable * 100`, with usable excluding the network and broadcast addresses. A large gap between IPAM-calculated and ARP-based utilisation means stale IPAM data.
- **Thresholds:** over 90% critical (expand now), over 80% warning (plan within the quarter), 20 to 80% healthy, under 20% oversized (reclaim candidate). DHCP pools tolerate higher utilisation than static ranges.
- **DHCP projection:** remaining leases per scope and the time to exhaustion at the observed growth rate. Under 10% free and growing needs expansion or a shorter lease time.
- **IPv6 coverage:** the share of subnets with an IPv6 counterpart. Percent-used is meaningless on a /64, so count active hosts and audit the prefix hierarchy (for example a /48 per site and a /64 per VLAN) instead.

### Step 6: Reconciliation report

Compile an IPAM health scorecard (utilisation distribution, IPAM-versus-live accuracy, hierarchy integrity, VLAN mapping), DNS findings by zone, a conflict inventory ordered by severity (duplicate IPs, then overlapping subnets, then DNS conflicts), and capacity recommendations: subnets needing expansion within 90 days, oversized subnets to reclaim, scope adjustments and IPv6 gaps.

## Threshold tables

| Metric | Good | Warning | Critical | Notes |
|---|---|---|---|---|
| Subnet utilisation | under 80% | 80 to 90% | over 90% | Allocated over usable, per prefix |
| DHCP scope free | over 20% | 10 to 20% | under 10% | Remaining leases |
| Forward/reverse match | 95% or more | 85 to 95% | under 85% | A records with a valid PTR |
| Stale A records | under 5% | 5 to 15% | over 15% | Pointing at inactive IPs |
| IPAM versus ARP accuracy | 90% or more | 80 to 90% | under 80% | IPAM entries confirmed by ARP |
| Duplicate IPs | 0 | n/a | any | Per VRF; a live duplicate is always a conflict |
| Orphaned PTRs | under 5% | 5 to 15% | over 15% | PTRs with no forward match |
| VLAN-subnet mapping | 95% or more | 85 to 95% | under 85% | VLANs with the right subnet |
| IPv6 dual-stack coverage | 80% or more | 50 to 80% | under 50% | Subnets with an IPv6 counterpart |

These are defaults; a local policy that states other numbers wins.

## Decision trees

```
Audit scope
├─ Full enterprise audit?
│  ├─ Over 1,000 subnets: scope by site or region and iterate
│  └─ Under 1,000: a single pass is feasible
├─ Targeted?
│  ├─ IP conflict report: the affected VRF and subnet
│  ├─ DNS failures: the affected zones
│  └─ Capacity planning: high-utilisation prefixes
└─ Pre-migration: the migrating subnets and zones

IPAM data source
├─ NetBox: REST under /api/ipam/
├─ Infoblox NIOS: WAPI, filter by network view
├─ BlueCat Address Manager: its REST API
├─ Spreadsheet: export to structured data first
└─ More than one source: reconcile them with each other before comparing with live state

Duplicate IP
├─ ARP shows conflicting MACs for one IP
│  ├─ Both belong to known devices: assignment error, reassign one
│  ├─ One MAC unknown: possible rogue device, investigate
│  └─ MACs alternate rapidly: active conflict, isolate one port through the owning team
├─ IPAM has the same IP on two records
│  ├─ One stale: archive it after confirming the active device
│  └─ Both active: find which device really uses it
└─ Different VRFs: expected overlap, verify isolation

Stale DNS record
├─ A record points at an IP the IPAM shows available: probably decommissioned; confirm with the owner, then recommend deletion
├─ A record points at an IP with no ARP activity
│  ├─ Device active in IPAM: verify it is powered on
│  └─ No device record: recommend deletion after a 30-day notification hold
├─ PTR with no forward record: orphaned, recommend deletion
└─ CNAME target does not resolve: recommend deleting or repointing
```

Every branch above is a recommendation: deleting or repointing is the owning team's action, and the audit names the record and the evidence.

## Report template

```
# IPAM and DNS reconciliation report

## Executive summary
- IPAM source: [NetBox | Infoblox | BlueCat | other]
- Scope: [VRFs and sites]; [n] prefixes, [n] DNS zones
- Audit date (UTC): [date]
- Composite IPAM health score: [%]

## Utilisation
| Tier | Prefixes | Average utilisation | Action |
|---|---|---|---|
| Critical (over 90%) | | | Expand now |
| Warning (80 to 90%) | | | Plan expansion |
| Healthy (20 to 80%) | | | Monitor |
| Oversized (under 20%) | | | Reclaim candidate |

## DNS
| Metric | Value | Threshold | Status |
|---|---|---|---|
| Forward/reverse consistency | [%] | 95% or more | |
| Stale A records | [n] | under 5% | |
| Orphaned PTRs | [n] | under 5% | |
| CNAME chain violations | [n] | 0 | |
| Delegation integrity | [pass/fail] | pass | |

## Conflicts
### Critical: duplicate IPs
| # | IP | VRF | MAC 1 | Device 1 | MAC 2 | Device 2 | Action |
### High: overlapping subnets
| # | Prefix A | Prefix B | VRF | Overlap | Action |
### Medium: DNS conflicts
| # | Record | Type | Conflict | Action |

## Capacity planning
| Subnet | Utilisation | Growth rate | Projected exhaustion | Recommendation |

## Remediation priorities
1. Resolve duplicate IPs. 2. Resolve overlapping subnets. 3. Expand critical-utilisation subnets. 4. Remove stale DNS records. 5. Reclaim oversized subnets. 6. Close IPv6 gaps.

## Appendix
- IPAM extraction parameters; DNS audit method (zones, servers, tools)
- ARP collection scope and device list
```

## Troubleshooting

- **ARP shows fewer IPs than expected:** entries age out (the IOS default is four hours, JunOS about 20 minutes), and hosts that only talk within their VLAN may never appear in a router's table. Collect at peak, check switch MAC tables, and use sweeps for idle subnets where authorised.
- **Zone transfer denied:** many servers restrict AXFR to secondaries. Fall back to individual lookups with `dig @[auth-server] [name] A`. It is slower but needs no transfer permission. Check `allow-transfer` (BIND) or the zone's transfer settings (Windows DNS).
- **No DHCP lease data:** if the DHCP server is not reachable, use an IPAM that syncs DHCP natively (Infoblox does; NetBox needs an external sync), or relay statistics on the gateway.
- **IPAM and ARP utilisation disagree:** high allocation with few active hosts means stale records. Cross-check against the device inventory in `network-source-of-truth`, then clean the allocations.
- **Overlaps not detected:** overlap detection must be VRF-scoped. Multi-VRF environments legitimately reuse space, and a wrong VRF assignment produces false alarms or hides real overlaps.
- **IPv6 utilisation reads about 0%:** a /64 has 2^64 addresses. Count active hosts and audit the hierarchy instead.

## Cross-references

- `network-source-of-truth`: the platform operations and the device, interface and cable reconciliation; the intended-state source this audit reads.
- `dns-network-ops` and the per-platform DNS skills: server-side fixes for what this audit finds (zone cleanup, TTLs, delegation, transfers).
- `nmap-scanning`: scope and authorisation for any active sweep.
- `network-topology-discovery`: ARP and MAC correlation from the devices themselves.
- `cloud-network-design`: address-space planning for cloud networks.
- `secrets-hygiene`: API tokens and credentials.
- `utc-timestamps`: the audit date and lease times in UTC.

## Red flags

- About to run a ping sweep over a range nobody authorised.
- About to delete a DNS record or reassign an IP from inside the audit.
- About to call an address free because it did not answer ICMP.
- About to report overlap across VRFs as an error without checking the VRF assignment.
- About to compute IPv6 utilisation as a percentage.
- About to trust one ARP snapshot as the full set of active addresses.
- About to compare against a recursive resolver's cached answer instead of the authoritative server.
- About to quote lease tables or zone exports without treating them as internal data.

## Bottom line

Take the IPAM's claim and test it against ARP, leases and authoritative DNS. Report conflicts first (duplicate IPs, overlaps), hygiene second (stale and orphaned records), capacity last, and leave every correction to the team that owns the record.

## Provenance

Re-authored from the Apache-2.0 `ipam-dns-audit` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; the six-step procedure, thresholds, decision trees and report template kept; ARP timer facts corrected; scope and authorisation guidance and cross-references added for this vault.
