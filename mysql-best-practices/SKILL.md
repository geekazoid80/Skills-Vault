---
name: mysql-best-practices
description: Use for any MySQL design, query-tuning, operations, or troubleshooting work. Triggers include "MySQL schema design", "MySQL primary key", "InnoDB", "utf8mb4", "MySQL JSON column", "EXPLAIN", "EXPLAIN ANALYZE", "composite index", "covering index", "MySQL deadlock", "innodb_row_lock", "REPEATABLE READ", "READ COMMITTED", "phantom read", "gap lock", "MySQL replication lag", "MySQL connection pool", "max_connections", "MySQL online DDL", "ALGORITHM=INSTANT", "ALGORITHM=INPLACE", "pt-online-schema-change", "gh-ost", "MySQL partitioning", "OFFSET pagination", "N+1", "implicit type conversion", "MySQL slow query", "performance_schema", "sys schema", "binlog", "MySQL upgrade", "MySQL backup", "mysqldump", "MySQL parameter tuning", "innodb_buffer_pool_size". Covers schema design (PK choice, utf8mb4 default, JSON discipline), indexing (composite ordering equality-then-range, covering indexes, unused-index detection), query optimisation (EXPLAIN red flags, OFFSET pagination anti-pattern, N+1), transactions and locking (isolation levels, deadlock prevention, row-locking gotchas, no-I/O-inside-transaction rule), operations (online DDL with InnoDB ALGORITHM choice, pt-online-schema-change / gh-ost when ALGORITHM is not enough, replication lag monitoring, connection pooling). Customised from gr1m0h/dot/mysql (PlanetScale-authored; MIT via SKILL.md frontmatter).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# MySQL best practices

The day-2 operations surface for MySQL 8.0+ (and MariaDB-when-bug-compatible; for MariaDB-specific deltas see `mariadb-deltas`). Sister to `postgres-best-practices`. The two engines differ enough that one general-SQL skill would cover neither well; per-engine is the vault pattern.

InnoDB is the storage engine for everything in this skill unless noted. MyISAM is legacy; do not use it for any table that ever takes a write outside maintenance windows. Memory tables are a niche; if you reach for one, surface the choice.

> **Skill marker**: When applying this skill, begin your reply with `[skill: mysql-best-practices]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the MySQL estate (version, replication topology, schema conventions, performance baselines) before recommending changes. Only ask the user for information not already covered or specific to this question.

Before answering, understand:

1. **Version and topology**
   - MySQL major version (8.0 LTS, 8.4 LTS, others)?
   - Single instance, primary-replica, group replication, or InnoDB Cluster?
   - Managed (RDS, Cloud SQL, Azure DB) or self-managed?

2. **Workload shape**
   - OLTP, reporting / OLAP, or mixed?
   - Read-heavy, write-heavy, or balanced?
   - Approximate row counts on the affected tables?

3. **Change context**
   - Schema change, query tuning, configuration change, or incident response?
   - Backup / snapshot in place before destructive operations?
   - Maintenance window and rollback plan?

---

## Iron rules

1. **utf8mb4 everywhere.** Database, table, column, connection. The deprecated `utf8` alias means utf8mb3 (no emoji, no astral plane). New schemas use `utf8mb4` collation `utf8mb4_0900_ai_ci` (MySQL 8.0+) or `utf8mb4_unicode_520_ci` (older).
2. **Every InnoDB table has an explicit primary key.** No exceptions. Without one InnoDB invents a 6-byte hidden ROWID that is invisible to query plans and replication.
3. **No I/O inside a transaction.** Open the transaction, do the writes, commit. Calling out to an HTTP API or a slow Python loop while a row is locked is how you get deadlocks at 03:00.
4. **Diagnose with EXPLAIN before tuning.** A guess at "this query is slow because of X" without an EXPLAIN is wrong as often as it is right.
5. **No destructive operation in production without a backup checkpoint.** DROP, TRUNCATE, large UPDATE / DELETE: snapshot first, or run in a transaction with a known rollback path, or use a soft-delete pattern.

## Schema design

### Primary key choice

| Choice | When | Notes |
|---|---|---|
| `BIGINT UNSIGNED AUTO_INCREMENT` | Default for any new table | Monotonic, 8 bytes, fits InnoDB's clustered-index assumption (sequential inserts cluster well). |
| `INT UNSIGNED AUTO_INCREMENT` | Tables that will provably stay below ~2B rows | Avoids the 32-bit-overflow rebuild but only if the row-count cap is genuinely true. |
| UUIDv4 (random) | Almost never as a PK | Random PKs fragment the InnoDB clustered index; rows insert into random pages; insert throughput tanks at scale. If you need a UUID, store it as a separate column and keep the PK monotonic. |
| UUIDv7 (time-ordered) | Acceptable as PK if you need a globally-unique identifier in the column | Roughly monotonic; mitigates the fragmentation problem. Store as `BINARY(16)` not `CHAR(36)` to halve the size. |
| Composite | When the natural identity is genuinely composite (junction tables, time-series with `(device_id, ts)`) | The leftmost column dictates the clustering order; pick it deliberately. |

### Data types

- Integers: `TINYINT` (1B), `SMALLINT` (2B), `MEDIUMINT` (3B), `INT` (4B), `BIGINT` (8B). Pick the smallest that fits the value range plus headroom. `UNSIGNED` doubles the positive range when negatives are not meaningful.
- Strings: `VARCHAR(n)` for variable-length up to 65535 bytes (limit applies to row, not column). `CHAR(n)` for fixed-length pad-with-space identifiers. `TEXT` family for long bodies (TINYTEXT 256, TEXT 64K, MEDIUMTEXT 16M, LONGTEXT 4G). TEXT is stored off-page; reading it is a separate fetch.
- Dates and times: `DATETIME(6)` for timestamps with microsecond precision (8 bytes). `TIMESTAMP` is range-limited (1970-2038) and timezone-converts on read; avoid for new schemas. Always store in UTC; see `utc-timestamps`.
- Decimals: `DECIMAL(p, s)` for money. **Never `FLOAT` or `DOUBLE` for currency.**
- JSON: native `JSON` type since 5.7. Stored as binary internally; selectable, indexable via generated columns. Do not abuse it as a schemaless escape hatch for fields that should be normalised.

### JSON columns

```sql
ALTER TABLE orders ADD COLUMN metadata JSON;
ALTER TABLE orders ADD COLUMN customer_tier
  VARCHAR(20) GENERATED ALWAYS AS (metadata->>"$.tier") VIRTUAL;
ALTER TABLE orders ADD INDEX idx_customer_tier (customer_tier);
```

The pattern: store the JSON, expose hot fields as virtual generated columns, index those. `VIRTUAL` columns cost zero storage. `STORED` columns cost storage but can be the leading column of an index more efficiently.

Do not use JSON to model relations that should be tables. If three out of every five queries select inside the JSON, the schema is wrong.

## Indexing

### Composite index ordering: equality then range

The single most useful indexing rule: in a composite index, put equality predicates first, then range predicates last.

```sql
-- query
SELECT * FROM events
WHERE tenant_id = ? AND created_at BETWEEN ? AND ?
ORDER BY created_at;

-- index
CREATE INDEX idx_events_tenant_created ON events (tenant_id, created_at);
```

Index on `(created_at, tenant_id)` would be wrong here: the range scan on `created_at` ends the seek path; the `tenant_id` check then has to scan all the matching range rows.

### Selectivity matters more than column order intuition

Selectivity = (distinct values / total rows). High-selectivity columns (high cardinality) belong earlier in the composite. A flag column with two values (`active`, `inactive`) at the leading edge of an index is wasted.

### Covering indexes

If an index includes every column the query reads, MySQL can answer the query from the index alone (index-only scan). Add the SELECT-list columns to the index when the query is hot.

```sql
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, status, amount, created_at);
```

The cost is index size and write amplification. Worth it for top-N hot queries; not worth it as a default.

### Find unused indexes

```sql
SELECT t.OBJECT_SCHEMA, t.OBJECT_NAME, t.INDEX_NAME
FROM performance_schema.table_io_waits_summary_by_index_usage t
WHERE t.INDEX_NAME IS NOT NULL
  AND t.OBJECT_SCHEMA NOT IN ('mysql','performance_schema','sys')
  AND t.COUNT_STAR = 0
ORDER BY t.OBJECT_SCHEMA, t.OBJECT_NAME;
```

Unused indexes cost write performance, storage, and InnoDB buffer-pool space. Drop them; do not keep "in case".

## Query optimisation

### EXPLAIN red flags

```sql
EXPLAIN ANALYZE SELECT ... ;
```

Watch for:

- `type: ALL` (full table scan) on a table with more than a few thousand rows.
- `Extra: Using filesort` on a sort that should hit an ordered index.
- `Extra: Using temporary` on a join or grouping; often a sign of a missing index.
- `rows` estimate orders of magnitude wrong (the optimiser is making bad choices because statistics are stale; `ANALYZE TABLE`).
- `Extra: Using join buffer (Block Nested Loop)` on a large join, especially with a hash join in 8.0.18+.

### OFFSET pagination is a trap

```sql
-- linear in OFFSET; at OFFSET=100000 this scans 100000 rows
SELECT * FROM events ORDER BY id LIMIT 20 OFFSET 100000;

-- keyset / seek pagination; constant time
SELECT * FROM events WHERE id > ? ORDER BY id LIMIT 20;
```

For deep pagination, keyset is the only viable pattern. Pass the last-seen ID instead of an offset.

### N+1

If you are selecting a parent row and then issuing one query per child, that is an N+1. Replace with a single JOIN, a single `WHERE id IN (...)` batched fetch, or an ORM eager-load. The detection rule: if the query log shows N near-identical queries differing only in a parameter, it is an N+1.

### Implicit type conversions break indexes

```sql
-- column is VARCHAR; the literal is INT; the index goes unused
SELECT * FROM users WHERE phone_number = 5551234567;

-- correct
SELECT * FROM users WHERE phone_number = '5551234567';
```

`EXPLAIN` shows the missed index. Type-cast the literal, not the column.

## Transactions and locking

### Isolation levels

| Level | Phantoms | Default? | Notes |
|---|---|---|---|
| READ UNCOMMITTED | Yes | No | Dirty reads. Almost never the right answer. |
| READ COMMITTED | Yes | No | Prevents dirty reads. Each statement sees a consistent snapshot of committed data. |
| REPEATABLE READ | No (in InnoDB, due to gap locks) | **Yes (MySQL default)** | Snapshot taken at first read; sees the same data for the whole transaction. InnoDB's gap-locking makes phantoms impossible at this level (PostgreSQL's REPEATABLE READ does not). |
| SERIALIZABLE | No | No | Strict; locks reads as if SELECT was SELECT FOR SHARE. Heavy. |

InnoDB's REPEATABLE READ default is the right choice for most applications. READ COMMITTED is sometimes used to reduce gap locking on hot tables; the trade-off is application-side handling of read inconsistency within a transaction.

### Deadlocks

Two transactions hold locks the other needs. InnoDB detects and aborts one (the smaller transaction); the application gets `ERROR 1213`.

Prevention:

1. **Consistent ordering of access.** If transaction A locks row 1 then row 2, every transaction that touches both must lock 1 then 2, never 2 then 1.
2. **Short transactions.** No I/O, no user-think-time, no slow Python loops between BEGIN and COMMIT.
3. **Smallest viable lock.** `SELECT ... FOR UPDATE` only when actually needed; `FOR SHARE` is lighter; pure SELECT does not lock at all under MVCC.
4. **Indexes on join and WHERE columns.** A WHERE without an index escalates to row-locks across the entire scanned range (gap locks).

When a deadlock happens, `SHOW ENGINE INNODB STATUS\G` shows the most recent one with the two transactions, the locks they held, and the locks they waited for.

### Gap locks (the InnoDB gotcha)

In REPEATABLE READ, InnoDB locks not just rows but the gaps between them, to prevent phantoms. Range-lock semantics surprise developers coming from Postgres or older MySQL. A query like `SELECT ... WHERE x BETWEEN 100 AND 200 FOR UPDATE` may lock the gap before 100, the gap after 200, and every gap between matched rows. Other transactions inserting into those gaps block.

Mitigations: drop to READ COMMITTED if the application tolerates it; narrow the WHERE; index the column being range-scanned.

## Operations

### Online DDL: pick the right ALGORITHM

```sql
ALTER TABLE orders ADD COLUMN promo_code VARCHAR(20), ALGORITHM=INSTANT;
```

| ALGORITHM | When MySQL chooses it | Lock | Notes |
|---|---|---|---|
| `INSTANT` (8.0.12+) | Add column at the end, drop column, rename column, set default | None | Metadata-only; instant. The cheapest path. Not all changes qualify. |
| `INPLACE` | Most index changes, modify column type compatible | Brief shared lock at start and end | Concurrent DML allowed during the operation. |
| `COPY` | Anything not above (e.g. column type change requiring rewrite, change of primary key) | Long shared lock; concurrent reads only | Can take hours on large tables. |

If MySQL would pick `COPY` and the table is large, **use `pt-online-schema-change` or `gh-ost`** instead. Both create a shadow table, copy data with throttling, and swap. Your application sees the change as instant; the operation runs in the background without blocking writes.

### Replication lag

Source-replica lag is the silent killer of read-after-write consistency. Watch:

```sql
SHOW REPLICA STATUS\G
-- Seconds_Behind_Source: 0 is healthy; >5 is concerning; >60 is an incident.
```

If you read from replicas, design for lag: route writes-followed-by-reads to the source (sticky session), or pass a wait-for-LSN annotation on the read.

Sources of lag: long-running transactions on the source, single-threaded replication on a high-volume schema, network saturation on the replication link, replica disk slow. Investigate, do not just bump alert thresholds.

### Connection pooling

MySQL's per-connection memory cost is real. `max_connections` of 1000 with 256 MB sort buffer per connection is a 256 GB ceiling.

Use a pooler in front (ProxySQL, MySQL Router, Percona ProxySQL, application-side pool with bounded limits). Pool size in front of MySQL = `max_connections - 10` (reserve 10 for admin and replication). Application pool size = (active workers per app instance) * (instance count); usually much smaller than `max_connections`.

### Backup discipline

- Logical: `mysqldump` (single-threaded; slow for large databases) or `mysqlpump` (parallel, MySQL 5.7+) or `mydumper` (parallel, third party).
- Physical: `xtrabackup` (Percona; hot, consistent, fast; the default for any database large enough that mysqldump times out).
- Always test restore. A backup that has never been restored is a wish, not a backup. Quarterly restore-drill cadence at minimum.

## Verification before claiming done

Per `completion-gate`, "I added an index" or "I tuned the query" is not a finish line. Before the chunk closes:

- [ ] EXPLAIN ANALYZE on the actual query, before and after, attached to the change.
- [ ] For schema changes: rollback path documented (the inverse migration runs and the reverse migration runs on a known-good replica).
- [ ] For index additions: monitored unused-index report a week later (the index is actually being used, or it gets removed).
- [ ] For replication-touching changes: Seconds_Behind_Source watched for at least one full traffic cycle after deploy.
- [ ] For DDL on a table over ~1M rows: ran via gh-ost or pt-online-schema-change, not raw ALTER unless ALGORITHM=INSTANT verified.

## Cross-references

- `postgres-best-practices`: sister skill for the other engine the vault covers; many shared patterns (EXPLAIN discipline, no-I/O-in-transaction, OFFSET pagination is bad) but engine-specific implementation differs.
- `mariadb-deltas`: when you are on MariaDB, read this skill for the shared 80% then `mariadb-deltas` for the differences.
- `forward-compatible-schemas`: every schema change in this skill must also be additive-compatible per the rename-via-add-then-flip pattern.
- `secrets-hygiene`: MySQL credentials, replication credentials, and pooler credentials all live in the secret store.
- `plan-time-tooling`: any chunk that touches schema, replication, or production DDL is an `engineering:deploy-checklist` trigger.
- `completion-gate`: the verification checklist above is the layer-3 gate.
- `systematic-debugging`: when a query is mysteriously slow, run the four-phase loop with EXPLAIN ANALYZE as the boundary evidence.
- `oncall-runbooks`: replication-lag, deadlock-storm, and connection-exhaustion runbooks live there; this skill is the technical source.
- `bash-defensive`: any `mysqldump | xz | aws s3 cp` backup script follows defensive-bash discipline.

## Red flags

- About to add a UUIDv4 column as the primary key of a write-heavy InnoDB table.
- About to leave a new schema without `utf8mb4` (default collation will silently be wrong).
- About to use `FLOAT` or `DOUBLE` for money.
- About to start a transaction with an HTTP call or slow Python loop inside it.
- About to pass `ORDER BY id LIMIT 20 OFFSET 1000000` for pagination.
- About to alter a 100M-row table with raw `ALTER TABLE` instead of gh-ost / pt-online-schema-change.
- About to fix a deadlock by raising the retry count instead of reordering the access pattern.
- About to disable `binlog` on a production instance "for performance".
- About to bump `max_connections` to fix a connection-exhaustion symptom that is actually pool misconfiguration.
- About to silently switch the isolation level from REPEATABLE READ to READ COMMITTED on a production cluster without an analysis of every transaction's reliance on snapshot semantics.
- About to commit a credential literal in `my.cnf` or in a tracked deploy script.
- About to read `Seconds_Behind_Source` once and call it stable. Watch a full traffic cycle.

## Bottom line

InnoDB plus utf8mb4 plus monotonic primary keys plus EXPLAIN-driven indexing covers 80% of MySQL well-being. Keep transactions short, never with I/O. Use online DDL tools for any large-table schema change. Watch replication lag and connection counts continuously. Verify with EXPLAIN ANALYZE before and after, and a tested restore behind every backup.
