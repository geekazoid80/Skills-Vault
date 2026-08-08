# Telemetry collectors and the receiver pipeline

A device stream is a firehose of path, value, and timestamp tuples in some encoding. The collector tier terminates the gRPC or subscription session, decodes the encoding, normalises paths into a stable metric model, and forwards to a store. This reference covers the collector choices and the pipeline design around them. The store, the alerting, and the dashboards are downstream and owned by the observability skills.

## What a collector does

1. **Terminate** the transport (gNMI Subscribe, MDT dial-out, NETCONF/YANG-push).
2. **Authenticate** with TLS/mTLS to the target (dial-in) or authenticate the inbound device (dial-out).
3. **Decode** the encoding (JSON_IETF, GPB, KV-GPB) into typed values.
4. **Normalise** the YANG path into a consistent metric name plus labels/tags, so the same signal from different vendors lands on the same series.
5. **Buffer** against downstream slowness, then **forward** to a time-series store, a message bus, or both.
6. **Scale** by sharding targets across collector instances.

## Collector options

### gnmic

`gnmic` is a purpose-built, vendor-neutral gNMI CLI and collector (an OpenConfig community tool). It subscribes to targets, supports SAMPLE/ON_CHANGE, and fans out to multiple outputs (Prometheus, InfluxDB, Kafka, NATS, file, TCP). It supports a clustered mode where multiple gnmic instances share a target set for horizontal scale and failover, with target distribution coordinated through a locker (for example Consul). It is the usual first choice for a gNMI-first fleet.

### Telegraf

Telegraf (the InfluxData agent) has two relevant input plugins:

- **`gnmi` (a.k.a. cisco_telemetry_gnmi)**: dial-in gNMI subscriptions, OpenConfig or native paths, SAMPLE/ON_CHANGE.
- **`cisco_telemetry_mdt`**: receives Cisco MDT dial-out streams (gRPC/TCP), decoding GPB.

Telegraf's output plugins then write to Prometheus, InfluxDB, Kafka, and many others, and its processor plugins can rename/tag on the way through. Useful when a site already runs Telegraf for host metrics and wants one agent.

### OpenTelemetry Collector

The OTel Collector has network-telemetry receivers (a gNMI/OpenConfig receiver among the contrib receivers) that ingest streaming telemetry into the OTel pipeline model (receivers, processors, exporters). This suits shops standardising on OpenTelemetry across application and network signals; the span/trace side of OTel is owned by `distributed-tracing`, but the same collector process can carry both.

## TLS and mTLS to targets

Every telemetry session should be encrypted; the stream exposes topology, addressing, interface names, and live state. Design for:

- Server-side TLS at minimum (collector verifies the device certificate against a CA).
- mTLS where the platform supports it (device also verifies the collector's client certificate).
- Client keys and CA material sourced from the secret store, never inline in a collector manifest (see `secrets-hygiene`).

For dial-out, the device presents (or verifies) certificates outbound to the collector's listener; plan the PKI so device certificates are issued and rotatable (gNOI `Cert` can rotate them).

## Dial-out target configuration

For dial-out, the device needs a destination-group naming the collector endpoint, the encoding, and the protocol; the collector needs an inbound listener that accepts and authenticates those device connections (Telegraf `cisco_telemetry_mdt`, or a gnmic/OTel dial-out listener). Dial-out shifts reachability from the collector to the device and scales fan-in cleanly, at the cost of device-side config to maintain.

## Buffering and backpressure

A collector must not lose the plot when the store slows down. Design an explicit policy:

- Bounded in-memory queues with a defined overflow behaviour (drop-oldest, drop-new, or block-and-apply-backpressure to the subscription).
- A durable buffer (Kafka, or the store's own WAL/remote-write queue) where loss is unacceptable.
- Metrics on the collector itself (queue depth, drop count, export latency) so backpressure is visible before it becomes data loss.

ON_CHANGE subscriptions are bursty by nature (quiet, then a storm during a fault); size buffers for the burst, not the average.

## Hand-off to the store

The collector's job ends at a normalised, forwarded stream. Common hand-offs:

- **Prometheus**: gnmic and Telegraf both expose/scrape or remote-write; `prometheus-configuration` owns the store, retention, and alerting.
- **InfluxDB / other TSDB**: Telegraf's native path.
- **Kafka / NATS**: a bus for fan-out to multiple consumers (a TSDB, a stream processor, a data lake) and for durable buffering.

Dashboards over any of these are owned by `grafana-dashboards`. Do not rebuild a metrics store, retention policy, or alert engine inside the collector; hand off and stop.

## Scaling the receiver tier

- **Shard targets** across collector instances (gnmic clustering, or static partitioning by device group).
- Keep a collector close to its targets in large or multi-site fabrics to bound WAN exposure and latency, mirroring the distributed-polling logic in `network-monitoring-selection`.
- Watch **cardinality**: subscribing to broad subtrees multiplies series; scope sensor paths to what is actually consumed.

## Attribution and references

The collector inventory and pipeline design are authored from public tool and vendor documentation, cited not reproduced: the gnmic (OpenConfig) documentation, the Telegraf `gnmi` and `cisco_telemetry_mdt` input plugin docs, the OpenTelemetry Collector receiver documentation, and Cisco IOS-XR/IOS-XE model-driven telemetry guides. The dial-in gNMI model is consistent with the Apache-2.0 `automateyournetwork/netclaw` `gnmi-telemetry` skill (genericised; its MCP-server framing removed).
