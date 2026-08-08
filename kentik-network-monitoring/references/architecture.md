# Kentik architecture: flow engine, enrichment, data model, NMS, and Map

How Kentik ingests and enriches flow at scale, the queryable data model, and the integrated SNMP and topology features.

## Flow analytics engine

- **Ingestion**: NetFlow v5/v9, IPFIX, sFlow, VPC Flow Logs (AWS, GCP, Azure), and an eBPF agent.
- **Scale**: designed for billions of flow records per day on a proprietary time-series datastore.
- **Query speed**: sub-second ad-hoc queries across months of full-granularity data.
- **Retention**: full-granularity flow retained for months, not sampled or rolled up.

## Flow enrichment

Every flow record is automatically enriched with:

- **BGP AS path**: source and destination AS, transit providers.
- **Geographic data**: GeoIP (MaxMind) for location context.
- **RPKI validation**: route-origin validation status.
- **IANA port registry**: application identification by port.
- **Custom tags**: device role, site, customer, business unit (user-defined).
- **Device metadata**: hostname, vendor, model (from SNMP).

Enrichment is what makes flow useful. Without a BGP feed there is no AS-path context; without custom tags there is no business context. Configure both.

## Data model

Flows are stored with all enrichment dimensions, enabling ad-hoc multi-dimensional queries:

```
Flow Record = {
  src_ip, dst_ip, src_port, dst_port, protocol,
  bytes, packets, duration,
  src_as, dst_as, as_path,
  src_geo, dst_geo,
  device, interface, direction,
  custom_tags...
}
```

Any of these dimensions can be a query dimension or a filter, which is why a single Kentik query can pivot from "top talkers" to "by ASN" to "by site" without re-instrumenting anything.

## Kentik NMS

SNMP-based device monitoring integrated with flow analytics:

- **SNMP polling**: device CPU, memory, interface utilisation, error counters.
- **Auto-discovery**: discover devices and interfaces via SNMP walk.
- **Correlation**: overlay device metrics on flow-analytics dashboards.
- **IP address search**: find IP assignments across devices.

## Kentik Map

- Automated topology visualisation combining SNMP, flow, and BGP data.
- Geographic and logical views.
- Interface-level traffic overlay from flow data.
- Device-health overlay from SNMP polling.
- Interactive: click a device to drill down into flow analytics.
