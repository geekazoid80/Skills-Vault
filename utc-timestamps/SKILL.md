---
name: utc-timestamps
description: Use when writing or editing code that creates, stores, transmits, hashes, indexes, compares, or schedules timestamps. Enforces ISO-8601 Z form everywhere persisted or on the wire; UI converts at the leaf render only. Covers JS / TS / Python / Rust / Go idioms, validation refinements, DB column types, log fields, API shapes, and cron declarations. Offers to migrate non-compliant code rather than silently accepting the existing pattern.
metadata:
  version: 1.0.0
---

# UTC Timestamps

> **Skill marker**: When applying this skill, begin your reply with `[skill: utc-timestamps]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Every timestamp stored, transmitted, hashed, indexed, or compared anywhere in any codebase is **UTC ISO-8601 Z-form** (e.g. `2026-05-03T12:34:56.000Z`). Local-offset forms (`+08:00`, `Asia/Singapore` strings) are forbidden in storage, on the wire, in audit chains, and in scheduled-job declarations.

The UI is the only layer that converts to local time, and only at the leaf rendering point, never up-stack.

**Core principle:** UTC ISO-8601 with trailing `Z`, persisted; local time only at the leaf render.

## The Iron Rule

```
NO LOCAL-OFFSET TIMESTAMPS IN STORAGE, ON THE WIRE, IN AUDIT CHAINS, OR IN CRON.
```

If a timestamp is going to be persisted, transmitted, hashed, indexed, sorted, or compared, it is `YYYY-MM-DDTHH:MM:SS.sssZ`. No `+08:00`. No bare `Asia/Singapore` strings. No naive datetimes.

## Generation idioms by language

| Language | Idiom |
|---|---|
| JavaScript / TypeScript | `new Date().toISOString()` (always returns UTC with `Z`) |
| Python | `datetime.now(tz=timezone.utc).isoformat()` (or `.isoformat().replace('+00:00', 'Z')` if the spec requires literal `Z`) |
| Rust | `chrono::Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)` or `time::OffsetDateTime::now_utc().format(&Rfc3339)` |
| Go | `time.Now().UTC().Format(time.RFC3339Nano)` |
| Java | `Instant.now().toString()` |
| Ruby | `Time.now.utc.iso8601(3)` |

## Validation refinements

Every input refinement (Zod, TypeBox, JSON Schema, pydantic, attrs, valibot, etc.) requires the trailing `Z` and rejects `[+-]\d{2}:\d{2}` patterns.

```ts
// Zod
z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/)
```

```python
# pydantic v2
from pydantic import BaseModel, field_validator
import re
class E(BaseModel):
    at: str
    @field_validator("at")
    def utc_z(cls, v: str) -> str:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z", v):
            raise ValueError("must be UTC ISO-8601 with trailing Z")
        return v
```

JSON Schema: `"pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,9})?Z$"`. The `format: date-time` keyword alone is too permissive; pair it with a pattern.

## Database columns

| Engine | Type | Notes |
|---|---|---|
| Postgres | `TIMESTAMP WITH TIME ZONE` (`timestamptz`) | Postgres normalises to UTC internally; never use `TIMESTAMP WITHOUT TIME ZONE` for event time. |
| SQLite | `TEXT` storing ISO-8601 with `Z` | SQLite has no native datetime type; the literal `Z` matters for sort and compare. |
| MySQL / MariaDB | `DATETIME(6)` with the session set to UTC, OR `TIMESTAMP` | Document the session timezone; do not rely on server defaults. |
| MongoDB | `Date` (BSON) | BSON Date is UTC milliseconds since epoch; write with explicit UTC. |

Never store a local-tagged value. Never store an offset string when the column is meant to hold an instant.

## Logs, structured events, audit chains

Every log line, every event envelope, every audit-chain entry uses UTC. If the logger framework defaults to local, configure it to UTC at boot, then verify a sample line.

Audit chains in particular: the hash input MUST be the UTC string. A local-offset string in the hashed payload makes the chain non-replayable across regions.

## API request and response shapes

Document UTC explicitly in OpenAPI / equivalent. Reject offset forms at the validation layer (see refinements above). Never auto-convert request inputs to local on the server side; pass the UTC value through.

## Cron schedules

Declare cron expressions in UTC unless the daemon insists on local. If forced to local, document the chosen timezone in a comment beside the schedule and beside any code that consumes the schedule's fired-at timestamp.

```
# UTC: runs daily at 14:00 UTC == 22:00 SGT
0 14 * * *  /usr/local/bin/nightly-job
```

## Migration when existing code violates

If you encounter a codebase that stores `+08:00` strings, naive datetimes, or local-tagged values:

1. Call it out in the same turn you noticed it.
2. Offer a migration path: add a UTC column, backfill from the existing column with explicit conversion, switch readers, drop the old column in a later release (see `forward-compatible-schemas`).
3. Do not silently accept the non-UTC pattern just because it is already there.

## Red flags

- `new Date().toString()` (locale-dependent string)
- `datetime.now()` without `tz=timezone.utc`
- `time.Now().Format(...)` without `.UTC()` first
- Storing an offset string (`2026-05-03T20:34:56+08:00`) in any column
- Hashing an audit payload that contains a local-offset timestamp
- Cron schedules with no timezone comment
- `format: date-time` validators without an accompanying `Z`-anchored pattern

## Bottom line

UTC at the wire, UTC at rest, UTC in the hash. Local time appears once, in the rendered string the user sees, and nowhere else.
