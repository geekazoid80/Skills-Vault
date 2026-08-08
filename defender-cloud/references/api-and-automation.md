# Microsoft Defender for Cloud API and automation

Read-only posture audit and reporting for Defender for Cloud (DfC) run through three surfaces: the ARM REST API for the `Microsoft.Security` resource provider (plan state, assessments, sub-assessments, secure score, JIT policies), the Microsoft Graph Security API (alerts and the unified secure-score model), and Azure Resource Graph (fast cross-subscription posture queries). All three authenticate as an Entra ID app registration using the OAuth 2.0 client-credentials flow. Every token and secret in this file is a placeholder; never inline a live secret.

## Authentication: the app-registration client-credentials flow

Register an application in Entra ID, grant it the least role and the least application permission the task needs, and authenticate with either a client secret or (preferred) a certificate. For ARM and Resource Graph, authorisation is Azure RBAC on the target scope (the built-in **Security Reader** role is the read-only fit for a DfC audit); for the Graph Security API it is application permissions plus admin consent.

```
POST https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<client-id>
&client_secret=<client-secret from the secret store>
&scope=https://management.azure.com/.default
```

Swap the `scope` for `https://graph.microsoft.com/.default` when calling the Graph Security API. The response carries an `access_token` (a bearer JWT, placeholder `<access-token>`) and an `expires_in` (seconds, typically 3599). Cache the token until shortly before expiry and refresh; do not fetch a fresh token per call.

```
Authorization: Bearer <access-token>
```

Prefer a certificate credential over a client secret for anything long-lived: a certificate is not a bearer string that leaks whole from a log line, and it is easier to rotate on a schedule. Store the secret or certificate password in the secret store (see `secrets-hygiene`), never in the script, the runbook, or a committed config file. Track the credential's expiry and rotate in place before it lapses.

### Least-privilege access for a read-only audit

| Task | Access | Notes |
|---|---|---|
| Read plan state, assessments, secure score (ARM) | Azure RBAC **Security Reader** on the scope | Read-only across `Microsoft.Security` resources |
| Cross-subscription posture queries (Resource Graph) | **Reader** on the scope | Resource Graph reflects ARM read permissions |
| Read security alerts (Graph Security) | `SecurityAlert.Read.All` | Read-only alert feed |
| Read secure score (Graph Security) | `SecurityEvents.Read.All` | The unified secureScores and control profiles |

Grant only what the task needs. A read-only audit should hold only reader roles and `*.Read.All` scopes; if the app can also change plan state, apply a remediation, or activate JIT, that write capability is itself an audit finding when the app was meant to be read-only. Split the read-only audit identity from any write identity so a compromised audit token cannot change the tenant.

## ARM REST: the Microsoft.Security resource provider

The `Microsoft.Security` provider is the canonical read surface for DfC posture. All the calls below are `GET` and read-only.

### Plan state (pricings)

```
GET https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Security/pricings?api-version=2024-01-01
Authorization: Bearer <access-token>
```

Each entry reports a plan name (`VirtualMachines`, `Containers`, `SqlServers`, `StorageAccounts`, `KeyVaults`, `Arm`, `Dns`, `AppServices`, `Api`, `CloudPosture` for Defender CSPM) with `pricingTier` (`Free` or `Standard`) and, where relevant, a `subPlan` (for example `P1`/`P2` on servers). This is the fastest way to confirm which layers are on: a subscription with every pricing at `Free` is foundational-only.

### Assessments and sub-assessments

```
GET https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Security/assessments?api-version=2020-01-01
Authorization: Bearer <access-token>
```

An assessment is the state of one recommendation against one resource: `status.code` is `Healthy`, `Unhealthy`, or `NotApplicable`, with a `displayName` and a `resourceDetails` pointer. Sub-assessments carry the granular findings under an assessment, most importantly the vulnerability findings from agentless scanning and MDVM:

```
GET https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Security/assessments/<assessment-name>/subAssessments?api-version=2019-01-01-preview
Authorization: Bearer <access-token>
```

Sub-assessment fields worth projecting: `id`, `displayName`, `status`, and for a vulnerability finding the CVE id, severity, CVSS score, patch state, and affected resource. This is the read-only route to a workload-vulnerability report; the programme design that consumes it belongs to `vulnerability-management`.

### Secure score

```
GET https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Security/secureScores/ascScore?api-version=2020-01-01
Authorization: Bearer <access-token>
```

Returns the current and maximum score and the percentage. The secure-score controls endpoint breaks the score down per control (`.../secureScores/ascScore/secureScoreControls`), reporting each control's current and max points and its healthy and unhealthy resource counts, which is exactly the input for prioritising by potential score increase.

### JIT policies (read-only)

```
GET https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Security/jitNetworkAccessPolicies?api-version=2020-01-01
Authorization: Bearer <access-token>
```

Reading the JIT policies confirms which VMs have JIT configured and on which ports. Requesting or activating access is a write and is out of scope for a read-only audit.

## Microsoft Graph Security API

The Graph Security surface unifies DfC alerts with the rest of Defender XDR.

```
GET https://graph.microsoft.com/v1.0/security/alerts_v2?$filter=serviceSource eq 'microsoftDefenderForCloud'&$top=50
Authorization: Bearer <access-token>
```

Useful alert fields: `id`, `title`, `category`, `severity`, `status`, `serviceSource` (filter to `microsoftDefenderForCloud`), `createdDateTime`, `evidence` (the resource, identity, and network entities), and `incidentId` (the parent incident that correlates this alert with endpoint, email, and identity signals). For a read-only audit, enumerate and project the non-secret fields; do not `PATCH` status or assignment. The Graph secure-score endpoint (`/security/secureScores` and `/security/secureScoreControlProfiles`) exposes the same posture metric in the unified model when a single cross-workload view is wanted.

## Azure Resource Graph for posture queries

Azure Resource Graph runs KQL-style queries across every subscription in scope in one call, which is the efficient way to answer estate-wide posture questions without paging per subscription.

```
POST https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01
Authorization: Bearer <access-token>
Content-Type: application/json

{
  "query": "securityresources | where type == 'microsoft.security/assessments' | where properties.status.code == 'Unhealthy' | summarize unhealthy = count() by assessment = tostring(properties.displayName) | order by unhealthy desc"
}
```

The `securityresources` table exposes DfC assessments, sub-assessments, secure-score controls, and plan state to KQL, so a single query returns the unhealthy-recommendation ranking, the vulnerable-VM list, or the plan-coverage gap across the whole estate. Resource Graph reflects the caller's ARM read permissions, so a **Reader** or **Security Reader** identity sees exactly the scope it is entitled to.

## Throttling, backoff, and pagination

- **Throttling**: ARM, Graph, and Resource Graph all throttle. On an HTTP `429`, honour the `Retry-After` header before retrying, and use exponential backoff with jitter for repeated `429` or `503`. A read-only audit has no reason to run hot.
- **Pagination**: ARM and Graph list responses page with `nextLink` (`@odata.nextLink` on Graph); follow it until absent rather than assuming the first page is complete. Resource Graph pages with a `$skipToken`; pass it back until it is empty, and cap large result sets with `top`/`skip` or a tighter filter.
- **Error handling**: never infer the cause of a non-2xx; capture the full status, headers, and body, distinguish a transient `429`/`503` from a permanent `401`/`403` by retrying, and confirm a `403` is a real permission gap (the app is missing the RBAC role, the scope, or admin consent) rather than a throttled or malformed call before reporting a capability as blocked.

## Secret-store discipline

- The client secret, the certificate, and the certificate password live in the secret store, never in the script, the runbook, or a committed config file. See `secrets-hygiene`.
- Never put a token or secret in a URL query string or a log line. A bearer JWT in a URL leaks whole into proxy and history logs.
- Prefer a certificate credential over a client secret for anything long-lived, and prefer certificate-based app-only auth for the unattended audit job.
- Track the expiry of the secret or certificate and rotate in place before it lapses; a lapsed credential fails the audit job silently until someone notices the empty report.
- Keep the audit app read-only (Reader or Security Reader RBAC, `*.Read.All` Graph scopes only). If the same app can also enable a plan, apply a remediation, or activate JIT, split the read-only audit identity from the write identity so a compromised audit token cannot change the tenant.
</content>
