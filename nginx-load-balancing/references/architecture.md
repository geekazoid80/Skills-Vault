# NGINX architecture and internals

How NGINX is built in its load-balancing role: the master/worker model, the event loop, shared memory zones, the NGINX Plus runtime state machinery, and the Ingress Controller design. Configuration syntax is in `configuration.md`; Plus and Kubernetes usage in `ingress-and-plus.md`.

## Master/worker process model

```
Master Process (root)
  +-- Worker Process 1 (thousands of connections via epoll/kqueue)
  +-- Worker Process 2
  +-- Worker Process N (worker_processes auto = 1 per CPU core)
  +-- Cache Manager / Cache Loader (if caching enabled)
```

- **Master:** runs as root (needs privileged ports 80/443), reads and validates config, creates and destroys workers, handles `reload`/`stop`/`quit`/`reopen`, and performs binary upgrades (hot-swap of the NGINX binary).
- **Workers:** run as an unprivileged user, single-threaded each, handle all client connections through a non-blocking I/O event loop, and do not share memory directly (only via shared zones).

## Event loop (epoll/kqueue)

Each worker uses the OS event mechanism: epoll (Linux, O(1)), kqueue (FreeBSD/macOS), eventport (Solaris).

```
1. Worker calls epoll_wait() -- blocks until events are ready
2. OS reports ready file descriptors (sockets with data)
3. Worker processes ALL ready events in one iteration
4. Worker calls epoll_wait() again
```

One worker handles thousands of concurrent connections without thread context-switching overhead.

### Connection capacity

```
worker_connections 1024;   # max per worker (default)
# total = worker_processes * worker_connections
# reverse proxy: each proxied client uses 2 fds (client + upstream)
# effective max proxied per worker = worker_connections / 2
```

For high traffic, raise `worker_connections` to 4096+ and set `worker_rlimit_nofile` to at least 2x it. NGINX handles 10,000+ connections per worker on typical workloads; the limits are file descriptors and memory.

## Shared memory zones

Zones let data cross workers:

- `limit_req_zone`: rate-limit counters.
- `limit_conn_zone`: connection counts.
- `proxy_cache_path ... keys_zone`: cache metadata.
- `upstream ... zone`: upstream state (health, connections), required for Plus features.

Sizing: `zone=name:size`; roughly 8,000-16,000 keys per 1 MB.

## Hot reload

`nginx -s reload` is zero-downtime: the master validates the new config, spawns new workers, old workers stop accepting connections and drain, then exit (or time out). During the drain both configs are briefly active; long-lived connections (WebSocket) can delay old-worker shutdown.

## NGINX Plus runtime state

### Real-time API

```
/api/{version}/
  /http/upstreams/      /stream/upstreams/    /connections/
  /ssl/                 /http/server_zones/   /http/caches/   /resolvers/
```

The write API (`api write=on`) adds/removes upstream servers, modifies parameters (weight, max_conns, down), and drains servers, all without a reload. Changes persist until the next reload (not saved to the config file).

### Active health-check architecture

Health checks run inside the workers: each worker probes independently, state lives in the shared `zone` (consistent across workers), and probes run on an interval regardless of client traffic. A server is marked down after `fails` consecutive failures and up after `passes`. Types: HTTP (status and/or body), TCP, gRPC, and `match` blocks for custom validation.

### Session-persistence architecture

- **Cookie insert (`sticky cookie`):** first request has no cookie; NGINX picks a server by algorithm and inserts a cookie naming it; later requests follow the cookie; a downed server is re-assigned and the cookie updated.
- **Learn (`sticky learn`):** NGINX observes an app-set cookie (e.g. `JSESSIONID`) and maps cookie value to server.
- **Route (`sticky route`):** a variable (`$cookie_route`, `$request_uri`) is the routing key for consistent server selection.

### Key-value store

In-memory, in a shared zone, read/written over the REST API without reload, read from config via `keyval`. Used for dynamic blocklists, feature flags, and A/B testing.

## NGINX Ingress Controller architecture

```
+-----------------------+
| NGINX Ingress Pod     |
| Controller (Go) ----> watches the K8s API for Ingress/CRD changes
|        |              |
|        v              |
| nginx.conf ---------> generated from K8s resources
|        |              |
|        v              |
| NGINX worker(s) ----> handle traffic                       |
+-----------------------+
```

The Go controller watches the Kubernetes API; on a change to Ingress/VirtualServer/ConfigMap it regenerates `nginx.conf` and reloads NGINX.

### Resource types

- **Standard Ingress:** basic host/path routing and TLS termination; limited features.
- **VirtualServer CRD (NGINX-specific):** traffic splitting (canary, blue-green), custom error pages, per-route health checks and rate limiting, WAF (App Protect).
- **VirtualServerRoute CRD:** delegated routing so multiple teams own paths under one hostname.
- **TransportServer CRD:** TCP/UDP (L4) load balancing in Kubernetes.

Configuration sources, in priority order: VirtualServer/VirtualServerRoute CRDs, then Ingress annotations, then ConfigMap globals, then controller command-line arguments. The current stable line (5.x) adds IPv6 for the CRDs, client proxy-header overrides, App Protect WAF, mTLS and JWT/OIDC with Plus, and evolving Gateway API support.

## Performance characteristics

- **Throughput limits:** SSL handshake CPU (TLS 1.3 faster than 1.2, ECDSA faster than RSA), upstream response time, `proxy_buffering` (on by default, buffers responses to memory/disk), and `gzip` (CPU for bandwidth).
- **Memory:** base ~5-10 MB per worker, ~256 bytes per connection, explicitly-sized shared zones, disk-based cache with a memory keys-zone, and an explicit SSL session cache (`ssl_session_cache shared:SSL:10m`).
