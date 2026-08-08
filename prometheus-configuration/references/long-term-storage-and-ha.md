# Long-Term Storage and High Availability

Prometheus's local TSDB is designed for short-to-medium retention (15-30 days). When you need retention spanning months or years, multi-datacenter query, or query deduplication across HA pairs, you layer a dedicated long-term-storage tier on top. This reference covers the two dominant open-source options (Thanos and Grafana Mimir), federation patterns, remote write and remote read, HA Prometheus pairs and deduplication, and retention/downsampling.

## Why Local TSDB Is Not Enough

The local TSDB uses 2-hour blocks, an in-memory head block, and compaction to manage data. Its retention is bounded by a single node's disk. Practical limits:

- Single point of failure for data and queries.
- Retention beyond 30 days requires very large local disks; compaction and query performance degrade as block count grows.
- No global view across multiple Prometheus instances (per-cluster, per-datacenter, per-team).
- HA Prometheus pairs produce duplicate series; there is no built-in deduplication at query time.

## Thanos

Thanos is a set of loosely-coupled components that extend Prometheus with object-storage-backed long-term retention and global query semantics. Components communicate over gRPC using a shared "StoreAPI".

### Sidecar

The sidecar runs alongside each Prometheus instance (same pod or adjacent container). It:

- Watches the Prometheus data directory for completed 2-hour blocks and uploads them to object storage (Amazon S3, Google Cloud Storage, Azure Blob Storage, or any S3-compatible endpoint).
- Exposes a gRPC StoreAPI endpoint that the Thanos Querier can query for both recent data (via the Prometheus HTTP API) and uploaded blocks (via object storage proxying).

```yaml
# thanos-sidecar flags (essential)
--tsdb.path=/var/lib/prometheus          # same path as Prometheus
--prometheus.url=http://localhost:9090
--objstore.config-file=/etc/thanos/objstore.yml
--grpc-address=0.0.0.0:10901
--http-address=0.0.0.0:10902
```

Object store config example (S3):

```yaml
type: S3
config:
  bucket: thanos-metrics
  endpoint: s3.us-east-1.amazonaws.com
  region: us-east-1
```

### Store Gateway

The store gateway serves historical data directly from object storage over gRPC StoreAPI, without keeping a local copy of all blocks. It indexes block metadata in memory and streams chunk data on demand. Deploy it with persistent local storage for the index cache to reduce object storage API calls.

### Compactor

The compactor runs as a single instance against object storage. It:

- Merges small 2-hour blocks into larger blocks (up to the configured max block duration, default 2h of retention becomes 24h, then 2-week blocks after downsampling).
- Applies tombstones.
- Downsamples: creates 5-minute-resolution and 1-hour-resolution downsampled copies from the original raw blocks. Dashboards spanning months can use downsampled data for performance.

The compactor must run as a singleton (it takes exclusive locks on object storage blocks). Run it as a Kubernetes CronJob or a permanently-running Deployment with `--wait`.

### Querier (Query)

The Thanos Querier aggregates queries across multiple StoreAPI endpoints (sidecars, store gateways, other queriers). It:

- Fans out the PromQL query to all configured store endpoints.
- Merges and deduplicates results based on the `--query.replica-label` flag (e.g., `replica`). Series that differ only in that label are treated as duplicates.
- Exposes a Prometheus-compatible HTTP API at port 10902 so Grafana or Prometheus federation can use it as a data source.

```yaml
# thanos-querier flags
--query.replica-label=replica
--store=thanos-sidecar-0:10901
--store=thanos-sidecar-1:10901
--store=thanos-store-gateway:10901
--grpc-address=0.0.0.0:10901
--http-address=0.0.0.0:10902
```

### Thanos Ruler

The Ruler evaluates recording rules and alert rules against the Thanos Store rather than a single Prometheus instance. It is optional; use it when rules must query data across multiple clusters or need access to historical data older than local Prometheus retention.

### Thanos deployment sketch

```
Prometheus-0 (replica=0)   Prometheus-1 (replica=1)
     + Sidecar                   + Sidecar
         |                           |
         |___________________________| (upload blocks to object storage)
                     |
               Object Storage (S3/GCS/Azure)
                     |
              Store Gateway
                     |
         Thanos Querier (dedup on replica label)
                     |
                  Grafana
```

## Grafana Mimir

Mimir is a horizontally scalable, multi-tenant Prometheus-compatible backend. Rather than attaching sidecars, Prometheus instances remote-write metrics to Mimir's ingest path. Mimir handles storage, compaction, querying, and native Ruler/Alertmanager components.

Key differences from Thanos:

| Aspect | Thanos | Mimir |
|--------|--------|-------|
| Ingestion | Block upload from sidecar | Remote write (streaming) |
| Storage backend | Object storage + Prometheus local TSDB | Object storage (blocks, no per-Prometheus TSDB reliance) |
| Scaling | Component-level | Horizontal sharding of all components |
| Multi-tenancy | Limited (per-cluster via external labels) | Built-in (X-Scope-OrgID header) |
| Ruler and Alertmanager | Separate Thanos Ruler and standard Alertmanager | Built-in Ruler and Alertmanager |
| Ecosystem | CNCF graduated | Grafana Labs (Apache-2.0) |

Mimir is the recommended choice when you are already in the Grafana ecosystem (Grafana Cloud, Loki, Tempo) or need multi-tenant isolation.

## Remote Write and Remote Read

### Remote Write

`remote_write` sends samples to a remote backend in real time as Prometheus scrapes them. Protobuf-encoded, snappy-compressed, over HTTPS. A WAL-backed queue with sharding ensures durability and throughput.

```yaml
remote_write:
  - url: https://mimir.example.com/api/v1/push
    basic_auth:
      username: prometheus
      password_file: /etc/prometheus/mimir-password
    queue_config:
      capacity: 500000          # samples buffered in the queue
      max_shards: 50            # parallel sending goroutines
      max_samples_per_send: 10000
      batch_send_deadline: 5s
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'go_.*'
        action: drop            # don't remote-write Go runtime metrics
```

**Tuning guidance:**

- `max_shards` controls parallelism. Increase for high-throughput environments with many active series (>500k). Each shard holds an in-memory buffer.
- `capacity` must be large enough to absorb remote-backend hiccups without dropping samples. Monitor `prometheus_remote_storage_pending_samples`; if it is consistently above zero, increase capacity or shards.
- `write_relabel_configs` reduces egress by dropping metrics not needed in long-term storage (internal Go runtime, build info, debug metrics).

**Monitoring remote write health:**

```promql
# Samples pending in queue (ideally near zero)
prometheus_remote_storage_pending_samples

# Failed sample rate
rate(prometheus_remote_storage_failed_samples_total[5m])

# Queue shard count (use to observe autoscaling behaviour)
prometheus_remote_storage_shards
```

### Remote Read

`remote_read` allows Prometheus to transparently query a remote backend for data older than local retention. Prometheus merges local and remote query results at query time.

```yaml
remote_read:
  - url: https://thanos-query.example.com/api/v1/read
    read_recent: false          # only query remote for data older than local retention
```

`read_recent: false` is recommended; without it, every query hits both local and remote, doubling load. With it, Prometheus only routes queries for out-of-retention data to the remote.

## Federation

Prometheus federation uses the `/federate` endpoint on a leaf Prometheus to scrape selected metrics into a global Prometheus. It is a pull from the HTTP API; queries at the global level are limited to what was federated.

```yaml
# Global Prometheus scraping leaf instances
scrape_configs:
  - job_name: federate
    honor_labels: true
    metrics_path: /federate
    params:
      match[]:
        - '{job="api-server"}'
        - 'http_requests_total'
        - 'node_cpu_seconds_total'
    static_configs:
      - targets:
          - prometheus-dc1.example.com:9090
          - prometheus-dc2.example.com:9090
```

**`honor_labels: true`** preserves the `job` and `instance` labels from the source Prometheus rather than overwriting them with the federation scrape job and target.

**Hierarchical federation:** Useful when leaf Prometheus instances collect per-service or per-cluster metrics and a global Prometheus aggregates cross-cluster KPIs. The global Prometheus only stores the aggregated/filtered metrics, not the full cardinality of each leaf.

**Cross-service federation:** A shared Prometheus can federate a small set of metrics from team-owned Prometheus instances (e.g., only SLI metrics). This avoids giving the shared Prometheus access to all metrics of every team.

**Limitations of federation:** Federation is a scrape; there is an inherent lag equal to the scrape interval. Queries at the global level are bounded by what was federated. Federation does not deduplicate HA pairs. For production multi-cluster use, prefer `remote_write` to Thanos/Mimir.

## High Availability Prometheus Pairs

The baseline HA pattern is two identical Prometheus instances scraping the same targets with the same configuration. Both evaluate the same recording and alert rules. Both send alerts to an Alertmanager cluster.

```
Prometheus-0 (external_labels: {cluster: prod, replica: "0"})
Prometheus-1 (external_labels: {cluster: prod, replica: "1"})
        |                           |
        +---------------------------+
                      |
              Alertmanager Cluster
            (3-node gossip, dedup on all labels except replica)
```

**External labels** are added to all time series sent to remote storage and to all alerts. The `replica` label differentiates the two instances. Alertmanager deduplicates alerts that are identical in all labels except `replica`.

**Alertmanager cluster (3 nodes):** Uses the Gossip protocol (memberlist) for deduplication across nodes. A 3-node cluster tolerates one-node failure while maintaining quorum. Single-node Alertmanager is a SPOF.

```yaml
# Prometheus configuration for HA pair
global:
  external_labels:
    cluster: prod-us-east-1
    replica: prometheus-0      # change to prometheus-1 on the second instance
```

**Query deduplication:** When using Thanos Querier, set `--query.replica-label=replica`. The querier returns one result per unique series, preferring whichever replica has the most recent sample.

When using Mimir, configure `ha_replica_label` in the Mimir distributor; Mimir deduplicates inbound remote-write samples before storing.

## Retention and Downsampling

### Local retention

Prometheus enforces retention by time and/or size:

```bash
--storage.tsdb.retention.time=30d
--storage.tsdb.retention.size=500GB
```

Both flags can be set simultaneously; whichever limit is reached first causes Prometheus to delete the oldest blocks.

**Storage sizing formula:**

```
disk_bytes = (active_series / scrape_interval_seconds) * 1.3_bytes * retention_seconds
```

For 500,000 series, 15s scrape interval, 30 days: approximately 112 GB. Add 20% for WAL and compaction scratch. Use SSD for the WAL directory.

### Thanos downsampling

The Thanos Compactor creates two downsampled resolutions from raw blocks:

| Resolution | Retention default | Use case |
|------------|-------------------|----------|
| Raw (per-sample) | Configurable, e.g. 90 days | Short-range dashboards, recent alerting |
| 5-minute downsampled | Configurable, e.g. 1 year | Month-range trend views |
| 1-hour downsampled | Indefinite | Year-range capacity planning |

Thanos Querier automatically selects the coarsest available resolution that satisfies the query range, reducing data transfer and query time for long-range queries.

Enable downsampling in the Compactor:

```yaml
# thanos-compactor flags
--retention.resolution-raw=90d
--retention.resolution-5m=1y
--retention.resolution-1h=0s          # 0s = indefinite
```

### Mimir compaction and retention

Mimir's Compactor runs as a separate service and manages the same block-merging and downsampling lifecycle as Thanos Compactor, but within Mimir's horizontally-sharded architecture. Per-tenant retention is configured in Mimir's runtime configuration:

```yaml
overrides:
  tenant-id:
    compactor_blocks_retention_period: 1y
```

## Programmatic Queries via the Prometheus MCP Server

The [pab1it0/prometheus-mcp-server](https://github.com/pab1it0/prometheus-mcp-server) is an MCP-compatible server that exposes Prometheus's HTTP API as structured tools. It is useful when an AI agent or automation script needs to query Prometheus without constructing raw HTTP calls.

**Available tools:**

| Tool | Purpose |
|------|---------|
| `execute_query` | Instant PromQL query at current time |
| `execute_range_query` | Range query over a time interval |
| `list_metrics` | Browse available metric names (paginated) |
| `get_metric_metadata` | Retrieve metric type, help text, unit |
| `get_targets` | View scrape target health and labels |
| `health_check` | Verify Prometheus server availability |

**Configuration via environment variables:**

```bash
PROMETHEUS_URL=http://prometheus:9090
PROMETHEUS_TOKEN=your_bearer_token   # for Grafana Cloud, Thanos, or Mimir
ORG_ID=1                             # for Mimir multi-tenant queries
```

All six tools are read-only. Use `execute_range_query` with UTC ISO-8601 timestamps for time bounds:

```
start="2024-06-01T00:00:00Z"
end="2024-06-01T06:00:00Z"
step="60s"
```

**Typical investigation workflow:**

1. `health_check` to confirm the Prometheus endpoint is reachable.
2. `list_metrics` to discover available metric names when the exact name is unknown.
3. `get_metric_metadata` to understand whether a metric is a counter, gauge, or histogram before writing a query.
4. `execute_query` for the current value of a specific series.
5. `execute_range_query` for trend analysis; keep the range and step proportionate to avoid very large result payloads.
6. `get_targets` to verify whether a scrape job is healthy when metrics are absent.

For long-range capacity queries targeting Thanos or Mimir, the bearer token or basic auth credentials must correspond to a user with query permissions on the relevant tenant.
