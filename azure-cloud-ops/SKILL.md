---
name: azure-cloud-ops
description: "Use for Azure implementation and operations across compute, storage, databases, networking, security and identity, data platform and messaging, and cost management. Vendor-specific cloud-ops skill in the cloud-ops family; owns Azure service selection and the cross-cutting cost, security, and governance decisions, and routes to per-service references for depth. Triggers include \"Azure\", \"Microsoft Azure\", \"Azure VM\", \"Azure Virtual Machine\", \"VM series\", \"Azure Kubernetes Service\", \"AKS\", \"Azure Container Apps\", \"App Service\", \"Azure Functions\", \"Container Apps\", \"Azure Batch\", \"Spot VM\", \"ARM-based VM\", \"Cobalt 100\", \"Azure Storage\", \"Blob Storage\", \"Azure Files\", \"Managed Disks\", \"Premium SSD\", \"Data Lake Storage\", \"Azure SQL\", \"Azure SQL Database\", \"Azure SQL Managed Instance\", \"Hyperscale\", \"Elastic Pool\", \"Cosmos DB\", \"CosmosDB\", \"Azure Cache for Redis\", \"Azure PostgreSQL\", \"Azure MySQL\", \"Azure VNet\", \"Virtual Network\", \"hub-spoke\", \"NSG\", \"Application Gateway\", \"Front Door\", \"ExpressRoute\", \"VPN Gateway\", \"Azure Firewall\", \"Private Endpoint\", \"Service Endpoint\", \"Traffic Manager\", \"DDoS\", \"Entra ID\", \"Azure IAM\", \"managed identity\", \"Azure RBAC\", \"Conditional Access\", \"Azure Key Vault\", \"Defender for Cloud\", \"Microsoft Sentinel\", \"Azure Policy\", \"PIM\", \"Bastion\", \"Data Factory\", \"Synapse Analytics\", \"Azure Databricks\", \"Event Hubs\", \"Service Bus\", \"Event Grid\", \"Azure OpenAI\", \"Azure cost optimisation\", \"Azure Cost Management\", \"Azure Hybrid Benefit\", \"AHUB\", \"Reserved Instances Azure\", \"Savings Plans Azure\", \"Azure Advisor\", \"right-sizing Azure\", \"Azure tagging strategy\", \"Dev/Test subscription\", \"management groups\", \"Azure subscriptions\", \"Azure landing zone\", \"Azure governance\", \"Azure Arc\", \"AHB\", \"Spot VMs Azure\". References: compute.md, storage.md, database.md, networking.md, security.md, data-platform.md, cost.md. For cloud selection and multi-cloud strategy see cloud-platform-selection; for Azure networking audit see azure-networking-audit. For Entra ID app registration depth see entra-app-lifecycle."
license: MIT
metadata:
  version: 1.0.0
---

# Azure cloud operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: azure-cloud-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

The vendor-specific Azure entry point in the cloud-ops family. Owns Azure service selection plus the cross-cutting cost, security, and governance decisions, and points at per-service references for depth. Every recommendation should address the trade-off triangle: performance, cost, and operational complexity.

Prices referenced anywhere in this skill and its references are US East unless noted, and they drift. Treat every figure as an order-of-magnitude anchor and verify current pricing at https://azure.microsoft.com/en-us/pricing/ before quoting a number to a customer.

## When to use

- Choosing or sizing an Azure service (compute, storage, database, networking, messaging) with cost and complexity trade-offs in view.
- Applying Azure-specific savings levers: Azure Hybrid Benefit, Reserved Instances, Savings Plans, Spot VMs, Dev/Test subscriptions, right-sizing via Azure Advisor.
- Setting up Azure security baselines (Entra ID, managed identities, Key Vault, Defender for Cloud, Azure Policy, RBAC) and multi-tenant governance (management groups, landing zones).
- Designing Azure networking (VNet hub-spoke, Private Endpoints, Front Door, Application Gateway, ExpressRoute, NSGs).
- Building data pipelines and event-driven architectures (Data Factory, Synapse, Event Hubs, Service Bus, Databricks).

## When not to use

- **Picking a cloud at all, or multi-cloud strategy** (Azure vs AWS vs GCP, cross-cloud service mapping, migration 7 Rs, FinOps practice): use `cloud-platform-selection`, the family-level meta skill.
- **Entra ID app registration and OAuth/OIDC lifecycle** (app registration, Conditional Access policy design, Managed Identity provisioning, MSAL integration, token validation): use `entra-app-lifecycle`, which owns that surface in depth.
- **Azure VNet networking audit** (security-posture audit of NSGs, route tables, peering, Flow Logs, CIS compliance): that lives in `azure-networking-audit`. This skill's `references/networking.md` provides design and operational depth; the audit procedure comes later.

## Service-category router

Load the reference that matches the request. Each is a standalone deep-dive.

| Category | Services | Reference |
|---|---|---|
| Compute | VMs, App Service, Functions, AKS, Container Apps, Batch | `references/compute.md` |
| Storage | Blob, Azure Files, Managed Disks, Data Lake Gen2 | `references/storage.md` |
| Database | Azure SQL, Cosmos DB, PostgreSQL Flexible, MySQL, Redis | `references/database.md` |
| Networking | VNet, NSG, Private Endpoints, Front Door, AppGW, ExpressRoute | `references/networking.md` |
| Security and identity | Entra ID/RBAC, Key Vault, Defender, Sentinel, Policy | `references/security.md` |
| Data platform and messaging | Data Factory, Synapse, Databricks, Event Hubs, Service Bus | `references/data-platform.md` |
| Cost | Hybrid Benefit, RIs, Savings Plans, Advisor, cost traps | `references/cost.md` |

## Compute selection decision tree

```
Need full OS control, GPU, SAP HANA, or legacy app?  -> Virtual Machine
No Kubernetes experience?
  Event-driven / sporadic?    -> Functions (Consumption)
  Containerised microservices -> Container Apps (Consumption)
  Web app / API               -> App Service (B1 up)
Kubernetes expertise present?
  Full K8s ecosystem needed?  -> AKS Standard tier
  Simpler containers OK?      -> Container Apps (Dedicated)
```

Default to Arm-based VMs (Dpsv6 / Cobalt 100) for new Linux workloads: 20 to 30 per cent savings over equivalent x64.

## Database selection

| Need | Service |
|---|---|
| Global distribution, sub-10ms p99, NoSQL | Cosmos DB (Autoscale mode) |
| SQL Server compatibility, to 4 TB | Azure SQL Database |
| SQL Server with CLR, SQL Agent, cross-DB queries | Azure SQL Managed Instance |
| >4 TB or hyperscale read scale-out | Azure SQL Hyperscale |
| Caching, session store, leaderboard | Azure Cache for Redis (Standard/Enterprise) |
| Data warehouse, ad-hoc queries | Synapse Serverless SQL |
| Data warehouse, sustained high-throughput | Synapse Dedicated SQL pool (paused when idle) |

## Networking selection

```
Multi-region web app with CDN + WAF?    -> Front Door (Standard ~$35/mo)
Regional web app + WAF?                 -> Application Gateway v2 (~$175/mo)
DNS-level failover / non-HTTP?          -> Traffic Manager (~$0.75/M queries)
On-premises connectivity, standard?     -> VPN Gateway (~$140/mo)
Latency-sensitive or compliance?        -> ExpressRoute (~$655/mo+)
Threat intelligence / TLS inspection?   -> Azure Firewall (~$912/mo; do not deploy for basic filtering: use NSGs, which are free)
```

## Top cost rules

1. **Scale to zero when possible.** Functions Consumption, Container Apps Consumption, and Azure SQL Serverless avoid idle cost entirely.
2. **Apply Azure Hybrid Benefit (AHUB).** Existing Windows Server and SQL Server licences cover Azure VMs and databases; savings of 40 to 85 per cent, stackable with Reserved Instances.
3. **Reserve predictable workloads.** 1-year RIs save 30 to 40 per cent; 3-year save 55 to 65 per cent. Savings Plans offer flexibility with slightly less discount.
4. **Use Spot VMs for fault-tolerant workloads.** Up to 90 per cent off for batch, CI/CD, and scale-out tiers.
5. **Default to Arm (Dpsv6) for Linux.** 20 to 30 per cent savings over equivalent x64 D-series.
6. **Use Dev/Test subscriptions.** Free Windows licensing and reduced rates for non-production (requires Visual Studio subscription or Enterprise Agreement).
7. **Right-size with Azure Advisor weekly.** VMs with average CPU below 5 per cent are over-provisioned.
8. **Pause what you can.** Synapse Dedicated pools, AKS dev clusters, and dev/test VMs on schedules.
9. **Set lifecycle policies on Blob Storage.** Hot to Cool at 30 days, Cold at 90, Archive at 180.
10. **Cap Log Analytics ingestion.** Chatty AKS clusters generate 50 to 100 GB/day at $2.76/GB. Use Basic Logs tier, adaptive sampling, and daily caps.

Deeper cost mechanics, the full traps list, and optimisation checklists are in `references/cost.md`.

## Azure-specific advantages to always surface

- **Azure Hybrid Benefit** stacks with Reserved Instances. A D4sv5 PAYG at ~$140/mo drops to ~$50/mo with RI + AHB.
- **Managed identities** eliminate service-principal secrets. Always prefer over secrets for Azure-hosted workloads. Same `DefaultAzureCredential` code works from local dev to production.
- **Availability Zones** provide 99.99% SLA at negligible cross-zone data cost (~$0.01/GB). Always deploy production across zones. Availability Sets are legacy.

## Multi-tenant governance structure

Production Azure environments should follow a management-group hierarchy:

- **Root management group**: tenant-wide Azure Policy (Deny effects for compliance)
- **Platform management group**: connectivity (hub VNet), identity (Entra ID), management (Log Analytics, Defender)
- **Landing zones management group**: corp (connected spoke VNets) and online (internet-facing) child groups
- **Sandbox management group**: isolated experimentation with budget caps

Key tools: Azure Policy (guardrails), Azure Blueprints or Bicep + deployment stacks (landing-zone templates), Defender for Cloud (security posture), Cost Management (budget alerts per subscription).

## Cross-references

- `cloud-platform-selection` (family meta skill): which cloud for which workload, multi-cloud strategy, cross-cloud service mapping, Well-Architected principles, migration 7 Rs, FinOps. Start there when the cloud itself is not yet decided.
- `entra-app-lifecycle`: Entra ID app registration and OAuth/OIDC lifecycle (Conditional Access policy design, Managed Identity provisioning, MSAL integration, token validation, AADSTS error triage). This skill owns the broader Azure security surface; entra-app-lifecycle owns the app-registration depth.
- `aws-cloud-ops` (sibling): the equivalent AWS vendor skill; cross-cloud service mapping lives in `cloud-platform-selection`.
- `gcp-cloud-ops` (live): the GCP sibling; GCP-specific compute, storage, database, GKE, Vertex AI, cost optimisation, and Cloud Monitoring/Logging MCP tooling.
- `azure-networking-audit`: VNet networking posture audit, NSG CIS compliance, Route Table validation, Network Watcher. This skill's `references/networking.md` owns design and operations; that skill owns the audit procedure.
- `secrets-hygiene`: credential-handling discipline that complements the Entra ID, Key Vault, and managed-identity material here.
- `linux-host-bringup` and `linux-host-ops`: in-guest configuration once Azure VMs are running.
- `grafana-dashboards`, `prometheus-configuration`, `distributed-tracing`: vendor-neutral observability that pairs with Azure Monitor and Application Insights patterns.

## Red flags

- Recommending a service without its cost model and a cheaper alternative considered.
- Quoting a price as current fact rather than an anchor to verify at the Azure pricing page.
- Recommending Azure Firewall for basic traffic filtering (NSGs are free; Firewall is $912/mo and warranted only for threat intelligence, TLS inspection, or FQDN-based filtering).
- Provisioning Cosmos DB RU/s without enabling Autoscale.
- Leaving Synapse Dedicated pools running 24/7 in non-production environments.
- Using an app-registration client secret for an Azure-hosted workload where managed identity would work.
- Omitting Availability Zones from a production deployment.
- Skipping resource tagging (CostCenter, Environment, Owner, Application) so cost attribution is impossible.

## Bottom line

Classify the request, load the matching reference, and frame every recommendation around performance, cost, and operational complexity with a concrete (verifiable) cost anchor. Defer cloud selection to `cloud-platform-selection`; defer Entra app-registration depth to `entra-app-lifecycle`; defer VNet audit procedure to `azure-networking-audit`.
