---
name: mariadb-deltas
description: "Use for any MariaDB work where the engine differs meaningfully from MySQL. Triggers include \"MariaDB\", \"Galera Cluster\", \"Galera node not joining\", \"WSREP\", \"wsrep_flow_control_paused\", \"MaxScale\", \"MaxScale read-write split\", \"ReadWriteSplit router\", \"MariaDB Aria\", \"ColumnStore\", \"Spider engine\", \"S3 storage engine\", \"MariaDB JSON column behaviour\", \"MariaDB GTID\", \"MariaDB replication from MySQL\", \"MariaDB system versioning\", \"FOR SYSTEM_TIME AS OF\", \"WITH SYSTEM VERSIONING\", \"MariaDB temporal tables\", \"MariaDB thread pool\", \"thread_pool_size\", \"mariadb-dump vs mysqldump\", \"mariadb-backup\", \"MariaDB optimizer hints\", \"ANALYZE FORMAT=JSON\", \"MariaDB cost-based optimizer\", \"MariaDB 11.4\", \"MariaDB 11.8 VECTOR type\", \"MariaDB version routing\", \"migrate MySQL to MariaDB\", \"migrate MariaDB to MySQL\", \"MariaDB unix_socket auth\", \"ed25519 auth\". Companion to `mysql-best-practices`; the MySQL skill covers the shared 80%, this skill covers the MariaDB-only deltas. Sections: storage engines (InnoDB default; Aria for crash-safe MyISAM-style; ColumnStore for OLAP; Spider for sharding; S3 for archival; CONNECT for external sources), Galera Cluster (synchronous multi-master, certification-based conflict detection, SST / IST, GCache, Flow Control, hard limits including PK-required, InnoDB-only, large-transaction stall, TOI DDL blocks cluster), MaxScale (ReadWriteSplit / ReadConnRoute / SchemaRouter; MariaDB Monitor failover; query filtering), key behavioural differences from MySQL (JSON as LONGTEXT not binary; domain-based GTID format incompatible with MySQL UUIDs; built-in thread pool vs MySQL Enterprise-only; native system versioning; ed25519 / unix_socket default auth; cost-based optimizer rewrite in 11.4+; CHECK constraints enforced from 10.2+), system versioning, binary naming transition (mariadb-* preferred over mysql-*), version routing table (10.6 LTS through 12.x rolling), common pitfalls including Galera-specific gotchas, migration discipline. Customised from chrishuffman5/domain-expert/database/mariadb (MIT)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# MariaDB deltas (over MySQL)

This skill is a **companion** to `mysql-best-practices`. Read that skill first; everything in it about InnoDB, indexing, transactions, locking, and EXPLAIN-driven query work applies unchanged to MariaDB. This skill is the differences.

The two engines forked from MySQL 5.5 in 2009 and have diverged substantially. By 2026 the deltas matter enough that "I know MySQL, I will figure out MariaDB" is wrong as often as right, especially around Galera, GTIDs, JSON, optimizer behaviour, and the binary-naming transition.

> **Skill marker**: When applying this skill, begin your reply with `[skill: mariadb-deltas]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the MariaDB estate (version branch, storage engines in use, Galera versus async replication) before recommending a delta. Only ask the user for information not already covered or specific to this question.

Before answering, understand:

1. **Version and edition**
   - MariaDB major version (10.6 LTS, 10.11 LTS, 11.x)?
   - Community, MaxScale, or vendor-distributed (Amazon RDS, SkySQL)?
   - Compatibility target (drop-in MySQL replacement, or using MariaDB-only features)?

2. **Topology**
   - Single instance, async primary-replica, or Galera cluster?
   - For Galera: node count, segment / WAN layout, SST / IST snapshot method?
   - Storage engine mix (InnoDB only, MyRocks, Spider, ColumnStore, Aria)?

3. **Workload and change**
   - OLTP, OLAP, or mixed?
   - Schema or query change in flight, or operational tuning?

---

## Version routing (LTS calendar)

| Version | Type | EOL | Key feature you must know about |
|---|---|---|---|
| 10.6 | LTS | Jul 2026 | Atomic DDL, JSON_TABLE, Oracle compatibility flags |
| 10.11 | LTS | Feb 2028 | password_reuse_check, NATURAL_SORT_KEY, performance boost |
| 11.4 | LTS | Jan 2033 | **Cost-based optimizer rewrite** (largest behaviour change in years; re-test plans on upgrade), JSON_SCHEMA_VALID |
| 11.8 | LTS | Jun 2028 | VECTOR type for similarity search, Y2038 fix, utf8mb4 default |
| 12.x | Rolling release | Continuous | MySQL-compatible optimizer hints, Oracle syntax extensions |

If unsure which version is in use: `SELECT VERSION();`. Behaviour differs enough that "MariaDB" alone is rarely a complete answer.

## Storage engines (the surface MySQL does not have)

| Engine | When | Notes |
|---|---|---|
| InnoDB | Default for OLTP | Same as MySQL; everything in `mysql-best-practices` applies. |
| Aria | System tables, on-disk temp tables, read-mostly workloads not needing transactions | Crash-safe via WAL (unlike MyISAM); table-level locks; faster scans than InnoDB for pure-read workloads. |
| ColumnStore | OLAP / analytics / large aggregations | Columnar; typically deployed as a separate storage backend behind a MariaDB front. |
| Spider | Sharding across multiple servers | Federated tables; complex; usually replaced by app-side sharding in modern stacks. |
| S3 | Archival of cold data | Read-only after archival; cheap. |
| CONNECT | Querying external sources (CSV, JSON, XML, ODBC, REST) | ETL / ad-hoc integration; not for production OLTP. |

The default mental model is still: InnoDB unless you have a specific reason. Aria, ColumnStore, Spider, S3, CONNECT are deliberate choices, never defaults.

## Galera Cluster (the big one)

Galera is MariaDB's synchronous multi-master replication. Every node holds every write; commits are coordinated via a certification protocol. The behaviour model is fundamentally different from async source-replica MySQL replication.

### How a write actually flows

1. Transaction executes locally on the originating node.
2. At COMMIT, the node packages a **writeset** (all row changes).
3. The writeset broadcasts to every node via group communication (GComm).
4. Each node runs **certification**: deterministic conflict check against pending writesets. All nodes reach the same commit / abort decision independently.
5. If certification passes, every node applies the writeset; if it fails, the originating node rolls back with a deadlock-style error.

### Hard limits (memorise these)

- **Every replicated table requires a primary key.** Galera's certification cannot resolve writeset ordering without one. Tables without PKs cause performance degradation and unpredictable conflict resolution.
- **InnoDB / XtraDB only for replicated data.** Aria, MyISAM, others are not replicated.
- **Large transactions (over ~128k rows) stall the cluster.** Big writesets hold up certification for everyone. Batch large operations.
- **DDL is Total Order Isolation (TOI).** Schema changes block the entire cluster for the duration. Use rolling schema changes (RSU) only when you understand the risk; the cluster temporarily diverges.
- **No `LOCK TABLES`, no `GET_LOCK`, no XA in multi-master mode.** Application code that relies on these will not work as expected.

### State transfers

When a node joins or rejoins:

- **SST (State Snapshot Transfer):** full data copy from a donor. Slow on large datasets. Methods: `mariabackup` (preferred; non-blocking), `rsync`, `mysqldump` (fallback; blocks the donor).
- **IST (Incremental State Transfer):** partial transfer of missed writesets from the donor's GCache. Fast; used when the joining node has been gone for less than the GCache window.

Size GCache for the longest expected node downtime. Too small forces SST; too large wastes memory.

### Flow control: the symptom you will see first

When one node falls behind (slow disk, network saturation, certification spike), it asks the cluster to slow down. Watch:

```sql
SHOW GLOBAL STATUS LIKE 'wsrep_flow_control_paused';
-- 0 = healthy; > 0 = the cluster is being throttled by some node
```

Sustained `wsrep_flow_control_paused > 0.1` (10% of the time) is an incident. The fix is to find the slow node, not to disable flow control.

### Quorum

A 3-node cluster tolerates 1 node loss. A 4-node cluster also tolerates 1 (no improvement). A 5-node cluster tolerates 2. **Always odd-numbered nodes for quorum**; the partition handler ties go to the side with majority.

## MaxScale

MariaDB's intelligent proxy. Sits in front of the cluster.

| Router | Use |
|---|---|
| `ReadWriteSplit` | Splits writes to the source / primary, reads to replicas. Statement-aware. The default for source-replica setups. |
| `ReadConnRoute` | Connection-level routing (each new connection picks a backend; sticky for the connection lifetime). Lighter; less smart. |
| `SchemaRouter` | Routes by schema name; for tenancy-by-schema deployments. |

MariaDB Monitor (built into MaxScale) does automatic failover. Configure it explicitly; the defaults are conservative (good) and may surprise on first failover.

MaxScale is also where query filtering, masking, and firewall rules live. Useful for compliance work; not a replacement for application-side validation.

## Behavioural deltas from MySQL (the table you will re-read)

| Area | MariaDB | MySQL |
|---|---|---|
| JSON storage | LONGTEXT with validation; no binary format | Binary JSON |
| JSON storage size functions | `JSON_STORAGE_SIZE` / `JSON_STORAGE_FREE` not meaningful | Native binary; functions return real bytes |
| GTID format | Domain-based: `domain-server_id-sequence` | UUID-based: `server_uuid:transaction_id` |
| GTID interop | **MariaDB and MySQL GTID-based replication are mutually incompatible.** | |
| Thread pool | Built-in, all editions | Enterprise Edition only |
| System versioning | Native (`WITH SYSTEM VERSIONING`) | Not native; do it in application code |
| Default auth | unix_socket + ed25519 / mysql_native_password | caching_sha2_password (8.0+) |
| Optimizer | Truly cost-based since 11.4; rule-based elements before | Cost-based with heuristics throughout |
| CHECK constraints | Enforced from 10.2 | Enforced from 8.0.16; ignored before |
| Binary log encryption | Own format | Different format |
| Spatial / R-tree | Limited InnoDB support; full MyISAM | InnoDB native since 8.0 |
| Optimizer hints | MySQL-compatible from 12.x | Available since 5.7 |

The single most disruptive difference in practice is **GTID incompatibility**. You cannot replicate from MySQL to MariaDB (or vice versa) using GTID-based replication. Migrations require a clean cutover or a logical replication tool that converts.

## System versioning (the MariaDB-only feature you might actually want)

```sql
CREATE TABLE products (
  id INT PRIMARY KEY,
  name VARCHAR(100),
  price DECIMAL(10,2)
) WITH SYSTEM VERSIONING;

-- Read history
SELECT * FROM products FOR SYSTEM_TIME AS OF '2025-01-01 00:00:00';
SELECT * FROM products FOR SYSTEM_TIME BETWEEN '2025-01-01' AND '2025-06-01';
SELECT * FROM products FOR SYSTEM_TIME ALL;
```

Every UPDATE or DELETE preserves the prior row in a hidden history. Storage cost is real (history accumulates indefinitely unless you partition by time and drop old partitions). Useful for audit, point-in-time queries, soft-delete-with-history. **Not a replacement** for proper audit logging when the requirement is regulatory; the history is in the same database and disappears if the schema is dropped.

## Binary naming transition

MariaDB has been renaming `mysql*` tools to `mariadb*`. Old names remain as symlinks **for now**.

| Old name | New name |
|---|---|
| `mysql` | `mariadb` |
| `mysqldump` | `mariadb-dump` |
| `mysqladmin` | `mariadb-admin` |
| `mysql_upgrade` | `mariadb-upgrade` |
| `mysqld` | `mariadbd` |
| `mysqlbackup` (Percona XtraBackup) | `mariadb-backup` (different tool, MariaDB's own fork of XtraBackup) |

Always use the `mariadb*` names in new scripts and documentation. The symlinks may be removed in a future major version.

## Optimizer hints (12.x+)

MySQL-compatible hint syntax landed in 12.x. Earlier versions have MariaDB-specific older syntax (`STRAIGHT_JOIN`, optimizer-switch flags) but no inline `/*+ ... */` hints.

```sql
SELECT /*+ JOIN_INDEX(t1, idx_col1) */ * FROM t1 WHERE col1 = 1;
SELECT /*+ NO_INDEX(t1, idx_col2) */ * FROM t1 WHERE col2 > 100;
SELECT /*+ GROUP_INDEX(t1, idx_grp) */ col1, COUNT(*) FROM t1 GROUP BY col1;
```

Use sparingly. A hint is an admission that the optimizer is wrong; in MariaDB 11.4+ the cost-based optimizer is usually right.

## ANALYZE FORMAT=JSON (better than EXPLAIN)

MariaDB extends EXPLAIN with `ANALYZE FORMAT=JSON`, which returns **actual** execution statistics (runs the query):

```sql
ANALYZE FORMAT=JSON SELECT * FROM orders WHERE customer_id = 42;
```

Key fields:

- `r_loops`: actual times the operation executed.
- `r_total_time_ms`: actual time spent.
- `r_rows`: actual rows returned. Compare against `rows` (estimate) to catch stale statistics.
- `r_filtered`: actual filter selectivity.

When `rows` and `r_rows` diverge by an order of magnitude, run `ANALYZE TABLE` to refresh stats. Stale stats are the most common cause of bad MariaDB plans, especially after the 11.4 optimizer rewrite.

## Common pitfalls (MariaDB-specific)

1. **MySQL JSON migration.** Apps using `JSON_STORAGE_SIZE`, `JSON_STORAGE_FREE`, or assuming binary-JSON performance break on MariaDB. Validate every JSON query path.
2. **GTID incompatibility.** No drop-in replication between MySQL and MariaDB. Plan a cutover or use a logical replication tool.
3. **Removed config variables on upgrade.** Removed variables cause startup failure. After every upgrade, run `mariadbd --help --verbose 2>&1 | grep -i warning` and clean the config.
4. **Galera missing primary key.** Performance and correctness issues. Audit every replicated table for explicit PK.
5. **Thread pool misconfigured.** `thread_pool_size` at or near CPU core count; setting it too high negates the benefit.
6. **Skipped ANALYZE TABLE after bulk load.** The 11.4+ optimizer relies on accurate statistics. After bulk operations or upgrades, run `ANALYZE TABLE` on changed tables.
7. **Large Galera transactions.** Anything modifying more than ~128k rows stalls the cluster. Batch.
8. **Assuming MySQL documentation applies.** Reference mariadb.com/kb, not MySQL docs, for anything introduced after the 5.5 fork.
9. **Disabling flow control to "fix" lag.** Flow control is the symptom, not the cause. Find the slow node.
10. **Leaving `mysql*` binary names in scripts.** They will work until they do not. Rename to `mariadb*` proactively.

## Migration discipline

### MySQL to MariaDB

Doable with planning. Considerations:

- GTID-based replication will not work; do a clean cutover during a maintenance window, or use logical replication (mariadb-dump | mariadb on the target, then catch up via row-based binlog read).
- JSON queries: re-test every one. Functions returning binary-JSON metadata are wrong.
- Authentication: `caching_sha2_password` does not exist in MariaDB. Re-issue users with `mysql_native_password` or `ed25519`.
- CHECK constraints: enforced; previously-ignored CHECK clauses will now fire.
- Optimizer: re-run EXPLAIN on every hot query; behaviour may differ.

### MariaDB to MySQL

Harder. MariaDB-only features must be removed:

- System versioning: drop or implement application-side history before migration.
- Aria / ColumnStore / Spider tables: convert to InnoDB or move to a separate analytics platform.
- Domain-based GTIDs: clean cutover.
- Optimizer hints: 12.x-style hints are MySQL-compatible; older MariaDB hints need translation.

Tooling: there is no direct two-way replication. Use logical dump-restore plus application-side dual-write during the migration window.

## Verification before claiming done

Per `completion-gate`, "I am running MariaDB now" is not a finish line. Before the chunk closes:

- [ ] `SELECT VERSION();` recorded in the chunk notes; behaviour expectations match the version.
- [ ] If on Galera: `wsrep_cluster_status` is `Primary`, `wsrep_local_state` is `Synced`, `wsrep_flow_control_paused` is near zero across all nodes.
- [ ] If touching JSON: every query touched has been re-tested under MariaDB JSON-as-LONGTEXT semantics.
- [ ] If touching system versioning: history retention policy documented (otherwise the table grows forever).
- [ ] After upgrade: `mariadbd --help --verbose 2>&1 | grep -i warning` returns no removed-variable warnings.
- [ ] After 10.x to 11.4+ upgrade: `ANALYZE TABLE` run on every hot table; `EXPLAIN` re-verified for top queries.
- [ ] Backup tool name is `mariadb-backup` (not `mysqlbackup`); restore tested on a non-production replica.

## Cross-references

- `mysql-best-practices`: the shared 80%. Read first; this skill is the deltas.
- `postgres-best-practices`: when the conversation is "should we even be on MariaDB", Postgres is the alternative; comparison surface lives there.
- `forward-compatible-schemas`: same additive-migration discipline applies; Galera makes blocking schema changes especially expensive.
- `secrets-hygiene`: MariaDB credentials, Galera node-to-node SST credentials, MaxScale service-account passwords, monitoring user passwords all live in the secret store.
- `plan-time-tooling`: any chunk touching Galera (node add / remove, schema change, version upgrade) is an `engineering:deploy-checklist` trigger.
- `completion-gate`: the verification checklist above is the layer-3 gate.
- `systematic-debugging`: when Galera is unhappy, run the four-phase loop with `wsrep_*` status as the boundary evidence; do not jump to fixes.
- `oncall-runbooks`: split-brain, slow-node, IST-failure, SST-failure runbooks live there; this skill is the technical source.
- `bash-defensive`: MaxScale config update scripts, mariabackup orchestration, `mariadbd-safe` wrappers all follow defensive-bash discipline.

## Red flags

- About to add a table to a Galera cluster without an explicit primary key.
- About to run a 500k-row UPDATE inside Galera in a single transaction.
- About to use MyISAM or Aria for a table that takes writes outside maintenance windows.
- About to set up GTID-based replication between MySQL and MariaDB.
- About to migrate JSON-heavy code from MySQL to MariaDB without re-testing every JSON query.
- About to disable Galera flow control to "fix" lag instead of finding the slow node.
- About to upgrade to 11.4+ without re-running EXPLAIN and `ANALYZE TABLE` on hot queries.
- About to set `thread_pool_size` to 64 on an 8-core box.
- About to deploy `WITH SYSTEM VERSIONING` without a history-retention strategy.
- About to use `mysqlbackup` (Percona) thinking it is `mariadb-backup` (different tool, different output format).
- About to commit a credential into `my.cnf` or `mariadb.cnf`.
- About to deploy a 4-node Galera cluster (4 nodes give no fault-tolerance improvement over 3; use 3 or 5).
- About to skip `wsrep_flow_control_paused` in the dashboard. Without it you cannot see Galera health degrading until it is too late.

## Bottom line

Start from `mysql-best-practices`. Layer in: storage-engine choice (Aria, ColumnStore, Spider, S3, CONNECT are deliberate, never defaults); Galera's hard rules (PK on every table, InnoDB only, no large transactions, TOI DDL); JSON-as-LONGTEXT (re-test every JSON path on migration); GTID incompatibility (clean cutover for MySQL interop); ANALYZE FORMAT=JSON for execution stats; `mariadb-*` binary names; system versioning when you actually want point-in-time history; version-aware advice (especially around the 11.4 optimizer rewrite).
