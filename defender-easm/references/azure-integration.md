# Azure integration

The Azure integrations are the main reason to choose Defender EASM over a standalone tool.

## Defender for Cloud

Export the EASM inventory into Defender for Cloud: in Defender for Cloud go to Environment Settings > External Attack Surface and connect the EASM workspace. EASM-discovered assets then appear as external inventory alongside Defender for Cloud's CSPM recommendations, so an internet-exposed Azure VM found by EASM can be seen next to its three critical CSPM recommendations in one view. Broader Defender for Cloud CSPM work belongs to `azure-cloud-ops`.

## Microsoft Sentinel

Enable the data connector (Sentinel > Data Connectors > Microsoft Defender EASM, connect the workspace). EASM findings flow into the `EasmAsset_CL` and `EasmInsight_CL` tables for KQL correlation:

```kql
// New critical insights in the last 7 days
EasmInsight_CL
| where TimeGenerated > ago(7d)
| where severity_s in ("High", "Critical")
| project TimeGenerated, assetName_s, insightName_s, severity_s, state_s
| sort by TimeGenerated desc

// Correlate external exposure with endpoint alerts on the same IP
let easm_ips = EasmAsset_CL
  | where assetType_s == "IP Address" and state_s == "Confirmed"
  | project ip = name_s;
DeviceAlerts
| where LocalIP in (easm_ips) or RemoteIP in (easm_ips)
| project Timestamp, DeviceName, AlertName, Severity, LocalIP, RemoteIP
```

This external-plus-internal correlation is what justifies choosing Defender EASM in a Microsoft-stack shop. Sentinel itself is covered by `siem-soar-investigation`.

## Logic Apps and Power Automate

Automate remediation since Defender EASM has less built-in SOAR than Xpanse. Example: a recurrence trigger every 24 hours calls the EASM API for new Critical insights, then for each one creates a ServiceNow incident ("EASM Critical Exposure: {insightName}") assigned to Security Operations.

## REST API

Authenticate with an Azure AD token (OAuth 2.0, scope `https://easm.defender.microsoft.com/.default`). Key endpoints: `GET /assets`, `GET /assets/{id}`, `PATCH /assets/{id}` (state and labels), `GET /insights`, `POST /discoveryGroups`, `GET /summaries/asset`, `GET /summaries/insight`.

```python
import requests
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
token = credential.get_token("https://easm.defender.microsoft.com/.default")
EASM_BASE = "https://eastus.easm.defender.microsoft.com/subscriptions/{sub}/resourceGroups/{rg}/workspaces/{ws}"
headers = {"Authorization": f"Bearer {token.token}"}

resp = requests.get(f"{EASM_BASE}/assets", headers=headers,
                    params={"filter": "state eq 'confirmed'", "$top": 100,
                            "api-version": "2023-04-01-preview"})
for asset in resp.json()["value"]:
    print(asset["kind"], asset["name"], asset["state"])
```

The token is a credential; obtain it via managed identity or the secret store, never inline (see `secrets-hygiene`).

## Pricing and cost control

Pricing is per billable asset per month, where billable means Confirmed Inventory only (Candidates and Dismissed do not count); a first tranche of assets is free during the trial. Control cost by regularly dismissing assets that are not yours, archiving decommissioned assets rather than leaving them Confirmed, and setting budget alerts in Azure Cost Management. Attribution hygiene and cost hygiene are the same activity here.
