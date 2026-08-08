# TLS handling, content switching, and traffic management

Where TLS terminates and why, plus the L7 traffic-management features a load balancer applies once it can read the request: content routing, rate limiting, caching, and WAF placement.

## SSL/TLS offload

### How offload works

The load balancer terminates the client TLS connection and forwards plaintext HTTP to the backend:

```
Client --[HTTPS/TLS]--> Load balancer --[HTTP]--> Backend
                              |
                  (TLS termination, certificate
                   management, cipher enforcement)
```

1. Client opens a TLS handshake with the load balancer.
2. The load balancer presents the server certificate and establishes the session.
3. It decrypts the request and makes its routing decision.
4. It forwards plaintext HTTP to the chosen backend.
5. The backend replies in plaintext; the load balancer re-encrypts to the client.

### Why offload

- Centralised certificate management: one certificate on the load balancer instead of one per server.
- CPU relief: the TLS handshake is expensive; offloading frees backend CPU for the application.
- L7 visibility: the load balancer can inspect content for routing, WAF, and compression.
- Consistent cipher policy applied at a single point.
- Protocol negotiation: the load balancer can speak HTTP/2 and HTTP/3 to clients while backends serve HTTP/1.1.

## Termination models: offload vs passthrough vs re-encryption

- **Offload (termination):** decrypt at the load balancer, plaintext to the backend. Maximum L7 capability; backend trusts the internal network.
- **Passthrough:** the load balancer forwards encrypted traffic untouched (L4); the backend owns the TLS session. No L7 visibility, no offload, but end-to-end client-to-backend encryption with no decryption in between.
- **Re-encryption (end-to-end TLS):** terminate the client TLS, then open a fresh TLS connection to the backend:

```
Client --[TLS 1.3]--> LB --[TLS 1.2/1.3]--> Backend
```

The load balancer keeps full L7 visibility for routing and security, the backend certificate can come from an internal CA, and the cost is double TLS processing. Choose re-encryption when compliance mandates encryption on the wire to the backend but you still need L7 features.

## TLS best practices (all platforms)

- Minimum TLS 1.2 (prefer TLS 1.3 for performance and security).
- Disable weak ciphers (RC4, 3DES, MD5, NULL).
- Enable OCSP stapling to cut client-side validation latency.
- Send HSTS (`Strict-Transport-Security: max-age=31536000`).
- Redirect HTTP to HTTPS at the load balancer.
- Re-encrypt to the backend when compliance requires it.

Certificate issuance and renewal are out of scope here: see `cert-manager` (Kubernetes) and `lets-encrypt` (public ACME). Private keys belong in the secret store, never inline in a config: see `secrets-hygiene`.

## Content switching

Once an L7 load balancer can read the request, it routes on content:

- **Path-based:** `/api/*` to the API pool, `/static/*` to the asset pool.
- **Host-based:** route by the `Host` header to serve many sites from one VIP.
- **Header / method / cookie:** route by arbitrary headers, HTTP method, or cookie value (canary releases, A/B testing, tenant routing).
- **Weighted:** split traffic by proportion across pools for blue-green and canary rollouts.

## Rate limiting

Most load balancers use the **token-bucket** algorithm: a bucket holds N tokens (burst), refills at R tokens/second (sustained rate), each request spends one token, and an empty bucket means excess requests are rejected (429) or queued.

| Strategy | Scope | Use case |
|---|---|---|
| Per-IP | Client IP | Stop individual client abuse |
| Per-user | Auth token / cookie | Enforce API quotas per user |
| Per-URI | Request path | Protect expensive endpoints |
| Global | All traffic | Shield the backend from total overload |

Implementations: NGINX `limit_req_zone` + `limit_req` (token bucket with burst and `nodelay`); HAProxy stick tables with an `http_req_rate` counter plus an ACL-based deny; F5 iRules, AFM rate limiting, or rate-shaping profiles.

## Caching at the load balancer

Cache static assets, identical public API responses, and content with explicit cache headers to cut backend load. Support varies: NGINX has a robust proxy cache (`proxy_cache_path`, `proxy_cache_valid`, stale-while-revalidate); HAProxy has no built-in cache (front it with Varnish); F5 offers a RAM-cache profile (WebAccelerator for advanced caching).

## WAF placement

A web application firewall belongs at the L7 load balancer, where traffic is decrypted and parsed. Options differ by platform: F5 ASM (built-in), NGINX App Protect (Plus), HAProxy Enterprise WAF or an external WAF, AWS WAF on ALB, Azure WAF v2 on Application Gateway, Envoy `ext_authz`. Place the WAF after TLS termination so it inspects plaintext; pair it with rate limiting for layered protection.

## Observability

Key metrics to watch, with sensible alert thresholds:

| Metric | Alert threshold |
|---|---|
| Active connections | > 80% of max capacity |
| Request rate | Deviation from baseline |
| Response time (LB to client) | > application SLA (e.g. 500ms) |
| Error rate (4xx/5xx) | > 1% for 5xx |
| Healthy backend count | < minimum healthy threshold |
| SSL handshake rate | > 80% of TLS capacity |
| Connection queue | > 0 sustained |

An L7 load balancer is also a tracing span boundary: propagate trace context and expose upstream latency. See `distributed-tracing`.
