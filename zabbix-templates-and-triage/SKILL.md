---
name: zabbix-templates-and-triage
description: "Use for any Zabbix design, configuration review, performance tuning, or incident triage on Zabbix 7.x (some 6.x notes inline). Triggers include 'zabbix', 'zabbix server won't start', 'zabbix no data from agent', 'zabbix LLD', 'low-level discovery', 'zabbix template design', 'trigger expression', 'zabbix proxy', 'zabbix agent2', 'zabbix_get', 'zabbix_sender', 'zabbix HTTP agent', 'dependent items', 'zabbix preprocessing', 'JSONPath in zabbix', 'TimescaleDB zabbix', 'zabbix housekeeper', 'zabbix proxy group', 'zabbix performance tuning', 'StartPollers', 'CacheSize', 'history sync queue', 'zabbix alert not firing', 'zabbix alerts flooding', 'zabbix dashboard', 'zabbix API', 'zabbix YAML import', 'zabbix Slack / Teams / PagerDuty media type'. Combines design discipline (template-first, dependent items, LLD with filters, hysteresis, tag taxonomy, proxy by network zone, TimescaleDB compression, monitor-zabbix-itself) with a four-step incident triage protocol (observe with concrete commands, deduce against a 7-row symptom table, test the hypothesis with a verification command, fix with a documented procedure). Customised from chrishuffman5/domain-expert/skills/monitoring/zabbix (MIT) and dz07/goku-skills/skills/zabbix-super-agent (folded; emojis and openclaw-harness script paths stripped). Pairs with linux-host-ops (host-side service / journalctl / systemd diagnostics), oncall-runbooks (runbook structure for the triage outputs), systematic-debugging (Phase 1 boundary evidence; Zabbix is often the first signal), slo-implementation (SLO compliance often shows in Zabbix dashboards before it shows in Prometheus), grafana-dashboards (when Grafana is the visualisation layer in front of Zabbix data), secrets-hygiene (DBPassword, agent PSK, API tokens, Slack webhook URLs). Advanced reference (load on demand): advanced-features (HA cluster, TLS / PSK / RBAC hardening, preprocessing pipelines, full trigger function set, escalation timing, zabbix_sender push monitoring, TimescaleDB initialisation SQL, PostgreSQL / MySQL tuning, LLD custom JSON, dashboard widgets and SLA objects). Additional triggers: 'zabbix HA', 'HANodeName', 'zabbix TLS', 'zabbix PSK', 'zabbix RBAC', 'zabbix preprocessing pipeline', 'zabbix escalation', 'zabbix SLA', 'create_hypertable', 'zabbix media type webhook'."
license: MIT
metadata:
  version: "1.1.0"
---

# Zabbix Templates and Triage

Specialist for Zabbix 7.x open-source monitoring. Two halves: design discipline (templates, items, triggers, LLD, proxies, database) and incident triage (observe, deduce, test, fix). Every recommendation balances monitoring completeness against database load and operational complexity.

> **Skill marker**: When applying this skill, begin your reply with `[skill: zabbix-templates-and-triage]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Zabbix estate (server / proxy topology, template library, host-group structure, on-call integration) before authoring or triaging. Only ask the user for information not already covered or specific to this task.

Before authoring or triaging, understand:

1. **Estate topology**
   - Standalone server, server + proxy fleet, or HA cluster?
   - Zabbix major version (6.x LTS, 7.x)?
   - Agent (active vs passive), SNMP, IPMI, or vendor-API templates dominant?

2. **Template and host context**
   - Existing template library (LLD-heavy, manual-item heavy, hybrid)?
   - Host-group conventions for grouping?
   - Inheritance pattern (nested templates, single-level)?

3. **Alert and triage**
   - Action / media-type setup (email, PagerDuty, Slack)?
   - Severity ladder in use; thresholds tuned per host or per template?
   - Recent false-positive or alert-fatigue pattern to address?

---

## When to use

- Designing or reviewing a Zabbix template before it goes to production
- Diagnosing "no data from agents", "server won't start", "frontend says server is down", "alerts not firing"
- Tuning performance on a deployment that has grown past 1000 hosts
- Choosing between Agent classic vs Agent2, between PostgreSQL+TimescaleDB vs MySQL, between proxy and direct agent
- Standing up LLD for a new resource type (filesystems, interfaces, containers, custom)
- Setting up media types and event correlation to suppress alert storms

## Architecture primer

```
[Monitored hosts] -> [Agent / Agent2] -> [Proxy (optional)] -> [Server] -> [Database]
                                                                              |
                                                                       [Frontend (PHP)]
```

| Component | Role |
|-----------|------|
| Server | Central polling, trigger evaluation, alert generation |
| Proxy | Distributed collection, buffering, DMZ / remote-site monitoring |
| Agent (C) | Lightweight host daemon; active + passive checks; UserParameters |
| Agent2 (Go) | Modern plugin-based agent; native MySQL / PostgreSQL / Redis / Docker / K8s plugins |
| Frontend | PHP web UI; JSON-RPC API at `/api_jsonrpc.php` |
| Database | PostgreSQL + TimescaleDB recommended; MySQL / MariaDB supported |

| Port | Direction | Use |
|------|-----------|-----|
| 10050 | Server -> Agent | Passive checks |
| 10051 | Agent -> Server / Proxy -> Server | Active checks, trapper, proxy traffic |
| 80 / 443 | Browser -> Frontend | Web UI and API |

## Design discipline

### Iron rule: template-first

Never configure items, triggers, or graphs directly on a host. Always go through a template.

- Templates enable reuse across hundreds or thousands of hosts.
- Templates can be exported to YAML and version-controlled.
- A template change updates every host using it; per-host changes are unmaintainable at scale.
- Drift on a host that someone manually edited is the most common "why is this host different" puzzle.

### Dependent items pattern

One master HTTP Agent item fetches a JSON or XML response from an API. Twenty dependent items extract individual metrics via JSONPath, XPath, or Prometheus pattern preprocessing.

- Reduces API calls by 20x.
- Reduces poller threads by 20x.
- One source of truth (the master item) for raw data.
- Enables "discover X dependent metrics from one master item" without rewriting the polling layer.

Use cases: any HTTP API, SNMP walk that returns a tree, JMX bulk fetch.

### Trigger expressions

```
avg(/host/system.cpu.load[all,avg1],5m) > 5
last(/host/vfs.fs.size[/,pused]) > 90
last(/host/proc.num[nginx]) = 0
nodata(/host/agent.ping,5m) = 1
max(/host/vm.memory.size[available],15m) < 104857600
find(/host/log[/var/log/app.log],60s,"regexp","FATAL|ERROR") = 1
```

Severity ladder: Not classified, Information, Warning, Average, High, Disaster.

Hysteresis: separate problem and recovery expressions stop trigger flap. Alert at CPU > 90%, recover at CPU < 80%.

Trigger dependencies: when a network switch fails, every host behind it would alert. Mark the switch trigger as a dependency on every downstream host trigger to suppress the storm.

### Low-level discovery (LLD)

LLD discovers dynamic entities (filesystems, network interfaces, databases, containers) and creates items, triggers, and graphs from prototypes.

Built-in discovery keys:

- `vfs.fs.discovery` returns `{#FSNAME}`, `{#FSTYPE}`
- `net.if.discovery` returns `{#IFNAME}`
- `vfs.dev.discovery` returns block devices
- `system.cpu.discovery` returns CPU cores

Item prototype example:

- Key: `vfs.fs.size[{#FSNAME},pused]`
- Name: `Filesystem {#FSNAME}: used space %`

**Always filter discovery results.** Without filters, LLD creates items for tmpfs, devtmpfs, loopback, and Docker overlay mounts. Filter `{#FSTYPE}` to `ext4|xfs|btrfs|zfs` (or whatever your fleet actually uses).

Use overrides for per-entity exceptions without modifying the prototype: disable the disk-full trigger on `/tmp` for hosts where `/tmp` is intentionally allowed to fill.

### Tag taxonomy

Tag every trigger with three families:

- `component` (database, web, queue, cache, proxy)
- `scope` (host, application, service, business)
- `service` (the named service, e.g. `service:checkout-api`)

Tags drive: alert routing in actions, dashboard filters, event correlation, SLA scoping. Untagged triggers are noise.

### Top 10 operational rules

1. Use templates for everything. No host-direct configuration.
2. Deploy Agent2 on new hosts. Use classic agent only for legacy compatibility.
3. Use dependent items for any source that returns multiple metrics in one call.
4. Tag every trigger.
5. Deploy proxies by network zone (DMZ, remote office, cloud VPC). Active proxy mode reduces firewall complexity.
6. Use TimescaleDB on PostgreSQL. Compression delivers 5x to 10x on history tables and improves write throughput.
7. Monitor Zabbix itself. Internal items `zabbix[*]` track queue depths, process busy %, cache hit ratios.
8. Use proxy groups (7.0+) for automatic failover and load distribution across multiple proxies.
9. Export templates as YAML to git. CI imports to staging before production.
10. Tune housekeeping. For large deployments, disable the built-in housekeeper and use TimescaleDB retention policies or PostgreSQL partitioning instead.

## Incident triage protocol

When Zabbix has any operational issue, run the four-step protocol. No assumptions; only facts from live evidence.

### Step 1: Observe (collect evidence)

```bash
# Zabbix server
systemctl status zabbix-server --no-pager
ps aux | grep zabbix_server | grep -v grep

# Frontend (nginx OR apache, whichever the deployment uses)
nginx -t 2>/dev/null || apachectl configtest 2>/dev/null
systemctl status nginx 2>/dev/null || systemctl status httpd 2>/dev/null

# Database
systemctl status postgresql 2>/dev/null || systemctl status mariadb 2>/dev/null || systemctl status mysql 2>/dev/null

# Resources
free -h
df -h /var/lib/zabbix /var/lib/postgresql /var/lib/mysql 2>/dev/null

# Server log
tail -100 /var/log/zabbix/zabbix_server.log
grep -i error /var/log/zabbix/zabbix_server.log | tail -30

# Listener health
ss -tlnp | grep -E '10051|3306|5432|80|443'

# Agent reachability (from server, against suspect agent)
zabbix_get -s <agent-ip> -k 'agent.ping'
zabbix_get -s <agent-ip> -k 'system.cpu.load'

# Config sanity
grep -E '^DB(Host|Name|User)|^Log|^Pid|^Cache|^Start' /etc/zabbix/zabbix_server.conf
```

### Step 2: Deduce (match symptom to likely cause)

| Symptom | Likely cause | First-pass action |
|---------|-------------|-------------------|
| Server running, no data from any host | Server cannot reach DB or all proxies dropped | Check DB credentials and proxy health |
| Server running, no data from one host | Agent down, firewall, or wrong agent IP | `zabbix_get -s <ip> -k agent.ping` |
| Frontend shows "Zabbix server is running: No" | Server process dead, port 10051 blocked, or `/var/run` socket missing | `systemctl restart zabbix-server` then check log |
| Old data in graphs, gaps | Server crash, history syncer stuck, OOM kill | Check log for crash; check history sync queue |
| Alerts not sending | Media type misconfig, queue stuck, escalation step disabled | Test media type from UI; check `alerts` table |
| High CPU on server | Too many items polled at the same second; pollers undersized | Distribute item intervals; raise StartPollers |
| Server will not start | DB lock, OOM, config syntax, unwritable PID dir | `zabbix_server -R config_cache_reload` test then read log |
| Database growing fast | Housekeeper off, TimescaleDB not compressing, history retention too long | Enable TimescaleDB compression; tune retention per item |
| Alert flood after switch failure | Trigger dependencies missing | Add upstream trigger as dependency on downstream items |
| Discovery creates noise items | LLD filter missing | Add `{#FSTYPE}` or `{#IFNAME}` filter |

### Step 3: Test (verify the hypothesis)

```bash
# DB connection (PostgreSQL)
psql -U zabbix -h <db-host> -d zabbix -c "SELECT count(*) FROM hosts;"
# DB connection (MySQL)
mysql -u zabbix -p -h <db-host> zabbix -e "SELECT count(*) FROM hosts;"

# Agent reachability and a real metric
zabbix_get -s <agent-ip> -k 'agent.ping'
zabbix_get -s <agent-ip> -k 'system.uname'

# Frontend reachable from local
curl -s http://localhost/zabbix/index.php | grep -i zabbix

# Run server foreground for one cycle to surface fatal errors
sudo -u zabbix zabbix_server -f -c /etc/zabbix/zabbix_server.conf 2>&1 | head -30

# History sync queue depth (from inside the frontend or via API)
# Reports / System information should show sync queue near zero

# SELinux / AppArmor are common silent blockers
getenforce 2>/dev/null
aa-status 2>/dev/null | head -5
```

### Step 4: Fix (procedure per common cause)

**Server will not start.** Check the log first; do not jump to `systemctl restart`. Common causes: DB credential change, DB lock from ungraceful shutdown, PID directory permission, config syntax. Run the foreground test from Step 3 to surface the exact line. If OOM, raise the systemd `MemoryLimit` via `systemctl edit zabbix-server` rather than disabling the limit.

**No data from agents.** Confirm agent process is running on the target. From the Zabbix server, run `zabbix_get -s <ip> -k agent.ping`. If timeout, check firewall on both ends (10050 server-to-agent for passive, 10051 agent-to-server for active) and that the agent's `Server=` (passive) or `ServerActive=` (active) lists the correct Zabbix server or proxy IP.

**Alerts not sending.** Test the media type from the UI (Administration -> Media types -> test). If the test works, the issue is in the action (escalation step, condition, or recovery operation). If the test fails, the issue is upstream (SMTP server, webhook destination, network egress).

**Database growing fast.** Enable TimescaleDB compression on history tables: `ALTER TABLE history SET (timescaledb.compress, timescaledb.compress_segmentby = 'itemid');` then `SELECT add_compression_policy('history', INTERVAL '7 days');`. Verify compression by querying `chunk_compression_stats('history')`. Confirm housekeeper-off settings if you have moved to TimescaleDB retention policies.

### Triage log template

```
EVIDENCE
- Zabbix server: running / stopped / restart loop
- Frontend reachable: yes / no (HTTP code)
- DB connection: works / fails (error)
- Agent reachable: works / timeout / wrong IP
- Memory: X used / Y total
- Disk: X% used on /var/lib/{zabbix,postgresql,mysql}
- Last server log error (verbatim, with timestamp)

HYPOTHESIS
[Most likely root cause]

TEST
[Command from Step 3 that confirms or refutes]

CONCLUSION
[Confirmed root cause]
[Fix applied; commit / change reference]
[Verification command and expected output]
```

## Performance tuning quick reference

```ini
# /etc/zabbix/zabbix_server.conf
StartPollers=20             # Scale with item count; default 5 is fine for <500 hosts
StartPollersUnreachable=5   # Default 1; raise if many hosts go intermittently down
StartPingers=5              # ICMP checks; default 1
StartTrappers=10            # Active checks and zabbix_sender; default 5
StartHTTPPollers=5          # HTTP Agent items; default 1
CacheSize=512M              # Configuration cache; default 8M is too small past 500 hosts
HistoryCacheSize=128M       # History buffer; raise if "Zabbix history syncer X is busy"
HistoryIndexCacheSize=64M
TrendCacheSize=64M
ValueCacheSize=512M         # In-memory values for trigger evaluation
LogSlowQueries=3000         # ms; surface DB queries > 3s
```

Restart `zabbix-server` after config changes. Confirm via internal items `zabbix[wcache,values,pfree]` (free space in caches; trigger if below 5%) and `zabbix[process,history syncer,avg,busy]` (busy %; trigger if above 75%).

## Common pitfalls

1. **Database growth without TimescaleDB.** History tables grow unbounded; without compression a 10000-host deployment fills hundreds of GB within months.
2. **All items polling at second 0.** Default intervals cause polling spikes. Use randomised delay or stagger intervals.
3. **Missing trigger dependencies.** A switch outage alerts every host behind it; storm.
4. **No LLD filter.** Discovery creates items for tmpfs, loopback, virtual interfaces.
5. **Classic agent where Agent2 would do.** Custom UserParameters and external scripts where Agent2 has a native plugin.
6. **Passive proxy mode in firewalled environments.** Server must initiate; active proxy mode means only the proxy needs outbound access.
7. **Storing DBPassword in plain text in `zabbix_server.conf` and committing it.** Use the secret-store pattern; see `secrets-hygiene`.
8. **Untagged triggers.** Alerts cannot be routed cleanly without tags.
9. **Templates unversioned.** YAML export to git is mandatory; CI to staging before production.

## Advanced topics (references)

The body covers design discipline and the incident triage protocol. For advanced configuration depth, load the reference:

| Reference | Read when |
|---|---|
| `references/advanced-features.md` | HA cluster setup, TLS / PSK / RBAC hardening, preprocessing pipelines, the full trigger function set, escalation timing, `zabbix_sender` push monitoring, TimescaleDB initialisation SQL, PostgreSQL / MySQL tuning, LLD custom JSON, dashboard widgets and SLA objects. |

## Cross-references

- `linux-host-ops`: host-side service / systemd / journalctl when triaging server, proxy, or agent.
- `oncall-runbooks`: runbook structure for the triage output; the triage log template above is the input to a postmortem.
- `systematic-debugging`: Phase 1 boundary evidence; Zabbix is often the first signal but not always the root.
- `slo-implementation`: when SLO compliance dashboards are sourced from Zabbix data.
- `grafana-dashboards`: when Grafana sits in front of Zabbix as visualisation layer.
- `secrets-hygiene`: DBPassword, agent PSK, API tokens, Slack / Teams / PagerDuty webhook URLs all live in the secret store, never in `zabbix_server.conf` or scheduler script bodies.
- `bash-defensive`: wrapper scripts (UserParameters, external check scripts) follow the same defensive-bash discipline.
- `completion-gate` Layer 3: after a Zabbix change, post-checks include "is the new template applied to the right host group" and "did the trigger fire on the test event".
- `plan-time-tooling`: schema-affecting changes (LLD prototype rework that changes itemid stability) fire engineering:architecture; production Zabbix server changes fire engineering:deploy-checklist.

## Red flags

- About to configure items or triggers directly on a host instead of in a template.
- About to write a UserParameter where Agent2 has a native plugin.
- About to set LLD with no filter.
- About to disable the housekeeper without a TimescaleDB retention policy or PostgreSQL partition replacement in place.
- About to roll DBPassword in `zabbix_server.conf` without coordinating restart and DB grant change.
- About to declare an issue resolved without `zabbix_get` or a SQL probe confirming the change took effect.
- About to ignore the trigger dependencies the runbook said to add after the last alert storm postmortem.
- About to add a Disaster-severity trigger without a recovery expression (will pin red until manual close).
- About to lift `EnableRemoteCommands=1` to "make a quick fix" without auditing what gets deployed (RCE surface).
- About to commit a Slack or Teams webhook URL into the YAML template export.

## Bottom line

Templates are the design surface; LLD is the scale lever; tags are the routing layer; TimescaleDB is the storage answer past 5000 hosts. When something breaks, the four-step protocol (observe, deduce, test, fix) keeps you in evidence and out of flailing. Never assume; always probe.
