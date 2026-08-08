---
name: distributed-tracing
description: "When the user mentions distributed tracing, OpenTelemetry, OTel, request flow visibility across services, span propagation, trace context, baggage, sampling strategies, service dependency graphs, or setting up Jaeger / Tempo / Honeycomb / Datadog / Zipkin / another tracing backend. Also use when the user mentions \"trace this request,\" \"why is latency high across services,\" \"instrument this service with OTel,\" \"correlate logs and traces,\" or \"tail-sampling.\" For metrics collection and alerting rules, see prometheus-configuration. For dashboard visualisation, see grafana-dashboards. For latency SLOs derived from trace data, see slo-implementation. For traces as a narrowing tool during bug investigation, see systematic-debugging. Advanced references (load on demand): otel-collector-pipelines (agent vs gateway, receivers / processors / exporters / connectors, tail-sampling processor, spanmetrics, scaling), instrumentation-auto-vs-manual (per-language auto agents, coverage gaps, semantic conventions, hybrid migration). Additional triggers: 'otel collector', 'collector pipeline', 'receivers processors exporters', 'tail sampling processor', 'spanmetrics', 'auto-instrumentation', 'manual instrumentation', 'semantic conventions', 'javaagent', 'opentelemetry-instrument'. Customised from chrishuffman5/domain-expert/skills/monitoring/opentelemetry (MIT)."
license: MIT
metadata:
  version: "1.1.0"
---

# Distributed Tracing

Implement distributed tracing across services to make request flows, dependencies, and latency hotspots visible. OpenTelemetry is the dominant instrumentation library; Jaeger and Tempo are common open-source backends, with Honeycomb, Datadog, Zipkin, and others as alternatives.

> **Skill marker**: When applying this skill, begin your reply with `[skill: distributed-tracing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project's tracing backend (Jaeger, Tempo, Honeycomb, Datadog, etc.), sampling defaults, service-naming conventions, context-propagation expectations, and any baggage / attribute standards. Only propose changes that fit the existing pipeline; do not invent a new backend silently.

## Purpose

Track requests across distributed systems to understand latency, dependencies, and failure points.

## When to Use

- Debug latency issues
- Understand service dependencies
- Identify bottlenecks
- Trace error propagation
- Analyse request paths

## Distributed Tracing Concepts

### Trace Structure

```
Trace (Request ID: abc123)
  ↓
Span (frontend) [100ms]
  ↓
Span (api-gateway) [80ms]
  ├→ Span (auth-service) [10ms]
  └→ Span (user-service) [60ms]
      └→ Span (database) [40ms]
```

### Key Components

- **Trace**: end-to-end request journey
- **Span**: single operation within a trace
- **Context**: metadata propagated between services
- **Tags / attributes**: key-value pairs for filtering
- **Logs / events**: timestamped events within a span
- **Baggage**: key-value pairs that propagate alongside the trace context across service boundaries

## Tracing Backend Setup

The examples below use Jaeger; the same shape applies to Tempo, Honeycomb, Datadog, and other backends with minor exporter / endpoint changes.

### Kubernetes Deployment (Jaeger example)

```bash
# Deploy Jaeger Operator
kubectl create namespace observability
kubectl create -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.51.0/jaeger-operator.yaml -n observability

# Deploy Jaeger instance
kubectl apply -f - <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger
  namespace: observability
spec:
  strategy: production
  storage:
    type: elasticsearch
    options:
      es:
        server-urls: http://elasticsearch:9200
  ingress:
    enabled: true
EOF
```

### Docker Compose (Jaeger example)

```yaml
version: "3.8"
services:
  jaeger:
    image: jaegertracing/all-in-one:1.62
    ports:
      - "5775:5775/udp"
      - "6831:6831/udp"
      - "6832:6832/udp"
      - "5778:5778"
      - "16686:16686" # UI
      - "14268:14268" # Collector
      - "14250:14250" # gRPC
      - "9411:9411" # Zipkin
    environment:
      - COLLECTOR_ZIPKIN_HOST_PORT=:9411
```

## Application Instrumentation

### OpenTelemetry (Recommended)

OpenTelemetry is vendor-neutral; the same SDK exports to Jaeger, Tempo, Honeycomb, Datadog, and most other backends with only an exporter swap. Prefer auto-instrumentation libraries where they exist for your framework; fall back to manual span creation for business-logic boundaries.

#### Python (Flask)

```python
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from flask import Flask

# Initialise tracer
resource = Resource(attributes={SERVICE_NAME: "my-service"})
provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(JaegerExporter(
    agent_host_name="jaeger",
    agent_port=6831,
))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

# Instrument Flask
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

@app.route('/api/users')
def get_users():
    tracer = trace.get_tracer(__name__)

    with tracer.start_as_current_span("get_users") as span:
        span.set_attribute("user.count", 100)
        # Business logic
        users = fetch_users_from_db()
        return {"users": users}

def fetch_users_from_db():
    tracer = trace.get_tracer(__name__)

    with tracer.start_as_current_span("database_query") as span:
        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.statement", "SELECT * FROM users")
        # Database query
        return query_database()
```

#### Node.js (Express)

```javascript
const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node");
const { JaegerExporter } = require("@opentelemetry/exporter-jaeger");
const { BatchSpanProcessor } = require("@opentelemetry/sdk-trace-base");
const { registerInstrumentations } = require("@opentelemetry/instrumentation");
const { HttpInstrumentation } = require("@opentelemetry/instrumentation-http");
const {
  ExpressInstrumentation,
} = require("@opentelemetry/instrumentation-express");

// Initialise tracer
const provider = new NodeTracerProvider({
  resource: { attributes: { "service.name": "my-service" } },
});

const exporter = new JaegerExporter({
  endpoint: "http://jaeger:14268/api/traces",
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();

// Instrument libraries
registerInstrumentations({
  instrumentations: [new HttpInstrumentation(), new ExpressInstrumentation()],
});

const express = require("express");
const app = express();

app.get("/api/users", async (req, res) => {
  const tracer = trace.getTracer("my-service");
  const span = tracer.startSpan("get_users");

  try {
    const users = await fetchUsers();
    span.setAttributes({ "user.count": users.length });
    res.json({ users });
  } finally {
    span.end();
  }
});
```

#### Go

```go
package main

import (
    "context"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/jaeger"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
)

func initTracer() (*sdktrace.TracerProvider, error) {
    exporter, err := jaeger.New(jaeger.WithCollectorEndpoint(
        jaeger.WithEndpoint("http://jaeger:14268/api/traces"),
    ))
    if err != nil {
        return nil, err
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceNameKey.String("my-service"),
        )),
    )

    otel.SetTracerProvider(tp)
    return tp, nil
}

func getUsers(ctx context.Context) ([]User, error) {
    tracer := otel.Tracer("my-service")
    ctx, span := tracer.Start(ctx, "get_users")
    defer span.End()

    span.SetAttributes(attribute.String("user.filter", "active"))

    users, err := fetchUsersFromDB(ctx)
    if err != nil {
        span.RecordError(err)
        return nil, err
    }

    span.SetAttributes(attribute.Int("user.count", len(users)))
    return users, nil
}
```

## Context Propagation

### HTTP Headers (W3C Trace Context)

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
tracestate: congo=t61rcWkgMzE
```

### Propagation in HTTP Requests

#### Python

```python
from opentelemetry.propagate import inject

headers = {}
inject(headers)  # Injects trace context

response = requests.get('http://downstream-service/api', headers=headers)
```

#### Node.js

```javascript
const { propagation } = require("@opentelemetry/api");

const headers = {};
propagation.inject(context.active(), headers);

axios.get("http://downstream-service/api", { headers });
```

## Tempo Setup (alternative backend)

### Kubernetes Deployment

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200

    distributor:
      receivers:
        jaeger:
          protocols:
            thrift_http:
            grpc:
        otlp:
          protocols:
            http:
            grpc:

    storage:
      trace:
        backend: s3
        s3:
          bucket: tempo-traces
          endpoint: s3.amazonaws.com

    querier:
      frontend_worker:
        frontend_address: tempo-query-frontend:9095
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: tempo
          image: grafana/tempo:2.7
          args:
            - -config.file=/etc/tempo/tempo.yaml
          volumeMounts:
            - name: config
              mountPath: /etc/tempo
      volumes:
        - name: config
          configMap:
            name: tempo-config
```

## Sampling Strategies

### Probabilistic Sampling

```yaml
# Sample 1% of traces
sampler:
  type: probabilistic
  param: 0.01
```

### Rate Limiting Sampling

```yaml
# Sample max 100 traces per second
sampler:
  type: ratelimiting
  param: 100
```

### Adaptive / Parent-based Sampling

```python
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased

# Sample based on trace ID (deterministic across services)
sampler = ParentBased(root=TraceIdRatioBased(0.01))
```

### Tail Sampling

For backends that support it (OTel Collector, Honeycomb, Datadog), tail sampling lets the collector keep traces that are interesting (errors, slow requests) and drop boring ones, regardless of the head-sampling decision. Useful when you want low overhead in steady state but full fidelity on anomalies.

## Trace Analysis

### Finding Slow Requests

**Query example (Jaeger):**

```
service=my-service
duration > 1s
```

Equivalent queries exist in Tempo (TraceQL), Honeycomb (BubbleUp / query builder), and Datadog APM. The fields are the same; the query syntax differs.

### Finding Errors

**Query example (Jaeger):**

```
service=my-service
error=true
tags.http.status_code >= 500
```

### Service Dependency Graph

Most backends automatically generate service dependency graphs from spans, showing:

- Service relationships
- Request rates
- Error rates
- Average latencies

## Best Practices

1. **Sample appropriately** (1-10% in production for head sampling; consider tail sampling for full-fidelity anomalies)
2. **Add meaningful tags** (user_id, request_id, tenant_id, feature_flag_id)
3. **Propagate context** across all service boundaries, including async queues
4. **Record exceptions** in spans (`span.record_exception(e)`)
5. **Use consistent naming** for operations (verb-noun: `get_users`, `enqueue_email`)
6. **Monitor tracing overhead** (target <1% CPU impact; benchmark before / after enabling)
7. **Set up alerts** for trace errors and trace-export failures
8. **Use baggage sparingly** (it propagates everywhere; high-cardinality baggage is expensive)
9. **Use span events** for important milestones inside long spans
10. **Document instrumentation** standards so all services agree on tag names

## Integration with Logging

### Correlated Logs

Inject the trace ID into log records so log queries can pivot directly to the trace and vice versa.

```python
import logging
from opentelemetry import trace

logger = logging.getLogger(__name__)

def process_request():
    span = trace.get_current_span()
    trace_id = span.get_span_context().trace_id

    logger.info(
        "Processing request",
        extra={"trace_id": format(trace_id, '032x')}
    )
```

## Troubleshooting

**No traces appearing:**

- Check collector endpoint
- Verify network connectivity from app pod to collector
- Check sampling configuration (you may be sampling everything out)
- Review application logs for exporter errors
- Confirm the exporter library matches the backend protocol (Thrift vs OTLP vs Zipkin)

**High latency overhead:**

- Reduce sampling rate
- Use `BatchSpanProcessor` rather than `SimpleSpanProcessor`
- Check exporter configuration (timeouts, queue size, max batch size)
- Inspect for noisy auto-instrumentation; selectively disable per-library instrumentations you do not need

**Broken trace continuity:**

- Confirm context propagation across async boundaries (background jobs, message queues)
- Check that downstream services parse the W3C `traceparent` header rather than only legacy formats
- Verify clock skew between services is acceptable

## Advanced topics (references)

The body covers SDK instrumentation, context propagation, backend setup, sampling, and trace analysis. For deeper work, load the matching reference:

| Reference | Read when |
|---|---|
| `references/otel-collector-pipelines.md` | Designing the OpenTelemetry Collector: agent vs gateway, receivers / processors / exporters / connectors, tail-sampling, scaling. |
| `references/instrumentation-auto-vs-manual.md` | Choosing between auto and manual instrumentation: per-language auto agents, coverage gaps, semantic conventions, hybrid migration. |

## Cross-references

- `prometheus-configuration`: paired metrics-collection skill; metrics + traces + logs is the classic observability triangle.
- `grafana-dashboards`: visualising traces, including service maps and latency heatmaps.
- `slo-implementation`: latency SLOs and burn-rate alerts derived from trace data.
- `oncall-runbooks`: trace-search-by-correlation-ID is a common runbook step; capture the query syntax in the runbook so the on-call doesn't reinvent it under pressure.
- `systematic-debugging`: traces are a Phase 2 narrowing tool; if traces are non-deterministic, raise the reproduction rate per the Phase 1 loop discipline before chasing trace gaps.
