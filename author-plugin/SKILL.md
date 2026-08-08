---
name: author-plugin
description: Use when authoring or maintaining a Claude Code plugin (the directory bundle that ships skills + commands + agents + hooks + MCP servers + settings as one installable unit). Triggers include "create a Claude Code plugin", "scaffold a plugin", "set up plugin.json", "add a slash command to a plugin", "add a custom agent to a plugin", "wire an MCP server into a plugin", "use ${CLAUDE_PLUGIN_ROOT}", "publish a plugin to a marketplace", "convert these scripts into a plugin", "structure a plugin for distribution". NOT for authoring a single skill on its own (use author-skill); NOT for hook authoring (use author-hook). Covers plugin directory layout, plugin.json manifest, the .claude-plugin/marketplace.json marketplace manifest and /plugin install, component organisation (commands / agents / skills / hooks / .mcp.json / scripts), the ${CLAUDE_PLUGIN_ROOT} portable-path reference, plugin-vs-settings hooks.json format distinction, command frontmatter and namespacing, inline bash execution in commands, agent frontmatter, MCP integration and transport types. Localised consolidation of anthropics/claude-code/plugins/plugin-dev (plugin-structure + plugin-settings + command-development + agent-development + mcp-integration folded into one skill).
metadata:
  version: 1.2.0
---

# Author Plugin

> **Skill marker**: When applying this skill, begin your reply with `[skill: author-plugin]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A Claude Code plugin is a directory bundle that ships zero or more skills, slash commands, custom agents, hooks, MCP servers, and settings as one installable unit. The harness auto-discovers components from conventional subdirectories; the plugin author opts in to additional components by adding the right files in the right places.

**Core principle:** plugins are about packaging, not about authoring the components themselves. The skills go via `author-skill`; the hooks go via `author-hook`; this skill is about the wrapper that ships them.

## When to use

- Wrapping a set of related skills + commands + agents into one installable plugin.
- Adding a slash command, custom agent, or MCP server to an existing plugin.
- Publishing a plugin to a marketplace (anthropic-marketplace, internal registry, etc.).
- Converting an ad-hoc directory of vault skills into a distributable plugin.
- Wiring an MCP server's connection details into a plugin so consumers don't configure manually.

Do NOT use this skill for:

- Authoring a single SKILL.md (use `author-skill`).
- Authoring a hook (use `author-hook`).
- Modifying user-level `~/.claude/settings.json` (use `update-config`).

## Directory structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # Required; the plugin manifest
├── commands/                 # Slash commands (one .md per command)
├── agents/                   # Subagent definitions (one .md per agent)
├── skills/                   # Skills (one subdirectory per skill)
│   └── skill-name/
│       └── SKILL.md          # Required for each skill
├── hooks/
│   └── hooks.json            # Event handler configuration
├── .mcp.json                 # MCP server definitions
└── scripts/                  # Helper scripts the components call into
```

Critical rules:

1. **Manifest location:** `plugin.json` MUST be in `.claude-plugin/`. Putting it at the plugin root or in a subdirectory breaks discovery.
2. **Component locations:** `commands/`, `agents/`, `skills/`, `hooks/` MUST be at plugin root. Do NOT nest them inside `.claude-plugin/`.
3. **Optional components:** create directories ONLY for components the plugin actually ships. An empty `commands/` directory is noise.
4. **Naming:** kebab-case for all directory and file names.

## plugin.json manifest

### Minimum required

```json
{
  "name": "plugin-name"
}
```

The name follows the kebab-case rule, must be unique across installed plugins, no spaces, no special characters. The validation regex is `/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/`: it must start with a letter and end with a letter or number.

### Recommended metadata

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "Brief explanation of plugin purpose",
  "author": {
    "name": "Author Name",
    "email": "author@example.com",
    "url": "https://example.com"
  },
  "homepage": "https://docs.example.com",
  "repository": "https://github.com/owner/plugin-name",
  "license": "MIT",
  "keywords": ["testing", "automation", "ci-cd"]
}
```

Version uses semver (MAJOR.MINOR.PATCH); `docs-versioning` covers the bump policy if the plugin is consumed by pinned downstream projects. It defaults to `"0.1.0"` when absent, and accepts pre-release forms (`1.0.0-alpha.1`, `1.0.0-beta.2`, `1.0.0-rc.1`).

Several fields accept a second shape:

- `author` also accepts a single string: `"Jane Developer <jane@example.com> (https://janedeveloper.com)"`.
- `repository` also accepts an object: `{"type": "git", "url": "...", "directory": "packages/plugin-name"}`.
- `license` is an SPDX identifier and supports expressions such as `"(MIT OR Apache-2.0)"`.
- `description` displays in marketplace listings; 50 to 200 characters is the recommended range.

### Custom component paths

When components live somewhere other than the conventional directory:

```json
{
  "name": "plugin-name",
  "commands": "./custom-commands",
  "agents": ["./agents", "./specialised-agents"],
  "hooks": "./config/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

`hooks` and `mcpServers` each accept **either** a string path **or** an inline object. Inline suits a simple plugin (hooks under about 50 lines, a single MCP server under about 20); move to an external file beyond that or for multiple servers:

```json
{
  "name": "plugin-name",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write", "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh" }] }
    ]
  }
}
```

Defaults when the field is absent: `./hooks/hooks.json` and `./.mcp.json`.

Path rules:

- Must be relative to plugin root.
- Must start with `./`.
- No absolute paths, and **no `../`**.
- Forward slashes only, even on Windows (`".\\commands"` is invalid).
- Arrays for multiple locations.

**Important:** custom paths SUPPLEMENT the defaults; they do NOT replace them. Resolution order is default directories first (`./commands/`, `./agents/`, `./skills/`, `./hooks/hooks.json`, `./.mcp.json`), then the manifest's custom paths. Nothing overwrites anything: all discovered components register, and a **name conflict is an error**, not a silent duplicate.

## Component organisation

### Commands (slash commands)

Location: `commands/<name>.md`. One markdown file per command. Auto-discovered by the harness when the user types `/<name>`.

**The command name comes from the filename, not from frontmatter.** `commands/review.md` becomes `/review`. There is no `name:` field; writing one adds an inert key.

**Every frontmatter field is optional.** A command works with no frontmatter at all.

| Field | Purpose |
|---|---|
| `description` | One-line summary shown in `/help`. Defaults to the first line of the command prompt. Keep it under about 60 characters so it displays cleanly. |
| `allowed-tools` | Scoped tool allowlist for the command run. Supports per-tool scoping, and the scoping is finer than a bare prefix: `Bash(git:*)`, `Bash(git status:*)`, `Bash(git diff:*)`. **Defaults to inheriting the conversation's permissions**, not to all tools. `"*"` grants all tools and is not recommended. |
| `model` | Pin a specific model for the command (`sonnet` / `opus` / `haiku`). Defaults to the session model. |
| `argument-hint` | Autocomplete hint shown when the user types `/<name> `. |
| `disable-model-invocation` | If true, the command can only be invoked by the user typing it. Gates against the LLM programmatically calling it via the `SlashCommand` tool. |

`allowed-tools` accepts either a comma-separated string or an array. The array form is what Anthropic's own shipped plugins use:

```yaml
allowed-tools: ["Read", "Write", "Grep", "Glob", "Bash", "TodoWrite", "AskUserQuestion", "Skill", "Task"]
```

Example (note the absence of `name`):

```markdown
---
description: Run a code review on the current branch.
allowed-tools: Bash(git:*), Read, Grep, Glob
model: sonnet
argument-hint: <commit-range> [--quick]
---

# /review

The actual prompt the harness sends to Claude when the user types `/review $ARGUMENTS` goes here. Use `$ARGUMENTS` for the full argument string, `$1` / `$2` for positional arguments, and `@<path>` to inline a file's contents into the prompt.
```

Argument syntax: `$ARGUMENTS` (full string), `$1` / `$2` / ... (positional), `@<path>` (file inclusion, resolves relative to the project root).

**Inline bash execution.** A command body can run a shell command and inject its output into the prompt before Claude sees it, using the `` !`command` `` form. This is the fourth dynamic-content mechanism alongside `$ARGUMENTS`, positionals, and `@<path>`:

```markdown
Files changed: !`git diff --name-only`
Build result: !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/build.sh 2>&1 || echo "BUILD_FAILED"`
```

It composes with positional arguments and `${CLAUDE_PLUGIN_ROOT}`, and requires a matching `allowed-tools: Bash(...)` entry or the command cannot run it.

**Namespacing and scope.** Commands resolve from three locations, each labelled in `/help`:

| Location | `/help` label |
|---|---|
| `.claude/commands/` | `(project)` |
| `~/.claude/commands/` | `(user)` |
| `<plugin>/commands/` | `(plugin:<plugin-name>)` |

Subdirectories create namespaces: `commands/review/security.md` becomes `/security` labelled `(plugin:<plugin-name>:review)`. Namespace once a plugin ships 5 or more commands (15 or more for project commands), and avoid generic names that collide across plugins (`/test`, `/run`).

### Agents (subagent definitions)

Location: `agents/<name>.md`. One markdown file per agent. Becomes available via the `Agent` tool's `subagent_type` parameter.

Frontmatter fields:

| Field | Required? | Purpose |
|---|---|---|
| `name` | yes | Kebab-case agent identifier; what the master uses as `subagent_type`. Validation: 3 to 50 characters, lowercase letters / numbers / hyphens only, must start and end with an alphanumeric, no underscores. |
| `description` | yes | The trigger surface. Use one or more `<example>` blocks (see below); the master reads this to decide whether to dispatch the agent. |
| `model` | yes | `inherit` (recommended; uses the master's model), `sonnet`, `opus`, `haiku`. |
| `color` | yes | One of `blue`, `cyan`, `green`, `yellow`, `magenta`, `red`. Used by the harness UI to colour-tag agent output. Pick semantically (red for security review, green for build / test, etc.). |
| `tools` | no | Allowlist of tools the agent can use. **Format is an array**: `tools: ["Read", "Write", "Grep", "Bash"]`. Omit the field, or use `["*"]`, for full access. |

Agents namespace the same way commands do: `agent-name` in a flat plugin, `plugin:<subdir>:<agent-name>` once you use subdirectories.

Example with the canonical `<example>` block trigger pattern in the description:

```markdown
---
name: brand-voice-checker
description: |
  Validates draft content against brand voice guidelines and returns deviations with suggested fixes.

  <example>
  Context: drafting a marketing email; want to make sure tone matches.
  user: "Check this email against the brand voice."
  assistant: "Dispatching brand-voice-checker..."
  <commentary>
  Brand-voice review is the agent's specialty; master delegates rather than checking inline.
  </commentary>
  </example>
model: inherit
color: cyan
tools: Read, Grep, Glob, Bash
---

# Brand voice checker

The system prompt for the agent goes here. Define its scope, return format, constraints.
```

Cross-reference: `subagent-delegation` covers WHEN to dispatch sub-agents (parallel, sequential, with two-stage review, etc.); this skill covers the packaging.

### Skills

Location: `skills/<name>/SKILL.md`. One subdirectory per skill, with the SKILL.md inside. Same format as standalone vault skills.

The vault's `author-skill` covers WHAT goes in a SKILL.md; this skill covers WHERE the SKILL.md lives inside the plugin bundle. The bundled-resources structure (`scripts/`, `references/`, `assets/` per skill subdirectory) is documented in `author-skill`.

### Hooks

Location: `hooks/hooks.json`. Single file defining all the plugin's hook handlers.

The vault's `author-hook` covers hook authoring (event types, prompt-based vs command hooks, the `${CLAUDE_PLUGIN_ROOT}` reference, hook configuration formats).

Important format distinction:

- **Plugin hooks.json (this file):** wrapped in `{"description": "...", "hooks": {...}}`. The `description` field is optional; the `hooks` field is the required wrapper.
- **User settings.json:** events directly at the top level, no wrapper.

The two formats are NOT interchangeable. A plugin that ships its hooks.json directly into a user's settings.json will not work; the wrapper distinction matters.

### MCP servers

Location: `.mcp.json`. Standard MCP server configuration file.

Four server transports, each with its own auth pattern:

| Transport | Where the server runs | Auth pattern | Best for |
|---|---|---|---|
| `stdio` | Local subprocess the plugin spawns | Env vars in the launch command (read by the server process) | Self-contained CLIs, local tooling, anything the plugin ships in `scripts/`. |
| `sse` | Remote host (server-sent events) | OAuth handled by the harness; user signs in once | Hosted SaaS (Asana, Linear, Notion). The harness owns the token lifecycle. |
| `http` | Remote host (REST over HTTP) | Bearer token via `headers` field | Self-hosted services with a token-based API. |
| `ws` | Remote host (bidirectional) | Token in connection URL or headers | Real-time backends; rare in plugin authoring. |

The WebSocket type value is the literal string `"ws"`. Writing `"websocket"` produces an invalid `.mcp.json`.

stdio example (plugin-bundled subprocess):

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-server.js"]
    }
  }
}
```

SSE example (hosted service):

```json
{
  "mcpServers": {
    "asana": {
      "type": "sse",
      "url": "https://mcp.asana.com/sse"
    }
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` is the portable absolute path to the plugin's root directory. Use it for any file references that need to survive the plugin being installed in different locations on different machines.

**Passing configuration and credentials.** Every server entry accepts an `env` object, and its values expand `${VAR}` from the user's shell. `${CLAUDE_PROJECT_DIR}` also expands inside `args`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-server.js"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}",
        "DB_POOL_SIZE": "10"
      }
    }
  }
}
```

This is the credential-passing surface, so it follows `secrets-hygiene`: reference the variable, never inline the literal secret into a tracked `.mcp.json`.

**MCP tool naming convention.** The harness auto-prefixes tools served by a plugin's MCP server as `mcp__plugin_<plugin-name>_<server-name>__<tool-name>`. Note that the tool segment keeps the server's own prefix, so a plugin `asana` with server `asana` serving `asana_create_task` resolves to `mcp__plugin_asana_asana__asana_create_task`. Use this exact form in command frontmatter `allowed-tools` to pre-allow a specific MCP tool (avoids the per-call permission prompt). A wildcard (`["mcp__plugin_asana_asana__*"]`) works but name specific tools instead.

Servers connect lazily on first tool use, not eagerly at session start, so bundling an MCP server does not by itself add session-start cost.

`/mcp` lists all connected servers, including plugin-provided ones.

### Scripts

Location: `scripts/<name>.{sh,js,py}`. Helper scripts the components call into. Reference them via `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`.

Bash scripts in `scripts/` should follow `bash-defensive` (strict mode, traps, ShellCheck-clean).

## Per-project plugin settings

Plugins that need user-configurable behaviour (per-project credentials, feature flags, custom thresholds) read settings from `.claude/<plugin-name>.local.md` in the project root. The file uses YAML frontmatter for structured config and a markdown body for free-form notes.

Convention:

````markdown
---
api_endpoint: https://internal.example.com/v2
default_severity: warning
notify_on_failure: false
---

# Optional notes for the human reader

Free-form section. The plugin ignores this; the user uses it for documentation.
````

Plugin hooks read the frontmatter via the sed-based extraction idiom (avoids requiring `yq` as a runtime dep):

```bash
# Quick-exit if the settings file is not present.
SETTINGS_FILE="${CLAUDE_PROJECT_DIR}/.claude/${PLUGIN_NAME}.local.md"
[[ -f "$SETTINGS_FILE" ]] || exit 0

# Extract a single key from the YAML frontmatter.
API_ENDPOINT=$(sed -n '/^---$/,/^---$/p' "$SETTINGS_FILE" \
  | grep -E '^api_endpoint:' \
  | sed 's/^api_endpoint:[[:space:]]*//')
```

Two non-negotiables:

- **Gitignore.** `.claude/*.local.md` MUST be in the project's `.gitignore`. Per-project settings are per-user; they are not source-controlled. The `secrets-hygiene` skill enforces this for credential-adjacent settings; the same rule applies for any non-secret config the user wants to keep local.
- **Settings require restart.** Plugins read `.local.md` at hook firing time, but harness-level effects (env vars exported by SessionStart hooks, MCP server configs read from `.mcp.json`) load at session start only. After editing a `.local.md` that influences those, the user must restart the Claude Code session.

Cross-reference: `secrets-hygiene` for credentials in settings files; `update-config` for the user-level (`~/.claude/settings.json`) equivalent.

## ${CLAUDE_PLUGIN_ROOT} (portable paths)

Always reference plugin-bundled files via `${CLAUDE_PLUGIN_ROOT}/...` rather than absolute paths or relative-to-cwd paths. The variable expands to the plugin's installed root, regardless of where the user installed the plugin.

```bash
# Right
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh

# Wrong (cwd-dependent; breaks when called from another directory)
bash ./scripts/validate.sh

# Wrong (absolute; only works on the author's machine)
bash /Users/alice/Documents/my-plugin/scripts/validate.sh
```

Use it in:

- Hook commands (`hooks/hooks.json`).
- MCP server configurations (`.mcp.json` `args` field).
- Command and agent prompts that reference bundled assets.
- Skill content that references bundled scripts or references.

## Plugin marketplaces

A plugin marketplace is a registry of plugins that users browse and install. The standard marketplace is `anthropic-marketplace`; internal teams can run their own.

To make a plugin marketplace-installable:

1. Host the plugin in a public git repo.
2. Tag releases per `docs-versioning` (semver, CHANGELOG entry per release).
3. List the plugin in a marketplace manifest (format below).
4. Per-release: bump version in `plugin.json`, add CHANGELOG entry, tag the commit.

**The marketplace manifest.** A marketplace repo carries `.claude-plugin/marketplace.json` at its root. This is a different file from a plugin's own `.claude-plugin/plugin.json`, and one marketplace lists many plugins:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
  "name": "my-marketplace",
  "version": "1.0.0",
  "description": "Plugins for the platform team.",
  "owner": { "name": "Platform Team", "email": "platform@example.com" },
  "plugins": [
    {
      "name": "plugin-dev",
      "description": "Author and maintain Claude Code plugins.",
      "source": "./plugins/plugin-dev",
      "category": "development",
      "version": "1.2.0",
      "author": { "name": "Jane Developer", "email": "jane@example.com" }
    }
  ]
}
```

Per entry: `name`, `description`, `source` (a path relative to the marketplace repo), and `category` are the working set; `version` and `author` are optional. Categories in use upstream are `development`, `productivity`, `learning`, and `security`.

Users install with `/plugin install <plugin>@<marketplace-name>`, for example `/plugin install plugin-dev@claude-code-marketplace`.

**Testing before you publish:** `cc --plugin-dir /path/to/plugin` loads a plugin straight from disk, so you can exercise it without a marketplace at all.

The vault's `consumer-rollout` skill applies if the plugin has downstream consumers that pin specific versions.

## Cross-references

- `author-skill`: writing the SKILL.md content. This skill covers WHERE SKILL.mds live in a plugin bundle; author-skill covers WHAT goes in them.
- `author-hook`: writing hook handlers. This skill covers WHERE the hooks.json lives; author-hook covers WHAT events fire and how to write the handlers.
- `subagent-delegation`: when to dispatch sub-agents (the operational discipline). Plugin-shipped agents are still subject to that discipline.
- `update-config`: modifying user-level `.claude/settings.json` (different from plugin-bundled hooks).
- `bash-defensive`: bash scripts in `scripts/` should follow strict mode + traps + ShellCheck.
- `docs-versioning`: semver bump policy for plugins consumed by pinned downstreams.
- `consumer-rollout`: when shipping a plugin with downstream consumers (drop "required hooks" sections into consumer AGENTS.md).

## Common mistakes

- `plugin.json` placed at plugin root instead of `.claude-plugin/plugin.json`.
- Component directories nested inside `.claude-plugin/` instead of at plugin root.
- Plugin's `hooks/hooks.json` written in the user-settings format (no `{"hooks": {...}}` wrapper); fails silently.
- Hook commands using cwd-relative or absolute paths instead of `${CLAUDE_PLUGIN_ROOT}/...`.
- `.mcp.json` outside the plugin (it works for the author because their cwd happens to be the plugin root; breaks for installed users).
- Custom component paths assumed to REPLACE defaults; they actually SUPPLEMENT them, and a resulting name conflict is a hard error rather than a tolerated duplicate.
- Writing a `name:` field in command frontmatter; the command name comes from the filename and the field is inert.
- Assuming `allowed-tools` defaults to all tools. It inherits the conversation's permissions.
- Writing `"type": "websocket"` in `.mcp.json`; the value is `"ws"`.
- Writing agent `tools` as a comma-separated string instead of an array.
- Confusing `.claude-plugin/marketplace.json` (a marketplace listing many plugins) with `.claude-plugin/plugin.json` (one plugin's own manifest).
- Plugin name conflicting with another installed plugin (kebab-case unique-across-installs requirement violated).
- Scripts in `scripts/` written without strict-mode bash discipline (per `bash-defensive`).

## Red flags

- A plugin without `.claude-plugin/plugin.json`.
- A plugin's `hooks/hooks.json` missing the `{"hooks": {...}}` wrapper.
- A plugin path in any config that starts with `./` (cwd-dependent) or with an absolute path (machine-specific) instead of `${CLAUDE_PLUGIN_ROOT}/...`.
- A plugin that bundles a hook handler that lives in the user's `~/.claude/settings.json` (wrong file; that's what `update-config` is for).
- A plugin name with spaces, capitals, or special characters (kebab-case violation).
- A plugin that bundles a large MCP server whose tool definitions the user pays for on every session. Connection itself is lazy (first tool use, not session start), so the cost is the exposed tool surface rather than the connect; keep that surface small and justified.
- A command body calling `` !`command` `` without a matching `Bash(...)` entry in `allowed-tools`.
- Five or more commands in one plugin with no namespacing, or a generic command name (`/test`, `/run`) likely to collide across plugins.
- A plugin without a CHANGELOG when downstream consumers pin specific versions.

## Bottom line

Plugins are packaging. The components (skills, commands, agents, hooks, MCP servers) have their own authoring skills; this one covers the wrapper that ships them. Manifest in `.claude-plugin/`, components at plugin root, `${CLAUDE_PLUGIN_ROOT}` for all bundled paths.
