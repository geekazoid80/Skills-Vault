# Graylog admin objects: exporting them as data, and rebuilding from the export

Reference for `graylog-log-investigation`. Measured against **Graylog 6.3 Open edition with Data Node** (Swagger-described REST API); re-check anything version-sensitive against the server's own API description before relying on it.

Why this matters: the objects an operator builds in the UI (pipelines and rules, event definitions and notifications, streams, index sets, inputs and their extractors, roles) live **only inside Graylog**. A restore or rebuild is not reproducible from the log data. Dump them as data on a schedule and the dump cannot drift from a hand-written recreate script nobody reran.

## Access basics

- Basic auth with the **access token as the user name and the literal string `token` as the password**. Any non-GET needs an `X-Requested-By` header. In zsh write `"${TOK}:token"` with braces (see `secrets-hygiene`).
- The server describes itself: `GET /api/api-docs` lists every resource (Swagger 1.2), and `GET /api/api-docs/<resource path>` lists its operations, HTTP methods and body type names. This is a read-only way to find the exact create and update endpoints **without applying anything**. **Percent-encode templated segments** (`%7BinputId%7D`): the raw braces return HTTP 500.
- List endpoints page with `per_page` and `page` and report `total`. Always ask for a large `per_page`, and fail if the items you collected differ from `total`.

## What to read (all GET)

| Object | Read from | Notes |
|---|---|---|
| Version, node | `/api/system` | needs `system:read` |
| Index sets | `/api/system/indices/index_sets` | a **permission-filtered list**, see below |
| Inputs | `/api/system/inputs`, then `/api/system/inputs/{id}/extractors` per input | extractors exist only on the input; easy to forget |
| Streams (rules embedded) | `/api/streams` | |
| Pipelines, rules, connections | `/api/system/pipelines/pipeline`, `/rule`, `/connections` | a pipeline names its rules by **title**, not id |
| Event definitions, notifications | `/api/events/definitions`, `/api/events/notifications` | paged |
| Roles | `/api/roles` (JSON). `/api/authz/roles` also JSON and carries role ids. `/api/authorization/roles` is the web app | |
| Users and token names | `/api/users`, `/api/users/{id}/tokens` | the token listing returns name and expiry, **never a value** |
| Saved searches and dashboards | `/api/views`, then `/api/views/search/{search_id}` | the query text lives in the search object |
| Grok, lookup tables, caches, adapters | `/api/system/grok`, `/api/system/lookup/...` | |
| Message-processor order | `/api/system/messageprocessors/config` | the Pipeline Processor must run after the Stream Rule Processor |
| Cluster configuration | `/api/system/cluster_config/{class}` | **fetch an allow-list only**: the list of classes includes ones holding key material (an encrypted CA keystore, a preflight encrypted secret). Never request those |
| Sidecar configurations | `/api/sidecar/configurations/{id}` | the template can embed credentials; scrub it |

## Prove the read is complete

- **The entity catalogue is an independent count.** `GET /api/system/catalog` lists the content-pack-addressable entities by type. Compare your per-type counts with it; a mismatch means a truncated page or a skipped object. Retry once (an object created between the reads is a race, not a defect).
- **The catalogue cannot count everything.** Index sets, roles, users, cluster configuration, processor order and extractors are not catalogue types. For those, use **referential checks**: every id one object holds for another must be in the export (streams name index sets, users name roles, the built-in `Admin` role and `admin` user must exist, processor order must be non-empty).
- **A permission-filtered list returns an EMPTY 200, not a 403.** An account without the grant sees zero index sets and the read "succeeds". The referential check is what catches it. Treat a surprising zero as a permission gap until a broader token reads the same.
- Where the catalogue **does** count a type, a dangling reference is usually stale data in Graylog (a pipeline deleted long ago and still listed in a stream's connection), so warn and record it rather than fail the run. Repost the connection with only valid ids to clean it up; the connections call replaces the whole list.
- **Strongest proof of all:** dump with the restricted account and with an admin token and compare the trees byte for byte, with a control showing a deliberate difference is seen.

## What never goes into a dump

Token values (only names and expiry), input TLS password fields, anything under a secret-named key (`password`, `secret`, `api_key`, `token`, `credential`, `community`, ...) as a string or number, PEM private-key blocks, bearer strings, URLs with embedded credentials, and credential lines inside templates. Redact in place so the rest of a rule or template survives, record where and why (never the value), and **prove it with planted fake secrets** that appear in the raw responses, plus a control that the same scan finds one when present. Build the fake secrets at run time from fragments if your environment blocks credential-shaped literals in files.

## Ids are regenerated: the reference graph

A rebuild creates new ids for every object, so each field that holds one must be remapped. Measured fields: stream to index set; pipeline connection to stream and pipelines; event definition to streams and to notifications; role permissions of the form `streams:read:<stream id>`; saved-view stream filters; the default-index-set setting. Per-user permission lists also embed ids but are **ownership grants Graylog adds when an object is created**, so do not replay them. The three built-in streams (default, events, system events) have fixed ids that do not change.

**Any tool keyed on a definition id breaks silently after a rebuild** (asking for an unknown event-definition id returns an empty result, not an error). Key such tools on the definition's **title** and resolve the id from the latest export, and treat an unresolvable title as "could not look", never as "no alerts".

## Rebuild order (dependencies first)

Cluster configuration basics, index sets, default index set, inputs, extractors (path carries the input id), streams then their rules then resume, grok and lookups, pipeline rules, pipelines, connections, processor order, event notifications, event definitions (created disabled: schedule them), saved views, roles, users and tokens. Verify the order mechanically: encode it with the measured dependency edges and assert each dependency precedes its dependant, with a control that a wrong order is caught. Create paths (from the API description): `POST /api/system/indices/index_sets`, `/api/system/inputs`, `/api/system/inputs/{id}/extractors` (and `.../extractors/order`), `/api/streams` (and `/{id}/rules`, `/{id}/resume`), `/api/system/pipelines/rule`, `/pipeline`, `/connections/to_stream`, `/api/events/notifications`, `/api/events/definitions` (and `/{id}/schedule`), `/api/views`, `/api/roles`, `/api/users` (and `/{id}/tokens/{name}`), `/api/system/messageprocessors/config` (PUT), `/api/system/cluster_config/{class}` (PUT).

## What a content pack can carry

Only the catalogue types: grok patterns, event definitions, streams, notifications, inputs, pipelines, pipeline rules, saved searches, dashboards, sidecar collectors and configurations, and lookups. Index sets, roles, users, cluster configuration and processor order need the API. Whether an input entity carries its extractors was not tested, so keep extractors on the API path until a drill shows otherwise.

## Credentials for an export account

- Make a **dedicated read-only role and service account**; never put an admin token on a host that only reads, and do not widen an account other tools depend on.
- **Token lifetime:** the default is 720 hours, which makes a daily job fail monthly. Mint with the `token_ttl` body field (an ISO duration such as `P365D`), and record the expiry and a rotation date. Rotate in place: mint the new token, swap it in, verify a run, then revoke the old one. A token is shown **once**, at creation, and the path segment is the user's 24-character hex id, not the username.
- **Permission spellings that worked** for a full read: `system:read`, `indexsets:read`, `inputs:read`, `streams:read`, `pipeline:read`, `pipeline_rule:read`, `pipeline_connection:read`, `eventdefinitions:read`, `eventnotifications:read`, `roles:read`, `users:read`, `users:list`, `users:tokenlist:*`, `view:read`, `lookuptables:read`, `clusterconfigentry:read`, `contentpack:read`, `catalog:list`, `sidecar_collectors:read`, `sidecars:read`, `sidecar_collector_configurations:read`. **Did not work:** `content_packs:read` and `catalog:read`. Find the rest by running the export with a "write what you can" mode and reading which sections 403, adding one candidate at a time.
- Prove read-only: with the account's token, a `PUT` or `DELETE` on a nonexistent stream id and a `POST /api/roles` should return 403, while an admin gets 404 on the same stream calls (it passed authorisation and found nothing).
- Roles are replaced whole by a `PUT`: send the full body and permission list.

## Other traps

- On Data Node builds the legacy retention fields (`retention_strategy`, `rotation_strategy`) can be accepted, echoed and **ignored** once data tiering is in use. Change and verify retention through `data_tiering`, and confirm a real rotation fires.
- The export itself must be **read-only by construction**: one HTTP method in the client, and a test asserting the server only ever saw GET, with a control that a deliberate POST is recorded.
- Make a run **all-or-nothing**: any unreadable section, short page or catalogue mismatch exits non-zero and promotes nothing, and the freshness marker advances only on a complete run. Write a new dated directory only when something changed, so the directory list is the change history.
