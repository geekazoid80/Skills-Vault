---
name: gcp-cloud-ops
description: "Use for GCP implementation and operations across compute, serverless, containers, storage, databases, networking, security and identity, AI/ML, data platform, observability, and cost management. Vendor-specific cloud-ops skill in the cloud-ops family; owns GCP service selection and the cross-cutting cost, security, and project-hierarchy decisions, and routes to per-service references for depth. Triggers include \"GCP\", \"Google Cloud\", \"Google Cloud Platform\", \"Compute Engine\", \"Cloud Run\", \"GKE\", \"GKE Autopilot\", \"GKE Standard\", \"GKE Autopilot vs Standard\", \"Cloud Functions GCP\", \"Cloud Functions 2nd gen\", \"App Engine\", \"App Engine Standard\", \"App Engine Flexible\", \"Cloud Storage GCP\", \"Cloud Storage Autoclass\", \"Persistent Disk\", \"Hyperdisk\", \"Filestore GCP\", \"BigQuery\", \"BigQuery partitioning\", \"BigQuery clustering\", \"BigQuery slots\", \"BigQuery ML\", \"Cloud SQL GCP\", \"AlloyDB\", \"Cloud Spanner\", \"Spanner TrueTime\", \"Firestore GCP\", \"Bigtable\", \"Memorystore\", \"Valkey GCP\", \"global VPC\", \"GCP VPC\", \"Shared VPC\", \"Private Service Connect\", \"PSC\", \"Cloud NAT\", \"Cloud Armor\", \"Cloud CDN GCP\", \"Cloud Interconnect\", \"Dedicated Interconnect\", \"Partner Interconnect\", \"HA VPN\", \"Cloud VPN GCP\", \"Cloud DNS GCP\", \"Network Service Tiers\", \"GCP egress\", \"Workload Identity\", \"Workload Identity Federation\", \"VPC Service Controls\", \"GCP Secret Manager\", \"Security Command Center\", \"SCC GCP\", \"Cloud KMS GCP\", \"Identity-Aware Proxy\", \"IAP GCP\", \"Organisation Policies GCP\", \"GCP service accounts\", \"GCP IAM\", \"Vertex AI\", \"Vertex AI AutoML\", \"Model Garden\", \"Gemini API\", \"TPU\", \"Cloud TPU\", \"Pub/Sub\", \"Dataflow\", \"Apache Beam GCP\", \"Dataproc\", \"Cloud Composer\", \"Eventarc\", \"Cloud Build\", \"Artifact Registry\", \"Cloud Monitoring\", \"Cloud Logging\", \"Cloud Trace\", \"Cloud Profiler\", \"GCP observability\", \"VPC flow logs GCP\", \"Cloud audit logs\", \"GCP cost optimisation\", \"Sustained Use Discounts\", \"SUDs GCP\", \"Committed Use Discounts GCP\", \"CUDs GCP\", \"custom machine types GCP\", \"GCP right-sizing\", \"Cloud Recommender\", \"Active Assist\", \"billing export BigQuery\", \"GCP free tier\", \"Spot VMs GCP\", \"sole-tenant nodes\". References: compute.md (Compute Engine, Cloud Run, Cloud Functions, GKE, App Engine, MCP operational tooling), storage.md (Cloud Storage Autoclass, Persistent Disks, Hyperdisk, Filestore), database.md (BigQuery, Cloud SQL, AlloyDB, Spanner, Firestore, Bigtable, Memorystore), networking.md (global VPC, Shared VPC, PSC, Cloud Armor, Cloud Interconnect, HA VPN, egress pricing), security.md (IAM hierarchy, Workload Identity, VPC Service Controls, SCC tiers, Cloud KMS, IAP), ai-data.md (Vertex AI, TPUs, Pub/Sub, Dataflow, Dataproc, Composer, Cloud Build), cost.md (SUDs, CUDs, custom machine types, Recommender, billing export, strategic playbook), observability.md (Cloud Logging MCP tools and workflows, Cloud Monitoring MCP tools and metrics). For cloud selection and multi-cloud strategy see cloud-platform-selection; for GCP networking audit see gcp-networking-audit."
license: MIT
metadata:
  version: 1.0.0
---

# GCP cloud operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: gcp-cloud-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

The vendor-specific GCP entry point in the cloud-ops family. Owns GCP service selection plus the cross-cutting cost, security, and project-hierarchy decisions, and points at per-service references for depth. Every recommendation should address the trade-off triangle: performance, cost, and operational complexity.

Prices referenced anywhere in this skill and its references are us-central1 on-demand unless noted, and they drift. Treat every figure as an order-of-magnitude anchor and verify current pricing at https://cloud.google.com/pricing before quoting a number to a customer.

## When to use

- Choosing or sizing a GCP service (compute, storage, database, messaging, serverless, AI/ML) with cost and complexity trade-offs in view.
- Applying GCP-specific savings levers: Sustained Use Discounts (automatic, no commitment), custom machine types, Committed Use Discounts, Spot VMs, billing export to BigQuery.
- Setting up GCP security baselines (IAM hierarchy, Workload Identity Federation, VPC Service Controls, Secret Manager, Security Command Center, Cloud KMS) and project-hierarchy governance (Organisations, Folders, Shared VPC).
- Designing GCP networking (global VPC, Shared VPC, Private Service Connect, Cloud Armor, Cloud Interconnect, HA VPN, Cloud CDN, egress cost management).
- Building data pipelines, event-driven architectures, and AI/ML workloads (BigQuery, Vertex AI, Pub/Sub, Dataflow, Dataproc, Composer, Eventarc).
- Investigating GCP infrastructure health via Cloud Monitoring and Cloud Logging MCP tools.

## When not to use

- **Picking a cloud at all, or multi-cloud strategy** (GCP vs AWS vs Azure, cross-cloud service mapping, migration 7 Rs, FinOps practice): use `cloud-platform-selection`, the family-level meta skill.
- **GCP networking audit** (security-posture audit of firewall rules, VPC flow logs, CIS compliance, route table validation): that lives in `gcp-networking-audit`. This skill's `references/networking.md` provides design and operational depth; the audit procedure comes later.

## Service-category router

Load the reference that matches the request. Each is a standalone deep-dive.

| Category | Services | Reference |
|---|---|---|
| Compute | Compute Engine, Cloud Run, Cloud Functions, GKE, App Engine, Spot VMs, MCP ops | `references/compute.md` |
| Storage | Cloud Storage (Autoclass), Persistent Disks, Hyperdisk, Filestore | `references/storage.md` |
| Database | BigQuery, Cloud SQL, AlloyDB, Spanner, Firestore, Bigtable, Memorystore | `references/database.md` |
| Networking | Global VPC, Shared VPC, PSC, Cloud Armor, Cloud CDN, Interconnect, VPN, egress | `references/networking.md` |
| Security and identity | IAM, Workload Identity, VPC Service Controls, SCC, KMS, IAP, Audit Logs | `references/security.md` |
| AI/ML and data platform | Vertex AI, TPUs, Pub/Sub, Dataflow, Dataproc, Composer, Cloud Build | `references/ai-data.md` |
| Cost | SUDs, CUDs, custom machine types, Recommender, billing export, playbook | `references/cost.md` |
| Observability | Cloud Logging MCP, Cloud Monitoring MCP, investigation workflows | `references/observability.md` |

## Service-selection decision trees

### Compute

```
Need full VM control, GPU, or stateful workload (SAP, Oracle, HPC)?
  YES -> Compute Engine (pick machine family per references/compute.md)
  NO  -> Stateless HTTP service or container?
    YES -> Cloud Run (default; scale-to-zero, 1000-concurrent model, no cluster)
    NO  -> Need Kubernetes ecosystem?
      YES -> Expert in K8s or need node-level control?
        YES -> GKE Standard
        NO  -> GKE Autopilot (pay per pod; no management fee)
      NO  -> Simple event-driven function?
        YES -> Cloud Functions 2nd gen (built on Cloud Run)
        NO  -> Simple HTTP app, generous free tier?
          YES -> App Engine Standard
```

**Decision shortcuts:**
- Stateless HTTP service? Cloud Run (always).
- Event-driven, simple function? Cloud Functions 2nd gen.
- Need Kubernetes ecosystem? GKE Autopilot unless you need node-level control.
- Full VM control, GPU, stateful workload? Compute Engine.
- No Kubernetes, not stateless HTTP? Compute Engine on E2 to start.

### Database

```
Analytics warehouse / ad-hoc SQL at any scale?
  YES -> BigQuery (partitioned + clustered tables)
Relational?
  YES -> Need global distribution + 99.999% SLA?
    YES -> Cloud Spanner (minimum ~$657/mo; only if justified)
    NO  -> PostgreSQL workload, high performance or vector search?
      YES -> AlloyDB (4x throughput vs standard PG)
      NO  -> Cloud SQL (MySQL, PostgreSQL, SQL Server; simplest managed RDBMS)
Document (mobile/web/real-time)?
  YES -> Firestore Native mode
Wide-column, time-series, IoT, ML feature store?
  YES -> Bigtable (minimum ~$468/mo)
In-memory cache?
  YES -> Memorystore (Redis or Valkey)
```

### Storage

```
Object storage?
  YES -> Cloud Storage; enable Autoclass for mixed/unpredictable access
Block storage for VMs?
  YES -> pd-balanced (default); pd-ssd for databases; Hyperdisk for max IOPS
Shared filesystem (NFS)?
  YES -> Filestore Enterprise for production; Basic for dev/test
```

### Networking connectivity

```
On-premises connectivity?
  Latency-sensitive or compliance requirement?
    YES -> Cloud Interconnect (Dedicated 10/100G or Partner 50M-50G)
    NO  -> HA VPN ($0.025/hr/tunnel; BGP, 99.99% SLA)
Web application?
  Multi-region or global users?
    YES -> External HTTP(S) LB (anycast, single IP) + Cloud CDN + Cloud Armor
    NO  -> Regional External HTTP(S) LB
```

## GCP strategic differentiators

**Sustained Use Discounts (SUDs):** Automatic 30% discount on N1/N2/N2D/C2 instances running all month. No reservation, no upfront payment. AWS and Azure require manual RI/SP purchases for equivalent savings.

**Custom machine types:** Specify exact vCPU (1-96) and memory (0.9-6.5 GB/vCPU). Eliminates the over-provisioning forced by fixed AWS/Azure instance sizes.

**BigQuery:** Fully serverless data warehouse. No clusters, no indexes, no maintenance. Google's Dremel engine. Nothing equivalent in AWS Redshift or Azure Synapse at this operational simplicity.

**Cloud Run concurrency model:** A single instance handles up to 1000 concurrent requests versus AWS Lambda's strictly one-per-instance model. Dramatically lowers cost for high-throughput stateless services.

**Global VPC:** One VPC spans all regions without peering. Subnets are regional; routes are global. Simplifies multi-region architectures that AWS/Azure require VPC peering or Transit Gateway/VWAN to achieve.

**Per-second billing with a generous free tier:** Compute bills per second (1-minute minimum for VMs). Free tier includes: one e2-micro VM, 2M Cloud Functions invocations, 1 TB BigQuery queries, 2M Cloud Run requests, and 5 GB Cloud Storage per month.

## Top 10 cost rules

1. **SUDs are automatic; verify they apply.** Check billing reports for N1/N2/N2D/C2 families. 100% monthly usage yields ~30% off with zero effort.
2. **Use custom machine types.** Avoid paying for 32 GB when you need 20 GB.
3. **Partition and cluster BigQuery tables.** This is the biggest single cost lever. Reduces scanned data 90%+ and directly cuts per-query cost.
4. **Default to Cloud Run for stateless services.** Scale-to-zero, per-second billing, 1000-request concurrency. Hard to beat on cost.
5. **Convert predictable workloads to CUDs.** 1-year: up to 57% off. 3-year: up to 70% off. Resource-based CUDs apply across project and region.
6. **Use Spot VMs for fault-tolerant work.** 60-91% discount. No 24-hour lifetime limit unlike legacy preemptible.
7. **Enable Autoclass on Cloud Storage.** Automatic tier optimisation without lifecycle policy guesswork.
8. **Use GKE Autopilot for most Kubernetes workloads.** Pay per pod, not per node. Eliminates node overprovisioning.
9. **Batch-load into BigQuery; avoid streaming inserts.** Streaming: $0.05/GB. Batch from GCS: free.
10. **Export billing to BigQuery.** Build custom dashboards, anomaly detection, and cost allocation with SQL.

## Common pitfalls

**Using basic roles (Owner/Editor/Viewer) in production.** Basic roles are overly broad. Use predefined roles (e.g. `roles/bigquery.dataViewer`) or custom roles. Disable auto-created default service accounts.

**Ignoring BigQuery cost controls.** A single `SELECT *` on a petabyte table costs $6,250. Set `maximum_bytes_billed` on all queries. Use `--dry_run` in CI/CD. Partition and cluster every large table.

**Network egress surprise.** GCP Premium Tier egress is $0.08-0.23/GB, the most expensive of the big three clouds. Evaluate Standard Tier for latency-tolerant workloads ($0.04-0.08/GB). Use Cloud CDN for static content.

**Spanner for workloads that do not need it.** Minimum ~$657/mo for one regional node. Only justified for global strong consistency, 99.999% availability, or unlimited horizontal scale.

**Service account key files instead of Workload Identity.** JSON key files are security liabilities: rotation burden, leak risk. Use Workload Identity for GKE, Workload Identity Federation for GitHub Actions/AWS/Azure.

**GKE Standard when Autopilot suffices.** Standard charges $73/mo management fee and you pay for entire nodes. Autopilot has no management fee and bills per-pod resources. At below 80% utilisation, Autopilot is cheaper.

**Not setting budgets and alerts.** GCP does not stop resources when budget is exceeded. Set alerts at 50%, 90%, and 100%+ via Billing Console and export billing data to BigQuery for anomaly detection.

## Reference architecture patterns

**Cost-optimised web application (~$140-190/mo)**
Cloud Armor on External HTTP(S) LB (~$0.75/mo policy) + Cloud Run (scale-to-zero) + Cloud SQL Serverless (~$5-50/mo) + Memorystore Basic (~$7/mo) + Secret Manager (~$0.06/10K access)

**Production microservices (~$1,200-1,600/mo)**
External HTTP(S) LB + GKE Autopilot (per-pod pricing) + Cloud SQL Enterprise Plus (~$150+/mo) + Memorystore Standard (~$30/mo) + Pub/Sub + Cloud Run for internal services

**Analytics platform (~$500-2,000/mo depending on query volume)**
Cloud Storage (Autoclass) + BigQuery (partitioned, Standard Edition) + Dataflow (Streaming Engine) + Pub/Sub + Vertex AI (Prediction endpoints only when needed)

## Cross-references

- `cloud-platform-selection`: family-level strategy skill; use to decide whether to use GCP in the first place, or for cross-cloud service mapping, migration 7 Rs, and FinOps practice.
- `aws-cloud-ops`: AWS sibling skill; use for AWS-specific service selection and cost optimisation.
- `azure-cloud-ops`: Azure sibling skill; use for Azure-specific service selection and Hybrid Benefit guidance.
- `secrets-hygiene`: use when handling GCP service account keys, Secret Manager secrets, `GOOGLE_APPLICATION_CREDENTIALS`, or any credential that must not be committed or logged.
- `distributed-tracing`: use for Cloud Trace integration, OpenTelemetry collector configuration, span propagation, and tail-sampling decisions.
- `prometheus-configuration`: use for GCP Managed Prometheus (GMP) configuration, metric collection from GKE workloads, and recording rules.
- `grafana-dashboards`: use when building Cloud Monitoring or Managed Prometheus dashboards for GCP resources.
- `linux-host-bringup`: use when provisioning new Compute Engine VMs from scratch (OS baseline hardening, service account injection, startup scripts).
- `linux-host-ops`: use for day-to-day Compute Engine VM operations (log tailing, service management, disk expansion, ssh via IAP tunnel).
- `gcp-networking-audit`: VPC firewall audit, VPC flow log analysis, CIS GCP Benchmark NSG equivalents, route table validation.
