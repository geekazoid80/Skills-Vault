# Platform selection and migration

How to choose between the major load-balancing platforms, how they map onto Kubernetes, and how to migrate from hardware to software. The per-vendor skills (`haproxy-load-balancing`, `nginx-load-balancing`, `aws-load-balancing`) own configuration; this is the selection reasoning.

## Platform profiles

### F5 BIG-IP (routing context; deep depth not yet in this vault)

Full-proxy ADC, hardware and virtual. Deepest single-box feature set (LTM, GTM/DNS, ASM/WAF, APM, AFM), a custom high-performance data plane (TMM), unlimited programmatic control via iRules, enterprise HA with traffic groups and config sync, built-in GSLB (GTM), and full automation via iControl REST. Trade-offs: highest cost, complex per-module/per-throughput licensing, steep learning curve, long hardware procurement. Best for enterprise data centres needing the full ADC feature set and existing F5 expertise.

### NGINX (see `nginx-load-balancing`)

Software reverse proxy and load balancer (OSS and commercial Plus). Extremely efficient event-driven architecture, the leading Kubernetes ingress, configuration-as-code that fits DevOps/GitOps, and a low resource footprint. NGINX Plus adds active health checks, session persistence, a live API, and JWT auth. Trade-offs: OSS lacks active health checks and persistence; no built-in GSLB or OSS WAF; fewer L4 features than a dedicated L4 balancer. Best for cloud-native and Kubernetes environments, API gateways, and reverse proxying.

### HAProxy (see `haproxy-load-balancing`)

Software TCP/HTTP load balancer (OSS and Enterprise). Exceptional raw performance (highest connections/second of the software options), a powerful ACL system, stick tables for stateful rate limiting and abuse detection, a runtime API for live changes, and zero-downtime reloads. Trade-offs: no built-in caching or OSS WAF, no native GSLB, less common than NGINX in Kubernetes. Best for high-performance TCP/HTTP balancing, rate limiting, and teams that value operational transparency.

### Citrix NetScaler (routing context)

Deep ADC (MPX/VPX/CPX/SDX/BLX form factors) with AppExpert policy engine, content switching, built-in GSLB (MEP), SSL offload, AppFW, and the NITRO API. A strong hardware/virtual ADC alternative to F5; deep depth not yet in this vault.

### Envoy (routing context)

Extensible L7 proxy and the core data plane of service meshes (Istio, Envoy Gateway). Dynamic xDS configuration, rich filter chains, ring-hash and maglev balancing, and outlier detection. The right tool for east-west service-to-service traffic; deep depth not yet in this vault.

### Cloud-native load balancers

AWS ALB (L7) / NLB (L4) / GWLB, Azure Application Gateway, and equivalents: managed, consumption-priced, and integrated with the cloud's WAF and DNS (Route 53, Traffic Manager). Lowest operational burden inside a single cloud. AWS depth lives in `aws-load-balancing`.

## Decision matrix

| Factor | F5 BIG-IP | NGINX | HAProxy | NetScaler | Envoy | AWS ALB/NLB | Azure App GW |
|---|---|---|---|---|---|---|---|
| L7 performance | High (TMM) | Very high | Highest | High (HW ASICs) | Very high | Managed | Managed |
| Feature breadth | Deepest | Moderate (Plus) | Moderate | Deep (ADC) | Extensible (filters) | AWS-integrated | Azure-integrated |
| Kubernetes native | BIG-IP CIS | NGINX Ingress | HAProxy Ingress | CPX / CIC | Envoy Gateway | ALB Controller | AGIC |
| GSLB | Built-in (GTM) | No | No | Built-in (MEP) | No | Route 53 | Traffic Manager |
| WAF | Built-in (ASM) | App Protect (Plus) | Enterprise only | AppFW | ext_authz filter | AWS WAF | WAF v2 (built-in) |
| Cost | Highest | Medium (OSS free) | Low (OSS free) | High (licence) | Free (OSS) | Consumption | Consumption |
| Service mesh | No | No | No | CPX sidecar | Core data plane | No | No |
| Configuration model | Object (TMSH) | Declarative | Declarative | Object (CLI/API) | xDS / YAML | Console / IaC | Console / IaC |

## Choosing: a short method

1. **Where does it run?** Single cloud -> prefer the cloud-native LB. Kubernetes -> NGINX/HAProxy ingress or a mesh. On-prem data centre -> hardware ADC or software on VMs.
2. **What traffic?** Raw TCP/UDP or extreme throughput -> L4 (NLB, HAProxy in TCP mode). HTTP with content routing and TLS offload -> L7 (ALB, NGINX, HAProxy in HTTP mode).
3. **Which features are non-negotiable?** Built-in GSLB or deep WAF in one box -> hardware ADC. Configuration-as-code and a small footprint -> software.
4. **North-south or east-west?** External ingress -> ingress controller or cloud LB. Service-to-service -> a service mesh (Envoy).
5. **Operating model and team skill?** Match the platform to how the team already works (GitOps, console, appliance) rather than to its peak feature list.

## Kubernetes load balancing

| Solution | Backing technology | Best for |
|---|---|---|
| NGINX Ingress Controller | NGINX / NGINX Plus | General-purpose L7 ingress, CRD-based routing |
| HAProxy Ingress | HAProxy | High-performance TCP/HTTP ingress |
| F5 BIG-IP CIS | F5 BIG-IP | Enterprise environments with existing F5 |
| Cloud LB (ALB/NLB) | Cloud provider | Simple cloud-native deployments |
| Istio / Envoy | Envoy proxy | Service mesh with advanced traffic management |

**Ingress vs service mesh.** Ingress handles north-south traffic (external to cluster) for public-facing services. A service mesh handles east-west traffic (service-to-service) for microservice communication, mTLS, and observability. Many production clusters run both: ingress at the edge, mesh inside.

## Hardware-to-software migration

1. **Inventory** every virtual server, pool, health check, persistence profile, iRule/ACL, and TLS profile on the current platform.
2. **Map features to the target.** Not every hardware feature has a direct software equivalent; identify the gaps early.
3. **Baseline performance** (throughput, connections/second, latency) before changing anything.
4. **Deploy in parallel** and shift traffic gradually rather than cutting over at once.
5. **Validate health checks** match the old coverage on the new platform.
6. **Test failover** so HA behaviour meets requirements.
7. **Decommission** the old platform only after 30+ days of stable operation.

### Feature-gap mapping (hardware ADC to software)

| ADC feature | NGINX equivalent | HAProxy equivalent |
|---|---|---|
| iRules | lua-nginx-module / njs | ACLs + http-request rules |
| GSLB (GTM) | External DNS (no built-in) | External DNS (no built-in) |
| WAF (ASM) | App Protect (Plus) | Enterprise WAF / external |
| Auth (APM) | `auth_jwt` (Plus) / `auth_request` | External auth (haproxy-lua) |
| Cookie persistence | `sticky` (Plus) | cookie insert/prefix |
| Connection reuse (OneConnect) | `keepalive` (upstream) | `http-reuse` |

For DNS-layer global distribution that replaces a built-in GSLB, see `dns-network-ops`.
