# Cacti operations: install, poller tuning, Boost, Thold, plugins, pitfalls

Standing up Cacti, scaling the poller, adding threshold alerting and plugins, and the traps that produce gappy graphs.

## Installation and sizing

- Run the web install wizard after deploying the LAMP stack; it validates PHP modules, MySQL/MariaDB settings, RRDtool, and net-snmp.
- **MySQL/MariaDB tuning is required, not optional.** Cacti's install check flags the InnoDB buffer-pool size, `max_heap_table_size`, `tmp_table_size`, `join_buffer_size`, and the recommended collation (utf8mb4). Ignoring the flags causes slow polling and UI timeouts at scale.
- Size by data-source count: a few hundred data sources run on cmd.php; thousands need Spine and tuning.

## Poller tuning

- **Switch cmd.php to Spine** as the first scaling step. Install the Spine package and select it as the poller type.
- **Concurrent poller processes** and **threads per process** (Spine) set the parallelism. Raise them until a cycle comfortably finishes inside the interval, watching CPU and SNMP timeouts.
- **Poller interval**: 300 seconds (5 minutes) by default. It can be lowered to 60 seconds for finer resolution, but only if the cycle finishes well inside 60 seconds and the RRAs are created for that step.
- **Watch for poller overrun**: the log reports cycle duration. If it approaches the interval, the next cycle slips and RRD gaps appear. Fix by adding parallelism, switching to Spine, reducing per-device OIDs, or lengthening the interval.

## The Boost plugin

On large installs the per-cycle RRD writes become a disk-I/O bottleneck. The Boost plugin batches updates: the poller writes into a Boost buffer table in the database, and Boost flushes them to the RRD files in bulk on a schedule. This trades a little query freshness for a large reduction in disk I/O, and is effectively required on large deployments.

## Thold threshold alerting

Core Cacti graphs and polls but does not alert; the **Thold** (thresholds) plugin adds alerting on data sources:

- **High / low threshold**: alert when a value crosses a fixed bound (interface utilisation above 90%, free disk below 10%).
- **Baseline threshold**: alert when a value deviates from a learned baseline by a percentage.
- **Time-based threshold**: evaluate against an average over a window rather than an instant.
- **Notification**: email, and (via the Syslog plugin or a command) syslog or external systems. Thold supports re-alert intervals and acknowledgement.

## The plugin ecosystem

Cacti's plugin architecture (now part of core) adds capability:

- **Thold**: threshold alerting (above).
- **Weathermap**: network weather maps with live link-utilisation colouring.
- **Monitor**: an at-a-glance up/down status dashboard.
- **Syslog**: receive and search syslog, correlate with device state.
- **FlowView**: NetFlow/sFlow collection and reporting.
- **Settings**: shared notification and mail configuration used by other plugins.

## Common pitfalls

1. **cmd.php at Spine scale**: poller overrun and RRD gaps. Switch to Spine and tune parallelism.
2. **Poller overrun**: collection exceeds the interval; the symptom is regular gaps in every graph at the same times.
3. **Changing an RRA after creation**: existing history does not re-shape. Plan the RRA structure up front; a change means rebuilding the RRD files.
4. **Hand-building graphs**: use data queries and host templates instead, or the install becomes unmaintainable.
5. **No Boost on a large install**: disk I/O caps the data-source count. Enable Boost.
6. **Skipping MySQL tuning**: the single most common cause of a slow Cacti; apply the settings the install check flags.
7. **A data query that creates no graphs**: usually a wrong SNMP community/credential, an unreachable device, or a query XML mismatch; verify SNMP reachability first.
8. **Credentials inline in a script sensor**: keep SNMPv3 credentials and device passwords in the secret store (`secrets-hygiene`), not in committed scripts.

## Version notes (1.2.x)

- Current stable is the 1.2.x line (1.2.31 as of mid-2026), a long-running maintenance series.
- **PHP 8.1 is the minimum from 1.2.31**; align the PHP runtime before upgrading.
- 1.2 introduced **remote data collectors** for distributed polling and an automation API for templated device onboarding.
- The 1.2.31 release notes emphasise security fixes; keep current, since Cacti has historically been a target for web-application vulnerabilities (treat the web UI as sensitive and restrict access).
