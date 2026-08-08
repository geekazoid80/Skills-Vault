---
name: grafana-dashboards
description: "Use for any Grafana dashboard design, review, or refactor work. Vendor-neutral on data source (Prometheus, Loki, Tempo, InfluxDB, Elasticsearch, MySQL, PostgreSQL, CloudWatch); examples lean Prometheus / PromQL because that is the most common pairing. Triggers include 'grafana', 'grafana dashboard', 'design a dashboard', 'visualise this metric', 'panel for X', 'RED method', 'USE method', 'golden signals', 'SLO dashboard', 'p95 latency panel', 'request rate panel', 'error rate panel', 'time-series vs stat vs heatmap', 'dashboard variables', 'dashboard provisioning', 'dashboards as code', 'dashboard rows', 'thresholds and colours', 'panel transformations', 'unify dashboards', 'reusable dashboard template', 'service-overview dashboard', 'infrastructure dashboard', 'database dashboard', 'application dashboard', 'business KPI dashboard'. Combines the design-discipline lens (information hierarchy, RED for services, USE for resources, panel-type-fits-question rule, variables for parameterisation, dashboard-as-code with Terraform / Ansible / file provisioner) with concrete JSON scaffolds (stat, time-series, table, heatmap, alert, query variable) and an explicit pattern catalogue (service overview, infrastructure, database, application). Customised from wshobson/agents/plugins/observability-monitoring/skills/grafana-dashboards (MIT). Pairs with slo-implementation (Stage 4 sibling; the SLO dashboard layout pattern lives there; this skill provides the panel-type discipline), zabbix-templates-and-triage (Stage 4 sibling; when Grafana visualises Zabbix data instead of Prometheus), oncall-runbooks (page-routing references the dashboard URL the on-call engineer should open first), systematic-debugging (Phase 1 boundary evidence often comes off a dashboard panel; clean panel design accelerates triage), secrets-hygiene (data-source credentials, Slack / Teams webhook UIDs, alert notification channels). Folds the assets/*.json reference pointers (api-dashboard, infrastructure-dashboard, database-dashboard) into inline panel-pattern catalogues. Advanced references (load on demand): loki-tempo-correlation (Loki LogQL, Tempo TraceQL, logs / traces / metrics correlation, derived fields, exemplars), unified-alerting-and-git-sync (Grafana Unified Alerting rules / contact points / notification policies / mute timings, plus 12.x Git Sync dashboards-as-code), mcp-observability-queries (querying Grafana via the Grafana MCP server). Additional triggers: 'loki', 'tempo', 'logql', 'traceql', 'logs to traces', 'exemplars', 'grafana alerting', 'contact points', 'notification policies', 'mute timings', 'git sync', 'dashboards as code', 'grafana mcp'. Folds chrishuffman5/domain-expert grafana (analytics + monitoring) and netclaw grafana-observability (Apache-2.0)."
license: MIT
metadata:
  version: "1.1.0"
---

# Grafana Dashboards

Specialist for production Grafana dashboard design and review. Two halves: the design lens (information hierarchy, RED, USE, panel-type-fits-question) and the implementation surface (panel JSON, variables, alerts, dashboard-as-code).

> **Skill marker**: When applying this skill, begin your reply with `[skill: grafana-dashboards]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the observability estate (data sources connected, naming conventions for dashboards / folders, audience for the panels) before designing. Only ask the user for information not already covered or specific to this dashboard.

Before designing, understand:

1. **Data sources and metrics**
   - Backend(s) connected (Prometheus, Loki, Tempo, Mimir, CloudWatch, others)?
   - Metrics, logs, or trace data driving the panels?
   - Naming conventions for metric / label / dashboard / folder?

2. **Audience and intent**
   - On-call triage, executive overview, capacity planning, or service health?
   - RED, USE, or hybrid framing appropriate?
   - Refresh cadence expectations (real-time, 1-min, 5-min)?

3. **Operational fit**
   - Variables (templating) needed for re-use across environments / tenants?
   - Annotations driven from deploy events or incident timelines?
   - Alerting rules paired with the panels?

---

## When to use

- Designing a new dashboard for a service, resource, or business KPI
- Reviewing an existing dashboard that nobody opens (signal: the dashboard is wrong)
- Refactoring a sprawling dashboard into something usable in an incident
- Setting up dashboard variables so one template covers many environments or services
- Provisioning dashboards from code (Terraform, Ansible, file provisioner) instead of clicking through the UI
- Wiring a dashboard alert that pages on-call

## Design lens

### Information hierarchy

A dashboard is read top-down in three bands.

```
Critical metrics             big numbers; must be visible without scrolling
Key trends                   time-series graphs; one per primary signal
Detailed metrics             tables, heatmaps; deep-dive surface
```

The first row exists for the on-call engineer who opened the dashboard at 3 AM. They get the green / yellow / red read in under five seconds, then drill into trends, then drop into tables.

### RED method (for services)

For any request-handling service:

- **Rate.** Requests per second.
- **Errors.** Errors per second (or as a percentage of rate).
- **Duration.** Latency distribution (p50, p95, p99 at minimum).

Three panels, top row, every service dashboard. Anything else is supplementary.

### USE method (for resources)

For any finite resource (CPU, memory, disk, queue, connection pool):

- **Utilisation.** Percent of time the resource is busy.
- **Saturation.** Queue length or wait time on the resource.
- **Errors.** Error count from the resource (timeouts, OOMs, full-queue rejections).

Pair RED at the service edge with USE at the resource layer; together they cover the "is the service healthy and is the underlying resource healthy" question without overlap.

### Panel type fits question

| Question shape | Panel type |
|---|---|
| What is the current value? | Stat |
| How is the value changing over time? | Time series |
| Compare current values across labelled series | Table |
| What is the latency distribution shape? | Heatmap |
| Where in this list is the outlier? | Bar gauge or table sorted descending |
| Is this resource healthy right now? | Stat with threshold colour |
| Year-over-year comparison? | Time series with shifted query |

Avoid: pie charts (humans cannot compare angles); 3D anything (visual noise); single-value gauges where a stat with threshold colour does the same job with less ink.

## Implementation patterns

### Dashboard skeleton (service overview)

```json
{
  "dashboard": {
    "title": "API Monitoring",
    "tags": ["api", "production"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[5m])) by (service)",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "Error Rate %",
        "type": "graph",
        "targets": [
          {
            "expr": "(sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))) * 100",
            "legendFormat": "Error Rate"
          }
        ],
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "P95 Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))",
            "legendFormat": "{{service}}"
          }
        ],
        "gridPos": {"x": 0, "y": 8, "w": 24, "h": 8}
      }
    ]
  }
}
```

Three RED panels. Request rate and error rate share the top row (h=8, w=12 each); p95 latency takes the second row full-width. Refresh is 30 s for a production dashboard; longer for capacity planning, shorter only in an active incident.

### Stat panel with threshold colour

```json
{
  "type": "stat",
  "title": "Error Rate %",
  "targets": [
    {"expr": "(sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))) * 100"}
  ],
  "options": {
    "reduceOptions": {"calcs": ["lastNotNull"]},
    "colorMode": "value"
  },
  "fieldConfig": {
    "defaults": {
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"value": 0,  "color": "green"},
          {"value": 1,  "color": "yellow"},
          {"value": 5,  "color": "red"}
        ]
      },
      "unit": "percent"
    }
  }
}
```

The thresholds and the unit are non-negotiable. Without unit, the panel reads "5" instead of "5%"; without thresholds, the colour is meaningless.

### Time series with multiple series

```json
{
  "type": "graph",
  "title": "CPU Usage by Instance",
  "targets": [
    {"expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"}
  ],
  "yaxes": [
    {"format": "percent", "max": 100, "min": 0},
    {"format": "short"}
  ]
}
```

Pin the y-axis range when the metric has a natural ceiling (percentage, rate, count). Otherwise auto-scale will hide the regression you are looking for.

### Table with transformation

```json
{
  "type": "table",
  "title": "Service Status",
  "targets": [
    {"expr": "up", "format": "table", "instant": true}
  ],
  "transformations": [
    {
      "id": "organize",
      "options": {
        "excludeByName": {"Time": true},
        "renameByName": {
          "instance": "Instance",
          "job": "Service",
          "Value": "Status"
        }
      }
    }
  ]
}
```

`instant: true` returns one snapshot value per series rather than a range. Transformations rename, reorder, and filter columns without changing the query.

### Heatmap (latency distribution)

```json
{
  "type": "heatmap",
  "title": "Latency Heatmap",
  "targets": [
    {"expr": "sum(rate(http_request_duration_seconds_bucket[5m])) by (le)", "format": "heatmap"}
  ],
  "dataFormat": "tsbuckets",
  "yAxis": {"format": "s"}
}
```

Heatmap shows distribution shape over time; percentile lines on a line graph show only summary statistics. Use both when latency matters.

## Variables

### Cascading query variables

```json
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_pod_info, namespace)",
        "refresh": 1,
        "multi": false
      },
      {
        "name": "service",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_service_info{namespace=\"$namespace\"}, service)",
        "refresh": 1,
        "multi": true
      }
    ]
  }
}
```

`namespace` populates from the cluster; `service` cascades off the selected namespace. `multi: true` on `service` lets the user compare two services side by side. `refresh: 1` reloads on dashboard load (use 2 for on-time-range-change if your label set is volatile).

Use in queries:

```
sum(rate(http_requests_total{namespace="$namespace", service=~"$service"}[5m]))
```

The `=~` regex match is required when `service` is multi-valued (Grafana joins selections with `|`).

## Alerts in dashboards

Dashboard alerts attach to a panel:

```json
{
  "alert": {
    "name": "High Error Rate",
    "conditions": [
      {
        "evaluator": {"params": [5], "type": "gt"},
        "operator": {"type": "and"},
        "query": {"params": ["A", "5m", "now"]},
        "reducer": {"type": "avg"},
        "type": "query"
      }
    ],
    "executionErrorState": "alerting",
    "for": "5m",
    "frequency": "1m",
    "message": "Error rate is above 5%",
    "noDataState": "no_data",
    "notifications": [{"uid": "slack-channel"}]
  }
}
```

Prefer the unified Grafana Alerting (post-8.x) over panel-attached legacy alerts for anything new; the panel-attached form above is the legacy path that still appears in older dashboards. Either way, route via `oncall-runbooks` so the alert payload includes the runbook URL.

## Dashboard provisioning

### File provisioner (`dashboards.yml`)

```yaml
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: General
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
```

Drop dashboard JSON files in `/etc/grafana/dashboards`; Grafana picks them up. `allowUiUpdates: true` permits in-UI tweaks to land in the same file (otherwise UI edits are ephemeral). `disableDeletion: true` stops a missing file from deleting the dashboard.

### Terraform

```hcl
resource "grafana_folder" "monitoring" {
  title = "Production Monitoring"
}

resource "grafana_dashboard" "api_monitoring" {
  config_json = file("${path.module}/dashboards/api-monitoring.json")
  folder      = grafana_folder.monitoring.id
}
```

### Ansible

```yaml
- name: Deploy Grafana dashboards
  copy:
    src: "{{ item }}"
    dest: /etc/grafana/dashboards/
  with_fileglob:
    - "dashboards/*.json"
  notify: restart grafana
```

## Pattern catalogue

### Service overview (RED)

Top row stats: request rate, error rate %, p95 latency. Second row time series of each. Third row table of error breakdown by status code. Variables: namespace, service.

### Infrastructure (USE)

Top row stats: CPU utilisation %, memory usage %, disk usage %, network bytes/sec. Second row time series of each per node. Third row table of pod count by namespace. Fourth row stat showing node count up vs total. Variables: cluster, namespace.

### Database

Top row: queries per second, connection pool usage %, p95 query latency. Second row: query latency p50 / p95 / p99 time series, slow query count time series. Third row: replication lag (one stat per replica), database size. Fourth row: top 10 slow queries table. Variables: database, instance.

### Application

Top row: request rate, error rate, response time percentiles. Second row: active users, active sessions, cache hit rate. Third row: queue length per worker. Variables: environment, service.

### Business KPI

Top row big-number stats: orders / hour, revenue / hour, signups / hour, churn / hour. Second row: trends over 24 h with same metrics. Third row: breakdown table (orders by region, revenue by tier). Refresh slower (5 m); these dashboards are read for trends, not for incidents.

## Best practices

1. Start with a community template and edit; do not start from blank.
2. Consistent naming for panels and variables across the team's dashboards.
3. Group related metrics in rows.
4. Default time range that matches reading cadence (last 6 h for live, last 30 d for capacity).
5. Use variables for any dimension that varies (env, service, region). One template beats ten clones.
6. Add panel descriptions for context that the title cannot carry.
7. Configure units (percent, seconds, bytes, requests/sec). Default "short" hides meaning.
8. Threshold colours mean something. Pick numbers that match the SLO.
9. Consistent colours across dashboards (red is bad, green is good, blue is informational).
10. Test with different time ranges before shipping. A query that works at "last 1 h" may explode at "last 7 d".

## Common pitfalls

- **Dashboard sprawl.** Hundreds of dashboards, none of them current. Curate ruthlessly; archive what nobody opens.
- **No variables.** One dashboard per service is unmaintainable; one templated dashboard with a service variable is.
- **Wrong panel type for the question.** Stat where a time series is needed (loses trend); time series where a heatmap is needed (loses distribution).
- **Defaults left as "short".** Numbers without units are guesses.
- **Alerts that page without a runbook URL in the payload.** On-call engineer is woken with no path to action.
- **Dashboard-as-code that drifts.** UI edits land, file does not. Either set `allowUiUpdates: false` and lock the source, or wire a webhook that exports back to file.
- **Dashboards that nobody owns.** Every dashboard needs a tag pointing to the owning team. Untagged dashboards become orphans.
- **PromQL recorded-query-name collisions.** Two dashboards reference `sli:http_availability:ratio` from different services without disambiguation; one displays the wrong service.
- **Refresh 5 s on a 200-target query.** Refresh interval times query cost equals load on Prometheus. Tune both.

## Advanced topics (references)

The core of this skill is dashboard design and provisioning. For deeper observability work, load the matching reference:

| Reference | Read when |
|---|---|
| `references/loki-tempo-correlation.md` | Wiring Loki (LogQL) and Tempo (TraceQL) as data sources and building logs / traces / metrics correlation (derived fields, exemplars, trace-to-logs). |
| `references/unified-alerting-and-git-sync.md` | Designing Grafana Unified Alerting (alert rules, contact points, notification policies, mute timings) or managing dashboards as code via Grafana 12.x Git Sync. |
| `references/mcp-observability-queries.md` | Querying Grafana programmatically via the Grafana MCP server (dashboards, Prometheus, Loki, alerting, incidents). |

## Cross-references

- `slo-implementation`: Stage 4 sibling. The SLO dashboard layout pattern lives there; this skill provides the panel-type discipline.
- `zabbix-templates-and-triage`: Stage 4 sibling. When Grafana visualises Zabbix data instead of Prometheus, query-language differs but design discipline is identical.
- `oncall-runbooks`: Page-routing references the dashboard URL on-call should open first; the runbook anchors panel descriptions.
- `systematic-debugging`: Phase 1 boundary evidence often comes off a dashboard panel; clean panel design accelerates triage.
- `secrets-hygiene`: Data-source credentials, Slack / Teams webhook UIDs, alert notification channels live in the secret store.
- `completion-gate` Layer 3: After deploy, verify the relevant panels show the expected change (request volume drop or rise, latency band shift, new error class appearing).
- `plan-time-tooling`: Schema-affecting changes that break label cardinality fire engineering:architecture; production data-source changes fire engineering:deploy-checklist.
- `bash-defensive`: When dashboards are deployed by shell scripts (file provisioner, jsonnet build, dashboard-as-code CI), the same defensive idioms apply.

## Red flags

- About to ship a dashboard with no variables (one-environment-only).
- About to use a stat panel for a metric that needs trend context.
- About to leave panels with default "short" unit.
- About to wire an alert with no runbook URL in the message body.
- About to duplicate a dashboard "for staging" instead of templating with environment as a variable.
- About to use 5-second refresh on a dashboard with 100+ targets.
- About to use a pie chart, a 3D bar, or any other low-data-density panel.
- About to commit dashboard JSON with hardcoded data-source UIDs (use variables or template the UID at provision time).
- About to leave `disableDeletion: false` on a critical-incident dashboard (one accidental file rename and the dashboard vanishes).
- About to ship without testing at the longest reasonable time range.

## Bottom line

Information hierarchy, RED for services, USE for resources, panel-type-fits-question. Variables instead of clones. Dashboards as code, not as click-history. The dashboard exists for the on-call engineer at 3 AM; design accordingly.
