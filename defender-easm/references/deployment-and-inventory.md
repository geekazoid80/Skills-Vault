# Deployment and inventory

## Product overview

Microsoft Defender EASM is an Azure-native external attack surface management service. It is an Azure resource deployed in a subscription and region, priced per confirmed asset (IP/domain count, not per user), uses Microsoft's global internet-scan infrastructure, and offers a free trial for an initial discovery assessment. It fits organisations already in the Microsoft security stack (Sentinel, Defender for Cloud, MDE) and those preferring Azure-native deployment and pricing. Compared with Xpanse or CrowdStrike Falcon Surface it is younger (launched 2022) with fewer pre-built non-Microsoft integrations, so SOAR work needs more custom build.

## Creating a workspace

**Azure portal:** search Defender EASM in the Marketplace, create the resource (subscription, resource group, a region near operations, a name like `easm-companyname-prod`); it deploys in about two minutes.

**Azure CLI:**

```bash
az provider register --namespace Microsoft.Easm
az easm workspace create \
  --workspace-name "easm-prod" \
  --resource-group "rg-security" \
  --location "eastus"
```

**Terraform:**

```hcl
resource "azurerm_easm_workspace" "main" {
  name                = "easm-prod"
  resource_group_name = azurerm_resource_group.security.name
  location            = "East US"
}
```

## Discovery seeds and groups

After creating the workspace, add a discovery group (Discovery > Discovery Groups > Create). Seed types:

- **Domains:** company.com, company.net
- **IP blocks:** 198.51.100.0/24
- **ASN:** AS12345
- **Hosts:** specific hostnames
- **Email contacts:** security@company.com (finds certificates carrying this email)
- **WHOIS organisations:** legal-entity names

Set a discovery frequency (weekly default or custom) and run. Via REST (Azure AD bearer token, placeholder shown):

```bash
EASM_BASE="https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Easm/workspaces/{workspace}"
curl -X PUT "${EASM_BASE}/discoveryGroups/main?api-version=2023-04-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"properties": {"seeds": [{"kind": "domain", "name": "company.com"},
       {"kind": "ipBlock", "name": "198.51.100.0/24"}], "frequencyMilliseconds": 604800000}}'
```

## Asset inventory and states

Every discovered asset holds one state:

| State | Meaning |
|---|---|
| Candidate | discovered, not yet confirmed as yours |
| Confirmed Inventory | accepted as belonging to your org (billable) |
| Dependencies | third-party assets your confirmed assets rely on |
| Monitor Only | watched but not managed (subsidiaries, partners) |
| Requires Investigation | flagged for review |
| Dismissed | not yours, removed from scope |
| Archived | was yours, now decommissioned |

Workflow: a discovered asset starts as Candidate, you review it, then mark Confirmed Inventory or Dismissed. This attribution step is also cost control, because only Confirmed assets are billable (see the pricing section in `azure-integration.md`).

## Asset labels

Apply custom labels for organisation and filtering: business unit (`finance`, `engineering`), environment (`production`, `staging`), risk tier (`tier-1`), compliance scope (`pci-scope`), geography (`us`, `eu`). Via API:

```bash
curl -X PATCH "${EASM_BASE}/assets/domains/company.com?api-version=2023-04-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"labels": {"environment": "production", "tier": "1"}}'
```
