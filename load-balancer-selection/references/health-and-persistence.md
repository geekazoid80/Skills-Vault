# Health checks, session persistence, and high availability

How a load balancer decides a backend is fit to serve, how (and whether) to pin a user to a server, and how the load balancers themselves survive failure.

## Health checks

### Purpose and types

Health checks remove unhealthy backends before users hit them. Two models:

- **Passive (failure detection).** Watch real traffic for errors; mark a server down after too many 5xx or timeouts. No extra probe traffic, but failures are only caught after they affect users. NGINX OSS works this way (`max_fails` + `fail_timeout`).
- **Active (probing).** Send periodic probes regardless of traffic; catch failure before users do, at the cost of probe overhead. NGINX Plus, F5, and HAProxy all support active checks.

### Health-check hierarchy

Use the most specific check the application supports:

| Level | Protocol | What it tests | Limitation |
|---|---|---|---|
| 1. ICMP ping | ICMP | OS is up | Process can be dead while the OS lives |
| 2. TCP connect | TCP | Port is open | App may be returning errors |
| 3. HTTP GET | HTTP | Web server responds | May return 200 while the app is broken |
| 4. Content match | HTTP | Response body is valid | Slower (must read the body) |
| 5. Custom script | Custom | Business logic | Most complex to maintain |

Use level 3 or 4 for HTTP services. A TCP-only check passes while the application returns 503.

### Parameters

| Parameter | Recommended | Why |
|---|---|---|
| Interval | 5-10 seconds | Balance detection speed against backend load |
| Timeout | 3-5 seconds | Must be shorter than the interval |
| Rise threshold | 2-3 successes | Stop a recovering server from flapping back in |
| Fall threshold | 2-3 failures | Tolerate transient errors before removal |
| Target URI | `/health` or `/healthz` | A dedicated endpoint, not the homepage |

### Health-endpoint design

A good `/health` or `/healthz` endpoint returns 200 only when the app is ready to serve, returns 503 when it should not receive traffic, checks critical dependencies (database, cache), stays lightweight (sub-100ms), does not return 200 during startup, and supports separate liveness and readiness checks for Kubernetes.

```json
{ "status": "healthy", "checks": { "database": "connected", "cache": "connected", "disk_space": "ok" } }
```

### Anti-patterns

1. Homepage as the health check (slow, cached, or dynamically generated).
2. No health check at all (dead servers receive traffic until removed by hand).
3. Over-aggressive intervals (1-second checks across 50 servers is 50 req/s of pure overhead).
4. TCP-only checks for HTTP services (the SYN succeeds while the app returns 500s).

## Session persistence (sticky sessions)

### Why it exists

Some applications keep session state locally (in-memory sessions, temp files, shopping carts). If the next request lands on a different server, the session is lost. Persistence pins a client to a server.

### Methods

| Method | Mechanism | Pros | Cons |
|---|---|---|---|
| Source IP | Client IP maps to a server | Simple, works at L4 | Collapses behind NAT/proxy (many clients, one IP) |
| Cookie insert | LB adds a cookie (`SERVERID=server1`) | Accurate, per-user | HTTP/HTTPS only, cookie overhead |
| Cookie learn | LB maps an existing app cookie to a server | No app change | Requires the app to set a cookie |
| Cookie prefix | LB prepends a server ID to an existing cookie | No extra cookie | Modifies the cookie value |
| SSL session ID | TLS session identifier maps to a server | Works before decryption | Short-lived; unreliable with TLS 1.3 session tickets |
| URL / header hash | Hash of a parameter or header | Application-specific affinity | Needs a consistent parameter |
| Custom (iRule / Lua) | Programmatic key | Maximum flexibility | Complexity and maintenance |

### Persistence vs statelessness

Modern architectures prefer **stateless design** with an external session store (Redis, Memcached, database) or JWT-based auth. It removes the need for persistence entirely, enables unrestricted distribution, simplifies auto-scaling (no session draining on scale-in), and survives server failure without losing sessions.

**Recommendation:** design new applications to be stateless; reach for persistence only for legacy apps that store state locally, and prefer cookie insert over source IP. Avoid persistence for microservices and auto-scaling environments, where persistent sessions block effective scale-in.

## High-availability patterns

### Active-passive

One load balancer serves all traffic; a standby takes over on failure. A virtual IP (VIP) floats between them, heartbeat monitoring detects failure, and failover takes 1-10 seconds. The simplest model, but standby capacity sits idle.

### Active-active

Both load balancers serve traffic simultaneously (distributed via DNS, an upstream L4 balancer, or ECMP). Roughly doubles capacity, but needs session synchronisation if persistence is in use and is harder to configure and troubleshoot.

### Clustering

Multiple load balancers share load and state:

- F5 BIG-IP: device groups with config sync and traffic groups.
- HAProxy: stick-table peer synchronisation across instances.
- NGINX Plus: zone-based state sharing across workers (not across instances).
