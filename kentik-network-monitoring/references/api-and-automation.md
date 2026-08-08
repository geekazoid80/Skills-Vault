# Kentik API, automation, synthetics, and pitfalls

Programmatic access to Kentik, the infrastructure-as-code paths, built-in synthetic monitoring, and the common operational traps.

## REST API

- Base URL: `https://api.kentik.com/api/v5/`.
- Authentication: an API token in the `X-CH-Auth-Email` and `X-CH-Auth-API-Token` headers. Keep both in the secret store (`secrets-hygiene`), never inline in a saved query or a committed script.

### Key endpoints

```
GET  /devices              # List monitored devices
POST /query/topXdata       # Ad-hoc flow query
GET  /alerting/policies    # List alert policies
POST /alerting/policies    # Create an alert policy
GET  /bgp/routes           # BGP route data
GET  /synthetics/tests     # Synthetic test list
POST /tags                 # Manage custom tags
```

## The topXdata query API

The query API is the core power of Kentik: a multi-dimensional flow query with filters, a metric, dimensions, a lookback window, and a top-N.

```json
POST /query/topXdata
{
  "queries": [{
    "query": {
      "metric": "bytes",
      "dimension": ["src_ip", "dst_ip"],
      "filters": {
        "connector": "All",
        "filterGroups": [{
          "connector": "All",
          "filters": [{
            "filterField": "dst_port",
            "operator": "=",
            "filterValue": "443"
          }]
        }]
      },
      "lookback_seconds": 3600,
      "topx": 20
    }
  }]
}
```

## Terraform provider

- The `kentik/kentik` provider on the Terraform Registry.
- Manages devices, tags, alert policies, and synthetic tests.
- State-based management for IaC workflows.

## Python SDK

- The `kentik-api` package on PyPI wraps the REST API with Python objects.
- Use cases: automated device onboarding, custom reporting, alert integration.

## Synthetic monitoring

- Built-in active probing alongside flow analytics.
- HTTP, TCP, and ICMP synthetic tests.
- Agent-based (deploy Kentik agents at sites).
- Correlate synthetic results with flow analytics.
- Measures latency, jitter, packet loss, and availability.

## Common pitfalls

1. **Flow sampling too aggressive**: high sampling (1:10000) loses visibility into small flows. Balance the sampling rate against device CPU; start at 1:1000 for core routers.
2. **Missing BGP feed**: flow without BGP lacks AS-path enrichment. Configure BGP peering from core routers to Kentik.
3. **Custom tags not applied**: tags must be configured explicitly, or queries lack business context (customer, site, application).
4. **DDoS thresholds too tight**: the baseline needs 2+ weeks; tight thresholds during learning cause false positives.
5. **Not using "What Changed?"**: manual query iteration is slow; use AI Insights to find the dominant dimension first, then drill down.
6. **VPC Flow Log gaps**: cloud flow logs may sample, delay, or drop fields depending on the provider. Verify completeness before relying on them for billing or security.
7. **Ignoring RPKI validation**: RPKI alerts flag routing-security issues; configure ROA validation to catch them early.
