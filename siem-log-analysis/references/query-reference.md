# SIEM Query Reference: Network Security Use Cases

Side-by-side query patterns for Splunk SPL, ELK KQL, QRadar AQL, and Graylog Lucene-extended syntax, organised by network security investigation use case. Each query targets network device syslog events; not endpoint or application logs.

The `[Graylog]` column is vault-authored (not present upstream) and bridges with the local `graylog-log-investigation` skill. Graylog uses Lucene-extended syntax (field-scoped match, boolean `AND` / `OR` / `NOT` uppercase, ranges `[a TO b]` / `{a TO b}` exclusive, `_exists_:field`, wildcards anchored when possible, regex `/.../ ` with time-range warning, phrase quoting). Aggregation happens via Dashboard widgets or Event Definitions, not inline pipe syntax.

## Authentication failures

Identify failed login attempts across network devices by source IP. Useful for detecting brute-force attacks against management interfaces.

**[Splunk]** SPL:
```
index=network sourcetype=syslog "authentication failure" OR "Login failed"
| stats count by src_ip, host
| where count > 5
| sort -count
```

**[ELK]** KQL:
```
event.outcome: "failure" AND (message: "authentication failure" OR message: "Login failed")
| Filter: source.ip exists
```
Aggregate in Kibana Lens: split by `source.ip`, metric `count`, filter `count > 5`.

**[QRadar]** AQL:
```sql
SELECT sourceip, COUNT(*) AS attempts
FROM events
WHERE LOGSOURCETYPENAME(logsourceid) ILIKE '%network%'
AND (UTF8(payload) ILIKE '%authentication failure%' OR UTF8(payload) ILIKE '%Login failed%')
GROUP BY sourceip
HAVING COUNT(*) > 5
ORDER BY attempts DESC
LAST 24 HOURS
```

**[Graylog]** Lucene-extended:
```
("authentication failure" OR "Login failed") AND _exists_:source_ip
```
Aggregate in a Dashboard widget: Data Table view with `count` aggregation, split by `source_ip`, filter `count > 5`, sort descending; time range from the picker (e.g., 24 hours). Save as an Event Definition with aggregation condition `count(source_ip) > 5` to alert on brute-force patterns; runbook URL goes in the event's notification template.

**Returns:** Source IPs with more than 5 failed authentication attempts against network device management interfaces within the search window.

## Configuration changes

Detect configuration modification events on network devices. Critical for change management auditing and unauthorised change detection.

**[Splunk]** SPL:
```
index=network sourcetype=syslog "Configured from" OR "SYSTEM_MSG" OR "commit complete"
| table _time, host, user, _raw
| sort -_time
```

**[ELK]** KQL:
```
message: "Configured from" OR message: "commit complete" OR message: "SYSTEM_MSG"
```

**[QRadar]** AQL:
```sql
SELECT starttime, sourceip, UTF8(payload) AS event_detail
FROM events
WHERE category = 4002
OR UTF8(payload) ILIKE '%configured from%'
OR UTF8(payload) ILIKE '%commit complete%'
ORDER BY starttime DESC
LAST 7 DAYS
```

**[Graylog]** Lucene-extended:
```
("Configured from" OR "commit complete" OR "SYSTEM_MSG")
```
Display: Message Table widget sorted by `timestamp desc`, columns `source`, `user`, `message`. For change-window correlation, overlay a Quick Values widget on `source` to spot devices with unexpected change rates.

**Returns:** Timestamped list of configuration change events with the user or source that initiated the change.

## Firewall and ACL denies

Identify blocked connections by source / destination to detect scanning, exfiltration attempts, or misconfigured access policies.

**[Splunk]** SPL:
```
index=network sourcetype=syslog action=denied OR action=dropped OR "Deny" OR "denied"
| stats count by src_ip, dest_ip, dest_port
| where count > 100
| sort -count
```

**[ELK]** KQL:
```
event.action: "denied" OR event.action: "dropped" OR message: "Deny"
```
Aggregate in Kibana: split by `source.ip` and `destination.port`, metric `count`.

**[QRadar]** AQL:
```sql
SELECT sourceip, destinationip, destinationport, COUNT(*) AS deny_count
FROM events
WHERE eventdirection = 'L2R' AND category = 5001
GROUP BY sourceip, destinationip, destinationport
HAVING COUNT(*) > 100
ORDER BY deny_count DESC
LAST 24 HOURS
```

**[Graylog]** Lucene-extended:
```
(action:denied OR action:dropped OR message:"Deny" OR message:"denied")
```
Aggregate in a Dashboard widget: Data Table with `count` aggregation, split by `source_ip` then `dest_ip` then `dest_port`, filter `count > 100`, sort descending. For ongoing detection, save as an Event Definition with the count threshold and a runbook-URL-bearing notification.

**Returns:** Source / destination pairs with high deny counts, revealing scanning activity or blocked lateral movement attempts.

## Interface state changes

Track network interface link up / down events to detect physical layer issues, cable pulls, or deliberate interface shutdowns during incidents.

**[Splunk]** SPL:
```
index=network sourcetype=syslog "LINK-3-UPDOWN" OR "LINEPROTO-5-UPDOWN" OR "SNMP_TRAP_LINK"
| table _time, host, _raw
| sort -_time
```

**[ELK]** KQL:
```
message: "UPDOWN" OR message: "link up" OR message: "link down" OR message: "SNMP_TRAP_LINK"
```

**[QRadar]** AQL:
```sql
SELECT starttime, LOGSOURCENAME(logsourceid) AS device, UTF8(payload) AS event
FROM events
WHERE UTF8(payload) ILIKE '%UPDOWN%' OR UTF8(payload) ILIKE '%link down%'
ORDER BY starttime DESC
LAST 24 HOURS
```

**[Graylog]** Lucene-extended:
```
(message:"UPDOWN" OR message:"link down" OR message:"link up" OR message:"SNMP_TRAP_LINK")
```
Display: Message Table sorted by `timestamp desc`, columns `source` and `message`. For cascading-failure spotting, add a time-series widget split by `source` to see clusters of interface events across multiple devices in a short window.

**Returns:** Chronological list of interface state changes across network devices; correlate with other events to identify cascading failures.

## VPN tunnel events

Monitor VPN tunnel establishment and teardown events for site-to-site and remote access VPN connections.

**[Splunk]** SPL:
```
index=network sourcetype=syslog "CRYPTO-6-ISAKMP" OR "IKE_PHASE" OR "tunnel" "established" OR "removed"
| table _time, host, src_ip, dest_ip, _raw
| sort -_time
```

**[ELK]** KQL:
```
message: "IKE" OR message: "ISAKMP" OR (message: "tunnel" AND (message: "established" OR message: "removed"))
```

**[QRadar]** AQL:
```sql
SELECT starttime, sourceip, destinationip, UTF8(payload) AS event
FROM events
WHERE UTF8(payload) ILIKE '%ISAKMP%' OR UTF8(payload) ILIKE '%IKE%'
OR (UTF8(payload) ILIKE '%tunnel%' AND (UTF8(payload) ILIKE '%established%' OR UTF8(payload) ILIKE '%removed%'))
ORDER BY starttime DESC
LAST 7 DAYS
```

**[Graylog]** Lucene-extended:
```
(message:"ISAKMP" OR message:"IKE" OR (message:tunnel AND (message:established OR message:removed)))
```
Display: Message Table sorted by `timestamp desc`, columns `source`, `source_ip`, `dest_ip`, `message`. For tunnel-lifetime tracking, save as a stream-scoped search and overlay an Event Definition that alerts on `removed` events from non-maintenance windows (runbook URL in payload).

**Returns:** VPN tunnel lifecycle events; unexpected teardowns may indicate connectivity issues or active attacks on VPN infrastructure.

## Anomalous traffic patterns

Detect unusual event volume or connections to new destinations that deviate from established baselines.

**[Splunk]** SPL:
```
index=network sourcetype=syslog
| timechart span=1h count AS event_count
| eventstats avg(event_count) AS avg_count, stdev(event_count) AS stdev_count
| eval anomaly=if(event_count > avg_count + 2*stdev_count, "YES", "NO")
| where anomaly="YES"
```

**[ELK]** KQL:
Use Kibana ML (Machine Learning) anomaly detection job on the `network-*` index with `event_rate` as the detector function and `host.name` as the partition field. Alternatively, create a threshold rule alert on event count per host.

**[QRadar]** AQL:
```sql
SELECT DATEFORMAT(starttime, 'YYYY-MM-dd HH') AS hour, COUNT(*) AS event_count
FROM events
WHERE LOGSOURCETYPENAME(logsourceid) ILIKE '%network%'
GROUP BY DATEFORMAT(starttime, 'YYYY-MM-dd HH')
ORDER BY hour DESC
LAST 7 DAYS
```
Compare results against baseline averages. QRadar's built-in anomaly detection rules can also flag deviations automatically.

**[Graylog]** Lucene-extended:
Graylog OSS does not ship inline sigma-band logic. Two pragmatic patterns:
- **Dashboard widget approach (OSS-friendly):** create a Time Series widget with `count` aggregation, 1-hour buckets, time range 7 days. Visually compare the current hour against the baseline trend. For per-source detection, split by `source` and look for hosts whose latest-hour count sits well above their historical mean.
- **Event Definition approach (alerting):** create an Aggregation-condition event with `count() > <threshold>` per 1-hour grouping window, where `<threshold>` is set from a manually computed baseline `mean + 2*sigma`. Refresh the threshold quarterly or after a meaningful traffic shift. Runbook URL in the notification template.
- **Anomaly Detection plugin (Graylog Enterprise):** automates the sigma-band logic. Configure on the network stream with `event_rate` detector and `source` partition.

**Returns:** Time periods where event volume exceeds 2 standard deviations from baseline; indicative of scanning, DDoS, or data exfiltration activity.

## Lateral movement indicators

Detect internal-to-internal connections on unusual ports or protocols that may indicate post-compromise lateral movement.

**[Splunk]** SPL:
```
index=network sourcetype=syslog src_ip=10.0.0.0/8 OR src_ip=172.16.0.0/12 OR src_ip=192.168.0.0/16
dest_ip=10.0.0.0/8 OR dest_ip=172.16.0.0/12 OR dest_ip=192.168.0.0/16
NOT dest_port IN (22, 53, 80, 443, 3389)
| stats dc(dest_ip) AS unique_dests, dc(dest_port) AS unique_ports by src_ip
| where unique_dests > 10 OR unique_ports > 20
```

**[ELK]** KQL:
```
source.ip: (10.0.0.0/8 OR 172.16.0.0/12 OR 192.168.0.0/16)
AND destination.ip: (10.0.0.0/8 OR 172.16.0.0/12 OR 192.168.0.0/16)
AND NOT destination.port: (22 OR 53 OR 80 OR 443 OR 3389)
```
Aggregate by `source.ip`, cardinality of `destination.ip` and `destination.port`.

**[QRadar]** AQL:
```sql
SELECT sourceip, COUNT(DISTINCT destinationip) AS unique_dests,
       COUNT(DISTINCT destinationport) AS unique_ports
FROM events
WHERE INCIDR('10.0.0.0/8', sourceip) AND INCIDR('10.0.0.0/8', destinationip)
AND destinationport NOT IN (22, 53, 80, 443, 3389)
GROUP BY sourceip
HAVING COUNT(DISTINCT destinationip) > 10
ORDER BY unique_dests DESC
LAST 24 HOURS
```

**[Graylog]** Lucene-extended:
Graylog's Lucene query layer does not natively understand CIDR. The cleanest pattern is to tag at ingest, then query against the tag. Add a Pipeline rule that sets a `source_class` field (and a `dest_class` field) to `internal` for RFC 1918 ranges and `external` otherwise:

```
rule "tag rfc1918 source"
when
    has_field("source_ip") AND
    (cidr_match("10.0.0.0/8", to_ip($message.source_ip)) OR
     cidr_match("172.16.0.0/12", to_ip($message.source_ip)) OR
     cidr_match("192.168.0.0/16", to_ip($message.source_ip)))
then
    set_field("source_class", "internal");
end
```
(Mirror for `dest_class`.) Then the lateral-movement query becomes:
```
source_class:internal AND dest_class:internal AND NOT dest_port:(22 OR 53 OR 80 OR 443 OR 3389)
```
Aggregate in a Data Table widget: split by `source_ip`, two metrics `cardinality(dest_ip)` and `cardinality(dest_port)`, filter `cardinality(dest_ip) > 10 OR cardinality(dest_port) > 20`. For ongoing detection, save as an Event Definition with the cardinality thresholds and a runbook URL in the notification.

If pipeline-rule tagging is not available, fall back to lexicographic range matching (e.g., `source_ip:[10.0.0.0 TO 10.255.255.255]`) but be aware this works correctly only if the IP field is stored with zero-padded octets; otherwise the lexicographic sort produces wrong-range matches. The pipeline-rule pattern is strongly preferred.

**Returns:** Internal source IPs connecting to many internal destinations on non-standard ports; a strong lateral movement indicator requiring immediate investigation.
