---
name: istio-ops
description: "Operating an Istio service mesh day to day once Istio is the chosen mesh: ambient mode (ztunnel, waypoint proxies, HBONE) and sidecar mode (Envoy injection, iptables interception), the istiod control plane and the Envoy/xDS data plane, traffic management (VirtualService, DestinationRule, Gateway, Kubernetes Gateway API), the security mechanics (PeerAuthentication mTLS, AuthorizationPolicy, RequestAuthentication JWT), observability (Istio metrics, Kiali, trace headers), and troubleshooting with istioctl. WHEN: \"Istio\", \"istioctl\", \"istiod\", \"VirtualService\", \"DestinationRule\", \"ambient mesh\", \"ztunnel\", \"waypoint\", \"HBONE\", \"Envoy sidecar\", \"sidecar injection\", \"Istio Gateway\", \"PeerAuthentication\", \"AuthorizationPolicy\", \"RequestAuthentication\", \"mTLS in the mesh\", \"istioctl analyze\", \"istioctl proxy-status\". Do NOT use for: whether to run a service mesh at all or which mesh to pick (service-mesh-selection); the sibling meshes (linkerd-ops, consul-ops); any Kubernetes operation, or declaring a Gateway/Service/NetworkPolicy (kubernetes-ops); the security programme that decides zero-trust policy, admission enforcement, image scanning, or supply chain (container-security); ingress and the L4/L7 balancer fronting a gateway (load-balancer-selection, nginx-load-balancing, haproxy-load-balancing, aws-load-balancing); in-mesh certificates (cert-manager, lets-encrypt) and secret stores (hashicorp-vault-ops, secrets-hygiene); the observability pipeline that scrapes and stores metrics and traces (prometheus-configuration, grafana-dashboards, distributed-tracing); GitOps and CD (cicd-platforms-ops, gh-actions-ci); cluster provisioning as code (terraform-iac-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Istio operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: istio-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating an Istio service mesh once Istio is the chosen mesh: reasoning about the istiod control plane and the Envoy/ztunnel data plane, choosing between ambient and sidecar mode, wiring traffic management, applying mTLS and authorization policy, setting up observability, and troubleshooting with istioctl. It assumes Istio has already been chosen; the whether-to-run-a-mesh and which-mesh decision lives in `service-mesh-selection`, and the sibling meshes are `linkerd-ops` and `consul-ops`.

The boundary matters. This skill wires the mesh mechanics: the mTLS configuration, the AuthorizationPolicy manifests, the traffic routing. The security programme that decides the zero-trust policy, the admission enforcement, and the supply-chain and image-scanning gates is `container-security`. Declaring a Kubernetes Gateway, Service, or NetworkPolicy is `kubernetes-ops`; the L4/L7 balancer that fronts an Istio gateway is `load-balancer-selection` and its vendor siblings.

Coverage spans recent Istio releases; the supported window as of 2026 is roughly 1.28 through 1.30 (a minor is supported until six weeks after its N+2 successor, so the exact window moves; confirm against istio.io/latest/news/support). Ambient mesh (ztunnel plus optional waypoint) went GA in 1.24 and is the recommended architecture for new deployments; sidecar mode remains fully supported. The core model is stable across these releases; the version-specific detail lives under `references/versions/`.

## When to use

- Choosing and running a data-plane mode: ambient (ztunnel L4, waypoint L7) versus sidecar (per-pod Envoy), or migrating from one to the other.
- Traffic management: canary and blue-green rollouts, header-based routing, traffic mirroring, circuit breaking, timeouts and retries with VirtualService and DestinationRule.
- Gateways: an Istio `Gateway` plus VirtualService, or the Kubernetes Gateway API (`gatewayClassName: istio`) with HTTPRoute.
- Security mechanics: STRICT versus PERMISSIVE mTLS with PeerAuthentication, default-deny plus explicit-allow AuthorizationPolicy, JWT validation with RequestAuthentication.
- Observability wiring: the built-in Istio Prometheus metrics, Kiali topology, trace-header propagation, and the Telemetry API.
- Installation and control plane: install profiles (ambient, default, minimal), istiod sizing and HA, external CA integration, IstioOperator customisation.
- Troubleshooting: `istioctl analyze`, `istioctl proxy-status`, `istioctl proxy-config`, proxy and ztunnel logs, `istioctl authn tls-check`.

## When not to use

- **Whether or which mesh**: deciding to adopt a mesh at all, or choosing Istio over Linkerd, Consul, or Cilium Service Mesh, is `service-mesh-selection`. That umbrella makes the choice; this skill operates Istio once it is made.
- **Sibling meshes**: `linkerd-ops` and `consul-ops` operate the other meshes. This skill is Istio-specific; do not apply its manifests to another mesh.
- **Kubernetes operation**: any cluster operation, and declaring a Kubernetes `Gateway`, `Service`, or `NetworkPolicy`, is `kubernetes-ops`. Istio consumes those objects; declaring them and running the cluster underneath live there.
- **Security programme**: the zero-trust policy, admission enforcement (OPA Gatekeeper, Kyverno), Pod Security Standards, image scanning, supply-chain integrity, and runtime protection are `container-security`. This skill writes the PeerAuthentication and AuthorizationPolicy; the programme that decides what they should say lives there.
- **Ingress and load balancing**: choosing the ingress or balancer approach is `load-balancer-selection`; the implementations are `nginx-load-balancing`, `haproxy-load-balancing`, and `aws-load-balancing`. Declaring an Istio gateway is here; the L4/L7 balancer in front of it is there.
- **Certificates and secrets**: in-mesh and service certificates are `cert-manager`, with public issuance via `lets-encrypt`; a central secret store is `hashicorp-vault-ops`, and the handling discipline for any credential is `secrets-hygiene`. istiod's own CA is covered here; external CA integration hands off to those.
- **Observability pipeline**: the Prometheus that scrapes the mesh metrics, the Grafana that renders them, and the tracing backend that stores spans are `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing`. Istio emits the metrics and propagates the trace headers here; the pipeline that consumes them lives there.
- **GitOps and CD**: delivering the mesh manifests through ArgoCD or Flux, and the pipelines that apply them, are `cicd-platforms-ops` and `gh-actions-ci`.
- **Cluster provisioning as code**: standing up the cluster and installing Istio through Terraform is `terraform-iac-ops`. Operating the mesh is here.

## Classify the request first

Every request resolves to one of these, which determines the reference to load. Also determine the data-plane mode: is the user running ambient mesh or sidecar mode? This fundamentally changes the architecture and the troubleshooting approach. Ambient is GA since 1.24. If the mode or the Istio minor version is unclear, ask, then default guidance to the latest stable and note where behaviour differs.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | istiod (Pilot, Citadel, Galley), xDS/ADS, ztunnel, waypoint, HBONE, Envoy sidecar internals, certificate flow, multi-cluster topologies | `references/architecture.md` |
| Traffic management / design | canary, blue-green, mirroring, circuit breaking, timeouts and retries, egress control, Sidecar-resource scoping, ambient-versus-sidecar selection | `references/best-practices.md` |
| Security | mTLS mode, AuthorizationPolicy, JWT, defence in depth, STRICT migration | this file plus `references/best-practices.md` |
| Observability | Istio metrics, Kiali, tracing headers, Telemetry API, access logs, alerting | this file plus `references/best-practices.md` |
| Installation / migration | ambient profile, sidecar-to-ambient migration, revision-based upgrade | `references/best-practices.md`, `references/versions/1.25.md` |
| Version-specific | ambient stability, migration tooling, Gateway API maturity per release | `references/versions/1.25.md` |

Work a request by classifying it, determining the mode, loading the matching reference, reasoning with awareness of Envoy proxy behaviour, then recommending actionable YAML and istioctl commands with validation steps (`istioctl analyze`, `istioctl proxy-status`, Kiali).

## Core model (condensed)

**istiod is the control plane; Envoy and ztunnel are the data plane.** istiod is a single binary that merges the historic Pilot (service discovery and config translation), Citadel (the certificate authority), and Galley (config validation). It watches the Kubernetes API and pushes configuration to every proxy over Envoy's xDS APIs, aggregated on one gRPC stream (ADS). Changes propagate in seconds.

```
istiod (control plane)
  watches Kubernetes API (Services, Endpoints, Pods, Istio CRDs)
  translates Istio CRDs -> Envoy xDS (LDS, RDS, CDS, EDS, SDS)
  issues SPIFFE workload certificates (CA)
  -> pushes over ADS (aggregated gRPC stream)

data plane, ambient:   ztunnel (per-node L4) + waypoint (per-namespace/service L7)
data plane, sidecar:   Envoy sidecar injected per pod
```

**Ambient splits the proxy in two.** ztunnel is a per-node Rust DaemonSet that handles mTLS and L4 authorization for every pod on the node, tunnelling cross-node traffic over HBONE (HTTP/2 CONNECT). L7 features (HTTP routing, retries, L7 authorization) require a waypoint proxy, an Envoy Deployment scoped to a namespace or service, deployed only when needed. No per-pod overhead, and no pod restart to join the mesh.

**Sidecar injects an Envoy per pod.** A mutating admission webhook adds an `istio-init` container (which programs iptables to redirect all TCP through Envoy) and the `istio-proxy` Envoy sidecar. L7 features are always available, at roughly 50 MB of memory per pod and a pod restart to inject.

**Traffic splitting needs both objects.** A VirtualService sets the routing and weights; a DestinationRule defines the subsets those weights point at, plus connection-pool, load-balancer, and outlier-detection policy. One without the other silently does nothing useful.

**mTLS and authorization are configuration you apply.** PeerAuthentication sets the mTLS mode (STRICT, PERMISSIVE, DISABLE); AuthorizationPolicy is default-allow until a policy selects a workload, at which point that workload becomes default-deny for the listed action. These are the mechanics; the policy that decides them is `container-security`.

**Anti-patterns:** PERMISSIVE mTLS left on in production; a VirtualService with no matching DestinationRule subsets; no trace-header propagation, so spans are disconnected; a waypoint not deployed when L7 features are needed in ambient mode; mixing the Istio API and the Gateway API for the same traffic; an `istioctl` version that does not match the installed control plane.

## Architecture: ambient mode (GA since 1.24)

Ambient mesh is the sidecar-less architecture and the recommended approach for new deployments.

### Components

**ztunnel (L4 per-node proxy):**
- Rust-based DaemonSet, one pod per node.
- Handles mTLS encryption and decryption for all pod traffic on the node.
- Enforces L4 authorization policies.
- Emits L4 telemetry (connection-level metrics).
- Routes traffic via HBONE (HTTP/2 CONNECT tunnels) between nodes.
- No per-pod overhead; shared across all pods on the node.

**Waypoint proxy (L7 per-namespace or per-service):**
- Envoy-based Deployment, deployed only when L7 features are needed.
- Handles HTTP routing, retries, timeouts, circuit breaking.
- Enforces L7 authorization policies (method, path, headers).
- Emits L7 telemetry (request-level metrics).
- Scoped to a namespace or specific services.

### Enabling ambient mode

```bash
# Install Istio with ambient profile
istioctl install --set profile=ambient

# Enable ambient for a namespace (L4 only)
kubectl label namespace production istio.io/dataplane-mode=ambient

# Deploy waypoint for L7 features (optional)
istioctl waypoint apply --namespace production

# Verify
kubectl get pods -n istio-system
# istiod-xxxxx    Control plane
# ztunnel-xxxxx   DaemonSet on each node (istio-system)

kubectl get pods -n production
# waypoint-xxxxx  Waypoint proxy (if deployed)
```

### HBONE (HTTP-Based Overlay Network Environment)

ztunnel creates HTTP/2 CONNECT tunnels between nodes to carry mTLS-encrypted traffic:

```
Pod A (Node 1) --> ztunnel (Node 1) --HBONE tunnel (mTLS)--> ztunnel (Node 2) --> Pod B (Node 2)
```

HBONE is transparent to applications. It encapsulates TCP traffic in HTTP/2 CONNECT, providing mTLS without per-pod proxy overhead.

## Architecture: sidecar mode

The traditional Istio architecture, with a per-pod Envoy sidecar.

### Sidecar injection

```bash
# Auto-injection via namespace label
kubectl label namespace production istio-injection=enabled

# Manual injection
istioctl kube-inject -f deployment.yaml | kubectl apply -f -

# Verify sidecar is present
kubectl get pod mypod -o jsonpath='{.spec.containers[*].name}'
# Returns: app istio-proxy
```

### Traffic interception

An init container (`istio-init`) configures iptables rules that redirect all inbound and outbound TCP traffic through the Envoy sidecar:

```
App container (listens on :8080)
  |
  iptables REDIRECT --> Envoy sidecar (:15001 outbound, :15006 inbound)
  |
  Envoy applies routing, mTLS, policies --> destination
```

## Traffic management

### VirtualService

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
  - myapp.production.svc.cluster.local
  http:
  # Canary: 10% to v2
  - route:
    - destination:
        host: myapp
        subset: v1
      weight: 90
    - destination:
        host: myapp
        subset: v2
      weight: 10
    timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: "5xx,connect-failure"
  # Header-based routing
  - match:
    - headers:
        x-user-role:
          exact: beta-tester
    route:
    - destination:
        host: myapp
        subset: v2
```

### DestinationRule

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: myapp
spec:
  host: myapp
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 1000
    loadBalancer:
      simple: ROUND_ROBIN
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

### Gateway (Istio API)

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: main-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: myapp-tls-cert
    hosts:
    - "*.example.com"
  - port:
      number: 80
      name: http
      protocol: HTTP
    tls:
      httpsRedirect: true
    hosts:
    - "*.example.com"
```

### Kubernetes Gateway API

Istio supports the standard Kubernetes Gateway API, recommended for new deployments. Declaring the `Gateway` and `HTTPRoute` objects themselves is `kubernetes-ops`; Istio implements them when `gatewayClassName: istio`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: production
spec:
  gatewayClassName: istio
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      certificateRefs:
      - name: myapp-tls

---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
spec:
  parentRefs:
  - name: my-gateway
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

## Security

This section wires the mechanics. The programme that decides the policy (what should be STRICT, what a default-deny posture must allow back, how the zero-trust rollout is enforced) is `container-security`.

### mTLS (PeerAuthentication)

```yaml
# Strict mTLS for entire namespace
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT

# Permissive for specific service (migration period)
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: legacy-service
  namespace: production
spec:
  selector:
    matchLabels:
      app: legacy
  mtls:
    mode: PERMISSIVE
```

### AuthorizationPolicy

```yaml
# Default deny all
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: production
spec: {}

# Allow specific service-to-service communication
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend-to-api
  namespace: production
spec:
  selector:
    matchLabels:
      app: api
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/production/sa/frontend"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
```

### RequestAuthentication (JWT)

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: jwt-auth
spec:
  selector:
    matchLabels:
      app: api
  jwtRules:
  - issuer: "https://auth.example.com"
    jwksUri: "https://auth.example.com/.well-known/jwks.json"
    audiences: ["api.example.com"]
    forwardOriginalToken: true
```

RequestAuthentication only validates a token when one is present; pair it with an AuthorizationPolicy that requires `requestPrincipals` to actually reject unauthenticated requests.

## Observability

Istio emits the metrics and propagates the trace context. The pipeline that scrapes, stores, and renders them is `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing`.

### Built-in metrics

Istio proxies automatically emit Prometheus metrics:

| Metric | Type | Description |
|---|---|---|
| `istio_requests_total` | Counter | Total requests with labels (source, dest, method, code) |
| `istio_request_duration_milliseconds` | Histogram | Request latency distribution |
| `istio_tcp_sent_bytes_total` | Counter | TCP bytes sent |
| `istio_tcp_received_bytes_total` | Counter | TCP bytes received |
| `istio_tcp_connections_opened_total` | Counter | TCP connections opened |

### Dashboards

```bash
istioctl dashboard kiali         # Service topology + health
istioctl dashboard grafana       # Pre-built Istio dashboards
istioctl dashboard jaeger        # Distributed tracing
istioctl dashboard prometheus    # Raw metrics
```

### Distributed tracing

Applications must propagate these headers for trace correlation:
- `traceparent` (W3C TraceContext)
- `x-request-id`
- `x-b3-traceid`, `x-b3-spanid`, `x-b3-parentspanid`, `x-b3-sampled` (B3)

Without application-level header propagation, the mesh produces disconnected spans rather than a single trace.

## Troubleshooting

```bash
# Analyze configuration for issues
istioctl analyze -n production

# Check proxy sync status (all proxies should be SYNCED)
istioctl proxy-status

# View proxy configuration
istioctl proxy-config routes <pod-name> -n production
istioctl proxy-config clusters <pod-name> -n production
istioctl proxy-config endpoints <pod-name> -n production

# Check proxy logs
kubectl logs <pod-name> -c istio-proxy -n production

# Check ztunnel logs (ambient mode)
kubectl logs -l app=ztunnel -n istio-system --tail=100

# Debug connection issues (remember to reset the level afterwards)
istioctl proxy-config log <pod-name> --level debug

# Verify mTLS status
istioctl authn tls-check <pod-name> <destination-service>
```

When events, logs, and certificate windows do not line up, suspect clock skew: correlate on UTC per `utc-timestamps`, since a skewed node clock corrupts the timeline and can break certificate validity windows.

## Common pitfalls

1. **PERMISSIVE mode left in production**: after migration, switch to STRICT mTLS to prevent plaintext traffic.
2. **VirtualService without DestinationRule subsets**: traffic splitting requires both the VirtualService (weights) and the DestinationRule (subset definitions).
3. **Not propagating trace headers**: without application-level header propagation, distributed traces are disconnected spans.
4. **Sidecar resource waste**: each Envoy sidecar consumes around 50 MB of RAM. For large clusters, consider ambient mode.
5. **Gateway API versus Istio API confusion**: both work. The Gateway API is the Kubernetes standard; the Istio API (VirtualService/Gateway) offers more Istio-specific features. Pick one and be consistent.
6. **Waypoint not deployed for L7**: in ambient mode, L7 features (HTTP routing, L7 auth policies) require a waypoint proxy. Without it, only L4 mTLS and L4 auth work.
7. **istioctl version mismatch**: always use an `istioctl` version matching the installed Istio control plane version.

## Version notes

Guidance defaults to the latest stable when the version is unknown. Ambient mesh (ztunnel plus optional waypoint) went GA in 1.24; sidecar mode remains fully supported and is not deprecated. Boundaries that change behaviour:

- **1.24**: ambient mesh goes GA (ztunnel L4 plus waypoint L7); this is the recommended architecture for new deployments.
- **1.25**: production hardening of ambient (ztunnel stability, waypoint reliability, HBONE optimisation), migration tooling from sidecar to ambient, and Kubernetes Gateway API maturity (TCPRoute, TLSRoute, ReferenceGrant). See `references/versions/1.25.md`.
- **1.27**: multi-cluster ambient mesh lands in alpha (per-cluster ztunnel, cross-cluster HBONE over east-west gateways). It was subsequently promoted to Beta in 2026 (ambient multi-network multicluster), so on current minors treat multi-cluster ambient as Beta, not alpha.

Sidecar-to-ambient migration is the change most likely to affect an existing deployment; validate configuration with `istioctl analyze` and check proxy sync with `istioctl proxy-status` before and after.

## Reference router

Load the reference that matches the class:

- `references/architecture.md`: istiod internals (Pilot, Citadel, Galley), xDS/ADS, ztunnel and waypoint, HBONE, Envoy sidecar internals, installation profiles, certificate management, multi-cluster topologies. Read for "how does X work".
- `references/best-practices.md`: ambient-versus-sidecar selection, traffic-management patterns (canary, blue-green, mirroring, circuit breaking, timeouts and retries), security best practices and STRICT migration, egress control, observability setup, performance tuning, the troubleshooting checklist. Read for design and operations.
- `references/versions/1.25.md`: version-specific ambient stability, migration tooling, Gateway API maturity, and upgrade steps.

## Cross-references

- `service-mesh-selection`: the vendor-neutral umbrella that decides whether to run a mesh and which one; this skill operates Istio once that choice is made. Reciprocal reference.
- `linkerd-ops`, `consul-ops`: the sibling meshes. Same problem space, different implementation; do not cross the manifests.
- `kubernetes-ops`: every Kubernetes operation, and declaring the `Gateway`, `Service`, or `NetworkPolicy` objects the mesh consumes. Istio runs on top; the cluster underneath is there.
- `container-security`: the security programme this skill's PeerAuthentication and AuthorizationPolicy mechanics serve, zero-trust policy, admission enforcement, image scanning, supply chain, runtime protection. Wire the mesh knobs here; take the policy from there.
- `load-balancer-selection`, `nginx-load-balancing`, `haproxy-load-balancing`, `aws-load-balancing`: choosing and implementing the ingress or L4/L7 balancer that fronts an Istio gateway.
- `cert-manager`, `lets-encrypt`: in-mesh and service certificates and public issuance; istiod's CA integrates with an external CA through these.
- `hashicorp-vault-ops`, `secrets-hygiene`: the central secret store and the handling discipline for any token or credential, including a Vault-backed mesh CA.
- `prometheus-configuration`, `grafana-dashboards`, `distributed-tracing`: the metrics, dashboards, and tracing pipeline that consume the Istio metrics and trace headers.
- `cicd-platforms-ops`, `gh-actions-ci`: GitOps and the CD pipeline that applies the mesh manifests.
- `terraform-iac-ops`: provisioning the cluster and installing Istio as code; operating the mesh is here.
- `utc-timestamps`: proxy logs, mesh events, and certificate windows correlate on UTC; a skewed node clock corrupts the timeline and can break certificate validity.

## Red flags

- About to leave PERMISSIVE mTLS on in production after a migration, allowing plaintext traffic back in.
- About to ship a traffic split with a VirtualService but no matching DestinationRule subsets, so the weights point at nothing.
- About to enable ambient on a namespace that needs L7 routing or L7 authorization without deploying a waypoint.
- About to mix the Istio API and the Kubernetes Gateway API for the same traffic path.
- About to run `istioctl` at a version that does not match the installed control plane.
- About to write an AuthorizationPolicy and assume RequestAuthentication alone rejects unauthenticated requests (it only validates a token when present).
- About to upgrade or migrate without `istioctl analyze` and an export of the current Istio CRDs.
- About to treat the mesh mTLS as the whole security programme, rather than the mechanics that `container-security` policy drives.

## Bottom line

Istio is istiod (the merged control plane) pushing Envoy xDS config to a data plane that is either per-node ztunnel plus optional waypoint (ambient, GA since 1.24, the default for new deployments) or a per-pod Envoy sidecar. Prefer ambient for new work: L4 mTLS with no per-pod overhead and no restart, waypoint added only where L7 features are needed. Split traffic with a VirtualService and a matching DestinationRule together, never one alone. Apply STRICT mTLS once every workload is meshed, default-deny with AuthorizationPolicy and allow back explicitly, and pair RequestAuthentication with an authorization rule. Emit the metrics and propagate the trace headers here, and let the observability pipeline consume them. Bring the mesh choice from `service-mesh-selection` and the security policy from `container-security`; keep Kubernetes operations, ingress balancers, certificates, secrets, observability, and CD in their proper homes.
