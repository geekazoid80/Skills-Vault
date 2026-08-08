# AWS Observability Reference

A practical reference for observing AWS workloads through CloudWatch: metrics, alarms, metric math, Logs, Logs Insights, dashboards, plus a brief pointer to X-Ray tracing. The orientation here is operational: what to watch, how to alarm on it, and how to query the evidence after the fact.

## Orientation

AWS observability rests on three CloudWatch pillars plus a tracing service:

- **Metrics**: numeric time-series for any AWS service (EC2, ELB, Transit Gateway, NAT Gateway, VPN, and more), plus your own custom metrics.
- **Alarms**: stateful watchers over a metric or a metric-math expression; they transition between states and can fan out notifications or actions.
- **Logs**: log groups and streams that hold application and service logs; Logs Insights queries them with a purpose-built query language.
- **X-Ray** (tracing): request-level traces that follow a call across services. Covered briefly at the end as a pointer.

Two cross-cutting properties shape everything below:

- **Region scope**: metrics, log groups, alarms, and dashboards are scoped to the AWS Region they live in. A metric published in one Region is not visible from another. When you go looking for evidence, confirm you are in the right Region first.
- **Query cost awareness**: Logs Insights queries are billed on the volume of log data scanned. Narrow the time range and scope the log groups before you run a broad query; an unbounded scan over a chatty log group can be expensive and slow.

## Metrics

### What a metric is

A CloudWatch metric is a time-ordered set of data points, identified by a namespace (for example `AWS/EC2`), a metric name (for example `NetworkIn`), and a set of dimensions (key/value pairs such as `InstanceId=i-0abc...`) that pin the metric to a specific resource. Each data point carries a timestamp and a value, and is aggregated over a period when you query or alarm on it.

### Statistics and periods

When you read a metric you choose a **statistic** (Average, Sum, Minimum, Maximum, SampleCount, or a percentile such as p95) and a **period** (the aggregation window, for example 60 seconds or 300 seconds). The same underlying data answers very different questions depending on the statistic: Sum of `BytesProcessed` is throughput; Maximum of a latency metric is the worst case in the window; a high percentile such as p99 is the tail experience that averages hide.

Pick the statistic that matches intent. For an error count you almost always want Sum. For latency you usually want a percentile rather than Average, because Average flatters a long tail.

### Common network metrics

The table below lists frequently watched network metrics and what each tells you. Keep concrete only what the metric name itself encodes; treat thresholds as workload-specific.

| Service | Metric | What it tells you |
|---------|--------|-------------------|
| VPN | `TunnelState` | Per-tunnel state: 0 = down, 1 = up. |
| VPN | `TunnelDataIn` / `TunnelDataOut` | Bytes through each site-to-site VPN tunnel. |
| NAT GW | `ActiveConnectionCount` | Active connections through the NAT Gateway. |
| NAT GW | `PacketsDropCount` | Packets dropped (often a capacity signal). |
| NAT GW | `BytesProcessed` | Traffic volume through the NAT Gateway. |
| TGW | `BytesIn` / `BytesOut` | Traffic per Transit Gateway attachment. |
| TGW | `PacketDropCountBlackhole` | Drops against a blackhole route. |
| ELB | `HealthyHostCount` | Healthy targets behind an ALB or NLB. |
| ELB | `TargetResponseTime` | Backend (target) latency. |
| EC2 | `NetworkIn` / `NetworkOut` | Instance network throughput. |
| EC2 | `NetworkPacketsIn` / `NetworkPacketsOut` | Instance packet rate. |

A few reading notes:

- `TunnelState` is binary per tunnel; a site-to-site VPN has two tunnels, so alarm per tunnel rather than on an aggregate.
- `PacketsDropCount` on a NAT Gateway rising alongside `ActiveConnectionCount` points at the Gateway approaching a capacity ceiling rather than a transient blip.
- `PacketDropCountBlackhole` on a Transit Gateway is a routing problem, not a load problem: traffic is matching a blackhole route. Treat a non-zero value as a route-table review trigger, not a scaling trigger.
- For ELB, watch `HealthyHostCount` and `TargetResponseTime` together; a latency rise with a falling healthy-host count is targets failing under load rather than slow backends per se.

### Metric math

Metric math lets you compute a new time-series from one or more existing metrics: ratios, rates, sums across resources, and fill expressions. Common uses:

- **Error rate** as a ratio: divide an error-count metric by a request-count metric to get a proportion, rather than alarming on a raw count that scales with traffic.
- **Aggregate across resources**: sum a per-attachment or per-instance metric into one fleet-wide series so a dashboard tile or an alarm reflects the whole tier.
- **Fill gaps**: use a fill expression to substitute a value for missing data points so an alarm does not flap when a sparse metric reports nothing for a period.

Alarming on a metric-math expression (for example an error ratio) is usually more robust than alarming on a raw metric, because the expression normalises away traffic volume and reports the thing you actually care about.

## Alarms

### Alarm states

A CloudWatch alarm is always in exactly one of three states:

- **OK**: the metric is within the configured threshold.
- **ALARM**: the metric has breached the threshold for the configured number of evaluation periods.
- **INSUFFICIENT_DATA**: the alarm has not got enough data points to decide (newly created, the metric stopped reporting, or the data is sparse).

`INSUFFICIENT_DATA` is not a failure in itself, but a sustained `INSUFFICIENT_DATA` on something you expect to report regularly is a signal in its own right: the source may have stopped emitting.

### Evaluation: periods, datapoints-to-alarm, and missing data

An alarm evaluates a metric (or metric-math expression) over a period, and transitions to ALARM only when a threshold is breached for a configured number of data points within an evaluation window (the "M out of N" datapoints-to-alarm setting). Tuning this is the main lever against flapping: requiring several breaching data points before firing absorbs single-period spikes, at the cost of a slightly slower alert.

You also choose how the alarm treats **missing data**: it can be treated as breaching, not breaching, ignored (maintain the current state), or as missing (the default). Choosing this deliberately matters for sparse metrics; pairing a sensible missing-data policy with a metric-math fill expression keeps an alarm honest when the source reports intermittently.

### Actions

An alarm can drive actions on each state transition, most commonly publishing to an SNS topic that fans out to email, chat, paging, or a Lambda function. Alarms can also trigger auto-scaling actions or EC2 actions. Wire the OK transition to a notification too if responders need to know an incident has cleared, not just that it opened.

### Composite alarms

A composite alarm combines several underlying alarms with a boolean rule, so you alert on a meaningful condition (for example "latency high AND error rate high") rather than firing a separate page for each contributing metric. Composite alarms are the main tool for cutting alert noise: suppress the children, page on the parent.

### A workflow: network health check

When the question is "how is our AWS network performing?", a repeatable pass:

1. **List alarms in ALARM state** to see what is already flagged.
2. **VPN**: check `TunnelState` per tunnel and `TunnelDataIn` / `TunnelDataOut` for site-to-site VPNs.
3. **NAT Gateway**: `ActiveConnectionCount`, `PacketsDropCount`, `BytesProcessed`.
4. **Transit Gateway**: `BytesIn` / `BytesOut` and `PacketDropCountBlackhole` per attachment.
5. **ELB**: `HealthyHostCount`, `TargetResponseTime`, and 5xx error counts.
6. **Report**: a health summary with any breaches and anomalies flagged, scoped to the Region you queried.

## Logs

### Structure: groups, streams, retention

CloudWatch Logs organises data into **log groups** (a logical container, typically one per application or service) and **log streams** (a sequence of events from a single source, for example one instance or one Lambda invocation environment) within each group.

**Retention** is set per log group. By default a log group retains events indefinitely until you set a retention policy; once set, events older than the retention period are deleted automatically. Set retention deliberately on every log group: indefinite retention on a high-volume group is a quiet, growing storage cost, while too short a retention can delete the evidence you need for a post-incident review. Match retention to how far back investigations realistically reach.

### Logs Insights

CloudWatch Logs Insights is the query interface over log groups. A query is a pipeline of commands separated by `|`, run against one or more selected log groups over a chosen time range. Core commands:

- `fields` selects which fields to return.
- `filter` keeps only matching events.
- `stats` aggregates (count, sum, average, percentiles) optionally grouped `by` a field.
- `sort` orders the results.
- `limit` caps the number of rows returned.
- `parse` extracts fields from unstructured message text.

Cost and scope discipline applies here especially: the query is billed on data scanned, so narrow the time range and select only the relevant log groups before running. Start tight and widen only if the evidence demands it.

### Flow log query examples

VPC and Transit Gateway flow logs delivered to CloudWatch Logs can be queried with Logs Insights. These examples assume the standard flow-log field names.

```
# Top rejected connections in the last hour
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count() as rejections by srcAddr, dstAddr, dstPort
| sort rejections desc
| limit 20

# Traffic from a specific source
fields @timestamp, srcAddr, dstAddr, dstPort, bytes, action
| filter srcAddr = "10.0.1.50"
| sort @timestamp desc

# Top talkers by bytes
fields srcAddr, dstAddr, bytes
| stats sum(bytes) as totalBytes by srcAddr, dstAddr
| sort totalBytes desc
| limit 10
```

### A workflow: flow log analysis

When investigating traffic patterns or a security event:

1. **Query VPC flow logs**, filtering by source IP, destination IP, port, and action (ACCEPT / REJECT).
2. **Identify rejected traffic**: pull the REJECT entries to see what was blocked.
3. **Find top talkers**: aggregate by source and destination to surface the heaviest flows.
4. **Correlate in time**: narrow the window to the period around the incident.
5. **Report**: a traffic analysis with the rejected flows, the top talkers, and any recommendations.

## Dashboards

A CloudWatch dashboard is a saved, shareable view that composes metric graphs, alarm-status widgets, Logs Insights query results, and free-form text into one page. Dashboards are Region-scoped by default; a cross-Region or cross-account view needs widgets that explicitly reference the other Region or account.

Practical guidance:

- Build dashboards around a question or an audience, not around a service inventory. A "is the network healthy?" dashboard collects the VPN, NAT Gateway, Transit Gateway, and ELB tiles from the health-check workflow above onto one page.
- Put the alarm-status widget near the top so a glance answers "is anything firing right now?" before anyone reads the graphs.
- Prefer metric-math tiles (error rate, aggregate throughput) over raw per-resource series where the math is the thing you actually watch; raw series belong in a drill-down, not the headline.
- A dashboard is a starting point for an investigation, not the investigation itself. When something looks wrong, pivot to Logs Insights over the relevant log groups and the matching time window.

## X-Ray (tracing): a brief pointer

Where metrics tell you a tier is slow and logs tell you what an individual component did, **X-Ray** tells you where time went across a single request as it traversed multiple services. A trace is assembled from segments (one per service) and subsegments (downstream calls within a service), so you can see, for one request, which hop dominated the latency.

Reach for tracing when a latency problem spans service boundaries and per-service metrics cannot tell you which hop is responsible: the metric says the request was slow, the trace says which downstream call made it slow. Treat this section as a pointer rather than a full guide; the depth here is intentionally limited to where tracing fits alongside metrics, alarms, and logs.

## Operating notes

- **Confirm the Region first.** Metrics, log groups, alarms, and dashboards are all Region-scoped. A "missing" metric is very often a wrong-Region session.
- **Scope and time-box Logs Insights queries.** Billing follows data scanned; narrow the log groups and the time range before running, and widen only if the evidence demands it.
- **Set retention on every log group.** Default indefinite retention is a quiet cost; too-short retention deletes the evidence a post-incident review needs. Match it to how far back investigations reach.
- **Alarm on the right shape.** Prefer metric-math expressions (ratios, aggregates) and a deliberate missing-data policy over raw counts; tune datapoints-to-alarm against flapping; use composite alarms to page on a meaningful condition rather than each contributing metric.
- **Keep an audit trail.** Record monitoring investigations (what was queried, when, what was found) so the next responder inherits the evidence rather than rediscovering it.
