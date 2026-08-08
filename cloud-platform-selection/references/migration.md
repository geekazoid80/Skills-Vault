# Cloud migration strategy

> 7 Rs framework, migration sequencing, tools by cloud provider, data migration patterns, and cross-cloud migration considerations.

## The 7 Rs framework

Each application in a migration portfolio should be assigned one of these strategies based on business value, technical complexity, and organisational readiness.

### 1. Retire (decommission)

Shut down applications no longer needed. Duplicate functionality, no active users, technical debt not worth carrying. Effort: low (requires business sign-off and data archival). Typical: 10 to 20 percent of portfolio.

### 2. Retain (revisit later)

Keep in current environment. Recently upgraded on-prem, regulatory constraints, nearing end-of-life, too complex to move now. Revisit on a schedule; "retain" can become "ignore" without an audit cadence.

### 3. Rehost (lift and shift)

Move as-is to cloud VMs with minimal changes. Fast but does not leverage cloud-native benefits. Often results in higher cloud costs than on-prem without optimisation. Tooling: AWS Application Migration Service (MGN), Azure Migrate, GCP Migrate for Compute Engine.

### 4. Relocate (hypervisor-level lift and shift)

Move VMware VMs to cloud VMware environment without re-platforming. Low effort. Options: VMware Cloud on AWS, Azure VMware Solution, Google Cloud VMware Engine.

### 5. Replatform (lift, tinker, and shift)

Make targeted optimisations during migration without changing core architecture. Examples: self-hosted PostgreSQL to RDS or Cloud SQL, self-hosted Kafka to managed Kafka, custom deployment to container orchestration. Medium effort.

### 6. Refactor or re-architect

Redesign to be cloud-native. Microservices, serverless, event-driven. Best long-term results but highest cost and risk. Reserve for strategic applications with strong business case.

### 7. Repurchase (replace with SaaS)

Replace custom or on-prem software with SaaS equivalent. Examples: on-prem Exchange to O365, on-prem CRM to Salesforce, self-hosted monitoring to Datadog. Medium effort (data migration plus user training).

### Quick decision tree

```
Is the app still needed?
  NO  -> RETIRE
  YES -> Can it be replaced by SaaS?
    YES, meets requirements -> REPURCHASE
    NO  -> Does it need architectural changes?
      YES, major -> REFACTOR (if business case justifies)
      YES, minor -> REPLATFORM
      NO  -> Is it on VMware?
        YES -> RELOCATE (VMware-to-VMware)
        NO  -> REHOST (lift and shift)
Too complex or risky to move now?
  YES -> RETAIN (revisit in 6 to 12 months)
```

## Migration sequencing

### Four-phase approach

1. **Assess.** Build application inventory, classify by 7 Rs, identify dependencies, map to migration waves.
2. **Mobilise.** Set up landing zone, networking (VPN, Direct Connect, ExpressRoute, Interconnect), security baseline, CI/CD for infrastructure.
3. **Migrate in waves.** Start with low-risk, well-understood applications. Build confidence and skills. Increase complexity over waves.
4. **Optimise post-migration.** Right-size, implement auto-scaling, enable managed services, address performance issues discovered in cloud.

### Wave planning guidance

- **Wave 1.** Simple stateless applications with few dependencies. Low risk, high confidence building.
- **Wave 2.** Applications with basic database dependencies. Validate database migration tooling.
- **Wave 3.** Complex applications with multiple service dependencies. Test interconnectivity.
- **Wave 4.** Mission-critical applications. Apply all lessons learned from previous waves.
- **Wave 5.** Legacy or complex applications (mainframe, tightly coupled). Longest timeline.

## Migration tooling by cloud

### AWS migration tooling

| Tool | Purpose |
|---|---|
| Migration Hub | Central tracking dashboard for all migrations |
| Application Migration Service (MGN) | Automated rehost of servers (replaces CloudEndure) |
| Database Migration Service (DMS) | Continuous database replication for migration |
| Schema Conversion Tool (SCT) | Convert database schemas between engines |
| DataSync | High-speed data transfer to and from AWS |
| Snow Family (Snowball, Snowcone, Snowmobile) | Physical data transfer for large datasets |
| Transfer Family | Managed SFTP, FTPS, FTP for S3 and EFS |
| Migration Evaluator | Build business case for migration (TCO analysis) |

### Azure migration tooling

| Tool | Purpose |
|---|---|
| Azure Migrate | Central hub: discovery, assessment, migration of servers, databases, web apps |
| Database Migration Service | Online and offline database migration |
| Data Box (Disk, Standard, Heavy) | Physical data transfer devices |
| AzCopy | High-performance command-line data transfer |
| Azure Site Recovery | Disaster recovery and rehost migration |
| Azure Migrate App Containerization | Containerise ASP.NET and Java web apps |
| Storage Migration Service | Migrate file servers to Azure |
| Total Cost of Ownership Calculator | Build business case for Azure migration |

### GCP migration tooling

| Tool | Purpose |
|---|---|
| Migrate for Compute Engine | Automated VM migration with minimal downtime |
| Database Migration Service | Managed migration for MySQL, PostgreSQL, SQL Server to Cloud SQL or AlloyDB |
| Transfer Service | Online data transfer from on-prem, other clouds, or internet sources |
| Transfer Appliance | Physical data transfer device for large datasets |
| Migrate for Anthos | Containerise and migrate VMs to GKE |
| BigQuery Data Transfer Service | Automated data loading into BigQuery |
| Cloud Foundation Toolkit | IaC templates for landing zone setup |
| Rapid Migration Program (RaMP) | Methodology and tools for accelerated migration |

## Data migration patterns

### Online vs offline migration

**Online (network-based).** Continuous replication over network. Best for databases and active file systems. Tooling: DMS (all clouds), DataSync (AWS), AzCopy (Azure), Transfer Service (GCP).

**Offline (physical transfer).** Ship physical devices when network transfer would take too long.

| Dataset size | 100 Mbps link | 1 Gbps link | 10 Gbps link | Physical transfer |
|---|---|---|---|---|
| 1 TB | ~1 day | ~2.5 hours | ~15 minutes | Overkill |
| 10 TB | ~10 days | ~1 day | ~2.5 hours | Consider |
| 100 TB | ~100 days | ~10 days | ~1 day | Recommended |
| 1 PB | ~3 years | ~100 days | ~10 days | Required |

**Rule of thumb.** If transfer would take more than 1 week over available bandwidth, consider physical transfer.

### Database migration patterns

- **Homogeneous (same engine).** Use native backup and restore or replication for minimal downtime.
- **Heterogeneous (different engine).** Schema conversion plus DMS or CDC for data migration. Test extensively; schema conversion is never 100 percent automated.
- **Cutover strategy.** Dual-write during transition, switch reads first (read replica in cloud), then switch writes. Always have a rollback plan.

## Cross-cloud migration considerations

When migrating between clouds (not just from on-prem):

- **Data transfer costs.** Egress from source cloud is the primary cost driver. Use direct interconnects between clouds where possible.
- **Service parity.** Map source services to target equivalents using `references/service-mapping.md`. Identify gaps early.
- **Identity migration.** Recreate IAM policies, roles, and service accounts in target cloud. Re-evaluate least privilege rather than copying one-to-one.
- **DNS cutover.** Plan carefully. Lower TTLs before migration. Have a rollback plan.
- **Monitoring parity.** Ensure monitoring, alerting, and dashboards are functional in target before cutover.
- **Compliance re-certification.** Changing clouds may require re-certification for SOC 2, HIPAA, PCI DSS.

## Certification paths by cloud

For teams building cloud skills during or before migration:

**AWS.** Cloud Practitioner, then Solutions Architect Associate, then Developer or SysOps Associate, then Solutions Architect Professional, then Specialty (Security, Networking, Database, ML).

**Azure.** AZ-900 Fundamentals, then AZ-104 Administrator or AZ-204 Developer, then AZ-305 Architect Expert, then AZ-400 DevOps Engineer, then Specialty (AZ-500 Security, DP-300 Database).

**GCP.** Cloud Digital Leader, then Associate Cloud Engineer, then Professional Cloud Architect, then Professional Cloud DevOps, Security, Data, or ML Engineer.
