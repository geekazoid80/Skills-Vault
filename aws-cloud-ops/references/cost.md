# AWS Cost Management Reference

> Cost framework, Savings Plans vs RIs, right-sizing process, common cost traps, estimation templates, plus the operational Cost Explorer workflows (network cost analysis, anomaly investigation, monthly review). Prices are US East (N. Virginia).

---

## Cost Optimisation Framework

### AWS Well-Architected Cost Pillar: five principles

1. **Implement cloud financial management**: dedicate a team or person to cost ownership.
2. **Adopt a consumption model**: pay only for what you consume, auto-scale down.
3. **Measure overall efficiency**: track business output per dollar spent.
4. **Stop spending on undifferentiated heavy lifting**: use managed services.
5. **Analyse and attribute expenditure**: tag everything, allocate costs to teams.

---

## AWS Cost Management Tools

### Cost Explorer

- Visualise spending by service, account, tag, region, instance type.
- Granularity: monthly, daily, hourly (hourly costs $0.01 per 1000 requests).
- Savings Plans recommendations with estimated savings.
- Reservation utilisation reports.
- Free for basic usage.

The Cost Explorer API itself charges **$0.01 per request**, so batch queries and avoid excessive polling. Cost data can lag by up to 24 hours. When pulling figures, clarify whether the user wants **unblended** or **amortised** cost (the two differ for upfront-paid commitments).

#### Cost Explorer via MCP server

The AWS Labs Cost Explorer MCP server exposes these queries programmatically:

- **Command**: `uvx awslabs.cost-explorer-mcp-server@latest` (stdio transport).
- **Requires**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (or `AWS_PROFILE`).
- **Note**: the underlying Cost Explorer API charges $0.01 per request; be mindful of query volume.

Key capabilities through this surface:

- **Cost breakdown**: spending by service, account, region, or tag.
- **Time series**: daily, monthly, or custom date-range cost trends.
- **Forecasts**: predicted spend based on historical patterns.
- **Anomaly detection**: unusual spending spikes.
- **Filtering**: narrow by service (EC2, VPC, TGW, NAT GW, VPN, etc.).

### AWS Budgets

- Set budgets on cost, usage, coverage, or utilisation.
- Alert at thresholds: e.g. 50%, 80%, 100% of monthly budget.
- **Budget Actions**: auto-stop EC2, apply IAM deny policies, restrict new resources when exceeded.
- First 2 budgets free, $0.01 per day per additional (5 alerts per budget free).

### Compute Optimizer

- ML-based right-sizing for EC2, Lambda, EBS, ECS on Fargate.
- Analyses 14 days of CloudWatch metrics.
- Free for basic; enhanced (3 months metrics) requires opt-in.

### Trusted Advisor

- Checks for: idle RDS, underutilised EC2, unassociated EIPs, idle load balancers.
- Full checks require Business or Enterprise Support plan.
- Key cost checks: Low Utilization EC2, Underutilized EBS, Unassociated EIPs, Idle LBs, Idle RDS.

### S3 Storage Lens

- Organisation-wide S3 visibility: bucket sizes, access patterns, cost efficiency.
- Free: 28 summary metrics. Advanced: $0.20 per million objects monitored.
- Find: buckets without lifecycle policies, versioning bloat, non-current versions.

---

## Purchasing Options Strategy

### Savings Plans vs Reserved Instances

| Feature | Savings Plans | Reserved Instances |
|---------|--------------|-------------------|
| Flexibility | Across instance families, regions, OS, tenancy | Locked to instance type + region |
| Services | EC2, Fargate, Lambda | EC2, RDS, ElastiCache, OpenSearch, Redshift |
| Discount | Up to 72% (3yr All Upfront) | Up to 72% |
| Recommendation | **Preferred for new commitments** | Use for RDS/ElastiCache (no SP option) |

### Compute Savings Plans

Apply to any EC2, Fargate, or Lambda usage regardless of instance family, region, or OS. **Start here.**

### EC2 Instance Savings Plans

Locked to instance family + region but deeper discount. Use when confident about family.

### Spot Instances (up to 90% off)

Use for: batch processing, CI/CD runners, data processing, stateless web servers behind ASG (mixed instances policy). **Never for**: databases, stateful services, anything that cannot tolerate 2-minute interruption.

---

## Right-Sizing Process

1. **Identify candidates**: Compute Optimizer + Cost Explorer right-sizing recommendations.
2. **Validate metrics**: 2 weeks minimum of CloudWatch data (CPU, memory via CW Agent, network, disk).
3. **Decision thresholds**:
   - CPU avg < 20% for 14 days -> downsize.
   - CPU avg < 5% for 14 days -> consider terminating (may be unused).
   - Memory avg < 30% -> downsize instance class.
   - Network < 20% of instance limit -> smaller type may work.
4. **Implement gradually**: one instance at a time, monitor 48 hours.
5. **Automate**: Instance Scheduler for dev/test (stop outside business hours = 65% savings).

---

## Common Cost Traps

### Networking traps (often the biggest surprise)

**NAT Gateway, the silent budget killer:**
- Data processing: **$0.045/GB** through NAT Gateway.
- Hourly: $0.045/hr ($32.85/mo just for existing).
- 1 TB/mo: $45 data + $32.85 hourly = **$77.85/mo per AZ**.
- **Fix**: VPC Gateway Endpoints for S3/DynamoDB (free). Interface Endpoints for other AWS services.

**Cross-AZ data transfer:**
- $0.01/GB each direction ($0.02/GB round trip).
- Microservices at 10 GB/hr cross-AZ = **$146/mo**.
- **Fix**: AZ-affinity routing. Tightly coupled services in same AZ.

**Elastic IP charges:**
- All public IPv4 addresses: $0.005/hr = **$3.60/mo** (even when attached, as of Feb 2024).
- **Fix**: use IPv6 where possible. Audit and release unused EIPs.

### Compute traps

**Lambda over-provisioned memory:**
- 1024 MB x 1M invocations x 500ms = **$8.34/mo**.
- Same at 256 MB (if not CPU-bound): 256 MB x 1M x 700ms = **$2.92/mo**.
- **Fix**: use Lambda Power Tuning to find optimal memory/cost balance.

**Idle RDS instances:**
- db.r6g.xlarge running 24/7 unused: **$274/mo**.
- RDS stop auto-restarts after 7 days.
- **Fix**: Instance Scheduler. For temp needs, Aurora Serverless v2 (0.5 ACU idle = $43.80/mo).

**Unattached EBS volumes:**
- 500 GB gp3 sitting unused: **$40/mo**.
- **Fix**: `aws ec2 describe-volumes --filters Name=status,Values=available`. Set DeleteOnTermination.

### Storage traps

**DynamoDB On-Demand at scale:**
- 1,000 writes/sec On-Demand: $1.25/M x 2,592M/mo = **$3,240/mo**.
- Provisioned: 1,000 WCU x $0.00065/hr x 730 = **$474.50/mo** (85% savings).
- **Fix**: monitor CloudWatch ConsumedWriteCapacityUnits. Switch to Provisioned.

**S3 versioning without lifecycle:**
- 1 GB overwritten daily for a year = 365 GB stored = **$8.40/mo** for "1 GB".
- **Fix**: `NoncurrentVersionExpiration: NoncurrentDays: 30` or `NewerNoncurrentVersions: 3`.

**CloudWatch Logs ingestion:**
- $0.50/GB ingested. 10 GB/day = **$150/mo** just for ingestion.
- **Fix**: filter logs before ingestion. Set retention policies. No DEBUG in production.

### Database traps

**Aurora I/O charges (Standard mode):**
- Write-heavy at 1B I/Os/mo = **$200/mo** on top of compute + storage.
- **Fix**: switch to I/O-Optimized when I/O > 25% of total database cost.

**ElastiCache oversized for dev/test:**
- 3-node cache.r6g.large cluster: **$495/mo**.
- **Fix**: Serverless for dev/test. Or cache.t4g.micro: **$11.68/mo**.

**DynamoDB GSI over-indexing:**
- Table with 5 GSIs: every write costs 6x.
- **Fix**: audit GSI usage. Remove unused. Use sparse indexes.

**Read replica sprawl:**
- 5 Aurora replicas "just in case" at db.r6g.xlarge: **$1,679/mo** on top of writer.
- **Fix**: Aurora Auto Scaling (min 1, max based on load). Delete unused.

---

## Network Cost Drivers (Reference Table)

Network services are commonly the largest avoidable line item; NAT Gateway data processing is usually the single biggest driver.

| Service | Cost component | Typical driver |
|---------|---------------|----------------|
| NAT Gateway | Data processing | $0.045/GB, largest network cost for most |
| NAT Gateway | Hourly charge | $0.045/hr per NAT GW |
| Transit Gateway | Data processing | $0.02/GB per attachment |
| Transit Gateway | Hourly charge | $0.05/hr per attachment |
| VPN | Hourly charge | $0.05/hr per VPN connection |
| VPN | Data transfer | $0.09/GB outbound |
| ELB (ALB) | Hourly + LCU | $0.0225/hr + LCU charges |
| ELB (NLB) | Hourly + NLCU | $0.0225/hr + NLCU charges |
| Direct Connect | Port hours | $0.03 to $0.30/hr depending on speed |
| Data Transfer | Cross-AZ | $0.01/GB each direction |
| Data Transfer | Cross-Region | $0.02/GB |
| Data Transfer | Internet out | $0.09/GB (first 10 TB) |

### Network cost optimisation quick reference

| Finding | Recommendation |
|---------|---------------|
| High NAT GW data processing | Use VPC endpoints for S3/DynamoDB (free) |
| Multiple NAT GWs per AZ | Consolidate if traffic allows |
| Idle VPN connections | Delete unused VPN tunnels |
| Cross-AZ traffic | Co-locate resources in same AZ where possible |
| Oversized ELB | Right-size based on actual LCU/NLCU usage |
| Unused EIPs | Release unattached Elastic IPs ($0.005/hr) |

---

## "How do I reduce my AWS bill by 30%?"

Ordered by typical impact (largest savings first):

1. **Savings Plans / RIs** (20 to 40% on compute + databases).
2. **Right-size instances** (10 to 30% on over-provisioned resources).
3. **Storage tiering** (50 to 90% on infrequently accessed data).
4. **Eliminate waste** (unattached EBS, idle RDS, unused EIPs).
5. **VPC Endpoints** (eliminate NAT Gateway data charges).
6. **Spot Instances** (60 to 90% on fault-tolerant workloads).
7. **Auto-scaling** (match capacity to demand).
8. **Dev/test scheduling** (stop outside business hours = 65%).
9. **DynamoDB mode switch** (On-Demand to Provisioned = up to 85%).
10. **Log optimisation** (reduce CloudWatch Logs ingestion).

---

## Operational Workflows (Cost Explorer)

### Workflow: network cost analysis

When a user asks "how much is our AWS network costing?":

1. **Total network spend**: cost breakdown for VPC, Transit Gateway, NAT Gateway, VPN, ELB, Direct Connect.
2. **Trend**: monthly trend for network services over last 6 months.
3. **Top services**: rank network services by spend (NAT GW data processing is often #1).
4. **Per-region**: break down network costs by region.
5. **Forecast**: projected network spend for next month.
6. **Report**: network cost dashboard with optimisation recommendations.

### Workflow: cost anomaly investigation

When investigating unexpected charges:

1. **Daily breakdown**: get daily costs for the spike period.
2. **Service drill-down**: which service caused the spike?
3. **Region check**: was the spike in a specific region?
4. **Correlate**: cross-reference with CloudTrail for resource creation events.
5. **Report**: root cause and recommended action.

### Workflow: monthly cost review

For regular FinOps review:

1. **Month-over-month**: compare current vs previous month spending.
2. **Service breakdown**: top 10 services by cost.
3. **Network focus**: VPC, TGW, NAT GW, VPN, ELB, Direct Connect costs.
4. **Growth rate**: percentage change per service.
5. **Forecast**: next month projection.
6. **Report**: executive cost summary with trends.

### Operating rules for cost queries

- **Cost Explorer API charges $0.01 per request**: batch queries, avoid excessive polling.
- **Data lag**: cost data can be delayed up to 24 hours.
- **Unblended vs amortised**: clarify which cost type the user wants before reporting.
- **Audit trail**: log cost investigations for an audit record.

### Environment variables

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (or `AWS_PROFILE`).

---

## Cost Estimation Templates

### Web application stack (~$625/mo, ~$470/mo with Savings Plans)

```
Compute:  2x m6g.large Multi-AZ               $112.42
ALB:      $0.0225/hr + LCU                     $26.43
Aurora:   db.r6g.large                         $194.18
          Storage 100 GB                       $10.00
Cache:    ElastiCache cache.r6g.large          $164.98
S3:       500 GB + 5M GET + 1M PUT             $18.50
NAT:      2 AZs + 100 GB data                 $70.20
CW:       Basic monitoring                     $10.00
Egress:   200 GB transfer out                  $18.00
Total:                                        ~$625/mo
```

### Serverless API (~$14/mo)

```
Lambda:   2M invocations, 256MB, 200ms          $2.07
API GW:   HTTP API 2M requests                  $2.00
DynamoDB: On-Demand light usage                 $3.25
S3:       50 GB                                 $1.15
CW:       Basic                                 $5.00
Total:                                         ~$14/mo
```

### Data pipeline (~$340/mo)

```
Kinesis:  2 shards provisioned                 $21.90
          50M records/mo                        $0.70
Lambda:   50M invocations, 512MB, 500ms       $218.33
S3:       1 TB cumulative (lifecycle)          $23.00
Athena:   100 GB/mo scanned                     $0.50
CW Logs:  5 GB/day                             $75.00
Total:                                        ~$340/mo
Biggest lever: Lambda duration (60% of cost)
```

---

## Cross-Cutting Cost Checklist

### Compute
- [ ] Graviton instances where compatible (20 to 40% savings)
- [ ] Latest instance generation (better price/performance)
- [ ] Compute Optimizer reviewed quarterly
- [ ] Savings Plans for steady-state
- [ ] Spot for fault-tolerant workloads
- [ ] Auto Scaling configured
- [ ] Lambda using ARM + tuned memory
- [ ] Fargate tasks right-sized

### Networking
- [ ] S3 and DynamoDB Gateway Endpoints (free)
- [ ] Interface endpoints for high-traffic AWS services
- [ ] NAT Gateway data costs monitored monthly
- [ ] Single NAT Gateway in non-production
- [ ] CloudFront Price Class appropriate
- [ ] ALBs consolidated with host-based routing
- [ ] Alias records for AWS DNS entries (free queries)

### Storage and data
- [ ] All gp2 migrated to gp3
- [ ] S3 lifecycle policies on all buckets
- [ ] Unattached EBS volumes deleted
- [ ] DynamoDB On-Demand evaluated for Provisioned switch
- [ ] CloudWatch Logs retention policies set
- [ ] Aurora I/O mode evaluated (Standard vs I/O-Optimized)

### Security
- [ ] KMS key types matched to requirements
- [ ] S3 Bucket Keys enabled with SSE-KMS
- [ ] Secrets/parameters cached in application
- [ ] Parameter Store Standard (free) for non-secret config
- [ ] GuardDuty optional sources evaluated for cost
- [ ] Config recording limited to needed resource types
```
