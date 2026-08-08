# Zscaler API and automation

Authentication, endpoints, response fields, rate limits, and pagination for the ZIA and ZPA REST APIs, plus the secret-store discipline. Every endpoint below is read-only unless flagged; an audit uses read-only scope and never activates a pending policy push. Placeholder tokens throughout: never commit a live value.

## Secret-store discipline (read this first)

The ZIA API key, ZIA admin password, ZPA client secret, SCIM bearer token, and App Connector provisioning key are all secrets. Keep every one in the project secret store and pass it in at runtime; never inline a live value in a saved API URL, a runbook, a script, or a committed config file, and never let a failing subprocess stringify a token into a transcript. In the examples the values come from environment variables (`$ZIA_API_KEY`, `$ZPA_CLIENT_ID`, `$ZPA_CLIENT_SECRET`) that a secret manager populates. See the `secrets-hygiene` skill for the store pattern, rotation, and leak response.

## Choosing the cloud base URL

Point every call at the tenant's own cloud; the wrong base URL silently targets the wrong tenant.

**ZIA base URLs:**

| Cloud | API base URL |
|---|---|
| zscaler.net | `https://zsapi.zscaler.net` |
| zscalerone.net | `https://zsapi.zscalerone.net` |
| zscalertwo.net | `https://zsapi.zscalertwo.net` |
| zscalerthree.net | `https://zsapi.zscalerthree.net` |
| zscloud.net | `https://zsapi.zscloud.net` |
| zscalerbeta.net | `https://zsapi.zscalerbeta.net` |
| zscalergov.net | `https://zsapi.zscalergov.net` |

**ZPA config base URLs:**

| Cloud | Config API base URL |
|---|---|
| Production (US) | `https://config.private.zscaler.com` |
| Production (EU) | `https://config.zscaler.com` |
| Beta | `https://config.zpabeta.net` |
| Gov | `https://config.zpagov.net` |

## ZIA authentication

ZIA uses session-based authentication with an obfuscated API key. The key is obfuscated with a timestamp-based algorithm before submission.

**Obfuscation algorithm:**
1. Take the current Unix timestamp in milliseconds as a string.
2. Extract the last 6 digits.
3. For each digit `n` at position `i`, take the character at index `n` of the API key.
4. Concatenate those characters to form the obfuscated key, then append the full timestamp.

**Authenticate:**
```
POST https://zsapi.<cloud>/api/v1/authenticatedSession
Content-Type: application/json

{
  "apiKey": "<obfuscated_api_key>",
  "username": "$ZIA_ADMIN_EMAIL",
  "password": "$ZIA_ADMIN_PASSWORD",
  "timestamp": "<timestamp_ms>"
}
```

The response sets a `JSESSIONID` cookie used on subsequent calls.

**Session lifecycle:** sessions idle out after 30 minutes and last at most 1 hour; only one active session per admin is allowed; call `DELETE /api/v1/authenticatedSession` to end it explicitly.

## ZPA authentication

ZPA uses OAuth 2.0 client credentials. Create the client in the ZPA Admin Portal under Administration -> API Keys.

**Get a token:**
```
POST https://config.<cloud>/signin
Content-Type: application/x-www-form-urlencoded

client_id=$ZPA_CLIENT_ID&client_secret=$ZPA_CLIENT_SECRET
```

**Response:**
```json
{ "token_type": "Bearer", "access_token": "<jwt_token>" }
```

Send it as `Authorization: Bearer <access_token>` on every call. Tokens last 3600 seconds; there is no refresh token, so request a new one before expiry.

## ZIA endpoints

### URL filtering
| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/urlFilteringRules` | GET | All URL filtering rules |
| `/api/v1/urlFilteringRules/{ruleId}` | GET | One rule |
| `/api/v1/urlCategories` | GET | All URL categories (predefined plus custom) |
| `/api/v1/urlCategories?type=URL_CATEGORY` | GET | Predefined categories only |
| `/api/v1/urlCategories?type=CUSTOM` | GET | Custom categories only |

Key `urlFilteringRules` fields: `id`, `name`, `order` (1 = first), `state` (`ENABLED`/`DISABLED`), `action` (`ALLOW`/`BLOCK`/`CAUTION`/`ISOLATE`), `urlCategories`, `locations`, `departments`, `groups`, `blockOverride`.

### Cloud firewall
| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/firewallRules` | GET | All cloud firewall rules |
| `/api/v1/networkServices` | GET | Network service definitions |
| `/api/v1/networkServiceGroups` | GET | Network service groups |
| `/api/v1/ipSourceGroups` | GET | IP source groups |
| `/api/v1/ipDestinationGroups` | GET | IP destination groups |

Key `firewallRules` fields: `id`, `name`, `order`, `state`, `action` (`ALLOW`/`BLOCK_DROP`/`BLOCK_RESET`/`BLOCK_ICMP`), `srcIpGroups`, `destIpGroups`, `nwServices`, `nwApplications`, `locations`, `departments`, `enableLogging`.

### SSL inspection
| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/sslInspectionRules` | GET | All SSL inspection rules |

Key fields: `id`, `name`, `order`, `state`, `action` (`INSPECT`/`DO_NOT_INSPECT`), `urlCategories`, `locations`, `cloudApplications`.

### DLP
| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/dlpEngines` | GET | DLP engines |
| `/api/v1/dlpDictionaries` | GET | DLP dictionaries |
| `/api/v1/dlpNotificationTemplates` | GET | Notification templates |
| `/api/v1/dlpExactDataMatchSchemas` | GET | EDM schemas |

Key `dlpDictionaries` fields: `id`, `name`, `dictionaryType` (`PATTERNS_AND_PHRASES`/`EXACT_DATA_MATCH`), `customPhraseMatchType`, `phrases`, `custom`.

### Locations, users, status
| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/locations` | GET | All locations |
| `/api/v1/locations/{locationId}/sublocations` | GET | Sub-locations |
| `/api/v1/departments` | GET | All departments |
| `/api/v1/users?page={n}&pageSize={size}` | GET | Users (paginated) |
| `/api/v1/status` | GET | Tenant activation status |
| `/api/v1/status/activation` | PUT | Activate pending changes (write: not for audit) |

Key `locations` fields: `id`, `name`, `parentId` (0 if top-level), `sslScanEnabled`, `surrogateIP`, `authRequired`, `vpnCredentials`. A stale last-policy-push (over 24 hours) means changes are pending activation. Sub-locations inherit parent settings unless overridden, so a restrictive parent policy can be undone by a permissive sub-location override: check both.

## ZPA endpoints

All ZPA config endpoints are prefixed `/mgmtconfig/v1/admin/customers/{custId}`; the tables below show the suffix.

### Application segments and server groups
| Suffix | Method | Description |
|---|---|---|
| `/application` | GET | All application segments |
| `/application/{appId}` | GET | One segment |
| `/application/segmentGroup` | GET | Segment groups |
| `/serverGroup` | GET | All server groups |

Key application-segment fields: `id`, `name`, `domainNames`, `tcpPortRanges` (`[from, to]` pairs), `udpPortRanges`, `bypassType` (`NEVER` = always inspect / `ALWAYS` = bypass), `doubleEncrypt`, `segmentGroupId`, `serverGroups`, `enabled`.

### Access policies
| Suffix | Method | Description |
|---|---|---|
| `/policySet/rules/policyType/ACCESS_POLICY` | GET | Access policy rules |
| `/policySet/rules/policyType/TIMEOUT_POLICY` | GET | Timeout policy rules |
| `/policySet/rules/policyType/CLIENT_FORWARDING_POLICY` | GET | Client forwarding rules |
| `/policySet/rules/policyType/ISOLATION_POLICY` | GET | Browser isolation rules |

Key access-rule fields: `id`, `name`, `action` (`ALLOW`/`DENY`), `policyType`, `conditions`, `appConnectorGroups`, `appServerGroups`, `customMsg`, `operator` (`AND`/`OR`). Condition operand types: `APP`, `APP_GROUP`, `SAML`, `SCIM`, `SCIM_GROUP`, `POSTURE`, `TRUSTED_NETWORK`, `CLIENT_TYPE`.

### Connectors
| Suffix | Method | Description |
|---|---|---|
| `/connector` | GET | All connectors |
| `/connector/{connId}` | GET | One connector |
| `/connectorGroup` | GET | All connector groups |

Key connector fields: `id`, `name`, `enabled`, `currentVersion`, `expectedVersion`, `upgradeAttempt`, `connectorGroupId`, `privateIp`, `publicIp`, `platform`, `runtimeOS`, `lastBrokerConnectTime`. Compare `currentVersion` against `expectedVersion` for drift.

### Identity, posture, provisioning
| Suffix | Method | Description |
|---|---|---|
| `/idp` | GET | Configured IdPs |
| `/posture` | GET | Posture profiles |
| `/samlAttribute` | GET | SAML attributes |
| `/scimAttributeHeader` | GET | SCIM attribute headers |
| `/associationType/CONNECTOR_GRP/provisioningKey` | GET | Connector provisioning keys |
| `/associationType/SERVICE_EDGE_GRP/provisioningKey` | GET | Service Edge provisioning keys |

Key IdP fields: `id`, `name`, `idpType` (`USER`/`ADMIN`/`USER_AND_ADMIN`), `ssoType` (`SAML`/`OIDC`), `domainList`, `enableScimBasedPolicy`, `scimEnabled`, `loginUrl`, `certificates` (check expiry). Key provisioning-key fields: `id`, `name`, `enabled`, `maxUsage`, `usageCount`, `expirationInEpochSec`, `associationType`.

## Rate limits and backoff

**ZIA:** roughly 40 requests per 10 seconds for general calls, 5 authentication attempts per 60 seconds, 10 bulk-export calls per 60 seconds. A 429 carries a `Retry-After` header; back off exponentially from 1 second to a 30-second cap. Prefer bulk endpoints (for example `/urlFilteringRules` returns every rule in one call) over per-rule retrieval.

**ZPA:** roughly 20 GET (read) requests per 10 seconds, 10 write requests per 10 seconds, 5 authentication attempts per 60 seconds. ZPA does not return `Retry-After`; use client-side backoff from 2 seconds, doubling to a 30-second cap.

## Pagination

ZPA list endpoints paginate:
```
GET /mgmtconfig/v1/admin/customers/{custId}/application?page=1&pagesize=500
```
`page` defaults to 1; `pagesize` defaults to 20 with a maximum of 500. The response carries `totalPages`; iterate every page for a complete audit data set. ZIA returns policy rules (URL, firewall, SSL) in a single response; ZIA user endpoints paginate with `page` and `pageSize`.

## Multi-tenant note

There is no cross-tenant API. Audit each ZIA or ZPA tenant independently, keep separate credentials per tenant, and label every finding with its tenant. For Cloud Connector or Branch Connector deployments, confirm the tenant ID in the connector configuration matches the tenant being audited.
