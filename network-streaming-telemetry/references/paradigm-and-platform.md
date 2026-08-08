# The streaming-telemetry paradigm and platform support

This reference frames model-driven streaming telemetry as a monitoring paradigm alongside the four that `network-monitoring-selection` owns (SNMP polling, flow analytics, synthetic, packet capture), and maps vendor support so an adoption decision is grounded. Load it when the question is "should we stream telemetry at all, and what does our kit support".

## Streaming telemetry vs SNMP polling vs flow

| Dimension | SNMP polling | Model-driven streaming telemetry | Flow analytics |
|---|---|---|---|
| Model | Pull: collector asks on an interval | Push: device streams on sample or on change | Push: device exports flow records |
| Data | Flat OID tree, per-request walk | Structured YANG (OpenConfig/native) | Per-flow 5-tuple + counters |
| Latency to signal | One poll interval (30s to 5m typical) | Sub-second (SAMPLE) or event-time (ON_CHANGE) | Export/active-timeout bound |
| Best for | Device health at modest frequency | High-frequency counters, event-driven state, structured context | Who-talked-to-whom, capacity, top-talkers |
| Cost model | Collector CPU walks trees; scales poorly at high frequency | Device fans out once; collector decodes a stream | Sampled at high volume |
| Owner in this vault | `network-monitoring-selection` | **this skill** | `network-monitoring-selection` (design) + `kentik-network-monitoring` (engine) |

The three are complementary, not substitutes. A mature stack polls slow-moving inventory with SNMP, streams high-frequency and event-driven state with telemetry, and analyses traffic with flow. Streaming telemetry does not answer a traffic-matrix question (that is flow) and flow does not answer an interface-error-rate-at-one-second question (that is telemetry).

## When model-driven telemetry beats SNMP

Reach for streaming telemetry when at least one holds:

- **Frequency**: you need sub-second or few-second granularity that SNMP polling cannot reach without hammering the device.
- **Event latency**: you need to know the instant a state changes (link down, BGP reset, alarm) rather than at the next poll (ON_CHANGE).
- **Structure**: you need YANG-modelled context (nested state, keyed lists) that flat OIDs cannot express cleanly.
- **Scale of collection**: walking large OID trees across a big fleet is saturating your pollers; push telemetry moves that cost onto the device once.

Stay on SNMP when the signal is slow-moving, the fleet is old or lacks telemetry support, or the operational cost of a telemetry pipeline is not justified by the signal.

## Cardinality and scale trade-offs

Streaming telemetry is easy to over-collect. Every subscribed leaf on every interface on every device is a time series; a broad subtree subscription can multiply cardinality by orders of magnitude and overwhelm both the collector and the store. Discipline:

- Subscribe to specific sensor paths, not whole subtrees "to be safe".
- Choose ON_CHANGE for state and SAMPLE only for genuinely moving counters.
- Set sample intervals to the slowest that meets the need.
- Shard collectors and watch collector-side cardinality metrics.

The store's cost (retention, indexing) is downstream and owned by `prometheus-configuration`, but the cardinality decision is made here, at subscription design.

## Per-vendor support (indicative)

Support and OpenConfig coverage move with software release; confirm against the running image and the device's advertised gNMI `Capabilities`. As a starting map:

| Platform | Transports | Notes |
|---|---|---|
| Cisco IOS-XR | gNMI, MDT (dial-in/dial-out), NETCONF/YANG-push | Strong OpenConfig + native (Cisco-IOS-XR-*) coverage; GPB/JSON |
| Cisco IOS-XE | gNMI, MDT, NETCONF/YANG-push | Growing OpenConfig coverage; MDT well established |
| Cisco NX-OS | gNMI, MDT | Telemetry via gRPC; model coverage varies by release |
| Juniper Junos | gNMI, native gRPC (Junos Telemetry Interface), NETCONF | Native JTI plus OpenConfig; JTI sensors distinct from gNMI paths |
| Arista EOS | gNMI (dial-in), state streaming | Strong OpenConfig; EOS state APIs |
| Nokia SR OS / SR Linux | gNMI | SR Linux is gNMI-native; strong OpenConfig |
| Cumulus / SONiC | gNMI (varies) | Coverage depends on distribution and agents |

Prefer OpenConfig sensor paths across a mixed fleet; fall back to native models where OpenConfig coverage is thin for a given feature.

## Adoption path

1. **Dual-run**: keep SNMP as the baseline and add telemetry for a few high-value, high-frequency signals (interface counters, CPU, BGP/adjacency state).
2. **Validate**: compare telemetry values against SNMP/CLI for the same leaf before trusting them (the netclaw upstream's gNMI-vs-CLI comparison workflow is the idea).
3. **Scope**: pick sensor paths deliberately; do not lift-and-shift the whole MIB into a subtree subscription.
4. **Migrate signal by signal**: move a signal off SNMP only once its telemetry equivalent is validated and the collector/store path is stable.
5. **Standardise**: one subscription model (dial-in or dial-out), one preferred encoding, OpenConfig-first paths, per administrative domain.

## Attribution and references

Authored from public standards and vendor documentation, cited not reproduced: the OpenConfig gNMI specification and OpenConfig models, RFC 8641 (YANG-push), and the Cisco IOS-XR/IOS-XE, Juniper Junos Telemetry Interface, Arista EOS, and Nokia SR OS/SR Linux telemetry documentation. The dual-run and gNMI-vs-CLI validation approach is consistent with the Apache-2.0 `automateyournetwork/netclaw` `gnmi-telemetry` skill (genericised). Per-vendor support is indicative and moves with release; verify against the running image.
