# Network-device log forensics

Forensic timeline construction and threat detection from network-device syslog: firewall denies, authentication failures, configuration changes, interface events, VPN tunnel state, routing adjacency, and lateral-movement indicators. The diagnostic reasoning is platform-independent (what to look for, how to correlate, what is anomalous); only query syntax diverges. Works two ways: with a SIEM (cross-platform queries) or against raw syslog with standard Unix tools when no SIEM is available.

All sources here are network-device syslog. Endpoint, application, and cloud-audit logs are out of scope; route those to the appropriate detections in the umbrella.

## Six-step forensic procedure

The procedure builds a timeline from raw events through correlation, anomaly detection, and triage. Each step feeds the next.

### Step 1: verify sources

Confirm every in-scope device is forwarding syslog before drawing conclusions. Missing sources create blind spots that invalidate findings.

Device-side verification: Cisco `show logging`; JunOS `show system syslog`; EOS `show logging`; PAN-OS `show log-interface-setting`; FortiGate `get log setting` plus `diagnose log test`.

SIEM-side receipt: confirm recent events per device (Splunk `| metadata type=sources index=network`; ELK `GET /network-*/_search?size=1&sort=@timestamp:desc&q=host.name:<device>`; QRadar Log Sources, non-zero count and recent Last Event).

Raw-collector verification: review rsyslog (`/etc/rsyslog.conf`, `/etc/rsyslog.d/*.conf`; confirm the file template includes source hostname) or syslog-ng (`/etc/syslog-ng/syslog-ng.conf`; `keep-hostname(yes)`). Check the listener with `ss -ulnp | grep 514`.

NTP check (correlation depends on it): Cisco/EOS `show ntp status`; JunOS `show system ntp`. Devices with offset over 1 second need timestamp correction before correlation.

### Step 2: normalise events

Map raw syslog to a common field taxonomy so events from different vendors correlate.

| Common field | Description |
|---|---|
| `timestamp` | Event time (UTC) from the syslog header |
| `source_device` | Originating device hostname |
| `event_type` | Normalised category: auth, config, traffic, interface, vpn |
| `source_ip` / `dest_ip` / `dest_port` | Parsed from the message body |
| `action` | Outcome (permit/deny/info) |
| `user` | Associated username from auth messages |
| `severity` | RFC 5424 severity (0-7) from the syslog PRI field |

Platform parsing: Splunk source types plus Technology Add-ons (verify with `| fieldsummary`); ELK ingest pipelines or Logstash filters (verify in Discover); QRadar Device Support Modules (check Log Source Extensions if fields are missing).

### Step 3: correlate across sources

Join events by shared attributes to turn isolated messages into investigation threads.

- **IP-based** - join firewall denies with auth failures sharing a source IP in a window.
- **Time-window** - group events within +/- 60 s of a trigger (interface down -> routing change -> traffic shift).
- **Session-based** - track a VPN tunnel from establishment to teardown via tunnel/session ID.
- **User-based** - follow a user across devices (auth -> config change -> logout).

With a SIEM: Splunk `| transaction src_ip maxspan=5m` or `| join`; ELK aggregations (`composite`/`terms`) or EQL sequence queries; QRadar offense rules or AQL `JOIN`. Without a SIEM, merge per-device logs into one sorted stream:

```
cat /var/log/rtr*.log /var/log/sw*.log | sort -k1,3 > /tmp/merged-timeline.log
```

Causal-chain detection: network failures propagate predictably, e.g. `LINK-3-UPDOWN` -> `OSPF-5-ADJCHG` -> `BGP-5-ADJCHANGE` -> traffic reroute. Extract each stage and verify temporal sequence. Correlate SNMP traps (linkDown OID `1.3.6.1.6.3.1.1.5.3`) with their syslog equivalents; mismatches indicate logging gaps.

### Step 4: detect anomalies

Compare observed events against baseline (at least 7 days of history for statistical work).

With a SIEM: Splunk `| timechart span=1h count | eventstats avg(count) as avg, stdev(count) as sd | eval anomaly=if(count > avg + 2*sd, 1, 0)`; ELK Kibana ML `event_rate` jobs partitioned by `host.name`, or a threshold rule; QRadar anomaly-detection rules or hourly AQL counts vs 7-day average.

Without a SIEM, all detection is grep/awk/sort:

```
# message frequency baseline
awk '{print $1, $2, $3}' /var/log/network.log | sort | uniq -c | sort -rn

# first-seen Cisco mnemonics vs a baseline file
grep -oP '%\S+-\d-\S+' /var/log/cisco.log | sort -u > /tmp/current.txt
comm -23 /tmp/current.txt /tmp/baseline-mnemonics.txt
```

Key anomalies: event volume over 2 sigma from the hourly baseline (scanning or DDoS); new internal-to-internal destinations not seen in 30 days; non-standard ports from internal sources (lateral movement); auth attempts from outside management ranges; config changes outside maintenance windows; VPN tunnels from unexpected sources or at odd hours.

### Step 5: build the timeline

Assemble a definitive chronological sequence; it is the primary deliverable.

```
grep -h "PATTERN1\|PATTERN2\|PATTERN3" /var/log/*.log | sort -s -k1,3
```

Use a stable sort (`sort -s`) to preserve order of equal-timestamp events. Normalise mixed time zones/formats to UTC epoch seconds before sorting; apply the NTP offset from Step 1 to drifted devices (on BSD/macOS use `date -jf` instead of `date -d`). For each significant event, annotate the network impact and the user-visible symptom, then walk backward from the symptom to the earliest causal event: the root cause is the first event that, if prevented, would have stopped all downstream effects.

### Step 6: triage and classify

Assign severity, eliminate false positives, decide escalation. Compare each finding against known-benign patterns (scheduled maintenance, authorised scanning, expected VPN sources), assign severity, set disposition (true positive / false positive / informational), and record it. Every alert requires a disposition before closing.

## Cross-platform query patterns

Side-by-side patterns for seven network-security use cases. Each targets network-device syslog.

### Authentication failures (brute-force against management interfaces)

```
# Splunk
index=network sourcetype=syslog "authentication failure" OR "Login failed"
| stats count by src_ip, host | where count > 5 | sort -count

# ELK (KQL + Lens aggregation)
event.outcome: "failure" AND (message: "authentication failure" OR message: "Login failed")
#   split by source.ip, metric count, filter count > 5

# QRadar (AQL)
SELECT sourceip, COUNT(*) AS attempts FROM events
WHERE LOGSOURCETYPENAME(logsourceid) ILIKE '%network%'
AND (UTF8(payload) ILIKE '%authentication failure%' OR UTF8(payload) ILIKE '%Login failed%')
GROUP BY sourceip HAVING COUNT(*) > 5 ORDER BY attempts DESC LAST 24 HOURS
```

### Configuration changes (change-management audit)

```
# Splunk
index=network sourcetype=syslog "Configured from" OR "commit complete" | table _time, host, user, _raw | sort -_time
# ELK
message: "Configured from" OR message: "commit complete" OR message: "SYSTEM_MSG"
# QRadar
SELECT starttime, sourceip, UTF8(payload) FROM events
WHERE category = 4002 OR UTF8(payload) ILIKE '%configured from%' ORDER BY starttime DESC LAST 7 DAYS
```

### Firewall / ACL denies (scanning, blocked lateral movement)

```
# Splunk
index=network action=denied OR action=dropped OR "denied"
| stats count by src_ip, dest_ip, dest_port | where count > 100 | sort -count
# ELK
event.action: "denied" OR event.action: "dropped" OR message: "Deny"
# QRadar
SELECT sourceip, destinationip, destinationport, COUNT(*) AS deny_count FROM events
WHERE eventdirection = 'L2R' AND category = 5001
GROUP BY sourceip, destinationip, destinationport HAVING COUNT(*) > 100 ORDER BY deny_count DESC LAST 24 HOURS
```

### Interface state changes, VPN tunnel events, anomalous volume, lateral movement

Interface: match `LINK-3-UPDOWN` / `LINEPROTO-5-UPDOWN` / `SNMP_TRAP_LINK`. VPN: match `ISAKMP` / `IKE` / `tunnel established|removed`. Anomalous volume: hourly `timechart`/`GROUP BY hour` against a 2-sigma baseline (Splunk `eventstats`, ELK ML, QRadar anomaly rules). Lateral movement: internal-to-internal connections excluding standard ports, then count distinct destinations and ports per source:

```
# Splunk lateral-movement indicator
index=network src_ip=10.0.0.0/8 dest_ip=10.0.0.0/8 NOT dest_port IN (22,53,80,443,3389)
| stats dc(dest_ip) AS unique_dests, dc(dest_port) AS unique_ports by src_ip
| where unique_dests > 10 OR unique_ports > 20

# QRadar equivalent
SELECT sourceip, COUNT(DISTINCT destinationip) AS unique_dests, COUNT(DISTINCT destinationport) AS unique_ports
FROM events WHERE INCIDR('10.0.0.0/8', sourceip) AND INCIDR('10.0.0.0/8', destinationip)
AND destinationport NOT IN (22,53,80,443,3389) GROUP BY sourceip
HAVING COUNT(DISTINCT destinationip) > 10 ORDER BY unique_dests DESC LAST 24 HOURS
```

## Vendor syslog formats

| Vendor | Format | Notes |
|---|---|---|
| Cisco IOS-XE | `*timestamp: %FACILITY-SEVERITY-MNEMONIC: description` | Facility = subsystem (LINK, OSPF, SEC); severity 0-7; mnemonic = event ID |
| Juniper JunOS | `hostname process[pid]: EVENT_ID: message` | `structured-data` adds `[junos@2636 tag="value"]` pairs |
| Arista EOS | `hostname AgentName: %FACILITY-SEVERITY-message` | Agent name = subsystem (Ebra, Bgp, Ospf) |

Common events across vendors:

| Category | Cisco | JunOS | EOS |
|---|---|---|---|
| Link down/up | `LINK-3-UPDOWN` | `SNMP_TRAP_LINK_DOWN/UP` | `%LINEPROTO-5-UPDOWN` |
| Login failure | `SEC_LOGIN-4-LOGIN_FAILED` | `SSHD_LOGIN_FAILED` | `%SECURITY-4-LOGIN_FAILED` |
| Config change | `SYS-5-CONFIG_I` | `UI_COMMIT` | `%SYS-5-CONFIG_I` |
| OSPF adjacency | `OSPF-5-ADJCHG` | `RPD_OSPF_NBRDOWN/UP` | `%OSPF-5-ADJCHG` |
| BGP adjacency | `BGP-5-ADJCHANGE` | `RPD_BGP_NEIGHBOR_STATE_CHANGED` | `%BGP-5-ADJCHANGE` |

RFC 5424 PRI is `(Facility x 8) + Severity`; e.g. `local0.warning = (16 x 8) + 4 = 132`, written `<132>` in raw syslog. Common network facility assignments: local0 routers, local1 switches, local2 firewalls, local3 wireless controllers, local7 network management (check the collector's routing rules, since local0-7 vary per organisation).

## Threshold and confidence tables

### Alert severity

| Severity | Criteria | Response |
|---|---|---|
| Critical | Confirmed compromise, exfil evidence, unauthorised admin access | Immediate IR, executive notification |
| High | Lateral-movement indicators, auth failures then success, unauthorised config change | Investigate within 1 hour |
| Medium | Volume over 2 sigma, new destination patterns, single unauthorised attempt | Investigate within 4 hours |
| Low | Minor policy violation, single deny from a known scanner | Review within 24 hours, tune if recurring |
| Info | Baseline variance, expected maintenance | Log for trending, no action |

### Correlation confidence

| Confidence | Criteria | Action |
|---|---|---|
| High (> 0.8) | 3+ correlated events across 2+ devices, matching IPs, window < 5 min | Treat as confirmed, escalate |
| Medium (0.5-0.8) | 2 correlated events or a single-device chain with circumstantial evidence | Investigate before escalating |
| Low (< 0.5) | Single event or loose correlation (> 30 min window) | Monitor, do not escalate alone |

## Report template

```
NETWORK SECURITY LOG INVESTIGATION
Investigation ID / trigger / window (UTC) / platform (Splunk|ELK|QRadar|raw) / analyst
SUMMARY: type, severity, disposition, devices involved
SOURCE VERIFICATION (Step 1): sources active N/total, gaps, time-sync status
TIMELINE (Step 5): # | timestamp UTC | device | event type | src | dst | action | notes
ANOMALIES (Step 4): description, statistical basis, affected devices
CORRELATION (Step 3): method, confidence, supporting events
ROOT CAUSE: description, confidence + justification, causal chain (first event -> user impact)
EVIDENCE INTEGRITY: gaps (missing devices, time periods, rotated files), NTP corrections applied
RECOMMENDATIONS: immediate / short-term / long-term
```

## Common pitfalls

- Missing log sources: check device config, then the network path (UDP/TCP 514 or TLS 6514), then the collector listener. Document the gap; findings during it are inconclusive.
- Timestamp-format inconsistencies: RFC 3164 (`Mmm dd HH:MM:SS`, no year) vs RFC 5424 (ISO 8601). Normalise before merging; add the year from file mtime or logrotate naming.
- Rotation destroyed evidence: search compressed archives with `zgrep`; if data is gone, state which conclusions are limited.
- High volume makes grep slow: narrow to the window first, redirect to a working file, use `LC_ALL=C grep`, consider GNU parallel.
- Query timeouts: narrow the time range; use Splunk `| tstats` over accelerated models, ELK filtered aggregations, QRadar `LAST N HOURS` and no `SELECT *`.

## Cross-references

- `siem-soar-investigation`: the umbrella; condensed core and routing.
- `references/detection-engineering.md`: turn a recurring investigation pattern into a tuned detection.
- `graylog-log-investigation`: when Graylog is the platform, its query language and investigation workflow.
- `igp-routing-analysis`, `bgp-analysis`: decoding the routing-adjacency events that appear in causal chains.
- `oncall-runbooks`: the runbook the investigation report feeds and the alert points to.
- `utc-timestamps`: NTP-true, UTC timestamps are the precondition for every correlation and timeline here.
