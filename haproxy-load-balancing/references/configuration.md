# HAProxy configuration

The working `haproxy.cfg`: the section structure, frontend/backend stanzas, ACL routing, stick-table rate limiting, health checks, SSL offload, L4 vs L7 mode, balance algorithms, and the runtime API commands. Architecture internals are in `architecture.md`; production tuning and patterns in `operations-and-tuning.md`.

## Configuration structure

```
global          # process-level: threading, SSL, logging, resource limits
defaults        # inherited by all frontends/backends
frontend        # listener: accepts client connections
backend         # server pool: forwards traffic
listen          # combined frontend + backend (shorthand)
```

### Frontend

```haproxy
frontend http_front
    bind *:80
    bind *:443 ssl crt /etc/ssl/example.pem alpn h2,http/1.1

    http-request redirect scheme https unless { ssl_fc }

    acl is_api path_beg /api/
    use_backend api_backend if is_api
    default_backend web_backend
```

### Backend

```haproxy
backend web_backend
    balance leastconn
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.internal
    http-check expect status 200

    server web1 192.168.10.11:8080 check weight 10
    server web2 192.168.10.12:8080 check weight 10
    server web3 192.168.10.13:8080 check weight 5 backup
```

### Listen (stats page)

```haproxy
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:password
```

## ACL routing

ACLs are named conditions for routing, blocking, and traffic control:

```haproxy
frontend http_front
    acl is_api          path_beg /api/
    acl is_admin        path_beg /admin/
    acl is_mobile       hdr_sub(User-Agent) -i Mobile
    acl internal_src    src 10.0.0.0/8 192.168.0.0/16
    acl has_auth        req.hdr(Authorization) -m found
    acl is_post         method POST

    use_backend api_backend    if is_api
    use_backend admin_backend  if is_admin internal_src
    http-request deny          if is_admin !internal_src
    default_backend web_backend
```

Matching methods: `path_beg`/`path_end`/`path_reg`; `hdr()`/`hdr_beg()`/`hdr_sub()`/`hdr_reg()`; `src`; `ssl_fc` (boolean); `method`; `-m found` (existence); `-i` (case-insensitive). Rules are first-match top-down: order specific before broad.

## Stick tables

### Rate limiting

```haproxy
frontend http_front
    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
```

### Session tracking and persistence

```haproxy
backend app_backend
    stick-table type ip size 100k expire 10m store conn_cur,http_req_rate(1m),http_err_rate(1m)
    stick on src
    server app1 192.168.10.11:8080 check
    server app2 192.168.10.12:8080 check
```

Data types: `conn_cur`, `conn_rate(period)`, `http_req_rate(period)`, `http_err_rate(period)`, `gpc0`/`gpc1`, `gpt0`, `bytes_in_rate`/`bytes_out_rate`. Size the table for the expected unique-client count, or new entries are rejected once it fills.

## Health checks

### HTTP

```haproxy
backend app_backend
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.internal
    http-check expect status 200
    http-check expect string "healthy"
    server app1 192.168.10.11:8080 check inter 2s rise 2 fall 3
```

Parameters: `inter` (interval, default 2s), `rise` (successes to mark UP, default 2), `fall` (failures to mark DOWN, default 3), `fastinter` (faster during transition), `downinter` (slower while down).

### TCP

```haproxy
backend db_backend
    mode tcp
    option tcp-check
    server db1 192.168.10.20:5432 check inter 5s
```

### External script

```haproxy
backend custom_backend
    option external-check
    external-check command /usr/local/bin/check_app.sh
    server app1 192.168.10.11:8080 check inter 10s
```

## SSL/TLS offload

```haproxy
global
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2
    tune.ssl.default-dh-param 2048

frontend https_front
    bind *:443 ssl crt /etc/ssl/certs/bundle.pem alpn h2,http/1.1
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-SSL-Client-CN %{+Q}[ssl_c_s_dn(cn)]
    default_backend app_backend
```

### SNI-based routing

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/ssl/certs/ strict-sni
    use_backend api_backend if { ssl_fc_sni api.example.com }
    use_backend web_backend if { ssl_fc_sni www.example.com }
    default_backend default_web
```

## L4 (TCP) vs L7 (HTTP) mode

### TCP mode (L4)

```haproxy
frontend db_front
    mode tcp
    bind *:5432
    default_backend db_backend

backend db_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server db1 192.168.10.20:5432 check
    server db2 192.168.10.21:5432 check
```

Use for databases (PostgreSQL, MySQL, Redis), SMTP, and custom TCP protocols.

### HTTP mode (L7)

```haproxy
frontend web_front
    mode http
    bind *:80
    default_backend web_backend

backend web_backend
    mode http
    balance leastconn
    option httpchk
    server web1 192.168.10.11:8080 check
```

Use for web applications, APIs, and any HTTP/HTTPS traffic needing content-based decisions. Match `mode` between frontend and backend.

## Balance algorithms

| Algorithm | Directive | Description |
|---|---|---|
| Round-robin | `balance roundrobin` | Sequential with weights |
| Static round-robin | `balance static-rr` | No dynamic weight changes; faster |
| Least connections | `balance leastconn` | Fewest active connections |
| Source | `balance source` | Client-IP hash (affinity) |
| URI | `balance uri` | URI hash (cache optimisation) |
| Header | `balance hdr(name)` | HTTP header hash |
| Random | `balance random` | Random; `random(2)` for power-of-two |
| First | `balance first` | Fill the first server before the next |
| RDP cookie | `balance rdp-cookie(name)` | RDP session persistence |

## Runtime API commands

Enable the socket (see `architecture.md` for access levels):

```haproxy
global
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
```

```bash
echo "show info"   | socat stdio /run/haproxy/admin.sock
echo "show stat"   | socat stdio /run/haproxy/admin.sock
echo "disable server app_backend/app1" | socat stdio /run/haproxy/admin.sock
echo "enable server app_backend/app1"  | socat stdio /run/haproxy/admin.sock
echo "set weight app_backend/app1 50"  | socat stdio /run/haproxy/admin.sock
echo "show table app_backend"          | socat stdio /run/haproxy/admin.sock
echo "clear table app_backend"         | socat stdio /run/haproxy/admin.sock
```

These change the running process only; a reload reverts to `haproxy.cfg`.

## Kubernetes Ingress Controller

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    haproxy.org/load-balance: "leastconn"
    haproxy.org/timeout-connect: "5s"
    haproxy.org/rate-limit-requests: "100"
    haproxy.org/rate-limit-period: "1m"
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

Standard Ingress resources with HAProxy-specific annotations, native stick-table session persistence, dynamic reconfiguration via ConfigMap + CRD, and the same balance algorithms (roundrobin, leastconn, source, uri, hdr). Tuning annotations and ConfigMap globals are in `operations-and-tuning.md`.
