# Cacti architecture: LAMP stack, RRDtool, the poller, and remote collectors

How Cacti is built, how RRDtool stores the data, how the poller collects it, and how polling distributes across sites.

## The LAMP stack

Cacti is a PHP web application backed by a relational database, fronted by a web server, collecting via SNMP and storing in RRDtool. The current stable line is 1.2.x (1.2.31 as of mid-2026).

| Component | Role | Notes |
|---|---|---|
| PHP | Application and the cmd.php poller | Minimum PHP 8.1 from 1.2.31 |
| MySQL / MariaDB | Configuration, templates, poller state, Boost buffer | Cacti ships recommended my.cnf settings the installer checks |
| Apache / nginx / IIS | Serves the web UI | Any PHP-capable web server |
| net-snmp | SNMP polling of devices | snmpget / snmpbulkwalk under the hood |
| RRDtool | Time-series storage and graph rendering | The round-robin database engine |

The MySQL/MariaDB tuning is not optional at scale: Cacti's install validation flags the required settings (buffer pool, max heap, tmp table sizes, collation), and ignoring them causes slow polling and UI timeouts.

## RRDtool data storage

### Round-robin databases

RRDtool stores each metric stream in a fixed-size RRD file. Because the file is fixed-size, it never grows: older data is consolidated and overwritten in a ring. The structure is defined at creation and cannot be reshaped in place.

### Data sources

A data source (DS) is one metric inside an RRD: a name, a type (GAUGE for a point-in-time value such as temperature, COUNTER for an ever-increasing value such as interface octets, DERIVE, ABSOLUTE), a heartbeat (how long before a missing update becomes unknown), and min/max bounds.

### Round-robin archives and consolidation

A round-robin archive (RRA) defines a resolution and a retention plus a consolidation function:

- **AVERAGE**: the mean over the consolidation window (the usual choice for traffic).
- **MIN** / **MAX**: the low/high in the window (peaks).
- **LAST**: the final value in the window.

A typical Cacti RRD carries several RRAs: full resolution for recent data, then progressively coarser averages for daily, weekly, monthly, and yearly views. Changing an RRA after creation does not re-shape existing history; the file must be rebuilt or recreated.

## The poller

### cmd.php versus Spine

- **cmd.php**: the PHP-based poller, the default. Adequate for small installs (a few hundred data sources).
- **Spine**: a C multithreaded poller (a separate package). Built for scale: many concurrent threads and processes poll devices in parallel. Switching to Spine is the primary scaling lever.

### Scheduling and the cycle

The poller runs from cron or a systemd timer, every 300 seconds by default. Each cycle:

```
1. The scheduler triggers the poller (cron / systemd timer, every 300s)
2. The poller collects data (SNMP, script, script server, data query)
3. The poller writes updates into the RRD files (or the Boost buffer)
4. Graphs render from the RRD files on demand
```

The collection must finish inside the interval. If a cycle takes longer than 300 seconds (poller overrun), the next cycle is delayed and RRD gaps appear. Tune the concurrent-process and thread counts, switch to Spine, or lengthen the interval to fix overrun.

## Remote data collectors

From 1.2, Cacti supports distributed polling. A remote data collector is a separate Cacti poller at a site that polls the local devices and reports back to the main server, which holds the central database and UI. This cuts WAN bandwidth for SNMP polling, keeps polling local to each site, and survives a WAN partition, mirroring the distributed-polling pattern of other NMS platforms.
