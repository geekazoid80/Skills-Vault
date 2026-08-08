# Elastic Stack as the log backend

Graylog and the Elastic Stack (ELK) share the same search substrate: Elasticsearch (or OpenSearch). This reference covers that overlap, the Graylog-on-Elasticsearch versus ELK-direct decision, and the ELK log-management features worth knowing when the backend is exposed.

Scope: the log-search backend only. ELK's APM, metrics (TSDB/Logsdb), and distributed-tracing features are out of scope here; for those use the observability skills (`distributed-tracing`, `grafana-dashboards`, `prometheus-configuration`). This reference exists because Graylog operators frequently meet the Elastic layer underneath.

## Shared substrate, different front ends

Graylog runs on top of Elasticsearch/OpenSearch: it manages index sets, streams, pipelines, and the query UI, while Elasticsearch does the storage and search. ELK exposes Elasticsearch directly through Kibana. The same cluster concerns apply to both: shard sizing, index lifecycle, mapping discipline, disk watermarks.

| Choose | When |
|---|---|
| Graylog (on Elasticsearch/OpenSearch) | You want opinionated log pipelines, streams, content packs, and a focused log-search UI without managing Kibana; ingest-time routing and extraction matter |
| ELK direct (Kibana over Elasticsearch) | You already run Elastic for observability, want ES\|QL/Lens, Fleet-managed agents, and the broader Elastic ecosystem; you are comfortable operating the cluster |

Both are valid; the deciding factor is usually whether you want Graylog's log-specific abstractions or Elastic's general-purpose, observability-wide platform.

## ELK log collection

Elastic Agent (Fleet-managed) is the unified collector that replaces the legacy Beats; recommend Beats (Filebeat) only for air-gapped or resource-constrained hosts.

```yaml
# filebeat.yml (filestream is preferred over the legacy "log" input)
filebeat.inputs:
  - type: filestream
    id: nginx-access
    paths: ["/var/log/nginx/access.log"]
filebeat.modules:
  - module: system
    syslog: { enabled: true }
    auth:   { enabled: true }
output.elasticsearch:
  hosts: ["https://es:9200"]
  api_key: "${ES_API_KEY}"
  data_stream.enable: true
setup.ilm.enabled: true
```

On Kubernetes, install Elastic Agent as a DaemonSet via the Fleet Kubernetes integration; it enriches logs with `kubernetes.pod.name`, `.namespace`, `.container.name`.

## Data streams, templates, and ILM

Use data streams for all log data, named `<type>-<dataset>-<namespace>` (e.g. `logs-nginx.access-production`). They give automatic rollover and ILM.

```json
PUT _index_template/logs-myapp
{
  "index_patterns": ["logs-myapp-*"],
  "data_stream": {},
  "priority": 200,
  "template": {
    "settings": {
      "index.lifecycle.name": "observability-logs",
      "default_pipeline": "logs-myapp-parse"
    }
  }
}
```

ILM tiers the data and caps cost: hot (1 day, rollover) -> warm (2-30 days, forcemerge/shrink) -> cold (30-90 days, searchable snapshots from object storage) -> frozen (90-365 days, on-demand mounts) -> delete. This is the Elastic implementation of the same rotation/retention model Graylog expresses through index sets.

Data-stream operations:

```bash
GET  _data_stream/logs-*                          # list
POST logs-nginx.access-prod/_rollover             # manual rollover
GET  logs-nginx.access-prod-000001/_ilm/explain   # ILM state
POST logs-nginx.access-prod-000001/_ilm/retry     # retry a failed ILM step
```

## Querying logs

- **KQL** (Kibana's default search bar): `service.name: "nginx"`, `url.path: /api/*`, `log.level: ("ERROR" OR "FATAL")`, `http.response.status_code >= 400 and < 500`, `NOT status: 200`, `field: *` for existence.
- **Lucene** (Lens, advanced filters): `service.name:nginx AND status:[400 TO 599]`, `message:"connection refused"`, `@timestamp:[now-1h TO now]`, fuzzy `message:connectoin~1`.
- **ES\|QL** (GA since 8.11): pipe-based analytics.

```esql
FROM logs-nginx.access-prod
| WHERE @timestamp >= NOW() - 1 hour
| WHERE http.response.status_code >= 500
| STATS count = COUNT(*) BY service.name
| SORT count DESC | LIMIT 10
```

This maps onto Graylog's Lucene-plus-extensions query language: field-scoped matches, boolean composition, ranges, and existence checks behave similarly because the substrate is the same.

## Cluster discipline (applies to Graylog and ELK alike)

- **Normalise to ECS.** Elastic's Common Schema (`source.ip`, `process.name`) is required for Kibana's log features and makes cross-source search consistent.
- **Target 10-50 GB primary shard size for logs.** Over-sharding wastes heap; use `max_primary_shard_size: 50gb` plus `max_age: 1d` for rollover.
- **Avoid mapping explosion.** Unbounded dynamic fields cause heap pressure; use `dynamic: false` or `dynamic: runtime`.
- **Watch disk watermarks.** Defaults: 85% low (stop allocating), 90% high (relocate), 95% flood (read-only). Scale before you hit them.
- **Prefer dissect over grok** for structured formats; grok's regex is CPU-intensive.
- **Replicas:** 1 on hot/warm for resilience, 0 on cold/frozen to save storage.

## Cross-references

- `graylog-log-investigation`: the parent skill; Graylog query language, streams, pipelines, index sets, and the investigation workflow.
- `siem-soar-investigation`: when Elasticsearch underpins a SIEM (Elastic Security), the detection-engineering and normalisation layer above the backend.
- `distributed-tracing`, `grafana-dashboards`, `prometheus-configuration`: ELK's APM, tracing, and metrics features, deliberately out of scope here.
- `secrets-hygiene`: the Elasticsearch API key / Fleet enrolment token belong in the secret store, never in a shipper config committed to git.
