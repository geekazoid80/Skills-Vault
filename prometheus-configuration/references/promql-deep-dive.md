# PromQL Deep Dive

PromQL (Prometheus Query Language) is the expression language for selecting and aggregating time-series data stored in Prometheus. This reference covers the type system, selector syntax, rate functions, aggregation, binary operations, histograms (classic and native), subqueries, and practical query recipes.

## Data Types

PromQL evaluates to one of four types:

| Type | Description | Typical use |
|------|-------------|-------------|
| Instant vector | Set of time series, each with one sample at the evaluation timestamp | Aggregation input, alerting expressions |
| Range vector | Set of time series, each with a window of samples | Input to `rate()`, `avg_over_time()`, etc. |
| Scalar | Single floating-point number | Arithmetic operands, `scalar()` output |
| String | String value | Limited use; mostly `label_replace` replacement strings |

Most operators and functions consume and produce instant vectors. Range vectors are an intermediate form: you cannot display them directly; you pass them to a function that returns an instant vector.

## Selectors and Matchers

**Bare metric name** selects all time series with that name:

```promql
http_requests_total
```

**Label matchers** narrow the selection:

```promql
http_requests_total{job="api", status=~"5.."}
http_requests_total{job!="batch", method="GET"}
http_requests_total{handler!~"/health|/ready"}
```

Matcher operators:

| Operator | Semantics |
|----------|-----------|
| `=` | Exact match |
| `!=` | Not equal |
| `=~` | RE2 regex match (anchored at both ends) |
| `!~` | RE2 regex not-match |

A selector with only label matchers and no metric name is valid and matches across all metrics:

```promql
{job="node-exporter", __name__=~"node_cpu.*"}
```

**Range selector** appends a duration to produce a range vector:

```promql
http_requests_total{job="api"}[5m]
```

**Offset modifier** shifts the evaluation window into the past:

```promql
rate(http_requests_total[5m] offset 1h)
```

**@ modifier** evaluates at a fixed Unix timestamp or relative anchor:

```promql
http_requests_total @ 1609459200        # fixed Unix timestamp (2021-01-01T00:00:00Z)
http_requests_total @ start()           # query range start
http_requests_total @ end()             # query range end
```

The `@` modifier is useful for comparing current values with a known reference point in the same expression.

## Rate Functions

Rate functions operate on counter range vectors. Counters only increase (or reset to zero on restart); rate functions handle resets transparently.

### `rate(v range-vector)`

Per-second average rate of increase across the full range window. Handles counter resets. The canonical choice for alerting and dashboards because it is smooth.

```promql
rate(http_requests_total{job="api"}[5m])
```

The range window should be at least 4x the scrape interval to guarantee enough samples. For a 15s scrape interval, use `[1m]` as the minimum practical window.

### `irate(v range-vector)`

Instantaneous rate using only the last two samples in the range window. Reacts immediately to spikes; highly volatile. Use on dashboards where you want to see momentary traffic surges. Do not use `irate` in alerting rules: a single-sample anomaly will cause the alert to fire and clear within one evaluation cycle, producing noisy notifications.

```promql
irate(http_requests_total{job="api"}[5m])
```

The range window is only a staleness bound for `irate`; the actual calculation always uses the two most-recent samples.

### `increase(v range-vector)`

Total counter increase over the range window. Mathematically equivalent to `rate(v[d]) * d` for duration `d`. Useful for "how many X happened in the last hour" summaries.

```promql
increase(http_requests_total{job="api"}[1h])
increase(kube_pod_container_status_restarts_total[1h]) > 5
```

### Choosing between `rate`, `irate`, and `increase`

| Situation | Recommended function |
|-----------|---------------------|
| Alerting rules | `rate` |
| Dashboard sparkline (smooth trend) | `rate` |
| Dashboard panel (momentary spikes) | `irate` |
| "Count of events in last N minutes" | `increase` |

## Aggregation Operators

Aggregation collapses multiple time series into fewer series by combining their values. The `by` and `without` clauses control which labels are preserved.

### `by` and `without`

`by (label1, label2)` keeps only the listed labels in the output, discarding all others. All series that share the same value for those labels are merged.

`without (label1, label2)` keeps all labels except the listed ones.

```promql
sum by (job) (rate(http_requests_total[5m]))
avg without (instance) (node_cpu_seconds_total)
```

When you aggregate without specifying `by` or `without`, all labels are discarded and the result is a single scalar-valued series.

### Aggregation functions

| Function | Purpose |
|----------|---------|
| `sum` | Sum of values |
| `avg` | Arithmetic mean |
| `max` | Maximum value |
| `min` | Minimum value |
| `count` | Count of series |
| `count_values` | Count series per unique label value |
| `stddev` | Population standard deviation |
| `stdvar` | Population variance |
| `topk(k, v)` | Top k series by current value |
| `bottomk(k, v)` | Bottom k series by current value |
| `quantile(phi, v)` | phi-quantile across series values |
| `group` | Returns a single 1-valued series per group (useful for joins) |

```promql
topk(5, sum by (handler) (rate(http_requests_total[5m])))
bottomk(3, node_filesystem_avail_bytes / node_filesystem_size_bytes)
count_values("version", build_info)
```

## Binary Operators and Vector Matching

### Arithmetic and comparison operators

Arithmetic: `+`, `-`, `*`, `/`, `%`, `^`

Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`

By default, comparison operators filter: they return only the series where the condition is true. Append `bool` to return 0 or 1 instead of filtering:

```promql
http_requests_total > bool 1000
```

Logical: `and`, `or`, `unless` (operate on sets of series, not values)

### One-to-one matching

When two instant vectors are combined with a binary operator, Prometheus pairs series by matching all their labels. If the label sets differ, use `on(...)` to specify which labels to match on, or `ignoring(...)` to exclude labels from matching.

```promql
# Ratio: series match on all labels
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Match on a subset of labels; ignore "mode" when dividing
node_cpu_seconds_total{mode="user"} / ignoring(mode) node_cpu_seconds_total
```

### Many-to-one and one-to-many matching

When the "one" side has multiple matching series on the "many" side, use `group_left` or `group_right` to carry extra labels from the many side.

```promql
# Carry the "tier" label from service_cost_per_request onto the rate result
rate(http_requests_total[5m])
  * on(service) group_left(tier)
  service_cost_per_request
```

`group_left(extra_labels)` means the left-hand vector is "many" and the right-hand vector provides the join key plus optional extra labels to copy across.

### Logical operators

`and` returns series from the left vector that have a matching series in the right vector (values come from the left).

`or` returns the union; the left vector's values take precedence for matched series.

`unless` returns series from the left vector that do NOT have a matching series in the right vector.

```promql
# Alert only when error rate is high AND traffic is significant (avoid alerting on zero-traffic)
(rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05)
  and
(rate(http_requests_total[5m]) > 10)
```

## Histogram Functions

### Classic histograms

A classic histogram metric is a set of counter time series with a `le` (less-than-or-equal) label for each bucket boundary, plus `_sum` and `_count` series.

`histogram_quantile(phi, v)` computes the phi-quantile from the bucket series. You must aggregate by `le` (and any other labels you want to preserve); omitting `le` causes an error.

```promql
histogram_quantile(0.95,
  sum by (job, le) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

Common pitfalls:

- Forgetting `by (le)` in the aggregation is the most frequent mistake.
- Aggregating across too many labels produces many output series and slows query evaluation; pre-compute as a recording rule.
- Classic histograms require bucket boundaries configured at instrumentation time. Poorly chosen buckets produce high interpolation error.

### Native histograms (Prometheus 3.x)

Native histograms replace pre-defined `le` bucket boundaries with a sparse exponential bucket schema. Each observation is placed in an automatically-sized bucket without any client-side configuration.

Key properties:

- No `le` label; the entire histogram is a single time series per label set, dramatically reducing cardinality.
- Server-side quantile computation is more accurate than classic staircase interpolation.
- Prometheus 3.x TSDB stores native histograms at roughly 5 bytes per sample (vs ~1.3 bytes per float sample, but far fewer total series).
- The `schema` parameter (default 0, base 2^(2^-schema) resolution) and `zero_threshold` are configured in the client library, not in Prometheus.

`histogram_quantile` works identically for both classic and native histograms:

```promql
# Native histogram: no "by (le)" needed, no "_bucket" suffix
histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))
```

Additional functions for native histograms:

```promql
histogram_avg(rate(http_request_duration_seconds[5m]))
histogram_count(rate(http_request_duration_seconds[5m]))
histogram_sum(rate(http_request_duration_seconds[5m]))
```

**Choosing between classic and native histograms:**

| Consideration | Classic | Native (3.x) |
|---------------|---------|--------------|
| Cardinality per metric | High (one series per bucket) | Low (one series per label set) |
| Bucket configuration | Required at instrumentation time | Automatic |
| Aggregation across instances | Supported (aggregate by `le`) | Supported natively |
| `histogram_quantile` accuracy | Depends on bucket placement | Higher (exponential schema) |
| Backwards compatibility | Works on all Prometheus versions | Requires Prometheus 3.x and updated client |

For new instrumentation on Prometheus 3.x, prefer native histograms. For compatibility with older Prometheus or existing dashboards expecting `_bucket` series, use classic histograms or enable both simultaneously via the client library's `NativeHistogramBucketFactor` configuration.

## Subqueries

A subquery embeds a range query inside an instant-vector context. The syntax is:

```promql
<instant-vector-expression>[<range>:<resolution>]
```

This evaluates the inner expression at each step of `resolution` across the `range`, producing a range vector that can then be passed to `max_over_time`, `avg_over_time`, etc.

```promql
# Maximum 5-minute rate over the last hour, sampled every 5 minutes
max_over_time(rate(http_requests_total[5m])[1h:5m])

# 95th percentile bandwidth over 30 days, sampled hourly
quantile_over_time(0.95,
  rate(ifHCInOctets{device="core-rtr-01"}[5m])[30d:1h]
) * 8
```

Subqueries are computationally expensive. Each evaluation of the inner expression queries multiple TSDB blocks. Always specify a `resolution` appropriate to the range; omitting it defaults to the global evaluation interval and can generate enormous result sets for long ranges.

## Over-Time Functions for Gauges

These functions operate on range vectors from gauge metrics (not counters):

```promql
avg_over_time(node_memory_MemAvailable_bytes[30m])
min_over_time(node_memory_MemAvailable_bytes[1h])
max_over_time(node_memory_MemAvailable_bytes[1h])
sum_over_time(node_memory_MemAvailable_bytes[5m])
count_over_time(node_memory_MemAvailable_bytes[5m])
quantile_over_time(0.95, node_memory_MemAvailable_bytes[1h])
last_over_time(node_memory_MemAvailable_bytes[5m])
```

## Utility Functions

**`absent(v)`** returns a one-element vector with value 1 if `v` has no series. Used in alerts that fire when a metric disappears (e.g., exporter stopped).

```promql
absent(up{job="critical-service"})
```

**`absent_over_time(v[d])`** fires if no data exists for the metric in the range window:

```promql
absent_over_time(up{job="api"}[10m])
```

**`predict_linear(v[d], t)`** fits a least-squares regression to the range vector and predicts the value `t` seconds from now. Useful for disk-filling alerts:

```promql
predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[6h], 4 * 3600) < 0
```

**`label_replace(v, dst, replacement, src, regex)`** creates or rewrites a label using regex capture groups:

```promql
label_replace(up, "service", "$1", "instance", "([a-z-]+)-\\d+:\\d+")
```

**`label_join(v, dst, separator, src1, src2, ...)`** joins multiple label values into a single label:

```promql
label_join(up, "host_port", ":", "host", "port")
```

**`changes(v[d])`** counts how many times a gauge changed value in the range. Useful for detecting configuration flaps.

**`resets(v[d])`** counts counter resets in the range (proxy for process restarts).

**`delta(v[d])`** is the difference between first and last value in the range. Use with gauges only.

**`deriv(v[d])`** computes the per-second derivative via least-squares regression.

**`clamp(v, min, max)`** / `clamp_min(v, min)` / `clamp_max(v, max)` restrict values to a range.

**Math:** `abs()`, `ceil()`, `floor()`, `round()`, `exp()`, `ln()`, `log2()`, `log10()`, `sqrt()`, `sgn()`

**Time:** `hour()`, `minute()`, `day_of_week()`, `day_of_month()`, `month()`, `year()`. These operate on timestamps of the series and are useful for time-of-day alerting suppression.

## Common Query Recipes

**HTTP error rate percentage (by job):**

```promql
100 * sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
  / sum(rate(http_requests_total[5m])) by (job)
```

**P99 latency from a classic histogram:**

```promql
histogram_quantile(0.99,
  sum by (service, le) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

**P99 latency from a native histogram:**

```promql
histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))
```

**CPU utilisation per node:**

```promql
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

**Memory usage percentage:**

```promql
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))
```

**Disk fill prediction (fire if filling within 4 hours):**

```promql
predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[6h], 4 * 3600) < 0
```

**Alert only when traffic is significant (avoid noise on zero-traffic services):**

```promql
(
  sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))
    / sum by (job) (rate(http_requests_total[5m]))
  > 0.05
) and (
  sum by (job) (rate(http_requests_total[5m])) > 1
)
```

**Pod restart count in last hour:**

```promql
increase(kube_pod_container_status_restarts_total[1h]) > 5
```

**Top 5 endpoints by request rate:**

```promql
topk(5, sum by (handler) (rate(http_requests_total[5m])))
```

**Apdex score (satisfied threshold 0.3s, tolerated 1.2s):**

```promql
(
  sum by (job) (rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
  + sum by (job) (rate(http_request_duration_seconds_bucket{le="1.2"}[5m]))
) / 2
/ sum by (job) (rate(http_request_duration_seconds_count[5m]))
```

**Interface bandwidth in bits/second:**

```promql
rate(ifHCInOctets{device="core-rtr-01"}[5m]) * 8
```

**95th percentile bandwidth over 30 days (subquery, sampled hourly):**

```promql
quantile_over_time(0.95,
  rate(ifHCInOctets{device="core-rtr-01"}[5m])[30d:1h]
) * 8
```

**Kubernetes node CPU request saturation:**

```promql
sum by (node) (kube_pod_container_resource_requests{resource="cpu", unit="core"})
/ sum by (node) (kube_node_status_allocatable{resource="cpu", unit="core"})
```

**Rolling 24-hour availability:**

```promql
avg_over_time(up{job="api"}[24h])
```

**JVM GC average pause duration:**

```promql
rate(jvm_gc_pause_seconds_sum[5m]) / rate(jvm_gc_pause_seconds_count[5m])
```

**Metric completely absent (dead man's switch pattern):**

```promql
absent(up{job="critical-service"}) == 1
```

## Recording Rules for Expensive Expressions

Any expression that appears in multiple dashboards or alert rules should be pre-computed. The naming convention is `level:metric:operations`:

```yaml
groups:
  - name: api_aggregations
    interval: 30s
    rules:
      - record: job:http_requests_total:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      - record: job:http_request_duration_seconds:p99
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          )
```

Recording rules reduce query-time cardinality and eliminate repeated evaluation of heavyweight expressions across dashboards and alert groups.
