# Grafana Unified Alerting and Git Sync

Reference for the Grafana Unified Alerting model (mandatory since v10) and the Grafana 12.x Git Sync feature for dashboards-as-code workflows.

---

## Unified Alerting Overview

Grafana Unified Alerting (also called Grafana Alerting) replaces the legacy dashboard-panel alerts with a centralised, multi-dimensional alerting engine modelled on Prometheus Alertmanager. It has been the only alerting path since Grafana 10.

The five core concepts are:

| Concept | Role |
|---|---|
| **Alert rules** | Define what to evaluate, when, and under what condition |
| **Contact points** | Define where and how to send notifications |
| **Notification policies** | Route alert instances to contact points using label matching |
| **Mute timings** | Recurring scheduled suppression windows |
| **Silences** | One-time, label-matched notification suppression |

---

## Alert Rules

Alert rules are organised into **rule groups** inside **folders**. The folder replaces the legacy dashboard-scoped alert.

### Rule definition fields

| Field | Description |
|---|---|
| Name | Human-readable rule name |
| Folder | Organisational folder; maps to RBAC namespace |
| Group | Rule group name; all rules in a group share the same evaluation interval |
| Evaluation interval | How often the rule evaluates (e.g., `1m`) |
| Pending period | How long the condition must hold before the alert transitions to Firing (the Prometheus `for` equivalent) |
| Condition | The query ref (A, B, C...) whose result is tested against the threshold |
| Annotations | Free-form key-value pairs: `summary`, `description`, `runbook_url` |
| Labels | Key-value pairs for routing and grouping: `severity`, `team`, `env` |

### Grafana-managed vs data-source-managed rules

**Grafana-managed rules** are evaluated by the Grafana alerting backend. They can query any configured data source. The evaluation state is stored in the Grafana database.

**Data-source-managed rules** are pushed to a Prometheus-compatible ruler (Mimir, Cortex, Thanos Ruler) and evaluated there. They appear read-only in the Grafana UI. Prefer this approach when alert evaluation load needs to scale independently of the Grafana server.

### Multi-dimensional alerting

A single rule produces one alert instance per unique label set returned by the query. Each instance is tracked independently. A rule over `{service=~".+"}` produces one Firing instance per service value. Notification policies receive each instance with its full label set.

### Provisioning alert rules as code

```yaml
# provisioning/alerting/rules.yaml
apiVersion: 1
groups:
  - orgId: 1
    name: service-slos
    folder: SLOs
    interval: 1m
    rules:
      - uid: error-rate-high
        title: "Error Rate > 5%"
        condition: C
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "Error rate exceeds 5% for {{ $labels.service }}"
          runbook_url: "https://runbooks.example.com/error-rate"
        noDataState: NoData
        execErrState: Alerting
        data:
          - refId: A
            datasourceUid: prometheus-uid
            model:
              expr: >-
                sum(rate(http_requests_total{status=~"5.."}[5m]))
                / sum(rate(http_requests_total[5m]))
          - refId: C
            datasourceUid: "__expr__"
            model:
              type: threshold
              conditions:
                - evaluator:
                    params: [0.05]
                    type: gt
                  query:
                    params: [A]
```

Contact points, notification policies, mute timings, and templates are provisioned in separate YAML files under `provisioning/alerting/`.

---

## Alert State Lifecycle

```
Normal
  |-- (condition met) --> Pending
                              |-- (pending period elapsed) --> Firing
                              |-- (condition clears)       --> Normal
Firing
  |-- (condition clears + keep-firing elapsed) --> Recovering --> Normal

Any state
  |-- (no data returned) --> NoData   (behaviour configurable)
  |-- (query fails)      --> Error    (behaviour configurable)
```

| State | Meaning |
|---|---|
| Normal | Condition not met |
| Pending | Condition met; pending period not yet elapsed |
| Firing | Condition held for the full pending period; notifications sent |
| Recovering | Condition cleared; optional keep-firing window still counting down |
| NoData | Query returned no data; set `noDataState` to `Normal`, `Alerting`, or `KeepLastState` |
| Error | Query execution failed; set `execErrState` to `Alerting`, `OK`, or `KeepLastState` |

Configure `noDataState` and `execErrState` explicitly on every rule. Leaving them at the default (`Alerting`) causes false pages when Prometheus restarts or a scrape target is briefly unreachable.

---

## Contact Points

Contact points define notification delivery. Each contact point can carry multiple integrations; all integrations in the point are notified simultaneously when an alert routes to it.

| Integration | Notes |
|---|---|
| Email | SMTP; subject and body support Go templates |
| Slack | Webhook or OAuth app; message layout customisable via Go templates |
| PagerDuty | Events API v2; severity maps from alert labels |
| Microsoft Teams | Incoming webhook; adaptive card format |
| Webhook | Generic HTTP POST; configurable auth, headers, payload template |
| OpsGenie | Alerts API; priority maps from labels |
| Telegram | Bot API |
| Alertmanager | Forward to an external Alertmanager for federation |
| Kafka | Publish alert events via REST Proxy |
| Google Chat | Webhook |

### Go templates in contact points

All notification message fields accept Go `{{ }}` syntax. Custom templates are defined under Alerting > Contact points > Templates and referenced by name.

```
{{ define "slack.title" }}
[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }} - {{ .CommonLabels.service }}
{{ end }}

{{ define "slack.body" }}
*Summary*: {{ .CommonAnnotations.summary }}
*Runbook*: {{ .CommonAnnotations.runbook_url }}
*Severity*: {{ .CommonLabels.severity }}
{{ end }}
```

Built-in variables include `.Status`, `.Labels`, `.Annotations`, `.StartsAt`, `.EndsAt`, `.GeneratorURL`.

### Provisioning contact points

```yaml
# provisioning/alerting/contact-points.yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: Platform Slack
    receivers:
      - uid: platform-slack-uid
        type: slack
        settings:
          url: "${SLACK_WEBHOOK_URL}"
          channel: "#platform-alerts"
          title: '{{ template "slack.title" . }}'
          text: '{{ template "slack.body" . }}'
```

Use environment variable substitution (`${ENV_VAR}`) for webhook URLs and API keys. Never commit credentials into the provisioning files.

---

## Notification Policies

Notification policies form a **routing tree**. Grafana evaluates the tree top-down; the first matching child policy wins (unless `continue: true` is set).

### Policy fields

| Field | Description |
|---|---|
| Contact point | Where to send matching alerts |
| Label matchers | `key=value`, `key=~regex`, `key!=value` applied to alert labels |
| Continue | If `true`, keep evaluating sibling policies after this one matches |
| Group by | Labels used to batch alert instances into one notification |
| Group wait | Delay before sending the first notification for a new group (default 30 s) |
| Group interval | Minimum interval between updates for an existing group (default 5 m) |
| Repeat interval | Re-send interval when a group is still firing with no new changes (default 4 h) |
| Mute timings | References to named mute timings that suppress notifications on a schedule |

### Routing tree example

```
Root policy
  contact: default-email     (catch-all for unmatched alerts)
  |
  |-- severity=critical
  |     contact: pagerduty-prod
  |     group_by: [alertname, service]
  |     continue: false
  |
  |-- team=platform
  |     contact: slack-platform
  |     group_by: [alertname]
  |
  └-- env=staging
        contact: slack-staging
        mute_timings: [weekends]
```

### Provisioning notification policies

```yaml
# provisioning/alerting/notification-policies.yaml
apiVersion: 1
policies:
  - orgId: 1
    receiver: default-email
    group_by: [alertname]
    routes:
      - receiver: pagerduty-prod
        matchers:
          - severity=critical
        group_by: [alertname, service]
        continue: false
      - receiver: slack-platform
        matchers:
          - team=platform
      - receiver: slack-staging
        matchers:
          - env=staging
        mute_time_intervals:
          - weekends
```

---

## Mute Timings

Mute timings are reusable, recurring suppression schedules. They are attached to notification policies, not individual alert rules.

### When to use mute timings vs silences

Use **mute timings** for recurring windows: maintenance nights, weekend on-call blackouts, scheduled downtime slots. The schedule is defined once and referenced by any number of policies.

Use **silences** for one-off suppression: a known bad deployment, a manual maintenance window, a ticket-in-progress situation. Silences match by alert labels and expire automatically.

The critical distinction: mute timings are **not inherited** from parent notification policies. If the root policy has a mute timing, child policies are not automatically suppressed during that window. Configure mute timings explicitly on each policy level that needs suppression.

### Provisioning mute timings

```yaml
# provisioning/alerting/mute-timings.yaml
apiVersion: 1
muteTimes:
  - orgId: 1
    name: weekends
    time_intervals:
      - weekdays: [saturday, sunday]
  - orgId: 1
    name: maintenance-window
    time_intervals:
      - times:
          - start_time: "02:00"
            end_time: "04:00"
        weekdays: [monday:friday]
```

Time intervals support: `times` (HH:MM ranges), `weekdays` (day names or ranges), `days_of_month` (1-31), `months` (1-12 or name ranges), `years` (YYYY ranges).

### Active time intervals (Grafana 12)

Active time intervals are the inverse of mute timings: they define when a notification policy is active, rather than when it is suppressed. Useful for routing alerts to different contact points based on working hours.

---

## Alerting Best Practices

- Set `for` (pending period) on every rule: minimum 1 m for critical, 5 m for warning. This prevents transient spikes from generating noise.
- Use labels (`severity`, `team`, `env`) on rules, not in annotations. Labels drive routing; annotations carry human-readable context.
- Include `runbook_url` in every rule annotation. On-call engineers should never receive an alert without a path to action.
- Test every rule before deploying: use the "Test rule" button in the alert rule editor to confirm the query evaluates correctly.
- Configure `noDataState` and `execErrState` explicitly. Defaults vary between versions and can cause unexpected behaviour.
- Use data-source-managed rules (Mimir/Cortex ruler) for high-volume rule sets. Offloading evaluation reduces Grafana server load.
- Provision everything as code. Manual alert rules created in the UI are fragile, not version-controlled, and hard to audit.

---

## Git Sync (Grafana 12 Dashboards-as-Code)

Git Sync is a native Grafana 12 feature for bidirectional synchronisation between Grafana dashboards and a Git repository. It is experimental for self-hosted instances and in public preview on Grafana Cloud (available from early 2026).

### How it works

- A Git repository (GitHub, GitLab, Gitea, Azure DevOps) is connected to a Grafana instance via a branch name and credentials.
- Dashboard JSON files committed to the configured branch are pulled into Grafana automatically.
- Changes made in the Grafana UI are committed back to the repository.
- Grafana 12.4 introduced GitHub App authentication as a more secure alternative to personal access tokens.

### Dashboard JSON schema v2

Git Sync introduces support for dashboard JSON schema v2 (public preview in Grafana 12). Schema v2 is a typed, versioned schema with formal kind definitions. It enables:

- Validation against a published schema (IDE support, CI linting).
- Structured diffing of dashboard changes in pull requests.
- Cleaner JSON output compared to the legacy ad-hoc v1 model.

Schema v2 is backward compatible; v1 dashboards continue to work and can be migrated incrementally.

### Typical Git Sync workflow

1. Enable Git Sync in Grafana administration settings. Configure the repository URL, branch, and credentials (service account token or GitHub App).
2. Push a dashboard JSON file to the configured branch:

```bash
git add dashboards/service-overview.json
git commit -m "feat: add service overview dashboard"
git push origin main
```

3. Grafana pulls the file within the configured sync interval (default 10 s).
4. When an engineer edits the dashboard in the Grafana UI, the change is committed back to the branch with a system-generated commit message.
5. For teams wanting review gates, branch protection rules on the Git repository enforce pull request review before changes merge to the watched branch.

### Configuring Git Sync (grafana.ini)

```ini
[git_sync]
enabled = true
repository_url = https://github.com/your-org/grafana-dashboards
branch = main
token = ${GIT_SYNC_TOKEN}
```

Environment variable substitution applies; never hardcode tokens in `grafana.ini`.

### Comparison of dashboards-as-code approaches

| Approach | Bidirectional | Review workflow | Grafana version |
|---|---|---|---|
| File provisioner (YAML provider) | No (file to Grafana only) | External CI on the repo | All |
| Terraform provider | No (Terraform to Grafana only) | Terraform plan/apply in CI | All |
| Kubernetes Operator (CRDs) | No (CRD to Grafana only) | GitOps via ArgoCD/Flux | All |
| Git Sync | Yes (Grafana UI to Git, Git to Grafana) | Branch protection on the Git repo | 12.x |

Git Sync is the only approach that captures UI edits back to Git automatically. For teams where dashboard authors prefer the Grafana UI, Git Sync prevents drift between the source repository and the live instance. For teams that treat dashboards as pure code artefacts, the file provisioner or Terraform provider remains simpler to reason about.

### Pitfalls and constraints

- Git Sync currently covers dashboards and folder structures only. Alert rules, data source definitions, and contact points are not yet synced (roadmap item).
- If both the UI and the Git repo are modified concurrently, Git Sync applies a last-write-wins merge. For collaborative teams, short-lived feature branches with PR review are recommended to avoid conflicts.
- The `allowUiUpdates: false` setting in the file provisioner is incompatible with Git Sync. Remove the provisioner or set `allowUiUpdates: true` before enabling Git Sync on the same folder.
- Git Sync is marked experimental on self-hosted Grafana 12. Test thoroughly before enabling in production; watch Grafana release notes for stability status changes.
