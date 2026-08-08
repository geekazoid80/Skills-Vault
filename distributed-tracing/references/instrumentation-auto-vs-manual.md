# Instrumentation: Auto vs Manual

Auto-instrumentation and manual instrumentation solve different problems. Auto-instrumentation gives broad framework and library coverage with no code changes. Manual instrumentation adds business context that no agent can infer. Most production services need both.

## The Decision Framework

Start with auto-instrumentation for all framework and library calls (HTTP, database, messaging, gRPC). Add manual spans and attributes for:

- Business domain operations that cross multiple library calls (e.g., "process_order" wrapping a DB read, a validation step, and a queue publish)
- Internal operations invisible to auto-instrumentation (in-memory caches, custom queues, batch loops)
- High-value attributes: customer identifiers, feature flag values, business metrics, SLA-relevant context
- Error context beyond what the framework captures (the exception type is captured; the retry reason is not)
- Important milestones within a long span as span events: `span.add_event("payment_authorised", {"provider": "stripe"})`

Practical rule: if the span name or its attributes would require reading business code to derive, add it manually.

## Per-Language Auto Agents

### Java: javaagent

The Java agent instruments at the bytecode level with no application code changes. It is the most complete auto-instrumentation across all languages, covering 100+ frameworks.

```bash
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

java \
  -javaagent:opentelemetry-javaagent.jar \
  -Dotel.service.name=order-service \
  -Dotel.exporter.otlp.endpoint=http://otelcol:4317 \
  -Dotel.traces.sampler=parentbased_traceidratio \
  -Dotel.traces.sampler.arg=0.1 \
  -Dotel.resource.attributes=deployment.environment=production,service.version=2.4.1 \
  -jar myapp.jar
```

All `otel.*` JVM properties have environment variable equivalents (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, etc.).

Covered: Spring MVC/WebFlux, Hibernate/JDBC, Kafka, gRPC, AWS SDK v1/v2, Apache HttpClient, OkHttp, Lettuce/Jedis, MongoDB, all major servlet containers.

Not covered: custom business logic, Kotlin coroutine boundaries (partial), frameworks not on the instrumentation list.

### Python: opentelemetry-instrument

Uses `sitecustomize.py` hooks to monkey-patch supported libraries before any application code runs.

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install   # installs matching instrumentation packages

OTEL_SERVICE_NAME=order-service \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otelcol:4317 \
OTEL_TRACES_SAMPLER=parentbased_traceidratio \
OTEL_TRACES_SAMPLER_ARG=0.1 \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.version=2.4.1 \
opentelemetry-instrument python app.py
```

Covered: Flask, Django, FastAPI, AIOHTTP, requests, urllib3, SQLAlchemy, psycopg2, pymongo, redis, celery, kafka-python, boto3 (partial).

Not covered: `asyncio.create_task` context propagation across arbitrary task boundaries, custom thread pools. Context does not cross thread or task boundaries without manual work.

Disable a noisy instrumentation without removing it:

```bash
OTEL_PYTHON_DISABLED_INSTRUMENTATIONS=celery,redis opentelemetry-instrument python app.py
```

### Node.js: require hook

Monkey-patches modules at `require()` time via the `@opentelemetry/auto-instrumentations-node` meta-package.

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// tracing.js -- loaded before any other module
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  serviceName: 'order-service',
  traceExporter: new OTLPTraceExporter({ url: 'http://otelcol:4317' }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': { enabled: false },  // disable noisy fs tracing
  })],
});
sdk.start();
```

```bash
node --require ./tracing.js server.js
# or via NODE_OPTIONS for Docker CMD lines:
NODE_OPTIONS='--require ./tracing.js' node server.js
```

Covered: http/https, Express, Fastify, Koa, NestJS, gRPC, mysql/mysql2, pg, mongodb, redis/ioredis, kafka-node, aws-sdk.

Not covered: `worker_threads` boundaries (context does not cross thread boundaries without manual propagation).

### .NET: startup hook

Uses `DOTNET_STARTUP_HOOKS` to inject before `Main`.

```bash
dotnet tool install --global OpenTelemetry.DotNet.Auto

OTEL_SERVICE_NAME=order-service \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otelcol:4317 \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production \
otel-dotnet-auto-run dotnet MyApp.dll
```

Covered: ASP.NET Core, HttpClient, SqlClient, Entity Framework Core, gRPC client, StackExchange.Redis, RabbitMQ, MongoDB.

### Go: no generic auto agent (use library wrappers or eBPF)

Go does not support runtime bytecode injection. Two paths exist:

**eBPF-based (Odigos, Coroot, OTel eBPF):** instruments at the kernel level without code changes. Coverage is limited to HTTP and some DB calls; does not capture business attributes. Appropriate as a starting point before instrumentation is budgeted.

**Library wrappers (standard Go path):** replace the plain library import with the OTel-wrapped variant from `go.opentelemetry.io/contrib`:

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

mux := http.NewServeMux()
mux.Handle("/api/orders", otelhttp.NewHandler(http.HandlerFunc(ordersHandler), "orders"))
http.ListenAndServe(":8080", mux)
```

Available wrappers: `otelhttp`, `otelgrpc`, `otelsql` (database/sql), `otelgin`, `otelgorilla`, `otelecho`, AWS SDK v2, Google Cloud client libraries.

### Kubernetes: OTel Operator Instrumentation CR

The Operator injects auto-instrumentation init containers at admission time without modifying Deployment specs.

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: default-instrumentation
  namespace: my-namespace
spec:
  exporter:
    endpoint: http://otelcol-collector:4317
  propagators: [tracecontext, baggage]
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.0
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.45b0
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.45.0
```

Opt a pod in by annotation: `instrumentation.opentelemetry.io/inject-java: "true"`. Pin image versions in the CR; `latest` causes silent rollouts during Operator upgrades.

## What Auto Covers vs Gaps

| Layer | Auto covers | Auto does not cover |
|---|---|---|
| Inbound HTTP | Route, method, status code, response time | Auth outcome, user identity, tenant ID |
| Outbound HTTP | Target URL, method, status code | Retry count, circuit breaker state |
| SQL | Parameterised query, table, operation | Rows affected, cache hit/miss |
| Messaging | Topic, message ID, consumer group | Retry count, dead-letter reason |
| gRPC | Service, method, status code | Request/response payload size |
| Errors | Exception type and message | Upstream error context, business error codes |
| Business logic | Nothing | All of it |

## Semantic Conventions

Use standardised attribute names from the OTel semantic conventions specification in preference to inventing your own. Backends recognise standard names in service maps, dashboards, and alerting.

### HTTP

```
http.request.method       GET, POST, DELETE
http.response.status_code 200, 404, 500
http.route                /users/{id}   (template, not actual value)
url.full                  https://api.example.com/users/42
server.address            api.example.com
```

Never put user IDs or tokens in `url.full`; strip or redact first.

### Database

```
db.system                 postgresql, mysql, redis, mongodb, dynamodb
db.name                   orders_db
db.operation              SELECT, INSERT, UPDATE
db.statement              SELECT id, email FROM users WHERE id = ?
```

Use parameterised form in `db.statement`. If your ORM interpolates PII into statements, use the Collector `attributes` processor to hash or delete this field before export.

### Messaging

```
messaging.system          kafka, rabbitmq, aws_sqs, azure_service_bus
messaging.destination.name  order-events
messaging.operation       publish, receive, process
messaging.message.id      (unique message ID if available)
```

### Resource attributes (set on TracerProvider, apply to every span)

Minimum required by all major backends:

```
service.name              order-service
service.version           2.4.1
deployment.environment    production
```

Recommended additions:

```
service.namespace         payments-platform
host.name                 (auto-detected by resource detectors)
k8s.pod.name              (auto-detected in Kubernetes)
k8s.namespace.name        (auto-detected in Kubernetes)
cloud.provider            aws, gcp, azure
cloud.region              ap-southeast-1
```

Setting via environment variables (all languages):

```bash
OTEL_SERVICE_NAME=order-service
OTEL_SERVICE_VERSION=2.4.1
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.namespace=payments-platform
```

## Migrating from Auto-Only to Hybrid

**Span hierarchy:** manual spans created inside an auto-instrumented request automatically become children of the auto-span. The SDK propagates context via `AsyncLocalStorage` (Node.js), `contextvars` (Python), or thread-local (Java, .NET). No explicit parent-linking is needed in most cases.

**Attribute naming consistency:** once you choose `order.id` as a span attribute name, use it everywhere. Inconsistent names (`order_id`, `orderId`, `order.id`) fragment queries in the backend. Document attribute names in a project-level conventions file.

**Instrumentation library scoping:** use a scoped tracer name per library or module:

```python
tracer = trace.get_tracer("com.example.payments", "1.0.0")
```

The tracer name becomes `otel.library.name` on each span, helping filter by origin in the backend.

**Disabling auto for a component you now instrument manually:** each language provides a mechanism to avoid duplicate spans:
- Python: `OTEL_PYTHON_DISABLED_INSTRUMENTATIONS=redis`
- Node.js: `getNodeAutoInstrumentations({'@opentelemetry/instrumentation-redis': {enabled: false}})`
- Java: `-Dotel.instrumentation.redis.enabled=false`

**Testing instrumented code:** use the in-memory exporter in unit tests to assert spans without a live Collector:

```python
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

exporter = InMemorySpanExporter()
provider = TracerProvider()
provider.add_span_processor(SimpleSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# run code under test

spans = exporter.get_finished_spans()
assert spans[0].name == "process_order"
assert spans[0].attributes["order.id"] == "test-123"
```
