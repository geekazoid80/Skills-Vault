---
name: asana-workflows
description: Use when the user wants to do something concrete with Asana, whether via the wired MCPs or the REST API. Triggers include "what's on my Asana", "my Asana tasks", "create an Asana task for", "update that Asana task", "Asana project", "Asana portfolio", "Asana goal", "Asana allocation", "Asana workspace report", "Asana cross-team", "Asana dependency", "set up Asana project", "draft an Asana project". Does NOT fire on vague "what's my workload" without an Asana hook, or on idle "should we use Asana" architecture chatter (defer to plan-time-tooling). Two Asana MCPs are wired (lighter preview surface and enterprise full surface); this skill carries the routing table that maps each use case to the right MCP. An estate may pin the Asana access path instead (direct REST under a named token identity, connectors forbidden, for identity control and auditability); check for that rule first, it overrides the routing table. For working against the Asana REST API directly (a script, a service, a CI job, or an estate whose access rule mandates it), a bundled full REST reference lives in references/asana-rest-api.md (endpoint index for every operation, schemas with exact enums, team-sharing via POST /memberships, the private_to_team privacy trap, refresh recipe); consult it for direct-REST work and refresh it on use when older than its 30-day TTL.
metadata:
  version: 1.2.0
---

# Asana Workflows

A thin wrapper over the two wired Asana MCPs. Tells the agent which MCP to reach for, in which order, and how to compose the calls into common workflows (read my tasks, create a task with context, build a project from scratch, pull a portfolio status, update a goal, wire dependencies, check cross-team capacity).

> **Skill marker**: When applying this skill, begin your reply with `[skill: asana-workflows]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Check for an estate access rule first (it overrides everything below)

Some organisations pin **how** Asana is reached, not just what is done with it: a named token identity, direct REST only, a particular connector forbidden. Such rules exist for identity control (a connector authenticates as whoever authorised it, which is the wrong and uncontrolled identity for automation), production parity (if the estate's own tools run on REST, then probing over REST behaves like the real run), and auditability (the credential used is explicit).

**Look for such a rule before you use the routing table below.** Read the standing instructions and memory for the estate you are working in, the working directory's `CLAUDE.md` / `AGENTS.md`, and any estate-specific skill covering this surface. Where a rule exists it **overrides this skill's routing entirely**, including the "default to enterprise" fallback and the framing of direct REST as a narrow exception; the bundled REST reference then becomes the primary path and this skill contributes only call mechanics (GID resolution, schemas, workflow shapes), never the choice of access path.

This matters because the failure is silent. The skill fires on the right trigger, its advice is followed faithfully, and the violation is invisible in the transcript until someone re-reads the estate's rules. Skill advice is a default; an estate access rule is an override, and the override wins.

If no such rule exists, the routing table applies as written.

## Initial Assessment

Before any tool call, read CLAUDE.md / AGENTS.md for any repo-scoped Asana guidance (including an access-path rule per the section above), then walk through the three context categories:

1. **What the user is asking for.** Read / write / create / update / search? Personal scope (acting user's own tasks) or workspace scope (cross-team, portfolio, goals, allocations)? Single object or rollup?
2. **Existing state of the Asana surface they care about.** Is the project / portfolio / goal already known by GID, or do we need a typeahead lookup first? Is the entity in the acting user's default workspace, or another workspace?
3. **Constraints.** Acting-user scope vs cross-team. Preview-first vs direct create (large or structured changes default to preview). Read-only vs mutating call (mutating calls always need explicit user confirmation of the proposed change).

If any of these is unclear, ask via AskUserQuestion before reaching for a tool.

## When to Use This Skill

- The user references Asana explicitly ("my Asana tasks", "this Asana project").
- The user asks for an action that maps to an Asana primitive (create a task, mark complete, set a dependency, comment on a thread).
- The user wants a workspace-level read (portfolio rollup, goal status, capacity report).
- The user wants a project scaffolded with sections and tasks.
- A meeting follow-up needs to land as a task (cross-skill with `calendar-workflows`).
- A Gmail draft needs an Asana follow-up attached (cross-skill with `gmail-workflows`).

## When NOT to Use This Skill

- The user asks "what's my workload" without naming Asana. They may mean a calendar pull, a Jira pull, a Linear pull, or just self-reflection. Ask first.
- The user is debating "should we use Asana or Linear for this project". That is an architecture decision; defer to `plan-time-tooling` for the framing.
- The user is asking how Asana's internal data model works. That is vendor-doc territory; link them to docs rather than running tool calls.
- The user wants to delete a task / project / goal without confirming. Mutating calls need explicit user sign-off on the exact target.

## Routing: which MCP handles what

Two Asana MCPs are wired in this session:

- **Preview surface** (`mcp__d26e8bef...`). Lighter call shape. Defaults to the acting user's scope. Tools: `get_me`, `get_my_tasks`, `get_task`, `get_tasks`, `search_tasks`, `create_tasks`, `update_tasks`, `delete_task`, `create_task_preview` / `_v2` / `_v3`, `create_project_preview` / `_v2`, `create_project`, `get_project`, `get_projects`, `get_status_overview`, `create_project_status_update`, `add_comment`, `get_attachments`.
- **Enterprise surface** (`mcp__7f060563...`, `asana_*` prefix). Full workspace coverage. Tools: `asana_typeahead_search`, `asana_list_workspaces`, `asana_get_workspace_users`, `asana_get_teams_for_workspace`, `asana_get_teams_for_user`, `asana_get_team_users`, `asana_get_portfolios`, `asana_get_portfolio`, `asana_get_items_for_portfolio`, `asana_get_goals`, `asana_get_goal`, `asana_create_goal`, `asana_update_goal`, `asana_update_goal_metric`, `asana_get_parent_goals_for_goal`, `asana_get_allocations`, `asana_get_time_periods`, `asana_get_time_period`, `asana_set_task_dependencies`, `asana_set_task_dependents`, `asana_set_parent_for_task`, `asana_add_task_followers`, `asana_remove_task_followers`, `asana_create_task_story`, `asana_get_stories_for_task`, `asana_get_projects_for_team`, `asana_get_projects_for_workspace`, `asana_get_project_sections`, `asana_get_project_status`, `asana_get_project_statuses`, `asana_get_project_task_counts`, `asana_create_project_status`, `asana_create_project`, `asana_create_task`, `asana_update_task`, `asana_delete_task`, `asana_get_task`, `asana_get_tasks`, `asana_search_tasks`, `asana_get_attachment`, `asana_get_attachments_for_object`.

| Use case | Which MCP | Specific tool | Why |
|---|---|---|---|
| "What's on my plate today" | Preview | `get_my_tasks` | Acting-user default; no GID lookup. |
| Look up a user / project / team / portfolio / goal by name (need GID) | **Enterprise (first)** | `asana_typeahead_search` | Locked rule: always resolve GIDs via enterprise typeahead first, then route the rest of the workflow to whichever surface fits. |
| Read one task you already have the GID for | Preview | `get_task` | Lighter call. |
| Create one task in a known project | Preview | `create_tasks` (or `create_task_preview_v3` if user wants to confirm) | Acting-user scope; minimal parameters. |
| Update / complete / delete a task you can see | Preview | `update_tasks` / `delete_task` | Acting-user scope; simpler. |
| Search tasks across the acting user's scope | Preview | `search_tasks` | Lighter call. |
| Search tasks workspace-wide | Enterprise | `asana_search_tasks` | Cross-workspace coverage. |
| Build a new project with sections + tasks | Preview | `create_project_preview_v2` then `create_project` | Preview tool is the canonical scaffold UX. |
| List all projects in a team or workspace | Enterprise | `asana_get_projects_for_team` / `_for_workspace` | Not exposed on preview surface. |
| Portfolio rollup or item list | Enterprise | `asana_get_portfolios`, `asana_get_portfolio`, `asana_get_items_for_portfolio` | Portfolio is planning surface, not personal. |
| Goal read / create / metric update | Enterprise | `asana_get_goal`, `asana_create_goal`, `asana_update_goal_metric` | Goals are workspace-scope. |
| Capacity / allocation queries | Enterprise | `asana_get_allocations`, `asana_get_time_periods` | Cross-team planning. |
| Wire task dependencies | Enterprise | `asana_set_task_dependencies`, `asana_set_task_dependents` | Not exposed on preview surface. |
| Set parent task (subtask reparent) | Enterprise | `asana_set_parent_for_task` | Same reason. |
| Add followers to a task | Enterprise | `asana_add_task_followers`, `asana_remove_task_followers` | Same reason. |
| Post a story (comment) on a task | Preview (simple) / Enterprise (rich) | Preview `add_comment` for plain comment; enterprise `asana_create_task_story` for story with html / attachments | Preview is enough for most comments. |
| Read project section structure | Enterprise | `asana_get_project_sections` | Not exposed on preview surface. |
| Read / post project status updates | Preview (read) / Enterprise (post structured) | Preview `get_status_overview`, `create_project_status_update`; enterprise `asana_get_project_statuses`, `asana_create_project_status` | Pick by the colour / structure of the update. |
| Read attachments for a task | Preview | `get_attachments` | Lighter. |
| Read one attachment object | Enterprise | `asana_get_attachment` | Preview doesn't expose object detail. |

If a use case isn't in the table, default to **enterprise** (the broader surface) and note in the reply why the preview surface fell short.

## Common Workflows

### Read my tasks (today / this week)

1. `get_my_tasks` (preview). No GID lookup needed.
2. If the user wants a project-grouped view, follow with `get_project` calls for each unique project GID returned.
3. Render the list. Flag overdue or unscheduled tasks.

### Create a task with context

1. Resolve the destination project's GID via `asana_typeahead_search` (enterprise) if not already known.
2. Show the user the proposed task body (title, notes, assignee, due date, project, tags) and ask for sign-off.
3. On sign-off, call `create_tasks` (preview) or `create_task_preview_v3` (if the user wants to see the preview shape inside Asana).

### Project from scratch

1. Resolve the team / workspace GID via `asana_typeahead_search`.
2. Sketch the project: name, sections, initial tasks per section. Show the user.
3. On sign-off, `create_project_preview_v2` (preview), then `create_project` to commit.
4. For each section's tasks, `create_tasks` in a batch.

### Portfolio status pull

1. `asana_typeahead_search` to resolve the portfolio GID by name.
2. `asana_get_portfolio` for the portfolio meta.
3. `asana_get_items_for_portfolio` for the rollup items.
4. For each project item, `asana_get_project_status` or `asana_get_project_statuses` for the latest health line.
5. Render the rollup.

### Goal update

1. `asana_typeahead_search` to resolve the goal GID.
2. `asana_get_goal` for current state.
3. Show the user the proposed metric change.
4. On sign-off, `asana_update_goal_metric` (numeric) or `asana_update_goal` (other fields).

### Dependency wiring

1. `asana_typeahead_search` for both task GIDs (the dependent and the dependee).
2. Show the user the proposed dependency chain (A blocks B).
3. On sign-off, `asana_set_task_dependencies` on B with A in the list (or `asana_set_task_dependents` on A with B).

### Cross-team capacity check

1. `asana_get_teams_for_workspace` to enumerate teams.
2. For the target team(s), `asana_get_team_users` for members.
3. `asana_get_allocations` per member for the target time period.
4. `asana_get_time_periods` if the user named a period informally ("this quarter"); resolve to the matching GID.
5. Render the load report.

### Meeting follow-up to task (cross-skill)

1. Cross-skill with `calendar-workflows`: the user identifies an event whose follow-ups need to become tasks.
2. Resolve the destination project GID via `asana_typeahead_search`.
3. Sketch the follow-up task(s) with meeting context (date, attendees, notes excerpt) and ask for sign-off.
4. On sign-off, `create_tasks` (preview) to land them.

## Preview-first discipline

For any create or restructure that touches more than three objects, or that builds nested structure (project with sections, project with bulk tasks, batch task creation), reach for the preview variant first (`create_task_preview_v3`, `create_project_preview_v2`). It gives the user a chance to inspect the proposed shape inside Asana before the final commit. Direct `create_*` calls are for single-object, low-stakes operations where the user has already approved the exact body.

## Acting-user scope vs workspace scope

The preview surface defaults to the acting user. The enterprise surface needs explicit scope (workspace GID, team GID, project GID, etc.). The locked routing rule: **always resolve any unknown GID via `asana_typeahead_search` (enterprise) first**, even if the rest of the workflow then routes back to the preview surface. This avoids "wrong-entity" errors where the preview surface guesses an acting-user-scoped match that is actually a different object.

Pattern:

```
1. asana_list_workspaces (enterprise) once per session to anchor the workspace GID
2. asana_typeahead_search (enterprise) with the workspace GID and the name fragment
3. Route the remaining tool calls to whichever surface fits the use case
```

`asana_get_workspace_users` is the right call when the user names a person by display name and you need their assignee GID.

## Direct REST API reference (bundled)

Most of this skill routes work through the wired Asana MCPs. When you instead work against the **Asana REST
API directly**, consult the bundled full reference rather than guessing. Direct REST is the path in two
cases: you are writing something that runs unattended (a script, a service, a CI job), **or** the estate you
are working in pins direct REST as its access rule, in which case it is the primary path for every call
including plain interactive reads, not an exception.

- **`references/asana-rest-api.md`** - the whole Asana REST API: base URL + auth, an endpoint index for every
  operation (grouped by resource), expanded schemas for the high-value resources with exact enum values, and
  a hand-maintained "behaviours worth knowing" section: team-share via `POST /memberships` (not `addMembers`,
  which rejects teams); `access_level` enums per resource; the `private_to_team` -> `private` privacy trap;
  notifications are not in the API; portfolio membership does not cascade to child projects; the
  custom-field-on-portfolio gotcha; pagination + rate limits.
- **`references/gen_asana_ref.py`** - regenerates the reference from Asana's official OpenAPI spec.

**Refresh on use when stale (cache-with-TTL, 30 days).** The reference carries a "Last refreshed" date and a
30-day TTL. When you rely on it and that date is older than 30 days, refresh it first (the recipe is in the
reference's "How to refresh" section: re-fetch the OpenAPI spec, re-run the generator, re-assemble, re-stamp
the date to today), then use it. No scheduler - refresh happens only on use, when stale.

## Cross-references

- `revops`: when a RevOps automation lands as an Asana task (handoff, SLA alert, deal-desk approval). The revops skill drives the trigger and the field set; this skill drives the MCP-side call shape.
- `calendar-workflows`: meeting-to-task follow-ups; the calendar skill identifies the event, this skill creates the task.
- `gmail-workflows`: email-to-task follow-ups; the Gmail skill drafts the reply, this skill creates the linked task.
- `plan-time-tooling`: routing decisions about which task system to use (Asana vs Linear vs Jira vs none). Architecture-shaped; this skill only fires after that decision has settled on Asana.
- `humanise-comms`: task titles, descriptions, and comments are human-bound text; voice rules apply.

## Red Flags

- Reaching for a connector on a surface whose estate pins direct REST. The routing table is a default, not a licence; an estate access rule outranks it, and the opening read of a session is where this is usually breached, before anyone has re-read the standing rules.
- Skipping `asana_typeahead_search` and guessing a GID. The preview surface's acting-user defaults are convenient but they can land you on the wrong object silently. Resolve first, act second.
- Calling `create_tasks` for a batch of more than three tasks without using `create_task_preview_v3` first. The preview gives the user a chance to catch a wrong project / section / field before bulk landing.
- Calling `delete_task` or `asana_delete_task` without explicit user confirmation of the exact GID and title.
- Mixing preview and enterprise surfaces for the same logical operation (e.g. `get_task` from preview for the read, then `asana_update_task` from enterprise for the write). Pick one surface per operation; switch only at workflow boundaries.
- Treating `add_comment` (preview) and `asana_create_task_story` (enterprise) as interchangeable. The story tool supports rich formatting and attachments; the comment tool is plain text. Match the tool to the content.
- Sending PII (customer names, deal sizes, headcount numbers) into a comment or task description without a sensitivity check.
- Calling enterprise tools for a clearly acting-user-scope operation (e.g. `asana_get_tasks` when `get_my_tasks` would do). Wastes parameters and obscures intent.
- Forgetting that `asana_get_time_periods` returns GIDs; you cannot pass a free-text period name to allocation queries.

## Bottom Line

Check for an estate access rule before anything else; where one exists it decides the access path and this skill supplies only the call mechanics. Absent such a rule: two Asana MCPs are wired. Resolve every unknown GID via enterprise `asana_typeahead_search` first; then route the rest of the workflow to the preview surface for acting-user operations and the enterprise surface for workspace-scope operations. Preview-first for any structured or bulk create. Confirm mutating calls with the user before they land.
