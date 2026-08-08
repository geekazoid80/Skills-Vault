---
name: siem-log-analysis
description: Use for any network-security SIEM log analysis or investigation across Splunk, ELK, QRadar, or Graylog platforms. Triggers include "splunk search for auth failures", "ELK query for firewall denies", "QRadar AQL for lateral movement", "graylog query for VPN tunnels", "investigate alert in SIEM", "SIEM correlation across firewall and switch", "build a saved search for security events", "anomalous traffic in SIEM", "build a forensic timeline from SIEM data", "tune SIEM detection rule", "SIEM ingest pipeline", "QRadar offence investigation", "splunk alert without runbook URL", "lateral movement search in SIEM", "build correlation rule for brute force", "investigate authentication failures from SIEM", "SIEM normalisation across vendors", "what queries detect data exfil in SIEM", "compliance log review PCI-DSS 10.6", "tune false positive in SIEM alert", "ELK ingest pipeline missing field". Six-step procedure (verify syslog sources, normalise events, correlate across sources, build timeline, identify anomalies, triage and classify). Three threshold tables (Alert Severity Critical / High / Medium / Low / Info, Event Volume Anomaly Thresholds with sigma-based bands, Correlation Confidence Scoring with High / Medium / Low bands). One decision tree (Alert Triage Flow with benign-pattern-then-correlation-confidence routing). Side-by-side query patterns for all four platforms (Splunk SPL, ELK KQL, QRadar AQL, Graylog Lucene-extended) covering seven network-security use cases (authentication failures, configuration changes, firewall and ACL denies, interface state changes, VPN tunnel events, anomalous traffic patterns, lateral movement indicators) live in `references/query-reference.md`. Scoped to network device syslog (firewall denies, auth failures, VPN tunnel state, routing protocol events, interface events, configuration changes); endpoint logs and application logs are out of scope (use the appropriate domain-specific skill). Pairs with `network-log-analysis` for the no-SIEM raw-syslog companion case, `graylog-log-investigation` for general-purpose Graylog work not network-security-scoped, `oncall-runbooks` (every SIEM alert needs a runbook URL in its payload), and `incident-response-network` for forensics-grade evidence preservation when an investigation surfaces a confirmed incident. Diagnose-first; read-only investigation; chain of custody for any evidence cited in reports. Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); `cli-reference.md` folded into body; `references/query-reference.md` kept and extended with `[Graylog]` platform column at vault.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network Security SIEM Log Analysis

Investigation specialist for SIEM-based network-security log analysis across Splunk, ELK, QRadar, and Graylog platforms. The procedure builds a forensic timeline from raw syslog events through correlation, anomaly detection, and triage. This skill is the SIEM-equipped arm of a three-skill log-analysis family: `network-log-analysis` covers the no-SIEM raw-rsyslog case; `graylog-log-investigation` covers general-purpose Graylog work (any log domain, not just network security); this skill covers network-security-scoped investigation across the four common enterprise SIEM platforms.

Platform queries use `[Splunk]` (SPL), `[ELK]` (KQL / Lucene / Elasticsearch DSL), `[QRadar]` (AQL), and `[Graylog]` (Lucene-extended) inline labels. Diagnostic reasoning is platform-independent; only query syntax diverges. All investigation data sources are network device syslog events: firewall permit / deny logs, authentication messages, configuration change notifications, interface state changes, VPN tunnel events, and routing protocol messages. Endpoint logs, application logs, and cloud audit trails are out of scope.

See `references/query-reference.md` for complete side-by-side query patterns covering the seven network-security use cases across all four platforms.

> **Skill marker**: When applying this skill, begin your reply with `[skill: siem-log-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the SIEM estate (platform, index / stream layout, source-type / DSM coverage, retention tiers, on-call alert routing) before investigating. Only ask the user for information not already covered or specific to this investigation.

Before investigating, understand:

1. **Platform and scope**
   - Which SIEM platform is in scope (Splunk / ELK / QRadar / Graylog, or a mix)?
   - Which network device source types or DSMs are configured and parsing cleanly?
   - What index / stream / pipeline routes the events in scope?

2. **Investigation trigger**
   - Is this triggered by an alert (which one; what's the runbook URL?), a threat-hunt hypothesis, a compliance review, or an incident-response request?
   - What's the time window of interest, and is it within the SIEM's retention tier?
   - Are there known benign patterns (scheduled maintenance, authorised scans, expected VPN sources) that should be excluded?

3. **Evidence-handling stance**
   - Will findings feed an incident-response timeline (chain-of-custody discipline required; cross to `incident-response-network`)?
   - Or is this a routine triage with no IR escalation expected?
   - Either way, capture the SIEM query verbatim in the report so results are reproducible.

## When to use

- **Security incident investigation**: build a forensic timeline from network device logs when a security event is detected or reported
- **Threat hunting**: proactively search for indicators of compromise in network event data (lateral movement, unusual destinations, auth anomalies)
- **Alert triage**: evaluate SIEM alerts from network device sources to determine true positive, false positive, or informational classification
- **Compliance log review**: verify that required log sources are active and retention policies are met (PCI-DSS 10.6, NIST 800-53 AU-6, ISO 27001 A.12.4)
- **Anomalous behaviour detection**: identify deviations from baseline traffic patterns, event volumes, or connection profiles
- **Post-incident timeline construction**: reconstruct the sequence of network events surrounding a confirmed security incident for root cause analysis and lessons learned

## Do NOT use this skill for

- General-purpose Graylog work that is not network-security-scoped (use `graylog-log-investigation` instead; this skill's `[Graylog]` column targets the seven network-security use cases specifically)
- No-SIEM raw-syslog investigation (no Splunk / ELK / QRadar / Graylog platform available); use `network-log-analysis` instead
- Endpoint forensics, malware analysis, or application-log investigation (use the appropriate domain-specific skill)
- SIEM administration not tied to investigation (index design, retention policy authoring, sidecar deployment, DSM development); use the platform's own admin runbooks
- Network forensics with packet-level evidence (use `incident-response-network` for chain-of-custody discipline, packet capture, ARP / MAC table preservation, containment verification)

## Prerequisites

- **SIEM platform access:** search-level privileges. **[Splunk]** Search & Reporting role with read on the network indices. **[ELK]** Kibana Discover + Dev Tools Console with read on the `network-*` index pattern. **[QRadar]** Log Activity tab + Advanced Search privilege. **[Graylog]** Stream read permission on the network-scoped stream(s) plus dashboard view; saved-search and event-definition read where needed. Read-only access is sufficient for all queries.
- **Platform search-access cheatsheet** (folded from upstream `cli-reference.md`):
  - **[Splunk]**: Search & Reporting → New Search; time picker for the investigation window. Prefer `| tstats` over accelerated data models for fast counts; `| search` for ad-hoc full-text. Useful pipes: `| stats count by src_ip, action`, `| timechart span=1h count by sourcetype`, `| table _time, host, src_ip, dest_ip, action`, `| inputlookup` for enrichment.
  - **[ELK]**: Discover for interactive filtering with KQL bar; Dev Tools Console for `GET /network-*/_search` with Elasticsearch Query DSL or `GET /network-*/_count` for fast counting. `GET /_cat/indices/network-*?v` lists indices with doc counts and sizes.
  - **[QRadar]**: Log Activity → Advanced Search (switch from Quick Filter to AQL). AQL supports `GROUP BY`, `ORDER BY`, `LAST N MINUTES / HOURS / DAYS` time clauses. Quick Filter → Log Source for source-scoped filtering.
  - **[Graylog]**: search bar accepts Lucene-extended syntax (field-scoped match, boolean AND / OR / NOT uppercase, ranges `[a TO b]` / `{a TO b}`, `_exists_:field`, wildcards anchored when possible, regex `/.../ ` with time-range warning, phrase quoting). Time range via relative (`5m`) / absolute / keyword. Aggregation via Dashboard widget on the saved search, not inline pipe syntax.
- **Network device syslog forwarding:** target network devices must be forwarding syslog events to the SIEM. Verify on each device:
  - **[Cisco]** `show logging` confirms syslog destination IP, trap level, facility code
  - **[JunOS]** `show system syslog` shows configured syslog hosts and facility / severity filters
  - **[EOS]** `show logging` displays syslog server address and logging level
  - **[PAN-OS]** `show log-interface-setting` confirms log forwarding interface
  - **[FortiGate]** `get log setting` shows syslog server and severity filter; `diagnose log test` generates a test event for receipt verification
- **RFC 5424 facility / severity literacy:** all four SIEMs parse syslog using RFC 5424. Severity 0-7 (Emergency, Alert, Critical, Error, Warning, Notice, Informational, Debug). Common facility codes for network devices: `kern` (0), `auth` (4), `authpriv` (10), `local0`-`local7` (16-23). Vendor defaults: **[Cisco]** and **[FortiGate]** default to `local7`; **[EOS]** to `local4`; **[PAN-OS]** to `user`; **[JunOS]** to per-process (e.g., `daemon` for routing).
- **Time synchronisation:** all network devices and the SIEM platform must use NTP-synchronised time. Skewed timestamps corrupt correlation and timeline accuracy. Verify with `[Cisco]` `show ntp status`, `[JunOS]` `show system ntp`, `[EOS]` `show ntp status`.
- **Log familiarity:** understanding of network device syslog message formats; Cisco `%FACILITY-SEVERITY-MNEMONIC`, Juniper structured syslog, Palo Alto CSV-format traffic / threat logs, Arista event format.
- **Baseline data:** at least 7 days of historical log data for statistical anomaly detection. Without baseline data, anomaly detection in Step 5 is limited to manual threshold comparison.

## Procedure

Follow these six steps sequentially. The procedure builds a forensic timeline from raw syslog events through correlation, anomaly detection, and triage. Each step produces artefacts consumed by subsequent steps.

### Step 1: Verify syslog sources

Before investigating, confirm that all relevant network devices are actively forwarding syslog events to the SIEM. Missing sources create blind spots that invalidate investigation conclusions.

Verify on each device using the platform commands listed in Prerequisites above. Then confirm SIEM-side receipt of events from each device:

**[Splunk]**: `| metadata type=sources index=network` and verify each device appears with a recent `lastTime` value. Gaps exceeding the device's expected log rate indicate forwarding failures.

**[ELK]**: `GET /network-*/_search?size=1&sort=@timestamp:desc&q=host.name:<device>` for each device. Compare the returned timestamp against the current time.

**[QRadar]**: Admin → Log Sources and verify each network device shows a non-zero event count and recent "Last Event" timestamp.

**[Graylog]**: In the network stream, run `source:<device-hostname>` over the last hour; verify recent results. For a fleet check, use a Dashboard widget with `count` aggregation split by `source` field over the search window. The `Sources` page (System → Inputs → per-input statistics) shows per-source last-message timestamps for the global view.

### Step 2: Normalise events

Map raw syslog events to a common field taxonomy so events from different vendors and platforms can be correlated. Key normalisation fields:

| Common field | Description | Source examples |
|-------------|-------------|----------------|
| `timestamp` | Event time (UTC) | syslog header timestamp |
| `source_device` | Originating device hostname | syslog host field |
| `event_type` | Normalised event category | auth, config, traffic, interface, vpn |
| `source_ip` | Source IP address | parsed from message body |
| `dest_ip` | Destination IP address | parsed from message body |
| `dest_port` | Destination port | parsed from message body |
| `action` | Outcome (permit / deny / info) | parsed from message body |
| `user` | Associated username | parsed from auth messages |
| `severity` | RFC 5424 severity (0-7) | syslog PRI field |

**[Splunk]**: source types (e.g., `cisco:ios`, `juniper:junos`, `pan:firewall`) provide automatic field extraction via Technology Add-ons (TAs). Verify field extraction accuracy with `| fieldsummary` on the relevant source type.

**[ELK]**: ingest pipelines and Logstash filters perform field extraction. Verify parsed fields in Kibana Discover by expanding an event document. Missing fields indicate parsing pipeline issues.

**[QRadar]**: Device Support Modules (DSMs) provide automatic parsing. Check Log Source Extensions if standard DSMs do not extract required fields for a device type.

**[Graylog]**: pipeline rules perform field extraction at index time (preferred) or via extractors on the input. Verify parsed fields by expanding a message in the search view and checking that `source_ip`, `dest_ip`, `action`, etc. appear as structured fields (not just inside `message`). If pipeline rules are not extracting cleanly, use the rule simulator (System → Pipelines → Simulator) against a representative raw message before promoting fixes.

### Step 3: Correlate across sources

Join events from multiple network devices by shared attributes (timestamp windows, IP addresses, session identifiers, or user accounts). Correlation transforms isolated events into investigation threads.

**Correlation strategies:**

1. **IP-based correlation**: join firewall deny events with authentication failure events sharing the same source IP within a time window
2. **Time-window correlation**: group events within plus / minus 60 seconds of a trigger event (e.g., interface down then routing change then traffic shift)
3. **Session-based correlation**: track VPN tunnel establishment through to teardown using tunnel / session identifiers
4. **User-based correlation**: follow a user's activity across devices (authentication then config change then logout)

**[Splunk]**: `| transaction` or `| join` to correlate events across source types. `| transaction src_ip maxspan=5m` groups events by source IP within 5-minute windows.

**[ELK]**: Elasticsearch aggregations with `composite` or `terms` buckets on shared fields. For complex correlation, use the EQL (Event Query Language) sequence queries in Security → Timelines.

**[QRadar]**: Offence rules automatically correlate related events. For manual correlation, use AQL `JOIN` syntax or the "Event Correlation" search to group events by shared properties.

**[Graylog]**: Graylog has no inline pipe-based join. Correlate by running per-source queries and stitching results in a Dashboard or via the Event Definitions feature (correlation rule with aggregation conditions over a time window). For interactive correlation, save the first query as a stream-scoped search, add a second saved search with the shared field (`source_ip`, `dest_ip`, or `session_id`), and overlay them on a Dashboard time-series widget. Heavy correlation cases belong in an upstream SIEM or via the Graylog Enterprise correlation engine.

### Step 4: Build timeline

Arrange correlated events chronologically to reconstruct the sequence of network activity. The timeline is the primary investigation artefact.

**Timeline construction:**

1. Select correlated events from Step 3
2. Sort by timestamp (ascending), ensuring UTC normalisation
3. Annotate each event with device, event type, source / destination, action
4. Identify phase transitions: reconnaissance, initial access, lateral movement, objectives
5. Mark decision points where the attacker or anomaly changed behaviour

**[Splunk]**: `| sort _time | table _time, host, event_type, src_ip, dest_ip, action` produces a chronological event table. Use `| streamstats` to compute inter-event time deltas for pattern recognition.

**[ELK]**: Elastic Security → Timelines provides an interactive timeline builder. Drag correlated events into a timeline and annotate phases. Alternatively, use Discover sorted by `@timestamp` ascending.

**[QRadar]**: Within an Offence, the "Events" tab shows correlated events in chronological order. Export to CSV for external timeline tools.

**[Graylog]**: search results in the message table can be sorted by timestamp ascending; select fields (`source`, `event_type`, `source_ip`, `dest_ip`, `action`) for the message-table columns. For a deliverable timeline artefact, export the search results via the search-result-export menu (CSV) and merge with other sources externally, or use a Dashboard widget with `Message Table` view filtered to the correlated events.

### Step 5: Identify anomalies

Compare observed events against baselines to surface deviations that may indicate security threats. Anomalies include unusual event volume, new source / destination pairs, unexpected protocols, and off-hours activity.

**Statistical anomaly detection:**

**[Splunk]**: `| eventstats` for rolling averages and standard deviations, then flag events exceeding 2 sigma from baseline:
```
| timechart span=1h count | eventstats avg(count) as avg, stdev(count) as sd
| eval anomaly=if(count > avg + 2*sd, 1, 0)
```

**[ELK]**: Kibana ML anomaly detection jobs on the network index with `event_rate` detectors partitioned by `host.name`. Review anomaly scores in the ML Explorer. Threshold rule alerts can flag volume spikes without ML.

**[QRadar]**: Anomaly Detection rules (Administrative Offence rules) identify behavioural deviations automatically. For manual analysis, query hourly event counts with AQL and compare against 7-day averages.

**[Graylog]**: Event Definitions with aggregation conditions (count over a time window, plus comparison threshold) flag volume spikes; for sigma-band logic, run a `count by source` aggregation in a Dashboard widget over the baseline window and compare against the live window manually. The Anomaly Detection plugin (commercial / Enterprise) automates this; in OSS, expose hourly counts via the `count` widget and read sigma off the chart.

**Key anomalies for network security:**

- Event volume more than 2 sigma from hourly baseline (possible scanning or DDoS)
- New internal-to-internal destination IPs not seen in prior 30 days
- Connections on non-standard ports from internal sources (lateral movement)
- Authentication attempts from IP addresses not in known management ranges
- Configuration changes outside approved maintenance windows
- VPN tunnels established from unexpected source IPs or at unusual times

See `references/query-reference.md` for complete anomaly detection and lateral movement query patterns across all four platforms.

### Step 6: Triage and classify

Assign severity to findings, eliminate false positives, and determine escalation actions. This step transforms investigation results into actionable decisions.

**Classification process:**

1. Review each anomaly or correlated event chain from Steps 3-5
2. Compare against known benign patterns (scheduled maintenance, authorised scanning, expected VPN sources)
3. Assign severity using the Alert Severity Classification table below
4. Determine disposition: true positive, false positive, or informational
5. Apply the triage decision tree (see Decision Trees section)

When the disposition is True Positive with Critical or High severity, hand off to `incident-response-network` for evidence preservation (the SIEM holds the metadata; on-device ARP / MAC tables and any packet capture must be preserved before they age out) and to `oncall-runbooks` / `incident-response-lifecycle` for the incident management wrapper.

## Threshold tables

### Alert severity classification

| Severity | Criteria | Response |
|----------|----------|----------|
| **Critical** | Confirmed active compromise, data exfiltration evidence, unauthorised admin access | Immediate IR engagement, executive notification |
| **High** | Lateral movement indicators, multiple auth failures plus success, unauthorised config changes | Priority investigation within 1 hour, security team alert |
| **Medium** | Anomalous volume more than 2 sigma, new destination patterns, single unauthorised access attempt | Investigation within 4 hours, document and track |
| **Low** | Minor policy violations, single firewall deny from known scanner, informational anomaly | Review within 24 hours, tune rules if recurring |
| **Info** | Baseline deviation within normal variance, expected maintenance activity | Log for trending, no immediate action |

### Event volume anomaly thresholds

| Metric | Normal | Warning (>1 sigma) | Alert (>2 sigma) | Critical (>3 sigma) |
|--------|--------|---------------|-------------|-----------------|
| Events per hour (per device) | Baseline plus / minus 1 sigma | 1-2 sigma above baseline | 2-3 sigma above baseline | More than 3 sigma above baseline |
| Unique destination IPs (internal host) | Up to 20 / hour | 21-50 / hour | 51-100 / hour | More than 100 / hour |
| Failed auth attempts (per source IP) | Up to 3 / hour | 4-10 / hour | 11-50 / hour | More than 50 / hour |
| Firewall denies (per source IP) | Up to 50 / hour | 51-200 / hour | 201-1000 / hour | More than 1000 / hour |
| Config change events (per device) | Up to 2 / day | 3-5 / day | 6-10 / day | More than 10 / day |

### Correlation confidence scoring

| Confidence | Criteria | Action |
|------------|----------|--------|
| **High (>0.8)** | 3 or more correlated events across 2 or more devices with matching IPs and tight time window (less than 5 min) | Treat as confirmed, escalate |
| **Medium (0.5-0.8)** | 2 correlated events or single-device chain with circumstantial evidence | Investigate further before escalating |
| **Low (<0.5)** | Single event or loose time correlation (more than 30 min window) | Monitor, do not escalate without additional evidence |

## Decision trees

### Alert triage flow

```
Alert received from SIEM
├── Source device in scope (network infrastructure)?
│   ├── No → Route to appropriate team (endpoint, application, cloud)
│   └── Yes → Continue network security triage
│
├── Known benign pattern?
│   ├── Matches scheduled maintenance window → FALSE POSITIVE
│   │   └── Document, tune alert rule if recurring (>3 occurrences)
│   ├── Matches authorised scanning activity → FALSE POSITIVE
│   │   └── Add scanner IP to allowlist in correlation rule
│   └── No known benign match → Continue investigation
│
├── Correlation confidence (from Step 3)?
│   ├── High (>0.8) → TRUE POSITIVE; escalate
│   │   ├── Critical / High severity → Engage incident response
│   │   │   └── Hand off to incident-response-network (evidence preservation) + oncall-runbooks / incident-response-lifecycle (IR wrapper)
│   │   └── Medium / Low severity → Assign to security analyst
│   ├── Medium (0.5-0.8) → PROBABLE; investigate further
│   │   └── Run additional queries from references/query-reference.md
│   │       └── Confidence increases → Reclassify as True Positive
│   │       └── No supporting evidence → INFORMATIONAL
│   └── Low (<0.5) → INFORMATIONAL
│       └── Document trend, monitor for recurrence
│
└── Disposition recorded?
    ├── Yes → Close alert with classification and notes
    └── No → Document before closing; all alerts require disposition
```

## Report template

```
NETWORK SECURITY SIEM INVESTIGATION REPORT
=============================================
Investigation ID:     [unique identifier]
Investigation Trigger: [alert ID / hunt hypothesis / compliance requirement]
Investigation Window:  [start timestamp] to [end timestamp] (UTC)
SIEM Platform:        [Splunk / ELK / QRadar / Graylog]
Analyst:              [name / identifier]

SUMMARY:
- Investigation type: [incident / hunt / compliance / triage]
- Severity classification: [Critical / High / Medium / Low / Info]
- Disposition: [True Positive / False Positive / Informational]
- Devices involved: [count and hostnames]

LOG SOURCE VERIFICATION (Step 1):
- Sources confirmed active: [count] / [total expected]
- Sources with gaps: [list any devices with missing or delayed logs]
- Time sync status: [all synchronised / issues noted]

TIMELINE OF EVENTS (Step 4):
| # | Timestamp (UTC) | Device | Event Type | Source IP | Dest IP | Action | Notes |
|---|-----------------|--------|------------|----------|---------|--------|-------|
| 1 | [time] | [host] | [type] | [src] | [dst] | [action] | [context] |

ANOMALIES DETECTED (Step 5):
- [description of anomaly, statistical basis, affected devices]

QUERY EVIDENCE:
- Platform: [Splunk / ELK / QRadar / Graylog]
- Query used: [paste query verbatim]
- Results: [summary of what the query returned]
- Time range: [search window]

CORRELATION ANALYSIS (Step 3):
- Correlation method: [IP / time-window / session / user]
- Confidence score: [High / Medium / Low]
- Supporting evidence: [list of correlated events]

RECOMMENDATIONS:
1. [immediate action, e.g., block IP, isolate device, engage IR]
2. [short-term, e.g., tune detection rule, add log source]
3. [long-term, e.g., improve baseline, add correlation rule]

NEXT STEPS:
- [ ] [action item with owner and deadline]
```

## Common failure modes

### Missing log sources

**Symptom:** a network device that should be forwarding syslog shows no events in the SIEM for the investigation window.

**Diagnosis:** verify syslog configuration on the device using the Prerequisites cheatsheet. Check network connectivity between device and SIEM collector (firewall rules on UDP / TCP 514 or TLS 6514).

**Resolution:** reconfigure syslog forwarding, verify receipt with a test event, and document the gap period in the investigation report. Findings during the gap are inconclusive for the affected device.

### Time synchronisation issues

**Symptom:** correlated events have implausible timestamps; events that should be sequential appear out of order or with large gaps.

**Diagnosis:** check NTP status on affected devices. Compare device clock with SIEM server clock. Look for daylight-saving-time or timezone-offset errors (all timestamps should be UTC or consistently offset-adjusted).

**Resolution:** fix NTP configuration, recalculate event timestamps with the known offset, and note the time correction in the investigation timeline. Events from desynchronised sources have reduced correlation confidence.

### Log parsing failures

**Symptom:** events arrive but key fields (source IP, destination IP, action) are not extracted; they appear only in the raw message body.

**Diagnosis:** check SIEM-side parsing. **[Splunk]** verify the correct Technology Add-on (TA) is installed. **[ELK]** check ingest pipeline or Logstash filter for parsing errors. **[QRadar]** verify the Device Support Module (DSM) mapping. **[Graylog]** run the pipeline-rule simulator against a representative raw message; check that the extractor or pipeline rule fires and produces the expected fields.

**Resolution:** install or update parsing configuration for the affected source type. Reprocess raw events if the SIEM supports reindexing.

### Query performance problems

**Symptom:** SIEM queries time out or return slowly, especially statistical queries over large time ranges.

**Diagnosis:** check the search time range; broad ranges (more than 30 days) against non-accelerated data cause performance issues across all platforms.

**Resolution:** narrow the time range to the investigation window. Use accelerated search methods: **[Splunk]** `| tstats` over accelerated data models instead of `| search`. **[ELK]** filtered aggregations instead of full-text queries. **[QRadar]** `LAST N HOURS` clauses; avoid `SELECT *` in AQL queries. **[Graylog]** narrow with field-scoped match before wildcards / regex; pre-aggregate via a saved Dashboard widget instead of running ad-hoc full-text searches across `message`.

### Incomplete correlation

**Symptom:** correlation in Step 3 produces few results despite evidence of related activity across multiple devices.

**Diagnosis:** check field normalisation from Step 2. Common issues: IP addresses in different formats (dotted decimal vs integer), timestamps in different timezones, hostname mismatches between syslog header and SIEM device name.

**Resolution:** normalise the correlation fields before joining. Use CIDR matching instead of exact IP matching where appropriate. Widen the correlation time window if device clocks have minor drift.

### Graylog query confused with general-purpose Graylog work

**Symptom:** the investigation drifts into general Graylog admin (input setup, retention tier design, sidecar deployment) instead of the network-security-scoped use cases.

**Diagnosis:** scope drift. This skill's `[Graylog]` column targets the seven network-security use cases (auth failures, config changes, firewall / ACL denies, interface state, VPN tunnel, anomalous traffic, lateral movement); general-purpose Graylog work belongs in `graylog-log-investigation`.

**Resolution:** load `graylog-log-investigation` if the work is general-purpose; stay in this skill if the work is network-security-scoped investigation.

## Cross-references

- `network-log-analysis`: companion no-SIEM raw-syslog skill (rsyslog / syslog-ng with grep / awk on Cisco IOS-XE / NX-OS / IOS-XR / IOS / JunOS / EOS message formats). Use when no SIEM platform is available; the diagnostic reasoning is the same.
- `graylog-log-investigation`: general-purpose Graylog skill (any log domain, vendor-neutral on shippers). Use when the work is Graylog operations, query construction, alert design, or pipeline tuning that is not network-security-scoped.
- `oncall-runbooks`: every SIEM alert payload should carry a runbook URL. The 9-section runbook structure (overview, detection, triage, mitigation, root cause, resolution, communication, escalation) is the receiving discipline once an alert fires.
- `incident-response-network`: forensics-grade evidence preservation arm. When an investigation surfaces a True Positive with Critical or High severity, hand off to capture ARP / MAC / CAM tables, packet captures, flow records, and routing snapshots before volatile evidence ages out.
- `incident-response-lifecycle`: NIST 800-61 process layer. Wraps incident-response-network for severity classification, role assignment, escalation, communications, and post-mortem facilitation.
- `bgp-analysis`, `igp-routing-analysis`: when SIEM events implicate a routing-protocol anomaly (BGP flap, OSPF adjacency loss, route hijack), load the appropriate protocol-depth specialist for diagnosis.
- `acl-rule-analysis`: when SIEM firewall-deny investigation needs ACL-rule-level analysis (rule ordering, shadowed rules, accidental allow).
- `systematic-debugging`: SIEM evidence is often the Phase 1 boundary evidence in a wider debugging loop. Use the four-phase loop (collect, hypothesise, test, validate) rather than chasing a single query.
- `secrets-hygiene`: API tokens for SIEM access live in a secret store, not a search URL or shared dashboard. Audit credentials referenced in saved searches and alerts; rotate after any incident with credential-exposure suspicion.
- `utc-timestamps`: all SIEM timestamps must be UTC in reports. Even if the SIEM stores per-user timezone, normalise to UTC for cross-team correlation.
- `cite-sources`: when a SIEM investigation report references external indicators (threat-intel feeds, vendor advisories, CVEs), cite the source with date and identifier.
- `completion-gate` Layer 3: post-investigation verification (the suspected-malicious traffic should have stopped after containment; re-run the SIEM query post-fix to confirm).
- `humanise-comms`: SIEM reports go to mixed audiences (security analysts, executives, regulators). Match the audience.
- `multi-vendor-network-ops`: umbrella entry-point skill; the 9-element response contract applies on any production-impacting action (e.g., recommending an IP block based on SIEM evidence).

## Red flags

- **Paste API token in shared search URL.** Search URLs end up in tickets, screenshots, and bookmarks; tokens leak permanently. Use the platform's secret-store integration or per-user credentials, never tokens in URLs.
- **Build alert with no runbook URL in payload.** Alerts without runbooks generate 3 a.m. confusion; the on-call engineer cannot triage without a defined response. Every detection rule's alert payload includes a runbook URL pointing at the matching `oncall-runbooks` artefact.
- **Search across `*` index without time-window bound.** Wildcard index with no time bound burns cluster resources and returns unwieldy result sets. Always pair wildcard scope with an explicit time window from the platform's time picker or query clause.
- **Treat `null=` / `isnull(...)` semantics as identical across platforms.** Splunk's `where isnull(field)`, ELK's `NOT _exists_:field`, QRadar's `field IS NULL`, and Graylog's `NOT _exists_:field` look similar but diverge on edge cases (empty string vs absent field; multi-value field nulls). Test before relying.
- **Regex on raw `_raw` over a 30-day range.** Regex against the raw message field over wide time ranges is the standard performance pathology. Use field-scoped match wherever the field has been extracted; restrict regex to narrow time windows.
- **Trust the SIEM clock without verifying device NTP drift.** A SIEM that ingests a timestamp from a desynchronised device produces a misleading timeline. Always check NTP status on the source devices for any investigation spanning more than minutes.
- **Splunk lookup without TTL.** Stale lookups (asset inventory, allowlist, threat-intel) drift silently. Every lookup table has a TTL or a documented refresh cadence; document who owns the refresh.
- **Conflate `[Graylog]` network-security queries with `graylog-log-investigation` general-purpose territory.** This skill's Graylog column targets seven network-security use cases. General-purpose Graylog work (input design, retention tier rotation, pipeline rule authoring not network-security-scoped, dashboard authoring for non-security domains) belongs in `graylog-log-investigation`.
- **Recommend containment from this skill.** This is an investigation skill, not a response skill. Containment recommendations (block this IP, null-route this prefix, isolate this VLAN) need a change ticket, peer review, and execution discipline; hand off to `incident-response-network` (verification of containment effectiveness) and the appropriate `change-verification` / `acl-rule-analysis` skills for the actual change.
- **Close an alert without a recorded disposition.** Every alert needs True Positive / False Positive / Informational classification before close, with notes. Closing without disposition makes the next analyst re-investigate from scratch.

## Bottom line

SIEM log analysis for network security is a six-step procedure: verify sources, normalise events, correlate, build timeline, identify anomalies, triage. The diagnostic reasoning is platform-independent; only query syntax diverges. Four platforms covered: Splunk SPL, ELK KQL, QRadar AQL, Graylog Lucene-extended. Every alert needs a runbook URL; every search needs a time bound; every finding needs a disposition; every report needs UTC timestamps and verbatim queries for reproducibility. Hand off forensics-grade evidence preservation to `incident-response-network`; hand off NIST 800-61 process management to `incident-response-lifecycle`.
