# Alerting design, data collection, and monitoring at scale

How to alert so that every alert gets acted on, how often to collect and how long to keep data, and how to scale monitoring across many sites and devices.

## Alerting design

### Threshold strategies

1. **Static threshold**: a fixed value (CPU > 90%, interface > 80%). Simple and predictable, but does not account for normal variation and generates false positives during known peaks or maintenance.
2. **Baseline deviation**: learn the normal pattern over time (hourly, daily, weekly) and alert when the metric deviates beyond N standard deviations. Fewer false positives, but needs a learning period and can miss slow degradation as the baseline shifts.
3. **Rate of change**: alert on rapid change (delta per second or minute), catching sudden failures independent of the absolute value (for example, utilisation jumping from 20% to 95% in two minutes).
4. **Composite / multi-condition**: combine metrics with AND/OR logic (CPU > 80% AND memory > 90% AND sustained for ten minutes). The quietest strategy; requires understanding the failure modes.

### Severity levels

| Level | Meaning | Response |
|---|---|---|
| Critical | Service-impacting; immediate action | Page the on-call engineer |
| Warning | Approaching threshold; proactive action | Email or chat notification |
| Informational | Notable event; no action | Dashboard or log only |

### Alert fatigue

Alert fatigue is the single biggest operational problem in network monitoring. Causes: too many non-actionable alerts, missing deduplication (one issue generates fifty alerts), no dampening (a flapping interface fires rapidly), and missing correlation (a device down triggers twenty interface alerts plus ten service alerts).

Mitigations:

- Every alert must have a documented response procedure.
- **Deduplication**: suppress duplicate alerts for the same issue.
- **Dampening**: require the condition to persist for N minutes before alerting.
- **Correlation**: use parent/child dependencies so a device-down suppresses its interface alerts.
- **Maintenance windows**: suppress alerts during planned changes.
- **Regular review**: disable any alert with no action taken in ninety days.

### Escalation pattern

```
Tier 1: auto-notification (email / chat)
  -> not acknowledged in 15 min ->
Tier 2: page the on-call engineer (PagerDuty / OpsGenie)
  -> not acknowledged in 30 min ->
Tier 3: page the team lead and manager
```

## Data-collection best practices

- **SNMP polling interval**: five minutes for capacity metrics, sixty seconds for availability, fifteen-to-thirty seconds for real-time dashboards (use sparingly).
- **Flow sampling**: full flow on smaller networks; sampled (1:1000 to 1:4096) on high-volume cores.
- **Synthetic test frequency**: one-to-five minutes for critical services, fifteen-to-thirty minutes for standard.
- **Log retention**: thirty-to-ninety days hot, one-to-two years archived for compliance.
- **SNMP version**: SNMPv3 with authentication and encryption for production; v2c only on isolated management networks.

## Monitoring at scale

### Distributed polling

Deploy multiple poller instances across sites. Each poller monitors its local devices and reports to a central NMS. This cuts WAN bandwidth for SNMP polling and provides monitoring resilience if the WAN fails. A single poller typically handles 500 to 2,000 devices; beyond that, distribute.

### Storage tiers

- **Hot** (1 to 30 days): full resolution, fast queries, SSD.
- **Warm** (30 to 180 days): reduced resolution (five-minute averages), HDD.
- **Cold** (1 to 2+ years): highly aggregated, compliance archive, object storage.

### Capacity planning

| Metric | Small (<500 devices) | Medium (500 to 5,000) | Large (5,000+) |
|---|---|---|---|
| Polling interval | 60s availability, 5m metrics | Same | Same (with distributed pollers) |
| Pollers | 1 | 1 to 3 | 5+ distributed |
| Flow records/day | <100M | 100M to 1B | 1B+ |
| Storage (1 year) | <1 TB | 1 to 10 TB | 10 to 100+ TB |
