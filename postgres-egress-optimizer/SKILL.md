---
name: postgres-egress-optimizer
description: Use when diagnosing or fixing excessive Postgres egress (network data transfer from database to application). Triggers include "the database bill is high", "unexpected data transfer costs", "network transfer charges", "egress spikes", "why is the bill so high", "database costs jumped", "SELECT * optimisation", "query overfetching", "reduce database costs", "the API is slow because of the database", or any review of query patterns for cost / efficiency. Walks the four-step loop (diagnose with pg_stat_statements; analyse the codebase; fix the five anti-patterns; verify). Vendor-agnostic; the patterns apply to any Postgres deployment regardless of who hosts it (RDS, Supabase, Neon, Crunchy, Aiven, Azure, GCP, bare). Customised vendor-neutral version of neondatabase/agent-skills/neon-postgres-egress-optimizer.
metadata:
  version: 1.0.0
---

# Postgres Egress Optimiser

> **Skill marker**: When applying this skill, begin your reply with `[skill: postgres-egress-optimizer]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Most high egress bills come from the application fetching MORE DATA THAN IT USES. The fix loop is: diagnose which queries are biggest, analyse the codebase to confirm, apply the right fix from a small set of anti-patterns, verify the result.

**Core principle:** measure with `pg_stat_statements` before optimising; the worst egress queries are often not the ones a reviewer would guess.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Postgres estate (managed provider, egress-billing surface, query observability) before diagnosing. Only ask the user for information not already covered or specific to this optimisation pass.

Before diagnosing, understand:

1. **Surface and billing**
   - Managed Postgres (RDS, Supabase, Neon, others)?
   - Egress charged to the database VPC, the application VPC, or both?
   - Cross-region or cross-AZ traffic involved?

2. **Observability**
   - `pg_stat_statements` extension available?
   - Recent stats reset, or stats accumulating since instance start?
   - Application-side query logs or APM traces available?

3. **Workload character**
   - High-volume small queries, occasional large result sets, or both?
   - ORM-driven N+1 patterns suspected?
   - Read replicas in use, and how applications route to them?

---

## When to use

- A noticeable jump in the database bill or in network-transfer costs.
- Database performance is fine but the application is slow (waiting on data transfer).
- A review of query patterns specifically for efficiency.
- A query is known to be heavy and the team wants to reduce its footprint.

Vendor-agnostic: applies to any Postgres deployment. Vendor-specific concerns (Neon's compute-scales-to-zero, RDS data-transfer pricing tiers) get a brief note where relevant.

## Step 1: Diagnose

### Check pg_stat_statements is available

```sql
SELECT 1 FROM pg_stat_statements LIMIT 1;
```

If it errors, create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Most managed Postgres services ship it preconfigured but require this `CREATE EXTENSION` call once.

### Handle empty stats

`pg_stat_statements` accumulates from the database's last reset. If stats are empty (a fresh start, a manual reset, or a Neon compute that scaled to zero and just resumed), let the application run under representative traffic for at least an hour, then come back. Or run the queries below now if you have stats from a production database accessible.

If no production stats are available, skip Step 1 and proceed to Step 2 (codebase analysis); code-level patterns are often enough to find the worst offenders.

### Diagnostic queries

Four lenses; each surfaces a different class of egress problem.

**Top total rows transferred:**

```sql
SELECT query, calls, rows AS total_rows, rows / calls AS avg_rows_per_call
FROM pg_stat_statements
WHERE calls > 0
ORDER BY rows DESC
LIMIT 10;
```

**Most rows per execution (poorly scoped SELECTs, missing pagination):**

```sql
SELECT query, calls, rows AS total_rows, rows / calls AS avg_rows_per_call
FROM pg_stat_statements
WHERE calls > 0
ORDER BY avg_rows_per_call DESC
LIMIT 10;
```

**Most frequently called (cache candidates):**

```sql
SELECT query, calls, rows AS total_rows, rows / calls AS avg_rows_per_call
FROM pg_stat_statements
WHERE calls > 0
ORDER BY calls DESC
LIMIT 10;
```

**Longest running (correlated with egress problem queries during spikes):**

```sql
SELECT query, calls, rows AS total_rows,
  round(total_exec_time::numeric, 2) AS total_exec_time_ms
FROM pg_stat_statements
WHERE calls > 0
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Interpret results

Rank by estimated egress impact:

- **High row count + wide rows = biggest egress.** A query returning 1,000 rows with a 50KB JSONB column transfers ~50MB per call.
- **Extreme call frequency** on small queries adds up. 50,000 calls per day returning 10 rows = 500,000 rows / day.
- **Cross-reference with the schema** to identify wide columns (JSONB, TEXT, BYTEA, large VARCHAR).

## Step 2: Analyse the codebase

For each query identified in Step 1 (or for each query in the codebase if no stats are available), check:

- Does it select ONLY the columns the response needs?
- Does it return a bounded number of rows (LIMIT / pagination)?
- Is it called frequently enough to benefit from caching?
- Does it fetch raw data that the application aggregates afterwards?
- Does it use a JOIN that duplicates parent data across child rows?

Each "no" maps to one of the five fixes below.

## Step 3: Fix

The five most common egress anti-patterns and their fixes.

### Anti-pattern 1: SELECT * (unused columns)

**Problem:** the query fetches all columns; the application only uses some. Wide columns (JSONB blobs, TEXT fields) get transferred and discarded.

**Before:**
```sql
SELECT * FROM products;
```

**After:**
```sql
SELECT id, name, price, image_urls FROM products;
```

### Anti-pattern 2: Missing pagination

**Problem:** a list endpoint returns all rows with no LIMIT. Unbounded egress risk; every new row in the table increases data transfer on every request. Flag this REGARDLESS of current table size; the bug shows up at scale.

**Before:**
```sql
SELECT id, name, price FROM products;
```

**After:**
```sql
SELECT id, name, price FROM products
ORDER BY id
LIMIT 50 OFFSET 0;
```

When adding pagination, check whether consuming clients support paginated responses; pick sensible defaults; document the pagination parameters in the API.

### Anti-pattern 3: High-frequency queries on static data

**Problem:** a query is called thousands of times per day but returns data that rarely changes (configuration tables, role definitions, feature flags, category lists). Every call transfers the same rows. Visible only from `pg_stat_statements`; the code itself looks normal.

**Fix:** add a caching layer between the application and the database (Redis, in-process cache with TTL, CDN edge). Configure a cache invalidation when the data does change.

### Anti-pattern 4: Application-side aggregation

**Problem:** the application fetches all rows from a table then computes aggregates (averages, counts, sums, groupings) in application code. The full dataset crosses the wire even though the result is a small summary.

**Fix:** push the aggregation into SQL.

**Before:** the application fetches entire `reviews` and `products` tables, then computes per-category average rating in code.

**After:**
```sql
SELECT p.category_id,
       AVG(r.rating) AS avg_rating,
       COUNT(r.id) AS review_count
FROM reviews r
INNER JOIN products p ON r.product_id = p.id
GROUP BY p.category_id;
```

### Anti-pattern 5: JOIN duplication

**Problem:** a JOIN between a wide parent table and a child table duplicates ALL parent columns across every child row. If a product has 200 reviews and the product row includes a 50KB JSONB column, the join sends 50KB times 200 = ~10MB for a single request.

This is distinct from SELECT *. Even with explicit column selection, a JOIN repeats parent data per child row. The fix is structural: avoid the join.

**Before:**
```sql
SELECT * FROM products
LEFT JOIN reviews ON reviews.product_id = products.id
WHERE products.id = 1;
```

**After (two separate queries):**
```sql
SELECT id, name, price, description, image_urls FROM products WHERE id = 1;
SELECT id, user_name, rating, body FROM reviews WHERE product_id = 1;
```

Two queries instead of one JOIN. Product data fetched once. Reviews fetched once. No duplication.

## Step 4: Verify

After applying fixes:

1. **Run existing tests** to confirm nothing broke.
2. **Check API responses** to make sure the data shape didn't change in a way clients depend on. Column-selection and pagination changes can break consumers that assumed full rows or full result sets.
3. **Measure the improvement.** If `pg_stat_statements` is available, reset it (`SELECT pg_stat_statements_reset();`), let representative traffic run, re-run the diagnostic queries, compare before and after.

Use `completion-gate` Layer 3 for the "fix worked" claim. Do not declare done without the after-measurement.

## Vendor-specific notes

Brief callouts where the vendor changes behaviour:

- **Neon:** compute scales to zero on idle; on resume, `pg_stat_statements` is empty. Either use a database that's been warm for an hour, or kick traffic for an hour before measuring.
- **Supabase:** database is shared across the project's connection pooler; transaction-mode pooling means session-scoped state (advisory locks, prepared statements, `SET`) does not persist across statements.
- **RDS:** data transfer between AZs is metered separately from database I/O; egress optimisation matters even more in cross-AZ topologies.
- **Bare Postgres:** `pg_stat_statements` may need `shared_preload_libraries = 'pg_stat_statements'` in `postgresql.conf` plus a restart before the `CREATE EXTENSION` works.

## Cross-references

- `postgres-best-practices`: the broader Postgres rule catalogue. The egress-optimiser is a focused pass; postgres-best-practices is the wider review.
- `systematic-debugging`: the four-step loop (diagnose, analyse, fix, verify) maps directly onto the four phases of systematic-debugging. Egress optimisation IS systematic debugging applied to the egress problem.
- `completion-gate` Layer 3: no claim of "fix worked" without the after-measurement.
- `forward-compatible-schemas`: column-selection changes that shrink the response shape are NOT additive (consumers may depend on the dropped columns); audit before pushing.

## Common mistakes

- Optimising without measuring (guessing which queries are heavy; usually wrong).
- Adding pagination only "where the table is big right now" (the bug shows up at scale; flag everywhere).
- Caching without invalidation (stale data; correctness before efficiency).
- Replacing a JOIN with two queries without checking call patterns (if the app calls them in a loop, you've created a more subtle N+1).
- Pushing aggregation into SQL without verifying the result matches the previous app-side computation (rounding differences, NULL handling).
- Resetting `pg_stat_statements` before saving the before-state (no comparison possible).

## Red flags

- High-bill alert with no `pg_stat_statements` data to investigate.
- A list endpoint without pagination.
- A SELECT * in a hot path.
- A JOIN between a wide parent and a child table without selective column projection.
- Application code that calls a database query inside a loop over fetched rows (the N+1).
- A cache layer added without an invalidation path.

## Bottom line

Diagnose with `pg_stat_statements`. Analyse the codebase. Fix one of five anti-patterns. Verify with after-measurement. Vendor-agnostic; the patterns apply regardless of who hosts the database.
