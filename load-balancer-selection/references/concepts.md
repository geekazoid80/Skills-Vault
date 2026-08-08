# Load-balancing fundamentals: layers, models, and algorithms

The vendor-neutral foundation: what layer to balance at, which proxy model the traffic implies, which algorithm fits, and how connections are reused. Health checks, persistence, and TLS each have their own reference; this one is the request-path mechanics.

## What a load balancer buys you

Distributing traffic across a backend pool delivers four things at once: high availability (a failed server is taken out of rotation), scalability (add servers without touching clients), performance (even distribution optimises response time), and maintainability (drain a server for updates without an outage). Every design decision below is in service of one or more of these.

## Layer 4 vs Layer 7

### Layer 4 (transport)

Balances TCP/UDP connections on source/destination IP and port without reading the payload.

- Strengths: very high throughput (millions of connections/second), protocol-agnostic (HTTP, databases, SMTP, custom TCP/UDP), low latency (no payload inspection), simple configuration.
- Limits: no content-based routing (cannot route by URL, header, or cookie), no HTTP-aware health checks (TCP connect or ICMP only), no TLS offload (encrypted traffic passes through), persistence limited to source IP.
- Use when: database load balancing, raw TCP/UDP services, extreme-performance paths, simple failover.

### Layer 7 (application)

Parses the application protocol (HTTP, gRPC) and routes on content. Full-proxy or reverse-proxy model: terminate the client connection, inspect the request, open a new connection to the chosen backend.

- Strengths: content-based routing (path, host header, cookie, method), HTTP/content health checks, TLS termination and offload, connection multiplexing, header manipulation, compression, caching, cookie persistence, WAF integration.
- Limits: higher CPU (application-layer parsing), higher latency (full-proxy processing), protocol-specific.
- Use when: web applications, API gateways, microservices, content routing, TLS offload, WAF integration.

## Proxy models

**Full-proxy (L7).** The load balancer terminates connection 1 from the client and opens connection 2 to the server, with full protocol visibility:

```
Client <--connection 1--> Load balancer <--connection 2--> Server
```

It can rewrite headers and URLs, compress, and cache. The backend sees the load balancer's IP as the source unless SNAT plus `X-Forwarded-For` is used to preserve the client IP.

**Transparent / pass-through (L4).** The load balancer forwards packets without terminating the connection, limited to L3/L4 header inspection:

```
Client <--------connection (through LB)--------> Server
```

No application-layer visibility, lower latency, and the server sees the original client IP (especially in DSR mode).

**Direct server return (DSR).** Only the request traverses the load balancer; the response goes straight from server to client:

```
Client --[request]--> Load balancer --[request]--> Server
Client <--[response]-- Server  (directly, bypassing the LB)
```

It dramatically cuts load-balancer bandwidth (responses dwarf requests) but needs special network configuration (the server must accept traffic for the VIP) and is L4-only: no TLS offload, no header manipulation, no cookie persistence. Used for streaming, large downloads, and CDN origins.

## Load-balancing algorithms

### Static

| Algorithm | How it works | Best for |
|---|---|---|
| Round-robin | Sequential distribution across servers | Homogeneous servers, stateless apps |
| Weighted round-robin | Round-robin with proportional weights (3:2:1 = 3/6, 2/6, 1/6) | Heterogeneous servers (different capacities) |
| IP hash | Hash of client IP selects the server | Simple affinity without cookies |
| URI / consistent hash | Hash of request URI onto a hash ring | Cache-heavy apps (maximise cache hits) |

### Dynamic

| Algorithm | How it works | Best for |
|---|---|---|
| Least connections | Send to the server with fewest active connections | Long-lived or variable-duration requests |
| Weighted least connections | Least connections adjusted by server weight | Mixed capacity with variable load |
| Fastest / least response time | Send to the lowest-latency server | Latency-sensitive applications |
| Random with two choices | Pick two at random, choose the less loaded | Large server pools (power of two choices) |

### Notes that matter

- **Consistent hash** remaps only a fraction of keys when a server joins or leaves, which is why it is the caching choice (`hash $request_uri consistent` in NGINX, `hash-type consistent` in HAProxy).
- **Power of two choices** is near-optimal with almost no global state and scales to large pools (`random` in HAProxy, `random two least_conn` in NGINX); it is mathematically far better than a single random pick.
- IP hash gives crude affinity but collapses behind NAT (every client on the NAT pins to one server).

### Selection guide

```
Is the application stateless?
  Yes -> homogeneous servers? Yes -> round-robin; No -> weighted round-robin
  No  -> need cookie persistence? Yes -> use persistence (not the algorithm) for affinity
                                  No  -> IP hash, or least-connections + source persistence

Are request durations variable? Yes -> least connections; No -> round-robin
Is caching important?           Yes -> URI / consistent hash; No -> least connections or round-robin
```

## Connection pooling, multiplexing, and draining

**Multiplexing (keep-alive).** Without it, each client request opens a fresh TCP connection to the backend. With it, the load balancer keeps a pool of persistent backend connections and reuses them:

```
100 clients --[100 connections]--> LB --[10 persistent connections]--> Backend
```

This cuts TCP setup overhead, lowers backend connection counts, and improves response time. Platform terms: F5 OneConnect, NGINX `keepalive` in the upstream block, HAProxy `http-reuse`.

**Draining (graceful shutdown).** When removing a server (maintenance, deploy, scale-in): stop new connections, let existing ones complete during a drain window, force-close stragglers after the timeout, then remove the server. F5 sets the member to "disabled"; NGINX Plus uses the `drain` API parameter; HAProxy uses `disable server` over the runtime API.

## Deployment patterns (at a glance)

| Pattern | Description | Use case |
|---|---|---|
| Single-tier L7 | One load-balancer layer for everything | Small to medium web apps |
| Two-tier (L4 + L7) | L4 distributes across an L7 farm | Scale L7 capacity behind an L4 front end |
| Active-passive HA | Standby takes over on failure | Most production deployments |
| Active-active HA | Both balancers handle traffic | High-traffic environments |
| DSR | Response bypasses the load balancer | Ultra-high-throughput (streaming, CDN) |
| Cloud LB + self-managed | Cloud ALB/NLB in front of NGINX/HAProxy | Kubernetes, cloud-native apps |
| Global (GSLB) | DNS-based distribution across sites | Multi-region, disaster recovery |
