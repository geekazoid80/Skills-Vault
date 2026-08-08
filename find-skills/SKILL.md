---
name: find-skills
description: Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill.
metadata:
  version: 1.0.0
---

# Find Skills

This skill helps you discover and install skills from the open agent skills ecosystem.

> **Skill marker**: When applying this skill, begin your reply with `[skill: find-skills]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## When to Use This Skill

Use this skill when the user:

- Asks "how do I do X" where X might be a common task with an existing skill
- Says "find a skill for X" or "is there a skill for X"
- Asks "can you do X" where X is a specialized capability
- Expresses interest in extending agent capabilities
- Wants to search for tools, templates, or workflows
- Mentions they wish they had help with a specific domain (design, testing, deployment, etc.)

## What is the Skills CLI?

The Skills CLI (`npx skills`) is the package manager for the open agent skills ecosystem. Skills are modular packages that extend agent capabilities with specialized knowledge, workflows, and tools.

**Key commands:**

- `npx skills find [query]` - Search for skills interactively or by keyword
- `npx skills add <package>` - Install a skill from GitHub or other sources
- `npx skills check` - Check for skill updates
- `npx skills update` - Update all installed skills

**Browse skills at:** https://skills.sh/

## How to Help Users Find Skills

### Step 1: Understand What They Need

When a user asks for help with something, identify:

1. The domain (e.g., React, testing, design, deployment)
2. The specific task (e.g., writing tests, creating animations, reviewing PRs)
3. Whether this is a common enough task that a skill likely exists

### Step 2: Check the Leaderboard First

Before running a CLI search, check the [skills.sh leaderboard](https://skills.sh/) to see if a well-known skill already exists for the domain. The leaderboard ranks skills by total installs, surfacing the most popular and battle-tested options.

For example, top skills for web development include:
- `vercel-labs/agent-skills`: React, Next.js, web design (100K+ installs each)
- `anthropics/skills`: Frontend design, document processing (100K+ installs)

### Step 3: Search for Skills

If the leaderboard doesn't cover the user's need, run the find command:

```bash
npx skills find [query]
```

For example:

- User asks "how do I make my React app faster?" → `npx skills find react performance`
- User asks "can you help me with PR reviews?" → `npx skills find pr review`
- User asks "I need to create a changelog" → `npx skills find changelog`

### Step 4: Verify Quality Before Recommending

**Do not recommend a skill based solely on search results.** Always verify:

1. **Install count**: Prefer skills with 1K+ installs. Be cautious with anything under 100.
2. **Source reputation**: Official sources (`vercel-labs`, `anthropics`, `microsoft`) are more trustworthy than unknown authors.
3. **GitHub stars**: Check the source repository. A skill from a repo with <100 stars should be treated with scepticism.

### Step 5: Present Options to the User

When you find relevant skills, present them to the user with:

1. The skill name and what it does
2. The install count and source
3. The install command they can run
4. A link to learn more at skills.sh

Example response:

```
I found a skill that might help! The "react-best-practices" skill provides
React and Next.js performance optimization guidelines from Vercel Engineering.
(185K installs)

To install it:
npx skills add vercel-labs/agent-skills@react-best-practices

Learn more: https://skills.sh/vercel-labs/agent-skills/react-best-practices
```

### Step 6: Offer to Install

If the user wants to proceed, you can install the skill for them:

```bash
npx skills add <owner/repo@skill> -g -y
```

The `-g` flag installs globally (user-level) and `-y` skips confirmation prompts.

## Common Skill Categories

When searching, consider these common categories:

| Category        | Example Queries                          |
| --------------- | ---------------------------------------- |
| Web Development | react, nextjs, typescript, css, tailwind |
| Testing         | testing, jest, playwright, e2e           |
| DevOps          | deploy, docker, kubernetes, ci-cd        |
| Documentation   | docs, readme, changelog, api-docs        |
| Code Quality    | review, lint, refactor, best-practices   |
| Design          | ui, ux, design-system, accessibility     |
| Productivity    | workflow, automation, git                |

## Tips for Effective Searches

1. **Use specific keywords**: "react testing" is better than just "testing"
2. **Try alternative terms**: If "deploy" doesn't work, try "deployment" or "ci-cd"
3. **Check popular sources**: Many skills come from `vercel-labs/agent-skills` or `ComposioHQ/awesome-claude-skills`

## When No Skills Are Found

If no relevant skills exist:

1. Acknowledge that no existing skill was found
2. Offer to help with the task directly using your general capabilities
3. Suggest the user could create their own skill with `npx skills init` or via the local `author-skill` skill.

Example:

```
I searched for skills related to "xyz" but didn't find any matches.
I can still help you with this task directly! Would you like me to proceed?

If this is something you do often, you could create your own skill:
npx skills init my-xyz-skill
# or use the local `author-skill` skill for a guided interview.
```

## Fetching upstream content for review (without installing)

When you want to read a skill's body before deciding whether to adopt it (per the four patterns in `merged-skills-registry`: adopt as-is / customise / fold into existing / skip and watchlist), fetch the raw `SKILL.md` directly via the `gh` CLI. This is faster than cloning the whole repo and avoids the `add-skill.sh` install side effects.

```bash
# Browse a folder structure
gh api repos/<owner>/<repo>/contents/<path> \
  --jq '.[] | .name + " (" + .type + ")"'

# Pull one SKILL.md as raw markdown
gh api repos/<owner>/<repo>/contents/<path>/SKILL.md \
  -H "Accept: application/vnd.github.raw" > _tmp/<name>.md
```

Use `_tmp/` (gitignored in this vault) so review artefacts do not pollute the working tree.

Once reviewed:

- **Adopt as-is** -> run `add-skill.sh <repo> <path>` per the README; the third-party folder lands and `.sources/<name>` records the upstream.
- **Customise at adoption** -> write a local `<name>/SKILL.md` and `.sources/<name>` with the literal `local CLAUDE.md`; register the upstream in `merged-skills-registry`.
- **Fold into an existing local skill** -> edit the local target's body; register the upstream in `merged-skills-registry`; do not install the third-party folder.
- **Skip and watchlist** -> add a row to the `merged-skills-registry` watchlist with the upstream URL and the reason for deferral.

The `gh api` call requires `GH_TOKEN` to be set; the vault's `.envrc` (per `secrets-hygiene` and the multi-PAT direnv setup) handles this.
