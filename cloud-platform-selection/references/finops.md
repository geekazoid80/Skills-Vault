# FinOps practice

> Financial accountability for cloud spend; bridging engineering, finance, and business teams. Covers tagging strategy, chargeback/showback models, unit economics, commitment management, anomaly detection, and cost optimisation by category.

## FinOps Foundation framework

FinOps has three iterative phases (not sequential; cycle through continuously).

### Phase 1: Inform (visibility and allocation)

- Accurate tagging and cost allocation.
- Dashboards showing spend by team, project, environment, service.
- Showback reports (show teams their costs) or chargeback (bill teams internally).
- Unit economics: cost per transaction, cost per user, cost per API call.

### Phase 2: Optimise (rate and usage)

- Right-sizing (overprovisioned resources are the number-one waste category).
- Reserved capacity for steady-state workloads.
- Spot or preemptible for fault-tolerant workloads.
- Storage tiering and lifecycle policies.
- Eliminate idle and orphaned resources.
- Architecture optimisation (serverless where appropriate, data transfer reduction).

### Phase 3: Operate (continuous governance)

- Budget policies and automated enforcement.
- Anomaly detection and alerting.
- Regular optimisation reviews (monthly minimum).
- FinOps team or cloud centre of excellence.
- Executive reporting tied to business metrics.

## Tagging strategy

Tags are the foundation of cloud cost management. Without consistent tagging, cost allocation is impossible.

### Mandatory tags (enforce via policy)

| Tag | Purpose | Example values |
|---|---|---|
| `owner` | Team or individual responsible | platform-team, data-eng, john.smith |
| `environment` | Deployment environment | production, staging, development, sandbox |
| `cost-center` | Finance cost-centre code | CC-1234, engineering-platform |
| `project` | Project or product name | checkout-service, data-pipeline, mobile-app |
| `managed-by` | How the resource is managed | terraform, manual, cdk, pulumi |

### Recommended tags

| Tag | Purpose | Example values |
|---|---|---|
| `data-classification` | Data sensitivity level | public, internal, confidential, restricted |
| `compliance` | Regulatory framework | hipaa, pci-dss, sox, gdpr |
| `auto-shutdown` | Can be stopped off-hours | true, false |
| `expiration-date` | Temporary resource cleanup | 2026-06-30 |
| `criticality` | Business criticality | critical, high, medium, low |

### Enforcement by cloud

- **AWS.** Service Control Policies plus AWS Config rules plus tag policies in Organizations.
- **Azure.** Azure Policy (deny resources without required tags).
- **GCP.** Organisation Policies plus labels (GCP uses "labels" for billing; "tags" are for firewall rules).

### GCP labelling note

GCP distinguishes between "labels" (key-value metadata for billing and organisation) and "tags" (used for firewall rule targeting). For cost allocation purposes, use labels.

## Chargeback vs showback

**Showback.** Show teams their cloud costs without actually billing them internally. Lower friction, good starting point. Risk: teams may ignore costs they do not pay.

**Chargeback.** Actually deduct cloud costs from team budgets. Higher accountability, but requires accurate allocation. Can create perverse incentives (teams avoid cloud features to save budget).

**Recommendation.** Start with showback. Move to chargeback only when tagging is mature and shared cost allocation is fair.

### Shared cost allocation

Shared infrastructure (networking, monitoring, security tools, Kubernetes clusters) is hard to allocate fairly.

| Strategy | Description | Best for |
|---|---|---|
| Proportional | Allocate proportionally to each team's direct spend | Simple but imprecise |
| Usage-based | Instrument shared services to track per-team usage | Most accurate, requires tooling |
| Fixed allocation | Each team pays a flat platform fee | Predictable but disconnected from usage |
| Hybrid | Fixed base fee plus variable usage-based component | Balances predictability with fairness |

### Kubernetes cost allocation

- Use labels consistently on all pods and deployments (team, project, environment).
- Tooling: Kubecost (open-source), CloudHealth, Apptio Cloudability, native cloud tools.
- Track: CPU requests and usage, memory requests and usage, PVCs, load balancer costs, egress per service.
- Challenge: shared cluster overhead (control plane, system pods, monitoring) must be distributed.

## Anomaly detection and cost alerts

| Capability | AWS | Azure | GCP |
|---|---|---|---|
| Budget alerts | AWS Budgets | Cost Management Budgets | Budget alerts |
| Anomaly detection | Cost Anomaly Detection (ML-based) | Anomaly alerts in Cost Management | Budget alerts (threshold-based) |
| Automated response | Budgets plus Lambda or SNS actions | Action groups (email, webhook, Logic Apps) | Pub/Sub plus Cloud Functions |
| Recommendations | Cost Explorer plus Compute Optimizer | Azure Advisor (cost pillar) | Active Assist Recommender |
| Cost analysis | Cost Explorer | Cost Analysis | Billing Reports or Looker Studio |

### Alert setup best practice

1. Set budget at expected monthly spend.
2. Configure alerts at 50, 80, 100, and 120 percent (forecast).
3. Route to Slack, Teams, or PagerDuty for team visibility.
4. Add automated actions at 100 percent (restrict new resource creation, notify leadership).
5. Review and adjust budgets quarterly.

## Commitment management

### Buying reserved capacity

1. Analyse 30 to 90 days of usage data for stable baseline.
2. Start with one-year commitments (lower discount, lower risk).
3. Cover only steady-state workload (70 to 80 percent of baseline).
4. Leave headroom for Spot or on-demand for peaks.
5. Review utilisation monthly; unused reservations are waste.

### Exchange and modification

- **AWS.** Convertible RIs can be exchanged; Savings Plans cannot be modified but are inherently flexible.
- **Azure.** RIs can be exchanged or refunded (with limitations); scope can be changed.
- **GCP.** CUDs cannot be cancelled; resource-based CUDs can be shared across projects.

### Monitoring utilisation

- Target: over 80 percent utilisation of reserved capacity.
- **AWS.** Cost Explorer RI and Savings Plan utilisation reports.
- **Azure.** Reservations blade in Cost Management.
- **GCP.** CUD utilisation in Billing console.

## Unit economics

The most important FinOps metric: tie cloud spend to business outcomes.

| Metric | Formula | Why it matters |
|---|---|---|
| Cost per transaction | Monthly cloud cost / monthly transactions | Tracks efficiency as you scale |
| Cost per active user | Monthly cloud cost / monthly active users | Ties spend to user growth |
| Cost per API call | API infrastructure cost / total API calls | Identifies expensive endpoints |
| Cost per GB processed | Data pipeline cost / GB processed | Tracks data processing efficiency |
| Cloud cost as percent of revenue | Total cloud spend / total revenue | Executive-level efficiency metric |
| Marginal cost of growth | Incremental cloud cost / incremental revenue | Shows if costs scale linearly |

**Target.** Cloud cost as percentage of revenue should decrease over time as you optimise and benefit from scale. If it is increasing, either revenue is declining or cloud waste is growing.

## Cost optimisation wins by category

### Quick wins (days, 10 to 30 percent savings)

- Delete unattached volumes, orphaned disks, unused persistent disks.
- Stop or terminate idle development instances (schedule auto-stop after hours).
- Downsize over-provisioned instances (most VMs use less than 30 percent CPU).
- Delete unused static IPs (they incur hourly charges when unattached).
- Clean up old snapshots beyond retention policy.
- Move infrequently accessed storage to cheaper tiers.

### Medium-term (weeks, 20 to 50 percent savings)

- Purchase Reserved Instances, Savings Plans, or CUDs for steady-state workloads.
- Implement auto-scaling for variable workloads (scale down at night, weekends).
- Use Spot or preemptible instances for batch, CI/CD, and fault-tolerant workloads.
- Consolidate underutilised databases.
- Right-size containers (many pods request 4x what they actually use).
- Review and optimise data transfer patterns (cross-AZ, cross-region, egress).

### Strategic (months, 30 to 60 percent savings)

- Refactor to serverless where appropriate (eliminate idle compute entirely).
- Implement caching layers to reduce database and API costs.
- Use ARM-based instances (Graviton, Ampere) for 20 to 40 percent better price-performance.
- Re-architect data pipelines for efficiency (batch vs streaming, compression, partitioning).
- Negotiate Enterprise Discount Programs (AWS EDP, Azure MACC, GCP committed spend).
- Implement FinOps culture: engineers own their costs, regular optimisation reviews.

## Cloud cost estimation checklist

When estimating cloud costs for a new workload, account for all categories:

```
[ ] Compute: VMs, containers, functions (include dev/staging environments)
[ ] Storage: object, block, file (include backups and snapshots)
[ ] Database: managed instances, replicas, storage, IOPS, backups
[ ] Networking: load balancers, NAT gateways, VPN/interconnect, static IPs
[ ] Data transfer: egress to internet, cross-region, cross-AZ, to other clouds
[ ] DNS: hosted zones, query volume
[ ] CDN: data transfer, requests, SSL certificates
[ ] Monitoring: metrics ingestion, log storage, custom metrics, APM, traces
[ ] Security: WAF rules, DDoS protection, vulnerability scanning, KMS key usage
[ ] CI/CD: build minutes, artifact storage, container registry storage
[ ] Support plan: required tier for production SLA
[ ] Reserved capacity: discount commitments (subtract from on-demand estimates)
[ ] Licensing: BYOL vs included (Windows, SQL Server, Oracle)
[ ] Third-party tools: monitoring (Datadog), security (Prisma Cloud), backup (Veeam)
[ ] Tax: cloud services are subject to sales tax in many jurisdictions
[ ] Growth buffer: add 20 to 30 percent for unexpected growth
```
