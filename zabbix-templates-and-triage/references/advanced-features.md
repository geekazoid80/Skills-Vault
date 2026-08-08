# Zabbix Advanced Features Reference

Covers topics absent from the main SKILL.md: HA cluster, security hardening, preprocessing depth,
full trigger function set, actions/escalations, push monitoring, TimescaleDB initialisation SQL,
PostgreSQL/MySQL tuning, LLD custom JSON and lifetime, dashboards/SLA/maintenance, and internal-item
health thresholds.

---

## High Availability (Zabbix 6.0+)

Native active-passive HA. Multiple server nodes share one database; only the active node processes
data. Standby promotes automatically on failure.

```ini
HANodeName=zabbix-node-01    # unique name per node; shared PostgreSQL or MySQL required
```

---

## Security Hardening

### TLS between components

```ini
TLSConnect=cert
TLSAccept=cert
TLSCAFile=/etc/zabbix/ca.crt
TLSCertFile=/etc/zabbix/agent.crt
TLSKeyFile=/etc/zabbix/agent.key
```

Use `TLSConnect=psk` + `TLSPSKIdentity` + `TLSPSKFile` for the simpler PSK path.

### Agent and API hardening

```ini
AllowRoot=0              # run as unprivileged user
Server=10.0.0.5          # restrict to specific IPs; never 0.0.0.0
HostMetadata=linux-prod  # auto-registration group rules; do not embed secrets here
```

- Restrict `/api_jsonrpc.php` to trusted ranges at the reverse proxy.
- Assign host-group-scoped RBAC roles; avoid "Super Admin" for service accounts.
- Frontend headers: `X-Frame-Options: SAMEORIGIN`, `Strict-Transport-Security`,
  `Content-Security-Policy: default-src 'self'`.

---

## Preprocessing Pipeline Depth

Each item supports up to 20 steps in order. Categories:

| Category | Preprocessors |
|----------|---------------|
| Text | Regex extract, trim, custom multiplier |
| Structured data | JSONPath, XML XPath, CSV-to-JSON |
| JavaScript | ECMAScript 5.1 in V8 engine |
| Prometheus | Pattern extraction from exposition format |
| Validation | Check not-supported, discard unchanged, discard unchanged with heartbeat |

**JavaScript example:**
```javascript
var data = JSON.parse(value);
return (data.used / data.total * 100).toFixed(2);
```

**Discard unchanged with heartbeat**: suppresses writes on unchanged values but forces a write every N
seconds regardless. Reduces history volume on low-churn items.

**History vs Trends**: history = raw values (90-day default, high write volume); trends = hourly
aggregates min/max/avg/count (365-day default). Value-type mismatch causes "not supported" errors.

---

## Full Trigger Function Set

The main SKILL.md shows six common examples. Complete set:

| Function | Purpose |
|----------|---------|
| `last(/host/key)` / `last(/host/key,#N)` | Most recent value; Nth most recent |
| `avg` / `max` / `min` / `sum` | Statistics over a time period |
| `count(/host/key,Ns)` | Count of values in period |
| `diff(/host/key)` | 1 if last two values differ |
| `change(/host/key)` | Arithmetic difference between last two values |
| `nodata(/host/key,Ns)` | 1 if no data received in N seconds |
| `find(/host/key,Ns,"regexp","pat")` | Regex or substring match on string values |
| `percentile(/host/key,Ns,P)` | Pth percentile over period |
| `trendavg(/host/key,period)` | Average from hourly trend data (use for weekly/monthly baselines) |

---

## Actions and Escalations

Conditions: trigger severity, host group, trigger tags, maintenance status.

Operations per step: send message, execute remote command, add/remove host from group.

Typical escalation ladder:

| Step | Delay | Recipient |
|------|-------|-----------|
| 1 | 0 min | On-call engineer |
| 2 | 30 min | Team lead (if unacknowledged) |
| 3 | 60 min | Management |

Configure "Recovery operations" and "Acknowledge operations" tabs separately. Built-in media types
(7.x): Email, SMS, Slack, Teams, PagerDuty, Opsgenie, Telegram, Jira, ServiceNow, VictorOps. The
JavaScript webhook media type covers any other destination via `Zabbix.request()`.

---

## Push Monitoring: zabbix_sender

For batch jobs or application instrumentation, push values to a Zabbix trapper item:

```bash
zabbix_sender -z zabbix-server.example.com -s "webhost01" -k app.users.active -o 142
zabbix_sender -z zabbix-server.example.com -i /tmp/batch.txt   # bulk: hostname key value per line
```

The receiving item must have type "Zabbix trapper". Allowed source IPs are set per item.

---

## LLD: Custom JSON and Lifetime Management

### Custom discovery JSON format

```json
[
  {"{#SERVICE}": "nginx",  "{#PORT}": "80"},
  {"{#SERVICE}": "mysql",  "{#PORT}": "3306"}
]
```

Macros (`{#SERVICE}`, `{#PORT}`) are then usable in item/trigger/graph prototypes.

**Keep lost resources period** (default 30 days): items for vanished entities survive this long before
deletion. Set to 0 for immediate deletion; useful for ephemeral containers and short-lived services.

---

## TimescaleDB Initialisation SQL

The main SKILL.md covers adding compression to an existing `history` table. For a fresh deployment,
convert all history and trends tables to hypertables before starting `zabbix-server`:

```sql
SELECT create_hypertable('history',      'clock', chunk_time_interval => 86400);
SELECT create_hypertable('history_uint', 'clock', chunk_time_interval => 86400);
SELECT create_hypertable('history_str',  'clock', chunk_time_interval => 86400);
SELECT create_hypertable('history_log',  'clock', chunk_time_interval => 86400);
SELECT create_hypertable('history_text', 'clock', chunk_time_interval => 86400);
SELECT create_hypertable('trends',       'clock', chunk_time_interval => 2592000);
SELECT create_hypertable('trends_uint',  'clock', chunk_time_interval => 2592000);

ALTER TABLE history      SET (timescaledb.compress, timescaledb.compress_segmentby = 'itemid');
ALTER TABLE history_uint SET (timescaledb.compress, timescaledb.compress_segmentby = 'itemid');
SELECT add_compression_policy('history',      INTERVAL '7 days');
SELECT add_compression_policy('history_uint', INTERVAL '7 days');
```

Verify: `SELECT * FROM chunk_compression_stats('history');`

---

## PostgreSQL and MySQL Tuning

### PostgreSQL (`postgresql.conf`)

```
shared_buffers             = 25% RAM
effective_cache_size       = 75% RAM
work_mem                   = 16MB
checkpoint_completion_target = 0.9
max_wal_size               = 2GB
```

Add PgBouncer as a connection pooler beyond 5000 hosts.

### MySQL/MariaDB (`my.cnf`)

```
innodb_buffer_pool_size         = 70-80% RAM
innodb_flush_log_at_trx_commit  = 2    # small durability trade-off; acceptable for monitoring
innodb_flush_method             = O_DIRECT
```

InnoDB required. Use partitioning scripts instead of the built-in housekeeper for large deployments.

---

## Dashboards, SLA Objects, and Maintenance Windows

Dashboard widgets: Graph/SVG graph, Problems, Top hosts, Honeycomb, Item value, Gauge, Map, Geomap,
SLA report, Data overview, Host availability. Network maps show topology with trigger-severity
colouring and support drill-down to sub-maps or host dashboards.

**SLA objects (6.0+):** Service tree with SLO target percentage and reporting period
(daily/weekly/monthly/quarterly/annual). Trigger firing counts as downtime.

**Maintenance windows:** "With data collection" suppresses alerts, keeps polling. "No data
collection" pauses polling. Both one-time and recurring schedules are supported.

---

## Internal Items: Full Health Thresholds

| Item key | What it measures |
|----------|-----------------|
| `zabbix[process,poller,avg,busy]` | Poller busy % |
| `zabbix[process,trapper,avg,busy]` | Trapper busy % |
| `zabbix[process,history syncer,avg,busy]` | History syncer busy % |
| `zabbix[queue]` | Items delayed in processing queue |
| `zabbix[queue,10m]` | Items delayed more than 10 minutes |
| `zabbix[vcache,cache,hits]` / `[misses]` | Value cache hits/misses |
| `zabbix[wcache,values,pfree]` | Write cache free % |
| `zabbix[rcache,buffer,pfree]` | Configuration cache free % |
| `zabbix[requiredperformance]` | Required new values per second (NVPS) |

Alert thresholds: process busy above 70%; queue above 0 sustained; vcache miss rate above 10%
(increase `ValueCacheSize`); write cache free below 5% (increase `HistoryCacheSize`);
config cache free below 10% (increase `CacheSize`).

`zabbix[requiredperformance]` signals when adding proxies or reducing item frequency is needed
before queue depth starts to grow.

---

## Monitoring Scale Reference

| Topology | Approximate capacity |
|----------|---------------------|
| Single server, no proxy, PostgreSQL | ~5000 hosts, ~500K checks/minute |
| Server plus proxy fleet | Linear: add proxies at ~50K checks/minute each |
| TimescaleDB-backed server | Sustained 100K+ values/second on modern hardware |

When `zabbix[queue]` grows above zero sustainably, add proxies or reduce item frequency before
upgrading hardware.
