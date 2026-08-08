---
name: postgres-best-practices
description: "Use when writing, reviewing, or optimising Postgres queries, schema designs, or database configurations (any project on Postgres regardless of vendor: bare Postgres, RDS, Supabase, Neon, Crunchy, Aiven, Azure Postgres). Triggers include \"this query is slow\", \"review my SQL\", \"design this schema\", \"do I need an index here\", \"set up RLS\", \"tune connection pooling\", \"optimise this Postgres query\", \"the database is hitting its connection limit\". Covers 8 categories of Postgres rules prioritised by impact: query performance (CRITICAL), connection management (CRITICAL), security and Row-Level Security (CRITICAL), schema design (HIGH), concurrency and locking (MEDIUM-HIGH), data access patterns (MEDIUM), monitoring and diagnostics (LOW-MEDIUM), advanced features (LOW). Vendor-agnostic; the rules apply to any Postgres deployment regardless of who hosts it. Localised adaptation of supabase/agent-skills/supabase-postgres-best-practices."
metadata:
  version: 1.0.0
---

# Postgres Best Practices

> **Skill marker**: When applying this skill, begin your reply with `[skill: postgres-best-practices]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Eight categories of Postgres rules ordered by impact. Rules in the higher-priority categories pay back the largest performance wins for the least work; lower-priority ones are polish. Apply the higher categories first when reviewing a new codebase or optimising an existing one.

**Core principle:** measure first (per `systematic-debugging` Phase 1 evidence-gathering); then apply the rule that addresses the actual bottleneck. Premature optimisation wastes time.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Postgres estate (version, deployment surface, connection-pool layout, RLS posture) before recommending changes. Only ask the user for information not already covered or specific to this question.

Before answering, understand:

1. **Version and deployment**
   - Postgres major version (14, 15, 16, 17, others)?
   - Surface (bare metal, RDS, Supabase, Neon, Crunchy, Aiven, Azure, Cloud SQL)?
   - Connection pooling (PgBouncer, native pooler, application-side)?

2. **Workload and rules priority**
   - OLTP, analytics, or mixed?
   - Symptom area (slow query, connection exhaustion, RLS / multi-tenant, schema, locking)?
   - Which rule category (1-8) is most relevant to the question?

3. **Change context**
   - Schema change, query tuning, configuration change, or incident response?
   - `pg_stat_statements` / `auto_explain` available for evidence?
   - Maintenance window and rollback plan?

---

## When to use

- Writing or reviewing SQL queries (per-query: ergonomic vs slow patterns).
- Designing or reviewing a schema (table layout, column types, normalisation level).
- Implementing or auditing indexes (which to add, which to drop, partial vs full).
- Reviewing a database performance issue (slow queries, lock contention, connection exhaustion).
- Configuring connection pooling (PgBouncer, native pooler, application-side).
- Setting up Row-Level Security (RLS) for multi-tenant or security-sensitive workloads.
- Reviewing for Postgres-specific features (JSONB, full-text search, partitioning, materialised views).

Vendor-agnostic: applies to bare Postgres, RDS, Supabase, Neon, Crunchy, Aiven, Azure Postgres, GCP Cloud SQL, etc. Vendor-specific tuning (connection limits per tier, autoscaling behaviour) is a separate discussion.

## Rule categories

| Priority | Category | Impact | Typical wins |
|---|---|---|---|
| 1 | Query performance | CRITICAL | 10x to 1000x query speedup; biggest single category |
| 2 | Connection management | CRITICAL | Prevents the "database fell over" outage class |
| 3 | Security and RLS | CRITICAL | Prevents tenant leakage; correctness over speed |
| 4 | Schema design | HIGH | Compounds: bad schema makes every query slower forever |
| 5 | Concurrency and locking | MEDIUM-HIGH | Prevents deadlocks under load |
| 6 | Data access patterns | MEDIUM | Reduces wasted egress and CPU |
| 7 | Monitoring and diagnostics | LOW-MEDIUM | You cannot fix what you cannot see |
| 8 | Advanced features | LOW | Specialised wins (full-text search, partitioning, JSONB indexing) |

## Category 1: Query performance (CRITICAL)

The biggest payoff category. Most slow Postgres apps have query problems before anything else.

### Rules

- **Always EXPLAIN ANALYSE before optimising.** Without the plan, you are guessing. `EXPLAIN (ANALYSE, BUFFERS)` shows the actual rows, time, and buffer hits per node.
- **Add the missing index.** A sequential scan on a large table is the most common slow-query cause. Index the columns used in WHERE / JOIN / ORDER BY.
- **Use partial indexes for selective predicates.** When most rows have one value of a column (e.g. `status='active'`), a partial index `WHERE status='active'` is smaller and faster than a full index.
- **Composite indexes follow the leftmost-prefix rule.** An index on `(user_id, created_at)` covers `WHERE user_id=?` and `WHERE user_id=? AND created_at>?`, but NOT `WHERE created_at>?` alone.
- **Avoid functions on indexed columns in WHERE.** `WHERE LOWER(email)=?` cannot use an index on `email`; either store the lowered value (generated column) or create an expression index `CREATE INDEX ON users(LOWER(email))`.
- **JOIN on indexed columns.** Joins without indexes on the join keys force nested loops over full tables.
- **Beware OR clauses; UNION can be faster.** `WHERE col=A OR col=B` may not use an index well; `WHERE col=A UNION ... col=B` often does.
- **LIMIT requires an ORDER BY.** Without it, Postgres returns "any" rows in indeterminate order; the query plan changes between runs.

## Category 2: Connection management (CRITICAL)

Postgres connections are expensive (roughly 10MB each, plus per-connection memory). Apps that open one connection per request crash the database under load.

### Rules

- **Always use a connection pooler.** PgBouncer (transaction mode) or your platform's native pooler (Supabase, Neon, RDS Proxy). Application-side pooling (HikariCP, pg-pool, SQLAlchemy pooling) is necessary too; the pooler pools across app instances.
- **Set application pool size sensibly.** Total connections from all app instances should stay well below the database's `max_connections`. Rule of thumb: `max_connections / num_app_instances - safety margin`.
- **Use transaction-mode pooling for short queries.** Session-mode pooling holds connections for the whole session; transaction-mode releases between statements. Transaction-mode breaks features that depend on session state (`PREPARE`, `LISTEN`, advisory locks); audit before switching.
- **Monitor connection-pool depletion.** Alert at 70% of pool capacity; at 90% the app is one spike from outage.
- **Close connections promptly in scripts.** Long-running scripts that open a connection and never release it eat slots that real traffic needs.

## Category 3: Security and Row-Level Security (CRITICAL)

Get this wrong and you leak data across tenants. Correctness, not speed.

### Rules

- **Use RLS for multi-tenant data.** Define policies per table; enforce in the database, not just in the application. Application-only checks fail when a developer writes a new query that forgets the tenant filter.
- **Set the tenant identifier per session.** RLS policies typically read from `current_setting('app.tenant_id')`. The connection pooler (transaction mode) means you must set this PER STATEMENT or use a `BEGIN; SET LOCAL ...; ... COMMIT;` block.
- **Test RLS with the actual role.** A policy that works for the table owner may not work for the application role. Use `SET ROLE application_role; SELECT ...` to verify.
- **Audit `BYPASSRLS`.** Roles with this attribute skip RLS entirely. Default to no role having it; promote with explicit justification.
- **Parameterise everything.** Never concatenate user input into SQL; always parameterise. SQL injection through a missed parameter is still the most common Postgres CVE class.
- **Encrypt at rest and in transit.** TLS to the database is non-negotiable; at-rest encryption is platform-provided on managed services.

## Category 4: Schema design (HIGH)

Schema decisions compound: a bad schema makes every query slower forever, every migration harder, every consumer more brittle.

### Rules

- **Normalise to 3NF first; denormalise with deliberate measurement.** Premature denormalisation creates update anomalies you'll fight for years.
- **Use the right type.** `INTEGER` (not `NUMERIC`) for counts; `TIMESTAMPTZ` (not `TIMESTAMP`) for timestamps; `TEXT` (not `VARCHAR(N)`) for variable-length text; `BOOLEAN` for booleans, not `INTEGER 0/1`. The `utc-timestamps` skill enforces TIMESTAMPTZ-everywhere.
- **Foreign keys with ON DELETE / ON UPDATE clauses.** Implicit cascade behaviour is a bug-source. Explicitly choose `RESTRICT`, `CASCADE`, or `SET NULL`.
- **Constraints at the database, not just the app.** `NOT NULL`, `CHECK`, `UNIQUE`, foreign-key. Apps reading concurrently will violate any rule the app forgets to enforce.
- **JSONB for genuinely schemaless data.** Not for "I'll figure out the columns later" (that's a deferred decision; surface and decide). JSONB has limited indexability (GIN indexes work but are slow to build); columns are faster.
- **Partition large tables.** Table sizes over ~50GB or row counts over ~100M start to slow down vacuum, autoanalyse, and queries. Partition by date or tenant.
- **Forward-compatible schema changes.** Per `forward-compatible-schemas`: additive within a release; renames go via add, double-write, flip readers, drop.

## Category 5: Concurrency and locking (MEDIUM-HIGH)

Under load, locks become contention, contention becomes deadlocks, deadlocks become outages.

### Rules

- **Read the lock acquisition order.** Two transactions taking locks in different orders deadlock. Document the canonical lock order per table; enforce in code.
- **Use `SELECT FOR UPDATE` only when necessary.** It locks rows for the rest of the transaction; long-running transactions hold the locks unnecessarily.
- **Prefer `SELECT FOR UPDATE SKIP LOCKED` for queue patterns.** Workers that contend for the same queue use SKIP LOCKED to grab unlocked rows without blocking each other.
- **Keep transactions short.** Long transactions block VACUUM (autovacuum cannot reclaim dead rows visible to old transactions); they hold locks; they accumulate dirty pages.
- **Set `lock_timeout` for risky operations.** A migration that adds a column on a hot table can wait for an exclusive lock that never comes; `SET lock_timeout = '10s'` aborts instead of blocking forever.
- **Use advisory locks for app-level coordination.** `pg_advisory_xact_lock(some_id)` is a lightweight cross-process lock that auto-releases on transaction end.

## Category 6: Data access patterns (MEDIUM)

How the application talks to the database matters as much as how the queries are written.

### Rules

- **Avoid SELECT \*.** Specify columns; large columns (TEXT, JSONB, BYTEA) get transferred over the wire even if the app discards them. The `postgres-egress-optimizer` skill covers this in depth.
- **Always paginate list endpoints.** Unbounded queries are an unbounded egress risk; one big table makes the endpoint hostile.
- **Push aggregation into SQL.** Application-side `.reduce()` over fetched rows transfers the full dataset; `SELECT COUNT(*), SUM(...) FROM ...` returns the result.
- **Cache static data outside the database.** Configuration tables, role definitions, feature flags hit on every request belong in a cache (Redis, in-process) not the database.
- **Beware N+1 queries.** ORMs love these. One query for the list, then N queries for each item's children. Fix with eager loading or a single JOIN.

## Category 7: Monitoring and diagnostics (LOW-MEDIUM)

You cannot fix what you cannot see. Set this up before you need it.

### Rules

- **Enable `pg_stat_statements`.** Per-query call count, total time, average time, total rows. The single most useful Postgres diagnostic. Available by default on most managed services; needs `CREATE EXTENSION` once.
- **Log slow queries.** `log_min_duration_statement = '500ms'` (tune to taste) writes any query over the threshold to the log.
- **Alert on connection-pool depletion, replication lag, and deadlock count.** Three alerts that catch most pre-outage signals.
- **Track table and index sizes.** `pg_size_pretty(pg_total_relation_size('table'))` for tables; `pg_size_pretty(pg_relation_size('index'))` for indexes. Anomalous growth often signals a bug (loop inserting forever, missing TTL).

## Category 8: Advanced features (LOW)

Specialised wins for specific use cases. Not core.

### Rules

- **Full-text search via `tsvector` and `tsquery`.** Faster than LIKE for prose. Pair with a GIN index. Consider materialised tsvector columns for performance.
- **Materialised views for expensive aggregations.** Refresh on a schedule when the underlying data is mostly read.
- **Range types for time / numeric ranges.** `tstzrange` for time ranges with overlap detection via `&&`. Pair with GIST indexes.
- **GIN indexes for JSONB and array columns.** Slow to build; fast to query. Necessary for production JSONB queries.

## Cross-references

- `postgres-egress-optimizer`: when the database bill is high or queries are returning more data than the app uses; the diagnostic + fix loop.
- `forward-compatible-schemas`: schema changes within a release are additive; renames go via add, double-write, flip readers, drop.
- `utc-timestamps`: TIMESTAMPTZ everywhere; never plain TIMESTAMP.
- `secrets-hygiene`: database credentials in gitignored files; per-deployment connection strings from the secret store.
- `systematic-debugging`: the Phase 1 evidence-gathering loop applies to slow queries (start with EXPLAIN ANALYSE; trace the actual plan, not the assumed one).
- `completion-gate` Layer 1: `pnpm db:format && pnpm db:validate` runs preemptively after Prisma schema edits.

## Common mistakes

- Optimising without `EXPLAIN ANALYSE` (guessing).
- Adding indexes "because it might help" (each index has a write-cost; only add when EXPLAIN shows a sequential scan that should not be there).
- App-side connection limit higher than database `max_connections / app_instances` (database falls over under load).
- Long-running transaction blocking VACUUM (table bloat, query plan degradation).
- RLS policy tested only as the table owner (works there; fails as the application role).
- `JSONB` column storing structured data that should have been columns (queryability lost).
- `LIMIT` without `ORDER BY` (non-deterministic results).
- Migration that takes an exclusive lock on a hot table without `lock_timeout` (waits forever, blocks all reads).
- N+1 query pattern hidden behind ORM lazy loading.

## Red flags

- A new query in a code review without an EXPLAIN ANALYSE in the PR description for anything non-trivial.
- A list endpoint without pagination.
- A connection pool size set "to be safe" without reference to `max_connections`.
- An RLS policy added without a test that runs as the application role.
- A schema change that is not additive within the release (per `forward-compatible-schemas`).
- A `JSONB` column being added when columns would do.
- A migration script with no `lock_timeout` that's about to take an exclusive lock on a hot table.

## Bottom line

Eight categories ordered by impact. Query performance pays back biggest; connection management prevents outages; security prevents tenant leakage; schema design compounds. Measure first (EXPLAIN, pg_stat_statements), then apply the rule that addresses the actual bottleneck.
