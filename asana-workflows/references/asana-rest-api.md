# Asana REST API reference

> **Last refreshed: 2026-07-26. Freshness TTL: 30 days.** Cache-with-TTL, not a scheduled job: when a session
> **uses** this reference and the date above is older than the TTL, **refresh it first** (re-run the recipe at
> the end: re-fetch the OpenAPI spec, regenerate the lower half, re-stamp the date), then rely on it. Refresh
> only on use, when stale.

A walkable reference to the whole Asana REST API, generated from Asana's official OpenAPI spec, with a
hand-maintained top section capturing behaviours that the spec alone does not make obvious (verified live
against the API). Base URL `https://app.asana.com/api/1.0`; auth `Authorization: Bearer <token>` (personal
access token or OAuth2).

## API behaviours worth knowing (verified live)

### Team-sharing: use POST /memberships, not addMembers
- To share a **portfolio or project with a TEAM**, use `POST /memberships`
  `{data:{member:<team_gid>, parent:<portfolio_or_project_gid>, access_level:<level>}}` -> **HTTP 201**. This
  is the only endpoint that accepts a team as a member.
- `POST /portfolios/{gid}/addMembers` and `POST /projects/{gid}/addMembers` **reject a team gid** -> HTTP 400
  "Not a user in Organization". `addMembers` is user-only.
- **Read team-shares back** via `GET /memberships?parent=<gid>&opt_fields=member.name,member.resource_type,access_level`.
  The `GET /projects/{gid}/project_memberships` surface and a portfolio's `members` field **omit teams**; the
  generic `/memberships?parent=` shows both users and teams.

### access_level enums (from the spec)
| Parent | Valid `access_level` |
|---|---|
| Project | `admin`, `editor`, `commenter`, `viewer` |
| Portfolio | `admin`, `editor`, `viewer` (no commenter) |
| Goal | `viewer`, `commenter`, `editor`, `admin` |
| Custom field | `admin`, `editor`, `user` |

### Setting privileges + notifications on a membership
- **Privilege (`access_level`) is settable at invite and updatable later.** `POST /memberships`
  `{data:{member, parent, access_level, role?}}` sets it at creation; `PUT /memberships/{membership_gid}`
  `{data:{access_level}}` changes it (access_level is the only updatable field). Read via
  `GET /memberships/{membership_gid}`; remove via `DELETE /memberships/{membership_gid}`.
- **Notifications are not in the REST API.** No membership schema (create / update / response) has a
  notification field, and no schema in the spec has a `notif*` field. Notification behaviour is GUI-only /
  per-user; you cannot set an invitee's notification preferences over REST.
- The per-resource membership endpoints (`/project_memberships`, `/portfolio_memberships`,
  `/team_memberships`, `/workspace_memberships`) are **GET-only**; writes go through `/memberships`.

### Project `privacy_setting` (`public_to_workspace` | `private_to_team` | `private`) - a trap
- `private_to_team` is on a deprecation path. In current Asana it may be **silently normalised to `private`
  with NO team membership added**, so a project created `private_to_team` can end up visible only to its
  creator - `privacy_setting` alone does **not** reliably team-share. Use `POST /memberships` for team
  visibility. `public_to_workspace` is preserved but exposes the object to the whole workspace. Verify the
  current behaviour live before relying on it.

### Inheritance
- Portfolio membership does **not** auto-cascade to child projects. A GUI "share all projects in this
  portfolio" applies to the projects that exist **at share time** only; future projects need their own share
  (e.g. a `POST /memberships` per created project).

### Custom-field value on a project
- To set a custom-field VALUE on a **project**, attach the field to the **containing portfolio**
  (`POST /portfolios/{gid}/addCustomFieldSetting`), not the project. Attaching to a project only exposes the
  field to that project's TASKS; a project value-write then 400s "not on given object".
- **The diagnostic lies, which is what makes this expensive.** After
  `POST /projects/{gid}/addCustomFieldSetting`, a `PUT /projects/{gid}` with
  `{"custom_fields": {"<field_gid>": <value>}}` returns `HTTP 400 "Custom field <id> is not on given object"`
  **while `GET /projects/{gid}/custom_field_settings` shows the field attached**. It is not eventual
  consistency, so retrying never clears it. Read the write path, not the settings list.
- Task-level custom-field values work the normal way; only **project-level** values need the portfolio
  attachment (one value per project matches that data model).
- Refs: Asana dev forum, ["is not on given object, it's definitely on"](https://forum.asana.com/t/api-put-call-for-updating-a-project-giving-custom-field-with-id-gid-of-custom-field-is-not-on-given-object-its-definitely-on/618448);
  [Add a custom field to a portfolio](https://developers.asana.com/reference/addcustomfieldsettingforportfolio).
  Verified live 2026-07-25.
- Read-side sibling: a project's `custom_fields` comes back as a **flat** list, so check
  `cf['gid']` / `cf['display_value']` / `cf['enum_value']['name']`, never `cf['custom_field']['gid']`. That
  nesting belongs to `custom_field_settings`, which for a project lists only TASK-level fields and never a
  portfolio-promoted project-level one. Confusing them false-reads a SET field as unset.

### Creating an enum custom field needs at least one option
- `POST /custom_fields` with `resource_subtype: "enum"` and an empty `enum_options` returns
  **`400 custom_field_enum_cannot_be_empty`** ("must have at least 1 option"). `multi_enum` is exempt.
- Seed at least one bootstrap option at creation, then add the rest additively via
  `POST /custom_fields/{gid}/enum_options`.
- **It only surfaces on the live create**, so it survives review: a `--dry-run` passes and a naive test fake
  passes, because neither actually POSTs. Model it in the fake, or assert the at-least-one-option invariant
  at the spec level, or the first real apply is where you find out.

### Mechanics
- **Pagination**: `limit` (1-100) + `offset` (opaque token from `next_page.offset`).
- **Sparse fields**: `opt_fields=a,b.c` (nested with dots). Many fields are opt-in (e.g. `parent`, `members`).
- **Rate limits**: HTTP 429 + `Retry-After`; back off and retry.

---
_Generated from the Asana OpenAPI spec (openapi 3.0.0, info.version 1.0). Source: https://raw.githubusercontent.com/Asana/openapi/master/defs/asana_oas.yaml_

**Base URL:** `https://app.asana.com/api/1.0`  
**Auth:** `Authorization: Bearer <PAT>` (personal access token) or OAuth2. **Pagination:** `limit` + `offset` (offset is an opaque token from `next_page`). **Sparse fields:** `opt_fields=a,b.c`. **Rate limits:** HTTP 429 with `Retry-After`.


## Endpoint index (all operations)


### AI Studio usage API

| Method | Path | Summary |
|---|---|---|
| `GET` | `/workspaces/{workspace_gid}/ai_studio/runs` | Get AI Studio credit utilization |
| `GET` | `/workspaces/{workspace_gid}/ai_studio/seats` | Get AI Studio seats |

### Access requests

| Method | Path | Summary |
|---|---|---|
| `GET` | `/access_requests` | Get access requests |
| `POST` | `/access_requests` | Create an access request |
| `POST` | `/access_requests/{access_request_gid}/approve` | Approve an access request |
| `POST` | `/access_requests/{access_request_gid}/reject` | Reject an access request |

### Agents

| Method | Path | Summary |
|---|---|---|
| `GET` | `/agents/{agent_gid}` | Get an agent |
| `GET` | `/workspaces/{workspace_gid}/agents` | Get a list of agents in a workspace |

### Allocations

| Method | Path | Summary |
|---|---|---|
| `GET` | `/allocations` | Get multiple allocations |
| `POST` | `/allocations` | Create an allocation |
| `DELETE` | `/allocations/{allocation_gid}` | Delete an allocation |
| `GET` | `/allocations/{allocation_gid}` | Get an allocation |
| `PUT` | `/allocations/{allocation_gid}` | Update an allocation |

### Attachments

| Method | Path | Summary |
|---|---|---|
| `GET` | `/attachments` | Get attachments from an object |
| `POST` | `/attachments` | Upload an attachment |
| `DELETE` | `/attachments/{attachment_gid}` | Delete an attachment |
| `GET` | `/attachments/{attachment_gid}` | Get an attachment |

### Audit log API

| Method | Path | Summary |
|---|---|---|
| `GET` | `/workspaces/{workspace_gid}/audit_log_events` | Get audit log events |

### Batch API

| Method | Path | Summary |
|---|---|---|
| `POST` | `/batch` | Submit parallel requests |

### Budgets

| Method | Path | Summary |
|---|---|---|
| `GET` | `/budgets` | Get all budgets |
| `POST` | `/budgets` | Create a budget |
| `DELETE` | `/budgets/{budget_gid}` | Delete a budget |
| `GET` | `/budgets/{budget_gid}` | Get a budget |
| `PUT` | `/budgets/{budget_gid}` | Update a budget |

### Custom field settings

| Method | Path | Summary |
|---|---|---|
| `GET` | `/goals/{goal_gid}/custom_field_settings` | Get a goal's custom fields |
| `GET` | `/portfolios/{portfolio_gid}/custom_field_settings` | Get a portfolio's custom fields |
| `GET` | `/projects/{project_gid}/custom_field_settings` | Get a project's custom fields |
| `GET` | `/teams/{team_gid}/custom_field_settings` | Get a team's custom fields |

### Custom fields

| Method | Path | Summary |
|---|---|---|
| `POST` | `/custom_fields` | Create a custom field |
| `DELETE` | `/custom_fields/{custom_field_gid}` | Delete a custom field |
| `GET` | `/custom_fields/{custom_field_gid}` | Get a custom field |
| `PUT` | `/custom_fields/{custom_field_gid}` | Update a custom field |
| `POST` | `/custom_fields/{custom_field_gid}/enum_options` | Create an enum option |
| `POST` | `/custom_fields/{custom_field_gid}/enum_options/insert` | Reorder a custom field's enum |
| `PUT` | `/enum_options/{enum_option_gid}` | Update an enum option |
| `GET` | `/workspaces/{workspace_gid}/custom_fields` | Get a workspace's custom fields |

### Custom types

| Method | Path | Summary |
|---|---|---|
| `GET` | `/custom_types` | Get all custom types associated with an object |
| `GET` | `/custom_types/{custom_type_gid}` | Get a custom type |

### Events

| Method | Path | Summary |
|---|---|---|
| `GET` | `/events` | Get events on a resource |

### Exports

| Method | Path | Summary |
|---|---|---|
| `POST` | `/exports/graph` | Initiate a graph export |
| `POST` | `/exports/resource` | Initiate a resource export |

### Goal relationships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/goal_relationships` | Get goal relationships |
| `GET` | `/goal_relationships/{goal_relationship_gid}` | Get a goal relationship |
| `PUT` | `/goal_relationships/{goal_relationship_gid}` | Update a goal relationship |
| `POST` | `/goals/{goal_gid}/addSupportingRelationship` | Add a supporting goal relationship |
| `POST` | `/goals/{goal_gid}/removeSupportingRelationship` | Removes a supporting goal relationship |

### Goals

| Method | Path | Summary |
|---|---|---|
| `GET` | `/goals` | Get goals |
| `POST` | `/goals` | Create a goal |
| `DELETE` | `/goals/{goal_gid}` | Delete a goal |
| `GET` | `/goals/{goal_gid}` | Get a goal |
| `PUT` | `/goals/{goal_gid}` | Update a goal |
| `POST` | `/goals/{goal_gid}/addCustomFieldSetting` | Add a custom field to a goal |
| `POST` | `/goals/{goal_gid}/addFollowers` | Add a collaborator to a goal |
| `GET` | `/goals/{goal_gid}/parentGoals` | Get parent goals from a goal |
| `POST` | `/goals/{goal_gid}/removeCustomFieldSetting` | Remove a custom field from a goal |
| `POST` | `/goals/{goal_gid}/removeFollowers` | Remove a collaborator from a goal |
| `POST` | `/goals/{goal_gid}/setMetric` | Create a goal metric |
| `POST` | `/goals/{goal_gid}/setMetricCurrentValue` | Update a goal metric |

### Jobs

| Method | Path | Summary |
|---|---|---|
| `GET` | `/jobs/{job_gid}` | Get a job by id |

### Memberships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/memberships` | Get multiple memberships |
| `POST` | `/memberships` | Create a membership |
| `DELETE` | `/memberships/{membership_gid}` | Delete a membership |
| `GET` | `/memberships/{membership_gid}` | Get a membership |
| `PUT` | `/memberships/{membership_gid}` | Update a membership |

### Ooo entries

| Method | Path | Summary |
|---|---|---|
| `GET` | `/ooo_entries` | Get OOO entries for a user |
| `POST` | `/ooo_entries` | Create an OOO entry |
| `DELETE` | `/ooo_entries/{ooo_entry_gid}` | Delete an OOO entry |
| `GET` | `/ooo_entries/{ooo_entry_gid}` | Get an OOO entry |
| `PUT` | `/ooo_entries/{ooo_entry_gid}` | Update an OOO entry |

### Organization exports

| Method | Path | Summary |
|---|---|---|
| `POST` | `/organization_exports` | Create an organization export request |
| `GET` | `/organization_exports/{organization_export_gid}` | Get details on an org export request |

### Portfolio memberships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/portfolio_memberships` | Get multiple portfolio memberships |
| `GET` | `/portfolio_memberships/{portfolio_membership_gid}` | Get a portfolio membership |
| `GET` | `/portfolios/{portfolio_gid}/portfolio_memberships` | Get memberships from a portfolio |

### Portfolios

| Method | Path | Summary |
|---|---|---|
| `GET` | `/portfolios` | Get multiple portfolios |
| `POST` | `/portfolios` | Create a portfolio |
| `DELETE` | `/portfolios/{portfolio_gid}` | Delete a portfolio |
| `GET` | `/portfolios/{portfolio_gid}` | Get a portfolio |
| `PUT` | `/portfolios/{portfolio_gid}` | Update a portfolio |
| `POST` | `/portfolios/{portfolio_gid}/addCustomFieldSetting` | Add a custom field to a portfolio |
| `POST` | `/portfolios/{portfolio_gid}/addItem` | Add a portfolio item |
| `POST` | `/portfolios/{portfolio_gid}/addMembers` | Add users to a portfolio |
| `POST` | `/portfolios/{portfolio_gid}/duplicate` | Duplicate a portfolio |
| `GET` | `/portfolios/{portfolio_gid}/items` | Get portfolio items |
| `POST` | `/portfolios/{portfolio_gid}/removeCustomFieldSetting` | Remove a custom field from a portfolio |
| `POST` | `/portfolios/{portfolio_gid}/removeItem` | Remove a portfolio item |
| `POST` | `/portfolios/{portfolio_gid}/removeMembers` | Remove users from a portfolio |

### Project briefs

| Method | Path | Summary |
|---|---|---|
| `DELETE` | `/project_briefs/{project_brief_gid}` | Delete a project brief |
| `GET` | `/project_briefs/{project_brief_gid}` | Get a project brief |
| `PUT` | `/project_briefs/{project_brief_gid}` | Update a project brief |
| `POST` | `/projects/{project_gid}/project_briefs` | Create a project brief |

### Project memberships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/project_memberships/{project_membership_gid}` | Get a project membership |
| `GET` | `/projects/{project_gid}/project_memberships` | Get memberships from a project |

### Project portfolio settings

| Method | Path | Summary |
|---|---|---|
| `GET` | `/portfolios/{portfolio_gid}/project_portfolio_settings` | Get project portfolio settings for a portfolio |
| `GET` | `/project_portfolio_settings/{project_portfolio_setting_gid}` | Get a project portfolio setting |
| `PUT` | `/project_portfolio_settings/{project_portfolio_setting_gid}` | Update a project portfolio setting |
| `GET` | `/projects/{project_gid}/project_portfolio_settings` | Get project portfolio settings for a project |

### Project statuses

| Method | Path | Summary |
|---|---|---|
| `DELETE` | `/project_statuses/{project_status_gid}` | Delete a project status |
| `GET` | `/project_statuses/{project_status_gid}` | Get a project status |
| `GET` | `/projects/{project_gid}/project_statuses` | Get statuses from a project |
| `POST` | `/projects/{project_gid}/project_statuses` | Create a project status |

### Project templates

| Method | Path | Summary |
|---|---|---|
| `GET` | `/project_templates` | Get multiple project templates |
| `DELETE` | `/project_templates/{project_template_gid}` | Delete a project template |
| `GET` | `/project_templates/{project_template_gid}` | Get a project template |
| `POST` | `/project_templates/{project_template_gid}/instantiateProject` | Instantiate a project from a project template |
| `GET` | `/teams/{team_gid}/project_templates` | Get a team's project templates |

### Projects

| Method | Path | Summary |
|---|---|---|
| `GET` | `/projects` | Get multiple projects |
| `POST` | `/projects` | Create a project |
| `DELETE` | `/projects/{project_gid}` | Delete a project |
| `GET` | `/projects/{project_gid}` | Get a project |
| `PUT` | `/projects/{project_gid}` | Update a project |
| `POST` | `/projects/{project_gid}/addCustomFieldSetting` | Add a custom field to a project |
| `POST` | `/projects/{project_gid}/addFollowers` | Add followers to a project |
| `POST` | `/projects/{project_gid}/addMembers` | Add users to a project |
| `POST` | `/projects/{project_gid}/duplicate` | Duplicate a project |
| `POST` | `/projects/{project_gid}/removeCustomFieldSetting` | Remove a custom field from a project |
| `POST` | `/projects/{project_gid}/removeFollowers` | Remove followers from a project |
| `POST` | `/projects/{project_gid}/removeMembers` | Remove users from a project |
| `POST` | `/projects/{project_gid}/saveAsTemplate` | Create a project template from a project |
| `GET` | `/projects/{project_gid}/task_counts` | Get task count of a project |
| `GET` | `/tasks/{task_gid}/projects` | Get projects a task is in |
| `GET` | `/teams/{team_gid}/projects` | Get a team's projects |
| `POST` | `/teams/{team_gid}/projects` | Create a project in a team |
| `GET` | `/workspaces/{workspace_gid}/projects` | Get all projects in a workspace |
| `POST` | `/workspaces/{workspace_gid}/projects` | Create a project in a workspace |
| `GET` | `/workspaces/{workspace_gid}/projects/search` | Search projects in a workspace |

### Rates

| Method | Path | Summary |
|---|---|---|
| `GET` | `/rates` | Get multiple rates |
| `POST` | `/rates` | Create a rate |
| `DELETE` | `/rates/{rate_gid}` | Delete a rate |
| `GET` | `/rates/{rate_gid}` | Get a rate |
| `PUT` | `/rates/{rate_gid}` | Update a rate |

### Reactions

| Method | Path | Summary |
|---|---|---|
| `GET` | `/reactions` | Get reactions with an emoji base on an object. |

### Roles

| Method | Path | Summary |
|---|---|---|
| `GET` | `/roles` | Get multiple roles |
| `POST` | `/roles` | Create a role |
| `DELETE` | `/roles/{role_gid}` | Delete a role |
| `GET` | `/roles/{role_gid}` | Get a role |
| `PUT` | `/roles/{role_gid}` | Update a role |

### Rules

| Method | Path | Summary |
|---|---|---|
| `POST` | `/rule_triggers/{rule_trigger_gid}/run` | Trigger a rule |

### Sections

| Method | Path | Summary |
|---|---|---|
| `GET` | `/projects/{project_gid}/sections` | Get sections in a project |
| `POST` | `/projects/{project_gid}/sections` | Create a section in a project |
| `POST` | `/projects/{project_gid}/sections/insert` | Move or Insert sections |
| `DELETE` | `/sections/{section_gid}` | Delete a section |
| `GET` | `/sections/{section_gid}` | Get a section |
| `PUT` | `/sections/{section_gid}` | Update a section |
| `POST` | `/sections/{section_gid}/addTask` | Add task to section |

### Status updates

| Method | Path | Summary |
|---|---|---|
| `GET` | `/status_updates` | Get status updates from an object |
| `POST` | `/status_updates` | Create a status update |
| `DELETE` | `/status_updates/{status_update_gid}` | Delete a status update |
| `GET` | `/status_updates/{status_update_gid}` | Get a status update |

### Stories

| Method | Path | Summary |
|---|---|---|
| `GET` | `/goals/{goal_gid}/stories` | Get stories from a goal |
| `POST` | `/goals/{goal_gid}/stories` | Create a story on a goal |
| `DELETE` | `/stories/{story_gid}` | Delete a story |
| `GET` | `/stories/{story_gid}` | Get a story |
| `PUT` | `/stories/{story_gid}` | Update a story |
| `GET` | `/tasks/{task_gid}/stories` | Get stories from a task |
| `POST` | `/tasks/{task_gid}/stories` | Create a story on a task |

### Tags

| Method | Path | Summary |
|---|---|---|
| `GET` | `/tags` | Get multiple tags |
| `POST` | `/tags` | Create a tag |
| `DELETE` | `/tags/{tag_gid}` | Delete a tag |
| `GET` | `/tags/{tag_gid}` | Get a tag |
| `PUT` | `/tags/{tag_gid}` | Update a tag |
| `GET` | `/tasks/{task_gid}/tags` | Get a task's tags |
| `GET` | `/workspaces/{workspace_gid}/tags` | Get tags in a workspace |
| `POST` | `/workspaces/{workspace_gid}/tags` | Create a tag in a workspace |

### Task templates

| Method | Path | Summary |
|---|---|---|
| `GET` | `/task_templates` | Get multiple task templates |
| `DELETE` | `/task_templates/{task_template_gid}` | Delete a task template |
| `GET` | `/task_templates/{task_template_gid}` | Get a task template |
| `POST` | `/task_templates/{task_template_gid}/instantiateTask` | Instantiate a task from a task template |

### Tasks

| Method | Path | Summary |
|---|---|---|
| `GET` | `/projects/{project_gid}/tasks` | Get tasks from a project |
| `GET` | `/sections/{section_gid}/tasks` | Get tasks from a section |
| `GET` | `/tags/{tag_gid}/tasks` | Get tasks from a tag |
| `GET` | `/tasks` | Get multiple tasks |
| `POST` | `/tasks` | Create a task |
| `DELETE` | `/tasks/{task_gid}` | Delete a task |
| `GET` | `/tasks/{task_gid}` | Get a task |
| `PUT` | `/tasks/{task_gid}` | Update a task |
| `POST` | `/tasks/{task_gid}/addDependencies` | Set dependencies for a task |
| `POST` | `/tasks/{task_gid}/addDependents` | Set dependents for a task |
| `POST` | `/tasks/{task_gid}/addFollowers` | Add followers to a task |
| `POST` | `/tasks/{task_gid}/addProject` | Add a project to a task |
| `POST` | `/tasks/{task_gid}/addTag` | Add a tag to a task |
| `GET` | `/tasks/{task_gid}/dependencies` | Get dependencies from a task |
| `GET` | `/tasks/{task_gid}/dependents` | Get dependents from a task |
| `POST` | `/tasks/{task_gid}/duplicate` | Duplicate a task |
| `POST` | `/tasks/{task_gid}/removeDependencies` | Unlink dependencies from a task |
| `POST` | `/tasks/{task_gid}/removeDependents` | Unlink dependents from a task |
| `POST` | `/tasks/{task_gid}/removeFollowers` | Remove followers from a task |
| `POST` | `/tasks/{task_gid}/removeProject` | Remove a project from a task |
| `POST` | `/tasks/{task_gid}/removeTag` | Remove a tag from a task |
| `POST` | `/tasks/{task_gid}/setParent` | Set the parent of a task |
| `GET` | `/tasks/{task_gid}/subtasks` | Get subtasks from a task |
| `POST` | `/tasks/{task_gid}/subtasks` | Create a subtask |
| `GET` | `/user_task_lists/{user_task_list_gid}/tasks` | Get tasks from a user task list |
| `GET` | `/workspaces/{workspace_gid}/tasks/custom_id/{custom_id}` | Get a task for a given custom ID |
| `GET` | `/workspaces/{workspace_gid}/tasks/search` | Search tasks in a workspace |

### Team memberships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/team_memberships` | Get team memberships |
| `GET` | `/team_memberships/{team_membership_gid}` | Get a team membership |
| `GET` | `/teams/{team_gid}/team_memberships` | Get memberships from a team |
| `GET` | `/users/{user_gid}/team_memberships` | Get memberships from a user |

### Teams

| Method | Path | Summary |
|---|---|---|
| `POST` | `/teams` | Create a team |
| `GET` | `/teams/{team_gid}` | Get a team |
| `PUT` | `/teams/{team_gid}` | Update a team |
| `POST` | `/teams/{team_gid}/addUser` | Add a user to a team |
| `POST` | `/teams/{team_gid}/removeUser` | Remove a user from a team |
| `GET` | `/users/{user_gid}/teams` | Get teams for a user |
| `GET` | `/workspaces/{workspace_gid}/teams` | Get teams in a workspace |

### Time periods

| Method | Path | Summary |
|---|---|---|
| `GET` | `/time_periods` | Get time periods |
| `GET` | `/time_periods/{time_period_gid}` | Get a time period |

### Time tracking categories

| Method | Path | Summary |
|---|---|---|
| `GET` | `/time_tracking_categories` | Get time tracking categories for a workspace |
| `POST` | `/time_tracking_categories` | Create a time tracking category |
| `DELETE` | `/time_tracking_categories/{time_tracking_category_gid}` | Delete a time tracking category |
| `GET` | `/time_tracking_categories/{time_tracking_category_gid}` | Get a time tracking category |
| `PUT` | `/time_tracking_categories/{time_tracking_category_gid}` | Update a time tracking category |
| `GET` | `/time_tracking_categories/{time_tracking_category_gid}/time_tracking_entries` | Get time tracking entries for a time tracking category |

### Time tracking entries

| Method | Path | Summary |
|---|---|---|
| `GET` | `/tasks/{task_gid}/time_tracking_entries` | Get time tracking entries for a task |
| `POST` | `/tasks/{task_gid}/time_tracking_entries` | Create a time tracking entry |
| `GET` | `/time_tracking_entries` | Get multiple time tracking entries |
| `DELETE` | `/time_tracking_entries/{time_tracking_entry_gid}` | Delete a time tracking entry |
| `GET` | `/time_tracking_entries/{time_tracking_entry_gid}` | Get a time tracking entry |
| `PUT` | `/time_tracking_entries/{time_tracking_entry_gid}` | Update a time tracking entry |

### Timesheet approval statuses

| Method | Path | Summary |
|---|---|---|
| `GET` | `/timesheet_approval_statuses` | Get multiple timesheet approval statuses |
| `POST` | `/timesheet_approval_statuses` | Create a timesheet approval status |
| `GET` | `/timesheet_approval_statuses/{timesheet_approval_status_gid}` | Get a timesheet approval status |
| `PUT` | `/timesheet_approval_statuses/{timesheet_approval_status_gid}` | Update a timesheet approval status |

### Typeahead

| Method | Path | Summary |
|---|---|---|
| `GET` | `/workspaces/{workspace_gid}/typeahead` | Get objects via typeahead |

### User task lists

| Method | Path | Summary |
|---|---|---|
| `GET` | `/user_task_lists/{user_task_list_gid}` | Get a user task list |
| `GET` | `/users/{user_gid}/user_task_list` | Get a user's task list |

### Users

| Method | Path | Summary |
|---|---|---|
| `GET` | `/teams/{team_gid}/users` | Get users in a team |
| `GET` | `/users` | Get multiple users |
| `GET` | `/users/{user_gid}` | Get a user |
| `PUT` | `/users/{user_gid}` | Update a user |
| `GET` | `/users/{user_gid}/favorites` | Get a user's favorites |
| `GET` | `/workspaces/{workspace_gid}/users` | Get users in a workspace or organization |
| `GET` | `/workspaces/{workspace_gid}/users/{user_gid}` | Get a user in a workspace or organization |
| `PUT` | `/workspaces/{workspace_gid}/users/{user_gid}` | Update a user in a workspace or organization |

### Webhooks

| Method | Path | Summary |
|---|---|---|
| `GET` | `/webhooks` | Get multiple webhooks |
| `POST` | `/webhooks` | Establish a webhook |
| `DELETE` | `/webhooks/{webhook_gid}` | Delete a webhook |
| `GET` | `/webhooks/{webhook_gid}` | Get a webhook |
| `PUT` | `/webhooks/{webhook_gid}` | Update a webhook |

### Workspace memberships

| Method | Path | Summary |
|---|---|---|
| `GET` | `/users/{user_gid}/workspace_memberships` | Get workspace memberships for a user |
| `GET` | `/workspace_memberships/{workspace_membership_gid}` | Get a workspace membership |
| `GET` | `/workspaces/{workspace_gid}/workspace_memberships` | Get the workspace memberships for a workspace |

### Workspaces

| Method | Path | Summary |
|---|---|---|
| `GET` | `/workspaces` | Get multiple workspaces |
| `GET` | `/workspaces/{workspace_gid}` | Get a workspace |
| `PUT` | `/workspaces/{workspace_gid}` | Update a workspace |
| `POST` | `/workspaces/{workspace_gid}/addUser` | Add a user to a workspace or organization |
| `GET` | `/workspaces/{workspace_gid}/events` | Get workspace events |
| `POST` | `/workspaces/{workspace_gid}/removeUser` | Remove a user from a workspace or organization |

## Key resource schemas


### ProjectMembershipCompact

This object describes a team or a user's membership to a project including their level of access (Admin, Editor, Commenter, or Viewer).

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `parent` | → ProjectCompact | [Opt In](/docs/inputoutput-options). The project the user is a member of. |
| `member` | → MemberCompact | Member can be a user or a team. |
| `access_level` | enum ['admin', 'editor', 'commenter', 'viewer'] | Whether the member has admin, editor, commenter, or viewer access to the project. _(read-only)_ |

### PortfolioMembershipCompact

This object determines if a user is a member of a portfolio.

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `parent` | → PortfolioCompact | The portfolio the user is a member of. |
| `member` | → MemberCompact | Member can be a user or a team. |
| `access_level` | enum ['admin', 'editor', 'viewer'] | Whether the member has admin, editor, or viewer access to the portfolio. Portfolios do not support commenter access yet. _(read-only)_ |

### MembershipRequest

| Field | Type | Description |
|---|---|---|
| `access_level` | string | Sets the access level for the member. Goals can have access levels `viewer`, `commenter`, `editor` or `admin`. Projects can have access l... |

### MembershipUpdateRequest

| Field | Type | Description |
|---|---|---|
| `access_level` | string | The role given to the member. Goals can have access levels `editor` or `commenter`. Projects can have access levels `admin`, `editor` or ... |

### GoalMembershipBase

This object represents a user's connection to a goal.

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. |
| `resource_subtype` | string | The type of membership. _(read-only)_ |
| `member` | → MemberCompact |  |
| `parent` |  |  |
| `role` | enum ['commenter', 'editor'] | *Deprecated: Describes if the member is a commenter or editor in goal.* |
| `access_level` | enum ['viewer', 'commenter', 'editor', 'admin'] | "Describes the membership access level for the goal. This is preferred over role." |
| `goal` |  |  |

### ProjectResponse

| Field | Type | Description |
|---|---|---|
| `custom_fields` | array of CustomFieldCompact | Array of custom field values applied directly to the project itself. These represent the values set on the project, not the fields availa... _(read-only)_ |
| `completed` | boolean | True if the project is currently marked complete, false if not. _(read-only)_ |
| `completed_at` | string | The time at which this project was completed, or null if the project is not completed. _(read-only)_ |
| `completed_by` |  |  |
| `followers` | array of UserCompact | Array of users following this project. Followers are a subset of members who have opted in to receive "tasks added" notifications for a p... _(read-only)_ |
| `owner` |  | The current owner of the project, may be null. |
| `team` |  |  |
| `permalink_url` | string | A url that points directly to the object within Asana. _(read-only)_ |
| `project_brief` |  |  |
| `created_from_template` |  |  |
| `workspace` |  |  |

### ProjectRequest

| Field | Type | Description |
|---|---|---|
| `custom_fields` | object | An object where each key is the GID of a custom field and its corresponding value is either an enum GID, string, number, or object (depen... |
| `followers` | string | *Create-only*. Comma separated string of users. Followers are a subset of members who have opted in to receive "tasks added" notification... |
| `owner` | string | The current owner of the project, may be null. |
| `team` | string | *Deprecated:* The team to share this project with is deprecated. Use `POST /memberships` with `{ parent: project, member: team }` to shar... |
| `workspace` | string | The `gid` of a workspace. |

### ProjectCompact

A *project* represents a prioritized list of tasks in Asana or a board with columns of tasks represented as cards. It exists in a single workspace or organization and is accessible to a subset of user

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | Name of the project. This is generally a short sentence fragment that fits on a line in the UI for maximum readability. However, it can b... |

### ProjectBase

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | Name of the project. This is generally a short sentence fragment that fits on a line in the UI for maximum readability. However, it can b... |
| `archived` | boolean | True if the project is archived, false if not. Archived projects do not show in the UI by default and may be treated differently for quer... |
| `color` | enum ['dark-pink', 'dark-green', 'dark-blue', 'dark-red', 'dark-teal', 'dark-brown', 'dark-orange', 'dark-purple', 'dark-warm-gray', 'light-pink', 'light-green', 'light-blue', 'light-red', 'light-teal', 'light-brown', 'light-orange', 'light-purple', 'light-warm-gray', 'none', None] | Color of the project. |
| `icon` | enum ['list', 'board', 'timeline', 'calendar', 'rocket', 'people', 'graph', 'star', 'bug', 'light_bulb', 'globe', 'gear', 'notebook', 'computer', 'check', 'target', 'html', 'megaphone', 'chat_bubbles', 'briefcase', 'page_layout', 'mountain_flag', 'puzzle', 'presentation', 'line_and_symbols', 'speed_dial', 'ribbon', 'shoe', 'shopping_basket', 'map', 'ticket', 'coins'] | The icon for a project. |
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `current_status` |  |  |
| `current_status_update` |  |  |
| `custom_field_settings` | array of CustomFieldSettingResponse | Array of custom field definitions that are enabled for the project. These represent which custom fields are available to be used on tasks... _(read-only)_ |
| `default_view` | enum ['list', 'board', 'calendar', 'timeline'] | The default view (list, board, calendar, or timeline) of a project. |
| `due_date` | string | *Deprecated: new integrations should prefer the `due_on` field.* |
| `due_on` | string | The day on which this project is due. This takes a date with format YYYY-MM-DD. |
| `html_notes` | string | [Opt In](/docs/inputoutput-options). The notes of the project with formatting as HTML. |
| `members` | array of UserCompact | Array of users who are members of this project. _(read-only)_ |
| `modified_at` | string | The time at which this project was last modified. *Note: This does not currently reflect any changes in associations such as tasks or com... _(read-only)_ |
| `notes` | string | Free-form textual information associated with the project (ie., its description). |
| `public` | boolean | *Deprecated:* new integrations use `privacy_setting` instead. |
| `privacy_setting` | enum ['public_to_workspace', 'private_to_team', 'private'] | The privacy setting of the project. *Note: Administrators in your organization may restrict the values of `privacy_setting`.* The value `... |
| `start_on` | string | The day on which work for this project begins, or null if the project has no start date. This takes a date with `YYYY-MM-DD` format. *Not... |
| `default_access_level` | enum ['admin', 'editor', 'commenter', 'viewer'] | The default access for users or teams who join or are added as members to the project. |
| `minimum_access_level_for_customization` | enum ['admin', 'editor'] | The minimum access level needed for project members to modify this project's workflow and appearance. |
| `minimum_access_level_for_sharing` | enum ['admin', 'editor'] | The minimum access level needed for project members to share the project and manage project memberships. |

### PortfolioResponse

| Field | Type | Description |
|---|---|---|
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `created_by` | → UserCompact |  |
| `custom_field_settings` | array of CustomFieldSettingResponse | Array of custom field definitions that are enabled for the portfolio. These represent which custom fields are available to be used on ite... |
| `current_status_update` |  |  |
| `custom_fields` | array of CustomFieldCompact | Array of custom field values applied directly to the portfolio itself. These represent the values set on the portfolio, not the fields av... |
| `members` | array of UserCompact |  _(read-only)_ |
| `owner` | → UserCompact |  |
| `workspace` |  |  |
| `permalink_url` | string | A url that points directly to the object within Asana. _(read-only)_ |
| `public` | boolean | True if the portfolio is public to its workspace members. |
| `privacy_setting` | enum ['public_to_domain', 'members_only'] | The privacy setting of the portfolio. *Note: Administrators in your organization may restrict the values of `privacy_setting`.* |
| `project_templates` | array of ProjectTemplateCompact | Array of project templates that are in the portfolio _(read-only)_ |

### PortfolioRequest

| Field | Type | Description |
|---|---|---|
| `workspace` | string | *Create-only*. The workspace or organization that the portfolio belongs to. |
| `public` | boolean | *Deprecated:* new integrations use `privacy_setting` instead. |

### PortfolioBase

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | The name of the portfolio. |
| `archived` | boolean | [Opt In](/docs/inputoutput-options). True if the portfolio is archived, false if not. Archived portfolios do not show in the UI by defaul... |
| `color` | enum ['dark-pink', 'dark-green', 'dark-blue', 'dark-red', 'dark-teal', 'dark-brown', 'dark-orange', 'dark-purple', 'dark-warm-gray', 'light-pink', 'light-green', 'light-blue', 'light-red', 'light-teal', 'light-brown', 'light-orange', 'light-purple', 'light-warm-gray'] | Color of the portfolio. |
| `start_on` | string | The day on which work for this portfolio begins, or null if the portfolio has no start date. This takes a date with `YYYY-MM-DD` format. ... |
| `due_on` | string | The day on which this portfolio is due. This takes a date with format YYYY-MM-DD. |
| `default_access_level` | enum ['admin', 'editor', 'viewer'] | The default access level when inviting new members to the portfolio |

### TaskResponse

| Field | Type | Description |
|---|---|---|
| `assignee` |  |  |
| `assignee_section` |  |  |
| `custom_fields` | array of CustomFieldResponse | Array of custom field values applied to the task. These represent the custom field values recorded on this project for a particular custo... _(read-only)_ |
| `custom_type` |  |  |
| `custom_type_status_option` |  |  |
| `followers` | array of UserCompact | Array of users following this task. _(read-only)_ |
| `parent` |  |  |
| `projects` | array of ProjectCompact | *Create-only.* Array of projects this task is associated with. At task creation time, this array can be used to add the task to many proj... _(read-only)_ |
| `tags` | array of TagCompact | Array of tags associated with this task. In order to change tags on an existing task use `addTag` and `removeTag`. _(read-only)_ |
| `workspace` |  |  |
| `permalink_url` | string | A url that points directly to the object within Asana. _(read-only)_ |

### TaskBase

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | Name of the task. This is generally a short sentence fragment that fits on a line in the UI for maximum readability. However, it can be l... |
| `resource_subtype` | enum ['default_task', 'milestone', 'approval', 'custom'] | The subtype of this resource. Different subtypes retain many of the same fields and behavior, but may render differently in Asana or repr... |
| `created_by` | object | [Opt In](/docs/inputoutput-options). A *user* object represents an account in Asana that can be given access to various workspaces, proje... _(read-only)_ |
| `approval_status` | enum ['pending', 'approved', 'rejected', 'changes_requested'] | *Conditional* Reflects the approval status of this task. This field is kept in sync with `completed`, meaning `pending` translates to fal... |
| `assignee_status` | enum ['today', 'upcoming', 'later', 'new', 'inbox'] | *Deprecated* Scheduling status of this task for the user it is assigned to. This field can only be set if the assignee is non-null. Setti... |
| `assigned_by` |  |  |
| `completed` | boolean | True if the task is currently marked complete, false if not. |
| `completed_at` | string | The time at which this task was completed, or null if the task is incomplete. _(read-only)_ |
| `completed_by` |  |  |
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `dependencies` | array of AsanaResource | [Opt In](/docs/inputoutput-options). Array of resources referencing tasks that this task depends on. The objects contain only the gid of ... _(read-only)_ |
| `dependents` | array of AsanaResource | [Opt In](/docs/inputoutput-options). Array of resources referencing tasks that depend on this task. The objects contain only the ID of th... _(read-only)_ |
| `due_at` | string | The UTC date and time on which this task is due, or null if the task has no due time. This takes an ISO 8601 date string in UTC and shoul... |
| `due_on` | string | The localized date on which this task is due, or null if the task has no due date. This takes a date with `YYYY-MM-DD` format and should ... |
| `external` | object | *OAuth Required*. *Conditional*. This field is returned only if external values are set or included by using [Opt In](/docs/inputoutput-o... |
| `html_notes` | string | [Opt In](/docs/inputoutput-options). The notes of the text with formatting as HTML. |
| `hearted` | boolean | *Deprecated - please use liked instead* True if the task is hearted by the authorized user, false if not. _(read-only)_ |
| `hearts` | array of Like | *Deprecated - please use likes instead* Array of likes for users who have hearted this task. _(read-only)_ |
| `is_rendered_as_separator` | boolean | [Opt In](/docs/inputoutput-options). In some contexts tasks can be rendered as a visual separator; for instance, subtasks can appear simi... _(read-only)_ |
| `liked` | boolean | True if the task is liked by the authorized user, false if not. |
| `likes` | array of Like | Array of likes for users who have liked this task. _(read-only)_ |
| `memberships` | array of object | <p><strong style={{ color: "#4573D2" }}>Full object requires scope: </strong><code>projects:read</code>, <code>project_sections:read</cod... _(read-only)_ |
| `modified_at` | string | The time at which this task was last modified.  The following conditions will change `modified_at`:  - story is created on a task - story... _(read-only)_ |
| `notes` | string | Free-form textual information associated with the task (i.e. its description). |
| `num_hearts` | integer | *Deprecated - please use likes instead* The number of users who have hearted this task. _(read-only)_ |
| `num_likes` | integer | The number of users who have liked this task. _(read-only)_ |
| `num_subtasks` | integer | [Opt In](/docs/inputoutput-options). The number of subtasks on this task. _(read-only)_ |
| `start_at` | string | Date and time on which work begins for the task, or null if the task has no start time. This takes an ISO 8601 date string in UTC and sho... |
| `start_on` | string | The day on which work begins for the task , or null if the task has no start date. This takes a date with `YYYY-MM-DD` format and should ... |
| `actual_time_minutes` | number | <p><strong style={{ color: "#4573D2" }}>Full object requires scope: </strong><code>time_tracking_entries:read</code></p>  This value repr... _(read-only)_ |

### CustomFieldResponse

| Field | Type | Description |
|---|---|---|
| `representation_type` | enum ['text', 'enum', 'multi_enum', 'number', 'date', 'people', 'formula', 'custom_id', 'reference'] | This field tells the type of the custom field. _(read-only)_ |
| `id_prefix` | string | This field is the unique custom ID string for the custom field. |
| `input_restrictions` | array of string |  |
| `is_formula_field` | boolean | *Conditional*. This flag describes whether a custom field is a formula custom field. |
| `is_value_read_only` | boolean | *Conditional*. This flag describes whether a custom field is read only. |
| `created_by` |  |  |
| `people_value` | array of UserCompact | *Conditional*. Only relevant for custom fields of type `people`. This array of [compact user](/reference/users) objects reflects the valu... |
| `reference_value` | array of AsanaNamedResource | *Conditional*. Only relevant for custom fields of type `reference`. This array of objects reflects the values of a `reference` custom field. |
| `html_text_value` | string | *Conditional*. Only relevant for custom fields of type `text`. This is the HTML representation of the text value of a custom field, corre... _(read-only)_ |
| `privacy_setting` | enum ['public_with_guests', 'public', 'private'] | The privacy setting of the custom field. *Note: Administrators in your organization may restrict the values of `privacy_setting`.* |
| `default_access_level` | enum ['admin', 'editor', 'user'] | The default access level when inviting new members to the custom field. This isn't applied when the `privacy_setting` is `private`, or th... |
| `resource_subtype` | enum ['text', 'enum', 'multi_enum', 'number', 'date', 'people', 'reference'] | The type of the custom field. Must be one of the given values. _(read-only)_ |

### CustomFieldRequest

| Field | Type | Description |
|---|---|---|
| `workspace` | string | *Create-Only* The workspace to create a custom field in. |
| `owned_by_app` | boolean | *Allow-listed*. Instructs the API that this Custom Field is app-owned. This parameter is allow-listed to specific apps at this point in t... |
| `people_value` | array of string | *Conditional*. Only relevant for custom fields of type `people`. This array of user GIDs, emails, or the string "me", reflects the users ... |
| `reference_value` | array of string | *Conditional*. Only relevant for custom fields of type `reference`. This array of GIDs reflects the objects to be written to a `reference... |

### CustomFieldBase

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | The name of the custom field. |
| `type` | enum ['text', 'enum', 'multi_enum', 'number', 'date', 'people', 'reference'] | *Deprecated: new integrations should prefer the resource_subtype field.* The type of the custom field. Must be one of the given values. _(read-only)_ |
| `enum_options` | array of EnumOption | *Conditional*. Only relevant for custom fields of type `enum` or `multi_enum`. This array specifies the possible values which an `enum` c... |
| `enabled` | boolean | *Conditional*. This field applies only to [custom field values](/docs/custom-fields-guide#/accessing-custom-field-values-on-tasks-or-proj... _(read-only)_ |
| `representation_type` | enum ['text', 'enum', 'multi_enum', 'number', 'date', 'people', 'formula', 'custom_id', 'reference'] | This field tells the type of the custom field. _(read-only)_ |
| `id_prefix` | string | This field is the unique custom ID string for the custom field. |
| `input_restrictions` | array of string |  |
| `is_formula_field` | boolean | *Conditional*. This flag describes whether a custom field is a formula custom field. |
| `date_value` | object | *Conditional*. Only relevant for custom fields of type `date`. This object reflects the chosen date (and optionally, time) value of a `da... |
| `enum_value` |  |  |
| `multi_enum_values` | array of EnumOption | *Conditional*. Only relevant for custom fields of type `multi_enum`. This object is the chosen values of a `multi_enum` custom field. |
| `number_value` | number | *Conditional*. This number is the value of a `number` custom field. |
| `text_value` | string | *Conditional*. This string is the value of a `text` custom field. |
| `display_value` | string | A string representation for the value of the custom field. Integrations that don't require the underlying type should use this field to r... _(read-only)_ |
| `description` | string | [Opt In](/docs/inputoutput-options). The description of the custom field. |
| `precision` | integer | Only relevant for custom fields of type `Number`. This field dictates the number of places after the decimal to round to, i.e. 0 is integ... |
| `format` | enum ['currency', 'identifier', 'percentage', 'custom', 'duration', 'none'] | The format of this custom field. |
| `currency_code` | string | ISO 4217 currency code to format this custom field. This will be null if the `format` is not `currency`. |
| `custom_label` | string | This is the string that appears next to the custom field value. This will be null if the `format` is not `custom`. |
| `custom_label_position` | enum ['prefix', 'suffix', None] | Only relevant for custom fields with `custom` format. This depicts where to place the custom label. This will be null if the `format` is ... |
| `is_global_to_workspace` | boolean | This flag describes whether this custom field is available to every container in the workspace. Before project-specific custom fields, th... _(read-only)_ |
| `has_notifications_enabled` | boolean | *Conditional*. This flag describes whether a follower of a task with this field should receive inbox notifications from changes to this f... |
| `asana_created_field` | enum ['a_v_requirements', 'account_name', 'actionable', 'align_shipping_link', 'align_status', 'allotted_time', 'appointment', 'approval_stage', 'approved', 'article_series', 'board_committee', 'browser', 'campaign_audience', 'campaign_project_status', 'campaign_regions', 'channel_primary', 'client_topic_type', 'complete_by', 'contact', 'contact_email_address', 'content_channels', 'content_channels_needed', 'content_stage', 'content_type', 'contract', 'contract_status', 'cost', 'creation_stage', 'creative_channel', 'creative_needed', 'creative_needs', 'data_sensitivity', 'deal_size', 'delivery_appt', 'delivery_appt_date', 'department', 'department_responsible', 'design_request_needed', 'design_request_type', 'discussion_category', 'do_this_task', 'editorial_content_status', 'editorial_content_tag', 'editorial_content_type', 'effort', 'effort_level', 'est_completion_date', 'estimated_time', 'estimated_value', 'expected_cost', 'external_steps_needed', 'favorite_idea', 'feedback_type', 'financial', 'funding_amount', 'grant_application_process', 'hiring_candidate_status', 'idea_status', 'ids_link', 'ids_patient_link', 'implementation_stage', 'insurance', 'interview_area', 'interview_question_score', 'itero_scan_link', 'job_s_applied_to', 'lab', 'launch_status', 'lead_status', 'localization_language', 'localization_market_team', 'localization_status', 'meeting_minutes', 'meeting_needed', 'minutes', 'mrr', 'must_localize', 'name_of_foundation', 'need_to_follow_up', 'next_appointment', 'next_steps_sales', 'num_people', 'number_of_user_reports', 'office_location', 'onboarding_activity', 'owner', 'participants_needed', 'patient_date_of_birth', 'patient_email', 'patient_phone', 'patient_status', 'phone_number', 'planning_category', 'point_of_contact', 'position', 'post_format', 'prescription', 'priority', 'priority_level', 'product', 'product_stage', 'progress', 'project_size', 'project_status', 'proposed_budget', 'publish_status', 'reason_for_scan', 'referral', 'request_type', 'research_status', 'responsible_department', 'responsible_team', 'risk_assessment_status', 'room_name', 'sales_counterpart', 'sentiment', 'shipping_link', 'social_channels', 'stage', 'status', 'status_design', 'status_of_initiative', 'system_setup', 'task_progress', 'team', 'team_marketing', 'team_responsible', 'time_it_takes_to_complete_tasks', 'timeframe', 'treatment_type', 'type_work_requests_it', 'use_agency', 'user_name', 'vendor_category', 'vendor_type', 'word_count', None] | *Conditional*. A unique identifier to associate this field with the template source of truth. _(read-only)_ |

### EnumOption

Enum options are the possible values which an enum custom field can adopt. An enum custom field must contain at least 1 enum option but no more than 500.

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | The name of the enum option. |
| `enabled` | boolean | Whether or not the enum option is a selectable value for the custom field. |
| `color` | string | The color of the enum option. Defaults to `none`. |

### UserResponse

| Field | Type | Description |
|---|---|---|
| `workspaces` | array of WorkspaceCompact | Workspaces and organizations this user may access. Note\: The API will only return workspaces and organizations that also contain the aut... _(read-only)_ |
| `custom_fields` | array of CustomFieldCompact | Array of Custom Fields. |

### UserCompact

A *user* object represents an account in Asana that can be given access to various workspaces, projects, and tasks.

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | *Read-only except when same user as requester*. The user's name. |

### TeamResponse

| Field | Type | Description |
|---|---|---|
| `description` | string | [Opt In](/docs/inputoutput-options). The description of the team. |
| `html_description` | string | [Opt In](/docs/inputoutput-options). The description of the team with formatting as HTML. |
| `organization` |  |  |
| `permalink_url` | string | A url that points directly to the object within Asana. _(read-only)_ |
| `visibility` | enum ['secret', 'request_to_join', 'public'] | The visibility of the team to users in the same organization |
| `edit_team_name_or_description_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can edit team name and description |
| `edit_team_visibility_or_trash_team_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can edit team visibility and trash teams |
| `member_invite_management_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can accept or deny member invites for a given team |
| `guest_invite_management_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can accept or deny guest invites for a given team |
| `join_request_management_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can accept or deny join team requests for a Membership by Request team. This field can only be updated when the team's `visi... |
| `team_member_removal_access_level` | enum ['all_team_members', 'only_team_admins'] | Controls who can remove team members |
| `team_content_management_access_level` | enum ['no_restriction', 'only_team_admins'] | Controls who can create and share content with the team |
| `endorsed` | boolean | Whether the team has been endorsed |
| `custom_field_settings` | array of CustomFieldSettingResponse | Array of Custom Field Settings applied to the team. |

### TeamCompact

<p><strong style={{ color: "#4573D2" }}>Full object requires scope: </strong><code>teams:read</code></p>

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `name` | string | The name of the team. |

### WorkspaceResponse

| Field | Type | Description |
|---|---|---|
| `email_domains` | array of string | The email domains that are associated with this workspace. |
| `is_organization` | boolean | Whether the workspace is an *organization*. |

### SectionResponse

| Field | Type | Description |
|---|---|---|
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `project` | → ProjectCompact |  |
| `projects` | array of ProjectCompact | *Deprecated - please use project instead* _(read-only)_ |

### StoryResponse

| Field | Type | Description |
|---|---|---|
| `gid` | string | Globally unique identifier of the resource, as a string. _(read-only)_ |
| `resource_type` | string | The base type of this resource. _(read-only)_ |
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `resource_subtype` | string | The subtype of this resource. Different subtypes retain many of the same fields and behavior, but may render differently in Asana or repr... _(read-only)_ |
| `text` | string | The plain text of the comment to add. Cannot be used with html_text. |
| `html_text` | string | [Opt In](/docs/inputoutput-options). HTML formatted text for a comment. This will not include the name of the creator. |
| `is_pinned` | boolean | *Conditional*. Whether the story should be pinned on the resource. |
| `sticker_name` | enum ['green_checkmark', 'people_dancing', 'dancing_unicorn', 'heart', 'party_popper', 'people_waving_flags', 'splashing_narwhal', 'trophy', 'yeti_riding_unicorn', 'celebrating_people', 'determined_climbers', 'phoenix_spreading_love'] | The name of the sticker in this story. `null` if there is no sticker. |
| `created_by` | → UserCompact |  |
| `type` | enum ['comment', 'system'] |  _(read-only)_ |
| `is_editable` | boolean | *Conditional*. Whether the text of the story can be edited after creation. _(read-only)_ |
| `is_edited` | boolean | *Conditional*. Whether the text of the story has been edited after creation. _(read-only)_ |
| `hearted` | boolean | *Deprecated - please use likes instead* *Conditional*. True if the story is hearted by the authorized user, false if not. _(read-only)_ |
| `hearts` | array of Like | *Deprecated - please use likes instead*  *Conditional*. Array of likes for users who have hearted this story. _(read-only)_ |
| `num_hearts` | integer | *Deprecated - please use likes instead*  *Conditional*. The number of users who have hearted this story. _(read-only)_ |
| `liked` | boolean | *Conditional*. True if the story is liked by the authorized user, false if not. _(read-only)_ |
| `likes` | array of Like | *Conditional*. Array of likes for users who have liked this story. _(read-only)_ |
| `num_likes` | integer | *Conditional*. The number of users who have liked this story. _(read-only)_ |
| `reaction_summary` | array of ReactionSummaryItemCompact | Summary of emoji reactions on this story. _(read-only)_ |
| `previews` | array of Preview | <p><strong style={{ color: "#4573D2" }}>Full object requires scope: </strong><code>attachments:read</code></p>  *Conditional*. A collecti... _(read-only)_ |
| `old_name` | string | *Conditional* The previous name of the task before a name change. |
| `new_name` | string | *Conditional* The updated name of the task after a name change. _(read-only)_ |
| `old_dates` | → StoryResponseDates |  |
| `new_dates` | → StoryResponseDates |  |
| `old_resource_subtype` | string | *Conditional* _(read-only)_ |
| `new_resource_subtype` | string | *Conditional* _(read-only)_ |
| `story` | → StoryCompact | *Conditional* _(read-only)_ |
| `assignee` | → UserCompact | *Conditional* _(read-only)_ |
| `follower` | → UserCompact | *Conditional* _(read-only)_ |
| `old_section` | → SectionCompact | *Conditional* _(read-only)_ |
| `new_section` | → SectionCompact | *Conditional* _(read-only)_ |
| `task` | → TaskCompact | *Conditional* _(read-only)_ |
| `project` | → ProjectCompact | *Conditional* _(read-only)_ |
| `tag` | → TagCompact | *Conditional* _(read-only)_ |
| `custom_field` | → CustomFieldCompact | *Conditional* _(read-only)_ |
| `old_text_value` | string | *Conditional* The previous value of a text-type field before it was updated. _(read-only)_ |
| `new_text_value` | string | *Conditional* The new value of a text-type field after it was updated. _(read-only)_ |
| `old_number_value` | integer | *Conditional* The previous value of a number-type custom field before the update. _(read-only)_ |
| `new_number_value` | integer | *Conditional* The new value of a number-type custom field after the update. _(read-only)_ |
| `old_enum_value` | → EnumOption | *Conditional* _(read-only)_ |
| `new_enum_value` | → EnumOption | *Conditional* _(read-only)_ |
| `old_date_value` |  |  _(read-only)_ |
| `new_date_value` |  |  _(read-only)_ |
| `old_people_value` | array of UserCompact | *Conditional*. The old value of a people custom field story. _(read-only)_ |
| `new_people_value` | array of UserCompact | *Conditional*. The new value of a people custom field story. _(read-only)_ |
| `old_multi_enum_values` | array of EnumOption | *Conditional*. The old value of a multi-enum custom field story. _(read-only)_ |
| `new_multi_enum_values` | array of EnumOption | *Conditional*. The new value of a multi-enum custom field story. _(read-only)_ |
| `new_approval_status` | string | *Conditional*. The new value of approval status. _(read-only)_ |
| `old_approval_status` | string | *Conditional*. The old value of approval status. _(read-only)_ |
| `duplicate_of` | → TaskCompact | *Conditional* _(read-only)_ |
| `duplicated_from` | → TaskCompact | *Conditional* _(read-only)_ |
| `dependency` | → TaskCompact | *Conditional* _(read-only)_ |
| `source` | enum ['web', 'email', 'mobile', 'api', 'unknown'] | The component of the Asana product the user used to trigger the story. _(read-only)_ |
| `target` |  |  |

### TagResponse

| Field | Type | Description |
|---|---|---|
| `created_at` | string | The time at which this resource was created. _(read-only)_ |
| `followers` | array of UserCompact | Array of users following this tag. _(read-only)_ |
| `workspace` | → WorkspaceCompact |  |
| `permalink_url` | string | A url that points directly to the object within Asana. _(read-only)_ |

---

## How to refresh (cache-with-TTL, on use when stale)

When the "Last refreshed" date at the top is older than the TTL and you are about to rely on this reference:

1. Re-fetch the official spec:
   `curl -sL -o asana_oas.yaml https://raw.githubusercontent.com/Asana/openapi/master/defs/asana_oas.yaml`
2. Regenerate the lower half (needs `pyyaml`): `python3 gen_asana_ref.py` (walks the spec → endpoint index +
   key-resource schemas → `asana-api-reference.generated.md`).
3. Re-assemble: concatenate the hand-maintained header section + the generated half →
   `asana-api-reference.md`.
4. Re-stamp the "Last refreshed" date at the top to today (re-derive from the live clock).
5. If Asana changed something the header section asserts (enums, endpoints, team-share behaviour), re-verify
   it live on a throwaway object and update the header + any dependent code.

The header section (top) is hand-maintained (behaviours verified live); only the generated half is
mechanically refreshed. Keep the two-file split so a refresh never clobbers the estate notes.
