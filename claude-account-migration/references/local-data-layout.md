# Local data layout for a Claude account migration

Learnt on the Claude desktop app 4.4212.0, macOS (Darwin 25.6.0), on 2026-11-10 by reading the app's own files and log. The layout is not a documented interface and may change between versions: re-verify with the checks at the end before trusting a path or key. Everything here is read-only except the copies you make yourself. No credential is needed for any of it.

Paths are under `~/Library/Application Support/Claude/` ("the app folder") unless stated. The log is `~/Library/Logs/Claude/main.log`.

## Account and organisation folders

Two stores are keyed by account then organisation:

```
claude-code-sessions/<account-uuid>/<org-uuid>/        Claude Code desktop sessions
local-agent-mode-sessions/<account-uuid>/<org-uuid>/   Cowork sessions
```

The folder names are UUIDs, not emails. A signed-in account can have more than one organisation folder (a personal one and a team one, for example). Find the right one with a **marker**: sign in as the target account, start a session with a unique title, then:

```bash
cd "$HOME/Library/Application Support/Claude/claude-code-sessions"
grep -l "unique marker title" */*/local_*.json
```

The path that matches is the target account and organisation. A folder is created, holding only a `scheduled-tasks.json`, the first time an account signs in.

## Claude Code desktop sessions

- **Transcripts** are `~/.claude/projects/<working folder with / replaced by ->/<cliSessionId>.jsonl`. They are plain files, shared by every account on the Mac, and are not touched by a migration.
- **Sidebar index** is one file per session: `local_<sessionId>.json`. Useful keys: `sessionId`, `cliSessionId` (names the transcript), `cwd`, `originCwd`, `createdAt` and `lastActivityAt` (milliseconds), `model`, `isArchived`, `title`, `titleSource`, `permissionMode`, `enabledMcpTools`, `remoteMcpServersConfig`, and `scheduledTaskId` (set only on sessions started by a scheduled task).
- Sessions with `scheduledTaskId` are listed under Scheduled, not in the main sidebar. A pilot copy of one of those looks like "the copy did not work".
- The app reads a folder when an account or organisation initialises, not live. The log shows it: `Loaded N persisted sessions from <folder> (M archived deferred)`. Archived sessions load after the active ones.
- A running app holds its sessions in memory and re-saves ones it has touched, which can write removed files back.
- Scale seen: about 370 KB per index file, 724 files, about 266 MB in total.
- The first reply in a copied session shows a notice that earlier thinking from another organisation cannot be reused; the session is intact and re-reads itself.

## Scheduled tasks

- Prompts live once, shared by all accounts: `~/.claude/scheduled-tasks/<taskId>/SKILL.md` (plus any helper scripts in that folder).
- The registry that says what runs is per account: `claude-code-sessions/<account>/<org>/scheduled-tasks.json`, shape `{"scheduledTasks": [...], "recordedSkips": {...}, ...}`. An entry carries `id`, `cronExpression` (absent on one-off tasks), `enabled`, `filePath`, `createdAt`, `lastRunAt`, `cwd`, `approvedPermissions` (list of `{toolName, ruleContent}`; can run to hundreds of rules), and `notifySessionId`.
- Copy recurring entries verbatim to carry the approved-tool list. The app adds its own start-time jitter, so do not add any.
- The create tool refuses a task ID whose folder already exists, so recreating through it does not work for migrated tasks.
- Only the signed-in account runs its tasks. Deleting a task through the old account's UI may delete the shared prompt folder; edit the registry file instead.

## Cowork sessions

Per session: `local_<id>.json` plus a `local_<id>/` folder holding `.audit-key`, `.claude/`, `audit.jsonl`, `outputs/`, `uploads/`, `uploads-tmp/`, and a few symlinks (copy with symlinks preserved).

- The JSON stores absolute paths that include the old account and organisation, for example the outputs folder. In the copy, replace `<old-account>/<old-org>` with `<new-account>/<new-org>` and check the result still parses.
- It also stores `accountName`, `emailAddress`, `memoryEnabled` and a long `systemPrompt` that includes the old identity and memory. Review before resuming a copy under the work account.
- Sizes vary from under 1 MB to about 16 MB. Verify a copy by comparing file counts per session folder and the rewritten JSON byte for byte.

## Log events that give login state

```
[account] Login-state transition (loggedOut: false → true, uuid: A → <none>)     logout
[account] Login-state transition (loggedOut: true → false, uuid: X → Y)          login
[LocalSessionManager] Initialization succeeded <em dash> accountId=A, orgId=O    account and org active
```

The real initialisation line carries an em dash where `<em dash>` stands; match it with a regex `.` rather than typing the character. The log text is the app's own, so it keeps the vendor's spelling. Replay the lines in order to learn who is signed in. The last initialisation line alone is wrong after a logout. The app can log itself back in after a logout.

## Processes

The app's main program is `/Applications/Claude.app/Contents/MacOS/Claude`. Other processes share the `Claude.app/Contents` path: renderer, plugin and GPU helpers, `chrome_crashpad_handler`, `Helpers/disclaimer`, and `Helpers/chrome-native-host` (kept alive by the Chrome extension). The last two outlive a quit, so a count of everything matching the path never reaches zero. Test only the main program:

```bash
ps -axo comm= | grep -c '^/Applications/Claude.app/Contents/MacOS/Claude$'   # 0 once quit
```

## The data export (claude.ai)

Settings > Privacy > Export data produces an email link to a **manifest** JSON: `instructions`, `created_at`, `total_files`, and `data_files[]` of `{batch_index, export_url, category, part, filename}`. Each `export_url` expires after 24 hours and may stop working after one use; download each in a browser. Categories seen and what each zip holds:

| Zip | Contents |
|---|---|
| `conversations-000.zip` | `conversations.json`: a list of chats `{uuid, name, summary, created_at, updated_at, account, chat_messages[]}`; a message is `{uuid, text, content[{type, text}], sender, created_at, attachments[{file_name, extracted_content}], files[{file_name}], parent_message_uuid}` |
| `projects-000.zip` | `projects/<uuid>.json`: `{uuid, name, description, is_private, is_starter_project, prompt_template, creator, docs[{filename, content}]}` |
| `memories-000.zip` | `memories/<account-uuid>.json`: `conversations_memory` (text), `project_memories` (id to text), `memory_files[{path, content, updated_at}]` |
| `claude_code_cloud-000.zip` | `routines.json` (name, prompt, enabled, schedule) and `routine_runs.json`; no web-session list |
| `light_metadata`, `design_chats`, `frames` | users and login history; design chats; artifacts |

Original uploaded files are not included, only extracted text. A single conversations file can be tens of megabytes; read it from the zip without extracting.

## Web interface facts that mattered

- Memory import: Settings > Your Claude > Memory > Import memory from other AI providers. Paste, "Add to memory"; it completes in seconds. Manage lists entries (Profile, Topics, Areas); the "Tell Claude what to change" box edits them.
- Project knowledge ceiling is roughly 5 MB of text. A project already over it shows "Project knowledge at capacity" and refuses more ("exceeds maximum"). New projects default to Private; an organisation-wide option sits beside it.
- Removing a project file: the confirm dialog names the file. Read it. The hidden Remove button of a neighbouring card is easy to target by reference.
- A browser upload tool may cap each call at 10 MB.
- Calendar import: Google Calendar > Settings > Import & export accepts an `.ics` with `RRULE` and `VALARM`; it reports "Imported N out of N events".
- The routine API can list, update and run a cloud routine but has no delete; pause with `enabled: false` and delete in the web UI.

## Dead ends, so nobody walks them again

- Fetching export links with curl (links are single use and need a browser session).
- `pgrep -f "Claude.app/Contents"` as an "app is quit" test.
- Reading only the last "Initialization succeeded" log line as the active account.
- Testing a safety guard by running the real `--apply`.
- Re-reading chat markdown in text mode when re-bundling: newline translation changes every bundle.
- Pilot-copying a scheduled-run session to test the sidebar.
- Recreating migrated scheduled tasks through the create tool.

## Re-verify before relying on this

```bash
ls "$HOME/Library/Application Support/Claude/claude-code-sessions"/*/*/ | head
python3 -c 'import json,sys;print(list(json.load(open(sys.argv[1])).keys()))' \
  "$HOME/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/scheduled-tasks.json"
grep -E "Login-state transition|Initialization succeeded" ~/Library/Logs/Claude/main.log | tail -3
```

If a key or log line differs from this file, update this file in the same change.
