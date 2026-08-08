---
name: forward-compatible-schemas
description: Use when editing a database schema, a Prisma model, a JSON / Avro / Protobuf contract, an API response shape, or any persisted data structure. Schema changes within a release are additive only. New fields are nullable or carry agreed defaults. Renames go via add → double-write → flip readers → drop in a later release. Roll-back from any release must work without DB editing. Calls out non-compliant change shapes and offers a compliant path.
metadata:
  version: 1.0.0
---

# Forward-Compatible Schemas

> **Skill marker**: When applying this skill, begin your reply with `[skill: forward-compatible-schemas]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Within a single release, schema changes are additive only. Renames, drops, and type-changes are spread across multiple releases so that any release can be rolled back without database editing and so that downstream consumers pinned to a previous version still see a valid shape.

**Core principle:** every release must be roll-back-safe and forward-readable by the previous release.

## The Iron Rule

```
WITHIN A RELEASE: ADDITIVE ONLY.
RENAMES / DROPS / TYPE CHANGES: SPREAD ACROSS RELEASES.
ROLL-BACK FROM ANY RELEASE MUST WORK WITHOUT DB EDITING.
```

## What "schema" means here

This rule covers anything that persists shape across a release boundary or across a process boundary where the consumer might be on a different version:

- SQL DDL (Postgres, MySQL, SQLite, etc.)
- ORM models (Prisma, Drizzle, SQLAlchemy, ActiveRecord, Hibernate, TypeORM, Diesel)
- JSON / Avro / Protobuf / Thrift / Cap'n Proto contracts
- OpenAPI / GraphQL response shapes
- Message-bus payloads (Kafka, RabbitMQ, SQS, NATS) when persisted or replayed
- Cache key formats and serialised cache values
- Anything a downstream consumer pinned to a previous release version might still see

## What counts as additive

Allowed within a release:

- Add a new nullable column / field.
- Add a new column with an agreed sensible default.
- Add a new index.
- Add a new table / message type / enum case (so long as old consumers tolerate unknown enum cases; Protobuf and Avro do, some hand-rolled JSON parsers do not).
- Add a new optional field to a request / response shape.
- Widen a numeric type (e.g. `int32` to `int64`) only if the wire format and all readers tolerate the wider type.

NOT allowed within a release:

- Drop a column / field that any reader still uses.
- Rename a column / field in place.
- Change a column's type in a way the previous reader cannot decode.
- Make a previously nullable column NOT NULL without a guaranteed-populated backfill.
- Add a new NOT NULL column without a default and without a backfill.
- Tighten an enum (remove a case) while old writers might still emit it.
- Change a primary key, partition key, or sort key.

## The four phases of a rename

```
Release N+0:  ADD            : new column exists alongside old; nullable.
Release N+1:  DOUBLE-WRITE   : writers write to BOTH old and new.
Release N+2:  FLIP READERS   : readers read from new; old still written for safety.
Release N+3:  DROP           : old column removed; only new column remains.
```

Each step ships in its own release. Roll-back at any step lands on a release that still works.

### Worked example: rename `userEmail` to `contactEmail` on `User`

| Release | Migration | Code change | Roll-back lands on |
|---|---|---|---|
| N+0 (add) | `ALTER TABLE user ADD COLUMN contact_email TEXT NULL;` | None to readers / writers; old code keeps using `userEmail`. | Pre-N+0 (column ignored). |
| N+1 (double-write) | None. | Writers write `contactEmail` and `userEmail` to the same value on every save. Readers still use `userEmail`. | N+0 (still readable). |
| N+2 (flip readers) | None. | Readers switch to `contactEmail`. Writers continue to write both. | N+1 (still readable). |
| N+3 (drop) | `ALTER TABLE user DROP COLUMN user_email;` | Writers stop writing `userEmail`. | N+2 (still readable). |

Four releases. Roll-back from any one lands on a release whose code is compatible with the schema.

## Roll-back invariant

Pick any release in the sequence. Imagine you have to roll back to it after a production incident. The roll-back must succeed using only application-level redeploy, no manual `ALTER TABLE`, no `UPDATE` statements run by hand.

If a proposed migration breaks that invariant, it is non-compliant.

## Common non-compliant patterns and the compliant path

### Non-compliant: drop a column in the same release that adds its replacement

```sql
-- DON'T
ALTER TABLE user DROP COLUMN user_email;
ALTER TABLE user ADD COLUMN contact_email TEXT NOT NULL;
```

Roll-back to the previous release leaves the database with `contact_email` (the old code does not know) and without `user_email` (the old code crashes).

Compliant path: split into the four phases above.

### Non-compliant: add NOT NULL without default or backfill

```sql
-- DON'T
ALTER TABLE order ADD COLUMN currency TEXT NOT NULL;
```

Existing rows fail the constraint; the migration aborts mid-deploy.

Compliant path:

```sql
-- Release N+0: add nullable
ALTER TABLE order ADD COLUMN currency TEXT NULL;
-- Backfill (separate step, can be run concurrently)
UPDATE order SET currency = 'USD' WHERE currency IS NULL;
-- Release N+1: tighten constraint after backfill confirmed
ALTER TABLE order ALTER COLUMN currency SET NOT NULL;
```

### Non-compliant: change a column's type in place

```sql
-- DON'T
ALTER TABLE event TABLE ALTER COLUMN amount TYPE numeric(18,4) USING amount::numeric;
```

If the old reader expected `int`, the new value may not deserialise.

Compliant path: add `amount_v2`, double-write, flip readers, drop `amount`. Same four-phase pattern as a rename.

### Non-compliant: rename a Prisma model field with `@map`

Prisma's `@map` makes the schema rename look free at the ORM layer, but the underlying column changed. Old consumers that read raw SQL or that share the database (replicas, read-only analytics) still see the old column.

Compliant path: add the new column, double-write via Prisma middleware or service-layer wiring, flip readers (including any raw SQL), drop the old column in a later migration.

### Non-compliant: tighten an enum

```ts
// DON'T
type Status = "pending" | "active";  // was: "pending" | "active" | "suspended"
```

Persisted rows with `"suspended"` and any in-flight messages with `"suspended"` will fail validation.

Compliant path: introduce the tighter type as `StatusV2`, add a translation layer, migrate persisted values, then remove the old type in a later release.

## Persisted message-bus payloads

If a consumer can replay messages from a topic / queue (Kafka, persisted SQS, durable RabbitMQ), the payload schema is bound by the same rules. A consumer running release N+1 must successfully decode messages written by release N+0 and vice versa for the duration of the rollout window.

Use Avro / Protobuf for strong forward-compat guarantees; use JSON Schema with `additionalProperties: true` and explicit `required` only on stable fields.

## When the existing codebase violates this rule

If you encounter a migration that drops a column in the same release that adds its replacement, or a NOT NULL column added without a default:

1. Call it out in the same turn.
2. Offer the four-phase compliant path with a worked release plan.
3. If the change has already shipped, the question becomes "do we backfill in place or roll forward to a compliant state". Surface that via AskUserQuestion; do not pick silently.

## Red flags

- A migration that contains both an `ADD COLUMN` and a `DROP COLUMN` in the same file
- An `ALTER COLUMN ... SET NOT NULL` on a column added in the same release with no backfill
- A Prisma `@map` rename with no double-write window
- An enum case removed in the same release that switches readers to the tightened type
- A "v2" endpoint that drops fields the v1 client still requests
- A rolled-back release that "needs a manual SQL fix to come back up"

## Bottom line

Additive within a release. Renames spread across four releases. Every release roll-back-safe. If you cannot tell whether a change is roll-back-safe, ASK before shipping it.
