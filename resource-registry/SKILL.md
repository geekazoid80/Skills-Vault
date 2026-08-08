---
name: resource-registry
description: Use when you create or are handed a durable addressable resource, an Asana field/project/portfolio GID, a database table, a cloud resource ID, API or service access (M365/Graph, Action1, a PAT), an SSH host + account + access command, an endpoint, a config key, a deployed service, or a canonical file path, and when writing or updating a plan file, at chunk-close, at park, or on resume before acting on a prior session's resources. Catalogue each resource once in a durable home (project memory or AGENTS.md) with its real identifier and the exact command or API to reach it; the plan file carries only a pointer. On resume, refresh from the catalogue and address resources by their true IDs instead of guessing or hallucinating field names, GIDs, hostnames, or access methods. NOT for ephemeral run state (TaskList, subprocess IDs, cwd), that is pre-park-externalisation; NOT for secret values, that is secrets-hygiene (store the credential's location, never the secret).
---

# Resource Registry

> **Skill marker**: When applying this skill, begin your reply with `[skill: resource-registry]` on its own line. If multiple skills fire on the same reply, emit each marker on its own line at the top.

## Overview

A resource created or accessed in one session is useless to the next if the next session has to guess its
identifier or re-derive how to reach it. Guessing produces hallucinated field names, wrong GIDs, the wrong
SSH user, invented endpoints. The fix: catalogue every durable addressable resource ONCE in a durable home,
keep only a pointer in the transient plan file, and on resume address resources by their true identifiers
read back from the catalogue, never from memory or a guess.

**Core principle:** durable resource, durable record. If a fresh session would have to know an ID or an
access command to use it, that ID and command live in the registry, not in someone's head or a cleared plan.

## When this fires

- You create or are handed any durable addressable resource (see the taxonomy below).
- You write or update a plan file, close a chunk, or park.
- You resume, BEFORE acting on any resource a prior session created.

## What counts as a resource (type-agnostic)

- **Created objects with IDs:** Asana custom-field / project / portfolio GIDs, database tables, cloud
  resource IDs, queue names.
- **API / service access:** M365 / Graph app-registration + scopes, Action1 org, an Asana PAT. Record the
  access pattern and WHERE the credential lives (e.g. `config.ini [asana] pat`), never the secret value.
- **SSH / host access:** the host, the account the key actually authorises, and the exact command (including
  any `sudo -u <owner>` needed to reach an owned path).
- **Endpoints, config keys, deployed services, canonical file paths.**

## The durable home + plan pointer (iron rule)

- The catalogue lives in a **durable home**: a project-memory file (e.g. `project-resources.md`) or a
  `## Resources & Access` block in `AGENTS.md`. Durable, because plan files are transient and get cleared at
  chunk close.
- The **plan file carries ONE line**: a pointer to the catalogue (`Resources & access: see
  project-resources.md`). Never inline the resource list into the plan, it will be lost.

## Each entry: four columns (+ two optional)

| what it is | real identifier (GID / path / host) | exact command or API to read/write it | auth (where the credential lives, never the secret) |

An entry with an ID but no access command is half-useful; include both. Two optional columns earn
their place for some resource types:

- **How to refresh / currency** (data-input resources): for a resource whose *value* goes stale (a live
  IP-assignment export, a footprint CSV, a cached lookup), record how to obtain a current copy (which
  export, which sync job, which repo to re-pull). The access command reaches the file; the refresh note
  keeps it from silently rotting.
- **Last verified** (date): stamp when the ID / access was last confirmed to resolve, so a reader can
  judge staleness at a glance. Sibling to `verify-now-not-next-session`.

## On resume: refresh, do not guess

- Before citing or acting on any prior resource, READ the catalogue and use the identifier / command from it.
- If a resource is not catalogued, look it up ONCE, use it, and add it. Do not hardcode a guess and do not
  re-derive it every session.
- Memories go stale: verify a cited ID or access method still resolves before asserting it as fact.
- **Retire on decommission.** When a resource is deleted, rotated, or replaced, UPDATE or REMOVE its
  entry in the same change. An entry is only trustworthy if it is maintained on the way out as well as
  in; a registry that only ever grows accumulates stale, misleading entries.

## Composition with sibling disciplines

- `pre-park-externalisation` flushes ephemeral STATE (TaskList, subprocess IDs, cwd); this catalogues durable
  RESOURCES + access. Different lifetimes, different homes.
- `reread-memory-before-planning`: refresh the registry when you re-read memory at plan-open.
- `secrets-hygiene`: the registry stores the credential's LOCATION and the access pattern, never the secret.

## Worked example

An IT-asset session created several Asana objects and worked out remote-host access. Instead of scattering
them through plan-file prose, one `## Resources & Access` table in project memory:

| Resource | Identifier | Access | Auth |
|---|---|---|---|
| Asset Location field (text) | `1216440033556530` | `find_custom_field(c, ws, "Asset Location")`; write `PUT /projects/{gid}` `{custom_fields:{gid:val}}` | Asana PAT, `config.ini [asana] pat` |
| Shared audit tracker (project) | `1216344260937216` | `cfg.followup_project_gid` | same |
| IT Asset Management (parent portfolio) | `1216223440137153` | `_match_by_name(get_all("/portfolios", owner=me), "IT Asset Management")` | same |
| Remote build host | `/opt/app/repo` on an internal host | `ssh deploy@build-host` (key authorises the deploy user; git ops + cron via `sudo git -C <repo> ...`) | `~/.ssh/id_ed25519` |

The plan file then holds only: `Resources & access: see project-resources.md`. A resumed session reads the
table and uses `1216440033556530` directly instead of guessing a field name, and connects as the deploy user
instead of retrying the wrong login account.

## Red flags

- Writing a GID / hostname / field name into a plan or a message from memory without checking the catalogue.
- Inlining the resource list into the plan file instead of a one-line pointer.
- Storing a secret VALUE in the catalogue (store its location instead).
- Re-deriving an access method a prior session already worked out (e.g. rediscovering the SSH user the hard way).
- A resource created this session that never made it into the registry.
- A catalogue entry with an identifier but no access command.
- A decommissioned / rotated resource left in the registry as if it were still live.
- A data-input resource with an access path but no note on how to get a *current* copy.

## Bottom Line

Durable resource, durable record. Catalogue every addressable resource (ID + how to reach it + where its
credential lives) in project memory; the plan file just points at it. On resume, read the registry and use
real identifiers, never guess. Ephemeral state is `pre-park-externalisation`'s job; secrets are
`secrets-hygiene`'s. This is the layer that stops the next session hallucinating what already exists.
