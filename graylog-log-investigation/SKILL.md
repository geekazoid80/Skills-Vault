---
name: graylog-log-investigation
description: "Use for any Graylog log investigation, query construction, alerting, or operational work. Covers Graylog 5.x and 6.x; the query language is Lucene + Graylog extensions (range, exists, list, fuzzy, regex). Triggers include 'graylog', 'graylog query', 'graylog search', 'graylog stream', 'graylog dashboard', 'graylog alert', 'graylog sidecar', 'graylog input', 'graylog content pack', 'graylog index set', 'graylog rotation strategy', 'graylog retention strategy', 'graylog API token', 'syslog severity', 'log level numeric', 'investigate this error', 'find logs by correlation id', 'aggregate log counts by host', 'log volume spike', 'log retention policy', 'graylog vs elastic stack', 'pipeline rules', 'pipeline simulator', 'pipeline rule never matches', 'grok', 'extractor', 'streams:read', 'role permissions', 'search returns zero', 'event alert returns nothing', 'GELF', 'beats input', 'syslog input'. Combines Graylog query-language reference (severity numerics 0-7 per RFC 5424, range syntax, exists / list / not, fuzzy + regex, time-range filters with relative + absolute + keyword forms), an investigation workflow (define scope, narrow by source / time / severity, pivot via correlation id, aggregate to spot patterns, escalate or close), index lifecycle management (rotation strategies time / size / message-count, retention strategies delete / close / archive, index set per data class), stream + pipeline + alert mechanics, sidecar / collector basics for Filebeat / NXLog / fluentd / rsyslog. Self-authored from public Graylog and RFC 5424 documentation; the NorceTech graylog-cli wrapper inspired the CLI-friendly query patterns but is not the source (no upstream licence). Pairs with linux-host-ops (host-side log shipping via systemd-journal-upload / Filebeat / rsyslog), zabbix-templates-and-triage (Stage 4 sibling; metrics complement logs in incident triage), oncall-runbooks (the runbook should name the Graylog stream and saved search the on-call engineer should open first), systematic-debugging (Phase 1 boundary evidence often surfaces in Graylog before metrics), secrets-hygiene (Graylog API tokens, LDAP service account, S3 / cold-storage archive credentials). For the Elasticsearch and OpenSearch search backend that Graylog shares with the Elastic Stack (ELK), covering data streams, ILM tiering, and KQL / Lucene / ES|QL log search, see references/elastic-stack-log-backend.md; for vendor-neutral SIEM / SOAR strategy, detection engineering, and SOAR playbooks see siem-soar-investigation. For exporting the admin objects (pipelines, rules, event definitions, notifications, streams, index sets, inputs and extractors, roles) as data and rebuilding a server from that export, including the Swagger API description, the entity catalogue cross-check, permission-filtered empty lists, token lifetime and id remapping, see references/graylog-admin-export-rebuild.md. Triggers also include 'export graylog config', 'rebuild graylog', 'graylog backup of pipelines and alerts', 'graylog api-docs', 'graylog catalog', 'graylog token ttl', 'event definition id changed after rebuild', 'empty list but no 403'."
license: Apache-2.0
metadata:
  version: "1.3.0"
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

### Prefer Extractors over pipeline-rule `regex()` for peeling fields out of unstructured text

Both mechanisms can extract fields from a raw message string, but they are not equally reliable in
practice. Verified 2026-09-18: a pipeline rule using the `regex()` function (both named `(?<name>...)`
capture groups and positional groups accessed via `m["1"]`/`m["ros_user"]`) **compiled with zero validation
errors, connected to a stream, and never populated a single field at runtime** across multiple real
messages that unambiguously matched the pattern (confirmed independently via a plain search-API query on
the same messages) — no error surfaced anywhere, the rule just silently did nothing. The named-group form
additionally hit an unrelated parser quirk choking on underscores inside `(?<name>...)`
(`"named capturing group is missing trailing '>'"` pointing at the underscore itself, not the missing
`>`). Switching the identical extraction logic to the older, input-level **Extractor** mechanism
(`POST /api/system/inputs/{inputId}/extractors`, `extractor_type: "regex"`, one extractor per target field,
each with its own single capture group and a `condition_type: "string"` gate) worked cleanly on the first
correctly-escaped attempt and has run reliably since. If a field-extraction need can be expressed as one
regex per field with a single capture group, reach for an Extractor first; only fall back to a pipeline
rule if the transform genuinely needs multi-step logic, lookup tables, or cross-field conditionals that
Extractors cannot express — and if a pipeline rule with `regex()` compiles but never seems to fire, do not
assume the rule is broken before checking a plain search for the messages it should be matching; it may be
a silent runtime no-op rather than a logic error.

**The `["matches"]` condition is the specific failure, and it can be false even for a pattern that matches
the same text everywhere else.** A rule whose `when` clause reads `regex("...", to_string($message.message))["matches"]`
can evaluate false for a message that a plain search, a regex tester and an extractor all match with the
identical pattern, anchored or not, while the plain `contains()` clauses in the same `when` pass. No error is
raised; the rule simply never fires. Do not spend time rewriting the pattern. Take the capture out of the
`when` clause and use `grok()` (or an extractor) instead:

```
rule "extract denied source address"
when
  has_field("message") && contains(to_string($message.message), "permission denied")
then
  set_fields(grok(pattern: "from: %{IPV4:denied_from} community", value: to_string($message.message), only_named_captures: true));
end
```

`grok()` returns an empty map for a line it does not match, so `set_fields` on an unmatched message adds
nothing and is safe to leave unguarded. Keep the cheap `contains()` pre-filter in `when` so the grok only runs
on candidate messages. Whatever you choose, prove the rule fires with the simulator below before trusting it.

### Test and bisect a pipeline rule with the simulator, not by watching live traffic

Waiting for live messages to show whether a rule fires is slow and proves little when a rule is silently
inert. Use the pipeline simulator over the API:

```
POST /api/system/pipelines/simulate
{"stream_id": "<stream id>", "input_id": "<input id>",
 "message": {"_id": "<any uuid>", "message": "<a real raw line>", "source": "<synthetic source>"}}
```

- The message object needs **`_id`**, not `id`; with `id` the request is rejected or the message is not
  recognised. Like every non-GET Graylog call it needs an `X-Requested-By` header.
- The response carries a rule-by-rule trace (which `when` clauses passed, which rule ran, which stage) plus the
  resulting fields, so you see exactly which clause fails instead of guessing.
- **Bisect by clause.** Run the same message with the `when` clause cut down one condition at a time; the
  first clause whose removal flips the rule to matched is the culprit.
- **Add a negative control.** Feed a message that must NOT match and confirm the output carries no new field. A
  rule that "passes" because it matches everything is as broken as one that matches nothing.
- **When bisecting on a live rule, guard every variant on a synthetic `source`** (a documentation-range
  address that no real device uses) so live traffic cannot match your experimental variant, and restore the
  saved original rule in a `finally`-style step so a failed experiment does not leave the pipeline altered.
- To prove a deployed rule has never matched, read its `matched`, `not-matched` and `failed` meters
  (`Rule.<rule id>...`) from the metrics API or the System > Metrics page: a rule whose `matched` stays at zero
  while `not-matched` climbs is evaluating and failing, not being skipped.

## Alerts

Alerts attach to a stream and a condition:

- Field aggregation (count of `level:<=3` over 5 minutes greater than 100)
- Field content (any message matching `message:"OutOfMemory"`)
- Pivot (top N hosts by error count)

Alert payload should include the runbook URL (see `oncall-runbooks`); do not page on-call without naming the procedure.

### REST API: event definition `series` uses `type`, not `function` — the silent-failure trap

Building an `aggregation-v1` event definition directly via `POST /api/events/definitions` (not through the
web UI), a grouped/threshold condition (`group_by` non-empty, `series` non-empty, `conditions.expression` a
real comparison) needs each `series` entry shaped as:

```json
{"type": "count", "id": "fail-count", "field": ""}
```

**Not** `{"id": "fail-count", "function": "count"}` — `function` is not a recognised property on the series
spec. The trap: `POST`/`PUT` with the wrong key **returns HTTP 200 with no validation error**, the
definition shows `state: ENABLED`, and it sits there silently never firing — no error, no log line (this
Graylog version's own `graylog-server` application logging can independently be broken after an unrelated
outage-recovery, which makes this doubly silent; see the outage runbook this was found alongside). Verified
2026-09-18: three separate hand-built definitions using `function` never matched across 15+ minutes of
observation despite thousands of qualifying messages in the stream; switching every `series` entry to the
`type`/`id`/`field` shape (confirmed against a real API response sample) fired within one execution cycle
against the same backlog. `field` is required even for `count` (pass `""`); for other series functions
(`card`, `avg`, `sum`, ...) it names the field being aggregated, e.g. `{"type": "card", "id": "ip-count",
"field": "gl2_remote_ip"}` for a distinct-count.

**The simple existence-check pattern is unaffected and a safe fallback while debugging this**: `group_by:
[]`, `series: []`, `conditions: {"expression": null}` fires on any single matching message in the window,
no series spec involved at all — useful to confirm the stream/query/notification wiring works before adding
a threshold. If a grouped-threshold definition creates cleanly, enables, and simply never matches against a
stream you can independently confirm has qualifying traffic (e.g. via a plain search-API query), suspect
this `type`-vs-`function` trap before suspecting the query or the stream.

Two related PUT-specific gotchas hit alongside this: (1) updating an existing notification or event
definition via `PUT /api/events/notifications/{id}` or `PUT /api/events/definitions/{id}` needs the body's
own top-level `"id"` field to match the URL's id — omitting it returns `"Notification IDs don't match"` (or
the definitions equivalent) rather than silently ignoring the mismatch. (2) A freshly-created event
definition is `state: DISABLED`; enable with `PUT /api/events/definitions/{id}/schedule` (returns
`state: ENABLED`), disable the same way with `.../unschedule`.

### A token without `streams:read` on a stream gets a silent zero, not an error

Searches and event-alert queries are filtered to the streams the caller may read. Ask for data in a stream the
token has no `streams:read` on and Graylog does not return 403: it returns an **empty result with HTTP 200**,
indistinguishable from "nothing happened". A detector or report built on that token will look healthy while
seeing none of the traffic.

- **Treat a surprising zero as a permission gap until proven otherwise.** Repeat the identical query, over the
  same closed time window, with a broader (admin-level) token and compare counts. A closed window matters:
  comparing against live traffic makes a difference of a few messages ambiguous. Equal counts mean the zero is
  real; reader lower than admin means the reader cannot see the stream.
- **Grant it on the role, not on the token.** For a read-only automation role, prefer the **wildcard
  `streams:read`** (no stream id) over listing stream ids one at a time: a new stream is then readable without
  another round of "why is it zero", and the grant is still read-only. Listing ids is the right call only where
  the role must be confined to specific streams.
- **API path.** Read and change roles at `/api/roles/<role name>`. `/api/authorization/roles` is the web UI
  route and returns the single-page-app HTML, which reads like a broken endpoint.
- **A role `PUT` needs the full body** (name, description, the complete permissions list, `read_only`), and the
  permissions list replaces the old one. Read the role first, add the permission to that list, and send the
  whole thing back; sending only the new permission strips the rest.
- Read-back after the change: list the streams as the reader token and re-run the comparison above, rather
  than trusting the PUT's 200. Note that `streams:read` does not let a token list event definitions; that is
  `eventdefinitions:read`, and the two are independent.

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
- **Trusting a pipeline rule because it compiled.** A rule can be accepted, connected and never match (see the `["matches"]` note under Extractors); simulate it, with a negative control.
- **Trusting a zero from a restricted token.** A missing `streams:read` returns an empty 200, not an error; compare against a broader token.
- **No timestamp normalisation.** Some shippers send local time; without normalisation, search by `timestamp` returns wrong-timezone results.

## Exporting and rebuilding the admin objects

Everything an operator builds in the UI lives only inside Graylog, so a restore is not reproducible from the log data. Dump the objects as data on a schedule, read-only, and rebuild from the dump; the full procedure, endpoint map, id-remapping table, rebuild order and the traps are in `references/graylog-admin-export-rebuild.md`. The load-bearing points:

- **Prove the read is complete.** Compare per-type counts with the entity catalogue (`/api/system/catalog`), and add referential checks for what the catalogue cannot count, because a **permission-filtered list returns an empty 200, not a 403**.
- **Ids are regenerated on rebuild.** Any tool keyed on an event-definition id goes silently blind (an unknown id returns an empty result); key it on the title and treat an unresolvable title as "could not look".
- **Never put secrets in a dump** (token values, input TLS passwords, secret-named keys); prove the stripping with planted fakes.
- **Use a dedicated read-only account** with a deliberately long token lifetime (the default is 720 hours), a recorded expiry and rotation date.

## Elastic Stack as the search backend

Graylog stores and searches through Elasticsearch or OpenSearch, the same substrate the Elastic Stack (ELK) exposes directly through Kibana. When the backend is visible (cluster sizing, index templates, ILM tiering, ECS normalisation), or when the choice is Graylog-on-Elasticsearch versus ELK-direct, see `references/elastic-stack-log-backend.md`. That reference covers ELK log collection (Elastic Agent / Filebeat), data streams, ILM hot/warm/cold/frozen tiers, and KQL / Lucene / ES|QL log search. ELK's APM, metrics, and tracing features are out of scope there; for those use `distributed-tracing`, `grafana-dashboards`, and `prometheus-configuration`.

## Cross-references

- `references/graylog-admin-export-rebuild.md`: exporting the admin objects as data and rebuilding from the export; the API description, catalogue cross-check, referential checks, id map, rebuild order, token lifetime and permission spellings.
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
- About to rely on `regex(...)["matches"]` in a rule's `when` clause without a simulator run that shows it true.
- About to believe an empty search or event-alert result from a token whose stream permissions you have not checked.
- About to `PUT` a role with only the permission you are adding (the body replaces the whole list).

## Bottom line

Source first, severity second, time third. Streams route, pipelines transform, alerts page. Index sets cap cost; retention strategy cap drift. The investigation log template feeds straight into the postmortem; do not waste an incident's worth of evidence by not writing it down.
