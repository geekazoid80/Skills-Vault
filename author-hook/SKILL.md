---
name: author-hook
description: Use when authoring or maintaining a Claude Code hook (event-driven automation that runs on PreToolUse, PostToolUse, Stop, SubagentStop, SessionStart, SessionEnd, UserPromptSubmit, PreCompact, or Notification events). Triggers include "create a hook", "add a PreToolUse / PostToolUse / Stop hook", "validate tool use", "block dangerous commands", "load context on session start", "automate this on every Y", "set up event-driven automation", "use ${CLAUDE_PLUGIN_ROOT}". Distinguishes prompt-based hooks (LLM-driven; recommended for context-aware decisions) from command hooks (bash-driven; for fast deterministic checks). Covers all 9 event types, the plugin-vs-settings hooks.json format distinction, the input / output JSON contracts (stdin / hookSpecificOutput), exit codes (0 success, 2 blocking error), the matcher field, the $CLAUDE_ENV_FILE persistence trick for SessionStart, and the hookify lightweight rule format. Localised consolidation of anthropics/claude-code/plugins/plugin-dev/skills/hook-development plus anthropics/claude-code/plugins/hookify/skills/writing-rules.
metadata:
  version: 1.2.0
---

# Author Hook

> **Skill marker**: When applying this skill, begin your reply with `[skill: author-hook]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Hooks are event-driven automation scripts that run in response to Claude Code events. They validate tool calls, enforce policies, add context, integrate external tools, and automate workflows. The right hook in the right place removes a class of repeated user instruction (the "from now on, when X happens, do Y" pattern that memory and skills cannot fulfil because the harness, not Claude, executes the action).

**Core principle:** prefer prompt-based hooks for context-aware decisions; command hooks for fast deterministic checks. Use the right format for the right scope (plugin vs settings).

## When to use

- The user repeatedly asks "from now on, when X happens, do Y" (a hook is the durable answer; memory and skills cannot enforce harness-side automation).
- A class of dangerous tool call needs blocking (`rm -rf /`, writes to system paths, edits to credentials files).
- Context needs loading on session start (project type, current sprint, on-call rotation, recent incidents).
- Tool results need a follow-up automation (every successful Edit triggers a typecheck; every failed Bash gets logged to an incident log).
- Stop / SubagentStop should be gated on completeness (tests run; build green; no TODOs left).

Do NOT use this skill for:

- Authoring a skill (use `author-skill`).
- Authoring the plugin wrapper (use `author-plugin`).
- Modifying user-level settings (use `update-config`).

## The two hook types

### Prompt-based hooks (recommended for context-aware decisions)

```json
{
  "type": "prompt",
  "prompt": "Evaluate if this tool use is appropriate given the project context. Check: system paths, credentials, path traversal, sensitive content. Return permissionDecision allow / deny / ask.",
  "timeout": 30
}
```

Supported events: `Stop`, `SubagentStop`, `UserPromptSubmit`, `PreToolUse`.

**Default timeout: 30 seconds.**

The prompt string interpolates the stdin payload through shell-style variables, which is how the hook actually sees the thing it is judging: `$TOOL_INPUT`, `$TOOL_RESULT`, `$USER_PROMPT`. Without one of these the prompt has no view of the tool call at all.

Strengths:

- Context-aware: the LLM reasoning sees the actual tool call AND the surrounding session state.
- Flexible: no bash scripting; the rule lives in natural language.
- Easier to maintain: change the prompt, not the regex.
- Better edge case handling: the LLM catches near-misses a regex would miss.

### Command hooks (for fast deterministic checks)

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh",
  "timeout": 60
}
```

**Default timeout: 60 seconds.**

Use for:

- Fast deterministic validations (regex match, file existence, env var present).
- File system operations (move tracking, log appends).
- External tool integrations (call out to a CLI, query a database).
- Performance-critical checks where LLM latency would compound (every PreToolUse).

## Hook configuration formats

### Plugin format (hooks/hooks.json inside a plugin)

```json
{
  "description": "Validation hooks for code quality",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate.sh"
          }
        ]
      }
    ]
  }
}
```

The `description` field is optional; the `hooks` field is the required wrapper containing the actual events.

### User settings format (~/.claude/settings.json)

```json
{
  "PreToolUse": [
    {
      "matcher": "Write",
      "hooks": [...]
    }
  ]
}
```

No wrapper; events directly at the top level.

**The two formats are NOT interchangeable.** A plugin hooks.json pasted into user settings will not work; the wrapper distinction matters. Cross-reference: `author-plugin` covers the plugin-side packaging; `update-config` covers the user-settings side.

## The 9 hook events

### PreToolUse

Runs before any tool call. Use to approve, deny, or modify the tool input.

Output (event-specific):

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": {"field": "modified_value"}
  },
  "systemMessage": "Explanation Claude sees"
}
```

`updatedInput` lets the hook rewrite the tool's parameters before the tool runs (e.g. add a `--safe` flag, redirect a file path).

### PostToolUse

Runs after a tool completes. Use to react to results, provide feedback, log.

Output behaviour:

- Exit 0: stdout is shown in the transcript.
- Exit 2: stderr is fed back to Claude as context.
- Other exit codes: non-blocking error.

### Stop

Runs when the main agent considers stopping (after the user's task appears done). Use to validate completeness:

```json
{
  "decision": "approve|block",
  "reason": "Tests pass and build succeeded",
  "systemMessage": "Additional context for Claude"
}
```

`block` keeps the conversation going; the `reason` tells Claude what's still missing.

### SubagentStop

Same as Stop but for sub-agents (after `Agent` tool returns). Use to ensure the sub-agent actually completed its scoped task before its return reaches master.

### UserPromptSubmit

Runs when the user submits a new prompt. Use to add context, validate prompt content, or block prompts that violate policy.

### SessionStart

Runs when a Claude Code session begins. Use to load project context and set environment.

Special capability: persist environment variables across the session via `$CLAUDE_ENV_FILE`:

```bash
echo "export PROJECT_TYPE=nodejs" >> "$CLAUDE_ENV_FILE"
echo "export ON_CALL=alice" >> "$CLAUDE_ENV_FILE"
```

Per `bash-defensive`, the script should follow strict mode and quote all variables.

### SessionEnd

Runs when a session ends. Use for cleanup, log archival, state preservation.

### PreCompact

Runs before context compaction. Use to add critical information that must survive the cut. Cross-reference: the global "pre-compact externalisation pass" rule from CLAUDE.md is the manual equivalent of this hook; PreCompact automates the pattern.

### Notification

Runs when Claude sends a notification. Use to react to notifications (forward to Slack, append to a log, trigger an external alert).

## Standard output format (all hooks)

```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "Message Claude sees"
}
```

- `continue`: false halts processing (default true).
- `suppressOutput`: true hides output from the transcript (default false).
- `systemMessage`: shown to Claude as context.

**Injecting context: `hookSpecificOutput.additionalContext`.** The same `hookSpecificOutput` envelope that carries `permissionDecision` for PreToolUse also carries a string that gets injected straight into Claude's context. `hookEventName` is required alongside it:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Project uses pnpm, not npm. Deploys run from main only."
  }
}
```

Confirmed on `SessionStart` and `PostToolUse`. This is how "load project context at session start" is actually implemented, and it is usually a better fit than the `$CLAUDE_ENV_FILE` route because the text lands in context directly rather than as an environment variable something else has to read.

## Standard input format (all hooks)

Hooks receive JSON via stdin with common fields:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask|allow",
  "hook_event_name": "PreToolUse"
}
```

Plus event-specific fields:

- `PreToolUse` / `PostToolUse`: `tool_name`, `tool_input`, `tool_result`.
- `UserPromptSubmit`: `user_prompt`.
- `Stop` / `SubagentStop`: `reason`.

Command hooks read these fields out of the stdin JSON. Prompt hooks reach them through the interpolation variables instead (`$TOOL_INPUT`, `$TOOL_RESULT`, `$USER_PROMPT`).

## Available environment variables

Command hooks have four harness-provided env vars available alongside stdin JSON:

| Variable | Set when | Purpose |
|---|---|---|
| `$CLAUDE_PROJECT_DIR` | Always | The project root (the user's working directory at session start). Anchor for any hook that operates on user files. |
| `$CLAUDE_PLUGIN_ROOT` | Always (plugin hooks) | The plugin's installed directory. Use for any path referencing files the plugin ships (`${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh`). |
| `$CLAUDE_ENV_FILE` | SessionStart only | Path to a writable env file. Lines appended here become exported environment variables for the rest of the session (see SessionStart event above). |
| `$CLAUDE_CODE_REMOTE` | When running in a remote context | Discriminates local Claude Code sessions from remote ones (cloud runners, CI). Use to gate hooks that should only fire locally. |

Prompt-based hooks see the same vars through their stdin envelope rather than as shell env.

## The matcher field

Hooks fire selectively via the `matcher` field. The matcher is a regex evaluated against the tool name (PreToolUse / PostToolUse) or the event payload (other events). Options:

- Tool name pattern: `"matcher": "Write"` (only when the Write tool is called).
- Multiple tools: `"matcher": "Write|Edit"` (regex alternation).
- Wildcard: `"matcher": "*"` (every event of this type).
- Regex pattern (MCP scope): `"matcher": "mcp__.*__delete.*"` (all MCP tools whose name ends with `delete<something>`; useful for "block destructive MCP calls" hooks).
- Regex pattern (plugin scope): `"matcher": "mcp__plugin_asana_.*"` (every MCP tool served by the asana plugin's MCP server; useful for plugin-scoped gating).
- Specific path or input: depends on event type; per-event matchers vary.

**Matchers are case-sensitive.** `"matcher": "write"` does NOT match the `Write` tool.

Without a `matcher`, the hook fires for every event of that type.

### Execution model

Two operational realities that bite first-time hook authors:

- **Parallel execution.** All matching hooks for a single event run in parallel with non-deterministic ordering and no inter-hook visibility. Hooks must be designed for independence; do NOT assume one hook's output is visible to another, and do NOT chain state across multiple hooks for the same event. If you need sequential phases, fold them into a single hook command that internally orders the steps.
- **Loaded at session start only.** Hooks are read from `hooks.json` (or the equivalent settings location) when the session starts. Editing `hooks.json` mid-session is a silent no-op; the user must restart the session. To verify which hooks are actually loaded in the current session, the user can run `/hooks` (the harness built-in).
- **Plugin hooks merge with the user's own.** A plugin's hooks do not replace anything in `~/.claude/settings.json`; both sets register and run in parallel for the same event.

**When a hook never fires, check loading before logic.** The failure modes are quiet by design:

- Invalid JSON in `hooks.json` fails the load outright.
- A missing script produces a warning, not an error.
- Syntax errors surface only in debug mode.

The diagnostic loop:

1. `claude --debug` logs hook registration, execution, the input and output JSON, and timing.
2. `/hooks` shows what actually loaded in this session.
3. Test a command hook standalone by feeding it a payload directly:

```bash
echo '{"tool_name": "Write", "tool_input": {"file_path": "/test"}}' \
  | bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh; echo "Exit code: $?"
```

### Conditionally-active hooks

Because hooks cannot be hot-swapped, the way to make one toggleable is a guard at the top of the script, not an edit to `hooks.json`. Two idioms:

```bash
# Flag file
FLAG_FILE="$CLAUDE_PROJECT_DIR/.enable-strict-validation"
[ -f "$FLAG_FILE" ] || exit 0
```

```bash
# Config key
ENABLED=$(jq -r '.strictMode // false' "$CLAUDE_PROJECT_DIR/.claude/plugin-config.json" 2>/dev/null)
[ "$ENABLED" = "true" ] || exit 0
```

Both exit 0 (success, no action) when disabled, so the hook stays registered and costs nothing. This is the standard answer to "how do I turn this hook off without restarting the session".

## Hookify rules (lightweight pattern rules)

Folded from `anthropics/claude-code/plugins/hookify/skills/writing-rules`. Hookify is a separate plugin that gives you a lightweight markdown-based rule format for hooks, without writing JSON-in-bash directly.

Rule file: `.claude/hookify.<rule-name>.local.md`. Two non-negotiables on naming and source control:

- **Prefix and suffix are required.** The filename MUST begin with `hookify.` and MUST end with `.local.md`. Bad examples: `.claude/warn-rm.md` (missing both), `.claude/hookify.warn-rm.md` (missing `.local`), `.claude/warn-rm.local.md` (missing `hookify.` prefix). Hookify discovers rules by exact pattern; mis-named files are silently ignored.
- **Gitignore.** `.claude/*.local.md` MUST be in the project's `.gitignore`. Hookify rules are per-user (different developers tune their own warnings); they are not source-controlled.

```markdown
---
name: warn-dangerous-rm
enabled: true
event: bash
pattern: rm\s+-rf
action: warn
---

`rm -rf` detected. Are you sure? Common safer alternatives: trash CLI, explicit path with confirmation, dry-run first.
```

Frontmatter fields:

- `name` (required): kebab-case, action-oriented (`warn-`, `prevent-`, `block-`, `require-`, `check-`).
- `enabled` (required): `true` / `false` (toggle without deleting).
- `event` (required): `bash`, `file`, `stop`, `prompt`, `all`.
- `action` (optional): `warn` (default; show message but allow), `block` (prevent operation or stop session).
- `pattern` (simple format): regex (Python syntax) matched against `command` (bash) or `new_text` (file).

What each `event` value actually covers, and which fields it exposes to `conditions`:

| `event` | Fires on | Available `field` values |
|---|---|---|
| `bash` | the Bash tool | `command` |
| `file` | Edit, Write **and** MultiEdit | `file_path`, `new_text`, `old_text`, `content` |
| `prompt` | user submits a prompt | `user_prompt` |
| `stop` | agent wants to stop | (no payload fields) |
| `all` | all events | as per the firing event |

**YAML escaping trap.** An unquoted pattern works as written; a quoted one needs doubled backslashes. `pattern: \s` and `pattern: "\\s"` are both correct, but `pattern: "\s"` silently fails to match. Prefer unquoted patterns.

Advanced format with multiple conditions:

```markdown
---
name: warn-env-file-secrets
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.env$
  - field: new_text
    operator: contains
    pattern: API_KEY
---

You are adding an API key to a .env file. Ensure this file is in .gitignore. Per `secrets-hygiene`, real credentials live in gitignored files only.
```

All conditions must match for the rule to trigger. Operators: `regex_match`, `contains`, `equals`, `not_contains`, `starts_with`, `ends_with`.

**Hookify rules reload dynamically.** This is the single biggest practical difference from `hooks.json`, which loads at session start only. A hookify rule is read on the next tool use, so you can write it, trigger it, refine it, and re-trigger it inside one session. Disabling is `enabled: false` (temporary) or deleting the file (permanent); neither needs a restart.

Use hookify when:

- The rule is a simple pattern match without LLM reasoning.
- You want to keep the rule next to the codebase rather than packaged in a plugin.
- You want a quick toggle (`enabled: false`) without touching the plugin.
- You are still iterating on the rule and do not want a session restart per edit.

Use full hooks.json when:

- The rule needs LLM reasoning (prompt-based hook).
- The hook is part of a distributable plugin.
- The rule needs to call into a multi-step bash script (use a command hook).

## Cross-references

- `author-plugin`: WHERE hooks.json lives in a plugin bundle, and the plugin-vs-settings format distinction.
- `author-skill`: skills cannot fulfil "from now on, when X happens, do Y" requests because the harness, not Claude, executes the action; hooks are the right answer.
- `update-config`: user-level settings.json (the non-plugin scope for hooks).
- `secrets-hygiene`: hooks that read or write credential-adjacent paths must follow the no-real-literals discipline.
- `bash-defensive`: command-hook bash scripts follow strict mode + traps + ShellCheck.
- `subagent-delegation`: SubagentStop hooks pair with the plan-execution loop's BLOCKED handling.
- `completion-gate`: Stop hooks pair with Layer 3's iron law (no completion claim without fresh evidence; the Stop hook IS the harness-enforced version of that rule).
- `plan-time-tooling`: chunk-zero settings audit decides which Bash commands need allowlisting; hooks are the harness-side enforcement, settings allowlist is the harness-side permission.

## Common mistakes

- Plugin hooks.json missing the `{"hooks": {...}}` wrapper (silently does nothing).
- Hook command using cwd-relative or absolute path instead of `${CLAUDE_PLUGIN_ROOT}/...`.
- Prompt-based hook firing on `PostToolUse` (not in the supported events; only Stop, SubagentStop, UserPromptSubmit, PreToolUse support prompt type).
- Stop hook returns `decision: block` without a `reason` field (Claude doesn't know what's missing; loops).
- SessionStart hook writing to a file other than `$CLAUDE_ENV_FILE` for env-var persistence (the env vars don't survive the session start).
- Using a hook to enforce a rule that should be a skill (skills load on triggers and inform; hooks fire on events and gate).
- Using a skill to enforce a rule that should be a hook (skills can miss; hooks cannot).
- Hookify rule with `action: block` on `event: stop` (blocks every stop attempt; the session never ends; user has to force-quit).

## Red flags

- The user asks "from now on, do X every time" and the response is to add memory or a skill (memory and skills do not fire harness-side; only a hook does).
- A hook command in `bash` that starts with `set -e` followed by `set +e` for the whole rest of the script.
- A prompt-based hook with no `timeout` field (default may be too short or too long).
- A PreToolUse hook returning `permissionDecision: deny` without an explanation in `systemMessage` (Claude doesn't learn).
- Hookify rule with very broad pattern (`event: all` + `pattern: .*`) and `action: block` (deadlocks the session).
- A hook that reads `tool_input` containing potential secrets and logs it without redaction.

## Bottom line

Prompt-based for context; command for deterministic. Plugin format wraps in `{"hooks": {...}}`; settings format does not. Stop / SubagentStop need `reason` when blocking. SessionStart persists via `$CLAUDE_ENV_FILE`. The matcher narrows; the wildcard broadens. Hookify is the lightweight markdown alternative for simple patterns.
