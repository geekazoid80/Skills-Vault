---
name: interface-health
description: "Use for interface and link health assessment on Cisco (IOS-XE / NX-OS), Juniper (JunOS) and Arista (EOS): admin and oper state, CRC, input and output errors, runts and giants, input and output discards, interface flaps and resets, optical power (DOM) and laser bias, and utilisation, graded against severity tiers. Triggers include \"interface down\", \"interface flapping\", \"CRC errors\", \"input errors\", \"output drops\", \"packet loss on a link\", \"duplex mismatch\", \"giants\", \"runts\", \"SFP low Rx power\", \"DOM readings\", \"optic failing\", \"microburst\", \"link saturation\", \"err-disabled\", \"after cable or optic swap\". Physical and data-link layers only. NOT for routing-protocol or adjacency diagnosis (bgp-analysis, igp-routing-analysis, evpn-vxlan-fabric), NOT for wireless RF health (wireless-ops), NOT for choosing a monitoring platform (network-monitoring-selection), NOT for building the topology map (network-topology-discovery)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Interface health assessment

> **Skill marker**: When applying this skill, begin your reply with `[skill: interface-health]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Threshold-driven diagnosis of interface and link health. It covers the physical and data-link layers: error counters, optical power, discards, flaps and utilisation. Each metric is graded against four tiers (Normal, Warning, Critical, Emergency) with vendor-specific collection commands.

Commands are labelled **[Cisco]**, **[JunOS]** or **[EOS]** where syntax diverges; unlabelled statements apply to all three. Syntax was written from vendor documentation and was not run against devices while authoring, so confirm it on the release and platform you operate. Command syntax is in `references/cli-reference.md`; the full per-metric tables and the per-optic-type ranges are in `references/threshold-tables.md`.

**Posture.** Read-only throughout: `show` commands only. Nothing here is run to change state. The remedies the decision trees lead to (bouncing a port, forcing speed or duplex, clearing counters, swapping hardware) are recommendations for after the root cause is found, and clearing counters destroys the evidence you were comparing, so record the values first.

## When to use

- An interface is reported down or flapping.
- Users report packet loss or poor throughput on a link.
- A monitoring alert fires for CRC errors, input errors or output drops.
- Validating link quality before and after a cable or optic swap.
- Optical power alarms from DOM (digital optical monitoring).
- Capacity planning: finding interfaces nearing saturation.
- Latency spikes that correlate with congestion on an interface.
- A baseline for a new link turn-up or circuit migration.

## When not to use

- **The interface is up and clean but the routing adjacency is not:** `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`. Come back here only if the adjacency problem traces to a flapping link.
- **Wireless RF, channel and client health:** `wireless-ops`.
- **Choosing or designing monitoring (SNMP versus flow versus streaming telemetry):** `network-monitoring-selection`, with `network-streaming-telemetry` for sub-second visibility into microbursts.
- **Finding what is on the other end of a link:** `network-topology-discovery`.
- **Before-and-after proof for a change window:** `change-verification`; use this skill's counters as part of that baseline.
- **Firewall or load-balancer interface problems:** the platform audit skills; the counters here are the generic router and switch set.

## Prerequisites

- SSH or console access (read-only privilege is enough).
- The interfaces to evaluate: specific ones, or all active.
- A baseline or earlier snapshot for delta comparison. Without one only instantaneous rates and absolute counters are available.
- The expected link parameters: speed, duplex, media (copper or fibre), SFP model and cable distance.
- For optical checks, DOM-capable SFP or QSFP modules.
- Credentials handled per `secrets-hygiene`.

## Procedure

Work through the steps in order. Early steps are broad; later steps drill into the failure domain the earlier ones point at.

### Step 1: Interface status overview

Collect admin state, oper state, speed, duplex and media for every interface under review.

- **[Cisco]** `show interfaces status`, `show interfaces [intf] | include line protocol|BW|duplex`
- **[JunOS]** `show interfaces terse`, `show interfaces [intf] | match "Physical|Speed|Duplex|Link-level"`
- **[EOS]** `show interfaces status`, `show interfaces [intf] | include line protocol|BW|duplex`

An interface that is admin up but oper down needs attention first; jump to the decision trees. A duplex mismatch (one end full, the other half) causes late collisions and must be fixed before error analysis means anything.

### Step 2: Error counter analysis

Counters are cumulative since the last clear, so always take a delta over a known interval (at least 5 minutes) to get a usable rate.

- **[Cisco]** `show interfaces [intf] | include CRC|input errors|output errors|frame|runts|giants`, `show interfaces [intf] counters errors`
- **[JunOS]** `show interfaces [intf] extensive | match "CRC|Errors|Framing|Runts|Giants"`
- **[EOS]** `show interfaces [intf] counters errors`, `show interfaces [intf] | include CRC|input errors|output errors|runts|giants`

What each counter tells you:

- **CRC errors:** corrupted frames; a physical-layer problem (bad cable, dirty fibre, failing SFP, interference).
- **Input errors:** the superset (CRC, frame, overrun); the aggregate receive-path indicator.
- **Output errors:** transmit failures, often buffer exhaustion or congestion.
- **Frame errors:** non-integer-octet frames; usually a duplex mismatch or a bad NIC.
- **Runts:** frames under 64 bytes; collision fragments or a bad NIC.
- **Giants:** oversized frames; an MTU mismatch between the endpoints.

Anything incrementing steadily at Warning or above deserves investigation. A stale historical value that is not moving is not a finding.

### Step 3: Discard analysis

Input and output discards have different causes, so read them separately.

- **[Cisco]** `show interfaces [intf] | include drops|discard|queue`, `show policy-map interface [intf]`
- **[JunOS]** `show interfaces queue [intf]`, `show class-of-service interface [intf]`
- **[EOS]** `show interfaces [intf] counters discards`, `show qos interface [intf]`

- **Output discards:** the transmit ring is full. Sustained congestion, poor QoS scheduling, or microbursts overrunning shallow buffers.
- **Input discards:** the receive ring is full. The CPU cannot keep up (control-plane punt), an input policer is dropping, or the receive buffer is exhausted.
- **Queue drops:** per-queue drops show which traffic class is affected, which sets the priority of the fix.

High output discards with low average utilisation is the signature of microbursts: spikes shorter than the polling interval that never show in a 5-minute average.

### Step 4: Resets and flap detection

- **[Cisco]** `show interfaces [intf] | include resets|Last input|Last output|last change`
- **[JunOS]** `show interfaces [intf] extensive | match "Last flapped|Resets"`
- **[EOS]** `show interfaces [intf] | include resets|Last input|Last output`, `show logging | include [intf].*up|[intf].*down`

Record reset counts and last-flap times, then correlate flaps with error spikes. A link that flaps and collects CRC errors on recovery has a physical problem (loose cable, marginal SFP). Frequent resets with no errors point to auto-negotiation failure or spanning-tree reconvergence.

### Step 5: Optical power

For fibre ports with DOM-capable optics, read Tx power, Rx power, laser bias current and module temperature.

- **[Cisco]** `show interfaces [intf] transceiver detail`
- **[JunOS]** `show interfaces diagnostics optics [intf]`
- **[EOS]** `show interfaces [intf] transceiver detail`

- **Tx power (dBm):** out of range means a degrading or failed SFP.
- **Rx power (dBm):** low Rx with normal far-end Tx means attenuation (dirty connector, bend loss, excess distance, bad splice).
- **Laser bias current (mA):** rising over time means the SFP is ageing; high bias with falling Tx means it is compensating for decline.
- **Temperature:** high temperature accelerates ageing and causes errors.

Compare against the SFP's own embedded alarm and warning thresholds, which every vendor exposes in the DOM output, and against the per-optic ranges in `references/threshold-tables.md` (1G-SX, 10G-SR, 10G-LR, 25G-SR, 100G-SR4).

### Step 6: Utilisation

- **[Cisco]** `show interfaces [intf] | include input rate|output rate|reliability`, `show interfaces [intf] summary`
- **[JunOS]** `show interfaces [intf] traffic`, `show interfaces [intf] statistics traffic`
- **[EOS]** `show interfaces [intf] | include input rate|output rate`, `show interfaces [intf] counters rates`

Utilisation is rate divided by interface speed. The CLI "input rate" and "output rate" figures are usually 5-minute weighted averages and hide bursts. For burst detection, correlate with output discards (Step 3) and use shorter polling or streaming telemetry where available.

## Threshold tables

Summary of the headline thresholds. The full tables, with meaning and action per tier, are in `references/threshold-tables.md`. Treat them as defaults and adjust for high-throughput links or links with known baseline noise.

| Metric | Normal | Warning | Critical | Emergency |
|---|---|---|---|---|
| CRC errors per 5 min | 0 | 1 to 5 | 6 to 50 | over 50 |
| Input errors per 5 min | 0 to 2 | 3 to 20 | 21 to 100 | over 100 |
| Output discards per 5 min | 0 to 10 | 11 to 100 | 101 to 1,000 | over 1,000 |
| Interface resets per hour | 0 | 1 to 2 | 3 to 10 | over 10 |
| Rx power against the optic's range | within spec | in the Warning band | in the Critical band | below low-alarm |
| Utilisation | 0 to 50% | 51 to 75% | 76 to 90% | over 90% |

## Decision trees

### High error rate

```
Errors incrementing (CRC, input, frame)
├── One interface?
│   ├── Yes: physical layer
│   │   ├── Fibre?
│   │   │   ├── Rx power low: clean connectors, check the fibre run
│   │   │   ├── Rx power normal: reseat the SFP
│   │   │   └── SFP temperature high: check airflow, replace the SFP
│   │   └── Copper?
│   │       ├── Check length (under 100 m for Cat6)
│   │       ├── Look for interference sources along the run
│   │       └── Swap the cable for a known-good one
│   └── No: several interfaces
│       ├── Same line card or module: suspect the card
│       ├── Same patch panel: suspect the panel or tray
│       └── All interfaces: suspect upstream power or grounding
├── Frame errors specifically: check duplex on both ends
├── Giants specifically: check MTU on both ends, and jumbo-frame settings
└── Runts specifically: collision domain or a bad NIC on the connected device
```

### High discards

```
Discards incrementing
├── Output discards
│   ├── Utilisation over 75%: congestion; add capacity or ECMP
│   ├── Utilisation under 50% but discards high: microbursts
│   │   ├── Check per-queue drops to find the traffic class
│   │   └── Tune buffers or QoS scheduling
│   └── A QoS policy applied
│       ├── Policer or shaper too tight
│       └── Priority queue starving best-effort
├── Input discards
│   ├── CPU-bound traffic: check control-plane policing counters for punt drops
│   ├── Input policer: compare its rate with actual traffic
│   └── Receive buffer exhaustion: rare; look for flood traffic
└── Sustained or intermittent
    ├── Sustained: a capacity issue; plan the upgrade
    └── Intermittent: burst-driven; tune buffers or QoS
```

### Optical power out of range

```
Optical reading outside the normal range
├── Rx power low
│   ├── Far-end Tx normal: a fibre path problem
│   │   ├── Clean both connectors (isopropyl wipes, not compressed air alone)
│   │   ├── Check bends against the minimum bend radius
│   │   ├── Check distance against the SFP specification
│   │   └── OTDR the run if available
│   └── Far-end Tx also low: the far SFP is failing
├── Tx power low
│   ├── Laser bias high: SFP degrading; plan replacement
│   ├── Laser bias normal: check SFP configuration and compatibility
│   └── Temperature high: fix cooling, then re-read Tx
├── Rx power high
│   └── A short run with no attenuator: add an inline attenuator
└── Temperature alarm
    ├── Ambient normal: SFP internal fault; replace
    └── Ambient high: fix chassis or room cooling first
```

## Report template

```
INTERFACE HEALTH REPORT
========================
Device: [hostname]
Vendor: [Cisco | JunOS | EOS]
Check time (UTC): [timestamp]
Performed by: [name or team]

INTERFACE SUMMARY
- Interfaces reviewed: [n]
- Admin up / oper up: [n]
- Admin up / oper down: [n] [list]
- With active errors: [n]
- With discards: [n]

FINDINGS
1. [Severity] [Category]: [description]
   Interface: [name]
   Observed: [value and rate]
   Threshold crossed: [Normal / Warning / Critical / Emergency boundary]
   Root cause: [from the decision tree]
   Action: [recommended remediation]

OPTICAL STATUS
- Interfaces with DOM data: [n]
- Rx power warnings: [list with dBm]
- Tx power warnings: [list with dBm]
- SFPs approaching end of life (rising bias): [list]

UTILISATION
- Over 75%: [list with peak and average]
- Over 90%: [list, needs attention now]

RECOMMENDATIONS
- [Prioritised actions]

NEXT CHECK: [Emergency 1 h | Critical 4 h | Warning 24 h | Normal 7 d]
```

## Troubleshooting

### CRC errors on fibre with normal optical power

Power within spec but CRC still climbing. Likely causes: mismatched SFP types (for example SX into LR), dirt inside the SFP cage rather than on the fibre tip, or a non-qualified optic the switch tolerates badly. Clean the receptacle, confirm both ends use the same type, and test with a vendor-qualified optic.

### Output discards with low utilisation

Under about 50% average with discards climbing is almost always microbursts. Look at per-queue drop counters for the affected class and the interface buffer allocation. Fix with QoS scheduling changes, deeper buffers or shaping at the ingress point.

### Interface stays down/down after a cable swap

Check that the SFP is fully seated, that fibre polarity is right (Tx to Rx crossover), that both ends use the same type, and that speed and duplex are auto or matched. On **[Cisco]**, check `show interfaces [intf] | include err-disabled`: BPDU guard, UDLD or link-flap detection may have disabled the port. After fixing the cause, `shutdown` then `no shutdown` recovers it.

### Flapping with zero errors

Cycling every few seconds with clean counters points to negotiation or protocol, not the cable. Suspect auto-negotiation incompatibility (force speed and duplex on both ends), spanning-tree topology changes causing repeated block and forward transitions, or UDLD aggressive mode seeing a unidirectional link.

### Laser bias rising while Tx power holds

The laser is being driven harder to hold its output, which is normal ageing and a warning that it will fail. Track the trend; once bias exceeds about 80% of the manufacturer's maximum, schedule replacement within 30 days.

## Cross-references

- `network-topology-discovery`: find the far end of a suspect link, and confirm it from both sides.
- `change-verification`: counters here form part of the baseline for a cable, optic or linecard change.
- `igp-routing-analysis`, `bgp-analysis`, `evpn-vxlan-fabric`: when a flapping link is the cause of an adjacency problem, diagnose the protocol effect there.
- `network-monitoring-selection`: SNMP polling, flow and streaming telemetry each see different faults; pick the one that can see microbursts if that is the problem. See also `network-streaming-telemetry`.
- `multi-vendor-network-ops`: the diagnose-first entry point and the nine-element response contract for any production-impacting remedy.
- `completion-gate` Layer 3: no "link fixed" claim without fresh counters, taken over a real interval, in the same turn.
- `oncall-runbooks` and `incident-response-network`: when a link failure becomes an incident.

## Red flags

- About to read cumulative counters as a rate without taking a delta.
- About to call an interface healthy from a single snapshot with no baseline.
- About to blame the optic when Rx power is low and the far-end Tx has not been checked.
- About to replace hardware before checking duplex and MTU on both ends.
- About to quote a 5-minute average as proof there is no congestion.
- About to bounce a port, clear counters or change speed or duplex while still assessing.
- About to apply the 10G-SR thresholds to a different optic type.
- About to declare the fix done without fresh counters after the repair.

## Bottom line

Take deltas, not totals. Work from state to errors to discards to flaps to optics to load, grade each against its tier, and let the decision trees pick the physical cause before anything is replaced. Fix and verify with fresh counters over a real interval.

## Provenance

Re-authored from the Apache-2.0 `interface-health` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; vendor commands, severity tiers, optic ranges, decision trees and report template kept; cross-references repointed to this vault.
