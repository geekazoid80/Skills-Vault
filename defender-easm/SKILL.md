---
name: defender-easm
description: Use for Microsoft Defender External Attack Surface Management (Defender EASM) configuration and operations. Covers the Azure-native EASM service (workspace as an Azure resource, per-asset pricing, Microsoft's global internet scan infrastructure), workspace deployment (Azure portal, Azure CLI az easm, Terraform azurerm_easm_workspace), discovery seeds and discovery groups (domains, IP blocks, ASNs, hosts, email contacts, WHOIS organisations) with discovery frequency, asset inventory management and asset states (Candidate, Confirmed Inventory, Dependencies, Monitor Only, Requires Investigation, Dismissed, Archived), asset labels, risk analysis (the attack surface summary dashboard, Insight Cards, observation categories like exposed RDP/SSH/databases and expired SSL, CVE integration mapping detected versions to KEV-flagged CVEs), Azure integration (Defender for Cloud external attack surface, Microsoft Sentinel data connector with EasmAsset_CL and EasmInsight_CL tables and KQL, Logic Apps and Power Automate workflows), the REST API with Azure AD token authentication and Python, and pricing and cost control (dismiss non-assets, archive decommissioned). References deployment-and-inventory.md, risk-analysis.md, azure-integration.md. Triggers include "Defender EASM", "Microsoft EASM", "Defender External Attack Surface", "Azure EASM", "Microsoft attack surface management", "EASM discovery group", "EASM asset state", "EasmInsight_CL", "az easm". For the vendor-neutral external attack surface management design and concepts this configures see attack-surface-management; for scanning and prioritising the CVEs it surfaces see vulnerability-management; for the CVE lookup see nvd-cve; for the broader Azure and identity context see azure-cloud-ops and entra-id; for credential and token handling see secrets-hygiene.
license: MIT
metadata:
  version: 1.0.0
---

# Microsoft Defender EASM

> **Skill marker**: When applying this skill, begin your reply with `[skill: defender-easm]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill builds and operates Microsoft Defender External Attack Surface Management: workspace deployment, discovery seeds and groups, inventory and asset states, risk analysis, and Azure-ecosystem integration. It assumes the decision to use Defender EASM and the EASM strategy are settled; the vendor-neutral discovery, attribution, and exposure-reduction reasoning lives in `attack-surface-management`. The depth here is the Azure-native implementation and its Defender for Cloud and Sentinel integrations.

## When to use

- Deploying a Defender EASM workspace (portal, Azure CLI, Terraform) and configuring discovery seeds and groups.
- Managing the discovered inventory: working assets through the state model, applying labels.
- Reading risk analysis: the attack surface summary, Insight Cards, observations, CVE findings.
- Integrating with Defender for Cloud, Microsoft Sentinel (KQL on EASM tables), and Logic Apps / Power Automate.
- Automating via the REST API; controlling cost through asset states.

## When not to use

- **The vendor-neutral EASM design and concepts** (discovery methods, attribution strategy, the EASM-to-VM loop, surface reduction): use `attack-surface-management`. This skill is the Defender EASM implementation of that.
- **Scanning and prioritising the CVEs EASM surfaces** (credentialed scan, SLA, remediation): use `vulnerability-management`.
- **A different EASM platform**: Xpanse, Falcon Surface, and Censys are named in `attack-surface-management`; this skill is Microsoft only.
- **Broader Azure posture and identity** (CSPM recommendations, Entra configuration): use `azure-cloud-ops` and `entra-id`.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Deployment + inventory | workspace creation (portal/CLI/Terraform), discovery seeds and groups, asset states, labels | `references/deployment-and-inventory.md` |
| Risk analysis | the attack surface summary dashboard, Insight Cards, observation categories, CVE integration | `references/risk-analysis.md` |
| Azure integration | Defender for Cloud, Sentinel connector and KQL, Logic Apps / Power Automate, the REST API, pricing and cost control | `references/azure-integration.md` |

## Core model (condensed)

**Defender EASM is an Azure resource that scans the internet for you.** The workspace lives in a subscription and region, is priced per confirmed asset, and uses Microsoft's global internet-scan infrastructure to discover internet-facing assets from the outside in. Its differentiator is depth of Azure integration: organisations already in the Microsoft security stack (Sentinel, Defender for Cloud, MDE) get correlated external-plus-internal exposure context that standalone EASM tools cannot match. It is younger and less automation-rich than Xpanse or Falcon Surface, but competitively priced.

**Discovery runs from seeds.** Create a discovery group seeded with domains, IP blocks, ASNs, hosts, email contacts (finds certificates carrying that email), and WHOIS organisation names; set a frequency (weekly default) and run. The internet-scan engine enumerates outward from the seeds.

**Work assets through the state model.** Every discovered asset starts as a **Candidate**; review and promote it to **Confirmed Inventory** (yours) or **Dismissed** (not yours). Other states are Dependencies (third-party your assets rely on), Monitor Only (subsidiaries, partners), Requires Investigation, and Archived (was yours, now decommissioned). Attribution discipline here is also cost discipline: only confirmed assets are billable, so dismiss non-assets and archive decommissioned ones.

**Risk surfaces as Insight Cards and observations.** The attack surface summary dashboard groups exposed services (web, email, VPN, remote access), SSL/TLS issues (expired, expiring, weak ciphers, self-signed), and CVEs on detected software versions, filterable by severity and CISA KEV. Observations flag policy violations like internet-exposed RDP/SSH/databases, public Kubernetes APIs, and unauthenticated admin panels.

**The Azure integrations are the reason to choose it.** Export inventory to Defender for Cloud to correlate external exposure with CSPM recommendations; stream findings to Sentinel (`EasmAsset_CL`, `EasmInsight_CL`) for KQL correlation with endpoint alerts; and drive remediation with Logic Apps / Power Automate.

## Reference router

| Need | Load |
|---|---|
| Workspace deployment (portal/CLI/Terraform), discovery seeds and groups, asset state model, labels | `references/deployment-and-inventory.md` |
| Attack surface summary dashboard, Insight Cards, observation categories, CVE integration | `references/risk-analysis.md` |
| Defender for Cloud integration, Sentinel connector and KQL queries, Logic Apps / Power Automate, the REST API and Python, pricing and cost control | `references/azure-integration.md` |

## Cross-references

- `attack-surface-management`: the vendor-neutral EASM design this skill implements. Reciprocal reference: that umbrella decides discovery strategy and whether Defender EASM fits; this skill configures it.
- `vulnerability-management`: where a confirmed exposed asset goes for credentialed scanning, prioritisation, and SLA-tracked remediation (the EASM-to-VM loop).
- `nvd-cve`: the CVE lookup behind a detected-version finding.
- `azure-cloud-ops`, `entra-id`: the broader Azure posture and identity context; Defender for Cloud CSPM correlation and the Azure AD token for the API.
- `siem-soar-investigation`: Sentinel is the SIEM that ingests EASM findings for correlation and detection.
- `secrets-hygiene`: the Azure AD token and any Logic App / API credentials live in the secret store, never inline.

## Red flags

- About to leave discovered assets as Candidate or Confirmed without attribution review (false positives and inflated billing).
- About to treat Defender EASM as a vulnerability scanner rather than a discovery-and-exposure tool (route CVE remediation to `vulnerability-management`).
- About to skip the Defender for Cloud / Sentinel integration, forgoing the one advantage that justifies choosing it.
- About to leave decommissioned assets as Confirmed (billable) instead of Archived.
- About to embed the Azure AD token or a Logic App credential inline instead of the secret store.

## Bottom line

Stand up the workspace, seed a discovery group, and work assets through the state model with real attribution review (it is both accuracy and cost control). Read risk from the Insight Cards and observations, and route the CVEs to `vulnerability-management`. The reason to pick Defender EASM over a standalone tool is the Azure integration, so wire up Defender for Cloud and Sentinel. Route the EASM strategy back to `attack-surface-management`.
