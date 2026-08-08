---
name: nginx-load-balancing
description: Use for NGINX as a load balancer, reverse proxy, and Kubernetes ingress (NGINX OSS and NGINX Plus). Covers the master/worker event-driven architecture (epoll/kqueue, worker_processes, worker_connections, shared memory zones, hot reload), upstream and reverse-proxy configuration (upstream blocks, proxy_pass, proxy_set_header, keepalive to upstream, buffering, timeouts), load-balancing methods (round-robin, least_conn, ip_hash, generic hash, random two for power-of-two), server parameters (weight, backup, max_fails/fail_timeout passive health, max_conns, slow_start), SSL/TLS termination (ssl_certificate, protocols, OCSP stapling, session cache, HSTS), rate limiting (limit_req_zone, burst, nodelay) and connection limiting (limit_conn_zone), proxy caching (proxy_cache_path, cache keys, proxy_cache_use_stale, cache lock and background update), stream module L4 TCP/UDP proxying, NGINX Plus features (active health_check with match blocks, sticky cookie/learn/route session persistence, live activity API, key-value store, JWT auth, slow_start), and the F5 NGINX Ingress Controller for Kubernetes (Ingress resources, VirtualServer and VirtualServerRoute and TransportServer CRDs, traffic splitting for canary and blue-green, ConfigMap globals, migration from the retired community ingress-nginx). References architecture.md, configuration.md, ingress-and-plus.md. Triggers include "NGINX", "nginx.conf", "upstream", "proxy_pass", "least_conn", "ip_hash", "limit_req_zone", "limit_conn_zone", "proxy_cache", "NGINX Plus", "active health check", "sticky cookie", "NGINX Ingress", "Ingress Controller", "VirtualServer CRD", "TransportServer", "stream module", "stub_status", "nginx -s reload", "worker_connections". This skill scopes NGINX to its load-balancing / reverse-proxy / ingress role, not general web-server hosting. For vendor-neutral load-balancing DESIGN, algorithm and persistence choice, and platform selection (NGINX vs HAProxy vs cloud) see load-balancer-selection; for HAProxy see haproxy-load-balancing; for AWS ALB/NLB/GWLB see aws-load-balancing; for the TLS certificates NGINX terminates see cert-manager and lets-encrypt; for private keys and Plus API access see secrets-hygiene.
license: MIT
metadata:
  version: 1.0.0
---

# NGINX load balancing

> **Skill marker**: When applying this skill, begin your reply with `[skill: nginx-load-balancing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns NGINX in its load-balancer, reverse-proxy, and Kubernetes-ingress role: upstream blocks, proxy configuration, SSL termination, rate limiting, caching, the NGINX Plus extras, and the Ingress Controller. It assumes the design decision (NGINX is the right platform) is already made; for that see `load-balancer-selection`. It is scoped to the load-balancing role, not general web-server hosting.

## When to use

- Configuring an `upstream` block and `proxy_pass`: load-balancing method, server parameters, keepalive to upstream, header forwarding, buffering, timeouts.
- Setting up SSL/TLS termination, rate limiting (`limit_req_zone`), or proxy caching on NGINX.
- Proxying TCP/UDP (databases, MQTT, DNS) via the `stream` module (L4).
- Using NGINX Plus features: active health checks, sticky-session persistence, the live API, key-value store, JWT auth.
- Deploying the F5 NGINX Ingress Controller: Ingress resources, VirtualServer CRDs, traffic splitting for canary/blue-green, ConfigMap globals.
- Migrating from the retired community ingress-nginx to the official F5 controller.
- Diagnosing reverse-proxy behaviour from access/error logs and `stub_status` or the Plus API.

## When not to use

- **Deciding whether NGINX is the right platform**, or choosing L4 vs L7, an algorithm, or a persistence strategy in the abstract: `load-balancer-selection` owns the design and cross-platform comparison.
- **HAProxy or AWS load balancers**: use `haproxy-load-balancing` or `aws-load-balancing`.
- **General NGINX web-server hosting** unrelated to load balancing (static-site serving, PHP-FPM hosting, FastCGI app serving): out of scope here; this skill covers the reverse-proxy/load-balancer/ingress role.
- **Issuing or renewing the TLS certificate** NGINX presents: `cert-manager` (Kubernetes) and `lets-encrypt` (public ACME). This skill consumes the certificate; it does not obtain it.
- **Storing private keys or Plus API credentials**: `secrets-hygiene` owns the secret-store discipline; never inline a key in `nginx.conf`.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | master/worker model, event loop, shared memory zones, Plus runtime state, Ingress Controller design, performance characteristics | `references/architecture.md` |
| Configuration | upstream blocks, balancing methods, server parameters, passive health, SSL termination, rate/connection limiting, proxy caching, stream L4, timeouts and buffering | `references/configuration.md` |
| Plus + Kubernetes | active health checks, sticky sessions, live API, key-value, JWT, Ingress resources, VirtualServer CRDs, canary/blue-green, ConfigMap, community-to-F5 migration | `references/ingress-and-plus.md` |

## Core model (condensed)

**Master configures, workers serve.** The master process reads and validates config and manages workers; each single-threaded worker handles thousands of connections through an epoll/kqueue event loop. Workers share state only through shared memory zones. `nginx -s reload` is zero-downtime: new workers spawn, old ones drain.

**Upstream blocks are the load balancer.** An `upstream` names servers and a method (default round-robin, `least_conn`, `ip_hash`, `hash $key`, `random two least_conn`). `keepalive` pools idle connections to the backend, but it is per worker, not total, and needs `proxy_http_version 1.1` plus `proxy_set_header Connection ""`.

**OSS health checks are passive; Plus adds active.** OSS detects failure only after real requests fail (`max_fails` + `fail_timeout`). Active probing, sticky sessions, the live API, and the key-value store all require NGINX Plus and a `zone` directive in the upstream, without which those features silently do nothing.

**Always forward the client context.** Set `Host $host`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto`, or the backend sees the upstream name as Host and loses the client IP and scheme.

**Caching buys resilience, not just speed.** `proxy_cache_use_stale` serves stale content when the backend is down, `proxy_cache_lock` prevents a cache stampede, and `proxy_cache_background_update` refreshes asynchronously.

**Anti-patterns:** forgetting `proxy_set_header Host`; relying on OSS passive checks in production; misreading `keepalive` as a total rather than per-worker; `ip_hash` behind a NAT or CDN (all clients pin to one server); rate limiting without `nodelay` for APIs (latency spikes); missing the `zone` directive for Plus features; using the retired community ingress-nginx for a new deployment.

## Reference router

| Need | Load |
|---|---|
| Master/worker model, event loop, connection capacity, shared memory zones, Plus runtime API and health-check and persistence architecture, Ingress Controller design, performance characteristics | `references/architecture.md` |
| Upstream configuration, balancing methods and server parameters, passive health checks, SSL/TLS termination, rate and connection limiting, proxy caching, stream (L4) proxying, timeouts, header forwarding, buffering | `references/configuration.md` |
| NGINX Plus active health checks (match blocks), sticky cookie/learn/route, live API, key-value store, JWT auth, the F5 Ingress Controller, Ingress vs VirtualServer/VirtualServerRoute/TransportServer CRDs, canary and blue-green, ConfigMap, community-to-F5 migration | `references/ingress-and-plus.md` |

## Cross-references

- `load-balancer-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether NGINX fits and at which layer; this skill builds it. Reciprocal reference.
- `haproxy-load-balancing`, `aws-load-balancing`: sibling vendor skills for the other platforms in the family.
- `cert-manager`, `lets-encrypt`: issue and renew the TLS certificate NGINX terminates; this skill consumes it. cert-manager is especially relevant for the Ingress Controller's TLS secrets.
- `secrets-hygiene`: TLS private keys and the Plus API write token live in the secret store, never inline in `nginx.conf`.
- `distributed-tracing`: NGINX is an L7 span boundary; forward trace headers and expose upstream response time for latency analysis.
- `multi-vendor-network-ops`: diagnose-first operations when an NGINX change is part of a wider production network change.

## Red flags

- About to omit `proxy_set_header Host $host`: the backend receives the upstream group name as the Host header.
- About to depend on OSS passive health checks in production: dead servers receive traffic until a real request fails.
- About to size `keepalive` as if it were a total: it is per worker, so multiply by `worker_processes`.
- About to use `ip_hash` where clients sit behind a NAT or CDN: they all pin to one server; use `hash $cookie_session consistent` or Plus sticky cookies.
- About to apply API rate limiting without `nodelay`: excess requests queue and cause latency spikes.
- About to enable a Plus feature (active health check, sticky, live API) without a `zone` in the upstream: it silently fails.
- About to stand up a new Kubernetes ingress on the retired community ingress-nginx instead of the F5 NGINX Ingress Controller.
- About to put a private key or Plus API token in `nginx.conf` or a runbook instead of the secret store.

## Bottom line

NGINX is a master plus single-threaded event-loop workers; the `upstream` block is the load balancer and shared memory zones are how workers cooperate. Forward the client context, prefer NGINX Plus (with a `zone`) for active health checks and sticky sessions in production, and use caching with `use_stale`/`lock` for resilience. In Kubernetes, reach for the F5 controller's VirtualServer CRDs over plain Ingress for canary and per-route control. Bring the design and platform choice from `load-balancer-selection`; keep certificates and keys in their proper homes.
