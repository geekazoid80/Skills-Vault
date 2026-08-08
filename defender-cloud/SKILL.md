---
name: defender-cloud
description: "Use for Microsoft Defender for Cloud (DfC, formerly Azure Security Center and Azure Defender) configuration, operations, and read-only posture audit. Covers Microsoft's CNAPP for Azure and multi-cloud: the foundational free CSPM tier versus the paid Defender CSPM plan, the Defender plans catalogue (Servers, Containers, Databases, Storage, App Service, Key Vault, Resource Manager, DNS, APIs), the secure score model and recommendations, Azure Arc onboarding plus the native AWS and GCP connectors, agentless scanning and the cloud security graph with attack-path analysis and the cloud security explorer, the regulatory compliance dashboard, workload protection controls (JIT VM access, adaptive application controls, file integrity monitoring, DevOps security), governance rules, Defender XDR portal correlation, and the Microsoft Graph Security API plus ARM REST and Azure Resource Graph for read-only audit. Also carries a read-only audit lens: foundational-only tenants with no Defender plans, Defender CSPM off so no attack paths, agentless scanning disabled, secure score stalled, JIT and FIM unconfigured, compliance standards unassigned, and governance with no owners. Do NOT use for: vendor-neutral CNAPP / CSPM / CWPP / CIEM / DSPM taxonomy and platform selection (route up to cloud-security-posture, the umbrella that owns \"which CNAPP\"); general Azure service configuration and operations (azure-cloud-ops); external outside-in attack surface (defender-easm); vulnerability programme design, CVSS/EPSS scoring, and remediation SLAs (vulnerability-management); GRC frameworks and compliance evidence (compliance-benchmark-audit); container and Kubernetes security depth (container-security). This skill owns Microsoft Defender for Cloud configuration and operations. References architecture.md, operations.md, api-and-automation.md. Triggers include \"Defender for Cloud\", \"Microsoft Defender for Cloud\", \"DfC\", \"secure score\", \"Defender for Servers\", \"Defender for Containers\", \"Defender plans\", \"Defender CSPM\", \"Azure Arc security\", \"regulatory compliance Azure\", \"JIT VM access\", \"adaptive application controls\", \"cloud security explorer\", \"attack path analysis Azure\", \"Azure Security Center\", \"Azure Defender\", \"agentless scanning Azure\", \"file integrity monitoring Azure\", \"DevOps security Azure\". For vendor-neutral CNAPP selection see cloud-security-posture; for general Azure operations see azure-cloud-ops; for external attack surface see defender-easm."
license: MIT
metadata:
  version: 1.0.0
---

# Microsoft Defender for Cloud

> **Skill marker**: When applying this skill, begin your reply with `[skill: defender-cloud]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Microsoft Defender for Cloud (DfC, formerly Azure Security Center and Azure Defender) configuration, operations, and read-only posture audit: Microsoft's cloud-native application protection platform (CNAPP) that pairs cloud security posture management (CSPM) with cloud workload protection (CWPP) across Azure, on-premises, and other clouds. It assumes the platform decision (Microsoft-native CNAPP rather than a third-party CNAPP) has already been made; for that vendor-neutral selection and the CNAPP/CSPM/CWPP/CIEM/DSPM taxonomy, route up to `cloud-security-posture`, the umbrella that owns "which CNAPP". The depth here is the free-versus-paid split, the Defender plans, the secure score and recommendations model, the cloud security graph with attack paths, multi-cloud onboarding, and the read-only audit lens that keeps a subscription covered and least-privilege.

## Overview

DfC has two layers, and the split is the single most important thing to get right:

- **Foundational CSPM (free)**: on for every Azure subscription at no cost. Secure score, security recommendations mapped to the Microsoft Cloud Security Benchmark (MCSB), the regulatory compliance dashboard, and asset inventory. No threat detection, no vulnerability assessment, no attack-path analysis.
- **Defender CSPM (paid plan)**: adds the cloud security graph, attack-path analysis, the cloud security explorer, agentless VM and container-image vulnerability scanning, data-aware security posture (DSPM), and cloud infrastructure entitlement management (CIEM).
- **The Defender plans (paid, per-resource CWPP)**: workload threat protection for Servers, Containers, Databases, Storage, App Service, Key Vault, Resource Manager, DNS, and APIs. Each plan protects one resource family with runtime alerts and, where relevant, vulnerability assessment.

Multi-cloud comes through Azure Arc (agent-based, brings the full Defender for Servers and Containers depth to AWS, GCP, and on-premises) and the native AWS and GCP connectors (agentless, CSPM visibility without an Arc agent). Everything correlates into the Microsoft Defender XDR portal alongside Defender for Endpoint, Defender for Office 365, and Entra ID signals.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (subscription and management-group structure, which Defender plans are on, whether the deployment is Azure-only or multi-cloud, the compliance frameworks required, the SIEM) before advising. Only ask for what is not already covered.

Before configuring or auditing, establish:

1. **Which layers are on.** Foundational CSPM only, Defender CSPM added, and which Defender plans are enabled and at what scope. A tenant running foundational-only has no threat detection and no attack paths, and advising a Defender CSPM or Defender-plan workflow to it is the most common category error.
2. **The scope.** Single subscription, a management group (the recommended enablement scope so new subscriptions inherit the plans), or multi-cloud. DfC is deepest at management-group scope; per-subscription enablement drifts as the estate grows.
3. **Azure-only or multi-cloud.** Azure-native, plus Arc-connected servers and Kubernetes, plus native AWS and GCP connectors. Multi-cloud is genuine but Azure is the deepest surface; Arc brings CWPP depth, the native connectors bring CSPM visibility only.
4. **The task class.** Posture and secure-score improvement, Defender-plan selection and configuration, regulatory compliance, workload protection (JIT, FIM, adaptive controls), DevOps security, or a read-only posture audit. The depth lives in different references.
5. **Read-only versus change.** An audit uses read-only ARM, Graph Security, and Resource Graph scope and never enables a plan, applies a Quick Fix, activates JIT, or changes a policy assignment. A configuration change (enabling a plan bills immediately, applying a Quick Fix mutates a resource) needs a change window and a rollback plan.

## When to use

- Deciding which Defender plans to enable and at what scope, what each plan protects, and the cost trade-off; enabling Defender CSPM for attack paths and agentless scanning.
- Improving secure score: reading recommendations, prioritising by potential score increase, using Quick Fix and Azure Policy remediation, assigning owners through governance rules.
- Standing up or reading the regulatory compliance dashboard: assigning a standard (CIS, NIST SP 800-53, PCI DSS, ISO 27001, SOC 2, HIPAA/HITRUST, FedRAMP, MCSB), drilling into failing controls, exporting evidence.
- Onboarding non-Azure workloads: Azure Arc for servers and Kubernetes (full CWPP depth), or the native AWS and GCP connectors (agentless CSPM).
- Configuring workload protection: JIT VM access, adaptive application controls, file integrity monitoring, and the Defender for Containers sensor and registry scanning.
- Wiring DevOps security: the GitHub, Azure DevOps, and GitLab connectors for IaC, dependency, secret, and image scanning with pull-request annotations.
- Querying the cloud security graph in the cloud security explorer and reading attack paths to critical assets.
- Automating read-only audit and reporting through the Microsoft Graph Security API, the ARM `Microsoft.Security` provider, and Azure Resource Graph.
- Running a read-only posture audit: foundational-only gaps, Defender CSPM off, agentless scanning disabled, stalled secure score, JIT and FIM unconfigured, unassigned compliance standards, ownerless governance.

## When not to use

- **Vendor-neutral CNAPP / CSPM / CWPP / CIEM / DSPM taxonomy and platform selection** (which CNAPP to buy, how the categories relate, comparing Microsoft against Wiz, Prisma Cloud, or others): use `cloud-security-posture`. Defender for Cloud is the Microsoft CNAPP vendor; the umbrella owns "which CNAPP", this skill owns DfC configuration and operations, exactly as a vendor skill routes to its umbrella.
- **General Azure service configuration and operations** (subscription and management-group design, RBAC, networking, Azure Policy beyond the DfC initiative, resource provisioning): use `azure-cloud-ops`. DfC assesses and protects Azure resources; it does not own the Azure platform.
- **External outside-in attack surface** (internet-facing asset discovery from the attacker's view, the Defender EASM service): use `defender-easm`. Defender CSPM has an EASM integration, but the discovery engine and its depth live in the sibling service.
- **Vulnerability programme design** (CVSS and EPSS scoring, remediation SLAs, the org-wide vuln management lifecycle): use `vulnerability-management`. DfC surfaces workload vulnerability findings from agentless scanning and MDVM; it does not own the programme design that consumes them.
- **GRC frameworks and compliance evidence** (control frameworks, audit evidence workflows, benchmark authoring): use `compliance-benchmark-audit`. DfC ships a regulatory compliance dashboard mapped to standards; the GRC programme around it is a separate skill.
- **Container and Kubernetes security depth** (Kubernetes hardening, admission control, supply chain, runtime beyond the DfC sensor): use `container-security`. Defender for Containers is the DfC plan; the deep Kubernetes security discipline is the sibling skill.
- **Storing the app secret, certificate, or admin credential**: use `secrets-hygiene`. Never inline a live secret in a saved API call, a runbook, or a config file.

This skill **owns Microsoft Defender for Cloud configuration and operations**. Route CNAPP selection, general Azure ops, external attack surface, vuln-programme design, GRC, and container depth out per the list above; keep everything DfC here.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / model | Foundational versus Defender CSPM, the Defender plans catalogue, the secure score model, Azure Arc and native-connector onboarding, agentless scanning, the cloud security graph and attack-path analysis and cloud security explorer, Defender XDR correlation | `references/architecture.md` |
| Operations / audit | Enabling and scoping plans, the regulatory compliance dashboard, secure-score improvement, JIT VM access, adaptive application controls, file integrity monitoring, DevOps security, recommendations and governance rules, workload alerts, and the read-only audit lens with a threshold table and decision trees | `references/operations.md` |
| API / automation | Microsoft Graph Security API, the ARM `Microsoft.Security` provider, Azure Resource Graph posture queries, secure-score and assessments and sub-assessments endpoints as a read-only posture, OAuth app-registration auth, throttling, pagination, secret-store discipline | `references/api-and-automation.md` |

## Core model (condensed)

**Foundational CSPM is the floor; Defender CSPM and the Defender plans are the paid ceiling.** Every subscription already has the free tier: secure score, MCSB recommendations, the regulatory compliance dashboard, asset inventory. It has no threat detection, no vulnerability assessment, and no attack paths. Defender CSPM (paid) adds the cloud security graph, attack-path analysis, the cloud security explorer, agentless scanning, DSPM, and CIEM. The Defender plans (paid, per resource) add runtime workload protection per resource family. Advising a Defender CSPM or Defender-plan workflow to a foundational-only tenant is the most common category error, so pin the layers before recommending.

**Secure score is control-binary, not resource-linear.** The score is points earned over points available. Recommendations group into security controls; a control contributes its points only when every recommendation in it is healthy for every in-scope resource. Partial completion earns zero for that control. So the highest-leverage move is the control with the largest potential score increase and the fewest remaining unhealthy resources, not simply the one with the most findings.

**The Defender plans map one plan to one resource family.** Servers (P1 brings Defender for Endpoint plus JIT; P2 adds FIM, adaptive controls, vulnerability assessment, and free Log Analytics ingestion), Containers, Databases (SQL, Cosmos DB, open-source engines), Storage (with malware scanning), App Service, Key Vault, Resource Manager, DNS, and APIs. Enable the plans the estate actually runs, ideally at management-group scope so new subscriptions inherit them; enabling a plan bills immediately.

**Multi-cloud is Arc for depth, native connectors for breadth.** Azure Arc installs the Connected Machine agent so an AWS EC2, GCP GCE, or on-premises VM appears as an Azure resource and can carry the full Defender for Servers and Containers depth. The native AWS and GCP connectors use a cross-account IAM role or a service account to pull posture data agentlessly, giving CSPM visibility and, with Defender CSPM, agentless VM and container scanning, but not the agent-based runtime depth.

**The cloud security graph is the attack-path engine.** With Defender CSPM on, DfC builds a graph of resources, identities, network exposure, and data, enriched with CVE data from agentless scanning and data classification from DSPM. Attack-path analysis walks that graph to surface multi-hop routes to critical assets (internet-exposed VM with a critical CVE and a managed identity that reaches a storage account holding sensitive data), and the cloud security explorer is the query interface over the same graph. Without Defender CSPM there is no graph, so there are no attack paths.

**Least privilege and full coverage are the through-line.** Foundational-only with no Defender plans, Defender CSPM off so no attack paths, agentless scanning disabled, secure score stalled with no owners, JIT and FIM unconfigured on P2 servers, compliance standards never assigned, governance rules with no owners or SLAs: these are the recurring findings. Enable the plans the estate needs, turn on Defender CSPM for the graph, assign the standards you are audited against, and give every recommendation an owner.

## Reference router

| Need | Load |
|---|---|
| The foundational-versus-Defender-CSPM split, the full Defender plans catalogue and what each protects, the secure score model, Azure Arc and native AWS/GCP connector onboarding, agentless scanning, the cloud security graph with attack-path analysis and the cloud security explorer, and Defender XDR correlation | `references/architecture.md` |
| Enabling and scoping Defender plans, the regulatory compliance dashboard and standards, the secure-score improvement workflow, JIT VM access, adaptive application controls, file integrity monitoring, DevOps security connectors, recommendations and governance rules, workload protection alerts, and the read-only audit lens with a threshold table and remediation decision trees | `references/operations.md` |
| The Microsoft Graph Security API, the ARM `Microsoft.Security` resource provider, Azure Resource Graph posture queries, the secure-score and assessments and sub-assessments endpoints as a read-only posture, the OAuth app-registration flow with placeholder tokens, throttling and backoff, pagination, and secret-store discipline | `references/api-and-automation.md` |

## Cross-references

- `cloud-security-posture`: the vendor-neutral CNAPP umbrella; consult for the CSPM/CWPP/CIEM/DSPM taxonomy and for choosing between Microsoft and other CNAPP vendors. DfC is the Microsoft implementation of what that skill describes generically.
- `azure-cloud-ops`: the Azure platform substrate (subscriptions, management groups, RBAC, networking, Azure Policy); DfC assesses and protects it but does not own it.
- `defender-easm`: the sibling Microsoft service for external outside-in attack surface, integrated into Defender CSPM but owning its own discovery depth.
- `vulnerability-management`: the org-wide vuln programme (CVSS, EPSS, SLAs) that consumes the findings DfC surfaces from agentless scanning and MDVM.
- `compliance-benchmark-audit`: the GRC and evidence discipline around the standards the DfC regulatory compliance dashboard maps to.
- `container-security`: the deep Kubernetes and container security skill; Defender for Containers is the DfC plan that feeds it.
- `defender-for-endpoint`, `defender-for-office-365`, `defender-easm`: sibling Microsoft Defender services that correlate with DfC inside the Defender XDR portal.
- `identity-access-management`: the Entra ID and CIEM substrate; DfC's CIEM reads permissions, but the identity platform is a separate skill.
- `siem-soar-investigation`: when DfC alerts stream to Microsoft Sentinel or another SIEM for correlation and long-term retention.
- `secrets-hygiene`: the app secret, certificate, and admin credential live in the secret store, never inline in a saved API call or runbook.

## Red flags

- Advising a Defender CSPM or Defender-plan workflow (attack paths, agentless scanning, JIT, FIM, workload alerts) to a tenant running foundational CSPM only.
- Foundational CSPM only with no Defender plans enabled: secure score and recommendations exist, but there is zero threat detection and zero vulnerability assessment.
- Defender CSPM off: no cloud security graph, so no attack-path analysis and no cloud security explorer, even though the marketing implies a full CNAPP.
- Agentless scanning disabled under Defender CSPM: VMs and container images go unscanned when the coverage was available at no extra agent cost.
- Plans enabled per-subscription instead of at management-group scope: new subscriptions land unprotected and drift is invisible until an incident.
- Secure score treated as resource-linear: chasing the recommendation with the most findings instead of the control with the highest potential score increase and fewest remaining unhealthy resources.
- Defender for Servers P2 enabled but JIT VM access and file integrity monitoring never configured: the capabilities are paid for and unused, management ports stay open.
- Adaptive application controls left in audit mode indefinitely: anomalous processes are logged but never blocked.
- Regulatory compliance standards never assigned: the dashboard shows only the default MCSB, and the framework the tenant is actually audited against is absent.
- Governance rules absent or ownerless: recommendations have no assigned owner and no SLA, so remediation never happens and secure score stalls.
- A native AWS or GCP connector mistaken for full CWPP: the connector gives CSPM visibility only; agent-based runtime depth needs Arc.
- Pasting an app secret, certificate password, or admin credential into a saved API URL, a runbook, or a committed file instead of the secret store.
- Running an audit with write scope (enabling a plan, applying a Quick Fix, activating JIT, changing a policy assignment) during what was meant to be a read-only review.

## Bottom line

Defender for Cloud is Microsoft's CNAPP: a free foundational CSPM floor (secure score, MCSB recommendations, compliance dashboard, inventory) with a paid Defender CSPM plan on top (the cloud security graph, attack paths, the cloud security explorer, agentless scanning, DSPM, CIEM) and per-resource Defender plans for workload protection (Servers, Containers, Databases, Storage, App Service, Key Vault, Resource Manager, DNS, APIs). Pin which layers are on before you advise, enable plans at management-group scope, turn on Defender CSPM for the graph and agentless scanning, assign the compliance standard you are audited against, configure JIT and FIM where you pay for P2, and give every recommendation an owner. Onboard non-Azure through Arc for depth or the native connectors for breadth, correlate in Defender XDR, and keep every credential in the secret store. Route CNAPP selection to `cloud-security-posture`, general Azure ops to `azure-cloud-ops`, external attack surface to `defender-easm`, vuln-programme design to `vulnerability-management`, GRC to `compliance-benchmark-audit`, and container depth to `container-security`.

## Reference files

- `references/architecture.md`: the foundational-versus-Defender-CSPM split with the full capability matrix, the Defender plans catalogue and what each plan protects and detects, the secure score model and how controls contribute points, the CSPM policy-based assessment pipeline and CWPP agent options, Azure Arc onboarding and the native AWS and GCP connectors, agentless scanning mechanics, the cloud security graph with attack-path analysis and the cloud security explorer, the Log Analytics workspace relationship, and Defender XDR and SIEM correlation.
- `references/operations.md`: enabling and scoping Defender plans, the regulatory compliance dashboard and standards, the secure-score improvement workflow, JIT VM access, adaptive application controls, file integrity monitoring, the DevOps security connectors, recommendations and Quick Fix and governance rules, workload protection alerts, and the read-only posture-audit lens with a threshold table and remediation decision trees.
- `references/api-and-automation.md`: the Microsoft Graph Security API (alerts and secure score), the ARM `Microsoft.Security` resource provider (pricings, assessments, sub-assessments, JIT policies), Azure Resource Graph for posture queries, the OAuth app-registration client-credentials flow with placeholder tokens only, throttling and backoff, pagination, and the secret-store discipline for API credentials.
</content>
</invoke>
