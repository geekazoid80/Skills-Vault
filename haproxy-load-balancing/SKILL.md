---
name: haproxy-load-balancing
description: Use for HAProxy load-balancing and reverse-proxy configuration, operations, and tuning (v2.x LTS through 3.x). Covers the global/defaults/frontend/backend/listen configuration model, the single-process multi-threaded event-driven architecture (nbthread, epoll/kqueue, zero-downtime reload via expose-fd listener socket passing), ACL-based routing (path/header/source/method/SNI fetches), stick tables for stateful rate limiting and session tracking (http_req_rate, conn_cur, http_err_rate, gpc/gpt, peer synchronisation), health checks (option httpchk, http-check expect, tcp-check, external-check, inter/rise/fall/fastinter/downinter), SSL/TLS offload and SNI routing (ssl-default-bind-ciphers, crt bundles, strict-sni), L4 (TCP mode) vs L7 (HTTP mode) proxying, the balance algorithms (roundrobin, leastconn, source, uri, hdr, random for power-of-two), cookie-based persistence (insert/indirect/httponly/secure), connection reuse (http-reuse) and timeouts, the runtime API over the admin socket (show stat, disable/enable server, set weight, show table), the stats page, performance tuning (maxconn, buffers, cpu-map, SSL cache), HAProxy Kubernetes Ingress Controller, and log analysis (httplog, termination flags). References architecture.md, configuration.md, operations-and-tuning.md. Triggers include "HAProxy", "haproxy.cfg", "frontend", "backend", "listen", "stick table", "stick-table", "ACL", "use_backend", "balance leastconn", "option httpchk", "http-check", "runtime API", "HAProxy stats", "HAProxy rate limiting", "HAProxy SSL", "strict-sni", "http-reuse", "HAProxy Ingress", "nbthread", "expose-fd", "termination flags". For vendor-neutral load-balancing DESIGN, algorithm and persistence choice, and platform selection (HAProxy vs NGINX vs cloud) see load-balancer-selection; for NGINX as a load balancer see nginx-load-balancing; for AWS ALB/NLB/GWLB see aws-load-balancing; for the TLS certificates HAProxy terminates see cert-manager and lets-encrypt; for the private keys and admin-socket access tokens see secrets-hygiene.
license: MIT
metadata:
  version: 1.0.0
---

# HAProxy load balancing

> **Skill marker**: When applying this skill, begin your reply with `[skill: haproxy-load-balancing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns HAProxy configuration, operations, and tuning. It assumes the design decision (HAProxy is the right platform, at this layer, with this algorithm and persistence model) has already been made; for that decision see `load-balancer-selection`. The depth here is the actual `haproxy.cfg`, the runtime API, and the operational discipline that keeps it healthy.

## When to use

- Writing or reviewing a `haproxy.cfg`: global/defaults tuning, frontend binds, ACL routing, backend pools.
- Building stick-table rate limiting, abuse detection, or session tracking.
- Configuring health checks (HTTP, TCP, external script) with sensible `inter`/`rise`/`fall` timing.
- Setting up SSL/TLS offload, SNI-based routing, or HTTP-to-HTTPS redirect on HAProxy.
- Choosing and configuring a `balance` algorithm and cookie-based persistence.
- Operating a running instance via the runtime API or the stats page (drain a server, change weight, inspect tables).
- Tuning for scale (threads, buffers, maxconn, SSL cache) or deploying the HAProxy Kubernetes Ingress Controller.
- Diagnosing connection issues from logs (termination flags, timers).

## When not to use

- **Deciding whether HAProxy is the right platform**, or choosing L4 vs L7, an algorithm, or a persistence strategy in the abstract: `load-balancer-selection` owns the design and the cross-platform comparison.
- **NGINX or AWS load balancers**: use `nginx-load-balancing` or `aws-load-balancing`.
- **Issuing or renewing the TLS certificate** HAProxy presents: `cert-manager` (Kubernetes) and `lets-encrypt` (public ACME). This skill consumes the certificate bundle; it does not obtain it.
- **Storing the private key or admin-socket credentials**: `secrets-hygiene` owns the secret-store discipline; never inline a key or token in `haproxy.cfg` or a saved command.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | process and thread model, ACL evaluation, stick-table internals, runtime-API mechanics, zero-downtime reload, logging | `references/architecture.md` |
| Configuration | frontend/backend stanzas, ACL routing, stick-table rate limiting, health checks, SSL offload, L4 vs L7, balance algorithms, cookie persistence | `references/configuration.md` |
| Operations + tuning | SSL best practices, health-check timing, rate-limit patterns, timeouts, connection reuse, performance tuning, stats monitoring, Kubernetes Ingress, operational checklist | `references/operations-and-tuning.md` |

## Core model (condensed)

**One process, many threads, no I/O in the data path.** HAProxy runs a single multi-threaded process (`nbthread`), each thread its own epoll/kqueue event loop, with all logging asynchronous over syslog so latency stays predictable under load. Zero-downtime reload depends on `expose-fd listeners` on the stats socket, which lets the new process inherit listener sockets from the old one.

**Frontend accepts, backend distributes.** A frontend binds ports and evaluates ACLs to pick a backend; a backend names the `balance` algorithm and the `server` lines. Match `mode` (tcp vs http) between frontend and backend, and always put `check` on server lines or no health checking happens.

**ACLs are first-match, top-down.** `use_backend` rules evaluate in order; order most specific to least specific or the broad rule shadows the narrow one. ACLs fetch from L3/L4 (`src`, `ssl_fc`) and L7 (`path_beg`, `hdr`, `method`, `ssl_fc_sni`).

**Stick tables are the stateful core.** An in-memory keyed store (`type ip size ... expire ...`) holds counters (`http_req_rate`, `conn_cur`, `http_err_rate`, `gpc0`) for rate limiting, abuse detection, and session persistence; `peers` synchronise them across instances. Size for the expected unique-client count or new entries are dropped.

**Runtime API changes are not persistent.** `disable server`, `set weight`, and `clear table` over the admin socket change the running process only; a reload reverts to `haproxy.cfg`, which is authoritative.

**Anti-patterns:** mismatched `mode` between frontend and backend (silent failure); missing `check` on server lines (no health checks); broad ACL before a specific one (the specific one never matches); an undersized stick table (new entries rejected); a misordered certificate bundle (validation failure); `tcplog` instead of `option httplog` for HTTP mode (no URL/status/timing); no `expose-fd listeners` (reload drops connections).

## Reference router

| Need | Load |
|---|---|
| Process/thread model, memory and buffer architecture, ACL processing and fetch methods, stick-table internals and peer sync, runtime-API mechanics and access levels, zero-downtime reload, logging and termination flags | `references/architecture.md` |
| Frontend/backend/listen stanzas, ACL routing, stick-table rate limiting and session tracking, HTTP/TCP/external health checks, SSL/TLS offload and SNI routing, L4 vs L7 mode, balance algorithms, runtime commands, Kubernetes Ingress annotations | `references/configuration.md` |
| Production SSL setup and certificate-bundle order, health-check timing strategy, rate-limiting patterns (per-IP, login, graduated, abuse), cookie persistence, connection reuse and timeouts, performance tuning, stats monitoring, common patterns (API gateway, database LB, WebSocket), operational checklist | `references/operations-and-tuning.md` |

## Cross-references

- `load-balancer-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether HAProxy fits and at which layer; this skill builds it. Reciprocal reference.
- `nginx-load-balancing`, `aws-load-balancing`: sibling vendor skills for the other platforms in the family.
- `cert-manager`, `lets-encrypt`: issue and renew the TLS certificate HAProxy terminates; this skill consumes the bundle.
- `secrets-hygiene`: TLS private keys and admin-socket access live in the secret store, never inline in `haproxy.cfg`.
- `distributed-tracing`: HAProxy is an L7 span boundary; forward trace headers and surface its timers (Tq/Tw/Tc/Tr/Tt) for latency analysis.
- `multi-vendor-network-ops`: diagnose-first operations when an HAProxy change is part of a wider production network change.

## Red flags

- About to set `mode tcp` on a frontend and `mode http` on its backend (or the reverse): a silent failure.
- About to add `server` lines without `check`: no health monitoring happens.
- About to order `use_backend` rules with a broad ACL above a specific one: the specific rule never fires.
- About to size a stick table below the expected unique-client count: new entries are rejected once it fills.
- About to ship an SSL bundle with the certificate, intermediates, and key in the wrong order: TLS validation fails.
- About to run HTTP mode with the default `tcplog`: logs lose URL, status code, and timing.
- About to reload without `expose-fd listeners` on the stats socket: a brief connection-reset window.
- About to paste a private key or admin-socket token into `haproxy.cfg` or a runbook instead of the secret store.

## Bottom line

HAProxy is a single multi-threaded process: frontends accept and route by first-match ACLs, backends distribute by `balance` algorithm, and stick tables carry the stateful rate-limiting and persistence. Match modes, always health-check with `check`, size stick tables for the client population, and remember the runtime API is transient while `haproxy.cfg` is authoritative. Bring the design and platform choice from `load-balancer-selection`; keep certificates and keys in their proper homes.
