---
name: network-streaming-telemetry
description: Use for model-driven streaming network telemetry, the push-based alternative to SNMP polling, and the receiver/collector tier that terminates the streams. Covers gNMI (Capabilities, Get, Set, Subscribe with SAMPLE, ON_CHANGE, and TARGET_DEFINED modes; dial-in versus dial-out gRPC), gNOI operational RPCs, NETCONF and YANG-push subscriptions (RFC 8639/8641 periodic and on-change), Cisco Model-Driven Telemetry (sensor-group, subscription, destination-group), OpenConfig and native YANG sensor paths, and encodings (JSON_IETF, protobuf/GPB, KV-GPB). Covers the collector tier that receives and normalises the streams (gnmic, Telegraf gNMI and cisco_telemetry_mdt inputs, the OpenTelemetry gNMI/OpenConfig receiver), TLS/mTLS to targets, dial-out target configuration on devices, pipeline buffering and backpressure, and scaling receivers. Also frames when model-driven streaming telemetry beats SNMP polling (sub-second, event-driven ON_CHANGE, structured YANG, cardinality and scale trade-offs) and per-platform support (Cisco IOS-XR/IOS-XE, Juniper Junos, Arista EOS, Nokia SR OS). Triggers include "streaming telemetry", "model-driven telemetry", "gNMI", "gNMI subscribe", "gNMI dial-out", "gNOI", "NETCONF telemetry", "YANG-push", "RFC 8641", "Cisco MDT", "sensor-group", "OpenConfig", "YANG sensor path", "telemetry subscription", "gnmic", "Telegraf gNMI", "telemetry collector", "telemetry receiver", "telemetry pipeline", "push versus poll", "ON_CHANGE telemetry". For flow analytics (NetFlow, sFlow, IPFIX) see network-monitoring-selection and kentik-network-monitoring; for SNMP polling and NMS design see network-monitoring-selection; for the metrics store, dashboards, and traces the collectors feed see prometheus-configuration, grafana-dashboards, and distributed-tracing; for gNMI as a config-push automation transport see ansible-network-modules, nornir-automation, and napalm-netmiko.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network streaming telemetry

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-streaming-telemetry]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns **model-driven streaming telemetry**: how a network device pushes structured, high-frequency operational state off-box (gNMI, gNOI, NETCONF/YANG-push, Cisco MDT over OpenConfig or native YANG), and the receiver/collector tier that terminates those streams and normalises them for a time-series store. It is the push-based counterpart to the poll-based paradigms in `network-monitoring-selection`: that umbrella frames the classic four (SNMP polling, flow analytics, synthetic, packet capture) and selects platforms; this skill owns the fifth, streaming telemetry, and the collector that receives it.

The boundary is deliberate. Everything flow-shaped (NetFlow, sFlow, IPFIX) is already owned elsewhere and is cross-referenced out, not repeated here. Everything metrics-store-shaped, dashboard-shaped, or trace-shaped belongs to the observability skills; this skill hands the normalised stream off to them and stops.

## When to use

- Deciding whether model-driven streaming telemetry should replace or augment SNMP polling for a given signal (high-frequency counters, event-driven state, structured YANG data).
- Designing a gNMI subscription: choosing SAMPLE vs ON_CHANGE vs TARGET_DEFINED, sample interval, dial-in vs dial-out, and the sensor paths to subscribe to.
- Configuring device-side telemetry: Cisco MDT sensor-group/subscription/destination-group, Junos native/gRPC telemetry, Arista EOS or Nokia SR OS streaming, NETCONF/YANG-push subscriptions.
- Standing up or choosing a receiver/collector: gnmic, Telegraf's gNMI or cisco_telemetry_mdt input, the OpenTelemetry gNMI/OpenConfig receiver, and wiring TLS/mTLS to targets.
- Designing the telemetry pipeline: collect, normalise, buffer against backpressure, and hand off to a TSDB or Kafka, then scale the receiver tier.
- Choosing OpenConfig vs native YANG sensor paths and an encoding (JSON_IETF, protobuf/GPB, KV-GPB) for a multi-vendor fleet.

## When not to use

- **Flow analytics (NetFlow, sFlow, IPFIX) for traffic analysis**: `network-monitoring-selection` owns the flow paradigm and design, and `kentik-network-monitoring` owns a flow engine end to end. Streaming telemetry and flow are different data planes; do not fold flow in here.
- **SNMP polling, traps, syslog, and NMS design/selection**: `network-monitoring-selection` owns the poll-based paradigms, the golden signals, alerting design, and platform choice. This skill owns only the streaming-telemetry paradigm and the receiver tier.
- **The metrics store, dashboards, and traces the collector feeds**: `prometheus-configuration` owns the metrics backend and PromQL, `grafana-dashboards` owns visualisation, and `distributed-tracing` owns OpenTelemetry spans and trace context. This skill collects and normalises the stream and hands it off; it does not own the store or the dashboard. `zabbix-templates-and-triage` owns Zabbix.
- **gNMI/NETCONF as a configuration-push transport**: when the task is pushing config (gNMI Set, NETCONF edit-config, resource modules), device automation is owned by `ansible-network-modules`, `nornir-automation`, and `napalm-netmiko`. This skill owns the telemetry-subscription and receiver half, not general config automation.
- **Interpreting the protocol semantics carried in a telemetry stream** (why a BGP session flapped, why an OSPF adjacency dropped): `bgp-analysis` and `igp-routing-analysis` own protocol diagnosis. This skill transports and collects the state; those read it.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Transport + subscription | gNMI modes and RPCs, dial-in vs dial-out, NETCONF/YANG-push, Cisco MDT config, gNOI, OpenConfig/YANG sensor paths, encodings | `references/protocols-and-subscriptions.md` |
| Collector + pipeline | gnmic, Telegraf gNMI/MDT inputs, OTel gNMI receiver, TLS/mTLS, dial-out target config, buffering/backpressure, scaling, hand-off to TSDB/Kafka | `references/collectors-and-pipeline.md` |
| Paradigm + platform | streaming vs SNMP vs flow, when MDT beats polling, cardinality/scale trade-offs, per-vendor support and maturity, adoption guidance | `references/paradigm-and-platform.md` |

## Core model (condensed)

**Streaming telemetry is push, not poll.** SNMP asks the device for a value on an interval; model-driven telemetry has the device stream the value out on its own, either on a sample timer or the moment it changes. That inverts the cost model: the device does the work once and fans out, the collector never walks an OID tree, and event-driven state (an interface going down, a BGP session resetting) arrives in milliseconds instead of at the next poll. Reach for it when the signal is high-frequency, event-driven, or wants structured YANG context that SNMP cannot express.

**Pick the subscription mode from the signal.** ON_CHANGE for state that is quiet then sudden (admin/oper status, session state, alarms): near-zero traffic until an event, then instant. SAMPLE (a fixed interval) for continuously moving counters (interface bytes, CPU, queue depth). TARGET_DEFINED lets the device pick per-path. Choosing SAMPLE for a rarely-changing leaf wastes bandwidth and cardinality; choosing ON_CHANGE for a monotonic counter never fires. Match the mode to how the data actually behaves.

**Dial-in vs dial-out is an operational choice, not just a protocol one.** Dial-in (the collector opens the gRPC session and subscribes) is easy to start and easy to reason about, but the collector must reach every device. Dial-out (the device initiates the connection to a known collector) suits devices behind NAT or in large fan-in fabrics and survives collector discovery, at the cost of device-side destination-group config and a collector that accepts inbound streams. Standardise one per domain.

**The collector tier is where telemetry becomes usable.** A device stream is a firehose of path/value/timestamp tuples; the collector (gnmic, Telegraf, an OTel receiver) terminates the gRPC/subscription, decodes the encoding, normalises paths into a consistent metric model, and forwards to a store. Design for backpressure (bounded queues, drop-or-block policy), TLS/mTLS to every target, and horizontal scale (shard targets across collector instances) before the fleet grows. The store, the alerting, and the dashboard are downstream and owned by the observability skills.

**Encoding and sensor-path choice decide portability.** Prefer OpenConfig sensor paths where a vendor supports them for a multi-vendor fleet; fall back to native YANG where OpenConfig coverage is thin. JSON_IETF is the interoperable default; protobuf/GPB and KV-GPB are more efficient but more vendor- and version-sensitive. Pin the YANG models and validate paths against the device's advertised capabilities before subscribing at scale.

**Anti-patterns:** streaming a leaf with SAMPLE when ON_CHANGE would send nothing until it matters; subscribing to a whole subtree "to be safe" and drowning the collector in cardinality; running one collector for a fabric that needs sharding; skipping TLS because "it is just telemetry" (the stream carries topology and state); treating streaming telemetry as a flow replacement (it is not, flow answers who-talked-to-whom); re-implementing a metrics store in the collector instead of handing off to Prometheus/Grafana.

## Reference router

| Need | Load |
|---|---|
| gNMI RPCs and subscription modes, dial-in vs dial-out, NETCONF/YANG-push (RFC 8639/8641), Cisco MDT config, gNOI, OpenConfig/native YANG sensor paths, encodings | `references/protocols-and-subscriptions.md` |
| Collector choice and config (gnmic, Telegraf gNMI/cisco_telemetry_mdt, OTel gNMI receiver), TLS/mTLS, dial-out target config, buffering/backpressure, scaling, hand-off to TSDB/Kafka | `references/collectors-and-pipeline.md` |
| Streaming vs SNMP vs flow, when MDT beats polling, cardinality/scale, per-vendor support and maturity, adoption path | `references/paradigm-and-platform.md` |

## Cross-references

- `network-monitoring-selection`: the NMS design umbrella. It owns the classic four paradigms (SNMP polling, flow, synthetic, packet capture), golden signals, alerting design, and platform selection; this skill is the fifth paradigm it routes streaming telemetry out to. Reciprocal reference.
- `kentik-network-monitoring`: flow analytics (NetFlow/IPFIX/sFlow ingest and enrichment). Streaming telemetry is a different data plane; flow questions go there.
- `prometheus-configuration`: the metrics store a telemetry collector commonly writes to; gnmic and Telegraf both output to Prometheus. This skill collects and normalises; Prometheus stores and alerts.
- `grafana-dashboards`: the visualisation layer over the stored telemetry. The collector feeds it via the store.
- `distributed-tracing`: the OpenTelemetry counterpart for application traces; the OTel Collector's gNMI/OpenConfig receiver is one collector option covered here, but span/trace pipelines are owned there.
- `ansible-network-modules`, `nornir-automation`, `napalm-netmiko`: device config automation, including gNMI Set and NETCONF edit-config as a config transport. This skill owns the telemetry-subscription and receiver half; those own config push.
- `bgp-analysis`, `igp-routing-analysis`: protocol diagnosis of the state a telemetry stream carries. This skill transports BGP/IGP sensor paths; those interpret them.
- `multi-vendor-network-ops`: diagnose-first operations that consume telemetry as an input artefact during a wider production change.
- `secrets-hygiene`: gNMI/gRPC client certificates, mTLS keys, and device credentials live in the secret store, never inline in a subscription config or a collector manifest.

## Red flags

- About to subscribe to a monotonic counter with ON_CHANGE (it will never fire) or a rarely-changing leaf with SAMPLE (constant waste).
- About to subscribe to an entire YANG subtree without scoping the sensor paths, multiplying collector cardinality for data nobody reads.
- About to run a single collector for a fabric that needs target sharding, then wondering why updates lag or drop.
- About to disable TLS on a telemetry session because "it is only monitoring" (the stream exposes topology, addressing, and live state).
- About to treat streaming telemetry as a flow replacement, or to fold NetFlow/sFlow/IPFIX in here instead of routing to `network-monitoring-selection` and `kentik-network-monitoring`.
- About to build a metrics store or alerting inside the collector instead of handing off to `prometheus-configuration` and `grafana-dashboards`.
- About to put a gNMI client key or device credential inline in a collector config instead of the secret store.

## Bottom line

Model-driven streaming telemetry is the push paradigm SNMP polling is not: the device streams structured YANG state on a sample timer or the instant it changes, and a collector (gnmic, Telegraf, an OTel receiver) terminates the stream, normalises it, and hands it off to a store. Pick ON_CHANGE for event-driven state and SAMPLE for moving counters; pick dial-in for reachable fleets and dial-out for NAT/fan-in; prefer OpenConfig paths and JSON_IETF for portability; secure every session with TLS and scale the collector before the fleet does. Keep flow, SNMP, the metrics store, and config-push out of scope: route them to the skills that own them, and let this skill own the stream and its receiver.
