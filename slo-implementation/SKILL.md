---
name: slo-implementation
description: "Use for any SLI / SLO / error-budget design or review work. Vendor-neutral; PromQL-first because Prometheus is the canonical SLO engine, but the discipline applies to any time-series backend (Datadog, New Relic, CloudWatch, VictoriaMetrics). Triggers include 'define an SLO', 'set a reliability target', 'service availability target', 'error budget policy', 'burn-rate alert', 'multi-window alerting', 'SLO compliance dashboard', 'SLI for latency / availability / durability', 'reliability vs feature velocity tradeoff', 'page on error budget burn', 'review this alert rule', 'fast burn vs slow burn'. Includes the SLI/SLO/SLA hierarchy, an availability-percentage to downtime table, PromQL templates for the three common SLI types (availability, latency, durability), Prometheus recording-rule + alerting-rule scaffolds, the multi-window multi-burn-rate (MWMBR) alerting pattern that catches fast burns without firing on benign noise, and an error-budget policy ladder (100 / 50 / 10 / 0 percent remaining). Customised from wshobson/agents/plugins/observability-monitoring/skills/slo-implementation (MIT). Pairs with oncall-runbooks (page-routing + incident classification), systematic-debugging (Phase 1 boundary evidence at burn-rate spikes), and grafana-dashboards (visualisation surface)."
license: MIT
metadata:
  version: "1.0.0"
---

# SLO Implementation

Framework for defining and operating Service Level Indicators (SLIs), Service Level Objectives (SLOs), and error budgets. Vendor-neutral methodology; PromQL examples because Prometheus is the canonical SLO engine.

> **Skill marker**: When applying this skill, begin your reply with `[skill: slo-implementation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the service catalogue, existing SLI definitions, observability backend, and any product-level reliability commitments before drafting SLOs. Only ask the user for information not already covered or specific to this service.

Before drafting, understand:

1. **Service in scope**
   - Customer-facing or internal? Multi-tenant?
   - Critical user journey(s) the SLI should measure?
   - Existing reliability commitments (SLA terms in customer contracts, internal targets)?

2. **Measurement substrate**
   - Metrics backend (Prometheus, Mimir, Cortex, vendor)?
   - Tracing backend if request-latency SLIs are in scope?
   - Synthetic checks or real-user monitoring available?

3. **Error budget policy**
   - Audience for the SLO report (team, product, executive)?
   - Burn-rate alert posture and paging policy?
   - Budget exhaustion response (feature freeze, retrospective, post-mortem trigger)?

---

## When to use

- Establishing reliability targets for a service for the first time
- Reviewing or adjusting an existing SLO that is consistently met or consistently missed
- Wiring up burn-rate alerts that page on real degradation, not on noise
- Implementing an error-budget policy that gates feature work against reliability work
- Building an SLO dashboard for the team or for a customer-facing status page
- Negotiating an SLA externally (the SLA tracks SLO with a comfort margin)

## SLI / SLO / SLA hierarchy

```
SLA  Service Level Agreement      external contract; financial / contractual consequences
 |
SLO  Service Level Objective      internal target; the team is on the hook
 |
SLI  Service Level Indicator      the actual measurement
```

SLA is what you promise the customer. SLO is what you target internally (always set tighter than the SLA so the comfort margin absorbs noise). SLI is the live number coming off your time-series backend.

## Defining SLIs

Three SLI shapes cover most user-facing services. Pick the ones that map to user-perceived reliability for the specific service.

### Availability SLI

Successful requests divided by total requests, over a rolling window.

```promql
sum(rate(http_requests_total{status!~"5.."}[28d]))
/
sum(rate(http_requests_total[28d]))
```

The exclusion pattern `status!~"5.."` treats 5xx responses as failures and 4xx as user error (not the service's fault). Adjust if your domain treats certain 4xx codes as service failures (e.g. 429 from a misconfigured rate limiter).

### Latency SLI

Fraction of requests served below a latency budget.

```promql
sum(rate(http_request_duration_seconds_bucket{le="0.5"}[28d]))
/
sum(rate(http_request_duration_seconds_count[28d]))
```

The `le="0.5"` bucket boundary must exist in your histogram definition. If you only have `le="0.25"` and `le="1.0"`, either re-bucket (which loses retroactive data) or accept the next-largest bucket as the budget.

### Durability SLI

Successful writes divided by total writes (for storage, queue, or stateful services).

```promql
sum(rate(storage_writes_successful_total[28d]))
/
sum(rate(storage_writes_total[28d]))
```

## Setting SLO targets

### Availability percentage to downtime

| SLO   | Downtime / month | Downtime / year |
|-------|------------------|-----------------|
| 99%   | 7.2 hours        | 3.65 days       |
| 99.5% | 3.6 hours        | 1.83 days       |
| 99.9% | 43.2 minutes     | 8.76 hours      |
| 99.95%| 21.6 minutes     | 4.38 hours      |
| 99.99%| 4.32 minutes     | 52.56 minutes   |

### Choosing the target

- **User expectation.** What level of reliability does the user actually need? An internal admin tool is fine at 99%; a payment gateway is not.
- **Current performance.** If you are operating at 99.93% today, a 99.99% target is aspirational and will burn the team out chasing the last nine.
- **Cost of reliability.** Each additional nine roughly doubles infrastructure + engineering cost.
- **Competitor benchmarks.** If competitors publish 99.9%, customers will compare.
- **Do not aim for 100%.** Zero error budget means zero room to deploy.

### Example target file

```yaml
slos:
  - name: api_availability
    target: 99.9
    window: 28d
    sli: |
      sum(rate(http_requests_total{status!~"5.."}[28d]))
      /
      sum(rate(http_requests_total[28d]))

  - name: api_latency_p95_500ms
    target: 99
    window: 28d
    sli: |
      sum(rate(http_request_duration_seconds_bucket{le="0.5"}[28d]))
      /
      sum(rate(http_request_duration_seconds_count[28d]))
```

## Error budget

### Formula

```
Error Budget = 1 - SLO Target
```

Worked example for 99.9% availability over 28 days:

- Error budget: 0.1% = 40.32 minutes / 28 days
- Spent so far this window: 0.05% = 20.16 minutes
- Remaining: 50%

### Error budget policy ladder

```yaml
error_budget_policy:
  - remaining_budget: 100%
    posture: Normal
    action: Ship features at full velocity
  - remaining_budget: 50%
    posture: Watch
    action: Defer risky changes (DB migrations, fanout changes, dependency bumps)
  - remaining_budget: 10%
    posture: Caution
    action: Freeze non-critical changes; reliability work jumps the queue
  - remaining_budget: 0%
    posture: Frozen
    action: Feature freeze; reliability work only until budget recovers
```

The policy ladder is the leverage point. Without an enforced ladder, an SLO is just a number on a dashboard.

## Implementation

### Recording rules (PromQL)

Compute SLIs as recording rules so dashboards and alerts read pre-computed series.

```yaml
groups:
  - name: sli_rules
    interval: 30s
    rules:
      - record: sli:http_availability:ratio
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[28d]))
          /
          sum(rate(http_requests_total[28d]))

      - record: sli:http_latency:ratio
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.5"}[28d]))
          /
          sum(rate(http_request_duration_seconds_count[28d]))

  - name: slo_rules
    interval: 5m
    rules:
      - record: slo:http_availability:compliance
        expr: sli:http_availability:ratio >= bool 0.999

      - record: slo:http_availability:error_budget_remaining
        expr: |
          (sli:http_availability:ratio - 0.999) / (1 - 0.999) * 100

      # Burn rate at 5-minute window
      - record: slo:http_availability:burn_rate_5m
        expr: |
          (1 - (
            sum(rate(http_requests_total{status!~"5.."}[5m]))
            /
            sum(rate(http_requests_total[5m]))
          )) / (1 - 0.999)
```

### Multi-window multi-burn-rate (MWMBR) alerts

Single-window burn-rate alerts either fire too often (short window) or too late (long window). Pair a short-window and a long-window check so both must agree before paging.

```yaml
groups:
  - name: slo_alerts
    interval: 1m
    rules:
      # Fast burn: 14.4x rate consumes 2% of monthly budget in 1 hour
      - alert: SLOErrorBudgetBurnFast
        expr: |
          slo:http_availability:burn_rate_1h > 14.4
          and
          slo:http_availability:burn_rate_5m > 14.4
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: Fast error budget burn detected
          description: "Burn rate {{ $value }}x; will exhaust monthly budget in ~2 days"

      # Slow burn: 6x rate consumes 5% of monthly budget in 6 hours
      - alert: SLOErrorBudgetBurnSlow
        expr: |
          slo:http_availability:burn_rate_6h > 6
          and
          slo:http_availability:burn_rate_30m > 6
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: Slow error budget burn detected
          description: "Burn rate {{ $value }}x; degradation persists"

      - alert: SLOErrorBudgetExhausted
        expr: slo:http_availability:error_budget_remaining < 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: SLO error budget exhausted
          description: "Remaining: {{ $value }}%; trigger error-budget-policy actions"
```

The 14.4x / 6x multipliers come from Google's SRE workbook; tune for your traffic shape if needed. The pair-of-windows construction is the key, not the exact multiplier.

## Dashboard surface

Dashboard layout pattern (see `grafana-dashboards` for the panel-type discipline):

```
SLO Compliance (current)
  99.95% (target 99.9%)            green / yellow / red status

Error Budget Remaining
  65%                              progress bar; red below 10%

SLI Trend (28d)
  time series                      one line per SLI; threshold band overlay

Burn Rate
  table                            burn rate by window: 5m / 30m / 1h / 6h
```

Useful PromQL for the burn-rate panel:

```promql
# Days until budget exhausted at current burn rate
(slo:http_availability:error_budget_remaining / 100)
*
28
/
(1 - sli:http_availability:ratio) * (1 - 0.999)
```

## Operational cadence

| Cadence    | Focus |
|------------|-------|
| Weekly     | Compliance status, budget remaining, trend deltas, incident hits this week |
| Monthly    | Achievement against target, postmortem follow-ups, target adjustments |
| Quarterly  | SLO relevance check (still measuring the right thing?), tooling, business alignment |

Pair with `oncall-runbooks` so the on-call shift starts each week with the SLO snapshot in front of them, not after they get paged.

## Best practices

1. Start with user-facing services. Internal services come second.
2. Use multiple SLIs per service (availability + latency at minimum).
3. Set achievable targets. 99% is a fine SLO; 100% is a misconfiguration.
4. Use multi-window burn-rate alerts (MWMBR) to suppress noise.
5. Enforce the error-budget policy. An SLO without a policy ladder is a vanity metric.
6. Review monthly; adjust quarterly. Do not change targets weekly.
7. Document SLO decisions in an ADR so the next person knows why 99.9% and not 99.99%.
8. Align SLOs to business risk, not to vendor defaults.
9. Automate SLO reporting. Manual reports decay.
10. Use SLOs to prioritise. The error-budget posture is the input to the sprint planning conversation.

## Cross-references

- `oncall-runbooks`: page routing for the burn-rate alerts; on-call rotation reads SLO state at shift handover.
- `systematic-debugging`: Phase 1 boundary evidence when a burn alert fires; isolate the failing dependency before declaring scope.
- `grafana-dashboards`: panel-type discipline + RED/USE method for the SLO surface.
- `completion-gate` Layer 3: post-deploy verification includes "did the deploy push us further into burn?"
- `plan-time-tooling`: SLO-affecting changes (new dependency, new write path, new region) fire engineering:architecture; deploys touching critical-path services fire engineering:deploy-checklist.
- `forward-compatible-schemas`: schema migrations are the most common cause of slow-burn incidents; coordinate with this skill before shipping.

## Red flags

- About to set an SLO above the current measured baseline. Aspirational targets exhaust budget within days.
- About to wire a single-window burn-rate alert. It will either flap or miss.
- About to define an SLI that is not user-perceived (e.g. CPU utilisation as the only SLI). User-perceived metrics only.
- About to set the SLO equal to the SLA. The SLO must be tighter than the SLA so noise does not breach the contract.
- About to remove an SLO because it is "always green". Always-green SLOs mean the target is too loose, not that the SLO is wrong.
- About to ship a feature in a Frozen-budget posture without explicit user approval to override the policy.

## Bottom line

SLO is a number; the policy ladder is the leverage. Define SLIs that the user feels, set targets the team can sustain, alert on burn rate not raw thresholds, and let the budget posture drive the feature-vs-reliability conversation. The hardest part is enforcing the policy when sales is pushing for the next ship.
