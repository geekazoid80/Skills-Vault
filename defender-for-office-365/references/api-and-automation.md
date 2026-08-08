# Microsoft Defender for Office 365 API and automation

Read-only audit and reporting for MDO run through three surfaces: the Microsoft Graph Security API (alerts and incidents), the Threat Submission API (submissions and, on the newer surface, tenant allow/block entries), and Exchange Online PowerShell (the policy objects). All three authenticate as an Entra ID app registration using the OAuth 2.0 client-credentials flow. Every token and secret in this file is a placeholder; never inline a live secret.

## Authentication: the app-registration client-credentials flow

Register an application in Entra ID, grant it the least application permission the task needs, and authenticate with either a client secret or (preferred) a certificate.

```
POST https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET_PLACEHOLDER}
&scope=https://graph.microsoft.com/.default
```

The response carries an `access_token` (a bearer JWT, placeholder `{ACCESS_TOKEN_PLACEHOLDER}`) and an `expires_in` (seconds, typically 3599). Cache the token until shortly before expiry and refresh; do not fetch a fresh token per call.

```
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}
```

Prefer a certificate credential over a client secret for anything long-lived: a certificate is not a bearer string that leaks whole from a log line, and it is easier to rotate on a schedule. Store the secret or certificate password in the secret store (see `secrets-hygiene`), never in the script, the runbook, or a committed config file. Track the credential's expiry and rotate in place before it lapses.

### Least-privilege application permissions

| Task | Permission (application) | Notes |
|---|---|---|
| Read security alerts and incidents | `SecurityAlert.Read.All` or `SecurityIncident.Read.All` | Read-only audit and SIEM feed |
| Read the newer alerts surface | `SecurityAlert.Read.All` (alerts_v2) | The v2 alerts unify Defender XDR signals |
| Read threat submissions | `ThreatSubmission.Read.All` | Read-only review of submitted items |
| Create threat submissions | `ThreatSubmission.ReadWrite.All` | A write scope; not for a read-only audit |
| Advanced Hunting (MDO tables) | `ThreatHunting.Read.All` | KQL over EmailEvents and related tables |

Grant only what the task needs. A read-only audit should hold only `*.Read.All` scopes; if the app can write (submit, remediate, activate), that is itself an audit finding when the app was meant to be read-only.

## Microsoft Graph Security API

### Alerts (alerts_v2) and incidents

```
GET https://graph.microsoft.com/v1.0/security/alerts_v2?$filter=serviceSource eq 'microsoftDefenderForOffice365'&$top=50
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}
```

Useful alert fields: `id`, `title`, `category`, `severity`, `status`, `serviceSource` (filter to `microsoftDefenderForOffice365`), `createdDateTime`, `evidence` (mailbox, sender, URL, and file entities), and `incidentId` (the parent incident that correlates this alert with device and identity signals).

```
GET https://graph.microsoft.com/v1.0/security/incidents?$filter=status eq 'active'&$expand=alerts
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}
```

An incident groups correlated alerts across MDO, Defender for Endpoint, Defender for Identity, and Entra ID. For a read-only audit, enumerate incidents, expand the alerts, and project the non-secret fields; do not PATCH status or assignment.

### Advanced Hunting over MDO tables

```
POST https://graph.microsoft.com/v1.0/security/runHuntingQuery
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}
Content-Type: application/json

{ "query": "EmailEvents | where Timestamp > ago(7d) | where DeliveryAction == 'Delivered' | join kind=inner EmailPostDeliveryEvents on NetworkMessageId | where Action == 'Zap' | project Timestamp, RecipientEmailAddress, SenderFromAddress, Subject" }
```

The MDO Advanced Hunting tables are `EmailEvents`, `EmailUrlInfo`, `EmailAttachmentInfo`, `EmailPostDeliveryEvents`, and `UrlClickEvents`. `runHuntingQuery` is read-only by nature (it returns rows, it does not change state) and is the cleanest way to script a coverage report (delivered-then-ZAPped mail, blocked Safe Links clicks, campaign spread).

## Threat Submission API

The Graph threat submission endpoints cover email, URL, and file submissions to Microsoft, and the tenant allow/block list on the newer surface.

```
GET  https://graph.microsoft.com/v1.0/security/threatSubmission/emailThreats
POST https://graph.microsoft.com/v1.0/security/threatSubmission/emailThreats
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}
```

Reading submissions (`ThreatSubmission.Read.All`) is a read-only audit action: see what was reported and Microsoft's verdict. Creating a submission (`ThreatSubmission.ReadWrite.All`) is a write action, so it is out of scope for a read-only review; note that the tenant reports false positives and false negatives here to correct verdicts at the source.

## Exchange Online PowerShell for policy audit

The MDO policy objects (Safe Attachments, Safe Links, anti-phish, anti-spam, anti-malware, quarantine) are read through Exchange Online PowerShell, not the Graph. Connect with the same app-registration identity using a certificate (app-only auth), which needs the Exchange administrator or a suitable directory role assigned to the service principal.

```powershell
# App-only connect with a certificate (thumbprint from the local store, or -Certificate for a file)
Connect-ExchangeOnline -AppId "{CLIENT_ID}" -CertificateThumbprint "{CERT_THUMBPRINT_PLACEHOLDER}" -Organization "{TENANT}.onmicrosoft.com"

# Read the policy objects (all read-only Get-* verbs)
Get-SafeAttachmentPolicy   | Select-Object Name, Action, Enable, Redirect
Get-SafeLinksPolicy        | Select-Object Name, IsEnabled, ScanUrls, EnableForInternalSenders, AllowClickThrough, DoNotRewriteUrls
Get-AntiPhishPolicy        | Select-Object Name, Enabled, EnableTargetedUserProtection, TargetedUsersToProtect, EnableMailboxIntelligence, PhishThresholdLevel
Get-HostedContentFilterPolicy | Select-Object Name, BulkThreshold, SpamAction, PhishSpamAction, ZapEnabled, PhishZapEnabled, SpamZapEnabled
Get-MalwareFilterPolicy    | Select-Object Name, EnableFileFilter, ZapEnabled
Get-QuarantinePolicy       | Select-Object Name, EndUserQuarantinePermissionsValue, ESNEnabled

# Preset security policy state
Get-EOPProtectionPolicyRule
Get-ATPProtectionPolicyRule
```

On the `powershell-module-compat` note: the Exchange Online Management module behaves differently across Windows PowerShell 5.1 and PowerShell 7, and app-only certificate auth uses a thumbprint from the local certificate store on Windows or a `-Certificate` object elsewhere; verify the specific cmdlet is present after `Import-Module` rather than assuming the module loaded fully. Keep every command in this audit to the read-only `Get-*` verbs; a `Set-*`, `New-*`, `Enable-*`, or `Release-QuarantineMessage` is a write and is out of scope for a read-only review.

## Throttling, backoff, and pagination

- **Throttling**: the Graph and Exchange Online both throttle. On an HTTP `429`, honour the `Retry-After` header before retrying, and use exponential backoff with jitter for repeated `429` or `503`. Do not hammer; a read-only audit has no reason to run hot.
- **Pagination**: Graph list responses page with `@odata.nextLink`; follow it until absent rather than assuming the first page is complete. `runHuntingQuery` caps result rows, so narrow the time window or project fewer columns rather than expecting an unbounded result set.
- **Error handling**: never infer the cause of a non-2xx; capture the full status, headers, and body, distinguish a transient `429`/`503` from a permanent `401`/`403` by retrying, and confirm a `403` is a real permission gap (the app is missing the scope or admin consent) rather than a throttled or malformed call before reporting a capability as blocked.

## Secret-store discipline

- The client secret, the certificate, and the certificate password live in the secret store, never in the script, the runbook, or a committed config file. See `secrets-hygiene`.
- Never put a token or secret in a URL query string or a log line. A bearer JWT in a URL leaks whole into proxy and history logs.
- Prefer a certificate credential over a client secret for anything long-lived, and prefer app-only certificate auth for the unattended audit job.
- Track the expiry of the secret or certificate and rotate in place before it lapses; a lapsed credential fails the audit job silently until someone notices the empty report.
- Keep the audit app read-only (`*.Read.All` scopes only). If the same app can also submit, remediate, or activate policy, split the read-only audit identity from the write identity so a compromised audit token cannot change the tenant.
