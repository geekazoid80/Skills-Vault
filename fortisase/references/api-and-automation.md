# FortiSASE API and automation

The programmatic surface for driving and auditing FortiSASE: FortiCloud IAM bearer-token authentication and refresh, the FortiSASE management API, the FortiOS CMDB and monitor REST API that FortiSASE exposes, the common response structures, and the pagination, rate-limiting, and error handling an automated audit must respect. Every credential shown here is a placeholder; store the real values in the secret store, never inline.

## FortiCloud authentication

All FortiSASE API calls carry a bearer token from the FortiCloud IAM service. The token is scoped to the FortiCloud account and grants access to FortiSASE tenant resources per the IAM role assignments.

### Token request

```
POST https://customerapiauth.fortinet.com/api/v1/oauth/token/
Content-Type: application/json

{
  "username": "<forticloud_username>",
  "password": "<forticloud_password>",
  "client_id": "<api_client_id>",
  "grant_type": "password"
}
```

### Token response

```json
{
  "access_token": "<ACCESS_TOKEN_PLACEHOLDER>",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "<REFRESH_TOKEN_PLACEHOLDER>"
}
```

### Token refresh

The token TTL is typically 3600 seconds. For an audit that runs longer than the TTL, refresh rather than re-authenticate:

```
POST https://customerapiauth.fortinet.com/api/v1/oauth/token/
Content-Type: application/json

{
  "refresh_token": "<refresh_token>",
  "client_id": "<api_client_id>",
  "grant_type": "refresh_token"
}
```

### Request headers

Every subsequent request carries:

```
Authorization: Bearer <access_token>
Content-Type: application/json
```

### IAM permission scopes

A read-only audit needs read scopes only. Requesting more than read is a least-privilege violation.

| Permission scope | Required for |
|---|---|
| `fortisase:read` | Tenant topology, PoP status, thin edge inventory |
| `fortisase:endpoint:read` | Endpoint compliance, ZTNA tags, FortiClient status |
| `fortisase:policy:read` | Firewall policies, SWG profiles, ZTNA rules |
| `fortisase:logging:read` | Log configuration, alert policies |
| `forticloud:account:read` | License status, subscription details |

## FortiSASE management API

Base URL: `https://<tenant>.fortisase.com/api/v1/fortisase`

### Tenant and topology

| Endpoint | Method | Description |
|---|---|---|
| `/pops` | GET | List all PoPs with status |
| `/pops/{pop_id}` | GET | PoP detail (capacity, region, health) |
| `/thin-edges` | GET | List all thin edge sites |
| `/thin-edges/{edge_id}` | GET | Thin edge detail |
| `/thin-edges/{edge_id}/sdwan/health` | GET | SD-WAN overlay health metrics |
| `/thin-edges/{edge_id}/firmware` | GET | Thin edge firmware version and update status |
| `/license/status` | GET | License utilisation and expiration |
| `/endpoints/summary` | GET | Endpoint count summary (connected, total, by platform) |

### Endpoint and compliance

| Endpoint | Method | Description |
|---|---|---|
| `/endpoints/compliance` | GET | Compliance summary across all endpoints |
| `/endpoints/ztna-tags` | GET | ZTNA tag assignment inventory |
| `/endpoints/groups` | GET | Endpoint group definitions and membership |
| `/ems/status` | GET | FortiClient EMS integration status |

### Logging and analytics

| Endpoint | Method | Description |
|---|---|---|
| `/logging/status` | GET | FortiAnalyzer Cloud connection status |
| `/logging/forwarders` | GET | Log forwarding configuration |
| `/logging/alerts` | GET | Alert policy definitions |

## FortiOS REST API (policy configuration)

FortiSASE exposes FortiOS CMDB configuration and monitor data via the standard FortiOS REST API pattern. These endpoints carry the security policy, UTM profiles, and inspection settings applied to SWG and ZTNA traffic.

Base URL: `https://<tenant>.fortisase.com/api/v2`

### Firewall policies

| Endpoint | Method | Description |
|---|---|---|
| `/cmdb/firewall/policy` | GET | All firewall policies (SWG and ZTNA) |
| `/cmdb/firewall/policy/{policy_id}` | GET | Specific policy detail |
| `/cmdb/firewall/central-snat-map` | GET | Central SNAT policy table |
| `/cmdb/firewall/address` | GET | Address objects |
| `/cmdb/firewall/addrgrp` | GET | Address groups |
| `/cmdb/firewall/service/custom` | GET | Custom service definitions |
| `/cmdb/firewall/service/group` | GET | Service groups |

### ZTNA configuration

| Endpoint | Method | Description |
|---|---|---|
| `/cmdb/firewall/access-proxy` | GET | ZTNA access proxy definitions |
| `/cmdb/firewall/access-proxy/{name}/api-gateway` | GET | ZTNA API gateway rules |
| `/cmdb/firewall/access-proxy/virtual-host` | GET | ZTNA virtual host (server) definitions |
| `/cmdb/user/device-category` | GET | Device categories (posture tags) |
| `/cmdb/user/group` | GET | User group definitions |
| `/cmdb/user/saml` | GET | SAML IdP integration settings |
| `/cmdb/user/ldap` | GET | LDAP server integration settings |

### UTM / security profiles

| Endpoint | Method | Description |
|---|---|---|
| `/cmdb/antivirus/profile` | GET | Antivirus profiles |
| `/cmdb/webfilter/profile` | GET | Web filter profiles |
| `/cmdb/webfilter/ftgd-local-cat` | GET | Local web filter categories |
| `/cmdb/application/list` | GET | Application control lists |
| `/cmdb/ips/sensor` | GET | IPS sensor profiles |
| `/cmdb/ips/rule` | GET | IPS rule definitions |
| `/cmdb/dnsfilter/profile` | GET | DNS filter profiles |
| `/cmdb/videofilter/profile` | GET | Video filter profiles |
| `/cmdb/casb/profile` | GET | Inline CASB profiles |
| `/cmdb/dlp/sensor` | GET | DLP sensor profiles |
| `/cmdb/firewall/ssl-ssh-profile` | GET | SSL/SSH inspection profiles |

### FortiGuard and system monitoring

| Endpoint | Method | Description |
|---|---|---|
| `/monitor/system/fortiguard` | GET | FortiGuard signature versions and status |
| `/monitor/fortiguard/service-communication-stats` | GET | FortiGuard service communication statistics |
| `/monitor/fortiguard/server-list` | GET | FortiGuard server list and connectivity |
| `/monitor/system/available-certificates` | GET | Available certificates for SSL inspection |
| `/monitor/license/status` | GET | License feature status |

## Common response structures

### Firewall policy object

```json
{
  "policyid": 1,
  "name": "SWG-Internet-Access",
  "srcintf": [{"name": "fortisase-swg"}],
  "dstintf": [{"name": "wan"}],
  "srcaddr": [{"name": "all"}],
  "dstaddr": [{"name": "all"}],
  "action": "accept",
  "status": "enable",
  "schedule": "always",
  "service": [{"name": "ALL"}],
  "utm-status": "enable",
  "av-profile": "default",
  "webfilter-profile": "corporate-web-filter",
  "application-list": "corporate-app-control",
  "ips-sensor": "high-security",
  "ssl-ssh-profile": "deep-inspection",
  "logtraffic": "all"
}
```

Audit read: `action accept` with `srcaddr`/`dstaddr` `all` and `service ALL` is over-permissive; `utm-status enable` with all four UTM profiles bound and `ssl-ssh-profile deep-inspection` is the healthy shape; `logtraffic` should be `all` or `utm`.

### ZTNA access proxy object

```json
{
  "name": "ztna-internal-apps",
  "vip": "ztna-vip-internal",
  "client-cert": "enable",
  "auth-portal": "enable",
  "api-gateway": [
    {
      "id": 1,
      "url-map": "/app1",
      "service": "https",
      "realservers": [
        {"id": 1, "ip": "10.0.1.10", "port": 443, "status": "active"}
      ],
      "saml-server": "corporate-idp",
      "ztna-tags": [
        {"name": "compliant-device"},
        {"name": "os-patched"}
      ]
    }
  ]
}
```

Audit read: a non-empty `ztna-tags` plus a `saml-server` is the zero-trust shape (identity plus posture); an empty `ztna-tags` array or a rule keyed only on source address is the finding.

### Thin edge status object

```json
{
  "edge_id": "<EDGE_SERIAL_PLACEHOLDER>",
  "name": "branch-office-example",
  "status": "online",
  "tunnel_status": "up",
  "tunnel_type": "ipsec",
  "pop_connected": "region-1",
  "firmware": {"current": "7.4.3", "recommended": "7.4.4", "status": "update_available"},
  "sdwan": {
    "status": "active",
    "health_checks": [
      {"name": "internet-check", "status": "alive", "latency": 12.5, "jitter": 2.1, "packet_loss": 0.0, "sla_pass": true}
    ]
  }
}
```

Audit read: `tunnel_status down` is Critical; `firmware.status update_available` with a gap greater than one major version is High; `sla_pass false` on a health check is an SLA violation to correlate against the failover-bypass check.

### Endpoint compliance summary object

```json
{
  "total_endpoints": 1250,
  "compliant": 1087,
  "non_compliant": 163,
  "compliance_rate": 86.96,
  "breakdown": {
    "os_patch_overdue": 45,
    "av_signatures_stale": 32,
    "critical_vulnerabilities": 18,
    "firewall_disabled": 12,
    "disk_encryption_off": 56
  }
}
```

## Pagination

FortiOS REST responses paginate large result sets:

| Parameter | Description | Default |
|---|---|---|
| `count` | Maximum items per page | 500 |
| `start` | Starting index (0-based) | 0 |
| `with_meta` | Include metadata (total count) | false |

```
GET /api/v2/cmdb/firewall/policy?count=100&start=0&with_meta=true
```

Response metadata includes `matched_count` (total) and `next_idx` (the `start` for the next page). Loop on `next_idx` until it is absent or exceeds `matched_count`.

## Rate limiting

### FortiCloud API

| Limit | Value |
|---|---|
| Requests per minute (per token) | 60 |
| Requests per hour (per token) | 1000 |
| Concurrent connections | 10 |
| Rate-limit response | `429 Too Many Requests` |
| Retry header | `Retry-After: <seconds>` |

### FortiOS REST API (direct device)

| Limit | Value |
|---|---|
| Concurrent admin sessions | 32 (default) |
| API request timeout | 300 seconds |
| Maximum response size | 50 MB |
| Session idle timeout | 900 seconds (configurable) |

### Backoff

On `429`, back off exponentially (1s, 2s, 4s, 8s, capped at 60s) and prefer the `Retry-After` value when the server provides one. For an audit querying many endpoints, batch where possible and keep a request queue that respects the per-minute limit.

## Error handling

Do not infer the cause of a failure; capture the full status and body, then act on the actual code. A failing read does not prove a write would fail, and a transient `403` or `429` is not a permissions verdict.

| HTTP status | Meaning | Audit action |
|---|---|---|
| `200` | Success | Process the response |
| `400` | Bad request | Fix the query syntax |
| `401` | Token expired or invalid | Refresh the token and retry |
| `403` | Insufficient permissions | Verify IAM role assignments (retry once to rule out a transient) |
| `404` | Not found | Feature may not be configured; document as N/A |
| `408` | Request timeout | Retry with a smaller scope or pagination |
| `429` | Rate limited | Back off; respect `Retry-After` |
| `500` | Internal server error | Retry after a delay; escalate if persistent |
| `503` | Service unavailable | FortiSASE degradation; check the status page |

## Thin edge direct queries

For cloud-vs-edge policy consistency or detailed device status, the thin edge FortiGate can be queried directly with the standard FortiOS REST pattern (`POST /api/v2/authentication` for a session, then `GET /api/v2/monitor/system/status`, `/api/v2/cmdb/firewall/policy`, `/api/v2/cmdb/system/sdwan`, `/api/v2/monitor/vpn/ipsec`). The thin edge admin credential is a separate secret from the FortiCloud token; store it in the secret store the same way. This direct-device surface overlaps the on-prem FortiGate world, so for a full standalone FortiGate audit use `fortigate-firewall-audit`; here it is only a consistency cross-check against the cloud policy.

## Secret discipline

The FortiCloud username and password, the API client ID, the derived access and refresh tokens, and any thin edge admin credential are all secrets. Keep them in the project secret store and reference them at runtime; never inline a real value into a saved API URL, a runbook, a committed script, or a report. Tokens are short-lived but a leaked one is live until it expires, so treat a leak as a rotate-now event. See `secrets-hygiene` for the store pattern and the leak-response procedure.
