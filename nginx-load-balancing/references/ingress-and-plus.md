# NGINX Plus features and the Kubernetes Ingress Controller

The NGINX Plus extras (active health checks, sticky sessions, live API, key-value store, JWT) and the F5 NGINX Ingress Controller for Kubernetes (Ingress resources, the CRDs, canary/blue-green, ConfigMap, migration). Base configuration is in `configuration.md`; internals in `architecture.md`.

## NGINX Plus features

Active health checks, sticky sessions, the live API, and the key-value store all need a `zone` directive in the upstream block. Without it they silently fail.

### Active health checks

```nginx
upstream app_backend {
    zone backend 64k;
    server 192.168.10.11:8080;
    server 192.168.10.12:8080;
}

server {
    location / {
        proxy_pass http://app_backend;
        health_check interval=5s fails=3 passes=2 uri=/health;
    }
}
```

Probes run regardless of client traffic and detect failure before a user is affected. Custom validation via a `match` block:

```nginx
match app_healthy {
    status 200;
    header Content-Type ~ "application/json";
    body ~ '"status":"ok"';
}

location / {
    proxy_pass http://app_backend;
    health_check match=app_healthy interval=5s;
}
```

### Session persistence

```nginx
upstream app_backend {
    zone backend 64k;
    server 192.168.10.11:8080;
    server 192.168.10.12:8080;
    sticky cookie srv_id expires=1h domain=.example.com path=/;
}
```

Three methods: `sticky cookie` (NGINX inserts a cookie naming the server), `sticky learn` (learns an app-set cookie such as `JSESSIONID`), `sticky route` (routes on a cookie or URI value).

### Live activity API

```nginx
server {
    listen 8080;
    location /api/ {
        api write=on;
        allow 10.0.0.0/8;
        deny all;
    }
}
```

Endpoints include `/api/8/http/upstreams`, `/api/8/stream/upstreams`, `/api/8/connections`, `/api/8/ssl`, plus per-server-zone and per-cache metrics in JSON. The write API enables dynamic upstream management without reload. Lock it down to a management network and keep the access token in the secret store (see `secrets-hygiene`).

### Key-value store

```nginx
keyval_zone zone=blocklist:1m;
keyval $remote_addr $blocked zone=blocklist;
server { if ($blocked) { return 403; } }
```

Keys are set/updated over the REST API without reload. Used for dynamic blocklists, feature flags, and A/B testing.

### JWT authentication

```nginx
server {
    auth_jwt "API Access";
    auth_jwt_key_file /etc/nginx/jwk.json;
    location /api/v1/ {
        auth_jwt_claim_set $user sub;
        proxy_set_header X-User $user;
    }
}
```

## Kubernetes Ingress Controller

Use the official F5 NGINX Ingress Controller (`nginx/kubernetes-ingress`). The community ingress-nginx project was retired in November 2025; do not start new deployments on it.

### Standard Ingress resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.org/proxy-connect-timeout: "10s"
    nginx.org/proxy-read-timeout: "60s"
spec:
  ingressClassName: nginx
  tls:
  - hosts: [app.example.com]
    secretName: app-tls
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

The `secretName` TLS secret is typically issued by cert-manager (see `cert-manager`).

### VirtualServer CRD (advanced routing)

```yaml
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: app-vs
spec:
  host: app.example.com
  upstreams:
  - name: app-v1
    service: app-v1-service
    port: 80
  - name: app-v2
    service: app-v2-service
    port: 80
  routes:
  - path: /
    splits:
    - weight: 90
      action:
        pass: app-v1
    - weight: 10
      action:
        pass: app-v2      # canary
```

VirtualServer adds traffic splitting (canary), custom error pages, per-route rate limiting, advanced health checks, and circuit-breaker patterns over standard Ingress. VirtualServerRoute delegates routing for multi-team ownership; TransportServer does TCP/UDP (L4).

### Deployment patterns

Canary: split weights across stable and canary upstreams (e.g. 95/5). Blue-green: a single `active` upstream whose `service` is switched between green and blue. Multi-team: a platform-owned VirtualServer delegating `/api` and `/web` to team namespaces via VirtualServerRoute.

### ConfigMap globals

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-config
  namespace: nginx-ingress
data:
  proxy-connect-timeout: "10s"
  worker-processes: "auto"
  ssl-protocols: "TLSv1.2 TLSv1.3"
```

### Migration from community ingress-nginx to F5

1. Install the F5 NGINX Ingress Controller alongside the existing ingress.
2. Create equivalent VirtualServer CRDs for each Ingress resource.
3. Update `ingressClassName` from `nginx` to the F5 controller's class name.
4. Map community annotations to F5 annotations (similar but not identical).
5. Test each service against the new controller.
6. Switch DNS/service to the new controller.
7. Remove the old community deployment.

## Monitoring (Plus API)

```nginx
server {
    listen 8080;
    location /api/ { api write=on; allow 10.0.0.0/8; deny all; }
    location /dashboard.html { root /usr/share/nginx/html; }
}
```

Exposes per-upstream, per-server-zone, per-cache, per-SSL, and per-resolver metrics in JSON. Alert on upstream response time over SLA, any upstream server down, sustained SSL handshake failures, and cache hit rate below target.
