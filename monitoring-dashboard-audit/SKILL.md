---
name: monitoring-dashboard-audit
description: "Use for a read-only audit of a network monitoring stack built on Grafana and Prometheus: dashboard inventory and staleness, panel and PromQL query quality, alert rule coverage and tuning, SLA and SLO report accuracy, and data source health (scrape targets, cardinality, retention, remote write). Triggers include \"audit our Grafana dashboards\", \"monitoring gap assessment\", \"which devices have no dashboard or alert\", \"alert fatigue\", \"too many alerts\", \"alerts nobody acts on\", \"dashboard shows no data\", \"PromQL review\", \"recording rule candidates\", \"SLO or error budget looks wrong\", \"burn rate alerting\", \"is monitoring ready for the migration\", \"did monitoring catch the incident\", \"cardinality explosion\", \"scrape target down\". Produces a coverage scorecard and prioritised findings; never changes dashboards, alerts or data sources. NOT for building dashboards or writing alert rules (grafana-dashboards, prometheus-configuration), NOT for defining SLOs from scratch (slo-implementation), NOT for choosing a monitoring platform (network-monitoring-selection), NOT for Zabbix (zabbix-templates-and-triage)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Monitoring dashboard audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: monitoring-dashboard-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

A structured assessment of network monitoring built on Grafana and Prometheus. It asks whether the dashboards cover what exists, whether the queries are right and affordable, whether the alerts fire when they should and not when they should not, whether SLA and SLO figures reflect real service, and whether the data underneath is healthy.

**Posture.** Read-only. The skill reads configuration and metrics through the Grafana and Prometheus HTTP APIs. It does not create, edit, silence or delete a dashboard, alert rule, contact point or data source. Findings and optimised queries are recommendations for the owners. Use a read-only token, never an admin one, and handle it per `secrets-hygiene`. API paths and queries were written from product documentation and were not run against live systems while authoring, so confirm them on the versions you operate.

Grafana and Prometheus API calls organised by audit step are in `references/cli-reference.md`; PromQL patterns for interface utilisation, error rates, BGP peer state and SNMP-derived metrics are in `references/query-reference.md`.

## When to use

- A monitoring gap assessment: do all critical devices and links have dashboards and alerts?
- A dashboard quality review: are the panels accurate and actionable for the operations team?
- An alert-fatigue investigation: teams report too many or irrelevant notifications masking real incidents.
- An SLA or SLO compliance review: do error-budget and availability numbers reflect delivery?
- Pre-migration readiness: will monitoring survive new devices, topology changes or a platform move?
- A post-incident review: did monitoring detect it, how fast did alerts fire, what let a failure stay silent?

## When not to use

- **Building a dashboard, writing a recording rule or an alert:** `grafana-dashboards` and `prometheus-configuration` own the authoring; this skill finds what is wrong with what exists.
- **Choosing the SLIs, SLOs and burn-rate alert design:** `slo-implementation`. This skill checks that an existing SLO is calculated correctly.
- **Which platform to use, or SNMP versus flow versus streaming telemetry:** `network-monitoring-selection`, with `network-streaming-telemetry`.
- **Zabbix environments:** `zabbix-templates-and-triage`; the PRTG, Cacti and Kentik skills for those platforms.
- **Tracing and OpenTelemetry pipelines:** `distributed-tracing`.
- **A device that is unhealthy right now:** `network-device-health`.

## Prerequisites

- **Grafana access:** a read-only service account token, confirmed working with the `Authorization: Bearer` header. Dashboards and search work at Viewer level, but the provisioning (alert rules, policies, contact points) and data source endpoints may need Editor or Admin permission to read. If an endpoint returns 403, record that as a coverage limit of the audit rather than asking for a write-capable token.
- **Prometheus access:** the HTTP API reachable (for example `/api/v1/status/config`), with whatever authentication the deployment uses.
- **Defined scope:** the device inventory, subnet ranges and critical service list, for coverage-gap analysis.
- **Baseline documentation:** the existing SLA and SLO targets, expected alert thresholds and runbooks to compare with.
- **Clock awareness:** confirm NTP across the monitoring stack, and treat all times as UTC (`utc-timestamps`); scrape timestamps and Grafana time ranges depend on consistent clocks.
- **Secrets:** never paste tokens into the conversation. Redact data source credentials and webhook URLs from any dashboard or alert JSON before quoting it.

## Procedure

Run the six steps in order. Each feeds the scorecard in Step 6.

### Step 1: Dashboard inventory

Enumerate every dashboard to learn the monitoring surface and find gaps, stale dashboards and organisational debt.

```
GET /api/search?type=dash-db&limit=5000
```

For each: uid, title, folder, tags, last-updated time. Dashboards not updated in over 180 days are staleness candidates, since they may point at retired metrics or devices. Look at folder structure: 50 or more dashboards at the root is organisational debt, and inconsistent prefixes or tags hurt discoverability mid-incident.

```
GET /api/dashboards/uid/<uid>
```

Record panel count, data source references and template variables. Flag hard-coded time ranges and panels that reference data sources that no longer exist, because empty panels erode operator trust.

Build the **coverage matrix**: map panels to the infrastructure inventory. A device, interface or service in the inventory but on no dashboard is a blind spot.

### Step 2: Panel and query analysis

Extract the PromQL from every panel target and assess:

- **Rate functions:** `rate()` needs a range at least two scrape intervals wide (four is the common safe choice). `irate()` uses only the last two points; it suits volatile short windows, not trend panels over long ranges.
- **Recording-rule candidates:** the same complex expression in three or more panels should be a recording rule. Find them by hashing normalised expressions. Typical candidates: interface utilisation, error-rate ratios, availability.
- **Cardinality:** queries aggregating high-cardinality labels with no matchers, or using `{__name__=~".*"}`, are expensive.
- **Thresholds:** gauge and stat panels without colour-coded thresholds give no at-a-glance severity; compare configured thresholds with operational standards (for example utilisation warning at 70% and critical at 90%).
- **Visualisation fit:** a time series on a gauge loses context, a single stat for a volatile metric misleads, and a 100-row unsorted table is unusable during an incident.

### Step 3: Alert rule validation

```
GET /api/v1/provisioning/alert-rules          (Grafana)
GET /api/v1/rules?type=alert                  (Prometheus)
```

For each rule evaluate:

- **Threshold fit:** thresholds should track operational impact, not arbitrary percentages. 50% on a 10 Gbps link is premature; 95% on a 100 Mbps WAN link is late. Check against link capacity and historical peaks.
- **Evaluation interval:** an interval longer than the scrape interval cannot catch short outages on critical infrastructure.
- **`for` duration:** `for: 0s` fires on transients and feeds alert fatigue; a long `for` on critical infrastructure is minutes of silent outage. Reasonable starting ranges: critical 2 to 5 minutes, warning 5 to 15.
- **Notification channels:** every rule needs at least one live channel. Check that channels still work (webhook returns 200, keys valid, SMTP reachable).
- **Routing and silences:** a catch-all route sending everything to one channel is a smell; silences must expire, because an open-ended silence masks a problem indefinitely.
- **Escalation:** critical alerts that only go to chat lack depth; they should escalate to paging after an acknowledgement timeout.

Both Grafana unified alerting and Prometheus-native alerting may be in use, so audit both and record which is authoritative for each alert category.

### Step 4: SLA and SLO reporting

- **Error budget:** `error_budget_remaining = 1 - (actual_errors / allowed_errors)`. Common mistakes: a calendar month where the SLO says rolling 30 days, planned maintenance left out of downtime, or availability taken from a single source when the service spans several components.
- **Availability SLIs:** uptime should come from probes (blackbox exporter, synthetic checks), not only device-reported state. MTTR that leaves out detection time understates recovery.
- **Burn-rate alerting:** use a long window with a short confirmation window (the standard pairs are 1 hour with 5 minutes at 14.4x, 6 hours with 30 minutes at 6x, and 3 days with 6 hours at 1x for a 30-day SLO); a single window fires too late or too often. See `slo-implementation` for the design. Severity should rise with burn rate.
- **Time zones:** Prometheus stores UTC; a dashboard in a local zone is the most common reason an SLA report disagrees with a business report.

### Step 5: Data source health

```
GET /api/v1/targets?state=active
GET /api/v1/status/tsdb
```

- **Scrape targets:** `up == 0` is a failing scrape (reachability, exporter health or authentication). A `scrape_duration_seconds` close to the interval means timeouts and gaps.
- **Cardinality:** list the top ten metrics by series count. Per-interface SNMP metrics on large chassis devices are the usual cause of explosions; over about 10,000 series for one metric name is worth investigating.
- **Retention:** it must cover the longest reporting window. 15-day retention under 30-day SLA dashboards produces incomplete reports. A WAL that is large against the TSDB (a rough rule: over 20%) can indicate write amplification from churn.
- **Remote write:** if Thanos, Cortex, Mimir or VictoriaMetrics sits behind remote write, check lag (over about 5 minutes is behind real time) and failed-sample counters.
- **Naming:** Prometheus conventions (snake_case, base units, unit suffixes such as `_bytes`, `_seconds`, `_total`) make cross-device comparison reliable.

### Step 6: Coverage report

- **Coverage scorecard:** rate each infrastructure category (core routers, distribution switches, WAN links, firewalls, load balancers) from 1 to 5: 1 none, 2 up/down only, 3 utilisation dashboards, 4 dashboards plus alerting, 5 dashboards, alerting and SLO tracking.
- **Alert quality:** alert-to-incident ratio, mean time to acknowledge and silence frequency per rule. Rules that are over 80% silenced or acknowledged with no action are candidates for retuning or removal.
- **Query optimisations:** for each inefficient query, the current and recommended expression, with recording rules first for anything in three or more panels.

## Severity tables

| Domain | Severity | Condition | Example |
|---|---|---|---|
| Coverage | Critical | Production device on no dashboard | Core router absent everywhere |
| Coverage | High | Service with dashboards but no alerting | WAN link monitored, no capacity alert |
| Coverage | Medium | Dashboard stale for over 180 days | Last edit predates a device refresh |
| Coverage | Low | No threshold colouring | Utilisation panel with no bands |
| Query | Critical | PromQL uses a metric that no longer exists | Panel empty after a rename |
| Query | High | `rate()` range under twice the scrape interval | `rate(metric[15s])` on a 30 s scrape |
| Query | Medium | Same expression in 3 or more panels | Utilisation formula in 5 dashboards |
| Query | Low | `irate()` on a long-range trend panel | 24 h overview using `irate()` |
| Alert | Critical | Rule with no notification channel | Silent alarm on critical infrastructure |
| Alert | High | Critical alert with `for` over 15 minutes | 15-minute detection gap |
| Alert | Medium | Warning alert with `for: 0s` | Transients drive fatigue |
| Alert | Low | Single channel, no escalation | Chat-only for a P1 alert |
| SLA | Critical | Error budget uses the wrong time window | Calendar month versus rolling 30 days |
| SLA | High | MTTR excludes detection time | MTTR understated |
| SLA | Medium | Single-window burn-rate alerting | One hour, no long window |
| SLA | Low | No historical trend on the SLO dashboard | No month-over-month view |
| Data source | Critical | Scrape target down for over 5 minutes | SNMP exporter unreachable |
| Data source | High | Over 10,000 series for one metric name | Per-interface metrics on a large chassis |
| Data source | Medium | Remote write lag over 5 minutes | Long-term store behind |
| Data source | Low | Metric naming breaks conventions | CamelCase, missing unit suffix |

These are starting points; adjust them to the environment and say so in the report.

## Decision trees

```
Where to start?
├─ Dashboard completeness unknown        -> Step 1
├─ Alert fatigue reported                -> Step 3
├─ SLA disputes or wrong reports         -> Step 4
├─ Gaps or missing metrics in graphs     -> Step 5
└─ General health check                  -> Steps 1 to 6

A panel query:
├─ Returns no data?
│  ├─ Metric exists in the TSDB?  yes -> check label matchers
│  └─ Metric absent?              -> Critical: exporter or scrape config broken
├─ Slow (over 10 s)?
│  ├─ High-cardinality labels     -> add matchers or aggregate
│  ├─ Wide range on a raw metric  -> recording rule
│  └─ Regex matcher               -> exact match where possible
└─ Unexpected values?
   ├─ rate() on a non-counter     -> use a gauge-appropriate function
   └─ Aggregation lost labels     -> add by or without

An alert rule:
├─ Never fires?        -> threshold too high, or metric absent (fix the scrape first)
├─ Fires constantly?   -> threshold under baseline, or `for` too short (raise to P95 plus margin; add a pending duration)
└─ Fires and is ignored -> fatigue
   ├─ Over 80% silenced -> remove or retarget
   └─ Low signal        -> longer `for`, or add an inhibition rule
```

## Report template

```
# Monitoring dashboard audit report

## Executive summary
- Scope: [Grafana instance, Prometheus endpoints, device count]
- Assessment date (UTC): [date]
- Dashboards: [total / active / stale]
- Alert rules: [total / firing / pending / inactive]
- Coverage score: [average across categories, 1 to 5]

## Coverage scorecard
| Category | Dashboards | Alerts | SLOs | Score |
|---|---|---|---|---|
| Core routers | [n] | [n] | [Y/N] | [1-5] |
| Distribution | [n] | [n] | [Y/N] | [1-5] |
| WAN links | [n] | [n] | [Y/N] | [1-5] |
| Firewalls | [n] | [n] | [Y/N] | [1-5] |

## Alert quality
| Metric | Value | Target |
|---|---|---|
| Alert-to-incident ratio | [ratio] | under 5:1 |
| Mean acknowledgement time | [duration] | under 15 min |
| Silences in 30 days | [count] | falling |
| Escalation coverage | [%] | 100% for critical |

## Findings by severity
[Critical, High, then Medium and Low: domain, finding, impact, recommendation]

## Query optimisations
| Dashboard | Panel | Current | Recommended | Expected saving |

## SLA and SLO accuracy
| Service | Reported availability | Validated availability | Discrepancy |

## Appendix
- Dashboard inventory with staleness dates
- Scrape target health summary
- Top-10 cardinality
```

## Troubleshooting

- **Grafana returns 401 or 403:** the token needs read access to every folder holding in-scope dashboards. Some provisioning and data source endpoints need more than Viewer; report which endpoints were out of reach rather than widening the token to write access.
- **Prometheus unreachable:** check connectivity and any reverse proxy; the base URL may need a path prefix if it runs under a subpath.
- **Empty dashboard inventory:** the search API paginates and folder permissions can hide dashboards from a restricted token. Raise `limit` or paginate.
- **Queries reference absent metrics:** SNMP exporter metric names change between exporter versions; check the exporter version and generator configuration.
- **No cardinality data:** the TSDB status endpoint needs Prometheus 2.14 or later. Without it, estimate with count queries, which are expensive on large installations.
- **SLA figures differ from business reports:** time zone handling. Use explicit UTC ranges or one consistent time-zone variable.
- **Duplicate alerting in Grafana and Prometheus:** audit both and name the authoritative system per category.

## Cross-references

- `grafana-dashboards` and `prometheus-configuration`: where the fixes for most findings are made (dashboard design, unified alerting, recording rules, PromQL, long-term storage).
- `slo-implementation`: how SLIs, SLOs and burn-rate alerts should be designed; this skill checks the implementation against it.
- `network-monitoring-selection` and `network-streaming-telemetry`: whether the signals are the right ones to collect.
- `zabbix-templates-and-triage`, `prtg-network-monitoring`, `cacti-network-monitoring`, `kentik-network-monitoring`: the equivalent surfaces for those platforms.
- `network-device-health`: the per-device check that a good dashboard and alert set should make routine.
- `incident-response-lifecycle` and `oncall-runbooks`: the post-incident monitoring review feeds these.
- `secrets-hygiene`: tokens, webhook URLs and data source credentials.
- `utc-timestamps`: report and query times in UTC.

## Red flags

- About to use an admin token for a read-only audit.
- About to edit, silence or delete a dashboard or alert from within the audit.
- About to quote dashboard or alert JSON containing webhook URLs or data source credentials.
- About to report a coverage figure with no inventory to measure it against.
- About to recommend lowering a threshold because it "never fires", without checking whether the metric exists.
- About to trust an SLA figure without checking its time window and time zone.
- About to count alert rules in one system when two systems evaluate alerts.

## Bottom line

Measure monitoring against the inventory it should cover, then check each layer: dashboards, queries, alerts, SLO maths and the data beneath. Score coverage, report alert quality by what operators actually do with alerts, and leave every change to the owners.

## Provenance

Re-authored from the Apache-2.0 `monitoring-dashboard-audit` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; the six-step procedure, severity tables, decision trees and report template kept; cross-references and secrets handling added for this vault.
