---
name: cloud-platform-selection
description: "Use for vendor-neutral cloud strategy across AWS, Azure, and GCP. Family-level entry point that owns the selection framework (which cloud for which workload), multi-cloud strategy, cross-cloud service equivalence mapping, Well-Architected principles (cross-cloud), migration strategy (7 Rs framework), and FinOps practice. Routes to vendor-specific cloud-ops skills for implementation depth. Triggers include \"which cloud should we use\", \"AWS vs Azure vs GCP\", \"cloud platform selection\", \"cloud platform comparison\", \"cloud strategy\", \"cloud architecture decision\", \"multi-cloud strategy\", \"when to go multi-cloud\", \"cloud lock-in\", \"cloud-agnostic architecture\", \"cross-cloud service mapping\", \"AWS to Azure equivalents\", \"AWS to GCP equivalents\", \"Azure to GCP equivalents\", \"cloud migration\", \"7 Rs framework\", \"retire retain rehost relocate replatform refactor repurchase\", \"migration sequencing\", \"migration waves\", \"cross-cloud migration\", \"cloud cost optimisation\", \"FinOps\", \"FinOps practice\", \"FinOps maturity\", \"cloud cost allocation\", \"tagging strategy for cost\", \"chargeback vs showback\", \"cloud unit economics\", \"cost per transaction\", \"cost per active user\", \"reserved instances\", \"savings plans\", \"committed use discounts\", \"spot preemptible cost\", \"cost anomaly detection\", \"Well-Architected\", \"AWS Well-Architected Framework\", \"Azure Well-Architected Framework\", \"GCP Cloud Architecture Framework\", \"cross-cloud design principles\", \"cloud reliability tier\", \"cloud disaster recovery tier\", \"cloud landing zone\", \"cloud governance pattern\", \"cloud egress cost\", \"cross-AZ traffic cost\", \"cloud sustainability\". Five reference files for depth: `references/well-architected.md` (cross-cloud design principles by pillar plus per-cloud framework summaries plus landing zone structures), `references/migration.md` (7 Rs decision tree plus four-phase migration sequencing plus per-cloud migration tooling plus data migration patterns plus certification paths), `references/service-mapping.md` (cross-cloud service equivalence tables across compute, storage, database, networking, security, serverless, AI/ML, data analytics, DevOps plus pricing model comparison plus egress pricing plus free tier comparison), `references/finops.md` (FinOps Foundation three-phase framework plus tagging strategy plus chargeback vs showback plus shared cost allocation plus anomaly detection plus commitment management plus unit economics plus cost optimisation wins by category). Diagnose-first; read tagging / billing / IAM telemetry before recommending architectural changes. Maps onto `multi-vendor-network-ops` nine-element response contract for production-impacting recommendations. Vendor depth lives in the `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops` skills. Customised from chrishuffman5/domain-expert/skills/cloud-platforms (MIT); em-dash purge, British / Pacific English, four-field vault frontmatter, vault skill cross-refs swapped."
license: MIT
metadata:
  version: 1.0.0
---

# Cloud Platform Selection

Family-level strategy skill for vendor-neutral guidance across AWS, Azure, and GCP. Owns cross-cloud material: selection criteria, multi-cloud strategy, service equivalence mapping, Well-Architected principles, migration framework (7 Rs), and FinOps practice. Vendor-specific implementation depth (compute / storage / database / IAM / cost optimisation tactics per cloud) lives in `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops` (all live).

This skill is the entry point for "which cloud" questions, multi-cloud architecture decisions, cloud migration planning, and FinOps practice. The cross-cloud reference files (well-architected, migration, service-mapping, finops) hold the depth; the umbrella body has the decision frameworks and decision trees that route to the appropriate reference or vendor skill.

> **Skill marker**: When applying this skill, begin your reply with `[skill: cloud-platform-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand existing cloud investments, compliance constraints, team skills, and stated cloud strategy before recommending anything. Only ask the user for information not already covered or specific to this investigation.

Before recommending a cloud direction, understand:

1. **Existing investments**
   - Active contracts (AWS EDP, Azure MACC, GCP committed spend)?
   - Tooling locked to one vendor (e.g. CloudFormation templates, Bicep, GCP Config Connector)?
   - Identity provider (Entra ID, Okta, IAM Identity Center) and how it federates to clouds?
2. **Workload characteristics**
   - Stateful or stateless; latency-sensitive or batch; data gravity (where the data lives now)?
   - Compute family (general purpose, memory-optimised, GPU, ARM-friendly)?
   - Compliance constraints (GovCloud, FedRAMP, sovereign cloud, data residency)?
3. **Team and organisation**
   - Existing cloud skills (which clouds have certified staff, comfort with serverless / containers / Kubernetes)?
   - Vendor relationship leverage (Microsoft EA / Google enterprise deal / AWS partner agreement)?
   - Hiring market for the cloud being considered?
4. **Cost context**
   - Steady-state spend or bursty; commitment willingness (1-year vs 3-year)?
   - Egress patterns (cross-AZ, cross-region, internet, to other clouds)?

## How to approach a request

Classify the request and route accordingly:

| Request type | Action |
|---|---|
| Cloud selection (which cloud for which workload) | Use the § "Cloud selection framework" below |
| Service mapping (AWS X to Azure Y to GCP Z) | Load `references/service-mapping.md` |
| Architecture review (cross-cloud principles) | Load `references/well-architected.md` |
| Migration planning (on-prem to cloud, or cross-cloud) | Load `references/migration.md` |
| Cost management or FinOps maturity | Load `references/finops.md` |
| Vendor-specific implementation | Route to `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops` (all live). Pair with `aws-networking-audit` for AWS VPC depth; for Entra ID app lifecycle, see `entra-app-lifecycle` |

## Cloud selection framework

The right cloud is determined by workload requirements, organisational context, and strategic goals. Vendor marketing does not pick the cloud; the workload and the organisation do.

### Vendor strengths summary

**AWS.** Broadest service catalogue (200+ services), largest talent pool, most third-party integrations (ISVs support AWS first), most mature serverless ecosystem (Lambda + EventBridge + Step Functions), broadest geographic coverage (33+ regions), strongest compliance-for-government story (GovCloud, FedRAMP High). Watch out for complex pricing, data egress costs (the only cloud charging cross-AZ traffic by default), IAM policy language complexity, service naming inconsistency.

**Azure.** Strongest hybrid story (Azure Arc, Azure Stack HCI), best fit for Microsoft-shop organisations (O365, Active Directory, SQL Server, .NET, SAP on Microsoft), Entra ID as a centralised identity provider that federates to non-Azure clouds and third-party SaaS, government and regulated industries (sovereign clouds). Watch out for service naming churn (frequent rebrands), portal UX complexity, networking model differences from AWS / GCP.

**GCP.** Best for data-intensive analytics workloads (BigQuery is best-in-class), Kubernetes-native architectures (GKE is Google-built; Google invented Kubernetes), AI / ML workloads (Vertex AI, TPU access), cost-sensitive workloads (automatic Sustained Use Discounts apply with no commitment, custom machine types let you pay for exact vCPU and RAM), real-time data processing (Pub/Sub plus Dataflow). Watch out for smaller service catalogue, smaller partner ecosystem, history of product deprecation, smaller talent pool, fewer regions.

### Decision factor matrix

| Factor | Favours AWS | Favours Azure | Favours GCP |
|---|---|---|---|
| Existing certified staff | AWS-certified | .NET / Windows / AD | Kubernetes / data engineering |
| Vendor relationships | AWS partner agreement | Microsoft EA / CSP | Google enterprise deal |
| Service-specific strength | Broadest catalogue | Identity, hybrid, SAP | Data, AI / ML, K8s |
| Talent availability | Largest pool | Large (.NET plus cloud) | Smaller, specialised |
| Cost optimisation tooling | RIs plus Savings Plans | RIs plus Hybrid Benefit | SUDs plus CUDs plus custom VMs |
| Enterprise integration | Broad ISV support | O365 / AD / SAP integration | Workspace / BigQuery |
| Compliance frameworks | Most certifications | Sovereign clouds, government | Strong EU data residency |

### Quick decision tree

```
Heavy Microsoft ecosystem (AD, O365, .NET, SQL Server)?
  YES -> Azure
  NO  -> Primary workload is data analytics or AI / ML?
    YES -> GCP (BigQuery, Vertex AI)
    NO  -> Kubernetes-native architecture?
      YES -> GCP (GKE) or AWS (EKS); both strong, pick on adjacent factors
      NO  -> Need broadest service catalogue or largest talent pool?
        YES -> AWS
        NO  -> All viable. Run a PoC on the top two; pick on team preference,
               pricing, and support experience.
```

### Decision process

1. Inventory constraints (regulatory, data residency, existing contracts, team skills).
2. Identify workload characteristics (compute type, data volume, latency needs, burst patterns).
3. Map to platform strengths (which cloud's native services best match the workload).
4. Evaluate total cost (compute plus egress plus support plus training plus hiring).
5. Assess vendor lock-in risk (how portable does the architecture need to be).
6. Run a proof of concept (always validate assumptions with a real PoC before committing).

## Multi-cloud strategy

### Types of multi-cloud

| Type | Description | Complexity | Best for |
|---|---|---|---|
| Best-of-breed | Different workloads on the cloud that best serves them | Moderate | Most practical approach |
| DR multi-cloud | Primary on one cloud, disaster recovery on another | Moderate | Cloud-level DR |
| Active multi-cloud | Workloads running simultaneously on multiple clouds | Highest | Maximum resilience |
| Lock-in avoidance | Abstraction layers for portability | High | Often counterproductive |

### Should you go multi-cloud?

```
Regulatory or compliance requires multiple clouds?
  YES -> Multi-cloud (compliance-driven)
  NO  -> Need cloud-level DR (not just region-level)?
    YES -> DR multi-cloud (passive second cloud)
    NO  -> Specific workloads clearly better on different clouds?
      YES -> Best-of-breed multi-cloud
      NO  -> M&A brought in a different cloud?
        YES -> Multi-cloud (consolidate over time)
        NO  -> Single cloud. Invest in depth, not breadth.
```

**Valid reasons.** Compliance and data-sovereignty requirements; cloud-level DR; genuinely different strengths for different workloads (BigQuery for analytics plus AWS for everything else); M&A bringing in a different cloud; negotiation leverage.

**Invalid reasons.** "Just in case" (maintaining two platforms is rarely justified); "cloud-agnostic is always better" (abstraction layers sacrifice 40-60% of cloud-native capabilities); FOMO (using every cloud's best feature requires staffing three platform teams).

**Recommendation.** Use cloud-native services as default. Use abstraction layers only where portability is a validated requirement, not a theoretical one.

### Abstraction layer trade-offs

| Abstraction | Portable? | Trade-off |
|---|---|---|
| Terraform / OpenTofu | IaC is portable | Cloud resources underneath are not; you still write provider-specific code |
| Kubernetes | Compute is portable | Storage, networking, IAM, managed services are cloud-specific |
| Pulumi | Same as Terraform | Same trade-offs, different language |
| Cloud-native services | Not portable | Higher performance, lower cost, more features, less operational burden |

### Key cross-cloud challenges

**Networking.** Site-to-site VPN between cloud VPCs (cheapest), dedicated interconnect partners (Megaport, Equinix Fabric), non-overlapping CIDR planning from day one. Transit architecture: hub VPC / VNet in each cloud connected via VPN or interconnect; spoke VPCs peer to hub. DNS: split-horizon or centralised with conditional forwarding. AWS VPC details live in `aws-networking-audit`.

**Identity.** Centralised IdP (Entra ID, Okta) federated to all clouds via SAML or OIDC. Use workload identity federation for service-to-service authentication. Avoid long-lived keys stored across clouds. Cross-cloud calls: short-lived tokens via OIDC federation.

**Governance.** Centralised guardrails, distributed execution. Single CI/CD platform (GitHub Actions, GitLab CI) deploying to all clouds. Single observability platform (per `grafana-dashboards`, `prometheus-configuration`, `distributed-tracing`) aggregating across clouds. Landing zone per cloud following cloud-native best practices. Consistent IaC tooling with shared modules per cloud.

## Cross-cloud service mapping (condensed)

For complete tables across compute, storage, database, networking, security, serverless, AI / ML, data analytics, and DevOps, load `references/service-mapping.md`. Key equivalences:

| Category | AWS | Azure | GCP |
|---|---|---|---|
| VMs | EC2 | Virtual Machines | Compute Engine |
| Managed Kubernetes | EKS | AKS | GKE |
| Serverless containers | Fargate | Container Apps | Cloud Run |
| Functions | Lambda | Functions | Cloud Functions |
| Object storage | S3 | Blob Storage | Cloud Storage |
| Managed RDBMS | RDS / Aurora | Azure SQL / Azure DB | Cloud SQL / AlloyDB |
| NoSQL key-value | DynamoDB | Cosmos DB | Bigtable |
| Data warehouse | Redshift | Synapse Analytics | BigQuery |
| CDN | CloudFront | Front Door | Cloud CDN |
| Identity | IAM | Entra ID plus RBAC | IAM |
| Secrets | Secrets Manager | Key Vault | Secret Manager |
| IaC (native) | CloudFormation | Bicep | Config Connector |
| Monitoring | CloudWatch | Monitor plus Log Analytics | Cloud Monitoring |
| ML platform | SageMaker | Azure ML | Vertex AI |
| LLM hosting | Bedrock | Azure OpenAI | Vertex AI Model Garden |

### Pricing model differences (high-level)

| Mechanism | AWS | Azure | GCP |
|---|---|---|---|
| Auto-discount (no commitment) | None | None | SUDs: up to 30 percent for VMs running 25 percent of month |
| Reserved 1-year | Up to 40 percent | Up to 40 percent | CUDs: up to 37 percent |
| Reserved 3-year | Up to 60 percent | Up to 60 percent | CUDs: up to 55 percent |
| Bring your own license | None | Hybrid Benefit (Windows / SQL): up to 85 percent | None |
| Custom machine types | None | None | Yes (pay for exact vCPU / RAM) |
| Spot / preemptible | Up to 90 percent (2-minute warning) | Up to 90 percent (30-second notice) | Up to 91 percent (30-second notice) |
| Cross-AZ egress within region | 0.01 USD per GB each direction | Free | Free |
| Internet egress (10 TB tier) | 0.09 USD per GB | 0.087 USD per GB | 0.085 to 0.12 USD per GB |

Key insight: Azure and GCP do not charge for cross-AZ traffic within a region; AWS charges 0.01 USD per GB each direction, which compounds for distributed architectures. GCP Sustained Use Discounts apply automatically with no commitment.

## Well-Architected principles (cross-cloud)

These principles apply regardless of cloud. For per-cloud framework details (AWS six pillars; Azure five pillars; GCP five focus areas) plus landing zone structures, load `references/well-architected.md`.

| Pillar | Core principle |
|---|---|
| Operational excellence | IaC everywhere, CI/CD pipelines, observability (metrics plus logs plus traces), deployment strategies (blue-green, canary) |
| Security | Zero trust, least privilege, encryption at rest and in transit, managed identities (no long-lived credentials), audit logging |
| Reliability | Multi-AZ minimum for production, health checks plus auto-healing, chaos engineering, explicit DR tiers (backup-restore through active-active) |
| Performance | Right-sizing, caching layers, async processing, auto-scaling, database read replicas, CDN for global audiences |
| Cost optimisation | Right-sizing (highest impact), reserved capacity for steady state, Spot for fault-tolerant, storage tiering, eliminate waste, tag everything |
| Sustainability | Fewer resources equals less energy, serverless when appropriate, ARM instances (better performance per watt), data lifecycle management |

### Anti-patterns to avoid (all clouds)

- Treating cloud like a data centre (lifting VMs without adopting elasticity or managed services).
- Over-engineering for scale (building for 10 million users when you have 10 thousand).
- Ignoring data gravity (data is expensive to move; place compute near data).
- Single AZ in production (one AZ failure takes down the application).
- No resource tagging (makes cost allocation and automation impossible).
- Overly permissive IAM (wildcard policies, admin access for services, shared credentials).
- Monolithic IaC (one Terraform state file for everything).

## Migration strategy overview (7 Rs)

For the full 7 Rs decision tree, four-phase migration sequencing, per-cloud tooling, data migration patterns, and certification paths, load `references/migration.md`. The framework at a glance:

| Strategy | Description | Effort | When |
|---|---|---|---|
| Retire | Decommission; no longer needed | Low | 10 to 20 percent of portfolio |
| Retain | Keep in current environment for now | None | Too complex or risky to move now |
| Rehost | Lift and shift to cloud VMs | Low to medium | Speed is priority |
| Relocate | VMware-to-VMware cloud migration | Low | Large VMware estate |
| Replatform | Targeted optimisations (e.g. self-hosted DB to managed) | Medium | Quick wins available |
| Refactor | Redesign as cloud-native (microservices, serverless) | High | Strategic applications |
| Repurchase | Replace with SaaS (Exchange to O365, CRM to Salesforce) | Medium | SaaS meets requirements |

Migration sequencing: Assess (application inventory plus dependency mapping), Mobilise (landing zone plus networking plus security baseline), Migrate in waves (start low-risk, build confidence), Optimise post-migration (right-size plus auto-scale plus managed services adoption).

## FinOps overview

For the full FinOps Foundation three-phase framework, tagging strategy, chargeback vs showback patterns, anomaly detection, commitment management, unit economics, and cost optimisation wins by category, load `references/finops.md`.

The three phases (iterative, not sequential):

1. **Inform**: visibility plus allocation via consistent tagging; dashboards by team / project / environment; unit economics (cost per transaction, cost per active user).
2. **Optimise**: right-sizing first (highest-impact), reserved capacity for steady state, Spot for fault-tolerant, storage tiering, eliminate waste.
3. **Operate**: budget policies plus automated enforcement, anomaly detection, monthly optimisation reviews, FinOps team or cloud centre of excellence.

Key metric: cloud cost as a percentage of revenue should decrease over time as you optimise and benefit from scale. If it is increasing, either revenue is declining or cloud waste is growing.

### Cost estimation checklist

When estimating cloud costs for a new workload, account for:

- Compute (VMs, containers, functions; include development and staging environments).
- Storage (object, block, file; include backups and snapshots).
- Database (instances, replicas, storage, IOPS, backups).
- Networking (load balancers, NAT gateways, VPN / interconnect, static IPs).
- Data transfer (egress to internet, cross-region, cross-AZ).
- Monitoring (metrics, logs, custom metrics, APM, traces).
- Security (WAF, DDoS protection, vulnerability scanning, KMS).
- Support plan (required tier for production SLA).
- Reserved capacity (subtract from on-demand estimates).
- Growth buffer (add 20 to 30 percent for unexpected growth).

## Vendor cloud-ops skills

The cloud-ops triad of vendor-specific skills (all live):

- `aws-cloud-ops` (live): AWS-specific compute (EC2, Lambda, ECS, EKS, Fargate), storage (S3, EBS, EFS), database (RDS, Aurora, DynamoDB), serverless patterns, messaging, security, observability, and AWS cost optimisation tactics. Pairs with `aws-networking-audit` for VPC-layer networking (which also holds the shared VPC design-and-cost reference).
- `azure-cloud-ops` (live): Azure-specific compute (VMs, AKS, App Service, Container Apps, Functions), storage (Blob, Files, Managed Disks), databases (Azure SQL, Cosmos DB, PostgreSQL Flexible, Redis), networking (VNet, NSG, Private Endpoints, Front Door, ExpressRoute), security (Entra ID/RBAC, Key Vault, Defender, Sentinel, Azure Policy), data platform and messaging (Data Factory, Synapse, Event Hubs, Service Bus), and Azure cost optimisation tactics (Hybrid Benefit, Reserved Instances, Savings Plans, Advisor). For Entra ID app registration depth, see also `entra-app-lifecycle`.
- `gcp-cloud-ops` (live): GCP-specific compute (Compute Engine, Cloud Run, GKE, Cloud Functions), storage (Cloud Storage Autoclass, Persistent Disks, Hyperdisk), databases (BigQuery, Cloud SQL, AlloyDB, Spanner, Firestore, Bigtable), networking (global VPC, Shared VPC, PSC, Cloud Armor, Interconnect), security (IAM hierarchy, Workload Identity Federation, VPC Service Controls, SCC, Cloud KMS), AI/ML and data platform (Vertex AI, TPUs, Pub/Sub, Dataflow, Dataproc), observability (Cloud Monitoring and Cloud Logging MCP tools), and GCP cost optimisation tactics (SUDs, CUDs, custom machine types, Active Assist, billing export to BigQuery).

## Cross-references

- `aws-networking-audit`: AWS VPC architecture, Security Group / NACL analysis, Transit Gateway, VPC Flow Log forensics. The cloud-platform-selection umbrella stays vendor-neutral; AWS VPC depth lives there.
- `multi-vendor-network-ops`: umbrella entry-point for general network work; nine-element response contract is the iron rule for any production-impacting cloud-architecture recommendation.
- `evpn-vxlan-fabric`: data-centre fabric depth. Cross-cloud fabric topologies that span DC and cloud reference this skill for the on-prem side and cloud-platform-selection for the cloud side.
- `secrets-hygiene`: IAM identities, federation tokens, BYOK / KMS / Key Vault / Cloud KMS keys, OIDC federation tokens. Never paste credentials into responses.
- `linux-host-bringup` and `linux-host-ops`: VM-level operating system discipline, complementary to cloud platform selection.
- `grafana-dashboards`, `prometheus-configuration`, `distributed-tracing`: cross-cloud observability platform; aggregates metrics, logs, traces from all clouds.
- `oncall-runbooks`: when a cloud issue becomes an incident, runbook structure applies (severity classification, mitigation-vs-resolution, blameless post-mortem with UTC timeline).
- `systematic-debugging`: Phase 1 boundary evidence (IAM vs network vs application vs cost-pricing) is the diagnose-before-generate pattern; especially useful when cloud bills surprise or workload performance regresses post-migration.
- `completion-gate` Layer 3: no claim of "migration complete", "cloud cost optimised", "multi-cloud architecture validated", or "landing zone deployed" without fresh post-checks in this turn.
- `plan-time-tooling`: cloud platform changes fire the `engineering:architecture` mandatory trigger (new tech choice, contract change) and `engineering:deploy-checklist` (infra change, first-cloud-deploy, OIDC federation).

## Red flags

- About to recommend a cloud without inventorying constraints (regulatory, existing contracts, team skills) first.
- About to recommend multi-cloud without a validated reason (compliance, cloud-level DR, M&A consolidation, or genuinely different workload-cloud fit); "just in case" multi-cloud is rarely justified.
- About to recommend an abstraction layer (Kubernetes, Terraform, service mesh) as the sole portability strategy without acknowledging that storage / networking / IAM / managed services remain cloud-specific.
- About to ignore egress costs in a multi-cloud or cross-region design; egress is the silent cost driver.
- About to skip the proof-of-concept step and commit to a cloud based on vendor sales conversations.
- About to recommend cloud architecture without a tagging strategy in place; untagged resources are invisible to cost management.
- About to set the overload bit on a transit cloud workload (the cloud equivalent: removing auto-scaling or health checks during maintenance) without confirming the blast radius.
- About to repeat any IAM key, OIDC token, BYOK material, or service-account JSON file from a pasted config.
- About to declare a cloud decision "made" without proof-of-concept evidence or a documented decision record (ADR per `plan-time-tooling`).

## Bottom line

The right cloud is determined by the workload, the existing organisational investments, and the team's skills, not by vendor marketing. Multi-cloud is justified by compliance, cloud-level DR, validated workload-cloud fit, or M&A; "just in case" multi-cloud is rarely justified. Use cloud-native services as the default; reserve abstraction layers for cases where portability is a validated requirement. FinOps practice (visibility, optimisation, governance) is non-optional at any meaningful scale. Vendor depth lives in `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`; cross-cloud strategy lives here.
