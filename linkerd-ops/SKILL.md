---
name: linkerd-ops
description: "Operating Linkerd service mesh day to day once Linkerd is the chosen mesh: the linkerd2-proxy Rust data plane, the destination/identity/proxy-injector control plane, zero-config automatic mTLS with SPIFFE identities and 24h certificate rotation, ServiceProfile per-route metrics/retries/timeouts and retry budgets, SMI TrafficSplit canary and Gateway API HTTPRoute, Server/AuthorizationPolicy/MeshTLSAuthentication authorization, multi-cluster gateway mirroring, ML-KEM-768 post-quantum key exchange, the Viz extension, and linkerd check troubleshooting. WHEN: \"Linkerd\", \"linkerd2-proxy\", \"linkerd check\", \"linkerd viz\", \"ServiceProfile\", \"TrafficSplit\", \"Linkerd mTLS\", \"Linkerd multi-cluster\", \"Linkerd install\", \"linkerd inject\", \"post-quantum mesh\", \"opaque-ports\", \"retry budget\". Do NOT use for: choosing whether to run a mesh at all or which mesh to pick (service-mesh-selection); Istio or Consul operation (istio-ops, consul-ops); any Kubernetes operation such as declaring a Service, Gateway, or NetworkPolicy, workloads, or cluster upgrades (kubernetes-ops); the security programme (zero-trust policy design, admission control, image scanning, supply-chain integrity, runtime protection) that the mesh serves (container-security); ingress and the L4/L7 balancer fronting the mesh (load-balancer-selection, nginx-load-balancing, haproxy-load-balancing, aws-load-balancing); certificate issuance and rotation tooling (cert-manager, lets-encrypt) and secret stores (hashicorp-vault-ops, secrets-hygiene); observability pipelines (prometheus-configuration, grafana-dashboards, distributed-tracing); CI/CD and IaC (cicd-platforms-ops, gh-actions-ci, terraform-iac-ops); clock and certificate-validity correctness (utc-timestamps)."
license: MIT
metadata:
  version: 1.0.0
---

# Linkerd operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: linkerd-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating Linkerd once Linkerd is the chosen service mesh: reasoning about the linkerd2-proxy data plane and the control plane, enabling and verifying automatic mTLS, shaping traffic with ServiceProfile and TrafficSplit, applying authorization policy, linking clusters with gateway mirroring, and troubleshooting with `linkerd check` and the Viz extension. It assumes Linkerd has been chosen; whether to run a mesh at all and which mesh to pick (Linkerd versus Istio versus Consul) is `service-mesh-selection`. Linkerd is the opinionated, minimal mesh: zero-config mTLS, an ultra-lightweight Rust proxy, and simplicity over feature richness. Many things that require configuration in Istio are automatic here.

This skill wires the mesh mechanics (automatic mTLS, ServiceProfile, TrafficSplit manifests, authorization policy). It routes the security programme (zero-trust policy design, admission control, image scanning, supply-chain integrity, runtime protection) to `container-security`, and it routes the Kubernetes objects the mesh sits on (Service, Gateway, NetworkPolicy, workloads, cluster upgrades) to `kubernetes-ops`.

## When to use

- Installing or upgrading Linkerd: CLI install, CRDs, control plane, the Viz, multi-cluster, and Jaeger extensions, sidecar injection, and the CNI plugin alternative to init containers.
- Enabling and verifying mTLS: confirming meshed edges are encrypted, reading `linkerd viz tap` TLS status, managing the trust anchor and its expiry.
- Shaping traffic: ServiceProfile per-route timeouts, retries, and retry budgets; SMI TrafficSplit canaries; Gateway API HTTPRoute weighting.
- Applying authorization: Server, AuthorizationPolicy, and MeshTLSAuthentication to control which identities may call a workload.
- Linking clusters: multi-cluster gateway mirroring, service export, and cross-cluster traffic splitting.
- Observing the mesh: Viz golden signals, tap, edges, and the Prometheus metrics the proxy exports.
- Troubleshooting: `linkerd check`, protocol-detection fallback to TCP, retry storms, trust-anchor expiry, and multi-cluster DNS naming.

## When not to use

- **Mesh selection**: whether to adopt a mesh at all, and choosing Linkerd over Istio or Consul, is `service-mesh-selection`. That umbrella decides whether Linkerd fits; this skill operates it once chosen.
- **Sibling meshes**: Istio operation (Envoy sidecars, ambient mode, VirtualService/DestinationRule, `istioctl`) is `istio-ops`; Consul service mesh (Consul Connect, intentions, Consul servers) is `consul-ops`. This skill covers Linkerd only.
- **Kubernetes operations**: declaring a Service, Gateway, HTTPRoute parent, or NetworkPolicy, and any workload, scheduling, storage, RBAC, or cluster-upgrade task, is `kubernetes-ops`. The mesh annotates and injects into those objects; it does not own them.
- **Security programme**: zero-trust policy design, admission control (OPA Gatekeeper, Kyverno), image scanning gates, supply-chain integrity, and runtime protection are `container-security`. Linkerd provides the mTLS and authorization mechanics; the programme that decides how to use them lives there.
- **Ingress and load balancing**: choosing and running the L4/L7 balancer that fronts the mesh is `load-balancer-selection`, `nginx-load-balancing`, `haproxy-load-balancing`, and `aws-load-balancing`. The mesh handles east-west traffic; the balancer handles north-south ingress.
- **Certificates and secrets**: issuing and auto-rotating the trust anchor and issuer certificates with cert-manager is `cert-manager`, with public issuance via `lets-encrypt`; a central secret store is `hashicorp-vault-ops`, and the handling discipline for any credential is `secrets-hygiene`.
- **Observability pipelines**: the Prometheus, dashboard, and tracing backends that consume Linkerd's metrics and spans are `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing`. The proxy's metrics and Jaeger spans originate here; the pipeline that stores and visualises them is there.
- **CI/CD and IaC**: the pipeline that applies mesh manifests is `cicd-platforms-ops` and `gh-actions-ci`; provisioning the cluster the mesh runs on is `terraform-iac-ops`.
- **Clock correctness**: mTLS certificate validity windows and 24h rotation depend on synchronised clocks; a skewed node clock corrupts them. That discipline is `utc-timestamps`.

## Classify the request first

Every request resolves to one of these, which determines what to load and how to reason. Also identify the Linkerd 2.x minor version; several features are version-gated (Gateway API and route-based authorization policy from 2.12+, with Server and ServerAuthorization from 2.11+; post-quantum key exchange from 2.19+). If the version is unclear, ask, then default guidance to the latest stable and note where behaviour differs.

| Class | Examples | Approach |
|---|---|---|
| Installation / upgrade | CLI install, CRDs, control plane, extensions, injection, CNI plugin, trust-anchor rotation | Run the install sequence below; verify with `linkerd check` at each step |
| Traffic management | ServiceProfile per-route policy, retry budgets, TrafficSplit canary, Gateway API HTTPRoute | Apply the manifest patterns; verify with `linkerd viz routes` and `stat` |
| Security / mTLS | mTLS verification, certificate management, authorization policy, post-quantum | mTLS is automatic; verify edges and taps; layer Server/AuthorizationPolicy for least privilege |
| Observability | Viz dashboard, tap, golden signals, edges, Prometheus integration | Use the Viz CLI; route the storage backend to the observability siblings |
| Multi-cluster | Gateway mirroring, service export, cross-cluster splitting | Install the extension on both clusters, link, export, split |
| Architecture / internals | proxy listeners, iptables interception, certificate chain, gateway model | Read `references/architecture.md` |

## Core model (condensed)

**Linkerd is opinionated and automatic.** mTLS is on by default between meshed workloads with no configuration. The proxy is a purpose-built Rust micro-proxy, not a general-purpose data plane, so the memory and latency cost is a fraction of an Envoy-based mesh. There is no ambient (sidecar-less) mode: Linkerd injects a sidecar into every meshed pod.

```
Control Plane (namespace: linkerd):
  destination    Service discovery, policy distribution to proxies
  identity       Certificate authority, mTLS cert issuance and rotation (24h default)
  proxy-injector Mutating webhook, injects the linkerd2-proxy sidecar

Data Plane:
  linkerd2-proxy (per pod, Rust sidecar)
  - Ultra-lightweight: ~20-30 MB RAM (versus Envoy's 50 MB+)
  - Purpose-built for service mesh (not a general-purpose proxy)
  - HTTP/1.1, HTTP/2, gRPC, WebSocket, TCP
  - Built-in mTLS, retries, timeouts, circuit breaking, L7 metrics
  - Protocol detection (no manual annotation for HTTP)
```

**Why linkerd2-proxy (Rust):**

- **Memory**: ~20-30 MB per pod versus Envoy's ~50 MB+ (saves 2-3x memory per pod).
- **Performance**: lower p99 latency than Envoy (Buoyant's published 2025 benchmark showed Linkerd about 163ms lower p99 than Istio sidecar mode at 2,000 RPS, and roughly 11ms lower than Istio ambient; a vendor benchmark, so read it as directional rather than neutral).
- **Security**: Rust memory safety eliminates buffer-overflow vulnerabilities.
- **Focus**: built only for service mesh, not a general-purpose proxy. Smaller codebase, smaller attack surface.
- **Control-plane memory**: ~200-300 MB versus Istio's 600 MB to 2 GB.

## Installation

```bash
# Install CLI
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

# Pre-flight check
linkerd check --pre

# Install CRDs
linkerd install --crds | kubectl apply -f -

# Install control plane
linkerd install | kubectl apply -f -

# Verify
linkerd check

# Install extensions
linkerd viz install | kubectl apply -f -          # dashboard + metrics
linkerd multicluster install | kubectl apply -f - # multi-cluster
linkerd jaeger install | kubectl apply -f -       # distributed tracing
```

### Sidecar injection

```bash
# Enable auto-injection for a namespace
kubectl annotate namespace production linkerd.io/inject=enabled

# Manual injection
linkerd inject deployment.yaml | kubectl apply -f -

# Verify the proxy is running
linkerd check --proxy -n production

# Check meshed pods
linkerd viz stat deployment -n production
```

Kubernetes owns the Deployment, Service, and namespace being injected into; that is `kubernetes-ops`. Linkerd only adds the sidecar and its annotations.

## mTLS (zero configuration)

Linkerd automatically enables mTLS on every TCP connection between meshed workloads. No configuration is required.

### How it works

1. The `identity` component issues X.509 certificates to each proxy at startup.
2. Certificates use the SPIFFE identity format: `spiffe://root.linkerd.cluster.local/ns/production/sa/myapp`.
3. Certificates rotate automatically every 24 hours.
4. Both client and server proxies verify certificates, giving mutual authentication.

### Verify mTLS

```bash
# Check mTLS status for all edges in a namespace
linkerd viz edges deployment -n production

# Live traffic stream showing mTLS status
linkerd viz tap deployment/myapp -n production

# Output shows TLS=true for encrypted connections
# req id=0:0 proxy=in  src=10.1.2.3:54321 dst=10.1.2.4:8080 tls=true :method=GET :path=/api/health
```

### Certificate management

```bash
# Check trust-anchor expiry
linkerd check --output json | jq '.categories[] | select(.categoryName == "linkerd-identity")'

# Rotate the trust anchor (before expiry)
step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password --not-after=8760h
linkerd upgrade --identity-trust-anchors-file=ca.crt | kubectl apply -f -
```

**Critical**: trust anchors have a default lifetime of 1 year. Set a calendar reminder to rotate before expiry, or use `cert-manager` for automatic rotation. Issuing and auto-rotating those certificates is `cert-manager`; the handling discipline for the key material is `secrets-hygiene`.

## Post-quantum cryptography (Linkerd 2.19+)

Linkerd 2.19 (released 31 October 2025) introduced ML-KEM-768 hybrid key exchange for mTLS, an early production service mesh to ship post-quantum key exchange enabled by default (the upstream announcement does not itself claim primacy, so avoid asserting "first").

### What this means

- **ML-KEM-768**: a NIST-standardised post-quantum Key Encapsulation Mechanism.
- **Hybrid key exchange**: combines ML-KEM-768 with X25519 (classical). If ML-KEM is broken, X25519 still provides security. If X25519 is broken by quantum computers, ML-KEM provides security.
- **Forward secrecy**: protects against "harvest now, decrypt later" attacks.
- **Transparent**: no application changes required. Enabled by default in 2.19+.

### Performance impact

- Key-exchange size increases by ~1 KB per connection.
- Negligible CPU overhead for ML-KEM-768 operations.
- Connection establishment takes ~0.5ms longer.
- Throughput impact: under 1%.

## Traffic management

### ServiceProfile (per-route policies)

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: myapp.production.svc.cluster.local
  namespace: production
spec:
  routes:
  - name: GET /api/users
    condition:
      method: GET
      pathRegex: /api/users(/.*)?
    responseClasses:
    - condition:
        status:
          min: 500
          max: 599
      isFailure: true
    timeout: 5s
    isRetryable: true

  - name: POST /api/orders
    condition:
      method: POST
      pathRegex: /api/orders
    timeout: 10s
    isRetryable: false    # POST is not safe to retry

  retryBudget:
    retryRatio: 0.2          # max 20% additional load from retries
    minRetriesPerSecond: 10  # always allow at least 10 retries/s
    ttl: 10s
```

**Retry budgets** prevent retry storms. Unlike Istio's per-attempt retries, Linkerd limits total retry traffic as a percentage of original traffic.

### TrafficSplit (canary deployments)

```yaml
# SMI TrafficSplit for canary
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: myapp-canary
  namespace: production
spec:
  service: myapp              # root service (clients connect to this)
  backends:
  - service: myapp-stable     # stable version
    weight: 90
  - service: myapp-canary     # canary version
    weight: 10
```

**How it works**: the root service (`myapp`) becomes a virtual service. Linkerd's proxy routes traffic to the backend services based on weights. Both backend services must have the same pod labels and ports. The Service objects themselves are `kubernetes-ops`; the split is Linkerd.

### Gateway API (Linkerd 2.12+)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
  namespace: production
spec:
  parentRefs:
  - name: myapp
    kind: Service
    group: ""
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: myapp-v1
      port: 8080
      weight: 90
    - name: myapp-v2
      port: 8080
      weight: 10
```

### Authorization policy (Linkerd 2.12+; Server and ServerAuthorization from 2.11+)

```yaml
# Server: define what the service accepts
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata:
  name: myapp-http
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: myapp
  port: 8080
  proxyProtocol: HTTP/1

---
# AuthorizationPolicy: who can call the server
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend
  namespace: production
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: myapp-http
  requiredAuthenticationRefs:
  - name: frontend-mtls
    kind: MeshTLSAuthentication
    group: policy.linkerd.io

---
# MeshTLSAuthentication: identity of allowed callers
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: frontend-mtls
  namespace: production
spec:
  identities:
  - "*.production.serviceaccount.identity.linkerd.cluster.local"
```

This is the mesh authorization mechanic. The decision of what least-privilege policy to enforce across the estate (the zero-trust programme) is `container-security`.

## Observability

### Linkerd Viz dashboard

```bash
# Open the dashboard
linkerd viz dashboard

# CLI-based golden signals
linkerd viz stat deployment -n production
# NAME       MESHED   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
# frontend   1/1      100.00%   50    5ms           15ms          25ms
# api        1/1      99.80%    150   3ms           12ms          45ms
# db         1/1      99.99%    200   1ms           5ms           10ms

# Top endpoints by request volume
linkerd viz top deployment/myapp -n production

# Live request stream (tap)
linkerd viz tap deployment/myapp -n production
# Shows: source, destination, method, path, status, latency, TLS status

# Traffic edges (who talks to whom)
linkerd viz edges deployment -n production
```

### Prometheus metrics

Linkerd automatically exports golden-signal metrics:

| Metric | Description |
|---|---|
| `request_total` | Total requests with labels (direction, tls, status, route) |
| `response_total` | Total responses with status-code classification |
| `response_latency_ms` | Response-latency histogram |
| `tcp_open_total` | TCP connections opened |
| `tcp_close_total` | TCP connections closed |
| `tcp_open_connections` | Currently open TCP connections |

The proxy exposes these; the Prometheus that scrapes and stores them and the Grafana that charts them are `prometheus-configuration` and `grafana-dashboards`. Distributed traces from the Jaeger extension route to `distributed-tracing`.

## Multi-cluster

```bash
# Install the multi-cluster extension on both clusters
linkerd multicluster install | kubectl apply -f -

# Link clusters (run on the target cluster)
linkerd multicluster link --context=east --cluster-name=east | \
  kubectl --context=west apply -f -

# Export a service for cross-cluster access
kubectl --context=east annotate svc myapp mirror.linkerd.io/exported=true

# In the west cluster, the service appears as myapp-east
kubectl --context=west get svc myapp-east
```

### How it works

- A **gateway** component runs in each cluster (Deployment plus LoadBalancer Service).
- Cross-cluster traffic flows through gateways with mTLS.
- Services are **mirrored**: `myapp` in east appears as `myapp-east` in west.
- Traffic splitting between local and remote is via TrafficSplit.
- No flat network is required; it works across cloud providers.

## Troubleshooting

Start with `linkerd check`, then narrow by symptom:

- **Control-plane or proxy health**: `linkerd check` for the full sweep, `linkerd check --proxy -n <ns>` for data-plane health in a namespace.
- **Protocol-detection failure**: if Linkerd cannot detect HTTP, it falls back to TCP and you lose per-route metrics, retries, and routing. Mark known-TCP ports opaque with the `config.linkerd.io/opaque-ports` annotation (for example `"3306,6379,5432"`).
- **Retry storms**: without a retry budget, retries can amplify a failure. Always configure `retryBudget` in the ServiceProfile.
- **Trust-anchor expiry**: the default 1-year lifetime, once expired, breaks all mTLS at once. Rotate ahead of expiry or automate with cert-manager.
- **Missing per-route data**: `linkerd viz routes deployment/<name>` requires a ServiceProfile whose name exactly matches the fully qualified DNS name.
- **Proxy internals**: `linkerd diagnostics proxy-metrics -n <ns> deployment/<name>` dumps the proxy's raw metrics for deep debugging.

## Common pitfalls

1. **Trust-anchor expiry**: default 1-year lifetime. If the trust anchor expires, all mTLS fails. Set calendar reminders or use cert-manager for auto-rotation.
2. **Protocol-detection failure**: if Linkerd cannot detect HTTP, it falls back to TCP (no per-route metrics). Use the `config.linkerd.io/opaque-ports` annotation for known-TCP ports.
3. **Retry storms**: without retry budgets, retries can amplify failures. Always configure `retryBudget` in the ServiceProfile.
4. **No JWT authentication**: unlike Istio, Linkerd has no built-in JWT validation. Use an API gateway or application-level JWT handling.
5. **ServiceProfile naming**: the ServiceProfile name must exactly match the fully qualified service DNS name (`myapp.production.svc.cluster.local`).
6. **Multi-cluster DNS**: mirrored services use `<service>-<cluster>` naming. Applications must be aware of this naming convention for failover.
7. **No ambient mode**: Linkerd uses sidecar injection only. There is no sidecar-less option like Istio's ambient mode.

## Version notes

Guidance defaults to the latest stable when the version is unknown. Boundaries that change behaviour:

- **2.11+**: Server and ServerAuthorization, the first authorization primitives.
- **2.12+**: route-based authorization policy (AuthorizationPolicy, MeshTLSAuthentication, NetworkAuthentication) and Gateway API HTTPRoute (weighted routing alongside SMI TrafficSplit).
- **2.19+** (October 2025): ML-KEM-768 hybrid post-quantum key exchange for mTLS, on by default.

The trust-anchor lifetime (default 1 year) and the 24h workload-certificate rotation are stable across these releases and are the two operational clocks most likely to bite. Validate mesh manifests against the target cluster before an upgrade.

## Reference router

- `references/architecture.md`: linkerd2-proxy listeners and protocol detection, the destination/identity/proxy-injector control plane, the certificate chain and mTLS handshake, post-quantum key exchange internals, iptables traffic interception and the CNI plugin, the multi-cluster gateway-mirroring model, and the Viz and Jaeger extension architecture. Read for "how does X work" and internals questions.

## Cross-references

- `service-mesh-selection`: the vendor-neutral umbrella that decides whether to run a mesh and which one; this skill operates Linkerd once that choice is made. Reciprocal reference.
- `istio-ops`, `consul-ops`: sibling meshes. Istio (Envoy sidecars, ambient mode, richer policy) and Consul (Connect, intentions) trade Linkerd's simplicity for feature breadth.
- `kubernetes-ops`: the Kubernetes objects the mesh sits on, Services, Gateways, HTTPRoute parents, NetworkPolicy, workloads, namespaces, and cluster upgrades. Declare them there; mesh them here.
- `container-security`: the security programme this skill's mTLS and authorization mechanics serve, zero-trust policy design, admission control, image scanning, supply chain, runtime protection. Wire the mesh knobs here; take the policy from there.
- `load-balancer-selection`, `nginx-load-balancing`, `haproxy-load-balancing`, `aws-load-balancing`: the ingress and L4/L7 balancer fronting the mesh. Linkerd handles east-west; those handle north-south.
- `cert-manager`, `lets-encrypt`: issuing and auto-rotating the trust anchor and issuer certificates, and public issuance.
- `hashicorp-vault-ops`, `secrets-hygiene`: a central secret store and the handling discipline for the trust-anchor key material and any credential.
- `prometheus-configuration`, `grafana-dashboards`, `distributed-tracing`: the pipeline that stores and visualises the metrics the proxy exports and the spans the Jaeger extension emits.
- `cicd-platforms-ops`, `gh-actions-ci`: the CD pipeline that applies mesh manifests; `terraform-iac-ops` provisions the cluster underneath.
- `utc-timestamps`: mTLS certificate validity windows and 24h rotation depend on synchronised clocks; skew corrupts them.

## Red flags

- About to run a ServiceProfile with retries but no `retryBudget`, leaving the mesh open to retry storms that amplify a failure.
- About to let a trust anchor approach its 1-year expiry with no rotation reminder or cert-manager automation, so all mTLS fails at once.
- About to route known-TCP traffic (databases, Redis) without an `opaque-ports` annotation, so protocol detection stalls for 10s and then falls back.
- About to name a ServiceProfile something other than the fully qualified service DNS name, so no per-route metrics or policy apply.
- About to assume Linkerd validates JWTs like Istio; it does not, so a missing API-gateway or app-level check leaves requests unauthenticated.
- About to expect an ambient (sidecar-less) mode; Linkerd injects a sidecar into every meshed pod, and there is no opt-out.
- About to hard-code a mirrored service name without accounting for the `<service>-<cluster>` convention, breaking cross-cluster failover.
- About to treat the mesh as the security programme; mTLS and authorization are mechanics, and the policy that governs them is `container-security`.

## Bottom line

Linkerd is the opinionated, minimal mesh: a lightweight Rust proxy, zero-config mTLS with SPIFFE identities and 24h certificate rotation, and a small control plane of destination, identity, and proxy-injector. Inject the sidecar, verify with `linkerd check` and `linkerd viz edges`, and let mTLS run by default. Shape traffic with ServiceProfile (always with a retry budget) and canary with TrafficSplit or Gateway API; layer Server and AuthorizationPolicy for identity-scoped access. Mark known-TCP ports opaque, keep the trust anchor rotated ahead of its 1-year expiry, and remember there is no ambient mode and no built-in JWT validation. Bring the mesh choice from `service-mesh-selection`, the Kubernetes objects from `kubernetes-ops`, and the security policy from `container-security`; keep certificates, secrets, ingress, observability, and CD in their proper homes.
