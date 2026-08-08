# Streaming telemetry transport and subscription protocols

The device side of model-driven telemetry: how a device exposes structured state and how a collector subscribes to it. Four transports matter in practice, gNMI, gNOI, NETCONF/YANG-push, and Cisco Model-Driven Telemetry, all carrying YANG-modelled data rather than the flat OID space of SNMP.

## gNMI (gRPC Network Management Interface)

gNMI runs over gRPC (HTTP/2 + protobuf) and is the dominant streaming-telemetry transport. It defines four RPCs:

| RPC | Purpose | Direction |
|---|---|---|
| `Capabilities` | Discover the YANG models, versions, and encodings a target supports | Read |
| `Get` | Retrieve a snapshot of state or config at one or more paths | Read |
| `Set` | Apply configuration (update/replace/delete) | Write (config-push; owned by the automation skills) |
| `Subscribe` | Stream telemetry for one or more paths | Read |

Paths are structured, not strings: a gNMI path is a sequence of YANG path elements with keys (for example `/interfaces/interface[name=Ethernet1]/state/counters`), which is what lets a collector map a value to a stable metric identity across vendors.

### Subscribe modes

`Subscribe` has three subscription list modes:

- **STREAM**: a continuous subscription. Each path within it carries a per-path sub-mode:
  - **SAMPLE**: emit the value every `sample_interval` (for example every 10s). Use for continuously moving counters (interface bytes/packets, CPU, memory, queue depth).
  - **ON_CHANGE**: emit only when the value changes, after an initial sync. Use for state that is quiet then sudden (admin/oper status, session/adjacency state, alarms). Near-zero traffic until an event.
  - **TARGET_DEFINED**: the target chooses SAMPLE or ON_CHANGE per leaf based on the model. Convenient, but the behaviour is vendor-decided, so validate what you actually get.
- **ONCE**: send the current values once and close. A snapshot over the subscribe channel.
- **POLL**: the collector triggers each fetch explicitly. Rare; SAMPLE is usually preferred.

Match the sub-mode to how the data behaves: SAMPLE on a rarely-changing leaf wastes bandwidth and cardinality; ON_CHANGE on a monotonic counter never fires.

### Dial-in vs dial-out

- **Dial-in**: the collector opens the gRPC session to the device and subscribes. Simple to reason about; the collector must have IP reachability and credentials to every device.
- **Dial-out**: the device initiates the gRPC connection outward to a configured collector (destination-group) and pushes. Suits devices behind NAT and very large fan-in fabrics; needs device-side destination config and a collector that accepts inbound streams.

Standardise one model per administrative domain rather than mixing them per device.

### Encodings

- **JSON_IETF**: human-readable, interoperable, the safe multi-vendor default. Higher on-wire cost.
- **PROTO / GPB (self-describing)**: protobuf key-value; compact.
- **KV-GPB / compact GPB**: most efficient, but more vendor- and version-sensitive (the schema is tied to the device build). Use where throughput matters and the fleet is homogeneous.

Discover supported encodings with `Capabilities` before subscribing at scale.

### Typical vendor ports

Ports are deployment-configurable, but common defaults are: Cisco IOS-XR 57400, Juniper 32767 (native) or 50051 (gNMI), Arista EOS 6030, Nokia SR OS 57400. Confirm per platform and per image; do not hard-code.

## gNOI (gRPC Network Operations Interface)

gNOI is the operational-action sibling of gNMI: gRPC services for device operations rather than telemetry, for example `System.Reboot`, `System.Ping`, `File` (transfer), `Cert` (certificate rotation), and `OS` (image install). It is not a telemetry transport, but it shares the gRPC/mTLS channel and is often deployed alongside gNMI; mentioned here so a fleet's gRPC design accounts for both. Operational RPCs that change device state are config-adjacent and coordinate with the automation skills.

## NETCONF and YANG-push

NETCONF (RFC 6241) carries YANG data over SSH; YANG-push adds a subscription layer for telemetry:

- **RFC 8639** defines dynamic and configured subscriptions to a datastore.
- **RFC 8641** defines YANG-push: periodic subscriptions (a fixed period, like SAMPLE) and on-change subscriptions (like ON_CHANGE), with a dampening period to bound event storms.

`establish-subscription` (dynamic) or a configured subscription names a datastore XPath/subtree filter, a period or on-change trigger, and an encoding (XML or JSON). NETCONF/YANG-push is the standards-track path where a device lacks gNMI, and it reuses the NETCONF session and access model.

## Cisco Model-Driven Telemetry (MDT)

Cisco IOS-XR and IOS-XE express streaming telemetry through three config objects:

- **sensor-group**: the YANG/OpenConfig sensor paths to stream.
- **subscription**: binds a sensor-group to a sample interval (or on-change) and a destination.
- **destination-group**: where to send (collector IP/port, encoding, protocol).

MDT supports **dial-in** (collector subscribes over gNMI/gRPC) and **dial-out** (device pushes to the destination-group over gRPC, or legacy TCP/UDP). Encodings are typically GPB (compact or self-describing) or JSON. The sensor paths can be OpenConfig or Cisco-native YANG.

## OpenConfig vs native YANG sensor paths

- **OpenConfig** models are vendor-neutral; the same sensor path (for example `/interfaces/interface/state/counters`) works across vendors that implement it, which is what makes a multi-vendor collector tractable. Coverage varies by vendor and feature area.
- **Native YANG** models are vendor-specific and usually more complete for that vendor's features, at the cost of portability.

For a multi-vendor fleet, prefer OpenConfig paths where coverage exists and fall back to native models where it does not. Pin the model versions and validate paths against each device's advertised `Capabilities` before a fleet-wide subscription.

## Attribution and references

gNMI dial-in and the four-RPC model are genericised from the Apache-2.0 `automateyournetwork/netclaw` `gnmi-telemetry` skill (its MCP-server tool framing removed; the vendor port table and JSON_IETF defaults retained). Dial-out, gNOI, NETCONF/YANG-push, Cisco MDT, and OpenConfig details are authored from public standards and vendor documentation, cited not reproduced: the OpenConfig gNMI and gNOI specifications, RFC 6241 (NETCONF), RFC 8639 (subscription to YANG datastores), RFC 8641 (YANG-push), and the Cisco IOS-XR/IOS-XE model-driven telemetry configuration guides. Consult those for exact syntax and per-image support.
