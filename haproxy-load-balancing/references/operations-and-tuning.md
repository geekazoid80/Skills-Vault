# HAProxy operations and tuning

Production SSL, health-check timing, rate-limiting patterns, connection management, performance tuning, stats monitoring, common deployment patterns, and the operational checklist. Configuration syntax is in `configuration.md`; internals in `architecture.md`.

## Production SSL/TLS

```haproxy
global
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    tune.ssl.default-dh-param 2048
    tune.ssl.cachesize 50000
    tune.ssl.lifetime 300

frontend https_front
    bind *:443 ssl crt /etc/ssl/certs/bundle.pem alpn h2,http/1.1
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-Frame-Options "DENY"
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Real-IP %[src]
    default_backend app_backend
```

### Certificate bundle order

A single PEM file in this order: server certificate, intermediate(s), private key. Wrong order causes validation failures. Multi-domain: point `crt` at a directory with `strict-sni`; HAProxy auto-loads all PEMs and selects by SNI. The private key belongs in the secret store, not a tracked file: see `secrets-hygiene`. Issuance and renewal: `cert-manager` / `lets-encrypt`.

### HTTP-to-HTTPS redirect

```haproxy
frontend http_front
    bind *:80
    http-request redirect scheme https code 301 unless { ssl_fc }
```

## Health-check timing

```haproxy
backend app_backend
    option httpchk
    http-check send meth GET uri /health ver HTTP/1.1 hdr Host app.internal
    http-check expect status 200
    server app1 192.168.10.11:8080 check inter 5s rise 2 fall 3
```

| Parameter | Value | Rationale |
|---|---|---|
| `inter` | 5s standard, 2s critical | Detection speed vs backend load |
| `rise` | 2 | Two successes before UP (anti-flap) |
| `fall` | 3 | Three failures before DOWN (tolerate transients) |
| `fastinter` | 1s | Faster during a state transition |
| `downinter` | 10s | Slower while already down (reduce load) |

Add `http-check expect string "status.*ok"` to validate the response body. For complex checks, `option external-check` runs a script that returns 0 for healthy.

## Rate-limiting patterns

### Per-IP

```haproxy
frontend http_front
    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
```

### Login-endpoint protection

```haproxy
    acl login_page path_beg /login
    acl too_many_logins sc_http_req_rate(0) gt 10
    http-request deny deny_status 429 if login_page too_many_logins
```

### Graduated (tarpit then deny)

```haproxy
    http-request tarpit if { sc_http_req_rate(0) gt 50 }
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 200 }
    http-request deny deny_status 429 if { sc_conn_cur(0) gt 100 }
```

### Abuse detection (error-based)

```haproxy
    stick-table type ip size 50k expire 1m store http_err_rate(1m),http_req_rate(1m)
    http-request track-sc0 src
    acl high_error_rate sc_http_err_rate(0) gt 50
    acl significant_traffic sc_http_req_rate(0) gt 20
    http-request deny deny_status 403 if high_error_rate significant_traffic
```

## Connection management

### Cookie persistence

```haproxy
backend app_backend
    balance roundrobin
    cookie SERVERID insert indirect nocache httponly secure
    server app1 192.168.10.11:8080 check cookie s1
    server app2 192.168.10.12:8080 check cookie s2
```

`insert` (HAProxy adds it), `indirect` (not passed to the backend), `nocache`, `httponly` (no JS access), `secure` (HTTPS only).

### Connection reuse

```haproxy
defaults
    http-reuse safe
```

Modes: `never`, `safe` (idle only, the safe default), `aggressive`, `always`.

### Timeouts

```haproxy
defaults
    timeout connect  5s
    timeout client   30s
    timeout server   30s
    timeout http-request 10s
    timeout http-keep-alive 5s
    timeout queue    30s
    timeout tunnel   1h
    retries 3
```

Keep `timeout connect` short (3-5s); set client/server by application behaviour (longer for uploads/downloads); `timeout http-request` defends against slowloris; `timeout tunnel` covers WebSocket sessions.

## Performance tuning

```haproxy
global
    maxconn 50000
    nbthread 4
    cpu-map auto:1/1-4 0-3
    tune.bufsize 16384
    tune.maxrewrite 1024
    tune.ssl.cachesize 50000
    tune.ssl.lifetime 300
    tune.ssl.maxrecord 0
```

Per-server limits and resilience:

```haproxy
backend app_backend
    server app1 192.168.10.11:8080 check maxconn 500 maxqueue 100
    timeout queue 10s
    retries 3
    option redispatch
```

## Stats monitoring

```haproxy
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:secure_password
    stats admin if TRUE
```

Watch: Scur/Smax (current/max sessions), Slim (limit), SessRate, Bin/Bout, Dreq/Dresp (denied), Ereq/Econ/Eresp (errors), Status (UP/DOWN/NOLB/MAINT), Chkfail/Chkdown (health-check failures/down events).

## Common patterns

### API gateway

Versioned routing plus rate limiting and CORS:

```haproxy
frontend api_gateway
    bind *:443 ssl crt /etc/ssl/api.pem
    acl is_v1 path_beg /api/v1/
    acl is_v2 path_beg /api/v2/
    stick-table type ip size 100k expire 1m store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
    use_backend api_v1 if is_v1
    use_backend api_v2 if is_v2
    default_backend api_v2
```

### Database load balancing

```haproxy
listen mysql_cluster
    mode tcp
    bind *:3306
    balance leastconn
    option tcp-check
    server db1 192.168.10.20:3306 check inter 5s
    server db2 192.168.10.21:3306 check inter 5s backup
```

### WebSocket

```haproxy
backend ws_backend
    balance source
    timeout tunnel 1h
    timeout server 1h
    server ws1 192.168.10.30:8080 check
    server ws2 192.168.10.31:8080 check
```

## Kubernetes ConfigMap globals

```yaml
data:
  maxconn: "50000"
  nbthread: "4"
  ssl-min-ver: "TLSv1.2"
  timeout-connect: "5s"
  timeout-client: "30s"
  timeout-server: "30s"
  syslog-server: "address:10.0.0.5:514, facility:local0"
```

## Operational checklist

- **Daily:** all servers UP on the stats page; error counts (Ereq/Econ/Eresp) not trending; session rates within range.
- **Weekly:** stick-table fill percentage; SSL certificate expiry; queue depths (sustained queuing means capacity pressure); log volume and destination health.
- **Monthly:** prune unused backends/servers; maxconn utilisation trend (capacity planning); test a reload (verify zero-downtime); revisit rate-limit thresholds against real traffic.
