# Task: Review CLAUDE.md and consolidate into Skills Vault

Context: I have a Skills Vault at `~/Documents/Skills-Vault` (symlinked to
`~/.claude/skills`) tracked at `git@github.com:geekazoid80/Skills-Vault.git`.
Helper scripts in the vault: `add-skill.sh`, `update-skill.sh`,
`fork-skill.sh`, `check-skill.sh`, `accept-snapshot.sh`, `list-skills.sh`,
`review-skills.sh`. Read the vault's `README.md` first to understand the
conventions, including the `.sources/` and `.snapshots/` patterns.

## Step 1: Inventory

Read these and summarise back to me before doing anything else:

1. `~/.claude/CLAUDE.md` (global rules)
2. Any `CLAUDE.md` found by:
   `find ~ -maxdepth 5 -name "CLAUDE.md" -not -path "*/node_modules/*" -not -path "*/.git/*"`
3. Any `.claude/skills/` directories found by:
   `find ~ -maxdepth 5 -type d -name ".claude" -not -path "*/node_modules/*"`
4. Each existing skill in `~/Documents/Skills-Vault/`, read every `SKILL.md`
   so you know what's already covered.

## Step 2: Classify

For every distinct rule, instruction, or procedure found in the CLAUDE.md
file(s), classify into one of:

- **Keep in CLAUDE.md**, genuinely always-on conventions (style, voice,
  language preferences, identity context). These should fire every session
  regardless of task.
- **Promote to new skill**, conditional procedure with a clear trigger
  context. Should only load when relevant.
- **Merge into existing skill**, overlaps with something already in the
  vault. Name the target skill.
- **Archive**, outdated, superseded, or no longer relevant.

Flag anything ambiguous as a question for me, don't guess.

## Step 3: Propose, don't execute

Output a plan as a markdown table:

| Rule (short summary) | Source location | Classification | Target | Notes |

Stop after the plan. Wait for me to approve before:

- editing `~/.claude/CLAUDE.md`
- creating new skills in the vault
- modifying existing skills
- committing or pushing anything

## Constraints

- British/Pacific English; no em dashes; my voice rules from CLAUDE.md
  apply to anything you write back.
- For new skills, follow the YAML frontmatter convention used by existing
  vault skills (read one to confirm format).
- New skills authored from CLAUDE.md content should record source as
  `local CLAUDE.md` in `.sources/<name>` (single line, no repo URL, the
  update-skill.sh script will refuse to update them, which is correct since
  there's no upstream).
- Don't touch superpowers-managed skills (anything in
  `~/.claude/plugins/marketplaces/`).
- Use the `superpowers/brainstorming` skill if it auto-triggers, I want
  to interrogate ambiguous classifications before they harden.

## Output format

End your first response with the classification table and a numbered list
of questions you want me to answer before proceeding to step 4
(implementation).
