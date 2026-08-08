---
name: network-log-analysis
description: Use for any no-SIEM raw-syslog network log investigation across rsyslog or syslog-ng collectors. Triggers include "raw syslog investigation", "no SIEM available", "rsyslog log review", "syslog-ng analysis", "grep through /var/log/network", "awk on syslog file", "build a forensic timeline from raw logs", "Cisco syslog pattern", "IOS-XR RP/0/RP0/CPU0 log prefix", "NX-OS module log facility", "JunOS structured-data syslog", "Arista EOS agent name log", "RFC 5424 severity numeric", "RFC 3164 vs 5424", "PRI calculation facility times eight plus severity", "compressed log rotation zgrep", "merge per-device log files chronologically", "NTP-aware timestamp normalisation", "epoch conversion for log sort", "syslog facility local0 local1 local2", "config change outside maintenance window", "auth failure cluster by source IP", "interface flap cascade pattern", "OSPF neighbour down to BGP withdrawal chain", "logrotate retention 90 days", "MTU mismatch syslog correlation", "syslog gap during rotation". Six-step procedure (log collection assessment, syslog pattern recognition, event correlation, anomaly detection, timeline reconstruction, report). Three threshold tables (Log Volume Anomaly with multiplier bands, Syslog Severity Response Matrix 0-7 with investigation actions, Correlation Confidence Levels Confirmed / Probable / Possible). Two decision trees (Investigation Entry Point with trigger-type routing, Anomaly Classification with volume / new-mnemonic / auth / config-change branches). Multi-vendor syntax labels `[IOS]` / `[IOS-XE]` / `[NX-OS]` / `[IOS-XR]` for the Cisco family (each broken out separately where facility names or message prefixes diverge), `[JunOS]` for Juniper, `[EOS]` for Arista. NX-OS uses `%module-severity-MNEMONIC` not the IOS-XE `%FACILITY-SEVERITY-MNEMONIC` style; IOS-XR prefixes every message with `RP/<rack>/<slot>/CPU<n>:` plus process name; classic IOS is largely identical to IOS-XE for the common mnemonics but lacks some modern facilities. RFC 5424 facility / severity matrix plus vendor-specific message format catalogues plus common event pattern tables (interface, authentication, configuration change, routing adjacency) all live in `references/syslog-patterns.md`. Scoped to raw syslog data only (rsyslog / syslog-ng collectors, device console logs, SNMP-trap-receiver output); for SIEM-equipped environments (Splunk / ELK / QRadar / Graylog) use `siem-log-analysis`. Pairs with `siem-log-analysis` (companion sibling for SIEM-equipped cases), `graylog-log-investigation` (Graylog-platform sibling), `oncall-runbooks` (when investigation surfaces an active incident), `incident-response-network` (forensics-grade evidence preservation when investigation surfaces a confirmed security incident), `bash-defensive` (one-liner discipline), `utc-timestamps` (timestamp normalisation discipline), `secrets-hygiene` (do not paste full syslog messages bearing session tokens into shared reports). Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); `cli-reference.md` folded into body; `references/syslog-patterns.md` kept and extended with IOS / NX-OS / IOS-XR pattern variants at vault.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network Log Analysis

Investigation specialist for device-level network syslog analysis using raw log data without SIEM platforms. The procedure builds a forensic timeline from rsyslog / syslog-ng collector files, device console logs, and SNMP-trap-receiver output, using standard Unix tools (grep, awk, sort, sed). This skill is the no-SIEM arm of a three-skill log-analysis family: `siem-log-analysis` covers the SIEM-equipped case (Splunk / ELK / QRadar / Graylog); `graylog-log-investigation` covers general-purpose Graylog work (any log domain, not just network security); this skill covers the raw-syslog fallback where no SIEM platform is available.

Vendor message formats use `[IOS]`, `[IOS-XE]`, `[NX-OS]`, `[IOS-XR]`, `[JunOS]`, and `[EOS]` inline labels. The four Cisco platforms are broken out separately because syslog formats diverge: classic IOS is largely identical to IOS-XE for the common mnemonics but lacks some modern facilities; NX-OS uses `%module-severity-MNEMONIC` not the IOS-XE `%FACILITY-SEVERITY-MNEMONIC` style; IOS-XR prefixes every message with `RP/<rack>/<slot>/CPU<n>:` plus process name. JunOS and EOS each have their own structured formats.

See `references/syslog-patterns.md` for vendor-specific message format catalogues, the RFC 5424 facility / severity matrix, common Cisco mnemonics by subsystem, and side-by-side event-pattern tables across all six vendor lanes.

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-log-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the collector topology (rsyslog vs syslog-ng vs direct-to-file), per-team facility assignments, log-rotation cadence, and NTP synchronisation baseline before investigating. Only ask the user for information not already covered or specific to this investigation.

Before investigating, understand:

1. **Collector topology**
   - rsyslog, syslog-ng, or both? Hybrid (rsyslog forwarding to syslog-ng aggregator) is common.
   - Direct-to-file collection or relay-through-aggregator?
   - Where are log files actually stored (`/var/log/network/`, custom paths, NFS-mounted volume)?

2. **Log rotation cadence and retention**
   - Daily / hourly / size-triggered rotation?
   - Compression policy (`compress`, `delaycompress`) and which file ages out next?
   - Retention window (30 days, 90 days, 1 year)? Does it cover the investigation period?
   - Are rotated files moved to colder storage (S3, tape) after a cutoff?

3. **NTP synchronisation baseline**
   - Are all in-scope devices NTP-synchronised? `show ntp status` on each.
   - Known clock-skew outliers? (Capture the offset; apply at correlation time.)
   - Collector clock vs devices: same source? Cross-check.

## When to use

- **No SIEM available**: investigate network events using only raw syslog files on a centralised collector or individual device logs
- **Syslog infrastructure audit**: verify that rsyslog or syslog-ng is correctly receiving, routing, and retaining logs from all network devices in scope
- **Multi-device event correlation**: construct a unified timeline from separate per-device or per-facility log files using timestamp sorting and pattern matching
- **Anomaly investigation**: identify deviations from normal log volume, new message types, or authentication failure clusters without statistical query engines
- **Post-incident timeline reconstruction**: assemble a chronological evidence chain from raw logs after a network outage or security event
- **Log retention compliance**: verify that log rotation policies and retention periods meet organisational or regulatory requirements

## Do NOT use this skill for

- SIEM-equipped investigation (Splunk / ELK / QRadar / Graylog available); use `siem-log-analysis` instead
- General-purpose Graylog operations not network-security-scoped; use `graylog-log-investigation`
- Endpoint, application, or cloud-audit-trail log investigation (use the appropriate domain-specific skill)
- Building rsyslog or syslog-ng configurations from scratch (this skill assumes a collector exists; use the collector's own admin runbooks for setup)
- Real-time alerting on log patterns (this skill is investigation-time; alerting belongs in the SIEM, in `zabbix-templates-and-triage`, or in a `cron`-driven check script)
- Packet-level forensics (use `incident-response-network` for chain-of-custody discipline, packet capture, ARP / MAC preservation, containment verification)

## Prerequisites

- **Syslog collector access**: SSH or console access to the rsyslog / syslog-ng server with read permissions on log directories (typically `/var/log/` or custom paths defined in collector config).
- **Device CLI access**: read-only credentials for network devices to verify syslog forwarding configuration and NTP synchronisation status.
- **Unix tool availability**: `grep`, `awk`, `sort`, `sed`, `wc`, `date`, plus `zgrep` / `zcat` for compressed-rotated-log access. Standard on any Linux / BSD system. For multi-GB files, `LC_ALL=C grep` runs faster (single-byte locale). For multi-file analysis, GNU `parallel` helps when CPU is the bottleneck.
- **NTP verification**: confirm time synchronisation across all network devices and the syslog collector before multi-device correlation; skewed clocks corrupt timeline accuracy. `[IOS / IOS-XE / NX-OS]` `show ntp status` + `show ntp associations`; `[IOS-XR]` `show ntp status` (drops `ip` keyword consistently with other XR show commands); `[JunOS]` `show system ntp` + `show system ntp associations`; `[EOS]` `show ntp status` + `show ntp associations`.
- **Log file identification**: know the log file paths, naming conventions, and rotation schedule on the collector; rsyslog and syslog-ng route logs differently based on facility, severity, and source address.
- **Collector configuration cheatsheet** (folded from upstream `cli-reference.md`):
  - **rsyslog**: `rsyslogd -N1` validates config syntax. Main config `/etc/rsyslog.conf`; drop-ins `/etc/rsyslog.d/*.conf`. Input modules: `imudp` (port 514 UDP), `imtcp` (port 514 TCP), `imrelp` (reliable event logging protocol, typically port 2514). Facility-routing example: `local0.* /var/log/network/routers.log`. Severity-routing: `*.crit /var/log/network/critical.log`. Source-IP filter: `:fromhost-ip, isequal, "10.0.0.1" /var/log/network/core-rtr01.log`. File template preserves hostname: `template(name="NetworkLog" type="string" string="%TIMESTAMP% %HOSTNAME% %syslogtag%%msg%\n")`.
  - **syslog-ng**: `syslog-ng --syntax-only` validates. Main config `/etc/syslog-ng/syslog-ng.conf`. Source: `source s_network { udp(port(514)); tcp(port(514)); };`. Filter examples: `filter f_routers { facility(local0); };`, `filter f_critical { level(crit..emerg); };`, `filter f_cisco { match("%[A-Z]+-[0-7]-[A-Z_]+" value("MESSAGE")); };`. Pipe: `log { source(s_network); filter(f_routers); destination(d_routers); };`. Preserve hostname: `options { keep-hostname(yes); use-dns(no); };`.

## Procedure

Follow these six steps sequentially. The procedure builds a forensic timeline from raw syslog evidence through pattern recognition, correlation, anomaly detection, and chronological reconstruction. Each step produces artefacts that feed subsequent steps.

### Step 1: Log collection assessment

Verify that the syslog infrastructure is complete and healthy before analysing log content. Missing or misconfigured sources create blind spots that invalidate investigation conclusions.

**Syslog server configuration**: examine the collector configuration to understand how logs are routed:

- **[rsyslog]**: review `/etc/rsyslog.conf` and `/etc/rsyslog.d/*.conf` for input modules (imudp, imtcp, imrelp), facility / severity routing rules, and output file templates. Confirm that the file template includes the source hostname for multi-device disambiguation.
- **[syslog-ng]**: review `/etc/syslog-ng/syslog-ng.conf` for source definitions (network listeners), filter chains (facility, severity, host match), and destination paths. Verify that `keep-hostname(yes)` preserves the originating device hostname.

**Device syslog verification**: on each in-scope network device, confirm syslog forwarding is active and targeting the correct collector:

- **[IOS / IOS-XE]** `show logging` confirms logging host, trap level, facility; `show logging history` shows recent buffered severity counts. Configure with `logging host <ip> transport udp port 514`, `logging trap informational`, `logging facility local0`, `logging source-interface Loopback0`.
- **[NX-OS]** `show logging server` shows configured syslog destinations and severity. `show logging` shows local buffer. Configure with `logging server <ip> 6 use-vrf management facility local0`.
- **[IOS-XR]** `show logging` (no `ip` keyword) shows local buffer and server destinations. Configure with `logging <ip> vrf default severity info facility local0` under the `logging` config stanza.
- **[JunOS]** `show system syslog` shows configured host targets, facility filters, and structured-data enablement. Configure with `set system syslog host <ip> any info`, `set system syslog host <ip> facility-override local0`, and `set system syslog host <ip> structured-data` for parseable output.
- **[EOS]** `show logging` shows syslog server address, logging level, and protocol (UDP / TCP). Configure with `logging host <ip> 514 protocol udp`, `logging trap informational`, `logging facility local0`.

**NTP synchronisation check**: devices with NTP offset exceeding 1 second require timestamp correction before correlation. Run `show ntp status` (or vendor equivalent from Prerequisites).

**Log retention and rotation**: check logrotate configuration for retention period, compression, and file size limits. Confirm the retention window covers the investigation period. Standard network-log rotation: `daily`, `rotate 90`, `compress`, `delaycompress` (yesterday's log uncompressed for easy grep), `create 0640 syslog adm`. Missing rotated files indicate evidence gaps.

### Step 2: Syslog pattern recognition

Parse raw syslog messages into structured fields using vendor-specific format knowledge. Pattern recognition transforms unstructured text into correlatable evidence.

**Vendor message formats:**

- **[IOS / IOS-XE]**: `*timestamp: %FACILITY-SEVERITY-MNEMONIC: description`. Timestamp prefixed with `*` for non-synced clock, `.` for synced. Facility identifies the subsystem (LINEPROTO, OSPF, SEC), severity is 0-7 (RFC 5424), mnemonic is the event identifier. Classic IOS is largely identical to IOS-XE for the common mnemonics but lacks newer facilities (IOSXE_INFRA-*, APP_HOSTING-*, IOX-*).
- **[NX-OS]**: `YYYY MMM DD HH:MM:SS.ms hostname %module-severity-MNEMONIC: description`. Module names: ETHPORT, ETH_PORT_CHANNEL, NTP, OSPF, BGP, VPC, FEX (Nexus 7K), FCOE (storage), POAP (zero-touch). Examples: `%ETHPORT-5-IF_DOWN_LINK_FAILURE`, `%BGP-5-ADJCHANGE`, `%VPC-2-PEER_KEEPALIVE_RECV_FAIL`. Different from IOS-XE: `IF_DOWN_*` style mnemonics vs `LINK-3-UPDOWN`.
- **[IOS-XR]**: `RP/<rack>/<slot>/CPU<n>:<timestamp> <hostname> <process>[<pid>]: %FACILITY-SEVERITY-MNEMONIC : description`. Prefix `RP/0/RP0/CPU0:` (or `RP/0/RSP0/CPU0:`, `LC/0/0/CPU0:` for line cards) identifies the route processor and node. Process-name prefix matters: routing protocols log via `pim`, `bgp`, `ospf`, `isis` daemons each with its own PID. IOS-XR-specific facility prefixes: `PKT_INFRA-LINK-3-UPDOWN`, `ROUTING-BGP-5-ADJCHANGE`, `ISIS-6-ADJCHG`. Regex against IOS-XR logs MUST account for the `RP/0/RP0/CPU0:` prefix or the message body will not match.
- **[JunOS]**: `hostname process[pid]: EVENT_ID: message`. When `structured-data` is enabled, adds `[junos@2636 tag="value" ...]` pairs.
- **[EOS]**: `hostname AgentName: %FACILITY-SEVERITY-message`. Agent name identifies the subsystem (Ebra, Bgp, Ospf, Stp, Acl, Aaa, ConfigAgent, Lldp, Mlag, PimBidir).

**Severity classification**: extract the severity digit and map to RFC 5424 levels (0 Emergency through 7 Debug). Filter scope to severity 0-4 (Emergency through Warning) for operationally significant events. Use severity 5-7 only when lower severities lack context.

**Message frequency baseline**: count messages per facility per hour to establish normal volume:

```bash
awk '{print $1, $2, $3}' /var/log/network.log | sort | uniq -c | sort -rn
```

This produces a timestamp-grouped frequency table. Significant deviations from the hourly mean indicate events worth investigating.

**Facility-to-subsystem mapping**: map syslog facility codes to network subsystems using `references/syslog-patterns.md`. Facility local0-local7 assignments vary per organisation; check the rsyslog routing rules from Step 1 to decode local facility meanings. Common defaults: `[IOS / IOS-XE / NX-OS / IOS-XR / EOS]` default to `local7` (facility 23); `[JunOS]` defaults to per-process (e.g., `daemon` for routing).

### Step 3: Event correlation

Join events from multiple devices and log files by shared attributes to build investigation threads from isolated messages.

**Multi-device timeline via grep / awk / sort**: merge per-device log files into a single chronologically sorted stream:

```bash
cat /var/log/rtr*.log /var/log/sw*.log | sort -k1M -k2n -k3 > /tmp/merged-timeline.log
```

If log files use different timestamp formats, normalise first with awk before merging (see Step 5 for timestamp-normalisation details). For IOS-XR logs, strip the `RP/0/RP0/CPU0:` prefix before sorting if you need clean per-message-body comparison:

```bash
sed 's/^RP\/[0-9]\+\/[A-Z]\+[0-9]\+\/CPU[0-9]\+://' /var/log/iosxr-router.log > /tmp/iosxr-stripped.log
```

**Temporal clustering**: identify events within a configurable time window of a known trigger event. For precision, convert timestamps to epoch seconds and select events within the desired window using awk numeric comparison:

```bash
TARGET_EPOCH=$(date -d "2026-05-23 14:30:00" +%s)
WINDOW=300  # 5 minutes in seconds
awk -v target="$TARGET_EPOCH" -v win="$WINDOW" '{
  cmd = "date -d \""$1" "$2" "$3"\" +%s 2>/dev/null"
  cmd | getline epoch; close(cmd)
  if (epoch >= target-win && epoch <= target+win) print
}' network.log
```

(On BSD / macOS, substitute `date -jf "%b %d %H:%M:%S" "..." +%s`.)

**Causal chain detection**: network failures propagate through protocol dependencies in predictable patterns: interface flap then OSPF neighbour down then BGP route withdrawal then traffic reroute on alternate paths. Per-vendor causal-chain patterns:

- **[IOS / IOS-XE]** `LINK-3-UPDOWN` then `OSPF-5-ADJCHG` then `BGP-5-ADJCHANGE`
- **[NX-OS]** `%ETHPORT-5-IF_DOWN_LINK_FAILURE` then `%OSPF-5-ADJCHG` then `%BGP-5-ADJCHANGE`
- **[IOS-XR]** `%PKT_INFRA-LINK-3-UPDOWN` then `%ROUTING-OSPF-5-ADJCHG` then `%ROUTING-BGP-5-ADJCHANGE`
- **[JunOS]** `SNMP_TRAP_LINK_DOWN` then `RPD_OSPF_NBRDOWN` then `RPD_BGP_NEIGHBOR_STATE_CHANGED`
- **[EOS]** `%LINEPROTO-5-UPDOWN.*down` then `%OSPF-5-ADJCHG.*Down` then `%BGP-5-ADJCHANGE.*down`

Search for cascading patterns by extracting events matching each stage and verifying temporal sequence.

**SNMP trap correlation**: if the collector receives SNMP traps (via snmptrapd), correlate trap OIDs with syslog events. Interface linkDown traps (OID 1.3.6.1.6.3.1.1.5.3) should pair with the corresponding link-down syslog message from the same device. Mismatches indicate logging gaps.

### Step 4: Anomaly detection

Compare observed log patterns against baselines to surface deviations that warrant investigation. All detection uses grep, awk, and sort against raw log files.

**Baseline deviation**: compare current-day event counts per device against the rolling 7-day average. A current-day count exceeding twice the average signals a volume anomaly. Calculate per-facility counts to pinpoint which subsystem generates excess messages.

**New or unseen message types**: extract unique mnemonics from the investigation window and compare against a baseline file:

```bash
# Cisco IOS / IOS-XE / EOS mnemonics
grep -oP '%\S+-\d-\S+' /var/log/cisco.log | sort -u > /tmp/current.txt
comm -23 /tmp/current.txt /tmp/baseline-mnemonics.txt

# NX-OS mnemonics (module-severity-MNEMONIC variant)
grep -oP '%[A-Z_]+-\d-[A-Z_]+' /var/log/nxos.log | sort -u > /tmp/nxos-current.txt

# IOS-XR mnemonics (prefix-aware extraction)
grep -oP 'RP\/[0-9]+\/[A-Z]+[0-9]+\/CPU[0-9]+:[^%]+%[A-Z_]+-[A-Z_]+-\d-[A-Z_]+' /var/log/iosxr.log | grep -oP '%[A-Z_]+-[A-Z_]+-\d-[A-Z_]+' | sort -u > /tmp/iosxr-current.txt

# JunOS event IDs
grep -oP '[A-Z][A-Z_]+_[A-Z_]+' /var/log/junos.log | sort -u > /tmp/junos-current.txt
```

Mnemonics present in current but absent from baseline are first-seen events requiring classification.

**Authentication failure clustering**: extract auth messages and group by source IP using grep / awk / sort. Per-vendor patterns:

- **[IOS / IOS-XE]** `grep "SEC_LOGIN-4-LOGIN_FAILED" /var/log/cisco.log | grep -oP 'src=\K\S+' | sort | uniq -c | sort -rn`
- **[NX-OS]** `grep "AUTHPRIV-3-SYSTEM_MSG.*authentication failure" /var/log/nxos.log | grep -oP 'rhost=\K\S+' | sort | uniq -c | sort -rn`
- **[IOS-XR]** `grep "SECURITY-MGD_AUTH-3-LOGIN_FAILED" /var/log/iosxr.log | grep -oP 'from \K\S+' | sort | uniq -c | sort -rn`
- **[JunOS]** `grep "SSHD_LOGIN_FAILED" /var/log/junos.log | grep -oP 'from \K\S+' | sort | uniq -c | sort -rn`
- **[EOS]** `grep "SECURITY-4-LOGIN_FAILED" /var/log/eos.log | grep -oP 'from \K\S+' | sort | uniq -c | sort -rn`

Source IPs with failure counts exceeding 10 per hour warrant investigation as potential brute-force attempts.

**Config changes outside maintenance windows**: filter for config change messages and check timestamps against the approved schedule:

- **[IOS / IOS-XE]** `SYS-5-CONFIG_I`
- **[NX-OS]** `VSHD-5-VSHD_SYSLOG_CONFIG_I`
- **[IOS-XR]** `CONFIG-6-DB_COMMIT`
- **[JunOS]** `UI_COMMIT`
- **[EOS]** `SYS-5-CONFIG_I`

Changes outside the window require attribution: who changed what, and was it authorised.

**Login source IP anomalies**: extract management session source IPs and compare against the authorised management subnet list. IPs outside known ranges indicate unauthorised access attempts.

### Step 5: Timeline reconstruction

Assemble a definitive chronological event sequence from all evidence gathered in Steps 1-4. The timeline is the primary deliverable of forensic log analysis.

**Chronological assembly**: merge relevant events from multiple log sources into a single sorted output:

```bash
grep -h "PATTERN1\|PATTERN2\|PATTERN3" /var/log/*.log | sort -k1M -k2n -k3
```

Use `sort -s -k1M -k2n -k3` (stable sort) to preserve original order of events with identical timestamps.

**NTP-aware timestamp normalisation**: if devices log in different timezones or formats, normalise all timestamps to UTC epoch seconds before sorting:

```bash
# RFC 3164 (Mmm dd HH:MM:SS, no year) to epoch
awk '{
  cmd = "date -d \""$1" "$2" "$3"\" +%s 2>/dev/null"
  cmd | getline epoch; close(cmd)
  print epoch, $0
}' logfile.log | sort -n | cut -d' ' -f2-

# RFC 5424 ISO 8601 sort
sort -t'T' -k1 rfc5424.log
```

Apply the NTP offset correction from Step 1 to events from devices with known clock drift. For BSD / macOS, use `date -jf "%b %d %H:%M:%S" "..." +%s` instead of `date -d`. Cross-reference `utc-timestamps` skill for the UTC-everywhere discipline.

**Event-to-impact mapping**: for each significant event in the timeline, annotate the user-visible impact:

1. Identify the event (e.g., `OSPF-5-ADJCHG neighbour down`)
2. Determine the network impact (loss of redundant path)
3. Map to the user symptom (degraded connectivity or failover latency)

**Root cause ordering**: walk the timeline backward from the user-reported symptom to the earliest causal event. The root cause is the first event that, if prevented, would have prevented all downstream effects. Document the causal chain with event references for each link.

### Step 6: Report

Compile all findings into a structured deliverable. Present the event timeline from Step 5 as the central artefact; annotate each entry with its classification (root cause, contributing factor, symptom, or informational). Summarise anomaly findings from Step 4 with counts and severity assessments. Document correlation chains from Step 3 with supporting evidence. State the root cause assessment with confidence level and the supporting evidence chain. Include an integrity section listing evidence gaps that limit conclusions.

When the disposition implies a security incident, hand off to `incident-response-network` for forensics-grade evidence preservation (ARP / MAC tables, packet captures, hash-verified file collection) and to `oncall-runbooks` / `incident-response-lifecycle` for the incident management wrapper.

## Threshold tables

### Log volume anomaly thresholds

| Metric | Normal | Warning (>1.5x) | Alert (>2x) | Critical (>3x) |
|--------|--------|-----------------|-------------|-----------------|
| Messages per hour (per device) | Baseline plus / minus 50% | 1.5-2x baseline | 2-3x baseline | More than 3x baseline |
| Unique mnemonics per day | Baseline count | 1-3 new mnemonics | 4-10 new mnemonics | More than 10 new mnemonics |
| Auth failure events (per source IP) | Up to 3 / hour | 4-10 / hour | 11-50 / hour | More than 50 / hour |
| Config change events (per device) | Up to 2 / day during windows | Any outside window | 3 or more outside window | More than 5 outside window |
| SNMP trap rate (per device) | Up to 5 / hour | 6-20 / hour | 21-100 / hour | More than 100 / hour |

### Syslog severity response matrix

| Severity | RFC 5424 Level | Investigation Action |
|----------|---------------|---------------------|
| 0 Emergency | System unusable | Immediate investigation, all-hands |
| 1 Alert | Immediate action needed | Priority investigation within 15 minutes |
| 2 Critical | Critical conditions | Investigation within 1 hour |
| 3 Error | Error conditions | Investigation within 4 hours |
| 4 Warning | Warning conditions | Review within 24 hours |
| 5 Notice | Normal but significant | Log for trending, review weekly |
| 6 Informational | Informational | Baseline data, no action |
| 7 Debug | Debug-level | Exclude from standard analysis |

### Correlation confidence levels

| Confidence | Criteria | Action |
|------------|----------|--------|
| **Confirmed** | 3 or more events across 2 or more devices with matching attributes and less than 60s window | Treat as established fact in report |
| **Probable** | 2 correlated events or single-device chain with supporting evidence | Include in report with qualification |
| **Possible** | Single event or loose time correlation (more than 5 min window) | Note as hypothesis, do not assert as finding |

## Decision trees

### Investigation entry point

```
Investigation trigger received
├── Reported outage with known time window?
│   ├── Yes → Start at Step 3 (Correlation) scoped to window
│   │   └── Expand to Step 2 (Pattern Recognition) if correlation yields insufficient events
│   └── No → Start at Step 1 (Log Collection Assessment)
│
├── Anomaly detected in monitoring (no log detail)?
│   ├── Time of anomaly known? → Start at Step 4 (Anomaly Detection)
│   │   └── Confirm with Step 2 pattern analysis
│   └── Time unknown? → Full procedure Steps 1-6
│
├── Post-incident review (incident already resolved)?
│   └── Start at Step 1 → Full procedure for completeness
│       └── Focus Step 5 (Timeline) for the deliverable
│
└── Compliance audit of syslog infrastructure?
    └── Steps 1 and 2 only (Collection + Pattern verification)
```

### Anomaly classification

```
Anomaly identified in Step 4
├── Volume anomaly (message count deviation)?
│   ├── Single device affected?
│   │   ├── Device reload or maintenance → Expected, document
│   │   └── No maintenance → Investigate device health
│   └── Multiple devices affected?
│       ├── Shared upstream link event? → Correlate in Step 3
│       └── Independent spikes? → Investigate each separately
│
├── New mnemonic or event type?
│   ├── Matches known firmware upgrade pattern? → Expected
│   ├── Security-related facility (SEC, AUTH, SECURITY-MGD_AUTH)? → Priority review
│   └── Informational facility? → Add to baseline if benign
│
├── Authentication anomaly?
│   ├── Single source IP, many targets? → Brute-force scanning
│   ├── Many source IPs, single target? → Distributed attack
│   └── Single source, single target? → Credential issue
│
└── Configuration change outside window?
    ├── Attributed to known admin? → Verify authorisation
    ├── Attributed to unknown user? → Security incident
    └── No attribution available? → Escalate immediately
```

## Report template

```
NETWORK LOG ANALYSIS REPORT
==============================
Report ID:            [unique identifier]
Investigation Trigger: [outage report / anomaly alert / compliance audit]
Investigation Window: [start timestamp] to [end timestamp] (UTC)
Analyst:              [name / identifier]
Log Sources:          [collector hostname, device count, log file paths]

SUMMARY:
- Investigation type: [outage / security / compliance / anomaly]
- Root cause confidence: [Confirmed / Probable / Possible]
- Devices involved: [count and hostnames]
- Evidence gaps: [list any missing log sources or time gaps]

LOG COLLECTION STATUS (Step 1):
- Syslog collector: [rsyslog / syslog-ng, config path]
- Devices forwarding: [count] / [total expected]
- NTP synchronised: [count] / [total], max offset: [ms]
- Retention coverage: [days available] vs [days needed]

EVENT TIMELINE (Step 5):
| # | Timestamp (UTC) | Device | Facility-Sev | Mnemonic / Event | Message Summary | Classification |
|---|-----------------|--------|-------------|----------------|-----------------|----------------|
| 1 | [time] | [host] | [fac-sev] | [mnemonic] | [summary] | [root cause / contributing / symptom] |

ANOMALIES DETECTED (Step 4):
| # | Type | Device(s) | Description | Severity |
|---|------|-----------|-------------|----------|

CORRELATION CHAINS (Step 3):
- Chain 1: [event A] then [event B] then [event C]
  Confidence: [Confirmed / Probable / Possible]

ROOT CAUSE ASSESSMENT:
- Root cause: [description]
- Confidence: [level with justification]
- Causal chain: [first event then ... then user impact]

EVIDENCE INTEGRITY:
- Gaps: [missing devices, time periods, rotated files]
- NTP corrections applied: [list any offset adjustments]

RECOMMENDATIONS:
1. [immediate, e.g., fix syslog forwarding gap, address root cause]
2. [short-term, e.g., add missing devices to collector, tune rotation]
3. [long-term, e.g., improve NTP architecture, add log redundancy]
```

## Common failure modes

### Missing device logs on collector

**Symptom:** expected device logs are absent from syslog collector files despite the device being configured to forward syslog.

**Diagnosis:** verify syslog configuration on the device (see Step 1 commands). Check network path; firewall rules may block UDP 514 or TCP 514 between the device and collector. On the collector, check rsyslog / syslog-ng for dropped messages: `rsyslogd` logs input errors to its own syslog facility. Verify the collector is listening on the expected port with `ss -ulnp | grep 514`.

**Resolution:** fix the forwarding path (device config, network ACLs, collector listener). Generate a test message from the device and confirm receipt. Document the gap period in the investigation report.

### Timestamp format inconsistencies

**Symptom:** merged log files produce an unsortable timeline because timestamp formats differ (RFC 3164 vs RFC 5424 vs device-specific).

**Diagnosis:** inspect the first 10 lines of each source. RFC 3164 uses `Mmm dd HH:MM:SS` (no year); RFC 5424 uses ISO 8601 with timezone. NX-OS uses `YYYY MMM DD HH:MM:SS.ms` (year present, milliseconds). IOS-XR uses ISO-8601-style with the `RP/0/RP0/CPU0:` prefix in front.

**Resolution:** write an awk normaliser for each format (see Step 5 examples). Add the year to RFC 3164 timestamps based on file modification date or logrotate naming convention.

### Log rotation destroyed evidence

**Symptom:** investigation period extends beyond the oldest available log file.

**Diagnosis:** check `/etc/logrotate.d/` for retention and compression settings. Look for compressed archives (`.gz`, `.bz2`, `.xz`).

**Resolution:** search within compressed files using `zgrep` or `zcat | grep`. If data is permanently lost, document the gap and state which conclusions are limited by missing evidence.

### High log volume makes grep impractical

**Symptom:** multi-GB log files make interactive grep analysis impractically slow.

**Resolution:** narrow to the investigation window with a date-based grep first, redirect to a working file, then apply detailed analysis to the smaller extract. Use `LC_ALL=C grep` for faster processing (single-byte locale). Consider GNU parallel for multi-file analysis.

### IOS-XR prefix breaks regex

**Symptom:** patterns that work against `[IOS / IOS-XE]` logs return zero matches against `[IOS-XR]` logs even though the underlying event is present.

**Diagnosis:** IOS-XR prefixes every message with `RP/<rack>/<slot>/CPU<n>:` plus process name and PID. A regex anchored at start-of-line on `%FACILITY-` will not match because the line starts with `RP/0/RP0/CPU0:`. Also: IOS-XR facility prefixes differ (`PKT_INFRA-LINK-` not `LINK-`; `ROUTING-BGP-` not `BGP-`).

**Resolution:** either strip the prefix first (`sed 's/^RP\/[0-9]\+\/[A-Z]\+[0-9]\+\/CPU[0-9]\+://'`) or write the regex to skip past it (`grep -oP 'RP\/[0-9]+\/[A-Z]+[0-9]+\/CPU[0-9]+:.*\K%PKT_INFRA-LINK-3-UPDOWN.*'`). Document the prefix discipline in the investigation report so other analysts know.

### NX-OS module facility differs from IOS-XE

**Symptom:** searches for `LINK-3-UPDOWN` return zero matches against NX-OS logs even though interface flap events are clearly happening.

**Diagnosis:** NX-OS uses module-name-based mnemonics: `%ETHPORT-5-IF_DOWN_LINK_FAILURE`, `%ETHPORT-5-IF_UP`, `%ETH_PORT_CHANNEL-5-PORT_DOWN`. The `LINK-3-UPDOWN` mnemonic does not exist in NX-OS.

**Resolution:** use NX-OS-specific patterns: `ETHPORT-.*IF_DOWN`, `ETHPORT-.*IF_UP`, `ETH_PORT_CHANNEL-.*PORT_DOWN`. Cross-reference `references/syslog-patterns.md` for the full NX-OS module catalogue.

## Cross-references

- `siem-log-analysis`: SIEM-equipped companion (Splunk / ELK / QRadar / Graylog). Use when a SIEM platform is available; the diagnostic reasoning is the same, only the query interface differs.
- `graylog-log-investigation`: general-purpose Graylog skill (any log domain). Use when the work is Graylog operations, query construction, or pipeline tuning that is not network-security-scoped.
- `oncall-runbooks`: when log analysis surfaces an active incident, the 9-section runbook structure is the receiving discipline. Every detection-rule alert should reference a runbook URL.
- `incident-response-network`: forensics-grade evidence preservation arm. When a True Positive with Critical or High severity is identified, hand off to capture ARP / MAC / CAM tables, packet captures, flow records, and routing snapshots before volatile evidence ages out.
- `incident-response-lifecycle`: NIST 800-61 process layer. Wraps incident-response-network for severity classification, role assignment, escalation, communications, and post-mortem facilitation.
- `bgp-analysis`, `igp-routing-analysis`: when log analysis surfaces routing-protocol anomalies (BGP flap, OSPF adjacency loss, IS-IS LSPDB issue, EIGRP stuck-in-active), load the appropriate protocol-depth specialist for diagnosis.
- `acl-rule-analysis`: when log analysis surfaces firewall / ACL deny patterns, the rule-ordering / shadowed-rule analysis lives here.
- `bash-defensive`: every one-liner in this skill that ends up in a script needs the defensive-bash discipline (set -Eeuo pipefail, quoted variables, trap-based cleanup).
- `platform-quirks-escape`: when an awk one-liner grows into a 50-line script with macOS-vs-GNU date / sed handling, escape to Python.
- `systematic-debugging`: raw log evidence is often the Phase 1 boundary evidence in a wider debugging loop. Use the four-phase loop (collect, hypothesise, test, validate) rather than chasing a single grep.
- `secrets-hygiene`: syslog messages can contain session tokens, API keys, IPs that disclose internal topology. Audit before pasting into shared reports; redact where appropriate.
- `utc-timestamps`: all timeline timestamps in reports must be UTC. The NTP-aware normalisation step in this skill is the operational mechanism.
- `cite-sources`: when an investigation report references external indicators (CVEs, vendor advisories, threat-intel feeds), cite with date and identifier.
- `completion-gate` Layer 3: post-investigation verification (the suspected pattern should have stopped after fix; re-run the grep post-fix to confirm).
- `humanise-comms`: investigation reports go to mixed audiences (network engineers, security analysts, executives). Match the audience.
- `multi-vendor-network-ops`: umbrella entry-point skill; the 9-element response contract applies on any production-impacting action recommended on the basis of log evidence.

## Red flags

- **`grep` on rotated log without checking the `.gz` tail.** A `grep` against `/var/log/network.log` misses anything that already rotated. Always check for `*.log.1`, `*.log.2.gz`, `*.log.3.gz` in the same directory; use `zgrep` for the compressed ones.
- **`awk` on a multi-line stack trace without record-separator change.** Default awk record-separator is newline; stack traces span multiple lines. Set `RS=""` (paragraph mode) or use a known delimiter to keep multi-line events together.
- **Sort timeline before timestamp normalisation to UTC.** Sorting raw timestamps from devices in different timezones produces an order that is locally correct on each device but globally wrong. Always normalise to UTC epoch first.
- **Trust device-local log buffer for events older than the buffer ring.** `show logging` on a device returns only what's in its local ring buffer (typically a few thousand lines). Older events are gone unless they reached the central collector. For anything more than minutes old, query the collector.
- **`tail -f` on an NFS-mounted log file.** NFS read-ahead caching can delay or skip updates. Either copy the file to local disk first, or use a syslog-receiver-side stream (e.g., `journalctl -fu rsyslog`).
- **Regex against IOS-XR log without `RP/0/RP0/CPU0:` prefix awareness.** Start-of-line anchors won't match (the line starts with the RP prefix). Strip the prefix first or write the regex to skip past it.
- **Treat NX-OS facility code as identical to IOS-XE.** `LINK-3-UPDOWN` does not exist on NX-OS; the equivalent is `%ETHPORT-5-IF_DOWN_LINK_FAILURE` or `%ETHPORT-5-IF_UP`. Cross-reference the per-vendor catalogue in `references/syslog-patterns.md`.
- **Paste full syslog message bearing session token into shared report.** Syslog messages can contain session IDs, API keys in URL parameters, IP addresses that disclose internal topology. Audit and redact before sharing.
- **Build a "real-time" alert from a polling grep loop.** A `while true; do grep ...; sleep 60; done` loop misses events between polls and burns CPU. Use the SIEM or `zabbix-templates-and-triage` for real-time alerting; this skill is investigation-time.
- **Recommend containment from this skill.** This is an investigation skill, not a response skill. Containment recommendations (block this IP, null-route this prefix) need a change ticket, peer review, and execution discipline; hand off to `incident-response-network` and the appropriate change-management skills.

## Bottom line

Raw-syslog network log analysis is a six-step procedure: assess collection, recognise patterns, correlate across devices, detect anomalies, reconstruct timeline, report. Diagnostic reasoning is platform-independent; only message-format syntax diverges. Six vendor lanes covered: classic IOS, IOS-XE, NX-OS, IOS-XR, JunOS, EOS. Every multi-device correlation needs UTC-normalised timestamps; every regex against IOS-XR needs prefix-awareness; every NX-OS search needs module-name-based mnemonics. Hand off forensics-grade evidence preservation to `incident-response-network`; hand off NIST 800-61 process management to `incident-response-lifecycle`. When a SIEM exists, switch to `siem-log-analysis` for the same reasoning at index-time scale.
