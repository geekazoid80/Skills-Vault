# Source-of-truth reconciliation

A source of truth (SoT) records *intended* network state: what the network designer says should exist. Reconciliation compares that intended state against *live device reality* (what the network is actually doing) and classifies every divergence. The methodology here is platform-agnostic. The intent side can be NetBox, Nautobot, or Infrahub; the reality side is whatever collects live device output, in this vault the `pyats-network-automation` skill (CDP/LLDP neighbours, `show`-command parsing).

## The golden rule

The SoT is authoritative. If reality differs, either the network is misconfigured *or* the SoT is stale; reconciliation cannot tell which on its own. So discrepancies are **reported and ticketed, NEVER auto-corrected**. A human decides whether to fix the device or update the SoT. There is no "apply" step in this methodology, by design.

## Discrepancy types

Severity order CRITICAL > HIGH > MEDIUM > LOW.

| Type | Severity | Meaning |
|---|---|---|
| `IP_DRIFT` | CRITICAL | Device IP differs from the SoT assignment (or device carries an IP the SoT does not document). |
| `MISSING_INTERFACE` | HIGH | Interface exists in SoT but not on the device, or exists on the device but not in SoT. |
| `UNDOCUMENTED_LINK` | HIGH | CDP/LLDP shows a neighbour connection that no SoT cable documents. |
| `CABLE_MISMATCH` | HIGH | SoT cable endpoints do not match the CDP/LLDP neighbour data. |
| `VLAN_MISMATCH` | MEDIUM | Device VLAN assignment differs from the SoT. |
| `STATUS_MISMATCH` | MEDIUM | SoT shows enabled but device shows down, or vice versa. |
| `MTU_MISMATCH` | LOW | Device interface MTU differs from the SoT interface MTU. |

## Reconciliation workflow

### Step 1: Collect SoT intent

Query the SoT platform (for example NetBox via its MCP server; equivalents for Nautobot and Infrahub live in their own references). Pull:

- Device inventory (active devices only).
- Per-device interfaces: name, type, enabled flag, MTU, MAC, mode, untagged and tagged VLANs, description.
- Per-device IP addresses: address in CIDR, assigned interface, status, role.
- Per-device cables: A-side device and interface, B-side device and interface, type, length.
- VLANs: vid, name, site.

### Step 2: Collect live device state

Collect via pyATS. The relevant commands and the fields they yield:

- Interfaces from `show ip interface brief` and `show interfaces`: name, admin status, protocol status, IP and mask, MTU, speed, duplex, description.
- IP addresses from `show ip interface`: primary and secondary.
- CDP/LLDP neighbours from `show cdp neighbors detail` and `show lldp neighbors detail`: local interface to remote device, remote interface, remote platform, remote IP.
- VLAN data from `show vlan brief` and `show interfaces switchport`.

### Step 3: Diff engine

Run each comparison per discrepancy type.

- **IP_DRIFT**: for each SoT IP assignment, find the matching interface on the device and compare IP plus prefix; if they differ, or the interface carries no IP, flag `IP_DRIFT`. For each device IP not present in the SoT, flag `IP_DRIFT` (undocumented IP).
- **MISSING_INTERFACE**: a SoT interface absent from the device flags `MISSING_INTERFACE`; a device interface absent from the SoT flags `MISSING_INTERFACE` (undocumented). Filter out virtual or internal platform interfaces (for example `Null0`, `NVI0`) before flagging.
- **UNDOCUMENTED_LINK**: for each CDP/LLDP neighbour, search the SoT cables for a matching A-side/B-side pair; if none exists, flag `UNDOCUMENTED_LINK`.
- **CABLE_MISMATCH**: for each SoT cable on this device, look up the CDP/LLDP entry for the local interface and compare remote device plus remote interface; if they differ, flag `CABLE_MISMATCH`.
- **VLAN_MISMATCH**: compare SoT untagged and tagged VLANs against the device switchport access, trunk, and native VLANs; differences flag `VLAN_MISMATCH`.
- **STATUS_MISMATCH**: compare the SoT enabled flag against the device admin and protocol status.
- **MTU_MISMATCH**: compare the SoT interface MTU against the device MTU.

### Step 4: Generate the report

Produce a severity-sorted discrepancy table per device, with stable IDs (`C-001`, `H-001`, `M-001`, `L-001`), a per-severity count summary, and an overall status (CRITICAL / HIGH / MEDIUM / LOW / CLEAN). Timestamp the report in UTC.

Report layout:

```
Reconciliation report: core-sw-01
Generated: 2026-06-01T09:14:32Z

ID     Severity  Type               Interface   SoT intent          Device reality
C-001  CRITICAL  IP_DRIFT           Gi0/1       10.0.1.1/24         10.0.1.9/24
H-001  HIGH      UNDOCUMENTED_LINK  Gi0/4       (none)              dist-sw-02 Gi1/0/12
M-001  MEDIUM    VLAN_MISMATCH      Gi0/3       access 20           access 30
L-001  LOW       MTU_MISMATCH       Gi0/2       1500                9000

Summary: CRITICAL 1  HIGH 1  MEDIUM 1  LOW 1
Overall status: CRITICAL
```

A single discrepancy line carries the ID, severity, type, the affected object, the SoT-intent value, and the device-reality value:

```
C-001  CRITICAL  IP_DRIFT  Gi0/1  SoT 10.0.1.1/24  device 10.0.1.9/24  (via show ip interface)
```

### Step 5: Ticket the discrepancies

For each CRITICAL discrepancy, open a ServiceNow incident: short description plus a full description carrying the SoT-intent value versus the device-reality value, the discovery method, and the UTC date; set urgency and impact to 2. For HIGH discrepancies, open incidents at lower urgency (3). MEDIUM and LOW are recorded in the report and triaged by a human. Reported and ticketed only; never auto-correct.

### Step 6: Generate a visual drift summary

Produce a visual drift summary for human review, for example a mind-map or a colour-coded topology diagram (green for match, red for mismatch, yellow for undocumented). This is for human consumption, not machine action; no hard tool dependency. Any renderer that produces a clear at-a-glance picture works.

## Fleet-wide reconciliation

To reconcile a whole fleet rather than one device:

1. List the device inventory from both sides: the pyATS testbed and the SoT active-device list.
2. Run Steps 1 to 6 for each device present in *both* inventories. Devices present in only one side are themselves a finding worth surfacing (missing testbed entry, or stale SoT record).
3. Produce a fleet summary table, sorted CRITICAL-first for triage:

```
Device       CRITICAL  HIGH  MEDIUM  LOW  Overall
core-sw-01          2     1       0    1  CRITICAL
dist-sw-02          0     3       1    0  HIGH
access-sw-09        0     0       2    4  MEDIUM
edge-rtr-01         0     0       0    0  CLEAN
Totals              2     4       3    5
Incidents created: 6
```

## Entity matching and data-quality scoring

The diff engine needs a way to decide that a SoT record and a live device are the same thing, and a way to say how trustworthy the SoT is overall. Matching and scoring are described here once.

### Matching entities

Normalise both sides before comparing: lower-case, strip the domain suffix, trim whitespace (trailing spaces in SNMP `sysName` are common). Then match on the first key that resolves unambiguously:

| Priority | Key | SoT side | Live side | Note |
|---|---|---|---|---|
| 1 | Hostname | device name | SNMP `sysName.0` | Primary, after normalisation |
| 2 | Serial number | device serial | `show inventory`, `entPhysicalSerialNum` | Best for hardware identity |
| 3 | Management IP | primary IP | discovery source IP | Reliable if the management IP is stable |
| 4 | MAC address | management interface MAC | ARP or `ifPhysAddress` | Last resort; it can change on virtual chassis |

Rate gaps by consequence: a live-only device on a production network is Critical (it cannot be managed or automated); a SoT-only record still marked active is High (it misleads automation) and one marked decommissioned is Low; a hostname or management-IP mismatch is High, serial, model or firmware Medium, and description or rack position Low. Classify each result as **matched**, **SoT-only** (stale, or not reached by discovery: re-verify before calling it stale), **live-only** (an undocumented asset: the highest integrity risk, because it cannot be managed or automated) or **ambiguous** (several candidate matches, needs a human).

### Scoring the SoT

Four dimensions, each scoped to the devices you defined as in-scope:

- **Coverage:** `matched devices / total live devices * 100`. Under 90% means the SoT has blind spots that automation will inherit.
- **Accuracy:** `fields matching live / discoverable populated fields * 100`. Only fields with a live equivalent count (hostname, model, serial, interface state, IP assignment); rack position, notes and tags are not scoreable. Under 80% (Critical) points to systematic update failures.
- **Cable-record coverage:** the share of LLDP/CDP neighbours that have a matching SoT cable record (80% or more is good, under 60% critical).
- **Completeness:** `populated required fields / required fields * 100`, using a per-role field list (a core router needs a loopback and BGP ASN, an access switch needs its access VLANs).
- **Freshness:** average days since `last_updated` across in-scope records. A recent bulk import resets every timestamp, so flag it and leave freshness out of the composite for one cycle.

| Dimension | Good | Warning | Critical |
|---|---|---|---|
| Coverage | 95% or more | 90 to 95% | under 90% |
| Accuracy | 90% or more | 80 to 90% | under 80% |
| Completeness | 85% or more | 70 to 85% | under 70% |
| Freshness (average days) | under 30 | 30 to 90 | over 90 |

A composite for trending can weight them (for example coverage 30%, accuracy 30%, completeness 25%, freshness 15%). Convert freshness to a 0 to 100 scale first: 0 days = 100, 30 days = 80, 90 days = 50, 180 days or more = 0. Read the composite as good at 85 or more, warning from 70 to 85, critical under 70. The weights are a convention, not a standard: state them in the report, keep them fixed between cycles, and trend the four dimensions as well as the composite, alerting when any falls below its warning level or the composite drops by more than 5 points between cycles.

## When to reconcile

- **Scheduled**: a weekly or monthly baseline sweep.
- **Post-change**: after any change window, to confirm the network matches the updated intent.
- **Incident response**: when triaging an outage, drift against the SoT is a fast lead.
- **New-device onboarding**: reconcile the moment a device joins, to catch documentation gaps early.
- **Audit and compliance**: to evidence that intended state and actual state agree.

## Working with the rest of this skill and the vault

- **Intent side**: query the SoT platform per its reference in this skill: `netbox.md`, `nautobot.md`, or `infrahub.md`.
- **Live state**: collect device reality via the `pyats-network-automation` vault skill (CDP/LLDP neighbours, `show`-command output).
- **Topology**: the CDP/LLDP neighbour data driving `UNDOCUMENTED_LINK` and `CABLE_MISMATCH` is also what `network-topology-discovery` produces from the devices themselves; run it first when the SoT has no cable records to compare with.
- **Tickets**: CRITICAL and HIGH findings route into the ServiceNow change and incident workflow; a human owns the fix-or-update-SoT decision.
