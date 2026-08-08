---
name: cacti-network-monitoring
description: "Use for Cacti configuration, operations, and tuning: the open-source RRDtool-based SNMP graphing and polling platform. Covers the LAMP architecture (PHP 8.1+, MySQL/MariaDB, Apache or nginx, net-snmp, RRDtool), RRDtool data storage (round-robin databases, data sources, round-robin archives, consolidation functions AVERAGE/MIN/MAX/LAST), the poller (cmd.php PHP poller vs the Spine C multithreaded poller, cron or systemd-timer scheduling, the 300-second default poller interval, poller-overrun avoidance), distributed polling via remote data collectors (1.2.x), the template model (data input methods, data templates, graph templates, host/device templates, data queries for SNMP interface discovery, CDEF RPN transforms, GPRINT legends, graph trees and aggregates), threshold alerting via the Thold plugin (high/low/baseline/time-based), the plugin architecture (Thold, Weathermap, Monitor, Syslog, FlowView), installation and MySQL/MariaDB sizing, the Boost plugin for batching RRD writes at scale, and common pitfalls (RRD gaps, poller overrun, RRA-change rebuilds). References architecture.md, templates-and-graphing.md, operations.md. Triggers include \"Cacti\", \"RRDtool\", \"RRD\", \"Spine poller\", \"cmd.php\", \"Cacti graph template\", \"data template\", \"data query\", \"CDEF\", \"GPRINT\", \"Boost plugin\", \"Thold\", \"Weathermap\", \"Cacti poller\", \"poller overrun\", \"remote data collector\", \"round robin database\". For vendor-neutral network-monitoring DESIGN, paradigm choice, and platform selection see network-monitoring-selection; for PRTG sensor monitoring see prtg-network-monitoring; for Kentik flow analytics see kentik-network-monitoring; for the SNMPv3 credentials Cacti uses see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Cacti network monitoring

> **Skill marker**: When applying this skill, begin your reply with `[skill: cacti-network-monitoring]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Cacti configuration, operations, and tuning. It assumes the design decision (Cacti is the right platform: open-source, RRDtool-based SNMP graphing) has already been made; for that decision see `network-monitoring-selection`. The depth here is the poller, the template-and-data-query model that makes Cacti scale, and the operational discipline that keeps the round-robin databases gap-free.

## When to use

- Installing or sizing Cacti: the LAMP stack, MySQL/MariaDB tuning, the poller schedule.
- Choosing and tuning the poller (cmd.php for small installs, Spine for scale) and avoiding poller overrun.
- Building data templates, graph templates, host templates, and SNMP data queries for interface discovery.
- Writing CDEF transforms and GPRINT legends, organising graph trees, and building aggregate graphs.
- Configuring threshold alerting with the Thold plugin, or adding plugins (Weathermap, Monitor, Syslog).
- Scaling with the Boost plugin (batched RRD writes) or remote data collectors (distributed polling).
- Diagnosing RRD gaps, poller overrun, or a data query that creates no graphs.

## When not to use

- **Deciding whether Cacti is the right platform**, choosing a monitoring paradigm, or comparing Cacti against PRTG, Kentik, LibreNMS, or Zabbix: `network-monitoring-selection` owns the design and the cross-platform comparison.
- **PRTG sensor monitoring**: `prtg-network-monitoring`. **Kentik flow analytics, DDoS, and BGP**: `kentik-network-monitoring`.
- **Storing SNMPv3 credentials or device passwords**: `secrets-hygiene` owns the secret-store discipline; never inline a credential in a script or a committed config.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture | LAMP stack, RRDtool storage model, the poller (cmd.php vs Spine), scheduling, remote data collectors | `references/architecture.md` |
| Templates + graphing | data input methods, data/graph/host templates, data queries, CDEF, GPRINT, graph trees, aggregates | `references/templates-and-graphing.md` |
| Operations | installation and MySQL sizing, poller tuning, Boost plugin, Thold threshold alerting, plugin architecture, pitfalls, version notes | `references/operations.md` |

## Core model (condensed)

**RRDtool is the data store, and its shape is fixed at creation.** Cacti writes time-series into round-robin databases (RRD files): each has data sources (the metrics) and round-robin archives (RRAs) that define the resolution and retention, consolidated by AVERAGE/MIN/MAX/LAST. The RRA structure is set when the RRD is created; changing the resolution or retention later means rebuilding or recreating the file, not editing it.

**The poller collects on a fixed cycle; collection must finish inside the interval.** A cron job or systemd timer runs the poller every 300 seconds by default. The poller gathers data (SNMP, script, or data query) and updates the RRD files. If collection takes longer than the interval (poller overrun), data gaps appear. `cmd.php` is the PHP poller for small installs; **Spine** is the C multithreaded poller for scale, and switching to Spine plus tuning the concurrent-process and thread counts is the primary scaling lever.

**Templates are what make Cacti repeatable, and data queries are what make it dynamic.** A data template defines what to collect; a graph template defines how to render it; a host template bundles them for a device type. A data query (for example the SNMP interface query) walks a table such as ifTable to discover entities and create a graph per interface automatically, so you template once and apply to many devices.

**CDEF transforms and GPRINT formats are the presentation layer.** A CDEF is an RPN expression that transforms a data source (bits to bytes, summing inbound and outbound); GPRINT formats the legend (LAST, AVERAGE, MAX). These shape the graph without changing what is stored.

**Alerting and scale are plugins, not core.** Core Cacti graphs and polls; the Thold plugin adds threshold alerting (high/low, baseline, time-based) and the Boost plugin batches RRD writes to cut disk I/O on large installs. Remote data collectors (1.2.x) distribute polling across sites.

**Anti-patterns:** running cmd.php at a scale that needs Spine (poller overrun and RRD gaps); a poller cycle that exceeds the interval; changing an RRA expecting existing history to adapt (it will not); building graphs by hand instead of via data queries and templates; large installs with no Boost plugin (disk I/O bottleneck); SNMP credentials inline in a script instead of the secret store.

## Reference router

| Need | Load |
|---|---|
| LAMP component versions, RRDtool data sources/RRAs/consolidation, the poller cmd.php vs Spine, cron/systemd scheduling, the poller cycle, remote data collectors | `references/architecture.md` |
| Data input methods, data templates, graph templates, host/device templates, SNMP data queries, CDEF RPN, GPRINT, graph trees, aggregate graphs | `references/templates-and-graphing.md` |
| Installation and MySQL/MariaDB sizing, poller tuning (threads, concurrent processes, interval), the Boost plugin, Thold threshold alerting, the plugin ecosystem, common pitfalls, 1.2.x version notes | `references/operations.md` |

## Cross-references

- `network-monitoring-selection`: the vendor-neutral design and platform-selection umbrella. Decides whether Cacti fits; this skill builds it. Reciprocal reference.
- `prtg-network-monitoring`, `kentik-network-monitoring`: sibling vendor skills for the other platforms in the family.
- `zabbix-templates-and-triage`: the alternative open-source NMS with native alerting; consult when comparing template-driven Zabbix against RRDtool-based Cacti.
- `grafana-dashboards`: Grafana can read RRD or a Cacti data source for richer dashboards over Cacti's graphs.
- `secrets-hygiene`: SNMPv3 credentials and device passwords live in the secret store, never inline in a Cacti script or committed config.
- `multi-vendor-network-ops`: diagnose-first operations that consume Cacti graphs and threshold alerts during a wider production network change.

## Red flags

- About to run cmd.php at a device count that needs Spine, guaranteeing poller overrun and RRD gaps.
- About to schedule a poller cycle whose collection time exceeds the interval.
- About to change an RRA and expect existing RRD history to re-shape (it will not; the file must be rebuilt).
- About to build graphs one by one instead of using data queries and host templates.
- About to run a large install with no Boost plugin and let disk I/O become the bottleneck.
- About to skip MySQL/MariaDB tuning that Cacti's own install check flags as required.
- About to put SNMPv3 credentials inline in a script sensor instead of the secret store.

## Bottom line

Cacti stores time-series in RRDtool round-robin databases whose resolution and retention are fixed at creation, polls them on a fixed cycle that must finish inside the interval, and scales by switching cmd.php for Spine and adding the Boost plugin. Template once and let data queries discover entities, transform with CDEF and format with GPRINT, and add Thold for alerting and remote data collectors for distributed polling. Bring the platform decision from `network-monitoring-selection`, and keep credentials in the secret store.
