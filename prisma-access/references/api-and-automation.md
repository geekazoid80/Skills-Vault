# Prisma Access API and automation: Strata Cloud Manager, Insights, CLI, and secret handling

Endpoints, authentication, CLI, and query language for reading and auditing a Prisma Access tenant programmatically. Read-only audit is the default posture here; every credential involved lives in the secret store, never inline. Architecture is in `architecture.md`; the operational meaning of these reads is in `operations.md`.

## Authentication

### Strata Cloud Manager: OAuth 2.0 client-credentials flow

SCM uses OAuth 2.0 with a Service Account bound to a Tenant Service Group (TSG). Every call carries a Bearer token from the token endpoint. Use placeholder values only; never write a real client secret or token into a script, a runbook, or a saved URL (see the secret-store section below).

Token request:

```
POST https://auth.apps.paloaltonetworks.com/oauth2/access_token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<SERVICE_ACCOUNT_CLIENT_ID>
&client_secret=<SERVICE_ACCOUNT_CLIENT_SECRET>
&scope=tsg_id:<YOUR_TSG_ID>
```

Token response:

```json
{
  "access_token": "<ACCESS_TOKEN>",
  "token_type": "Bearer",
  "expires_in": 899,
  "scope": "tsg_id:<YOUR_TSG_ID>"
}
```

- Tokens expire in 899 seconds (roughly 15 minutes). Cache and refresh proactively rather than per request.
- The `scope` must include the TSG ID; omitting it returns 401.
- The Service Account needs at least an `Auditor` or `View-Only Administrator` role for read-only audit access. That role ceiling is deliberate: an audit account should not carry write scope.

Using the token:

```
GET https://api.sase.paloaltonetworks.com/sse/config/v1/<resource>
Authorization: Bearer <ACCESS_TOKEN>
```

### Legacy Panorama Cloud Services API

For tenants still on Panorama with the Cloud Services plugin, use the PAN-OS XML API with a key generated from Panorama:

```
GET https://<PANORAMA_HOST>/api/?type=keygen&user=<USERNAME>&password=<PASSWORD>
```

The returned key authenticates config reads:

```
GET https://<PANORAMA_HOST>/api/?type=config&action=get&xpath=<XPATH>&key=<API_KEY>
```

Legacy responses are XML; Prisma Access objects live under the Cloud Services device-group hierarchy. If a tenant has migrated to SCM, the legacy API can return stale data, so confirm the authoritative plane before trusting a read.

## Strata Cloud Manager configuration API

Base URL: `https://api.sase.paloaltonetworks.com/sse/config/v1`

All endpoints accept a `folder` query parameter to scope results: `Mobile Users`, `Remote Networks`, `Service Connections`, or `Shared`.

### Security policy and profiles

```
GET /security-rules?folder=Mobile Users
GET /security-rules?folder=Remote Networks
GET /decryption-rules?folder=Mobile Users
GET /nat-rules?folder=Mobile Users
```

Per-rule fields: `name`, `source`, `destination`, `from` (source zones), `to` (destination zones), `application` (App-ID list or `["any"]`), `service` (objects or `["application-default"]` / `["any"]`), `action` (`allow`, `deny`, `drop`, `reset-client`, `reset-server`, `reset-both`), `profile_setting` (Security Profile Group or individual profiles), `disabled`, `log_start` / `log_end`, `tag`.

```
GET /security-profile-groups?folder=Shared
GET /anti-spyware-profiles?folder=Shared
GET /vulnerability-protection-profiles?folder=Shared
GET /wildfire-anti-virus-profiles?folder=Shared
GET /url-filtering-profiles?folder=Shared
GET /dns-security-profiles?folder=Shared
GET /file-blocking-profiles?folder=Shared
GET /data-filtering-profiles?folder=Shared
```

A profile group lists its bound profile names per type: `virus`, `spyware`, `vulnerability`, `url-filtering`, `file-blocking`, `wildfire-analysis`, `data-filtering`. An allow rule whose `profile_setting` names no group is the uninspected-traffic finding from `operations.md`.

### Objects, remote networks, and mobile users

```
GET /addresses?folder=Shared
GET /address-groups?folder=Shared
GET /application-filters?folder=Shared
GET /application-groups?folder=Shared

GET /remote-networks
GET /ike-gateways
GET /ipsec-tunnels
GET /ike-crypto-profiles
GET /ipsec-crypto-profiles
GET /bgp-routing

GET /mobile-users/regions
GET /mobile-agent/global-settings
GET /hip-objects
GET /hip-profiles

GET /service-connections
```

Crypto profiles report encryption algorithm (AES-128/256-CBC, AES-128/256-GCM), hash (SHA256/384/512), DH group (14/19/20), and SA lifetime, which feeds the remote-network strength check. IKE gateways report `peer_address`, `authentication` (pre-shared-key or certificate), `protocol` (IKEv1/IKEv2), and a `crypto_profile` reference. Service connections report `region`, `ike_gateway`, `ipsec_tunnel`, `subnets`, `bgp`, and `qos`.

## Prisma Access Insights API

Operational telemetry (tunnel status, connected users, client versions, bandwidth) rather than config. Base URL differs by region:

```
Base URL: https://pa-<REGION>.api.prismaaccess.com/api/sase/v2.0
```

Authentication uses the same SCM OAuth 2.0 token. Queries are POSTed with a property list and an optional filter:

```
POST /resource/tenant/<TSG_ID>/custom/query/prisma_sase_external_network
{
  "properties": [
    {"property": "site_name"},
    {"property": "tunnel_status"},
    {"property": "node_type"},
    {"property": "last_status_change"}
  ],
  "filter": {
    "operator": "AND",
    "rules": [
      {"property": "tunnel_status", "operator": "equals", "values": ["down"]}
    ]
  }
}
```

Other useful query resources: `prisma_sase_connected_user` (user, host IP, client version, compute location, HIP status), `prisma_sase_bandwidth` (site, allocated/used Mbps, utilisation percentage, filterable on a threshold), and `prisma_sase_gp_client_versions` (client version, count) for the version-distribution check in the audit.

## Common response structure

SCM config responses share an envelope:

```json
{
  "data": [
    {"id": "<UUID>", "name": "<RESOURCE_NAME>", "folder": "Mobile Users"}
  ],
  "offset": 0,
  "total": 42,
  "limit": 200
}
```

`data` is the array of resources; `offset` is the 0-based pagination offset; `total` is the total matching; `limit` is the max per request (default 200). Page by incrementing `offset` by `limit` until `offset >= total`:

```
GET /security-rules?folder=Mobile Users&offset=0&limit=200
GET /security-rules?folder=Mobile Users&offset=200&limit=200
```

### Error responses and codes

```json
{
  "_errors": [
    {"code": "E003", "message": "Invalid Object",
     "details": {"errorType": "Invalid Object", "message": "<DETAIL>"}}
  ],
  "_request_id": "<UUID>"
}
```

- `401 Unauthorized`: token expired or missing/incorrect TSG ID in scope.
- `403 Forbidden`: the Service Account lacks the required role.
- `404 Not Found`: resource or folder does not exist.
- `429 Too Many Requests`: rate limit exceeded (see below).

Do not infer the cause of a non-2xx: capture the full status, headers, and body, retry once to tell transient from permanent, and read the `_errors` detail before concluding. A failing read does not prove a write would fail, and vice versa.

## Rate limiting

| Endpoint category | Limit | Window |
|---|---|---|
| Configuration read (`GET`) | 60 requests | per minute |
| Configuration write (`POST`/`PUT`/`DELETE`) | 30 requests | per minute |
| Prisma Access Insights queries | 120 requests | per minute |

A `429` carries a `Retry-After` header (seconds). For audit workflows: batch reads (retrieve full resource lists, not individual objects), page at `limit=200`, cache responses for the audit session (config is point-in-time and stable within the window, so a local cache with a short TTL avoids re-fetching), and time-bound Insights queries so they do not scan the whole data lake per call.

## PAN-OS CLI for troubleshooting

From a compute location reached via the SCM terminal or Panorama CLI:

```
show global-protect-gateway statistics      # GlobalProtect gateway status
show global-protect-gateway current-user     # active GlobalProtect users
show tunnel ipsec                            # service-connection / remote-network tunnels
show running security-policy                 # security-policy hit counts
show wildfire status                         # WildFire connectivity and queue
show url-cloud status                        # PAN-DB URL database version
```

## Cortex Query Language

Prisma Access logs land in Cortex Data Lake (schema in `architecture.md`). Query with CQL:

```sql
-- Blocked connections from non-US external sources
SELECT src, dst, app, rule, action, time_generated
FROM `firewall.traffic`
WHERE action = 'deny' AND srcloc != 'US'
ORDER BY time_generated DESC
LIMIT 1000

-- Top applications by bandwidth in the last hour
SELECT app, SUM(bytes_sent + bytes_received) AS total_bytes
FROM `firewall.traffic`
WHERE time_generated > NOW() - INTERVAL 1 HOUR
GROUP BY app
ORDER BY total_bytes DESC
LIMIT 20
```

Cortex Data Lake forwards to Microsoft Sentinel (Cortex Sentinel connector) and Splunk (the Palo Alto Splunk app for Cortex Data Lake) for correlation with other estate telemetry.

## API version notes

- The SCM config API uses versioned paths (`/sse/config/v1/`); check release notes for breaking changes on a version increment.
- The Insights API (`/api/sase/v2.0/`) region prefix (`pa-<REGION>`) corresponds to the tenant's primary compute region and can differ by region.
- The legacy Panorama API does not version Prisma Access xpaths separately from on-prem config; the Cloud Services plugin version determines available features.

## Secret-store discipline

Every credential here is a real secret: the SCM Service Account `client_id` and `client_secret`, the Panorama API key (and the username/password that mint it), and remote-network pre-shared keys. Keep them in the project secret store (see `secrets-hygiene`), reference them from environment or a gitignored config file at runtime, and never inline a live value in a script, a saved API URL, a runbook, or a policy export. Client secrets have a configurable expiry: track the lifetime and rotate in place through SCM Identity and Access before it lapses, rather than discovering the audit account has stopped authenticating. When a subprocess shells out with a token in its arguments, scrub both its output and any raised exception, since a stringified `CalledProcessError` leaks the full argv.
