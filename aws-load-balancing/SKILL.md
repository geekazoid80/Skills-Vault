---
name: aws-load-balancing
description: Use for AWS Elastic Load Balancing configuration and operations across Application Load Balancer (ALB, L7), Network Load Balancer (NLB, L4), and Gateway Load Balancer (GWLB, L3 appliance insertion). Covers LB-type selection (ALB for HTTP/HTTPS/gRPC content routing, NLB for TCP/UDP/TLS, static IPs, PrivateLink and ultra-low latency, GWLB for transparent security-appliance insertion), ALB listener rules (path/host/header/query-string/source-IP/method matching, priority ordering, weighted target groups for canary and blue-green, redirect/fixed-response/authenticate actions, URL and host rewrite, Cognito and OIDC auth), target groups (instance/IP/Lambda/ALB target types, health checks, deregistration delay and connection draining, slow start, stickiness lb_cookie vs app_cookie, round_robin vs least_outstanding_requests), NLB capabilities (static IP and Elastic IP per AZ, TLS termination vs passthrough, PrivateLink endpoint, QUIC pass-through, cross-zone behaviour and inter-AZ cost), GWLB internals (GENEVE encapsulation on UDP 6081, symmetric 5-tuple hashing, GWLB endpoints, appliance fleet auto-scaling), health-check parameters and timing, ACM certificates and TLS policies, AWS WAF v2 integration, access logging (ALB request logs, NLB connection logs), CloudWatch metrics, and IaC (Terraform aws_lb / aws_lb_target_group / aws_lb_listener, CloudFormation). References elb-architecture.md, configuration-and-integration.md, operations.md. Triggers include "ALB", "NLB", "GWLB", "AWS load balancer", "Application Load Balancer", "Network Load Balancer", "Gateway Load Balancer", "ELB", "target group", "listener rule", "AWS WAF ALB", "ACM certificate ALB", "PrivateLink NLB", "GENEVE", "cross-zone load balancing", "ELBSecurityPolicy", "aws_lb target group", "weighted target group", "deregistration delay". For vendor-neutral load-balancing DESIGN, algorithm and persistence choice, and platform selection (cloud vs self-managed) see load-balancer-selection; for HAProxy see haproxy-load-balancing; for NGINX see nginx-load-balancing. For the VPC security-group rules and ENI/subnet placement of a public load balancer and its public-exposure audit see aws-networking-audit; for AWS service-selection and cost trade-offs around the load balancer see aws-cloud-ops; for the ACM certificates and PrivateLink secrets see cert-manager and secrets-hygiene. AWS Classic ELB is legacy and out of scope.
license: MIT
metadata:
  version: 1.0.0
---

# AWS load balancing

> **Skill marker**: When applying this skill, begin your reply with `[skill: aws-load-balancing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns AWS Elastic Load Balancing configuration and operations across ALB, NLB, and GWLB. It assumes the design decision (a managed AWS load balancer is the right choice) is made; for that and the cross-platform comparison see `load-balancer-selection`. AWS Classic ELB is legacy and out of scope.

## When to use

- Choosing among ALB (L7), NLB (L4), and GWLB (appliance insertion) for a given AWS workload.
- Configuring ALB listener rules: path/host/header routing, weighted target groups, redirects, Cognito/OIDC auth, URL rewrite.
- Designing target groups: target type (instance/IP/Lambda/ALB), health checks, draining, slow start, stickiness.
- Setting up NLB static IPs, TLS termination vs passthrough, PrivateLink endpoints, or QUIC pass-through.
- Deploying GWLB for third-party firewall/IDS/IPS insertion with GENEVE.
- Wiring AWS WAF, ACM certificates, access logs, and CloudWatch metrics to a load balancer.
- Writing the Terraform/CloudFormation for any of the above.

## When not to use

- **Deciding whether a managed AWS LB is the right choice** versus self-managed HAProxy/NGINX, or choosing L4 vs L7 in the abstract: `load-balancer-selection` owns the design and cross-platform comparison.
- **HAProxy or NGINX**: use `haproxy-load-balancing` or `nginx-load-balancing`.
- **The VPC-side network security of the load balancer** (security-group rules, ENI/subnet placement, public-exposure audit, NACLs): `aws-networking-audit` owns that review. This skill configures the load balancer; that audits how it is exposed.
- **Broader AWS service-selection and cost trade-offs** around the workload: `aws-cloud-ops`.
- **Issuing certificates outside ACM, or storing PrivateLink/API secrets**: `cert-manager`/`lets-encrypt` for non-ACM certificates, `secrets-hygiene` for secret handling.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | ALB/NLB/GWLB request and packet processing, GENEVE, target-group mechanics, cross-zone behaviour, health-check timing | `references/elb-architecture.md` |
| Configuration + integration | listener rules and actions, target types, health-check parameters, ACM/TLS, WAF, Cognito, PrivateLink, stickiness, access logs, Terraform | `references/configuration-and-integration.md` |
| Operations + selection | which LB type, deployment patterns (NLB+ALB, CloudFront, GWLB+TGW), cross-zone cost, CloudWatch monitoring, pitfalls | `references/operations.md` |

## Core model (condensed)

**Three load balancers, three layers.** ALB is L7 (HTTP/HTTPS/gRPC) with content routing, WAF, and auth; NLB is L4 (TCP/UDP/TLS) with static IPs, PrivateLink, and ultra-low latency; GWLB is L3 transparent insertion of security appliances via GENEVE. Pick by the traffic and the requirement, not by habit.

**Target groups are the backend.** A target group holds targets (instance, IP, Lambda, or an ALB), a health check, and attributes (stickiness, slow start, deregistration delay, algorithm). IP targets reach peered VPCs, on-prem over VPN/DX, and ECS/EKS workloads; Lambda targets are ALB-only.

**Listener rules are priority-ordered.** ALB evaluates rules low priority first; multiple conditions on a rule are AND, multiple values within a condition are OR. Weighted target groups give canary and blue-green without DNS changes (now on NLB too).

**Security groups attach to ALB, not NLB.** ALB needs a security group allowing inbound; NLB has none (traffic passes through), so backend security groups must allow the client or LB subnet. This is the most common cross-type confusion.

**Cross-zone is on for ALB, off by default for NLB/GWLB.** Disabled cross-zone on NLB causes uneven distribution and hot spots; enabling it evens distribution but adds inter-AZ data-transfer cost. ALB cross-zone is always on and free.

**Anti-patterns:** ALB for raw TCP/UDP (it only does HTTP/HTTPS/gRPC, use NLB); NLB left with cross-zone disabled and uneven targets; GWLB appliances without AWS-TLV GENEVE support; expecting PrivateLink on ALB/GWLB (NLB only); an ACM certificate in the wrong region (us-east-1 for CloudFront); forgetting NLB's 10s minimum health-check interval means 30s+ failover; shipping without access logs.

## Reference router

| Need | Load |
|---|---|
| ALB request processing and listener-rule evaluation, NLB packet/flow processing and static IPs, GWLB GENEVE protocol and symmetric hashing and endpoints, target-group internals, health-check timing maths, access-log formats, cost components | `references/elb-architecture.md` |
| ALB routing rules and actions, target types, health-check parameters, ACM/TLS policies, AWS WAF v2, Cognito/OIDC auth, PrivateLink, sticky sessions, NLB TLS modes and QUIC, Terraform/CloudFormation snippets | `references/configuration-and-integration.md` |
| LB-type selection, NLB+ALB and CloudFront and GWLB+Transit-Gateway patterns, cross-zone cost trade-off, CloudWatch monitoring, the common-pitfalls catalogue, cross-refs to aws-networking-audit and aws-cloud-ops | `references/operations.md` |

## Cross-references

- `load-balancer-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether a managed AWS LB fits and at which layer; this skill builds it. Reciprocal reference.
- `haproxy-load-balancing`, `nginx-load-balancing`: sibling vendor skills; an ALB or NLB often fronts an NGINX/HAProxy or Kubernetes ingress.
- `aws-networking-audit`: the VPC security-group rules, ENI/subnet placement, and public-exposure audit of the load balancer. This skill configures it; that audits its exposure. Reciprocal reference (aws-networking-audit already defers ALB/NLB content here).
- `aws-cloud-ops`: AWS service-selection and cost trade-offs around the load balancer. Reciprocal reference (aws-cloud-ops already defers load-balancer depth here).
- `cert-manager`, `lets-encrypt`: non-ACM certificate issuance; ACM is covered inline here.
- `secrets-hygiene`: PrivateLink and API credentials and any non-ACM private keys live in the secret store.
- `distributed-tracing`: an ALB is an L7 span boundary; propagate trace context and use `TargetResponseTime` for latency analysis.

## Red flags

- About to put raw TCP or UDP behind an ALB: it only handles HTTP/HTTPS/gRPC, use an NLB.
- About to leave NLB cross-zone disabled with unevenly distributed targets: hot spots and skew.
- About to deploy GWLB with appliances that do not support AWS-TLV GENEVE on UDP 6081: traffic blackholes.
- About to expect PrivateLink, mTLS, or Lambda targets on the wrong LB type (PrivateLink/QUIC are NLB; mTLS/Lambda/Cognito are ALB).
- About to attach an ACM certificate from the wrong region (must match the LB region; us-east-1 for CloudFront).
- About to plan failover without accounting for NLB's 10s minimum health-check interval (30s+ to detect down).
- About to add a security group to an NLB (it has none) or forget one on an ALB (it requires one).
- About to ship without access logs, then have no per-request data when debugging latency or 5xx.

## Bottom line

ALB routes L7, NLB moves L4 with static IPs and PrivateLink, GWLB inserts security appliances at L3 via GENEVE: choose by the traffic and the requirement. Target groups carry the backend, health check, and stickiness; listener rules are priority-ordered with weighted groups for safe rollouts. Mind the asymmetries (security groups on ALB not NLB, cross-zone defaults and cost, PrivateLink and Lambda placement, ACM region), enable access logs from day one, and bring the design and platform choice from `load-balancer-selection` while leaving the VPC-exposure audit to `aws-networking-audit`.
