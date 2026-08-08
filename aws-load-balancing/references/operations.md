# AWS load-balancer operations and selection

Which load-balancer type to choose, the standard composition patterns, the cross-zone cost trade-off, monitoring, and the common-pitfalls catalogue. Internals are in `elb-architecture.md`; configuration in `configuration-and-integration.md`.

## Choosing the LB type

| Need | Choose |
|---|---|
| HTTP/HTTPS/gRPC content routing, WAF, Cognito, Lambda targets | ALB |
| Fixed IPs (firewall rules, DNS pinning) | NLB |
| TCP/UDP services (databases, game servers, IoT, MQTT) | NLB |
| Ultra-low latency (trading, real-time) | NLB |
| PrivateLink service exposure across VPCs/accounts | NLB |
| TLS passthrough (backend owns TLS) or QUIC | NLB |
| Very high throughput (millions of req/s) | NLB |
| Transparent security-appliance insertion (firewall, IDS/IPS, DLP) | GWLB |

mTLS, Lambda targets, and Cognito are ALB-only. PrivateLink and QUIC are NLB-only. When in doubt about cloud-vs-self-managed, return to `load-balancer-selection`.

## When to use NLB over ALB

Clients needing fixed IPs; raw TCP/UDP; ultra-low latency; PrivateLink; TLS passthrough; very high throughput.

## Composition patterns

### NLB + ALB (static IP + L7)

```
Internet -> NLB (static / Elastic IPs) -> ALB (L7 routing, WAF, Cognito) -> targets
```

Register the ALB as an NLB target (ALB-type target group) to combine fixed IPs with L7 features.

### ALB + CloudFront

```
Internet -> CloudFront (CDN) -> ALB (origin) -> targets
```

CloudFront caches static content at the edge; the ALB serves dynamic requests. Use a custom origin header so the ALB can verify requests came from CloudFront. The CloudFront ACM certificate must be in us-east-1.

### GWLB + Transit Gateway (centralised inspection)

```
Spoke VPCs -> Transit Gateway -> security VPC -> GWLB -> appliance fleet
```

Centralises security inspection for all VPC traffic; Transit Gateway routes through the security VPC; GWLB distributes across the appliance ASG with symmetric hashing.

## Cross-zone load balancing

| Setting | ALB | NLB | GWLB |
|---|---|---|---|
| Default | Enabled (always) | Disabled | Disabled |
| Enabled | Even across all AZs | Even, but may add inter-AZ transfer cost | Even to appliances |
| Disabled | N/A | Each AZ serves local targets only | Each AZ routes to local appliances |

Cross-zone traffic on NLB/GWLB incurs inter-AZ data-transfer charges; weigh cost against distribution evenness. Disabled cross-zone with uneven targets per AZ causes hot spots.

## Monitoring (CloudWatch)

Watch `RequestCount`, `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, `HealthyHostCount`/`UnHealthyHostCount`, `ActiveConnectionCount`, and `RejectedConnectionCount`. Enable access logs from day one (request-level on ALB, connection-level on NLB) and apply an S3 lifecycle policy for cost. Use `describe-target-health` for current target state. An ALB is also an L7 span boundary: see `distributed-tracing`.

## Common pitfalls

1. **ALB for TCP services** - ALB only supports HTTP/HTTPS/gRPC; use NLB for raw TCP/UDP.
2. **NLB without cross-zone** - disabled by default; uneven targets across AZs cause hot spots. Enable cross-zone or balance targets evenly.
3. **GWLB GENEVE mismatch** - appliances must support GENEVE with the AWS TLV format (0x0108) on UDP 6081; verify before deployment.
4. **Slow health-check intervals** - NLB minimum is 10s; with unhealthy threshold 3, detection takes 30s+. Plan failover around it.
5. **Security-group confusion** - ALB requires a security group; NLB has none (traffic passes through), so target security groups must admit the client/LB subnet.
6. **ACM region mismatch** - the certificate must be in the LB's region; CloudFront requires us-east-1.
7. **PrivateLink requires NLB** - ALB and GWLB cannot be PrivateLink endpoints directly.
8. **Ignoring access logs** - they hold the latency, error-code, and client-IP data you need to debug; enable from day one.

## Boundary with the network-security audit

This skill configures the load balancer. The VPC-side security review (security-group rules, ENI/subnet placement, public-exposure assessment, NACLs) belongs to `aws-networking-audit`, which already defers ALB/NLB configuration content here. Broader AWS service-selection and cost framing belongs to `aws-cloud-ops`, which already defers load-balancer depth here. Keep the two boundaries clean: configure here, audit exposure there.
