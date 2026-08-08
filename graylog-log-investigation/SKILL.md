---
name: graylog-log-investigation
description: "Use for any Graylog log investigation, query construction, alerting, or operational work. Covers Graylog 5.x and 6.x; the query language is Lucene + Graylog extensions (range, exists, list, fuzzy, regex). Triggers include 'graylog', 'graylog query', 'graylog search', 'graylog stream', 'graylog dashboard', 'graylog alert', 'graylog sidecar', 'graylog input', 'graylog content pack', 'graylog index set', 'graylog rotation strategy', 'graylog retention strategy', 'graylog API token', 'syslog severity', 'log level numeric', 'investigate this error', 'find logs by correlation id', 'aggregate log counts by host', 'log volume spike', 'log retention policy', 'graylog vs elastic stack', 'pipeline rules', 'extractor', 'GELF', 'beats input', 'syslog input'. Combines Graylog query-language reference (severity numerics 0-7 per RFC 5424, range syntax, exists / list / not, fuzzy + regex, time-range filters with relative + absolute + keyword forms), an investigation workflow (define scope, narrow by source / time / severity, pivot via correlation id, aggregate to spot patterns, escalate or close), index lifecycle management (rotation strategies time / size / message-count, retention strategies delete / close / archive, index set per data class), stream + pipeline + alert mechanics, sidecar / collector basics for Filebeat / NXLog / fluentd / rsyslog. Self-authored from public Graylog and RFC 5424 documentation; the NorceTech graylog-cli wrapper inspired the CLI-friendly query patterns but is not the source (no upstream licence). Pairs with linux-host-ops (host-side log shipping via systemd-journal-upload / Filebeat / rsyslog), zabbix-templates-and-triage (Stage 4 sibling; metrics complement logs in incident triage), oncall-runbooks (the runbook should name the Graylog stream and saved search the on-call engineer should open first), systematic-debugging (Phase 1 boundary evidence often surfaces in Graylog before metrics), secrets-hygiene (Graylog API tokens, LDAP service account, S3 / cold-storage archive credentials). For the Elasticsearch and OpenSearch search backend that Graylog shares with the Elastic Stack (ELK), covering data streams, ILM tiering, and KQL / Lucene / ES|QL log search, see references/elastic-stack-log-backend.md; for vendor-neutral SIEM / SOAR strategy, detection engineering, and SOAR playbooks see siem-soar-investigation."
license: Apache-2.0
metadata:
  version: "1.1.0"
---

# Graylog Log Investigation

Specialist for Graylog log search, alerting, and operations. Vendor-neutral on shippers (Filebeat, NXLog, fluentd, rsyslog, GELF SDKs); Graylog server-side semantics are the focus.

> **Skill marker**: When applying this skill, begin your reply with `[skill: graylog-log-investigation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Graylog estate (input sources, stream layout, retention tiers, search-cluster topology) before investigating. Only ask the user for information not already covered or specific to this investigation.

Before investigating, understand:

1. **Source and ingestion**
   - Which inputs are in scope (Syslog, GELF, Beats, raw)?
   - Stream(s) that should contain the events of interest?
   - Pipeline rules transforming or routing the data?

2. **Investigation scope**
   - Symptom (error spike, missing event, deliberate hunt)?
   - Time window (live tail, recent hour, archive search)?
   - Severity expected (RFC 5424 numeric)?

3. **Search and retention**
   - Index set holding the period in scope (hot, warm, archived to S3 / object store)?
   - Saved searches or dashboards already built for the area?
   - Field extractor coverage for the sources of interest?

---

## When to use

- Investigating an incident where logs are the primary evidence
- Building a search query that finds the needle without scrolling through the haystack
- Setting up streams, pipelines, or alerts on a new data source
- Designing index sets, rotation, and retention before storage costs explode
- Reviewing a dashboard or alert that fires too often or never
- Troubleshooting a stuck input, a sidecar that stopped reporting, or an index that will not write

## Log severity numerics (RFC 5424)

Every syslog-shaped log carries a numeric severity. Filter on the number; tolerate any synonym for the level name.

| Numeric | Name | Meaning |
|---------|------|---------|
| 0 | Emergency | System unusable; imminent panic |
| 1 | Alert | Immediate action required |
| 2 | Critical | Critical condition; partial outage |
| 3 | Error | Error events; functionality impaired |
| 4 | Warning | Warning; situation deserves attention |
| 5 | Notice | Normal but significant |
| 6 | Informational | Informational; routine |
| 7 | Debug | Debug-level; verbose |

Common filter shorthand:

- `level:<=3`: anything that should page or pre-page (Emergency through Error)
- `level:<=4`: add Warning for early-warning investigation
- `level:7`: Debug only; usually noise unless the application is misconfigured to ship Debug to production
- `* AND NOT level:7`: strip Debug from a broad search

## Graylog query language

Built on Apache Lucene; Graylog adds operators and time semantics.

### Field-scoped match

```
source:payment-service
service:checkout-api
http_status:500
```

Field name is case-sensitive on the index mapping; value match is case-sensitive unless the field is mapped as analysed text.

### Boolean composition

```
source:payment-service AND level:<=3
service:checkout AND level:<=4 AND NOT message:"healthcheck"
(source:web1 OR source:web2) AND http_status:[500 TO 599]
```

`AND`, `OR`, `NOT` must be uppercase. Parentheses for grouping are mandatory when mixing operators.

### Ranges

```
http_status:[400 TO 499]            # inclusive both ends
http_status:{400 TO 500}            # exclusive both ends
duration_ms:[1000 TO *]             # >= 1000
timestamp:[2026-05-09 TO 2026-05-10]
```

### Existence and list match

```
_exists_:correlation_id
NOT _exists_:user_id
status:(200 OR 201 OR 204)
```

### Fuzzy and wildcard

```
checkout~                            # fuzzy match (Levenshtein distance 2)
checkou*                             # wildcard suffix
*timeout*                            # wildcard contains (slow; avoid on hot indexes)
```

Leading wildcards are expensive. Anchor when possible; if not, narrow the time range and source first.

### Regex

```
source:/api-(prod|staging)-[0-9]+/
message:/exception.*timeout/
```

Regex on `message` is the slowest match; never run it across an unbounded time range.

### Phrase and quoted string

```
"Connection refused"
"failed to fetch user"
```

Quoted strings preserve word order and adjacency. Without quotes, Lucene tokenises and ranks; the result is a different query.

## Time range

Graylog accepts three time-range forms:

- Relative: `Last 5 minutes`, `Last 1 hour`, `Last 24 hours`, `Last 7 days`. Default is 5 minutes; explicitly set when sharing a search URL.
- Absolute: `2026-05-10 09:00:00 to 2026-05-10 09:30:00`. Use UTC; tag the timezone in the URL parameters.
- Keyword: `today`, `yesterday`, `this week`. Convenient but ambiguous across time zones.

In a saved search, prefer absolute + UTC for postmortem evidence; prefer relative for live dashboards.

## Investigation workflow

1. **Define scope.** What service, what time window, what severity floor?
2. **Narrow by source first.** `source:checkout-api` reduces 10 GB to 100 MB before any other clause runs. Source is the cheapest filter.
3. **Add severity floor.** `AND level:<=3` strips Notice / Info / Debug. Add `level:<=4` only if the issue might be in Warning land.
4. **Pivot on correlation id.** When the user reports "order 12345 failed", search for `correlation_id:abc-123` (or `order_id:12345`) and follow the trail across services.
5. **Aggregate to spot patterns.** Counts by `source`, by `error_code`, by `http_status` reveal whether one host is misbehaving or all are.
6. **Escalate or close.** Either the evidence points to a hypothesis (test it; see `systematic-debugging`) or the search came up empty (widen severity, widen time, widen source list; or accept that logs do not have the answer and pivot to metrics or traces).

### Investigation log template

```
SCOPE
- Service: checkout-api
- Time: 2026-05-10 09:00 to 09:30 UTC
- Severity floor: level:<=3

QUERY
source:checkout-api AND level:<=3 AND _exists_:correlation_id

OBSERVATIONS
- 47 errors from one host (checkout-api-7); other hosts clean
- All carry correlation_id; downstream service (payment-gateway) shows matching errors

HYPOTHESIS
checkout-api-7 lost network path to payment-gateway between 09:05 and 09:25

NEXT
Check Zabbix net.tcp.port[checkout-api-7,8443] over the same window
Check oncall-runbooks for "downstream-dependency-loss" runbook
```

## Streams

A stream is a saved query that flags every matching message at ingest time. Use streams for:

- Routing messages to dedicated index sets (cheap retention for noise, expensive retention for signal)
- Alerting (alerts attach to streams, not raw search)
- Per-team scoping (Team A sees only their app's stream)

Stream rules are exact-match or contains; for pattern matching at ingest, use a pipeline rule instead.

## Pipelines

Pipelines run on the message at ingest. Use for:

- Field extraction (parse JSON message body, lift fields to top level)
- Field renaming (`pid` to `process_id` for cross-source consistency)
- Type conversion (string `200` to integer `200` for range filters)
- Drop or route messages (drop Debug from production stream; route by environment)
- Enrichment (lookup table for region by source IP)

Pipeline rules are written in the Graylog DSL (lookup tables, when / then / let). Test with `pipeline simulator` before connecting to a stream; a buggy rule blocks ingestion.

## Alerts

Alerts attach to a stream and a condition:

- Field aggregation (count of `level:<=3` over 5 minutes greater than 100)
- Field content (any message matching `message:"OutOfMemory"`)
- Pivot (top N hosts by error count)

Alert payload should include the runbook URL (see `oncall-runbooks`); do not page on-call without naming the procedure.

## Index lifecycle

### Index sets

One index set per data class. Common split:

- `production-app-logs`: 7 d hot, 30 d warm
- `production-syslog`: 14 d hot, 90 d warm
- `production-audit`: 30 d hot, 7 y warm or archived (regulatory)
- `noise`: 1 d hot, then drop

### Rotation strategy

| Strategy | When to use |
|---|---|
| Time-based | Predictable per-day volume; default for most |
| Size-based | Variable volume; cap each index at e.g. 50 GB |
| Message-count | Predictable per-message rate; rare |

### Retention strategy

| Strategy | When to use |
|---|---|
| Delete | Most operational logs; cheapest |
| Close | Keep on disk but unsearchable; recover by re-opening |
| Archive | Move to S3 / GCS / Azure Blob; required for regulated data |

Set retention per index set, not per stream. Streams that share an index set share retention.

## Sidecars and shippers

Graylog Sidecar manages collectors on hosts (Filebeat, NXLog, fluentd, Winlogbeat). Configuration is centrally managed and pushed to sidecars on poll.

Direct shippers (no sidecar) are simpler but unmanaged at scale. Direct GELF over TCP / UDP / HTTP is also valid; UDP risks loss under network stress, prefer TCP or HTTP for production.

For Linux hosts: prefer Filebeat or rsyslog with the omfwd module shipping to a Graylog Beats or Syslog input. See `linux-host-ops` for the host side.

## Common pitfalls

- **Wildcards on `message` over wide time ranges.** Crushes Elasticsearch; the cluster goes red.
- **Streams with too many rules.** Each rule evaluates per message; 50-rule streams cost ingest CPU.
- **Pipeline rules without simulator testing.** A bad rule blocks every message; the cluster does not error, it just stops ingesting.
- **Same retention for noise and signal.** Either you keep noise too long or signal too short.
- **Default 5-minute time range on shared searches.** Recipients open the link minutes later; the window has slid; results are different.
- **Alerts without runbook URL.** Pages on-call with no path to action.
- **API token in dashboard URL.** Tokens belong in the secret store, not in shared links.
- **Index sets per stream.** Sets cost cluster overhead; consolidate by data class.
- **Sidecar configuration drift.** Hosts run different collector configs because someone edited one in place; bring them all back under sidecar control.
- **No timestamp normalisation.** Some shippers send local time; without normalisation, search by `timestamp` returns wrong-timezone results.

## Elastic Stack as the search backend

Graylog stores and searches through Elasticsearch or OpenSearch, the same substrate the Elastic Stack (ELK) exposes directly through Kibana. When the backend is visible (cluster sizing, index templates, ILM tiering, ECS normalisation), or when the choice is Graylog-on-Elasticsearch versus ELK-direct, see `references/elastic-stack-log-backend.md`. That reference covers ELK log collection (Elastic Agent / Filebeat), data streams, ILM hot/warm/cold/frozen tiers, and KQL / Lucene / ES|QL log search. ELK's APM, metrics, and tracing features are out of scope there; for those use `distributed-tracing`, `grafana-dashboards`, and `prometheus-configuration`.

## Cross-references

- `references/elastic-stack-log-backend.md`: the Elasticsearch / OpenSearch backend Graylog shares with ELK; data streams, ILM tiering, KQL / Lucene / ES|QL, and the Graylog-vs-ELK-direct decision.
- `siem-soar-investigation`: vendor-neutral SIEM / SOAR strategy, detection engineering, normalisation standards, SOAR playbooks, and network-device log forensics; Graylog is one concrete log-investigation platform under that umbrella.
- `linux-host-ops`: Host-side log shipping via Filebeat, rsyslog, systemd-journal-upload; journalctl as the local-only fallback when Graylog is unreachable.
- `zabbix-templates-and-triage`: Stage 4 sibling. Metrics complement logs in incident triage; Zabbix often points the time range, Graylog provides the evidence.
- `grafana-dashboards`: Stage 4 sibling. When Grafana is the visualisation layer in front of Graylog data via the Loki-style data source.
- `slo-implementation`: Stage 4 sibling. Log-derived SLIs (error-rate computed from logs rather than metrics) when the application instrumentation is metrics-poor.
- `oncall-runbooks`: The runbook should name the Graylog stream and saved-search URL the on-call engineer should open first; alert payloads carry the runbook URL.
- `systematic-debugging`: Phase 1 boundary evidence; logs often surface the failure before metrics.
- `secrets-hygiene`: API tokens, LDAP service-account password, S3 / GCS / Azure cold-storage archive credentials all live in the secret store, not in pipeline rules or content packs.
- `bash-defensive`: Wrapper scripts that call the Graylog REST API follow defensive-bash discipline (quoted variables, set -e, fail-fast on non-2xx response).
- `completion-gate` Layer 3: After a deploy, post-checks include "did the new error class disappear from the stream" and "are the expected new fields parsing".
- `plan-time-tooling`: Index-set design or pipeline-rule changes that affect ingest fire engineering:architecture; cluster-level changes (capacity, rotation strategy, indexer) fire engineering:deploy-checklist.

## Red flags

- About to run a wildcard on `message` across "Last 7 days".
- About to add a pipeline rule directly to a connected stream without simulator testing.
- About to share a Graylog URL with the default 5-minute relative range.
- About to commit an API token into a content pack export.
- About to set rotation strategy to time-based with retention of 30 indices on a stream that occasionally bursts to 10 GB / day (each rotation will retain 30 GB; do the maths first).
- About to wire an alert with no runbook URL in the message body.
- About to ship Debug to production without filtering at the source.
- About to disable the Sidecar collector configuration "to make a quick local change" (drift is forever).
- About to delete an index set for "old logs" without confirming retention overlap with audit / compliance requirements.
- About to add a wildcard regex to a pipeline rule that runs on every message (cluster CPU spike).

## Bottom line

Source first, severity second, time third. Streams route, pipelines transform, alerts page. Index sets cap cost; retention strategy cap drift. The investigation log template feeds straight into the postmortem; do not waste an incident's worth of evidence by not writing it down.
