# Service mesh concepts

The fundamentals a service mesh selection rests on: what a mesh is, the sidecar and ambient architectures, the data plane versus control plane split, mTLS and SPIFFE identity, traffic management, observability, authorization policy, the Gateway API, and multi-cluster patterns. These are product-agnostic; Istio, Linkerd, and Consul Connect all implement the same core patterns, which is why the selection reasoning outlasts any one mesh.

## What is a service mesh?

A service mesh is a dedicated infrastructure layer for handling service-to-service communication. It provides a uniform way to connect, secure, observe, and control traffic between microservices without modifying application code.

## Architecture patterns

### Sidecar pattern

The traditional service mesh architecture deploys a proxy alongside every service instance:

```
Pod:
  +---------------------------------------------------+
  |  Application container                            |
  |  (your code, unmodified)                          |
  |     |                                             |
  |     | localhost traffic                           |
  |     v                                             |
  |  iptables redirect (transparent interception)     |
  |     |                                             |
  |     v                                             |
  |  Sidecar proxy (Envoy / linkerd2-proxy)           |
  |  - mTLS encryption and decryption                 |
  |  - Traffic routing rules                           |
  |  - Metrics, tracing spans                          |
  |  - Authorization policy enforcement               |
  +---------------------------------------------------+
         |
    mTLS-encrypted traffic
         |
  +---------------------------------------------------+
  |  Destination pod (same structure)                 |
  +---------------------------------------------------+
```

**How transparent interception works**: an init container modifies the pod's iptables rules to redirect all inbound and outbound TCP traffic through the sidecar proxy. The application sees only localhost connections.

### Ambient pattern (sidecar-less)

The ambient pattern splits mesh functionality into two layers:

```
Node:
  +---------------------------------------------------------------+
  |  ztunnel (DaemonSet, one per node)                            |
  |  - Layer-4 mTLS (encrypt and decrypt all pod traffic on node) |
  |  - Layer-4 authorization policies                             |
  |  - Layer-4 telemetry (connection-level metrics)               |
  |  - HBONE tunnels (HTTP/2 CONNECT between nodes)               |
  +---------------------------------------------------------------+
         |
    HBONE tunnel (mTLS over HTTP/2)
         |
  +---------------------------------------------------------------+
  |  Waypoint proxy (Deployment, per namespace or service)        |
  |  - Layer-7 HTTP routing, retries, timeouts                    |
  |  - Layer-7 authorization policies                             |
  |  - Layer-7 telemetry (request-level metrics)                  |
  |  - Only deployed when layer-7 features are needed             |
  +---------------------------------------------------------------+
```

**Key difference**: no per-pod proxy. Layer-4 (mTLS, basic auth) runs at the node level. Layer-7 (HTTP routing) runs only where explicitly needed.

### Data plane versus control plane

| Component | Data plane | Control plane |
|---|---|---|
| What it does | Handles actual traffic (proxy, encrypt, route, observe) | Configures the data plane (policies, certificates, service discovery) |
| Where it runs | Per pod (sidecar), per node (ambient), or per service | Centralised deployment (1 to 3 replicas) |
| Examples | Envoy, linkerd2-proxy, ztunnel | istiod, Linkerd destination and identity, Consul servers |
| Failure impact | Affects an individual service's traffic | Affects policy updates, but existing config keeps working |

## mTLS (mutual TLS)

### How service mesh mTLS works

1. **Identity**: each service gets a cryptographic identity (X.509 certificate) from the mesh's CA.
2. **Certificate format**: typically SPIFFE (Secure Production Identity Framework for Everyone) X.509 SVIDs.
   - URI SAN: `spiffe://cluster.local/ns/production/sa/frontend`
3. **Certificate lifecycle**: automatically issued, rotated (every 24h in Linkerd, configurable in Istio), and revoked.
4. **Handshake**: both client and server present certificates. Both verify against the mesh CA.
5. **Encryption**: all pod-to-pod traffic is encrypted with TLS 1.3 (or TLS 1.2 minimum).

### SPIFFE identity

```
spiffe://trust-domain/ns/namespace/sa/service-account

Example:
spiffe://cluster.local/ns/production/sa/frontend
  |           |            |              |
  scheme   trust domain  namespace    service account
```

This identity is used in authorization policies to allow or deny specific service-to-service communication.

### mTLS modes

| Mode | Behaviour | Use case |
|---|---|---|
| STRICT | Only mTLS connections accepted | Production (after migration) |
| PERMISSIVE | Both mTLS and plaintext accepted | Migration period (meshed plus non-meshed services) |
| DISABLE | No mTLS | Debugging, external services |

**Migration pattern**: start with PERMISSIVE globally, migrate services into the mesh, then switch to STRICT once all services are meshed.

## Traffic management

### Load balancing algorithms

| Algorithm | Behaviour | Best for |
|---|---|---|
| Round robin | Rotate through endpoints sequentially | Default, uniform workloads |
| Least connections | Route to the endpoint with fewest active connections | Variable request durations |
| Random | Select a random endpoint | Simple, low overhead |
| Ring hash | Consistent hashing by header or cookie | Session affinity, caching |
| Maglev | Google's consistent hashing | Large-scale layer-4 load balancing |

### Traffic splitting (canary / A/B)

Route a percentage of traffic to a new version:

```
100% traffic
  |
  +--> 90% to v1 (stable)
  |
  +--> 10% to v2 (canary)
```

Progressive delivery: start at 1%, monitor error rate and latency, increase to 5%, 10%, 25%, 50%, 100%.

### Circuit breaking

Prevent cascading failures by stopping requests to unhealthy upstream services:

```
Normal:     Client to Proxy to Service (healthy)
                                   |
                              response OK

Tripped:    Client to Proxy --X--> Service (unhealthy)
                         |
                    503 immediately
                    (fast failure, no waiting)

Half-open:  Client to Proxy to Service (probe request)
                                   |
                              if OK, close the circuit (resume normal)
                              if fail, keep the circuit open
```

Circuit breaker parameters:

- **Consecutive errors**: the number of failures before tripping (for example, 5 consecutive 5xx).
- **Interval**: the time window for counting errors.
- **Base ejection time**: how long the endpoint is ejected.
- **Max ejection percent**: the maximum percentage of endpoints that can be ejected (prevents ejecting all of them).

### Retries

Automatically retry failed requests:

| Parameter | Purpose |
|---|---|
| Attempts | Max number of retries (including the original request) |
| Per-try timeout | Timeout for each individual attempt |
| Retry on | Conditions to retry (5xx, connection-failure, reset, and so on) |
| Retry budget | Max percentage of requests that can be retries (prevents retry storms) |

**Retry storms**: without retry budgets, retries can amplify failures. If service A retries 3x to service B, and B retries 3x to service C, a single failure generates 9 requests to C.

### Fault injection

Inject failures for chaos engineering:

| Type | Effect | Use case |
|---|---|---|
| Delay | Add artificial latency | Test timeout handling |
| Abort | Return an error status code | Test error handling |
| Rate limit | Inject for a percentage of traffic | Gradual fault testing |

### Timeouts

| Timeout type | Scope |
|---|---|
| Request timeout | Total time for the entire request (including retries) |
| Per-try timeout | Time for each individual attempt |
| Idle timeout | Connection idle timeout before closing |
| Connection timeout | Time to establish the upstream connection |

## Observability

### Golden signals (layer-7 metrics)

Service meshes automatically emit per-service metrics:

| Signal | Metric | What it tells you |
|---|---|---|
| Latency | Request duration histogram | How fast the service responds (p50, p95, p99) |
| Traffic | Request rate (RPS) | How much load the service handles |
| Errors | Error rate (4xx, 5xx) | How reliable the service is |
| Saturation | Connection count, queue depth | How close to capacity |

These metrics are tagged with:

- Source service (who is calling)
- Destination service (who is being called)
- HTTP method, path, response code
- mTLS status (encrypted or not)

### Distributed tracing

Service mesh proxies generate trace spans for each hop:

```
[Client] --span1--> [Frontend proxy] --span2--> [API proxy] --span3--> [DB proxy]
     |_________________________________trace context________________________________|
```

**Application responsibility**: the mesh proxy generates spans, but the application must propagate trace context headers between inbound and outbound requests:

- W3C TraceContext: `traceparent`, `tracestate`
- B3: `x-b3-traceid`, `x-b3-spanid`, `x-b3-parentspanid`, `x-b3-sampled`
- Istio: `x-request-id`

Without header propagation, traces are disconnected per-hop spans.

### Access logging

Mesh proxies can log every request with structured data:

- Source and destination service identity
- Request method, path, protocol
- Response code, bytes sent and received
- Duration
- mTLS handshake status

## Authorization policies

### Policy model

```
Identity-based (not IP-based):
  "Allow service frontend (SA: frontend, NS: production)
   to call service api (SA: api, NS: production)
   with HTTP GET on /api/v1/*
   when the JWT issuer is accounts.example.com"
```

### Policy evaluation order

1. **CUSTOM** action (external authorization) is evaluated first.
2. **DENY** policies are evaluated second (any match means deny).
3. **ALLOW** policies are evaluated last (must match at least one to allow; no ALLOW policies means allow all).

**Default deny**: create an empty AuthorizationPolicy to deny all traffic, then add specific ALLOW rules.

## Gateway API (Kubernetes standard)

The Kubernetes Gateway API is replacing mesh-specific routing APIs:

```yaml
# Gateway (entry point)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: istio   # or linkerd, consul
  listeners:
  - name: https
    port: 443
    protocol: HTTPS

# HTTPRoute (routing rules)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
spec:
  parentRefs:
  - name: my-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-service
      port: 8080
      weight: 90
    - name: api-canary
      port: 8080
      weight: 10
```

All major meshes now support the Gateway API, providing a standardised way to define traffic routing that is portable between mesh implementations.

## Multi-cluster patterns

### Flat network

All clusters share a flat network (same pod CIDR, routable between clusters):

- The simplest model, but it requires network connectivity.
- Used by Istio multi-cluster with a shared control plane.

### Gateway-based

Clusters communicate through mesh gateways:

- Traffic exits cluster A through a gateway and enters cluster B through a gateway.
- Works across cloud providers, VPNs, and air-gapped networks.
- Used by Linkerd (gateway mirroring) and Consul (mesh gateways).

### Federation

Multiple independent mesh control planes with cross-mesh communication:

- Each cluster has its own control plane.
- Service discovery spans clusters.
- Consul's WAN federation is the most mature implementation.
