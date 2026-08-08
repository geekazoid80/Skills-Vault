---
name: aws-cloud-ops
description: "Use for AWS implementation and operations across compute, serverless, containers, storage, databases, messaging, cost management, security, and observability. Vendor-specific cloud-ops skill in the cloud-ops family; owns AWS service selection and the cross-cutting cost, security, and account-structure decisions, and routes to per-service references for depth and to aws-networking-audit for VPC networking. Triggers include \"AWS\", \"Amazon Web Services\", \"EC2\", \"EC2 instance family\", \"Graviton\", \"ARM instances\", \"Auto Scaling\", \"ECS\", \"EKS\", \"Fargate\", \"AWS Batch\", \"Lambda\", \"Lambda cold start\", \"Lambda concurrency\", \"API Gateway\", \"REST vs HTTP API\", \"Step Functions\", \"EventBridge\", \"S3\", \"S3 storage class\", \"S3 lifecycle\", \"EBS\", \"gp3 vs gp2\", \"io2\", \"EFS\", \"FSx\", \"RDS\", \"Aurora\", \"Aurora vs RDS\", \"Aurora Serverless\", \"DynamoDB\", \"DynamoDB capacity mode\", \"DynamoDB on-demand vs provisioned\", \"ElastiCache\", \"MemoryDB\", \"DocumentDB\", \"OpenSearch\", \"Redshift\", \"SQS\", \"SNS\", \"Kinesis\", \"SQS vs SNS\", \"FIFO queue\", \"fan-out\", \"AWS cost optimisation\", \"Savings Plans\", \"Reserved Instances\", \"Spot Instances\", \"Compute Optimizer\", \"AWS Budgets\", \"Cost Explorer\", \"right-sizing\", \"NAT Gateway cost\", \"Cost anomaly detection\", \"IAM\", \"IAM least privilege\", \"Identity Center\", \"KMS\", \"envelope encryption\", \"Secrets Manager\", \"Parameter Store\", \"GuardDuty\", \"Security Hub\", \"AWS Config\", \"WAF\", \"SCP\", \"service control policy\", \"AWS Organizations\", \"multi-account\", \"Control Tower\", \"landing zone\", \"CloudWatch\", \"CloudWatch alarms\", \"CloudWatch Logs\", \"Logs Insights\", \"metric math\", \"X-Ray\", \"AWS observability\", \"AWS tagging strategy\". References: compute.md, serverless.md, database.md, storage.md, messaging.md, cost.md, security.md, observability.md. For cloud selection and multi-cloud strategy see cloud-platform-selection; for VPC networking audit and design-and-cost depth see aws-networking-audit."
license: MIT
metadata:
  version: 1.0.0
---

# AWS cloud operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: aws-cloud-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

The vendor-specific AWS entry point in the cloud-ops family. It owns AWS service selection plus the cross-cutting cost, security, and account-structure decisions, and points at per-service references for depth. Every recommendation should address the trade-off triangle: performance, cost, and operational complexity.

Prices referenced anywhere in this skill and its references are US East (N. Virginia) on-demand unless noted, and they drift. Treat every figure as an order-of-magnitude anchor and verify current pricing at https://aws.amazon.com/pricing/ before quoting a number to a customer.

## When to use

- Choosing or sizing an AWS service (compute, storage, database, messaging, serverless) with cost and complexity trade-offs in view.
- Reviewing an AWS bill or designing a cost-optimisation pass (Savings Plans, right-sizing, storage tiering, NAT and data-transfer traps).
- Setting up AWS security baselines (IAM, KMS, Secrets Manager, GuardDuty, Security Hub, Config, WAF) and multi-account guardrails.
- Standing up AWS observability (CloudWatch metrics, alarms, Logs, Logs Insights, dashboards) and request tracing (X-Ray).

## When not to use

- **Picking a cloud at all, or multi-cloud strategy** (AWS vs Azure vs GCP, cross-cloud service mapping, migration 7 Rs, FinOps practice): use `cloud-platform-selection`, the family-level meta skill.
- **VPC networking**: VPC design, subnet tiers, CIDR planning, NAT placement, VPC endpoints, Transit Gateway, security groups and NACLs, Flow Logs, and the networking cost trade-offs all live in `aws-networking-audit` (audit procedure plus a design-and-cost reference). This skill cross-refers there rather than duplicating it.
- **DNS, load balancing, and CDN as primary topics** (Route 53 routing policies, ALB vs NLB vs GLB, CloudFront): these belong to the DNS and load-balancer families. Touch them only as incidental context here.

## Service-category router

Load the reference that matches the request. Each is a standalone deep-dive.

| Category | Services | Reference |
|---|---|---|
| Compute | EC2 instance families, Graviton, Auto Scaling, ECS, EKS, Fargate, Batch | `references/compute.md` |
| Serverless | Lambda patterns and concurrency, API Gateway, Step Functions, EventBridge | `references/serverless.md` |
| Database | RDS, Aurora, DynamoDB, ElastiCache, MemoryDB, selection | `references/database.md` |
| Storage | S3 classes and lifecycle, EBS volume types, EFS, FSx | `references/storage.md` |
| Messaging | SQS, SNS, EventBridge, Kinesis, FIFO vs Standard, fan-out | `references/messaging.md` |
| Cost | Savings Plans vs RIs, right-sizing, cost traps, estimation templates, FinOps ops | `references/cost.md` |
| Security | IAM, KMS, Secrets Manager, GuardDuty, Security Hub, Config, WAF, SCPs | `references/security.md` |
| Observability | CloudWatch metrics, alarms, metric math, Logs, Logs Insights, dashboards, X-Ray | `references/observability.md` |
| Networking | VPC, NAT, endpoints, TGW, security groups, Flow Logs | see `aws-networking-audit` (not a reference here) |

## Service-selection decision trees

### Compute

```
Short-lived, event-driven task (under 15 min)?
  YES -> Needs over 10 GB memory or a GPU?
    YES -> ECS/EKS on EC2 (GPU instances) or EC2 directly
    NO  -> Lambda (start here; move to containers if cost exceeds threshold)
  NO -> Long-running service?
    YES -> Need the Kubernetes ecosystem or multi-cloud portability?
      YES -> EKS (control-plane charge applies)
      NO  -> ECS (simpler, free control plane); then Fargate vs EC2 per references/compute.md
    NO -> Batch job?
      YES -> AWS Batch on Spot
      NO  -> EC2 with Auto Scaling
```

### Database

```
Structured data, complex queries, transactions?    -> RDS or Aurora (references/database.md)
Key-value lookups at scale, single-digit ms?        -> DynamoDB
Caching, session store, real-time counters?         -> ElastiCache / MemoryDB
Document store with MongoDB compatibility?          -> DocumentDB
Full-text search and analytics?                     -> OpenSearch Service
Data warehouse at petabyte scale?                   -> Redshift
```

### Storage

```
Files, images, video, backups?     -> S3 (choose the class by access pattern)
Shared POSIX filesystem?           -> Linux: EFS (auto-scale) or FSx Lustre (HPC); Windows: FSx for Windows
Block storage for one instance?    -> EBS gp3 (always gp3 over gp2)
```

## Top cost rules

1. **Default to Graviton (ARM).** 20 to 40 per cent better price/performance; use `g`-suffix instances (m7g, c7g, r7g) and `arm64` Lambda unless a hard x86 dependency exists.
2. **Always gp3 over gp2.** gp3 is cheaper per GB and ships 3,000 IOPS baseline; migrating is zero-downtime.
3. **Create S3 and DynamoDB Gateway Endpoints.** They are free and remove NAT Gateway data-processing charges for that traffic.
4. **Lifecycle every S3 bucket.** Standard to IA at 30 days, Glacier at 90, Deep Archive at 365; large savings over keeping everything in Standard.
5. **Use Compute Savings Plans for EC2/Fargate/Lambda; RIs for RDS/ElastiCache** (which have no Savings Plan option).
6. **Right-size quarterly** with Compute Optimizer; most instances run well under 30 per cent CPU.
7. **Stop non-production after hours** with Instance Scheduler.
8. **DynamoDB: start On-Demand, observe, then switch to Provisioned** for sustained workloads (materially cheaper at steady throughput).
9. **Watch NAT Gateway data charges**; prefer VPC Interface Endpoints for frequently called AWS services. Network cost detail lives in `aws-networking-audit`.
10. **Use Spot for fault-tolerant workloads**, diversified across many instance types and all AZs with capacity-optimised allocation.

Deeper cost mechanics, the full traps list, and estimation templates are in `references/cost.md`.

## Cross-cutting architecture decisions

Condensed here; the references carry the full tables and pricing.

- **Graviton vs x86.** Default Graviton; choose x86 only for Windows or x86-only binaries.
- **Savings Plans vs Reserved Instances.** Compute Savings Plans for EC2/Fargate/Lambda (flexible across family, region, OS); RIs where no Savings Plan exists (RDS, ElastiCache, OpenSearch, Redshift).
- **ECS vs EKS.** ECS for AWS-native simplicity and a free control plane; EKS for an existing Kubernetes investment or multi-cloud portability.
- **Aurora vs RDS.** Aurora often wins for production HA because Multi-AZ durability is included; RDS suits small, dev, or budget-constrained workloads.
- **Encryption defaults.** SSE-S3 for S3 by default (SSE-KMS only when you need key control or audit); enable RDS encryption at creation (it cannot be added later); force TLS in transit. Full decision tree in `references/security.md`.

## Multi-account structure

A production AWS Organizations layout, governed by Control Tower (landing zone), SCPs (guardrails), an organisation CloudTrail (audit), and GuardDuty delegated admin (threat detection):

- **Management** account: Organizations root and billing, no workloads.
- **Security** account: GuardDuty and Security Hub admin, CloudTrail archive.
- **Log archive** account: immutable CloudTrail, VPC Flow Logs, Config logs.
- **Shared services** account: CI/CD, container registry, shared tooling.
- **Network** account: Transit Gateway, Direct Connect, shared DNS.
- **Workload** accounts: one per application or team per environment.
- **Sandbox** accounts: isolated experimentation with a limited budget.

## Cross-references

- `cloud-platform-selection` (family meta skill): which cloud for which workload, multi-cloud strategy, cross-cloud service mapping, Well-Architected principles, migration 7 Rs, FinOps. Start there when the cloud itself is not yet decided.
- `aws-networking-audit`: VPC networking posture audit (security groups, NACLs, Transit Gateway, Flow Logs, route tables) plus a design-and-cost reference (CIDR planning, NAT and VPC-endpoint cost, TGW vs peering). All AWS networking depth lives there.
- `azure-cloud-ops` (live): the Azure sibling in the cloud-ops triad. Cross-cloud service mapping lives in `cloud-platform-selection`.
- `gcp-cloud-ops` (live): the GCP sibling; GCP-specific compute, storage, database, GKE, Vertex AI, cost optimisation, and Cloud Monitoring/Logging MCP tooling.
- `secrets-hygiene`: credential-handling discipline that complements the IAM, KMS, and Secrets Manager material here.
- `linux-host-bringup` and `linux-host-ops`: in-guest configuration once EC2 instances are running.
- `grafana-dashboards`, `prometheus-configuration`, `distributed-tracing`: vendor-neutral observability that pairs with the CloudWatch and X-Ray material in `references/observability.md`.

## Red flags

- Recommending a service without its cost model and a cheaper alternative considered.
- Quoting a price as current fact rather than an anchor to verify at the pricing page.
- Duplicating VPC or networking guidance here instead of pointing at `aws-networking-audit`.
- Pulling Route 53, ELB, or CloudFront depth into this skill rather than deferring to the DNS and load-balancer families.
- Provisioning DynamoDB On-Demand for a steady, predictable workload.
- gp2 volumes, unattached EBS volumes, idle Elastic IPs, or CloudWatch log groups with no retention policy left unaudited.

## Bottom line

Classify the request, load the matching reference, and frame every recommendation around performance, cost, and operational complexity with a concrete (verifiable) cost anchor. Defer cloud selection to `cloud-platform-selection` and all networking to `aws-networking-audit`.
