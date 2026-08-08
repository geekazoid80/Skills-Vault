# Kentik traffic analysis: DDoS, BGP monitoring, and AI Insights

DDoS detection and mitigation, BGP route monitoring, and the AI-powered analysis that finds the dominant dimension fast.

## DDoS detection and defence

### Baseline profiling

- ML-based traffic profiling per customer, network, application, and interface.
- Learns the normal patterns: volume, packet rate, protocol distribution, geographic distribution.
- Builds per-dimension baselines (hourly, daily, weekly).

### Anomaly detection

- Real-time comparison of current traffic against the learned baselines.
- An alert triggers when traffic exceeds normal by a configured multiplier.
- Multi-dimensional: volume, packet rate, protocol ratio, source diversity.

### Attack classification

- **Volumetric**: bandwidth exhaustion (UDP flood, DNS amplification, NTP reflection).
- **Protocol**: state exhaustion (SYN flood, ACK flood, fragmentation).
- **Application**: application-layer exhaustion (HTTP flood, DNS query flood).

### Automated mitigation

- **RTBH (Remote Triggered Black Hole)**: announce a /32 route to null via a BGP community.
- **Flowspec**: BGP Flowspec rules for granular traffic filtering.
- **A10 Networks**: API integration to activate a scrubbing centre.
- **Radware DefensePro**: API-triggered mitigation.
- **Custom webhook**: trigger any external system via HTTP POST.

### Mitigation workflow

```
1. Kentik detects an anomaly exceeding the baseline threshold
2. An alert fires with attack-classification details
3. Automated mitigation activates (RTBH, Flowspec, or scrubber API)
4. Mitigation is in effect; Kentik continues monitoring
5. The attack subsides; auto-withdrawal or manual deactivation
6. A post-incident report is generated
```

Baselines need 2+ weeks of data. Tight thresholds during the learning period cause false positives.

## BGP monitoring

### Route collection

- Receives full BGP table feeds from customer routers.
- Integrates with public route collectors (RIPE RIS, RouteViews).
- Stores BGP RIB snapshots and update streams.

### Detections

- **Route change alerts**: prefix announcement/withdrawal, AS-path changes.
- **Prefix hijack**: an unexpected origin AS for your prefixes.
- **Route leak**: an unexpected transit AS in the path (a customer announces provider routes).
- **RPKI ROA validation**: alerts on RPKI-invalid route origins.
- **Subprefix hijack**: a more-specific prefix announced by an unauthorised AS.

### BGP + flow correlation

- Correlate a BGP route change with the traffic shift observed in flow data.
- Answer: when the route changed, did traffic follow, and did latency increase?
- Identify traffic-engineering opportunities from AS-path analysis.

This is monitoring and alerting, not protocol troubleshooting; for BGP adjacency and path-selection debugging see `bgp-analysis`.

## AI Insights

### "What Changed?" analysis

- ML-powered root-cause analysis for traffic anomalies.
- Automatically identifies the top contributing dimensions to any anomaly: which ASN, which source/destination prefix, which application/port, which device/interface.
- Cuts mean-time-to-identify from hours to seconds.

### Natural-language queries

- A conversational interface for flow data.
- Example: "Show me top talkers to AWS from the New York site in the last hour."
- Translates to an optimised flow query behind the scenes; available from the dashboard and the API.

### Saved queries and dashboards

- Save complex queries as reusable views.
- Custom dashboards with drag-and-drop query widgets.
- Alerting thresholds on any saved query.
- Scheduled reports (PDF, email).
