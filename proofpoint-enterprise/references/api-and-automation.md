# Proofpoint Enterprise API and automation

Authentication, endpoints, response fields, rate limits, and pagination for the Proofpoint TAP SIEM API, the TAP People (VAP) API, and the TRAP API, plus the secret-store discipline. Every endpoint below is read-only unless flagged; an audit uses read-only calls and never triggers a TRAP remediation or a policy change. Placeholder tokens throughout: never commit a live value.

## Secret-store discipline (read this first)

Proofpoint Enterprise automation uses several distinct credentials, and each is a live secret:

- **TAP Service Principal + Secret**: the service credentials for the TAP SIEM and People APIs, issued in the TAP dashboard (Settings -> Connected Applications). Sent as HTTP Basic auth.
- **TRAP API token**: a bearer token from the TRAP appliance / tenant for the TRAP REST API.
- **M365 app-registration client secret** (or certificate): what TRAP itself uses to reach Microsoft Graph. Not used by your scripts directly, but it lives in the same estate and is the highest-value secret because it can read and delete mail tenant-wide.
- **Google service-account JSON key**: the equivalent for a Google Workspace estate.

Rules:

- Keep every one of these in the secret store (a secrets manager, or a gitignored `config.toml` per the project convention), never inline in a saved API URL, a runbook, or a committed file.
- Reference the credential by name in scripts; resolve it at runtime. Placeholder literals only in any example or template (`{tap_principal}`, `{tap_secret}`, `{trap_token}`).
- Scrub subprocess exceptions: a failed `curl` / HTTP call can stringify the full argv, so a token passed on the command line leaks into the error text. Pass secrets via an environment variable or a header read from the store, and scrub raised exceptions.
- Track the lifetime of any non-self-renewing credential (the M365 client secret and the Google key both expire); raise a rotate-in-place ticket ahead of expiry rather than discovering it at an outage.
- Least privilege is a credential property, not just a policy one: the TRAP M365 app registration should hold only `Mail.ReadWrite`, `Mail.Read`, `MailboxSettings.Read`, and `User.Read.All`; a Google service account only `gmail.modify` and `admin.directory.user.readonly`.

## TAP SIEM API

Threat and message events (delivered, blocked, click-permitted, click-blocked) for SIEM ingestion. Auth is HTTP Basic with the TAP service principal and secret.

Base URL:

```
https://tap-api-v2.proofpoint.com
```

| Endpoint | Method | Purpose |
|---|---|---|
| `/v2/siem/all` | GET | All event types in one call (messages delivered / blocked, clicks permitted / blocked) |
| `/v2/siem/messages/delivered` | GET | Messages delivered that later proved malicious |
| `/v2/siem/messages/blocked` | GET | Messages blocked by TAP |
| `/v2/siem/clicks/permitted` | GET | URL Defense clicks that were permitted |
| `/v2/siem/clicks/blocked` | GET | URL Defense clicks that were blocked |
| `/v2/siem/issues` | GET | Messages and clicks deemed a threat (blocked + delivered-then-condemned) |

Time-window parameters (one per call): `sinceSeconds` (a rolling look-back, 30 to 3600), or `sinceTime` / `interval` (ISO 8601). Format is `format=json` (default) or `syslog`.

```
GET https://tap-api-v2.proofpoint.com/v2/siem/all?format=json&sinceSeconds=3600
Authorization: Basic {base64(tap_principal:tap_secret)}
```

Key response fields include `messagesDelivered`, `messagesBlocked`, `clicksPermitted`, `clicksBlocked`, each an array carrying the sender, recipients, `messageID`, `threatsInfoMap` (threat type, classification, the threat URL / attachment, the campaign ID), and the timestamp. The campaign ID joins to the campaign / forensics endpoints.

## TAP Campaign and Forensics API

| Endpoint | Method | Purpose |
|---|---|---|
| `/v2/campaign/ids` | GET | Campaign IDs active in a time window |
| `/v2/campaign/{campaignId}` | GET | Campaign detail: families, actors, techniques, associated IOCs |
| `/v2/forensics?threatId={id}` | GET | Forensic evidence (behaviours, dropped files, network activity) for a threat or campaign |

Same Basic auth as the SIEM API. Use these to enrich a SIEM event into a full campaign picture.

## TAP People (VAP) API

The people-centric feed: the Very Attacked People and per-user attack-index data, for integration with HR, PAM, and the SIEM. Same base URL and Basic auth as the TAP SIEM API.

| Endpoint | Method | Purpose |
|---|---|---|
| `/v2/people/vap` | GET | The VAP list with attack-index scores |
| `/v2/people/top-clickers` | GET | Users who most often click malicious URLs |

Window parameter `window` is a fixed look-back in days (`14`, `30`, or `90`).

```
GET https://tap-api-v2.proofpoint.com/v2/people/vap?window=30
Authorization: Basic {base64(tap_principal:tap_secret)}
```

Response carries `users[]`, each with the `identity` (email, VIP flag, department, guessed location where available), a `threatStatistics` block (`attackIndex`, per-family counts), and the summary `totalVapUsers` and `interval`. The `attackIndex` is the number to sort on when binding stricter policy to the most-attacked users; feed the email list into the group your VAP policy and URL Isolation rule target.

## TRAP API

The Threat Response / TRAP REST API drives and reads post-delivery remediation. Auth is a bearer token issued by the TRAP tenant. Base URL is the TRAP instance host (cloud tenant or on-prem appliance):

```
https://{trap-host}/api
```

| Endpoint | Method | Purpose | Note |
|---|---|---|---|
| `/incidents` | GET | List remediation incidents (filter by state, time) | Read-only |
| `/incidents/{id}` | GET | Incident detail, including affected mailboxes and actions taken | Read-only |
| `/incidents/{id}/comments` | GET | Analyst comment trail | Read-only |
| `/json/alert` | POST | Inject an alert / IOC to open a remediation (SIEM / SOAR trigger) | CHANGE: triggers remediation |
| `/incidents/{id}/close` | POST | Close an incident | CHANGE |

```
GET https://{trap-host}/api/incidents?state=open
Authorization: Bearer {trap_token}
```

The `/json/alert` POST is the SOAR integration point: a playbook posts a confirmed IOC (message-ID, hash, sender) and TRAP opens the auto-pull incident. In a read-only audit, use only the `GET /incidents` endpoints to read the remediation history and confirm the automation-rule thresholds and audit trail; never POST an alert or close an incident during a review.

## Rate limits, backoff, and pagination

- **Rate limits**: the TAP APIs are throttled per service principal. A `429 Too Many Requests` carries a `Retry-After` header; honour it with exponential backoff. For the SIEM API, prefer one `/v2/siem/all` call per window over separate per-type calls to stay under the limit, and poll on a schedule (a rolling `sinceSeconds` no shorter than the poll interval) rather than hammering.
- **Do not assume the cause of a non-2xx**: capture the full status, headers, and body before concluding. A `401` may be a clock-skewed Basic header or a rotated secret, not a permissions wall; a `429` is transient; a `403` may be a scope the principal genuinely lacks. Retry once to tell transient from permanent, then read the body.
- **Pagination**: the TAP SIEM and People endpoints return the full window in one response bounded by the time parameter, so "pagination" is really windowing: page by advancing `sinceTime` / `interval` across the range, keeping each window small enough to stay under the response-size and rate limits. The TRAP `/incidents` list paginates with `page` / `size` query parameters; follow until a short (less-than-`size`) page returns.
- **Caching**: cache the VAP list and campaign detail locally with a TTL matched to the window (a 30-day VAP window does not need re-fetching every minute); the SIEM event stream is the real-time surface and is polled, not cached.

## Automation patterns

- **VAP-driven policy**: poll `/v2/people/vap` on a schedule, diff against the current VAP security group, and reconcile membership so force-sandbox and URL Isolation always track the live most-attacked list. This is the automation that makes the people-centric model act, not just report.
- **SIEM feed**: poll `/v2/siem/all` on a fixed interval into the SIEM; join `threatsInfoMap.campaignId` to `/v2/campaign/{id}` for context. Route to `siem-soar-investigation` for the downstream workflow.
- **SOAR-driven TRAP**: on a confirmed-malicious SIEM detection, a SOAR playbook posts `/json/alert` to open a TRAP incident, then polls `GET /incidents/{id}` for the outcome. Gate the auto-pull on the same confidence threshold the TRAP automation rules use, so the API path and the dashboard path agree.
