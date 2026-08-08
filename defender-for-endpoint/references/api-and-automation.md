# Microsoft Defender for Endpoint API and automation

Read-only audit and reporting for MDE run through three surfaces on Microsoft Graph: the Graph Security API (alerts and incidents), the Advanced Hunting API (`runHuntingQuery` over the Device tables), and machine-actions (device isolation, scans, live-response commands). This reference treats the read surfaces as the default and machine-actions as a deliberately-gated, normally-not-used capability, so an "audit" integration cannot mutate the estate. All three authenticate as an Entra ID app registration using the OAuth 2.0 client-credentials flow. Every token and secret in this file is a placeholder; never inline a live secret.

## The read-only-by-default posture

An MDE automation built for audit and reporting requests only read scopes and never calls a mutating endpoint. The mutating machine-actions (isolate, unisolate, run antivirus scan, collect investigation package, live-response commands) exist and are documented below for completeness, but an audit app should not hold the permissions that reach them. Separate the read app from any response app, so a reporting job physically cannot isolate a device.

- **Read surfaces (audit default):** Graph Security alerts and incidents, the Advanced Hunting API, machine and vulnerability read.
- **Mutating surfaces (out of scope for audit):** machine-actions and live response. Gate these behind a separate app registration, a change window, and an approval, exactly as the interactive equivalents are gated by RBAC.

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
| Read alerts and incidents | `SecurityAlert.Read.All`, `SecurityIncident.Read.All` | The audit and reporting default |
| Run an advanced-hunting query | `ThreatHunting.Read.All` | Read-only KQL over the Device tables |
| Read machines and their risk | `Machine.Read.All` | Device inventory, onboarding state, risk score |
| Read vulnerabilities | `Vulnerability.Read.All` | MDVM CVEs, software inventory, recommendations |
| Isolate or scan a machine (NOT for audit) | `Machine.Isolate`, `Machine.Scan` | Mutating; separate app, change window, approval |
| Live response (NOT for audit) | `Machine.LiveResponse` | Mutating; separate app, change window, approval |

Grant only the read permissions to an audit app. Admin consent is required for application permissions; record who consented and when.

## The Graph Security API: alerts and incidents

```
GET https://graph.microsoft.com/v1.0/security/alerts_v2?$filter=status eq 'new'&$top=50
GET https://graph.microsoft.com/v1.0/security/incidents?$top=50&$expand=alerts
```

Alerts carry the severity, the detection source (`microsoftDefenderForEndpoint`), the affected device, and the evidence collection; incidents group correlated alerts across Defender XDR. Filter server-side with `$filter` and page with `@odata.nextLink` rather than pulling everything and filtering client-side.

## The Advanced Hunting API: runHuntingQuery over the Device tables

The same KQL you run interactively is available through the API, which is the cleanest way to schedule a read-only audit query.

```
POST https://graph.microsoft.com/v1.0/security/runHuntingQuery
Content-Type: application/json
Authorization: Bearer {ACCESS_TOKEN_PLACEHOLDER}

{
  "query": "DeviceInfo | where Timestamp > ago(1d) | summarize arg_max(Timestamp, OnboardingStatus) by DeviceName | where OnboardingStatus != 'Onboarded'"
}
```

The response is `{ "schema": [...], "results": [...] }`. Limits: the query runs over roughly 30 days of retained telemetry, the result set and the query runtime are capped, and the API is throttled per tenant, so keep audit queries summarised (project only the columns you need, aggregate before returning). The Device tables (`DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceRegistryEvents`, `DeviceLogonEvents`, `DeviceEvents`, the `DeviceTvm` tables, and `DeviceInfo`) are all reachable this way.

## Machine-actions (out of scope for audit)

For completeness only. These mutate the estate and belong to a separate, approved response app, never the audit app.

```
# Isolate a device (mutating: cuts network except sensor comms)
POST https://graph.microsoft.com/v1.0/security/... /machineActions
{ "machineId": "{MACHINE_ID}", "actionType": "Isolate", "comment": "IR-1234 approved" }

# Query an action's status
GET  https://graph.microsoft.com/v1.0/security/... /machineActions/{ACTION_ID}
```

Any script that can reach these must scrub subprocess exceptions (a failed call stringifies its argv, which can carry the token and the machine id) and must require an explicit, logged approval before it runs.

## Throttling, backoff, and pagination

- **Throttling.** Graph and the hunting API return HTTP 429 with a `Retry-After` header when a tenant exceeds its call budget. Honour `Retry-After` exactly; do not retry immediately.
- **Backoff.** On 429 or 5xx, retry with exponential backoff and jitter, capped at a few attempts. Do not infer the cause of a non-2xx from the status alone; read the response body, which carries the Graph error `code` and `message`.
- **Pagination.** Follow `@odata.nextLink` until it is absent; never assume a single page holds every result. For the hunting API, aggregate inside the query rather than paging large raw result sets.

## Secret-store discipline

- The client secret or certificate password lives in the secret store (see `secrets-hygiene`), read at runtime, never written to a script, a runbook, a saved API call, or a committed config file.
- Placeholders only in any saved example: `{TENANT_ID}`, `{CLIENT_ID}`, `{CLIENT_SECRET_PLACEHOLDER}`, `{ACCESS_TOKEN_PLACEHOLDER}`, `{MACHINE_ID}`, `{ACTION_ID}`.
- Prefer a certificate over a client secret for long-lived automation; track its expiry and rotate in place before it lapses.
- Scrub tokens and identifiers from any logged subprocess exception, not just from captured stdout and stderr.
- Keep the read (audit) app and any response app as separate registrations with separate credentials, so a reporting job cannot hold a mutating permission.
