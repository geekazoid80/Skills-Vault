---
name: load-balancer-selection
description: Use for vendor-neutral load-balancing and application-delivery DESIGN and platform selection. Covers L4 (transport) vs L7 (application) load balancing, full-proxy vs transparent vs direct-server-return models, load-balancing algorithms (round-robin, weighted, least-connections, IP hash, consistent hash, power-of-two-choices), health-check design (active vs passive, the ICMP/TCP/HTTP/content/script hierarchy, intervals and thresholds), session persistence and affinity (source-IP, cookie insert/learn/prefix, SSL session ID, application hash) versus stateless design, SSL/TLS termination vs passthrough vs re-encryption, content switching and traffic management (path/host/header routing, rate limiting, WAF placement, caching, connection pooling and multiplexing), high-availability patterns (active-passive, active-active, clustering), Kubernetes ingress vs service mesh, and which platform to choose (HAProxy vs NGINX vs cloud-native vs hardware ADC vs Envoy/mesh). The organising idea is layer-and-model thinking plus map-the-traffic-to-the-platform. References concepts.md, health-and-persistence.md, tls-and-traffic-management.md, platform-selection.md. Triggers include "load balancer", "load balancing", "application delivery", "ADC", "L4 vs L7", "layer 4 load balancing", "layer 7 load balancing", "reverse proxy", "load balancing algorithm", "round robin", "least connections", "consistent hash", "health check design", "session persistence", "sticky sessions", "session affinity", "SSL offload", "TLS termination", "SSL passthrough", "direct server return", "DSR", "connection draining", "rate limiting", "GSLB", "global server load balancing", "virtual server", "backend pool", "load balancer comparison", "which load balancer", "HAProxy vs NGINX", "hardware vs software load balancer", "Kubernetes ingress vs service mesh". For HAProxy configuration and operations see haproxy-load-balancing; for NGINX as a load balancer, reverse proxy, or Kubernetes ingress see nginx-load-balancing; for AWS ALB / NLB / GWLB see aws-load-balancing. For VPC security-group and ENI placement of a public load balancer see aws-networking-audit; for AWS service-selection trade-offs see aws-cloud-ops; for the certificates a load balancer terminates see cert-manager and lets-encrypt; for DNS-based and GSLB load balancing see dns-network-ops. F5 BIG-IP, Citrix NetScaler, Azure Application Gateway, and Envoy are named here only as routing context; deep per-vendor depth for those is not yet in this vault.
license: MIT
metadata:
  version: 1.0.0
---

# Load-balancer and application-delivery design

> **Skill marker**: When applying this skill, begin your reply with `[skill: load-balancer-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for load-balancing and application-delivery (ADC) design. It owns the reasoning that survives any one product: which layer to balance at, which proxy model fits the traffic, which algorithm and persistence method the application needs, how to terminate TLS, and which platform earns the deployment. Platform-specific configuration (HAProxy stanzas, NGINX upstream blocks, AWS target groups) lives in the per-vendor skills; the depth here is the design that outlasts a platform change.

## When to use

- Choosing between L4 and L7 load balancing for a given traffic type (HTTP/HTTPS, TCP, UDP, gRPC).
- Selecting a load-balancing algorithm and deciding whether session persistence is needed at all.
- Designing health checks that detect application failure, not just an open port.
- Deciding where TLS terminates (offload, passthrough, or re-encryption to the backend) and why.
- Planning a high-availability topology (active-passive, active-active, clustering, DSR, two-tier L4+L7).
- Comparing platforms (HAProxy, NGINX, cloud-native, hardware ADC, Envoy/mesh) and choosing one.
- Deciding between Kubernetes ingress and a service mesh, or planning a hardware-to-software migration.

## When not to use

- **Configuring a specific platform** (the exact HAProxy `backend` stanza, NGINX `upstream` block, or AWS target-group settings): use `haproxy-load-balancing`, `nginx-load-balancing`, or `aws-load-balancing`. This umbrella owns the design; those own the syntax and operations.
- **VPC-side placement and security of a cloud load balancer** (security-group rules, ENI/subnet placement, public-exposure audit): `aws-networking-audit` owns the network-security review.
- **The certificate lifecycle a load balancer depends on** (issuance, ACME, renewal): `cert-manager` (Kubernetes) and `lets-encrypt` (public ACME) own that; this skill decides where TLS terminates, not how the certificate is obtained.
- **DNS-based or GSLB load balancing as a DNS concern** (weighted/latency/geo records, health-checked failover at the DNS layer): `dns-network-ops` owns the DNS design; this skill cross-references it for global distribution.
- **F5 BIG-IP, Citrix NetScaler, Azure Application Gateway, Envoy deep configuration**: named here as routing context only; deep per-vendor depth for those is not yet in this vault.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Fundamentals + algorithm | L4 vs L7, full-proxy vs transparent, DSR, which algorithm, connection pooling | `references/concepts.md` |
| Health + persistence | health-check level and thresholds, sticky sessions, affinity method, stateless design | `references/health-and-persistence.md` |
| TLS + traffic management | TLS termination vs passthrough vs re-encrypt, content switching, rate limiting, WAF, caching | `references/tls-and-traffic-management.md` |
| Platform selection | HAProxy vs NGINX vs cloud-native vs hardware vs Envoy, Kubernetes ingress vs mesh, migration | `references/platform-selection.md` |

## Core model (condensed)

**Pick the layer first.** L4 balances connections by IP and port without reading the payload: very high throughput, protocol-agnostic, but no content routing, no HTTP health checks, no TLS offload. L7 terminates the connection and reads the application protocol: content-based routing, rich health checks, TLS offload, header manipulation, at the cost of CPU and latency. Most web traffic wants L7; databases, raw TCP/UDP, and extreme-throughput paths want L4. A two-tier design (L4 in front of an L7 farm) scales L7 capacity.

**The model follows the layer.** Full-proxy (L7) means two separate connections, so the backend sees the load balancer's IP unless `X-Forwarded-For` is honoured. Transparent/pass-through (L4) preserves the client IP. Direct server return sends only the request through the load balancer and lets the response bypass it: it slashes load-balancer bandwidth but rules out TLS offload, cookie persistence, and header work.

**Algorithm is a smaller decision than persistence.** Round-robin for homogeneous stateless servers; weighted for mixed capacity; least-connections when request durations vary; consistent hash when cache-hit locality matters; power-of-two-choices for large pools. But the bigger question is whether you need persistence at all: stateless design with an external session store (Redis, JWT) beats sticky sessions because it allows free distribution and clean auto-scaling. Reach for persistence only when a legacy app stores state locally, and prefer cookie insert over source-IP (which collapses behind NAT).

**Health checks must test the application, not the port.** A TCP connect succeeds while the app returns 500s. Use an HTTP or content-level check against a dedicated `/health` endpoint that verifies real dependencies; set rise/fall thresholds to stop flapping and intervals that balance detection speed against probe load.

**TLS terminates where you need visibility.** Offload at the load balancer for centralised certificate management, CPU relief, and L7 inspection; passthrough when the backend must own the TLS session; re-encrypt when compliance demands encryption on the wire to the backend and you still want L7 routing.

**Then choose the platform.** Match the traffic and the operating model to the product: software (HAProxy, NGINX) for cloud-native and configuration-as-code; cloud-native (AWS ALB/NLB) for managed simplicity inside one cloud; hardware ADC for the deepest single-box feature set; Envoy/mesh for east-west service-to-service.

**Anti-patterns:** balancing at L7 when raw TCP throughput is the goal (wasted CPU and latency); adding sticky sessions to an app that could be stateless; using the homepage as a health check; source-IP persistence behind a corporate NAT; choosing a hardware ADC for a single cloud-native web app; buying a platform before the traffic profile (HTTP vs TCP, north-south vs east-west, scale) is understood.

## Reference router

| Need | Load |
|---|---|
| L4 vs L7, full-proxy vs transparent vs DSR, the algorithm catalogue and selection guide, connection pooling/multiplexing and draining | `references/concepts.md` |
| Health-check levels, parameters and anti-patterns, persistence methods and trade-offs, when to avoid persistence, HA patterns | `references/health-and-persistence.md` |
| SSL/TLS offload vs passthrough vs re-encryption, TLS best practices, content switching, rate limiting, caching, WAF placement | `references/tls-and-traffic-management.md` |
| Platform comparison (F5, NGINX, HAProxy, NetScaler, Envoy, cloud LBs), decision matrix, Kubernetes ingress vs service mesh, hardware-to-software migration | `references/platform-selection.md` |

## Cross-references

- `haproxy-load-balancing`: HAProxy frontend/backend configuration, ACLs, stick tables, runtime API, and operations. This umbrella decides whether HAProxy fits; that skill builds it.
- `nginx-load-balancing`: NGINX as a load balancer, reverse proxy, and Kubernetes ingress (upstream blocks, proxy caching, NGINX Plus). Reciprocal reference.
- `aws-load-balancing`: AWS ALB (L7), NLB (L4), and GWLB, with target groups, listeners, and AWS integrations.
- `aws-networking-audit`: VPC security-group and ENI placement of a public load balancer; the network-security review of how the load balancer is exposed.
- `aws-cloud-ops`: AWS service-selection and cost trade-offs; consult when the choice is "managed AWS LB vs self-managed on EC2".
- `cloud-platform-selection`: vendor-neutral cloud strategy; consult when the load-balancing choice is part of a wider multi-cloud or migration decision.
- `cert-manager`, `lets-encrypt`: the certificates a load balancer terminates. This skill decides where TLS terminates; those obtain and renew the certificate.
- `secrets-hygiene`: TLS private keys and load-balancer API tokens live in the secret store, never inline in a config or a saved query.
- `dns-network-ops`: DNS-based and GSLB load balancing (weighted, latency, geo, health-checked failover at the DNS layer) as the global counterpart to in-data-centre load balancing.
- `distributed-tracing`: an L7 load balancer is a span boundary; propagate trace context and surface upstream latency for observability.
- `multi-vendor-network-ops`: diagnose-first operations when a load-balancer change is part of a wider production network change.

## Red flags

- About to put an L7 full-proxy in front of raw TCP or UDP traffic where an L4 balancer would be faster and simpler.
- About to add sticky sessions to an application that could externalise its session store and stay stateless.
- About to use source-IP persistence for clients that sit behind a shared NAT or proxy (all of them pin to one server).
- About to configure a TCP-only health check for an HTTP service (a 500-erroring app still passes).
- About to use the application homepage as the health-check target instead of a lightweight dedicated endpoint.
- About to choose a hardware ADC for a single cloud-native web app, or a software LB for a feature (GSLB, deep WAF) it does not natively provide.
- About to terminate TLS at the load balancer without a plan for certificate renewal, or leave the private key inline in a config file.
- About to pick a platform before the traffic profile (HTTP vs TCP, north-south vs east-west, connections/sec, environment) is known.

## Bottom line

Balance at the lowest layer that meets the requirement, and let the proxy model follow from the layer. Decide whether you need persistence before you pick an algorithm, and prefer a stateless design with an external session store. Health-check the application, not the port. Terminate TLS where you need visibility and have a renewal plan. Choose the platform from the traffic profile and operating model, not from familiarity, and route all per-vendor configuration to the HAProxy, NGINX, and AWS load-balancer skills.
