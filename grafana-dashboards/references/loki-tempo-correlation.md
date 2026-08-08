# Loki, Tempo, and Cross-Signal Correlation

Reference for configuring Loki (LogQL) and Tempo (TraceQL) as Grafana data sources, and for wiring the logs, traces, and metrics correlation layer that makes the LGTM stack useful as a unified debugging surface.

---

## Loki Data Source

Loki is a horizontally scalable, multi-tenant log aggregation backend. It indexes only metadata (labels), not log content, keeping storage costs lower than full-text indexing systems. Collection agents (Grafana Alloy, Promtail, Fluentd, Fluent Bit) attach labels to log streams and push to the Loki API.

### Provisioning the Loki data source

```yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
    jsonData:
      maxLines: 1000
      timeout: 60
      derivedFields:
        - name: TraceID
          matcherRegex: '"traceId":"(\w+)"'
          url: '${__value.raw}'
          datasourceUid: tempo-uid
```

Key `jsonData` options:

| Option | Purpose |
|---|---|
| `maxLines` | Cap on log lines returned per query. Prevents oversized responses. |
| `timeout` | Query timeout in seconds. Increase for large log volumes. |
| `derivedFields` | Extracts values from log lines and renders them as clickable links. The primary mechanism for log-to-trace linking. |

`derivedFields` requires a `matcherRegex` to capture the field value and a `datasourceUid` pointing at the Tempo instance. The `url` field accepts `${__value.raw}` for the captured group.

---

## LogQL

LogQL is Loki's query language. Every LogQL query starts with a **log stream selector** (label-based) followed by an optional **pipeline** of filter, parser, and metric expressions.

### Stream selectors

```logql
{app="nginx", env="prod"}        # exact label match
{app=~"nginx|apache"}            # regex match
{app!="mysql"}                   # negative exact match
{app!~"test.*"}                  # negative regex
```

Stream selectors are indexed; they are the fast path. Narrow selectors first, then filter within the stream.

### Filter expressions

```logql
{app="api"} |= "error"           # line contains string
{app="api"} != "health"          # line does not contain
{app="api"} |~ "ERR|WARN"        # regex match
{app="api"} !~ "debug.*"         # regex exclude
```

Add line filters before parsers: filtering raw text before parsing reduces the volume fed to the (more expensive) parser stage.

### Parser expressions

```logql
{app="api"} | json                          # parse JSON; all keys become labels
{app="api"} | logfmt                        # parse key=value format
{app="api"} | pattern "<ip> - <user> [<ts>] \"<method> <path>\" <status>"
{app="api"} | regexp "(?P<level>\\w+) (?P<msg>.*)"
```

### Label filter expressions (post-parse)

Once parsed, labels from the log line can be filtered numerically or by string:

```logql
{app="api"} | json | level="error"
{app="api"} | json | status >= 500
{app="api"} | json | duration > 1s
```

### Line format

```logql
{app="api"} | json | line_format "{{.level}} {{.msg}}"
```

Rewrites the log line for display. Useful for condensing verbose JSON logs.

### Metric queries (log-to-metric)

LogQL metric queries produce time series from log streams. They can be graphed in time-series panels and used in alert rules.

```logql
# Rate of log lines per second over the last 5 minutes
rate({app="api"}[5m])

# Error count per minute, grouped by pod
sum by (pod) (count_over_time({app="api"} |= "error" [1m]))

# p99 of an extracted numeric field
quantile_over_time(0.99,
  {app="api"} | json | unwrap duration [5m]
) by (endpoint)
```

### LogQL performance rules

- Always include at least one indexed label in the stream selector.
- Place line filters (`|=`, `!=`) before parsers to reduce parsed volume.
- Avoid high-cardinality labels (same principle as Prometheus).
- Use `rate()` and `count_over_time()` for log-based alerting rather than querying raw lines at alert evaluation time.

---

## Tempo Data Source

Tempo is a high-volume distributed tracing backend that stores traces in object storage (S3, GCS, Azure Blob). It accepts traces via OTLP, Jaeger, Zipkin, and Kafka.

### Provisioning the Tempo data source

```yaml
apiVersion: 1
datasources:
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    jsonData:
      httpMethod: GET
      tracesToLogsV2:
        datasourceUid: loki-uid
        tags:
          - key: "service.name"
            value: "app"
        filterByTraceID: true
      tracesToMetrics:
        datasourceUid: prometheus-uid
        tags:
          - key: "service.name"
            value: "job"
        queries:
          - name: Request rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))
      serviceMap:
        datasourceUid: prometheus-uid
      nodeGraph:
        enabled: true
      lokiSearch:
        datasourceUid: loki-uid
```

Key `jsonData` sections:

| Section | Purpose |
|---|---|
| `tracesToLogsV2` | Links a trace span to a Loki log query filtered by trace ID and time range. |
| `tracesToMetrics` | Links a trace span to a Prometheus/Mimir metric query using span attributes. |
| `serviceMap` | Populates the service topology map from Prometheus spanmetrics. |
| `lokiSearch` | Enables log search within the Tempo Explore view. |

The `$$__tags` macro in `tracesToMetrics` queries converts span attributes into Prometheus label matchers at query time.

---

## TraceQL

TraceQL is Tempo's query language. It selects traces and spans using a pipeline syntax similar to LogQL.

### Span attribute selectors

```traceql
{ span.http.method = "GET" }              # span attribute
{ resource.service.name = "api" }         # resource attribute
{ duration > 500ms }                      # intrinsic: span duration
{ status = error }                        # intrinsic: status
{ name = "GET /api/v1/users" }            # intrinsic: span name
```

Intrinsic fields (`duration`, `status`, `name`, `traceDuration`) are always available. Span and resource attributes depend on what the instrumentation emits.

### Combining conditions

```traceql
{ span.http.method = "POST" && duration > 1s }
{ resource.service.name =~ "api|gateway" }
{ span.http.status_code >= 500 }
```

### Structural operators

TraceQL can express parent-child and ancestor-descendant relationships across spans in the same trace:

```traceql
{ resource.service.name = "frontend" } >> { status = error }
```

This matches traces where a frontend span has a descendant span in error state. The `>>` operator means "has descendant"; `>` means "has child"; `~` means "has sibling".

### TraceQL metrics (public preview)

TraceQL metrics aggregate over traces to produce time series, similar to LogQL metric queries:

```traceql
{ resource.service.name = "api" } | rate()
{ status = error } | rate() by (resource.service.name)
{ duration > 1s } | histogram_over_time(duration) by (span.http.route)
```

---

## Cross-Signal Correlation

The practical value of the LGTM stack is the ability to pivot between signals. Grafana implements four correlation paths.

### Metrics to traces (exemplars)

Prometheus and Mimir support exemplars: individual metric samples that carry a trace ID. When enabled, a time-series panel shows exemplar points as diamonds overlaid on the line. Clicking an exemplar navigates to the linked trace in Tempo.

Enable exemplar storage in Prometheus:

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
storage:
  exemplars:
    max_exemplars: 100000
```

Enable exemplar display in the Prometheus data source in Grafana (toggle "Exemplars" on the data source config page).

Instrument application code to emit exemplars alongside histogram observations. Libraries in Go, Java, and Python support this via the OpenTelemetry SDK or native Prometheus client libraries.

### Traces to logs

Click a span in the Tempo trace waterfall. Grafana opens a Loki query pre-filtered to the trace ID and the span's time window. Configuration is in `tracesToLogsV2` on the Tempo data source (see provisioning snippet above).

The `filterByTraceID: true` option adds a `traceID="<value>"` filter to the Loki query. The `tags` array maps span resource attributes to Loki label matchers, scoping the log query to the right service.

### Traces to metrics

Click a span. Grafana opens a Prometheus query using span attributes mapped via `$$__tags` to metric label selectors. Configuration is in `tracesToMetrics` on the Tempo data source.

This path is most useful for navigating from a slow span to the raw rate/error/latency time series for the same service, without leaving the trace view.

### Logs to traces (derived fields)

A log line containing a trace ID (e.g., `"traceId":"abc123def456"`) renders the extracted value as a link to the Tempo trace. Configuration is in `derivedFields` on the Loki data source (see provisioning snippet above).

The `matcherRegex` must capture exactly one group: the raw trace ID value. The `datasourceUid` must match the UID of the configured Tempo data source.

### Correlation flow summary

```
Metrics panel (Prometheus)
  (exemplar click) --> Tempo trace waterfall
                            |
              (span click) --> Loki logs for that trace + time window
              (span click) --> Prometheus metrics for that service

Loki Explore (log line)
  (derived-field click) --> Tempo trace waterfall
```

The bidirectional linking enables a complete triage cycle: detect the anomaly in metrics, find the specific trace, read the correlated logs, then confirm in metrics again.

---

## Panel Types for Logs and Traces

| Signal | Panel type | Notes |
|---|---|---|
| Raw log lines | Logs panel | Level colour-coding, deduplication, live tail |
| Log volume over time | Time series (LogQL metric query) | `count_over_time` or `rate` |
| Trace waterfall | Traces panel | Full span waterfall from Tempo/Jaeger/Zipkin |
| Service topology | Node graph | Requires Tempo service map + Prometheus spanmetrics |
| Latency distribution from traces | Heatmap | TraceQL metrics `histogram_over_time` |

The Logs panel expects a Loki data source query returning log streams. The Traces panel expects a Tempo (or Jaeger/Zipkin) query returning trace data. Neither works with a raw Prometheus query.

---

## Practical Configuration Checklist

- Loki data source: `derivedFields` configured with `matcherRegex` matching the trace ID format your services emit.
- Tempo data source: `tracesToLogsV2.datasourceUid` points at the correct Loki UID; `tracesToLogsV2.filterByTraceID` is `true`.
- Tempo data source: `tracesToMetrics.datasourceUid` points at Prometheus/Mimir; at least one rate query using `$$__tags` is defined.
- Prometheus data source: exemplar support toggled on (requires Prometheus 2.25+ or Mimir).
- Services emit trace IDs in log output in a consistent, extractable format.
- Grafana Alloy (or Promtail) configured to forward logs to Loki with labels matching the span attribute keys used in `tracesToLogsV2.tags`.
