---
name: sqlite-best-practices
description: Use for any SQLite design, query, schema, migration, backup, or operations work. Triggers include "SQLite", "SQLite schema", "SQLite pragma", "WAL mode", "journal_mode = wal", "PRAGMA foreign_keys", "PRAGMA busy_timeout", "STRICT tables", "WITHOUT ROWID", "INTEGER PRIMARY KEY", "rowid alias", "type affinity", "json1", "json_extract", "fts5", "rtree", "VACUUM INTO", "auto_vacuum", "incremental_vacuum", "RETURNING", "generated columns", "SQLITE_BUSY", "begin immediate", "savepoint", "SQLite migration", "ALTER TABLE limitation", "table recreation", "12-step migration", "SQLite backup", "online backup API", "VACUUM INTO", "wal_checkpoint", "SQLite over NFS", "SQLite locking_mode EXCLUSIVE", "embedded database", "edge SQLite", "Cloudflare D1", "Litestream", "rqlite". Covers schema discipline (STRICT default, INTEGER PRIMARY KEY rowid alias rule, type affinity hints not strict, money in cents, timestamps as ISO 8601 UTC text), connection pragmas (WAL + foreign_keys + busy_timeout + cache_size as the four-line baseline), concurrency model (one writer + many readers; SQLITE_BUSY remediation; separate read pool from write connection in multi-threaded apps), indexes (FK index always, partial index where status=, EXPLAIN QUERY PLAN before adding), STRICT tables (3.37+; allowed types integer / real / text / blob / any), WITHOUT ROWID (composite or text PK with small rows; never with INTEGER PRIMARY KEY alone), generated columns (3.31+; VIRTUAL vs STORED with index implication), RETURNING (3.35+), backups (VACUUM INTO is the safe default; never copy .db while connections are open; reflink copy after wal_checkpoint TRUNCATE for migration backups), VACUUM and maintenance (auto_vacuum incremental for large databases), 14-row anti-pattern table including SQLite-over-NFS-causes-corruption rule, 13-item new-schema checklist, ALTER TABLE limitations and the 12-step table-recreation pattern. Self-authored from public SQLite documentation rather than folded (Chogos/claude-skills and MSch/skills both unlicenced upstreams; vault discipline requires explicit licence provenance per the graylog precedent). Inspired structurally by both upstreams.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# SQLite best practices

SQLite is the file-per-database, in-process, embedded relational engine that powers more apps than every other database combined (it ships in every browser, every Android, every iOS, every Mac). The deployment model is fundamentally different from MySQL or Postgres: there is no server, no network, no socket. The application opens a file, runs SQL against it, closes the file. That model is the source of every SQLite virtue (zero ops, atomic writes, single-file backups) and every SQLite trap (one writer at a time, no privilege model, no replication).

Sister to `mysql-best-practices` and `postgres-best-practices`. Use this when the engine actually is SQLite; do not assume MySQL or Postgres patterns transfer.

> **Skill marker**: When applying this skill, begin your reply with `[skill: sqlite-best-practices]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand how SQLite is being used in the project (embedded library, application-process database, file format, test fixture) and the concurrency model before recommending changes. Only ask the user for information not already covered or specific to this question.

Before answering, understand:

1. **Embedding context**
   - In-application library (Python sqlite3, Go modernc, Rust rusqlite), CLI tool, or a third-party application's data file?
   - Read-only consumer, read-write owner, or shared across multiple processes?
   - File path on local disk, network share (NFS / SMB), or in-memory `:memory:`?

2. **Workload**
   - Concurrency expectations (single writer, occasional concurrent readers, many concurrent readers)?
   - Write rate and transaction size?
   - Database size today and projected?

3. **Change context**
   - New schema, pragmas / journal-mode tuning, migration from another engine, or troubleshooting?
   - Backups and snapshots in place before destructive operations?

---

## Iron rules

1. **Never use SQLite over a network filesystem (NFS, SMB, GlusterFS).** File-locking semantics on remote filesystems are unreliable; corruption is the consistent outcome. SQLite must be on a local filesystem. Always.
2. **Set the four base pragmas on every connection.** `journal_mode = WAL`, `foreign_keys = ON`, `busy_timeout = 5000`, `synchronous = NORMAL`. The defaults are wrong for almost every workload.
3. **One writer at a time, period.** SQLite serialises writes. Multi-writer architectures need either coordination (one process owns the writer connection, others queue requests through it) or a different engine.
4. **`INTEGER PRIMARY KEY` is the rowid alias.** Spelt full word, any case. `INT PRIMARY KEY`, `BIGINT PRIMARY KEY`, `INTEGER PRIMARY KEY AUTOINCREMENT` are all subtly different and usually not what you want.
5. **Money in INTEGER cents, never REAL.** Same rule as MySQL and Postgres; SQLite's REAL is IEEE 754 double; rounding errors compound.
6. **Backups via `VACUUM INTO` (or the online backup API), never via `cp` of an open database.** Copying the `.db` file while connections are open risks corruption, especially in WAL mode where `-wal` and `-shm` files must stay consistent with the main file.

## Type affinity (the SQLite peculiarity)

SQLite uses **type affinity**, not strict types. The declared type is a hint about how to store values, not a constraint. `CREATE TABLE t (x INT)` will happily accept `INSERT INTO t VALUES ('hello')`. This is intentional but surprising.

Two responses:

| When | Use |
|---|---|
| Default for new schemas (3.37+) | `STRICT` tables; types are enforced. |
| Legacy compatibility, sub-3.37 | Affinity tables; rely on `CHECK` constraints for domain rules. |

Recommended type column-by-column:

| Use | Declared type | Notes |
|---|---|---|
| Integer PK | `INTEGER` | Full word, any case. Becomes the rowid alias. |
| Other integer | `INTEGER` | |
| Text | `TEXT` | |
| Floating point | `REAL` | Not for money. |
| Boolean | `INTEGER` (0 / 1) | Add `CHECK (col IN (0, 1))`. |
| Timestamps | `TEXT` (ISO 8601 UTC) | `'2026-05-10T07:50:00Z'`. See `utc-timestamps`. |
| UUID | `TEXT` | Or `BLOB` for compact 16 bytes. |
| Money | `INTEGER` (smallest currency unit; cents) | `REAL` loses precision. |
| Binary | `BLOB` | |
| JSON | `TEXT` with `CHECK (json_valid(col))` | Native JSON support comes via the `json1` extension; ships in every modern build. |

## Connection pragmas (the four-line baseline)

```sql
PRAGMA journal_mode = WAL;       -- concurrent readers; one writer
PRAGMA foreign_keys = ON;        -- not enforced by default
PRAGMA busy_timeout = 5000;      -- wait 5s on a lock instead of erroring immediately
PRAGMA synchronous = NORMAL;     -- safe with WAL; faster than FULL
```

Optional but commonly worth it:

```sql
PRAGMA cache_size = -65536;      -- 64 MB page cache (negative = kibibytes)
PRAGMA temp_store = MEMORY;      -- temp tables in RAM
PRAGMA mmap_size = 268435456;    -- 256 MB memory-mapped reads
```

These pragmas are **per connection** (except `journal_mode`, which persists in the file). Set them every time the application opens a connection, including the migration connection, the maintenance connection, every read connection in the pool, and the write connection.

## Concurrency model

WAL mode allows readers and one writer to operate concurrently. Without WAL (the default), any write blocks all readers. **Turn on WAL.**

Even with WAL, only one writer at a time. SQLite serialises writes via a file lock. Concurrent write attempts block until the lock is released or `busy_timeout` expires. After timeout, the writer gets `SQLITE_BUSY`.

For multi-threaded applications:

- **Write connection.** One long-lived connection. Serialise access via a mutex or a queue. Every write goes through it.
- **Read pool.** A small pool (2-4 connections is usually enough; SQLite reads are very fast). Each connection sets its own pragmas.

If you see `SQLITE_BUSY` despite a 5s `busy_timeout`, the cause is usually a long-running read transaction holding a WAL checkpoint. Keep read transactions short; consider `PRAGMA wal_autocheckpoint` tuning.

## Schema discipline

### Foreign keys must be enabled

```sql
PRAGMA foreign_keys = ON;
```

**Per connection. Disabled by default.** A FK constraint declared in the schema is silently ignored if the connection has not enabled them.

### Constraints

Push as much invariant as possible into the schema. SQLite's CHECK constraints are cheap and durable.

```sql
CREATE TABLE order_item (
    id          INTEGER PRIMARY KEY,
    order_id    INTEGER NOT NULL REFERENCES "order"(id) ON DELETE CASCADE,
    product_id  INTEGER NOT NULL REFERENCES product(id) ON DELETE RESTRICT,
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    unit_price  INTEGER NOT NULL CHECK (unit_price >= 0),  -- cents
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;
```

### STRICT tables (3.37+; the modern default)

```sql
CREATE TABLE product (
    id    INTEGER PRIMARY KEY,
    sku   TEXT    NOT NULL UNIQUE,
    name  TEXT    NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0)
) STRICT;
```

Allowed types in STRICT: `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY`. Wrong-type inserts fail rather than silently coerce. Use STRICT unless there is a specific compatibility reason not to.

Combine with `WITHOUT ROWID` if appropriate: `... ) STRICT, WITHOUT ROWID;`.

### WITHOUT ROWID (selective use)

```sql
CREATE TABLE tag_assignment (
    tag_id  INTEGER NOT NULL REFERENCES tag(id),
    item_id INTEGER NOT NULL REFERENCES item(id),
    PRIMARY KEY (tag_id, item_id)
) WITHOUT ROWID;
```

Use when:

- Composite PK or non-integer PK.
- Rows are small (under ~200 bytes for 4 KB pages).

**Do NOT** use with a single `INTEGER PRIMARY KEY` (regular rowid tables are faster for that).

### Generated columns (3.31+)

```sql
CREATE TABLE event (
    id      INTEGER PRIMARY KEY,
    payload TEXT NOT NULL CHECK (json_valid(payload)),
    user_id INTEGER GENERATED ALWAYS AS (payload ->> 'user_id') VIRTUAL,
    kind    TEXT    GENERATED ALWAYS AS (payload ->> 'kind')    STORED
);
CREATE INDEX idx_event_user_id ON event(user_id);
CREATE INDEX idx_event_kind    ON event(kind);
```

`VIRTUAL`: zero storage; recomputed on every read.
`STORED`: stored on disk; can be the leading column of an index efficiently.

The `->>` operator needs 3.38+. Use `json_extract()` for older builds.

## Indexes

Same rules as the other engines: an index on every FK column, composite indexes that put equality first then range, EXPLAIN QUERY PLAN before adding, drop unused.

```sql
-- FK index (always)
CREATE INDEX idx_order_item_order_id ON order_item(order_id);

-- Composite (column order matches WHERE filter and ORDER BY)
CREATE INDEX idx_order_status_created ON "order"(status, created_at DESC);

-- Partial index (3.8.9+; reduces index size dramatically when most rows do not qualify)
CREATE INDEX idx_order_pending ON "order"(created_at) WHERE status = 'pending';
```

There is no `INCLUDE` clause in SQLite. To get a covering scan, list the columns directly in the index key.

```sql
EXPLAIN QUERY PLAN
SELECT id, title FROM "order"
WHERE status = 'pending' AND created_at > ?;
```

Read the output: `SEARCH order USING INDEX idx_order_pending` is good; `SCAN order` is a full table scan and almost always wrong on a non-trivial table.

## Transactions

```sql
BEGIN IMMEDIATE;
  UPDATE account SET balance = balance - 100 WHERE id = ?;
  UPDATE account SET balance = balance + 100 WHERE id = ?;
  INSERT INTO transfer_log (from_id, to_id, amount) VALUES (?, ?, 100);
COMMIT;
```

**`BEGIN IMMEDIATE` for writes.** It acquires the write lock at BEGIN, not on first write. Avoids the `SQLITE_BUSY` you would get from a lock-upgrade mid-transaction.

`BEGIN DEFERRED` (the default plain `BEGIN`) is fine for read-only transactions. It does not lock until the first read.

`SAVEPOINT name` for nested rollback: `ROLLBACK TO SAVEPOINT name` on error, `RELEASE SAVEPOINT name` on success.

### RETURNING (3.35+)

```sql
INSERT INTO product (sku, name, price) VALUES (?, ?, ?)
RETURNING id, created_at;

UPDATE "order" SET status = 'shipped' WHERE id = ?
RETURNING id, status;

DELETE FROM session WHERE expires_at < strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
RETURNING id;
```

One round-trip instead of two.

## Migrations and the ALTER TABLE limitation

SQLite's `ALTER TABLE` is sharply limited compared to MySQL or Postgres:

| Operation | Supported | Workaround if not |
|---|---|---|
| Add column | Yes (3.0+) | |
| Add column with NOT NULL DEFAULT | Yes (3.3.0+) | |
| Drop column | Yes (3.35.0+) | 12-step recreate on older versions |
| Rename column | Yes (3.25.0+) | 12-step recreate on older versions |
| Rename table | Yes | |
| Change column type | **No** | 12-step recreate |
| Add CHECK constraint to existing column | **No** | 12-step recreate |
| Drop FK constraint | **No** | 12-step recreate |
| Reorder columns | **No** | 12-step recreate (rarely needed) |

**The 12-step table-recreation pattern** (from the SQLite official docs):

```sql
PRAGMA foreign_keys = OFF;
BEGIN;
  CREATE TABLE new_t (...);                      -- new shape
  INSERT INTO new_t SELECT ... FROM t;           -- copy data
  DROP TABLE t;
  ALTER TABLE new_t RENAME TO t;
  -- recreate indexes, triggers, views that referenced t
  PRAGMA foreign_key_check;                      -- verify FK integrity
COMMIT;
PRAGMA foreign_keys = ON;
```

For application migration tooling (`yoyo`, `dbmate`, `goose`, `flyway`, custom scripts), the migrator should:

- Use a single dedicated SQLite connection for the whole migration.
- Take an exclusive lock on the database (`PRAGMA locking_mode = EXCLUSIVE` plus a real schema read like `SELECT name FROM sqlite_master WHERE type = 'table' LIMIT 1` to actually acquire it; `SELECT 1` does not touch the file and does not lock).
- Coordinate with the application via an OS-level lock file (`<db>.migrate.lock` with `flock`) so the application waits for the migrator to finish.

## Backup discipline

Three options, in order of preference:

### 1. `VACUUM INTO` (3.27.0+; the default)

```sql
VACUUM INTO '/path/to/backup.db';
```

Creates a consistent point-in-time copy without blocking other connections. The output file is a clean, defragmented database. Safe to run while the source is in use.

### 2. The online backup API

Programmatic, page-level, incremental. Use when you need to copy in chunks (e.g. across a network without holding the source locked for the duration). Almost every SQLite binding exposes this.

### 3. `cp --reflink=always` after `wal_checkpoint(TRUNCATE)`

For migration-time backups when you control all clients:

```sql
PRAGMA wal_checkpoint(TRUNCATE);
-- check: busy = 0; checkpointed_frames == log_frames
-- now copy the main DB file (no -wal, no -shm needed)
```

Then `cp --reflink=always source.db backup.db` (filesystem-level zero-copy on btrfs, XFS reflinks, APFS).

**Never plain-copy an open database.** If you `cp foo.db backup.db` while a writer is in flight, the resulting file will be corrupt at the next read.

## Vacuum and maintenance

SQLite does not reclaim disk space after deletes. The file keeps its high-water-mark size.

```sql
-- One-shot full reclaim. Rewrites the entire database; blocks all access; needs 2x DB size in free space.
VACUUM;

-- Incremental auto-vacuum (must be set BEFORE creating tables; cannot enable later)
PRAGMA auto_vacuum = INCREMENTAL;
PRAGMA incremental_vacuum(100);   -- reclaim up to 100 pages

-- Integrity verification (full; slow)
PRAGMA integrity_check;

-- Quick check (faster; less thorough)
PRAGMA quick_check;
```

For databases over a few hundred MB, prefer `auto_vacuum = INCREMENTAL` set at creation time, with periodic `incremental_vacuum` calls. A full `VACUUM` on a 10 GB database is an outage.

Run `PRAGMA optimize` on connection close (3.18+) or `PRAGMA optimize = 0x10002` on connect (3.46+) to update query-planner statistics for any tables modified since the last analyze.

## Anti-patterns and fixes

| Anti-pattern | Fix |
|---|---|
| Missing `PRAGMA foreign_keys = ON` per connection | Set in connection-open helper, every time. |
| `REAL` for money | `INTEGER` cents (divide by 100 for display). |
| Epoch integers for timestamps | ISO 8601 UTC `TEXT`. Sortable, human-readable, timezone-explicit. |
| `AUTOINCREMENT` keyword by default | Omit. `INTEGER PRIMARY KEY` is the rowid alias and gives auto-increment. `AUTOINCREMENT` adds a slower monotonic guarantee that is rarely required. |
| Bare `BEGIN` for writes | `BEGIN IMMEDIATE` to avoid lock-upgrade `SQLITE_BUSY`. |
| `SELECT *` in application code | Name columns explicitly. |
| String-concatenated queries | Parameterised (`?` or `:name`). |
| Missing index on FK column | Add an index for every FK. |
| JSON in TEXT without validation | `CHECK (json_valid(col))`. |
| One shared connection for reads and writes in a multi-threaded app | One write connection serialised; pool of read connections. |
| Never running `VACUUM` | Schedule periodic full `VACUUM` during quiet windows, or `auto_vacuum = INCREMENTAL` from creation. |
| Copying `.db` while open | `VACUUM INTO` or the backup API. |
| **SQLite over NFS / SMB / network filesystem** | **Always local. Network FS causes corruption.** |
| `INT PRIMARY KEY` instead of `INTEGER PRIMARY KEY` | Full word `INTEGER` to get the rowid alias. |
| `SELECT 1` to "hold a lock" | Lock acquisition needs a real schema read; `SELECT 1` does not touch the file. |

## New schema checklist

- [ ] All columns have explicit types and a NOT NULL / nullable decision.
- [ ] `INTEGER PRIMARY KEY` (full word) for auto-increment PK.
- [ ] FKs declared with explicit ON DELETE behaviour.
- [ ] CHECK constraints for domain rules; `json_valid(col)` for any JSON column.
- [ ] Index on every FK column.
- [ ] STRICT considered (default for new tables on 3.37+).
- [ ] WITHOUT ROWID considered for composite or text PKs with small rows.
- [ ] Connection-open helper sets `journal_mode=WAL`, `foreign_keys=ON`, `busy_timeout=5000`, `synchronous=NORMAL`.
- [ ] Backup strategy chosen (`VACUUM INTO` or backup API).
- [ ] `EXPLAIN QUERY PLAN` run on every hot query.
- [ ] No SQLite-over-NFS in any deployment target.

## Edge SQLite (Cloudflare D1, Litestream, rqlite, libSQL / Turso)

The "SQLite as a service" ecosystem matters. Differences from a vanilla local-file SQLite:

- **Cloudflare D1**: SQLite at the edge with replication. No `BEGIN IMMEDIATE`; transactions are batched at HTTP level. No `PRAGMA` access for most settings (D1 controls them). FK enforcement on by default.
- **Litestream**: streams the WAL to S3 (or compatible) for continuous backup. Adds no read or write latency; recovery is a restore-from-S3 + replay. Free, simple, very effective for single-writer apps.
- **rqlite**: distributed SQLite via Raft consensus. Strong consistency at the cost of write latency. One-writer rule still applies (the leader is the writer).
- **libSQL / Turso**: SQLite fork with embedded replicas, sync, and HTTP API. Modifies the type system and concurrency in non-trivial ways; read their docs before assuming compatibility.

If your deployment is one of these, this skill still applies for schema design and query patterns. Read the platform's docs for connection management and transaction semantics.

## Verification before claiming done

Per `completion-gate`, "I added a SQLite table" is not a finish line. Before the chunk closes:

- [ ] Connection helper sets all four base pragmas (verified by reading them back: `PRAGMA journal_mode;` returns `wal`).
- [ ] EXPLAIN QUERY PLAN on every new hot query; no `SCAN tablename` on tables over a few thousand rows.
- [ ] FK integrity verified post-migration: `PRAGMA foreign_key_check;` returns no rows.
- [ ] `PRAGMA integrity_check;` passes after any migration that recreates tables.
- [ ] Backup taken before migration (`VACUUM INTO` or reflink-after-checkpoint).
- [ ] Restore tested from the backup on a non-production path; the restored DB opens, foreign-key-check passes, top queries return expected results.
- [ ] If WITHOUT ROWID was used: row-size is genuinely small (under ~200 bytes); test with `pragma page_count` before and after to confirm the storage win.

## Cross-references

- `mysql-best-practices`, `mariadb-deltas`, `postgres-best-practices`: sister skills for the other engines. Many indexing and EXPLAIN patterns transfer; concurrency and operations do not.
- `forward-compatible-schemas`: SQLite's ALTER TABLE limitations make additive-only schema discipline more important, not less; renames go via add-new-column, dual-write, flip-readers, drop.
- `secrets-hygiene`: SQLite has no built-in user / privilege model. Access control is filesystem permissions. The DB file's owner and group matter.
- `plan-time-tooling`: any chunk that touches a SQLite migration in production (especially on shared edge platforms like D1) is an `engineering:deploy-checklist` trigger.
- `completion-gate`: the verification checklist above is the layer-3 gate.
- `systematic-debugging`: when SQLITE_BUSY is mysterious, the four-phase loop with `PRAGMA database_list` plus `pragma_database_list` plus connection-trace logging is the boundary-evidence step.
- `oncall-runbooks`: SQLite "database is locked" runbooks live there; fix is almost always to find the long-running read transaction.
- `bash-defensive`: any backup automation script (sqlite3 .dump, VACUUM INTO, reflink copy) follows defensive-bash discipline.
- `utc-timestamps`: `'%Y-%m-%dT%H:%M:%SZ'` is the SQLite-standard ISO 8601 UTC strftime format; do not deviate.
- `linux-host-ops`: SQLite databases live on filesystems; backups, permissions, log rotation, and disk-space monitoring all surface in linux-host-ops.

## Red flags

- About to deploy SQLite onto NFS, SMB, EFS, GlusterFS, or any other network filesystem.
- About to leave a connection without `PRAGMA foreign_keys = ON`.
- About to use REAL for money or REAL for any value where 0.1 + 0.2 = 0.30000000000000004 will bite.
- About to copy a live `.db` file with `cp` instead of `VACUUM INTO` or the backup API.
- About to use `INT PRIMARY KEY` and wonder why auto-increment does not work the way you expected.
- About to start a write transaction with bare `BEGIN` instead of `BEGIN IMMEDIATE`.
- About to rely on a CHECK constraint without using STRICT or testing wrong-type inserts.
- About to set `auto_vacuum = INCREMENTAL` on an existing database (it must be set before any tables are created; setting later does nothing).
- About to use `SELECT 1` as a "lock-acquiring" no-op (it does not touch the file).
- About to share one SQLite connection across N application threads without serialising writes.
- About to schedule a full `VACUUM` on a 50 GB SQLite database during business hours.
- About to ship a SQLite-based service with no backup automation. The single-file model means the file is the entire database; lose it and lose everything.
- About to assume Cloudflare D1, libSQL, or rqlite behave like local SQLite without reading their concurrency and transaction docs.

## Bottom line

WAL plus the four-line pragma baseline plus STRICT plus INTEGER PRIMARY KEY plus money-as-cents plus ISO-8601-UTC text timestamps covers 80% of SQLite well-being. One writer at a time; never on NFS; backup via VACUUM INTO; migrations via the 12-step recreate when ALTER TABLE cannot do it. SQLite is wonderfully simple as long as you respect what makes it different from MySQL and Postgres.

## External resources

- SQLite documentation: https://www.sqlite.org/docs.html
- Type affinity: https://www.sqlite.org/datatype3.html
- WAL mode: https://www.sqlite.org/wal.html
- 12-step table-recreation pattern: https://www.sqlite.org/lang_altertable.html#otheralter
- STRICT tables: https://www.sqlite.org/stricttables.html
- Online backup API: https://www.sqlite.org/backup.html
- `PRAGMA optimize`: https://www.sqlite.org/pragma.html#pragma_optimize
