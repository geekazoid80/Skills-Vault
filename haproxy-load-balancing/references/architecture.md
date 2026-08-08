# HAProxy architecture and internals

How HAProxy is built: the process and thread model, the frontend/backend pipeline, ACL evaluation, stick-table internals, the runtime API, zero-downtime reload, and logging. Read this for "how does X work" questions; configuration syntax lives in `configuration.md`.

## Core design

A high-performance, event-driven TCP/HTTP load balancer built for throughput and predictable latency.

### Single-process, multi-threaded

- One process (not master/worker like NGINX). Multi-threaded since 2.x: `nbthread` scales across CPU cores.
- Threads share one address space with fine-grained locking; no inter-process communication overhead.

### Event-driven I/O

- epoll (Linux) / kqueue (BSD) for non-blocking I/O, one event loop per thread.
- No file I/O in the data path: all logging is asynchronous (syslog over UDP/TCP or a local socket). This is what keeps latency predictable even when the log destination is slow.

### Memory

- Buffers are pre-allocated at startup from `tune.bufsize` and `maxconn`: roughly `(tune.bufsize * 2 + ~17kB) * maxconn` per process.
- The buffer pool removes runtime allocation overhead. Stick tables use dedicated, size-capped memory.

## Frontend / backend model

```
Client -> [bind *:443 ssl] -> [ACL evaluation] -> [use_backend] -> Backend -> [balance] -> [health filter] -> Server
```

- **Frontend (listener):** `bind` (IP, port, SSL), ACLs, `use_backend` (conditional), `default_backend` (fallback), `http-request` rules. Multiple frontends can coexist on different ports/IPs.
- **Backend (server pool):** `balance` algorithm, `server` lines (with health check and weight), `option httpchk`, `stick-table`, `cookie` persistence.
- **Listen:** combines frontend and backend for simple deployments (commonly the stats page).

## ACL system internals

ACLs are evaluated in order within `use_backend` directives, first match wins:

```
acl is_api path_beg /api/
acl is_admin path_beg /admin/
acl is_internal src 10.0.0.0/8
use_backend api_backend   if is_api              # checked first
use_backend admin_backend if is_admin is_internal
default_backend web_backend                       # fallback
```

### Fetch methods

- **L3/L4:** `src`, `dst`, `src_port`, `dst_port`, `ssl_fc` (boolean: is this an SSL connection).
- **L7 (HTTP mode):** `path`/`path_beg`/`path_end`/`path_reg`, `url_param(name)`, `hdr(name)`/`hdr_beg`/`hdr_sub`/`hdr_reg`, `method`, `req.body`, `cookie(name)`.
- **Stick-table samples:** `sc_http_req_rate(0)`, `sc_conn_cur(0)`, `sc_http_err_rate(0)`, `sc_gpc0_rate(0)` for the tracked source.

## Stick-table architecture

An in-memory hash table keyed per client, storing counters plus an expiry timer and an optional sticky server assignment:

```
Key (e.g. client IP) -> data stores (conn_cur, http_req_rate, gpc0, ...) -> expiry -> sticky server (optional)
```

### Data types

| Type | Use |
|---|---|
| `conn_cur` | Current concurrent connections (connection limiting) |
| `conn_rate(period)` | Connection rate limiting |
| `http_req_rate(period)` | Request rate limiting |
| `http_err_rate(period)` | Error detection |
| `bytes_in_rate` / `bytes_out_rate` | Bandwidth limiting / monitoring |
| `gpc0`, `gpc1` | General-purpose counters (failed logins, etc.) |
| `gpt0` | General-purpose tag (blocklist / allowlist marking) |
| `server_id` | Server assignment (session persistence) |

### Key types

`ip` (4 bytes), `ipv6` (16 bytes), `integer` (4 bytes), `string len N`, `binary len N`.

### Peer synchronisation

```
peers HAPROXY_PEERS
    peer haproxy1 192.168.1.10:10000
    peer haproxy2 192.168.1.11:10000

backend app_backend
    stick-table type ip size 100k expire 10m store http_req_rate(1m) peers HAPROXY_PEERS
```

- HAProxy 3.0: sharded tree (table split across tree heads with separate locks), roughly 6x throughput on 80-thread systems.
- HAProxy 3.2: a dedicated sync thread, 5-8 million updates/second (up from 500k-1M) on 128-thread systems.

## Runtime API

Operates through a Unix domain socket; commands are line-oriented text, processed synchronously. Changes modify the running process but not `haproxy.cfg`, so they are lost on reload (the config file is authoritative).

- **Read-only:** `show info`, `show stat`, `show backend`, `show servers state`, `show table`, `show errors`.
- **State-changing:** `disable server`, `enable server`, `set weight`, `set maxconn server`, `clear table`, `clear counters`.
- **3.2 additions:** `show events` (event stream with `-0` delimiter), array index access (`data.gpt[1]`).

```
global
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats socket ipv4@127.0.0.1:9999 level operator
    stats timeout 30s
```

Access levels: `user` (read-only stats), `operator` (read + enable/disable server), `admin` (full, including weights and tables). `expose-fd listeners` is critical for zero-downtime reload (lets the new process inherit listener file descriptors).

## Multi-threading

```
global
    nbthread 4
```

- All threads share the address space; each runs its own event loop; connections are distributed via the accept queue.
- **Thread-local (no contention):** connection handling, buffers, most per-connection state.
- **Shared (locking):** stick tables (sharded in 3.0+), server health state, statistics, the DNS resolver cache, peers sync.
- Scaling: start with `nbthread` = core count; SSL-heavy workloads scale nearly linearly to ~16 cores, beyond which stick-table locking is the bottleneck (eased in 3.0/3.2).

## Zero-downtime reload

```
1. systemctl reload haproxy (SIGUSR2)
2. New process starts with new config
3. New process inherits listener sockets via expose-fd
4. Old process stops accepting new connections
5. Old process drains existing connections
6. Old process exits after drain (or hard-stop-after timeout)
```

`expose-fd listeners` on the stats socket is the key requirement, without it the reload causes a brief connection-reset window. `hard-stop-after 30s` caps how long the old process lingers for long-lived connections (WebSocket, streaming).

## Logging

No file I/O in the data path: all logs go via syslog (UDP to local syslogd, or TCP to remote), with no blocking writes during request processing.

```
defaults
    option httplog        # detailed HTTP log format
    option dontlognull    # skip health-check probes
    log /dev/log local0
```

The HTTP log includes timestamp, frontend, backend, server, the Tq/Tw/Tc/Tr/Tt timers, status code, bytes, termination flags, and connection counts.

### Termination flags

`--` normal completion; `CD` client disconnected; `SD` server disconnected; `sH` server read timeout; `cD` client timeout; `SC` server connection refused; `PH` proxy protocol error. These flags are the fastest way to diagnose how and why a connection ended.
