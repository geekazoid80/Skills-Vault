# AWS Elastic Load Balancing architecture

How ALB, NLB, and GWLB work internally: request and packet processing, the GENEVE protocol, target-group mechanics, health-check timing, access-log formats, and cost components. Configuration is in `configuration-and-integration.md`; selection and operations in `operations.md`.

All three are fully managed, with built-in HA, auto-scaling, and AWS integration.

## Application Load Balancer (ALB, L7)

### Request processing

```
Client HTTPS request
  -> ALB node (per-AZ)
     -> TLS termination (ACM certificate)
     -> WAF evaluation (if attached)
     -> listener-rule evaluation (priority-ordered)
          rule 1: path=/api/*  -> forward api-tg
          rule 2: host=admin.* -> authenticate(Cognito) + forward admin-tg
          default:                forward web-tg
     -> target-group selection
     -> algorithm (round_robin or least_outstanding_requests)
     -> health filter (skip unhealthy)
     -> forward to target (EC2, IP, Lambda)
```

ALB provisions managed nodes in each configured AZ, auto-scaling transparently; the DNS name resolves to node IPs that change as nodes scale. Cross-zone load balancing is always enabled and cannot be disabled on ALB.

### Listener rules

Evaluated in priority order (1-50000, lowest first):

- **Conditions:** path-pattern, host-header, http-header, query-string, source-ip, http-request-method. Multiple conditions on a rule are AND; multiple values within a condition are OR.
- **Actions:** forward, redirect, fixed-response, authenticate-cognito, authenticate-oidc.

### Sticky sessions

- **Duration-based (`lb_cookie`):** ALB generates an `AWSALB` cookie, duration 1s to 7 days.
- **Application-based (`app_cookie`):** ALB reads an application-generated cookie and pins to the same target.

### Connection handling

Idle timeout default 60s (1-4000s); deregistration delay default 300s (connection draining); slow start 0-900s (ramp traffic to new targets); HTTP/2 on the frontend with HTTP/1.1 to the backend by default; full gRPC support including health checks and routing by package/service/method.

### Integrations and 2025 features

AWS WAF v2 attaches directly (managed OWASP/Bot-Control/ATP rule groups, custom IP/geo/regex/rate rules, allow/block/count/CAPTCHA/challenge actions). Cognito offloads auth (redirect to login, validate JWT, add `x-amzn-oidc-*` headers). 2025: regex URL/host rewrite before forwarding, and Target Optimizer routing AI/ML inference by concurrency to avoid GPU contention.

## Network Load Balancer (NLB, L4)

### Packet processing

```
Client TCP SYN
  -> NLB node (per-AZ, static IP)
     -> no L7 inspection
     -> flow hash: src IP, src port, dst IP, dst port, protocol
     -> target selection (same flow -> same target for the connection)
     -> health check
     -> forward to target (client IP preserved by default)
```

Nodes have static IPs per AZ (optionally Elastic IPs for fixed public addresses). NLB has no security groups (traffic passes through); client IP is preserved by default (no SNAT for instance targets). It handles millions of requests per second at minimal latency.

### Static IP, TLS, PrivateLink

Static/Elastic IPs let clients hardcode firewall rules or DNS. TLS modes: termination (NLB terminates, plaintext to targets), passthrough (target handles TLS), and mTLS is NOT supported on NLB (use ALB). PrivateLink requires NLB as the entry point: the consumer creates an interface VPC endpoint pointing at the NLB service, traffic stays on the AWS backbone, cross-account and cross-region supported.

### Weighted target groups and QUIC

Weighted target groups (Nov 2025) bring canary and blue-green to TCP services. QUIC pass-through forwards UDP 443 to targets unmodified for HTTP/3 (connection migration, 0-RTT).

## Gateway Load Balancer (GWLB, L3)

### Packet flow

```
1. Route table directs traffic to a GWLB endpoint (GWLBE)
2. GWLBE forwards to the GWLB
3. GWLB encapsulates in GENEVE, sends to an appliance
4. Appliance inspects, re-encapsulates the response in GENEVE
5. GWLB decapsulates, forwards to the original destination
6. Return traffic follows the symmetric path (same appliance)
```

### GENEVE protocol

Outer UDP: hash-based source port (for ECMP), destination port 6081. GENEVE header: version 0, protocol type 0x6558 (transparent Ethernet bridging), a GWLB-assigned VNI, and an AWS option (type 0x0108) carrying flow metadata (VPC, subnet, ENI, flow hash). The inner original IP packet is preserved intact.

### Symmetric hashing and endpoints

GWLB uses a 5-tuple hash to pick an appliance, and it is symmetric: forward and return paths hash to the same appliance, which is essential for stateful inspection. If an appliance fails, flows redistribute (existing connections may break). GWLB endpoints are ENIs in the application VPC; route-table entries direct traffic through them; GWLB and the appliance ASG can live in a separate security VPC, with cross-account support via PrivateLink. Appliances must support GENEVE encap/decap on UDP 6081, the AWS TLV (0x0108), GWLB health checks, and inline forwarding.

## Target groups

### Target types

| Type | ALB | NLB | GWLB |
|---|---|---|---|
| Instance | Yes | Yes | Yes |
| IP | Yes | Yes | Yes |
| Lambda | Yes | No | No |
| ALB | No | Yes | No |

IP targets reach private IPs in peered/Transit-Gateway VPCs and on-prem over VPN/Direct Connect; ECS Fargate and EKS pods (VPC CNI) register as IP targets.

### Attributes and draining

Deregistration delay default 300s (connection draining); optional connection termination on deregistration. Key attributes: `stickiness.enabled` and `.type` (`lb_cookie`/`app_cookie`), `slow_start.duration_seconds`, `load_balancing.algorithm.type` (`round_robin`/`least_outstanding_requests`), `deregistration_delay.timeout_seconds`.

## Health checks

### Timing maths

```
time to detect unhealthy = interval x unhealthy_threshold
  ALB default: 15s x 3 = 45s
  NLB default: 30s x 3 = 90s
time to restore healthy = interval x healthy_threshold
  ALB: 15s x 2 = 30s ; NLB: 30s x 2 = 60s
```

| Parameter | ALB range | NLB range |
|---|---|---|
| Interval | 5-300s | 10-300s |
| Timeout | 2-120s | 2-120s |
| Healthy threshold | 2-10 | 2-10 |
| Unhealthy threshold | 2-10 | 2-10 |
| Matcher | HTTP 200-499 | HTTP codes or TCP success |

ALB checks send `GET /healthz` with `User-Agent: ELB-HealthChecker/2.0`; a 200 marks healthy (once the threshold is met), a 503 marks unhealthy.

## Access logging

- **ALB (request-level, to S3):** type, timestamp, elb, client:port, target:port, the three processing-time fields, elb and target status codes, bytes, request line, user agent, SSL cipher and protocol, target-group ARN, trace id, domain name, chosen cert ARN, matched rule priority, actions executed, redirect URL, error reason.
- **NLB (connection-level):** type, version, timestamp, elb, listener, client:port, destination:port, connection and TLS-handshake times, bytes, TLS alert, chosen cert, cipher and protocol, named group, domain name, ALPN fields.

## Cost

ALB bills hourly + LCU (new and active connections, processed bytes, rule evaluations); NLB hourly + NLCU; GWLB hourly + GLCU. NLB and GWLB cross-zone traffic incurs standard inter-AZ data-transfer charges; ALB cross-zone is always on at no extra charge. See `operations.md` for the cross-zone trade-off.
