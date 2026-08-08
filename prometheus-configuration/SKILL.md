---
name: prometheus-configuration
description: "When the user mentions Prometheus setup, metric scraping, recording rules, alert rules, AlertManager, service discovery, \"scrape config,\" \"promtool,\" \"rate(http_requests_total[5m]),\" \"p95 latency from a histogram,\" or wants to configure metric collection / monitoring infrastructure / alerting pipelines. Also use when the user mentions Thanos / Cortex / Mimir for long-term storage, federation, multi-cluster Prometheus, or \"why isn't this target showing up in /targets.\" For distributed tracing setup, see distributed-tracing. For dashboard visualisation, see grafana-dashboards. For SLO definition and burn-rate alerts, see slo-implementation. For runbook integration with alert annotations, see oncall-runbooks. Advanced references (load on demand): promql-deep-dive (vector matching, aggregation operators, histogram_quantile, classic vs native histograms in 3.x, subqueries, query recipes), long-term-storage-and-ha (Thanos / Mimir, federation, remote_write / remote_read, HA pairs and dedup, retention and downsampling). Additional triggers: 'promql', 'histogram_quantile', 'native histograms', 'vector matching', 'group_left', 'thanos', 'mimir', 'federation', 'remote_write', 'ha prometheus', 'prometheus mcp'. Customised from chrishuffman5/domain-expert/skills/monitoring/prometheus (MIT) and netclaw prometheus-monitoring (Apache-2.0)."
license: MIT
metadata:
  version: "1.1.0"
---

# Prometheus Configuration

Complete guide to Prometheus setup, metric collection, scrape configuration, recording rules, and alert rules. AlertManager handles alert routing; Thanos, Cortex, and Mimir are common long-term-storage options; Grafana is the usual visualisation layer.

> **Skill marker**: When applying this skill, begin your reply with `[skill: prometheus-configuration]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project's metrics backend, scrape targets, recording-rule conventions, alert-routing pipeline, label cardinality budgets, and any retention / federation assumptions before proposing changes. Match the existing scrape-job naming and recording-rule namespace conventions rather than inventing new ones.

## Purpose

Configure Prometheus for comprehensive metric collection, alerting, and monitoring of infrastructure and applications.

## When to Use

- Set up Prometheus monitoring
- Configure metric scraping
- Create recording rules
- Design alert rules
- Implement service discovery

## Prometheus Architecture

```
┌──────────────┐
│ Applications │ ← Instrumented with client libraries
└──────┬───────┘
       │ /metrics endpoint
       ↓
┌──────────────┐
│  Prometheus  │ ← Scrapes metrics periodically
│    Server    │
└──────┬───────┘
       │
       ├─→ AlertManager (alert routing and notification)
       ├─→ Grafana (visualisation)
       └─→ Long-term storage (Thanos, Cortex, Mimir, etc.)
```

## Installation

### Kubernetes with Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageVolumeSize=50Gi
```

### Docker Compose

```yaml
version: "3.8"
services:
  prometheus:
    image: prom/prometheus:v3.2
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=30d"

volumes:
  prometheus-data:
```

## Configuration File

**prometheus.yml:**

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "production"
    region: "us-west-2"

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

# Load rules files
rule_files:
  - /etc/prometheus/rules/*.yml

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Node exporters
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "node1:9100"
          - "node2:9100"
          - "node3:9100"
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: "([^:]+)(:[0-9]+)?"
        replacement: "${1}"

  # Kubernetes pods with annotations
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels:
          [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod

  # Application metrics
  - job_name: "my-app"
    static_configs:
      - targets:
          - "app1.example.com:9090"
          - "app2.example.com:9090"
    metrics_path: "/metrics"
    scheme: "https"
    tls_config:
      ca_file: /etc/prometheus/ca.crt
      cert_file: /etc/prometheus/client.crt
      key_file: /etc/prometheus/client.key
```

## Scrape Configurations

### Static Targets

```yaml
scrape_configs:
  - job_name: "static-targets"
    static_configs:
      - targets: ["host1:9100", "host2:9100"]
        labels:
          env: "production"
          region: "us-west-2"
```

### File-based Service Discovery

```yaml
scrape_configs:
  - job_name: "file-sd"
    file_sd_configs:
      - files:
          - /etc/prometheus/targets/*.json
          - /etc/prometheus/targets/*.yml
        refresh_interval: 5m
```

**targets/production.json:**

```json
[
  {
    "targets": ["app1:9090", "app2:9090"],
    "labels": {
      "env": "production",
      "service": "api"
    }
  }
]
```

### Kubernetes Service Discovery

```yaml
scrape_configs:
  - job_name: "kubernetes-services"
    kubernetes_sd_configs:
      - role: service
    relabel_configs:
      - source_labels:
          [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels:
          [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
```

## Recording Rules

Create pre-computed metrics for frequently queried expressions. Useful when the same expensive PromQL appears in many dashboards or alerts.

```yaml
# /etc/prometheus/rules/recording_rules.yml
groups:
  - name: api_metrics
    interval: 15s
    rules:
      # HTTP request rate per service
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      # Error rate percentage
      - record: job:http_requests_errors:rate5m
        expr: sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))

      - record: job:http_requests_error_rate:percentage
        expr: |
          (job:http_requests_errors:rate5m / job:http_requests:rate5m) * 100

      # P95 latency
      - record: job:http_request_duration:p95
        expr: |
          histogram_quantile(0.95,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          )

  - name: resource_metrics
    interval: 30s
    rules:
      # CPU utilisation percentage
      - record: instance:node_cpu:utilization
        expr: |
          100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      # Memory utilisation percentage
      - record: instance:node_memory:utilization
        expr: |
          100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)

      # Disk usage percentage
      - record: instance:node_disk:utilization
        expr: |
          100 - ((node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100)
```

Note: recording-rule metric names like `instance:node_cpu:utilization` retain US spelling to match upstream node_exporter and community-rule conventions. Keep the names consistent with the rest of the ecosystem; UK / Pacific spelling applies to prose, not metric identifiers.

## Alert Rules

```yaml
# /etc/prometheus/rules/alert_rules.yml
groups:
  - name: availability
    interval: 30s
    rules:
      - alert: ServiceDown
        expr: up{job="my-app"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"
          description: "{{ $labels.job }} has been down for more than 1 minute"

      - alert: HighErrorRate
        expr: job:http_requests_error_rate:percentage > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate for {{ $labels.job }}"
          description: "Error rate is {{ $value }}% (threshold: 5%)"

      - alert: HighLatency
        expr: job:http_request_duration:p95 > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency for {{ $labels.job }}"
          description: "P95 latency is {{ $value }}s (threshold: 1s)"

  - name: resources
    interval: 1m
    rules:
      - alert: HighCPUUsage
        expr: instance:node_cpu:utilization > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}%"

      - alert: HighMemoryUsage
        expr: instance:node_memory:utilization > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value }}%"

      - alert: DiskSpaceLow
        expr: instance:node_disk:utilization > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk usage is {{ $value }}%"
```

When wiring alerts to runbooks, add a `runbook_url` annotation that points at the runbook entry; the on-call should not have to invent the response under pressure.

## Validation

```bash
# Validate configuration
promtool check config prometheus.yml

# Validate rules
promtool check rules /etc/prometheus/rules/*.yml

# Test query
promtool query instant http://localhost:9090 'up'
```

## Best Practices

1. **Use consistent naming** for metrics (prefix_name_unit, e.g. `http_requests_total`, `http_request_duration_seconds`)
2. **Set appropriate scrape intervals** (15-60s typical; longer for slow-changing infrastructure metrics)
3. **Use recording rules** for expensive queries that appear in many places
4. **Implement high availability** (multiple Prometheus instances scraping the same targets)
5. **Configure retention** based on storage capacity (use Thanos / Cortex / Mimir for long retention)
6. **Use relabeling** for metric cleanup and label normalisation
7. **Monitor Prometheus itself** (scrape `/metrics` on the Prometheus server)
8. **Implement federation** for large deployments (hierarchical Prometheus, or push to a long-term-storage tier)
9. **Use long-term storage** (Thanos, Cortex, Mimir) when retention exceeds local disk capacity
10. **Watch label cardinality**: each unique label-value combination is a new time series. Avoid high-cardinality labels (user IDs, request IDs); they explode storage and slow queries
11. **Document custom metrics**: name, unit, label set, expected cardinality

## Troubleshooting

**Check scrape targets:**

```bash
curl http://localhost:9090/api/v1/targets
```

Look at `lastError` per target to see why a scrape is failing. Common causes: TLS misconfiguration, /metrics endpoint missing, DNS / network policy blocking the scrape, target returning non-200.

**Check configuration:**

```bash
curl http://localhost:9090/api/v1/status/config
```

**Test query:**

```bash
curl 'http://localhost:9090/api/v1/query?query=up'
```

**Unexpectedly high cardinality:**

```bash
# Top series by label-set count
curl 'http://localhost:9090/api/v1/status/tsdb' | jq '.data.headStats'
```

If a metric is exploding, find the culprit:

```promql
topk(20, count by (__name__)({__name__=~".+"}))
```

## Advanced topics (references)

The body covers setup, scraping, recording and alert rules, and validation. For deeper work, load the matching reference:

| Reference | Read when |
|---|---|
| `references/promql-deep-dive.md` | Writing non-trivial PromQL: vector matching, aggregation, `histogram_quantile`, classic vs native histograms (3.x), subqueries, query recipes. |
| `references/long-term-storage-and-ha.md` | Scaling beyond a single local TSDB: Thanos / Mimir, federation, remote-write, HA pairs and dedup, retention and downsampling. |

## Cross-references

- `distributed-tracing`: paired tracing skill; metrics + traces + logs is the classic observability triangle. Correlate trace IDs with metric labels for trace-to-metric pivots.
- `grafana-dashboards`: visualising Prometheus metrics; recording rules feed dashboards efficiently.
- `slo-implementation`: SLOs derived from recording rules (success-rate, latency); burn-rate alerts piggyback on Prometheus alert rules.
- `oncall-runbooks`: every alert should have a `runbook_url` annotation pointing at the runbook entry for that alert.
- `systematic-debugging`: metrics are a Phase 1 fast pass/fail signal; if a metric is non-deterministic, raise the scrape interval or the reproduction rate before chasing the signal.
