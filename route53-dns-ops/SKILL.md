---
name: route53-dns-ops
description: "Use for AWS Route 53 DNS operations, hosted zones (public and private), Alias records, routing policies (simple, weighted, latency, geolocation, geoproximity, failover, multivalue, IP-based), health checks, Route 53 Resolver (inbound/outbound endpoints, resolver rules), DNS Firewall, DNSSEC (KMS-based KSK), Traffic Flow, Application Recovery Controller (ARC), and Route 53 IaC (Terraform, CloudFormation, AWS CLI). References: architecture.md. Triggers include \"Route 53\", \"Route53\", \"AWS Route 53\", \"hosted zone\", \"public hosted zone\", \"private hosted zone\", \"Alias record\", \"zone apex record\", \"weighted routing\", \"latency routing\", \"geolocation routing\", \"geoproximity routing\", \"failover routing\", \"multivalue routing\", \"IP-based routing\", \"Route 53 health check\", \"endpoint health check\", \"calculated health check\", \"Route 53 Resolver\", \"resolver endpoint\", \"inbound endpoint\", \"outbound endpoint\", \"resolver rule\", \"forward rule\", \"Route 53 DNS Firewall\", \"managed domain list\", \"Route 53 DNSSEC\", \"KMS key signing key\", \"KSK rotation\", \"Traffic Flow\", \"traffic policy\", \"ARC routing control\", \"Route 53 Profiles\", \"aws_route53_zone\", \"aws_route53_record\", \"aws route53\", \"associate-vpc-with-hosted-zone\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops; for VPC networking, Security Groups, and broader AWS infrastructure see aws-networking-audit and aws-cloud-ops."
license: MIT
metadata:
  version: 1.0.0
---

# Route 53 DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: route53-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers AWS Route 53 implementation and operations: hosted zone design, Alias record usage, all eight routing policies, health check design patterns (including the private-endpoint CloudWatch pattern), Route 53 Resolver for hybrid DNS, DNS Firewall for VPC egress filtering, DNSSEC with KMS-managed keys, and IaC (Terraform, CloudFormation, AWS CLI). The conceptual DNS layer (resolution flow, DNSSEC chain of trust, cross-platform architecture, split-horizon design) lives in `dns-network-ops`.

## When to use

- Creating or migrating a public or private hosted zone in Route 53.
- Choosing or configuring a routing policy: simple, weighted, latency, geolocation, geoproximity, failover, multivalue, or IP-based.
- Placing an Alias record at the zone apex or pointing to an AWS resource (ALB, CloudFront, API Gateway, S3, Global Accelerator, etc.).
- Designing health checks: endpoint, calculated, CloudWatch alarm-based, or ARC routing controls.
- Setting up Route 53 Resolver for hybrid DNS: inbound/outbound endpoints and forwarding rules.
- Configuring DNS Firewall rule groups, managed domain lists, and VPC associations.
- Enabling DNSSEC on a public hosted zone (KMS KSK, DS registration at registrar).
- Defining Traffic Flow policies or geoproximity routing with bias tuning.
- Writing or reviewing Terraform, CloudFormation, or AWS CLI for any Route 53 resource.

## When not to use

- **DNS architecture, DNSSEC design theory, or cross-platform comparison**: use `dns-network-ops`.
- **VPC networking, Security Groups, Transit Gateway, or broader AWS infrastructure**: use `aws-networking-audit`.
- **AWS service configuration beyond DNS (IAM, KMS policy design, EC2, RDS)**: use `aws-cloud-ops`.
- **On-premises BIND/PowerDNS authoritative serving the same hybrid domain**: use `bind-dns-ops` or `powerdns-ops` alongside this skill for the on-prem side.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and operations | Hosted zones (public/private), Alias records, all routing policies with config detail, health check types and patterns, Route 53 Resolver (endpoints and rules), DNS Firewall, DNSSEC (KMS KSK, ZSK, DS registration, KSK rotation, alarms), Traffic Flow, ARC, pricing notes, Terraform/CloudFormation/CLI reference | `references/architecture.md` |

## Core concepts

### Classify the hosted zone first

Two zone types drive every design decision downstream:

| Type | Scope | Requires | DNSSEC |
|---|---|---|---|
| Public | Internet-accessible; served from AWS anycast edge | Nothing; delegates from registrar | Supported |
| Private | VPC-internal only; hidden from internet | `enableDnsHostNames` + `enableDnsSupport` on each associated VPC | Not supported |

The single most common private-zone mistake is assuming VPC peering propagates DNS: it does not. Each VPC must be explicitly associated with the private hosted zone.

### Alias records vs CNAME

Alias records are a Route 53 extension that behaves like a CNAME but can sit at the zone apex and incurs no per-query charge for AWS resource targets. Use an Alias record whenever the target is an ALB, NLB, CloudFront distribution, API Gateway, S3 website endpoint, Elastic Beanstalk environment, VPC Interface Endpoint, Global Accelerator, or another Route 53 record. A CNAME cannot sit at the zone apex (RFC 1034 prohibition); a CNAME to an AWS resource is charged per query.

### Routing policy selection

Load `references/architecture.md` for the full policy detail. Quick guide:

- **Simple**: one target, no routing logic, no health check (multiple values returned randomly to client).
- **Weighted**: traffic splitting, A/B testing, canary (weight 0 = no traffic; all weight 0 = equal distribution).
- **Latency**: multi-region, route to lowest-latency AWS region.
- **Failover**: active/passive DR; health check mandatory on PRIMARY.
- **Geolocation**: country/continent/US state; always add a default record or unmatched clients receive NXDOMAIN.
- **Geoproximity**: distance-based with bias tuning; requires Traffic Flow (Traffic Policies).
- **Multivalue**: up to 8 healthy records per response; not a replacement for a load balancer.
- **IP-based**: CIDR collections, useful for ISP-based or network-segment-based routing.

### Health check design for private endpoints

Route 53 health checkers use public IPs; they cannot reach private VPC resources directly. Pattern: deploy a CloudWatch metric or alarm that monitors the private resource, then create a Route 53 CloudWatch alarm-based health check that monitors the alarm state. See `references/architecture.md` for the full flow.

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC chain of trust, platform selection, cross-platform comparison, and the full DNS family skill set. Load this for design decisions that span platforms.
- `aws-networking-audit`: VPC layout, Security Groups, NACLs, Transit Gateway, and the broader AWS networking context that Route 53 private zones and Resolver endpoints operate within.
- `aws-cloud-ops`: IAM policy design for Route 53, KMS key policy for DNSSEC KSK, CloudWatch alarms for health checks and DNSSEC monitoring, and broader AWS service operations.
- `multi-vendor-network-ops`: production-change contract (assumptions, risk, pre-checks, execution, post-checks, rollback, escalation). Apply to every DNSSEC enablement, KSK rotation, routing-policy migration, and Resolver rule change in production.
- `secrets-hygiene`: Route 53 DNSSEC KSK is held in KMS; the KMS key policy must follow least-privilege. CLI credentials and Terraform state must never expose the key ARN in plain-text logs.
- `utc-timestamps`: Route 53 DNSSEC key timing (activate/retire windows), health check failure logs, and CloudWatch alarm state transitions must be reasoned about in UTC.
- `systematic-debugging`: structured fault-isolation for Route 53 failures: NXDOMAIN for unmatched geolocation, failover records stuck on SECONDARY, Resolver rule precedence conflicts, DNSSEC validation chains that break after KSK rotation.

## Red flags

- **CNAME at zone apex.** Route 53 rejects a CNAME at the zone apex. Use an Alias record (type A or AAAA pointing to the AWS resource) instead.
- **Geolocation routing without a default record.** Clients from unmapped countries receive NXDOMAIN if no default geolocation record exists. Always add a default.
- **Failover without a health check on PRIMARY.** Without a health check, Route 53 never switches to SECONDARY. The `evaluate_target_health = true` Terraform attribute on the Alias, or an explicit health check ID on the record, is required.
- **Private hosted zone VPC not associated.** VPC peering, Transit Gateway, and RAM sharing do NOT automatically propagate private hosted zone DNS. Each consuming VPC must be explicitly associated.
- **DNSSEC KMS key in the wrong region.** The KMS key for the DNSSEC KSK must be in us-east-1 regardless of the hosted zone's operational region. A key in any other region causes DNSSEC enablement to fail.
- **DNSSEC KSK not monitored.** Unlike ZSK (auto-rotated by Route 53 every ~7 days), KSK does not auto-rotate. Set CloudWatch alarms on `DNSSECKeySigningKeysNeedingAction` and `DNSSECInternalFailure`. Unmonitored KSK expiry causes DNSSEC validation failure for the entire zone.
- **Geoproximity configured outside Traffic Flow.** Geoproximity routing is only available through Traffic Flow (Traffic Policies), not standard record-set API calls. Attempting standard record creation with geoproximity fails.
- **Health checker IPs blocked.** Route 53 health checkers source from a published IP range. If Security Groups or NACLs block those ranges, health checks fail and failover triggers unintentionally. Publish and maintain the health-checker IP allowlist.

## Bottom line

Classify the zone type (public vs private) and the routing requirement (single resource, traffic split, latency, failover, geography, or DR) before writing any configuration. Load `references/architecture.md` for policy detail, health check patterns, Resolver endpoint design, DNSSEC KMS steps, and Terraform/CLI examples. Route conceptual and cross-platform architecture decisions to `dns-network-ops`. Treat DNSSEC enablement, KSK rotation, and failover routing changes as change-controlled production operations under the `multi-vendor-network-ops` contract.
