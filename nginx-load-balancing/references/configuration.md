# NGINX configuration (load-balancer role)

The working `nginx.conf` for reverse proxying and load balancing: upstream blocks, balancing methods, server parameters, passive health, SSL termination, rate and connection limiting, proxy caching, the stream module, and tuning. Internals are in `architecture.md`; Plus and Kubernetes in `ingress-and-plus.md`.

## Upstream and reverse proxy

```nginx
upstream app_backend {
    least_conn;
    server 192.168.10.11:8080 weight=3;
    server 192.168.10.12:8080 weight=2;
    server 192.168.10.13:8080 backup;
    keepalive 32;              # idle keepalive connections PER WORKER
    keepalive_requests 1000;
    keepalive_timeout 60s;
}

server {
    listen 80;
    server_name app.example.com;
    location / {
        proxy_pass http://app_backend;
        proxy_http_version 1.1;            # required for upstream keepalive
        proxy_set_header Connection "";     # required for upstream keepalive
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port  $server_port;
        proxy_connect_timeout 5s;
        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
    }
}
```

`keepalive` is per worker: with 4 workers and `keepalive 32`, up to 128 idle upstream connections. `proxy_http_version 1.1` plus `proxy_set_header Connection ""` are mandatory for keepalive (HTTP/1.0 defaults to `Connection: close`).

### Balancing methods (OSS)

| Method | Directive | Description |
|---|---|---|
| Round-robin | (default) | Sequential distribution |
| Least connections | `least_conn` | Fewest active connections |
| IP hash | `ip_hash` | Client-IP affinity |
| Generic hash | `hash $key` | Hash of any variable (URI, cookie); add `consistent` for the hash ring |
| Random | `random` | Random; `random two least_conn` for power-of-two |

### Server parameters

| Parameter | Description |
|---|---|
| `weight=N` | Relative weight |
| `backup` | Used only when all primaries are down |
| `down` | Permanently unavailable |
| `max_fails=N` | Failures before temporary unavailability (passive health, default 1) |
| `fail_timeout=Ns` | Failure-count window and unavailability duration (default 10s) |
| `max_conns=N` | Concurrent-connection limit to the server |
| `slow_start=Ns` | Ramp traffic to a recovered server (Plus only) |

### Passive health checks (OSS)

OSS detects failure only from real traffic: `max_fails` failed requests within `fail_timeout` mark the server down for `fail_timeout`. The limitation is that failures are caught only after user requests fail; for proactive checks use NGINX Plus active health checks (see `ingress-and-plus.md`).

### Timeouts and buffering

```nginx
location / {
    proxy_connect_timeout 5s;     # keep short; slow connect means an overloaded upstream
    proxy_read_timeout    60s;    # API 30-60s; uploads 300s+; WebSocket 3600s+
    proxy_send_timeout    60s;
    proxy_buffering on;           # buffer the response, freeing the upstream quickly (default)
    proxy_buffer_size 4k;
    proxy_buffers 8 8k;
}
```

Turn buffering off for streaming/real-time responses. For large uploads raise `client_max_body_size` and consider `proxy_request_buffering`.

## SSL/TLS termination

```nginx
server {
    listen 443 ssl http2;
    server_name secure.example.com;
    ssl_certificate      /etc/ssl/certs/fullchain.pem;
    ssl_certificate_key  /etc/ssl/private/privkey.pem;
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;    # TLS 1.3 ignores this
    ssl_session_cache    shared:SSL:10m;
    ssl_session_timeout  1d;
    ssl_session_tickets  off;          # off for forward secrecy
    ssl_stapling         on;
    ssl_stapling_verify  on;
    ssl_trusted_certificate /etc/ssl/certs/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
}
```

HTTP-to-HTTPS redirect: a port-80 server block with `return 301 https://$host$request_uri;`. Multi-domain SNI is one server block per domain, each with its own certificate. The private key belongs in the secret store (see `secrets-hygiene`); issuance and renewal are `cert-manager` / `lets-encrypt`.

## Rate limiting and connection limiting

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $http_authorization zone=api_user:10m rate=100r/s;

location /api/ {
    limit_req zone=api burst=20 nodelay;
    limit_req zone=api_user burst=50 nodelay;
    limit_req_status 429;
    proxy_pass http://api_backend;
}
```

`rate` is the sustained rate per key, `burst` allows a spike, `nodelay` processes the burst immediately (omit to queue). Use `$binary_remote_addr` (16 bytes) over `$remote_addr`. Use `nodelay` for APIs (fail fast); omit for web pages (queue and serve slowly). Connection limiting:

```nginx
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
location / { limit_conn conn_limit 10; }
```

## Proxy caching

```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=app_cache:10m max_size=1g inactive=60m use_temp_path=off;

location / {
    proxy_cache app_cache;
    proxy_cache_valid 200 10m;
    proxy_cache_valid 301 302 1h;
    proxy_cache_valid 404 1m;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503;
    proxy_cache_background_update on;
    proxy_cache_lock on;
    add_header X-Cache-Status $upstream_cache_status always;
    proxy_pass http://app_backend;
}
```

`proxy_cache_use_stale` serves stale on backend failure (resilience), `proxy_cache_lock` stops a cache stampede, `proxy_cache_background_update` refreshes asynchronously. Cache-key examples and per-user bypass:

```nginx
proxy_cache_key "$scheme$request_method$host$request_uri";
proxy_cache_bypass $cookie_session;
proxy_no_cache $cookie_session;
```

Monitor `$upstream_cache_status` (HIT/MISS/BYPASS/STALE/UPDATING/REVALIDATED).

## Stream (L4) proxying

```nginx
stream {
    upstream db_backend {
        server 192.168.10.20:5432;
        server 192.168.10.21:5432;
    }
    server {
        listen 5432;
        proxy_pass db_backend;
        proxy_connect_timeout 5s;
    }
}
```

Use for database load balancing, MQTT, custom TCP protocols, and DNS (UDP).

## Performance tuning

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;
events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

large_client_header_buffers 4 16k;   # large cookies / auth tokens
client_max_body_size 10m;            # uploads
proxy_buffer_size 8k;
proxy_buffers 16 8k;

access_log /var/log/nginx/access.log combined buffer=32k flush=5s;
location /health { access_log off; return 200 "ok"; }
```

## Monitoring (OSS stub_status)

```nginx
server {
    listen 127.0.0.1:8080;
    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
```

Exposes active connections, accepts, handled, requests, reading/writing/waiting. Watch active connections (> 80% of `worker_connections * worker_processes`), waiting (many idle keepalive), 5xx rate (> 1%), and cache hit rate (< 80% for cacheable content). The richer per-upstream Plus API is in `ingress-and-plus.md`.
