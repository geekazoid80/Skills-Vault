---
name: consul-ops
description: "Operating HashiCorp Consul service mesh (Consul Connect) day to day across Kubernetes, VMs, and bare metal: the Consul server cluster (Raft consensus, service catalog, KV store), Consul Dataplane and the Envoy sidecar, service discovery and the catalog, intentions (L4 and L7 service-to-service authorisation), L7 traffic management (ServiceRouter, ServiceSplitter, ServiceResolver, ServiceDefaults), mesh, ingress, and terminating gateways, WAN federation and multi-datacentre, transparent proxy, ACLs, Vault CA integration, and Helm deployment. WHEN: \"Consul\", \"Consul Connect\", \"Consul mesh\", \"Consul service mesh\", \"intentions\", \"ServiceRouter\", \"ServiceSplitter\", \"ServiceResolver\", \"Consul Dataplane\", \"mesh gateway\", \"Consul on Kubernetes\", \"WAN federation\", \"transparent proxy\", \"Consul on VMs\". Do NOT use for: whether to adopt a mesh or which mesh to choose (service-mesh-selection); the sibling meshes (istio-ops, linkerd-ops); Kubernetes operation and Service, Gateway, or NetworkPolicy declaration (kubernetes-ops); the security programme, zero-trust policy, admission, image scanning, or supply chain (container-security); ingress and L4/L7 load balancing (load-balancer-selection, nginx-load-balancing, haproxy-load-balancing, aws-load-balancing); certificates (cert-manager, lets-encrypt); secret and KV management discipline, dynamic secrets, and PKI issuance (hashicorp-vault-ops, secrets-hygiene); observability (prometheus-configuration, grafana-dashboards, distributed-tracing); CI/CD and GitOps (cicd-platforms-ops, gh-actions-ci); cluster and mesh provisioning as code (terraform-iac-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Consul operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: consul-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating HashiCorp Consul's service mesh (Consul Connect) once Consul is the chosen mesh: reasoning about the server cluster and the data plane, enforcing service-to-service access with intentions, shaping L7 traffic with ServiceRouter, ServiceSplitter, and ServiceResolver, wiring mesh, ingress, and terminating gateways, federating across datacentres, and deploying with Helm. It assumes Consul Connect has been chosen; whether to run a mesh at all and which mesh to pick lives in `service-mesh-selection`.

Consul's differentiator is reach. Unlike Istio and Linkerd, which are Kubernetes-native, Consul runs a single mesh across Kubernetes, virtual machines, bare metal, and cloud-native services at once, which makes it the usual choice for hybrid and multi-platform estates. That breadth shapes everything below: the same catalog, intentions, and gateways serve pods and long-lived VMs together.

## When to use

- Enforcing access: writing L4 or L7 intentions, setting the default-deny posture, reasoning about intention precedence, checking why a connection is denied.
- Shaping L7 traffic: ServiceRouter path and header routing, ServiceSplitter weighted rollouts, ServiceResolver subsets and failover, the ServiceDefaults protocol that unlocks all of it.
- Wiring gateways: mesh gateways for cross-datacentre mTLS, ingress gateways for external clients, terminating gateways to reach services outside the mesh.
- Federating: WAN federation across datacentres, mesh-gateway modes, cross-datacentre service discovery and failover.
- Deploying and operating: the Helm chart and its values, CRD-based configuration, transparent proxy on Kubernetes, VM and bare-metal enrolment into the same mesh.
- Running the control plane: the Consul server cluster (Raft, catalog, KV, built-in CA), ACL bootstrap and tokens, Vault CA integration.
- Troubleshooting: an intention that will not take effect, L7 config that is silently L4, a mesh-gateway bottleneck, a certificate that will not rotate, a service missing from the catalog.

## When not to use

- **Mesh selection**: whether a mesh is warranted and Consul versus Istio versus Linkerd versus ambient is `service-mesh-selection`. That umbrella decides; this skill operates Consul once chosen.
- **Sibling meshes**: Istio operation (VirtualService, DestinationRule, Envoy, ambient) is `istio-ops`; Linkerd operation (its Rust micro-proxy, service profiles) is `linkerd-ops`. This skill is Consul-specific.
- **Kubernetes operation**: declaring a Service, Gateway, Ingress, or NetworkPolicy, running Deployments and StatefulSets, and general cluster operation are `kubernetes-ops`. Consul rides on Kubernetes here; the cluster underneath is there.
- **Security programme**: the zero-trust policy, admission control, image scanning gates, supply-chain integrity, and runtime protection are `container-security`. This skill wires the mesh mechanics (intentions, mTLS, gateway config); the programme that decides how to use them for security is there.
- **Ingress and load balancing**: choosing an ingress or L4/L7 balancer is `load-balancer-selection`; the implementations are `nginx-load-balancing`, `haproxy-load-balancing`, and `aws-load-balancing`. A Consul ingress gateway fronts the mesh; the balancer choice in front of it is there.
- **Certificates**: general in-cluster and public certificate issuance is `cert-manager` and `lets-encrypt`. Consul's built-in Connect CA and its Vault CA integration are here; the wider certificate estate is there.
- **Secret and KV management**: Consul is also a KV and service-discovery store, but the discipline for managing secrets, dynamic secrets, and PKI issuance is `hashicorp-vault-ops`, and the handling rules for any token or credential are `secrets-hygiene`. Consul's KV as mesh configuration is here; secret material belongs there.
- **Observability**: the metrics, dashboards, and tracing pipeline is `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing`. Consul and Envoy expose the metrics here; the pipeline that scrapes them is there.
- **CI/CD and GitOps**: delivering CRDs and Helm values through a pipeline is `cicd-platforms-ops` and `gh-actions-ci`. The manifest is here; the delivery mechanism is there.
- **Provisioning as code**: standing up the cluster, VMs, and Consul itself with Terraform is `terraform-iac-ops`. Operating the mesh is here; declaring the infrastructure that creates it is there.

## Classify the request first

Every request resolves to one of these, which determines the depth to load. Also identify the platform early: Kubernetes, VMs, bare metal, or a mix. The deployment model differs sharply between them, so this changes the answer more than it would for a Kubernetes-only mesh.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | server cluster and Raft, Dataplane and Envoy wiring, Connect CA hierarchy, intention evaluation flow, the L7 traffic chain, gateway internals, transparent-proxy iptables | `references/architecture.md` |
| Access control | L4 and L7 intentions, precedence, default-deny, `consul intention check` | inline below, with the evaluation flow in `references/architecture.md` |
| Traffic management | ServiceRouter, ServiceSplitter, ServiceResolver, ServiceDefaults protocol, canary and subset rollout | inline below, with the full chain in `references/architecture.md` |
| Deployment | Helm chart and values, CRDs, connect-inject, transparent proxy, ACL bootstrap, Vault CA | inline below |
| Multi-platform / multi-DC | VM enrolment, catalog sync, hybrid mesh, WAN federation, mesh-gateway modes, cross-DC discovery | inline below, with gateway internals in `references/architecture.md` |
| Troubleshooting | intention not taking effect, L7 config behaving as L4, mesh-gateway bottleneck, certificate not rotating, missing catalog entry | inline below |

## Core model (condensed)

**A server cluster is the single source of truth; a lightweight sidecar rides each service.** A Raft-consensus cluster of 3 or 5 Consul servers holds the service catalog, the intentions, the KV store, and the Connect CA. Alongside every service instance (pod or VM) runs Consul Dataplane, a lightweight process that talks to the servers over gRPC, translates their configuration into Envoy xDS, and manages a local Envoy proxy. Envoy does the actual work: mTLS, intention enforcement, and L7 routing.

```
Consul Server Cluster (3 or 5 nodes, Raft consensus)
  |-- Service Catalog: registry of all services and their health
  |-- Intentions: access control rules (L4/L7)
  |-- Configuration: centralised KV store, ServiceRouter, ServiceSplitter
  |-- Certificate Authority: built-in CA or Vault integration
  |-- Service Discovery: DNS and HTTP API
  |
  Per Service Instance (Kubernetes or VM):
    Consul Dataplane (lightweight sidecar process)
    |-- Manages local Envoy proxy configuration
    |-- Talks to Consul servers via xDS and gRPC
    |-- No full Consul client agent needed (since 1.14+)
    |
    Envoy Proxy (sidecar)
    |-- Enforces intentions (L4 and L7)
    |-- Handles mTLS (certificate exchange, encryption)
    |-- Reports telemetry (Prometheus metrics, access logs)
    |-- Applies L7 routing rules
```

**Consul Dataplane replaced the client-agent model.** The legacy model ran a full Consul agent per node; Dataplane (Consul 1.14+) runs a small process per service that speaks gRPC to the servers and needs no gossip.

| Aspect | Client Agent (Legacy) | Consul Dataplane |
|---|---|---|
| Architecture | Full Consul agent per node | Lightweight process per service |
| Resource usage | High (gossip, health checks, cache) | Low (gRPC to servers only) |
| Networking | Agent port exposure (8301, 8500, etc.) | gRPC only |
| Kubernetes | DaemonSet of agents | Sidecar per pod |
| Startup time | Slower (gossip join, sync) | Fast (direct gRPC) |
| Introduced | Original | Consul 1.14+ |

Always use Consul Dataplane for new deployments; the client-agent model is legacy.

**Anti-patterns:** shipping L7 intentions or routing without setting `protocol: http` in ServiceDefaults, so everything silently falls back to L4 TCP; running production without ACLs; under-provisioning a mesh gateway that carries all cross-DC traffic; leaving external services unreachable because no terminating gateway or ServiceEntry exists; starving the Raft servers of consistent CPU or disk, so consensus stalls.

## Consul server cluster and Raft

Consul servers form a Raft cluster (3 or 5 nodes recommended). The leader handles all writes (catalog mutations, KV writes, intention changes, ACL token creation) and replicates the Raft log to followers; followers serve reads. Consistency modes trade freshness for speed: `default` (leader-served, consistent), `stale` (any server, eventually consistent, faster), and `consistent` (leader verifies leadership first, strongest). The server process exposes HTTP API on 8500, gRPC (xDS, Dataplane, peering) on 8502, DNS on 8600, Serf gossip on 8301 (LAN) and 8302 (WAN), and Raft on 8300. Full port and subsystem detail is in `references/architecture.md`.

Raft consensus needs consistent performance: use SSDs and adequate CPU and memory for server pods, and do not co-locate them with noisy neighbours.

## Consul Dataplane and Envoy

Each service instance runs Consul Dataplane, a lightweight Go process, next to the unmodified application. It bootstraps and manages the local Envoy proxy: it watches the servers over gRPC for configuration changes, requests the service instance's mTLS certificate, upstream endpoints, intention rules, and L7 routing, translates all of that into Envoy xDS, and hot-reloads Envoy on change with no restart. Envoy terminates and originates mTLS, enforces intentions at L4 and L7, applies ServiceRouter rules, load-balances, health-checks, and emits Prometheus metrics. The per-service sidecar model and the full bootstrap flow are in `references/architecture.md`.

## Service discovery and the catalog

The catalog is the registry of every service and its health, queryable by DNS and HTTP:

```bash
# DNS query for a service in the local datacentre
dig @consul-dns api.service.consul

# DNS query for a service in another datacentre
dig @consul-dns api.service.dc2.consul

# HTTP API, health of a service in another datacentre
curl http://consul:8500/v1/health/service/api?dc=dc2
```

Service records follow `<service>.service.consul` and `<service>.service.<dc>.consul`; SRV records carry port information. On Kubernetes with transparent proxy, applications use ordinary Kubernetes DNS and the mesh intercepts transparently (see below).

## Intentions (access control)

Intentions are Consul's service-to-service authorisation rules.

### L4 intentions (connection-level)

```bash
# CLI: allow frontend to call api
consul intention create -allow frontend api

# CLI: default deny all
consul intention create -deny '*' '*'

# List intentions
consul intention list

# Check whether one service may call another
consul intention check frontend api
```

### L7 intentions (request-level)

```yaml
# CRD: L7 intention with HTTP permissions
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: api
  namespace: production
spec:
  destination:
    name: api
  sources:
  - name: frontend
    permissions:
    - action: allow
      http:
        methods: ["GET"]
        pathPrefix: /api/v1/
    - action: allow
      http:
        methods: ["POST"]
        pathPrefix: /api/v1/orders
    - action: deny       # deny everything else from frontend

  - name: admin-service
    action: allow         # full access for admin

  - name: '*'
    action: deny          # deny all other services
```

**L4 versus L7**: L4 intentions evaluate per connection (allow or deny the TCP connection); L7 intentions evaluate per request (allow or deny on HTTP method, path, or headers). L7 requires `protocol: http` in ServiceDefaults; without it everything is L4 TCP.

### Intention precedence

Most specific wins:

1. Exact source and exact destination (most specific).
2. Exact source and wildcard destination.
3. Wildcard source and exact destination.
4. Wildcard source and wildcard destination (least specific, the place to set default-deny).

The per-connection and per-request evaluation flows, and how intention changes propagate to Envoy through xDS (typically under 5 seconds, no restart), are in `references/architecture.md`.

## L7 traffic management

### ServiceDefaults (protocol configuration)

L7 features do nothing until the protocol is declared. This is the single most common Consul mistake, so set it first.

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: api
spec:
  protocol: http          # http | grpc | tcp | http2
  meshGateway:
    mode: local           # local | remote | none
  expose:
    checks: true          # expose health check endpoints
  maxInboundConnections: 1000
```

### ServiceRouter (path- and header-based routing)

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceRouter
metadata:
  name: api
spec:
  routes:
  - match:
      http:
        pathPrefix: /api/v2
    destination:
      service: api-v2
      requestTimeout: 10s
      numRetries: 3
      retryOnStatusCodes: [503]

  - match:
      http:
        header:
        - name: x-canary
          exact: "true"
    destination:
      service: api-canary

  # Default route (no match = catch-all)
  - destination:
      service: api
```

### ServiceSplitter (weighted traffic splitting)

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceSplitter
metadata:
  name: api
spec:
  splits:
  - weight: 90
    service: api
    serviceSubset: v1
  - weight: 10
    service: api
    serviceSubset: v2
```

### ServiceResolver (subsets and failover)

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceResolver
metadata:
  name: api
spec:
  defaultSubset: v1
  subsets:
    v1:
      filter: "Service.Meta.version == v1"
    v2:
      filter: "Service.Meta.version == v2"
  failover:
    '*':
      datacenters: ["dc2", "dc3"]
  connectTimeout: 5s
  requestTimeout: 10s
```

### The L7 traffic chain

The three resources compose in order: router picks the service, splitter distributes by weight, resolver selects the subset and handles failover.

```
Request --> ServiceRouter (path/header matching)
              |
              v
           ServiceSplitter (weight-based distribution)
              |
              v
           ServiceResolver (subset selection, failover)
              |
              v
           Endpoint (actual service instance)
```

A worked end-to-end example (a GET with a canary header routed, split, resolved, and load-balanced) is in `references/architecture.md`.

## Gateways, WAN federation, and multi-datacentre

Consul natively federates across datacentres. The three gateway types serve distinct jobs:

| Gateway | Purpose | Use case |
|---|---|---|
| Mesh gateway | Cross-datacentre service mesh traffic | Multi-DC communication |
| Ingress gateway | Expose mesh services to external clients | External access without a sidecar |
| Terminating gateway | Let meshed services reach external services | Database or API outside the mesh |

### WAN federation

```yaml
# consul-values.yaml for a federated (secondary) cluster
global:
  datacenter: dc2
  tls:
    enabled: true
    caCert:
      secretName: consul-federation    # shared CA across DCs
  federation:
    enabled: true
    primaryDatacenter: dc1

server:
  extraVolumes:
  - type: secret
    name: consul-federation
    load: true
```

### Mesh gateways

Mesh gateways route mTLS traffic between datacentres, inspecting the SNI of the connection and routing on the destination service name without inspecting the payload (L4 only). Traffic stays encrypted end to end.

```
DC1:  Service A --> Envoy sidecar --> Mesh Gateway (DC1)
                                          |
                                    (mTLS over WAN)
                                          |
DC2:                                 Mesh Gateway (DC2) --> Envoy sidecar --> Service B
```

Gateway modes:

- **local**: traffic exits through the local datacentre's mesh gateway (default, most common).
- **remote**: traffic enters through the remote datacentre's mesh gateway (when the remote DC controls ingress).
- **none**: direct pod-to-pod, which requires a flat network between DCs.

### Terminating gateway

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: TerminatingGateway
metadata:
  name: terminating-gateway
spec:
  services:
  - name: external-db
    caFile: /consul/tls/ca.pem
  - name: external-api
```

Mesh gateways carry all cross-DC traffic, so size them for the load; under-provisioning causes bottlenecks. The full gateway internals (SNI routing, ingress gateway listeners, terminating-gateway TLS origination) are in `references/architecture.md`.

## Transparent proxy (Kubernetes)

Transparent proxy captures all TCP traffic from pods via iptables and routes it through the Envoy sidecar with no application changes:

```yaml
connectInject:
  transparentProxy:
    defaultEnabled: true
```

Benefits:

- No service URL changes; applications use Kubernetes DNS as normal.
- All traffic is automatically encrypted with mTLS.
- Intentions are enforced on every connection, not only explicitly configured ones.

With transparent proxy, expose health-check endpoints via `expose.checks: true` in ServiceDefaults, and route external (non-mesh) destinations through a terminating gateway or an explicit ServiceEntry. The iptables redirect rules are in `references/architecture.md`.

## Deployment (Kubernetes)

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install consul hashicorp/consul \
  --namespace consul \
  --create-namespace \
  --values consul-values.yaml
```

### Production Helm values

```yaml
global:
  name: consul
  datacenter: dc1
  image: hashicorp/consul:1.22
  tls:
    enabled: true
    enableAutoEncrypt: true
  acls:
    manageSystemACLs: true
  metrics:
    enabled: true
    enableAgentMetrics: true
    enableGatewayMetrics: true

server:
  replicas: 3
  storage: 20Gi
  storageClass: fast-ssd
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi

connectInject:
  enabled: true
  default: true              # auto-inject sidecars into all pods
  transparentProxy:
    defaultEnabled: true     # capture all traffic via iptables
  metrics:
    defaultEnabled: true
    defaultPrometheusScrapePort: 20200
  consulNamespaces:
    mirrorK8S: true          # mirror K8s namespaces to Consul

meshGateway:
  enabled: true
  replicas: 2
  service:
    type: LoadBalancer
  wanAddress:
    source: Service

ingressGateway:
  enabled: true
  defaults:
    replicas: 2
    service:
      type: LoadBalancer

terminatingGateway:
  enabled: true
  defaults:
    replicas: 1

ui:
  enabled: true
  service:
    type: ClusterIP

dns:
  enabled: true
```

## ACLs and Vault CA

Production requires ACLs. Set `acls.manageSystemACLs: true` so the chart bootstraps and manages the system tokens automatically; without it, tokens are unmanaged and the mesh is effectively open.

Consul ships a built-in Connect CA (a root CA, a per-datacentre intermediate, and short-lived leaf certificates, EC P-256, auto-renewed between 60% and 90% of their TTL). For a shared CA across datacentres, HSM-backed root keys, or audit logging of certificate operations, back Connect with Vault instead:

```yaml
# Use Vault as the Connect CA instead of the built-in CA
global:
  secretsBackend:
    vault:
      enabled: true
      consulServerRole: consul-server
      consulClientRole: consul-client
      connectCA:
        address: https://vault.example.com
        rootPKIPath: connect-root
        intermediatePKIPath: connect-intermediate
        authMethodPath: kubernetes
```

The Vault CA config is a mesh-CA wiring decision; operating Vault itself, its dynamic secrets, and its PKI engine is `hashicorp-vault-ops`, and secret-handling discipline is `secrets-hygiene`. The CA hierarchy and rotation detail are in `references/architecture.md`.

## Multi-platform (Kubernetes, VMs, bare metal)

Consul's reach is the reason to choose it. The same catalog, intentions, and gateways serve services on Kubernetes and on long-lived VMs or bare-metal hosts at once. On Kubernetes the connect-inject webhook adds the Dataplane and Envoy sidecars and the iptables init container automatically; on a VM the service is enrolled into the catalog and runs Dataplane plus Envoy as host processes. Intentions, ServiceRouter, and gateways then apply uniformly regardless of where a service runs, which is what makes Consul the usual pick for hybrid estates migrating from VMs to Kubernetes. Keep Kubernetes and Consul namespaces aligned with `consulNamespaces.mirrorK8S: true`.

## Troubleshooting

- **L7 config behaving as L4** (routing, splitting, or L7 intentions ignored): the service is missing `protocol: http` in ServiceDefaults. This is the first thing to check for any L7 symptom.
- **Intention not taking effect**: confirm the intention exists and its precedence (a more specific intention wins), check the ACL default policy for the no-match case, and verify propagation with `consul intention check <src> <dst>`; changes reach Envoy over xDS in seconds, so a persistent miss is a config or precedence issue, not lag.
- **External service unreachable under transparent proxy**: non-mesh destinations need a terminating gateway or an explicit ServiceEntry; transparent proxy alone will not reach them.
- **Mesh-gateway bottleneck**: the gateway carries all cross-DC traffic; watch its latency and connection metrics and scale replicas before it saturates.
- **Certificate not rotating**: check the Connect CA (built-in or Vault) health and the leaf TTL; leaves auto-renew between 60% and 90% of their TTL, so a stuck rotation points at the CA path.
- **Missing catalog entry**: confirm the service registered (connect-inject on Kubernetes, or Dataplane enrolment on a VM) and that health checks pass; an unhealthy instance is filtered from discovery.

Observe the mesh through Prometheus (Envoy request and error metrics, Dataplane xDS sync and certificate rotation, server Raft commit time, gateway cross-DC counters) and the built-in Consul UI (catalog with health, intention allow/deny graph, KV browser, service topology, ACL management). The metric sources and alerting examples are in `references/architecture.md`; the pipeline that scrapes them is `prometheus-configuration` and `grafana-dashboards`.

## Common pitfalls

1. **Forgetting the ServiceDefaults protocol**: L7 intentions and routing require `protocol: http`; without it everything is L4 TCP.
2. **Running without ACLs**: production needs them; set `manageSystemACLs: true` for automatic bootstrap.
3. **Under-sizing mesh gateways**: they handle all cross-DC traffic, so under-provisioning causes bottlenecks.
4. **Transparent proxy and external services**: services outside the mesh need a terminating gateway or an explicit ServiceEntry.
5. **Starving Consul servers**: Raft consensus needs consistent performance; use SSDs and adequate CPU and memory.
6. **Namespace drift**: enable `consulNamespaces.mirrorK8S` to keep Kubernetes and Consul namespaces aligned.
7. **Health-check ports under transparent proxy**: expose health-check endpoints with `expose.checks: true` in ServiceDefaults.

## Version notes

- **Consul Dataplane** is the default and recommended data-plane model since Consul 1.14; the client-agent model is legacy and should not be used for new deployments.
- **L7 features are gated on the ServiceDefaults protocol**, not on a Consul version: `protocol: http` (or `grpc`/`http2`) must be set for ServiceRouter, ServiceSplitter, and L7 intentions to apply.
- **Connect leaf certificates** default to a 72h TTL (`LeafCertTTL`, configurable between 1h and 1 year) and auto-renew between 60% and 90% of their lifetime; the CA (built-in or Vault) is configurable.
- **Mesh config CRDs** are served under `consul.hashicorp.com/v1alpha1` (ServiceDefaults, ServiceRouter, ServiceSplitter, ServiceResolver, ServiceIntentions, TerminatingGateway, and the rest); there is no `v1beta` promotion as of 2026, so keep the `v1alpha1` group.
- Pin the `global.image` (for example `hashicorp/consul:1.22` above) to a known-good release and read the release notes before a minor bump, since CRD schemas and Helm value keys evolve across minors. Current stable is the 1.22.x line; a re-versioned 2.0.x line began in 2026 (under HashiCorp's IBM-era support model), so verify consul-k8s Helm-chart compatibility before adopting it.

## Reference router

- `references/architecture.md`: the server cluster and Raft, the Dataplane and Envoy sidecar model and bootstrap flow, the Connect CA hierarchy and Vault CA integration, L4 and L7 intention evaluation, the full ServiceRouter/Splitter/Resolver chain, mesh/ingress/terminating gateway internals, transparent-proxy iptables, and monitoring metrics. Read for "how does X work" and for deep implementation.

## Cross-references

- `service-mesh-selection`: the vendor-neutral umbrella that decides whether to run a mesh and Consul versus Istio versus Linkerd versus ambient; this skill operates Consul once that choice is made. Reciprocal reference.
- `istio-ops`, `linkerd-ops`: the sibling meshes. Consul is the multi-platform choice (Kubernetes plus VMs plus bare metal); those are Kubernetes-native.
- `kubernetes-ops`: operating the cluster Consul rides on, and declaring Services, Gateways, Ingress, and NetworkPolicy. The mesh mechanics are here; the Kubernetes objects are there.
- `container-security`: the security programme this skill's intentions, mTLS, and gateway mechanics serve, zero-trust policy, admission control, image scanning, supply chain, runtime protection. Wire the mesh knobs here; take the policy from there.
- `load-balancer-selection`, `nginx-load-balancing`, `haproxy-load-balancing`, `aws-load-balancing`: choosing and implementing the ingress or L4/L7 balancer in front of a Consul ingress gateway.
- `cert-manager`, `lets-encrypt`: the wider certificate estate; Consul's built-in Connect CA and Vault CA integration are here.
- `hashicorp-vault-ops`, `secrets-hygiene`: operating Vault (dynamic secrets, PKI issuance) and the handling discipline for any credential; Consul's KV and Vault CA wiring are here, secret material lives there.
- `prometheus-configuration`, `grafana-dashboards`, `distributed-tracing`: the metrics, dashboards, and tracing pipeline that consumes the Consul, Dataplane, and Envoy endpoints.
- `cicd-platforms-ops`, `gh-actions-ci`: GitOps and the CD pipeline that delivers CRDs and Helm values to the cluster.
- `terraform-iac-ops`: provisioning the cluster, VMs, and Consul as code; operating the mesh is here.
- `utc-timestamps`: intention changes, catalog health, and certificate validity windows correlate on UTC; a skewed clock corrupts the timeline and can break mTLS certificate validity.

## Red flags

- About to ship L7 intentions or routing without setting `protocol: http` in ServiceDefaults, so it silently falls back to L4 TCP.
- About to run a production mesh without ACLs (`manageSystemACLs: true`).
- About to size a mesh gateway for steady state while it carries all cross-DC traffic.
- About to enable transparent proxy but leave external services with no terminating gateway or ServiceEntry.
- About to co-locate or starve Consul servers so Raft consensus loses consistent performance.
- About to store real secret material in Consul KV instead of Vault, or hard-code an ACL token instead of sourcing it from the secret store.
- About to add or change an intention without checking precedence, so a broader rule keeps overriding it.
- About to skip more than one Consul minor version, or bump the image without reading the CRD and Helm value changes in the release notes.

## Bottom line

Consul Connect is a Raft-consensus server cluster holding the catalog, intentions, KV, and CA, with a lightweight Consul Dataplane and an Envoy sidecar beside every service on Kubernetes, VMs, or bare metal alike. That multi-platform reach is the reason to choose it. Enforce access with intentions (default-deny at the wildcard, most-specific wins), and remember that L7 intentions and all L7 routing need `protocol: http` in ServiceDefaults first. Shape traffic with the ServiceRouter, ServiceSplitter, ServiceResolver chain; federate across datacentres with WAN federation and correctly sized mesh gateways; reach outside the mesh through terminating gateways. Run ACLs in production, back the CA with Vault where a shared or HSM-protected root matters, and keep real secrets in Vault, not Consul KV. Bring the mesh choice from `service-mesh-selection` and the security programme from `container-security`; keep the cluster, certificates, secrets, ingress, observability, and CD in their proper homes.
