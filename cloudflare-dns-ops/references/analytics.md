# Cloudflare DNS analytics

## Overview

The Cloudflare DNS Analytics MCP server provides read-only access to zone listings, DNS record inventories, and DNS query analytics for Cloudflare-managed zones. Operations cover zone discovery, record inspection, query volume analysis, performance metrics, and trend analysis over time.

## Prerequisites

Three environment variables must be set before using the MCP server tools:

| Variable | Required | Scope / notes |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | Yes | Zone:Read permission scope. See secrets-hygiene callout below. |
| `CLOUDFLARE_ACCOUNT_ID` | Yes | Found in the Cloudflare dashboard under Account Home -> right sidebar. |
| `CLOUDFLARE_ZONE_ID` | Optional | Default zone ID used when a tool accepts a zone parameter; can be overridden per call. |

**Secrets hygiene:** `CLOUDFLARE_API_TOKEN` is a bearer credential. Never paste it into a prompt, store it in a source-controlled file, or log it. Set it as an environment variable via a secrets manager, a `.envrc` entry excluded from version control, or a vault-injected environment. Rotate immediately on suspected exposure. See `secrets-hygiene` for the full protocol.

## Tools

| Tool | Description |
|---|---|
| `list_zones` | List all DNS zones in the Cloudflare account. Returns zone names, IDs, status, and plan tier. Useful for discovery when the zone ID is unknown. |
| `get_zone` | Get details for a specific zone by ID: name, status, name servers, plan, DNSSEC status, creation date. |
| `list_dns_records` | List DNS records in a zone. Returns type, name, content, proxy status, and TTL for each record. Use for inventory audits and proxy-mode verification. |
| `get_dns_analytics` | Get DNS query analytics for a zone over a specified time range. Returns query counts, response codes (NOERROR, NXDOMAIN, SERVFAIL, etc.), and query type breakdown. |
| `get_dns_performance` | Get DNS performance metrics: query latency, response time percentiles, cache hit rate. Foundation DNS zones have access to extended percentile metrics (P50, P95, P99) and sourceIP dimension. |
| `get_dns_trends` | Get DNS trend analysis over time: query volume over a period, growth/decline patterns, anomaly indicators. Useful for capacity planning and detecting unexpected spikes. |

## Example queries

```
List all DNS zones in the account

Show all DNS records for zone <zone_id>

What are the DNS query analytics for my zone over the last 24 hours?

Show DNS query performance metrics for example.com

Get DNS query trends for zone <zone_id> over the past 7 days
```

## Analytics use cases

### Zone and record inventory

Use `list_zones` to discover all zones under the account, then `list_dns_records` to audit records per zone. Key checks:
- Verify proxy mode on each A/AAAA/CNAME record (proxied vs DNS-only).
- Identify stale records (old A/AAAA records that may expose origin IPs).
- Confirm CNAME flattening at apex is in place where needed.

### Query volume and error rates (get_dns_analytics)

Monitor NXDOMAIN rates: a spike may indicate subdomain takeover attempts, misconfigured records, or a misconfigured application sending queries for non-existent names. SERVFAIL spikes after a DNSSEC change indicate DS mismatch or propagation lag at the parent registrar.

### Latency and performance (get_dns_performance)

Foundation DNS zones expose extended latency data with P95/P99 percentiles and source IP dimension, enabling identification of geographic regions or specific clients experiencing high query latency. Standard zone performance data covers aggregate latency and cache hit ratios.

### Trend analysis (get_dns_trends)

Use trend data for capacity planning and anomaly detection. Unexpected query volume growth may indicate DNS amplification abuse targeting the zone, a new application generating more queries than expected, or a misconfigured client generating a query storm.

## Analytics availability by plan

| Feature | Free / Pro / Business | Enterprise | Foundation DNS |
|---|---|---|---|
| Query analytics window | 7 days | 7 days | 31 days |
| Performance percentiles | Aggregate | P95/P99 | P50/P95/P99 |
| Source IP dimension | No | No | Yes |
| GraphQL API | Limited | Full | Full |

## Relationship to dns-network-ops and cloudflare-dns-ops

Analytics operations (read-only, non-destructive) use this reference. For zone configuration changes, record management, DNSSEC enablement, and secondary DNS setup, see `references/architecture.md`. For architecture decisions and cross-platform design, see `dns-network-ops`.
