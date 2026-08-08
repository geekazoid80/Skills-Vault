# Grafana MCP Server for Observability Queries

Reference for using the [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana) MCP server to query dashboards, Prometheus metrics, Loki logs, Tempo traces, and alert rules programmatically from an AI agent session.

---

## MCP Server Overview

| Property | Value |
|---|---|
| Source | [grafana/mcp-grafana](https://github.com/grafana/mcp-grafana) |
| Transport | stdio (default), SSE, streamable-http |
| Language | Go (run via `uvx mcp-grafana`) |
| Tools available | 75+ (dashboards, Prometheus, Loki, alerting, incidents, OnCall, annotations) |
| Auth | Service account token (preferred) or username/password |
| Requires | Grafana 9.0+; service account with Editor role or equivalent RBAC |

### Running the server

```bash
# stdio mode
uvx mcp-grafana

# Read-only mode (disables dashboard/alert write tools)
uvx mcp-grafana --disable-write
```

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `GRAFANA_URL` | Yes | Grafana instance URL, e.g. `http://grafana.example.com:3000` |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Yes* | Service account token (preferred over basic auth) |
| `GRAFANA_USERNAME` | Alt | Basic auth username (alternative to token) |
| `GRAFANA_PASSWORD` | Alt | Basic auth password |
| `GRAFANA_ORG_ID` | No | Organisation ID for multi-org Grafana instances |

*Token or username/password is required; token is preferred because it supports fine-grained RBAC.

Use `--disable-write` in any environment where the agent should not be permitted to modify dashboards or alert rules.

---

## Tool Reference by Category

### Dashboard operations

| Tool | What it does |
|---|---|
| `search_dashboards` | Find dashboards by title or metadata |
| `get_dashboard_summary` | Lightweight overview (panel list, variable list); use this before fetching full JSON |
| `get_dashboard_by_uid` | Full dashboard JSON; large payload, use sparingly |
| `get_dashboard_property` | Extract a specific field via JSONPath without loading the full document |
| `get_dashboard_panel_queries` | Extract panel query definitions only |
| `update_dashboard` | Create or replace a dashboard |
| `patch_dashboard` | Targeted modification without a full JSON replacement |

Always start with `get_dashboard_summary`. It returns enough context to identify relevant panels without the token cost of the full JSON.

### Prometheus (PromQL)

| Tool | What it does |
|---|---|
| `query_prometheus` | Execute instant or range PromQL queries |
| `list_prometheus_metric_names` | Discover available metrics |
| `list_prometheus_label_names` | List label names matching a selector |
| `list_prometheus_label_values` | List values for a specific label |
| `query_prometheus_histogram` | Calculate percentile values (p50, p90, p95, p99) |
| `list_prometheus_metric_metadata` | Metric type, help text, unit |

### Loki (LogQL)

| Tool | What it does |
|---|---|
| `query_loki_logs` | Execute LogQL queries against log streams |
| `list_loki_label_names` | Discover available log labels |
| `list_loki_label_values` | List values for a specific log label |
| `query_loki_stats` | Stream statistics: volume and rate |
| `query_loki_patterns` | Detect recurring log structure patterns |

### Alerting

| Tool | What it does |
|---|---|
| `list_alert_rules` | List all Grafana-managed and data-source-managed alert rules |
| `get_alert_rule_by_uid` | Retrieve a specific rule's definition, thresholds, and conditions |
| `create_alert_rule` | Create a new alert rule |
| `update_alert_rule` | Modify an existing alert rule |
| `delete_alert_rule` | Remove an alert rule |
| `list_contact_points` | List configured notification endpoints |

### Incident management

| Tool | What it does |
|---|---|
| `list_incidents` | List Grafana Incidents with filtering by status and labels |
| `get_incident` | Retrieve details for a single incident |
| `create_incident` | Open a new incident |
| `add_activity_to_incident` | Append a timeline entry to an open incident |

### OnCall

| Tool | What it does |
|---|---|
| `list_oncall_schedules` | View on-call rotation schedules |
| `get_oncall_shift` | Details for a specific shift |
| `get_current_oncall_users` | Who is on call right now |
| `list_alert_groups` | OnCall alert groups with filtering |

### Annotations and rendering

| Tool | What it does |
|---|---|
| `get_annotations` | Query annotations with time range and tag filters |
| `create_annotation` | Add an annotation to a dashboard or panel |
| `get_panel_image` | Render a panel as a PNG image |
| `generate_deeplink` | Create a Grafana URL for sharing a specific view |

### Sift investigation tools

| Tool | What it does |
|---|---|
| `list_sift_investigations` | List automated Sift investigations |
| `get_sift_investigation` | Details for a specific investigation |
| `find_error_pattern_logs` | Detect elevated error patterns across log streams |
| `find_slow_requests` | Identify slow requests via Tempo traces |

---

## Typical Investigation Workflows

### Alert investigation

```
list_alert_rules(folder="Production")
  --> get_alert_rule_by_uid(uid="<firing-rule>")
  --> query_prometheus(expr="<the rule's query>", time_range="1h")
  --> query_loki_logs(query="{service='<svc>'} |= 'error'", time_range="1h")
  --> list_incidents()   # check if already tracked
```

### Dashboard metric lookup

```
search_dashboards(title="Network Interfaces")
  --> get_dashboard_summary(uid="<uid>")
  --> get_dashboard_panel_queries(uid="<uid>")
  --> query_prometheus(expr="<extracted query>", time_range="30m")
```

### Log analysis

```
list_loki_label_names()
  --> list_loki_label_values(label="host")
  --> query_loki_logs(query="{host='core-rtr-01'} |= 'error'", time_range="1h")
  --> query_loki_patterns(query="{job='syslog'}")
  --> query_loki_stats(query="{job='syslog', host='core-rtr-01'}")
```

### Incident response

```
list_incidents(status="open")
  --> get_incident(id="<id>")
  --> get_current_oncall_users()
  --> query_prometheus(expr="<affected service metrics>")
  --> find_error_pattern_logs(service="<svc>", time_range="1h")
  --> add_activity_to_incident(id="<id>", note="<findings>")
  --> create_annotation(dashboardUid="<uid>", text="Incident INC-123 opened")
```

---

## Context-Window Management

Grafana dashboard JSON documents can be large (hundreds of kilobytes for complex dashboards). Apply these strategies to stay within token budgets:

1. Always start with `get_dashboard_summary`: returns panel names and variable list, not full JSON.
2. Use `get_dashboard_property` with a JSONPath expression to extract only the field needed.
3. Use `get_dashboard_panel_queries` to extract query definitions without fetching panel layout and styling.
4. Reserve `get_dashboard_by_uid` for cases where the full JSON is genuinely required (e.g., patching a specific panel configuration).
5. Scope Prometheus and Loki queries with narrow time ranges. A 15-minute window is usually sufficient for active investigation; use longer ranges only for trend analysis.

---

## Error Handling

| Error | Likely cause | Resolution |
|---|---|---|
| 401 / 403 | Invalid or expired token; insufficient RBAC permissions | Verify `GRAFANA_SERVICE_ACCOUNT_TOKEN`; confirm the service account has the required role |
| Datasource not found | UID or name mismatch | Run `list_datasources` to discover current UIDs |
| PromQL parse error | Invalid metric or label name | Run `list_prometheus_metric_names` or `list_prometheus_label_names` before constructing the query |
| LogQL parse error | Label or filter syntax error | Run `list_loki_label_names` to confirm available labels |
| Dashboard not found | UID stale or title changed | Run `search_dashboards` to re-discover the current UID |
| Rate limiting (429) | Too many concurrent requests | Space out large query batches; avoid querying all panels simultaneously |

---

## Security Notes

- Use a service account token scoped to the minimum required permissions. Read-only investigations need only Viewer role; dashboard modifications require Editor.
- Pass `--disable-write` when the agent session should not be permitted to modify Grafana state.
- Never embed credentials or sensitive values inside PromQL or LogQL expressions. Label values are logged by Grafana and may appear in Loki streams.
- Rotate service account tokens on a scheduled basis; store them in a secrets manager rather than in environment files on disk.
