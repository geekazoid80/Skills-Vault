# OTel Collector Pipelines

The OpenTelemetry Collector is a vendor-neutral binary that receives telemetry, processes it, and exports it to one or more backends. It decouples instrumentation libraries from backend concerns: change exporter config, not application code.

## Agent vs Gateway Deployment

Two deployment topologies are common, and they compose well.

**Agent (DaemonSet or sidecar):** one Collector per node or per pod. Lightweight config: receive OTLP from local workloads, enrich with Kubernetes metadata, forward upstream. Bounded by node resources; keep heavy processing off agents.

**Gateway (Deployment, 2-5 replicas minimum):** centralised fleet for expensive processing: tail sampling, fan-out to multiple backends, attribute redaction, transforms. Scales horizontally; front with a load balancer. For tail sampling across multiple replicas, route by trace ID using the `loadbalancing` exporter so all spans of a trace reach the same instance.

**Choosing one vs both:** single-service or low-traffic setups can run a single gateway Deployment. Production Kubernetes at scale uses agent DaemonSet forwarding to a gateway Deployment. Sidecar is appropriate when strict per-pod isolation is needed.

## Pipeline Model

Data flows strictly left-to-right within a pipeline:

```
Receivers  -->  Processors  -->  Exporters
```

Connectors bridge two pipelines by acting as an exporter on one and a receiver on another (e.g., `spanmetrics` generates RED metrics from trace spans).

### Config skeleton

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  telemetry:
    logs:
      level: warn
    metrics:
      address: 0.0.0.0:8888   # scrape Collector's own metrics here
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
```

Key conventions:
- Each signal type gets its own named pipeline. Multiple pipelines of the same type are valid: `traces/ingest` and `traces/sampling` coexist.
- Use `/suffix` to disambiguate components of the same type: `otlp/tempo`, `otlp/datadog`.

## Key Processors

### memory_limiter (MUST be first in every pipeline)

Prevents OOM under load. Without it, a traffic spike crashes the Collector and silently drops telemetry.

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512        # ~80% of container memory limit
    spike_limit_mib: 128  # 20-25% of limit_mib
```

When the soft limit is hit, the Collector refuses new data and forces a GC pass. When the hard limit is hit, it drops data. Neither crashes the process.

### batch

Buffer items and send in larger batches to reduce network overhead and backend write amplification. Place just before exporters.

```yaml
processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048
```

### resource and attributes

`resource` mutates Resource-level attributes (service metadata), `attributes` mutates per-span/metric/log attributes.

```yaml
processors:
  resource:
    attributes:
      - key: deployment.environment
        value: production
        action: insert
  attributes:
    actions:
      - key: http.user_agent
        action: delete
      - key: db.statement
        action: hash          # hash PII before exporting
```

### filter (OTTL expressions)

Drop unwanted spans, metrics, or log records before batching, saving queue space.

```yaml
processors:
  filter:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/healthz"'
        - 'attributes["http.route"] == "/readyz"'
    logs:
      log_record:
        - 'severity_number < SEVERITY_NUMBER_WARN'
```

### tail_sampling

Unlike head sampling (decided at the trace root), tail sampling buffers all spans for a trace until it completes, then applies policy. Retains errors and slow traces at full fidelity while discarding routine traffic.

```yaml
processors:
  tail_sampling:
    decision_wait: 10s       # wait this long for all spans to arrive
    num_traces: 50000        # max traces held in memory
    expected_new_traces_per_sec: 100
    policies:
      - name: errors-policy
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow-traces
        type: latency
        latency: {threshold_ms: 1000}
      - name: baseline-sample
        type: probabilistic
        probabilistic: {sampling_percentage: 5}
      - name: rate-cap
        type: rate_limiting
        rate_limiting: {spans_per_second: 2000}
```

Policies are evaluated in order; a trace is kept if ANY policy matches. Add a `rate_limiting` policy last as a hard cap.

Critical constraint: tail sampling requires all spans of a single trace to reach the same Collector instance. With multiple gateway replicas, route by trace ID using the `loadbalancing` exporter on the upstream tier.

### k8sattributes (Kubernetes metadata enrichment)

```yaml
processors:
  k8sattributes:
    auth_type: serviceAccount
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.deployment.name
        - k8s.pod.name
        - k8s.node.name
    pod_association:
      - sources:
          - from: resource_attribute
            name: k8s.pod.ip
```

Requires a ClusterRole with `get` and `list` on pods and nodes.

## OTLP Receivers and Exporters

### OTLP receiver (primary for SDK-instrumented services)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317   # default; high throughput
        max_recv_msg_size_mib: 4
      http:
        endpoint: 0.0.0.0:4318   # for browser SDKs, firewalled environments
        cors:
          allowed_origins: ["*"]
```

### OTLP exporter (forwarding to another Collector tier or OTLP-native backend)

```yaml
exporters:
  otlp/gateway:
    endpoint: otelcol-gateway:4317
    tls:
      insecure: false
      ca_file: /certs/ca.crt
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000
```

Always enable `retry_on_failure` and `sending_queue` on production exporters. Without them, backend outages cause silent span loss.

### loadbalancing exporter (required for multi-replica tail sampling)

```yaml
exporters:
  loadbalancing:
    protocol:
      otlp:
        tls:
          insecure: true
    resolver:
      dns:
        hostname: otelcol-sampler   # headless Kubernetes service
        port: 4317
        interval: 5s
```

Resolves all A records for `hostname` and routes spans for the same trace ID to the same downstream instance, providing trace-ID affinity for tail sampling.

## Spanmetrics Connector (RED Metrics from Traces)

Derives `calls_total`, latency histograms, and error rates from span data, feeding a metrics pipeline.

```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [2ms, 4ms, 6ms, 8ms, 10ms, 50ms, 100ms, 200ms, 400ms, 800ms, 1s, 2s, 5s]
    dimensions:
      - name: http.method
      - name: http.status_code
      - name: http.route
    exemplars:
      enabled: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [spanmetrics, otlp/tempo]
    metrics:
      receivers: [spanmetrics]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
```

## Scaling and Queue/Retry

**Horizontal scaling:** the Collector is stateless for traces and metrics pipelines; run as many replicas as needed. Exception: tail sampling requires trace-ID-affinity routing via the `loadbalancing` exporter.

**Queue sizing:** `sending_queue.queue_size` is in items. Tune for burst tolerance. A queue of 1000 with 10 consumers and a backend latency of 100 ms per batch handles roughly 10 seconds of burst at steady throughput.

**Retry window:** set `retry_on_failure.max_elapsed_time` to the expected backend recovery time (300 s covers most Kubernetes restarts).

**Self-observability:** scrape `http://otelcol:8888/metrics` for queue fill levels (`otelcol_exporter_queue_size`), dropped items (`otelcol_exporter_send_failed_spans`), and receiver refusals under memory pressure (`otelcol_receiver_refused_spans`). Alert on non-zero failed or refused counts.

**Collector distributions:** `otelcol` (upstream core) vs `otelcol-contrib` (all community components). Most production deployments use `otelcol-contrib`. The OpenTelemetry Operator manages Collector deployments as `OpenTelemetryCollector` CRs in Kubernetes.
