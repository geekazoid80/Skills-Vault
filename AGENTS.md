# Skills-Vault, operating guide

The operating SSOT for this repo. A public, generic Claude skills vault: each top-level
directory containing a `SKILL.md` is one skill, consumed by Claude Code and the Claude Desktop
app through the `~/.claude/skills/` symlink farm. `README.md` is the user-facing landing page;
this file is the guide for anyone, person or agent, operating on the vault. Where the two
overlap, this file is canonical for bootstrap and conventions.

## First pull (bootstrap)

**Clone alongside.** The vault stands alone: building its own farm needs no sibling repo. If you
also run a private or overlay vault, clone that too and run ITS overlay builder after this one
(see Related repos); this repo never needs to know an overlay exists.

```
git clone git@github.com:geekazoid80/Skills-Vault.git ~/Documents/Skills-Vault
cd ~/Documents/Skills-Vault && ./bootstrap.sh
```

**Prerequisites.** Bash and coreutils, nothing else. No runtime, no packages: the vault is
markdown and shell, and the builder only makes symlinks.

**Credentials.** None to clone, build, or read the vault. Publishing a change needs a GitHub
push credential for `geekazoid80/Skills-Vault`; read it from your own credential store at push
time (a Keychain entry, a `gh` login, an env var), never a value committed here.

**First run, and what working looks like.** `./bootstrap.sh` prints `base: linked N generic
skills into <farm>`. Then `ls ~/.claude/skills/` shows one symlink per skill, and
`find -L ~/.claude/skills -maxdepth 1 -type l` prints nothing (anything it prints is a broken
link). Claude Code watches the directory, so no restart is needed. A healthy exit is 0; the
builder refuses loudly rather than mis-building silently:

- exit 2, base vault not found at the resolved path;
- exit 3, zero skills ingested (a wrong or empty clone);
- exit 7, a `SKILL.md` frontmatter does not parse as YAML;
- exit 6, `bootstrap.sh` found the farm already carries overlay links from another vault and
  would strip them. Run that machine's overlay builder instead, or `SKILLS_FARM_RESET=1
  ./bootstrap.sh` to drop the overlay on purpose.

**Paths and overrides.** `build-farm-base.sh` resolves the vault as the directory holding the
script and the farm as `${SKILLS_FARM:-$HOME/.claude/skills}`; both move via `SKILLS_VAULT_BASE`
and `SKILLS_FARM`, so a clone in another location works once they are set (for example
`VAULT=~/code/Skills-Vault bash ~/code/Skills-Vault/bootstrap.sh`).

**Related repos (the graph this sits in).**

- Consumer: `~/.claude/skills/`, the symlink farm this vault builds. Not a repo, a generated
  directory; never edit it by hand, re-run the builder.
- Optional overlay: a private or overlay vault that composes on top. It runs its own overlay
  builder AFTER `bootstrap.sh`; that builder resets the farm, rebuilds this base, then re-adds
  its own layer. On a machine that carries an overlay, run the overlay builder, not
  `bootstrap.sh` directly; the brownfield guard (exit 6) enforces this.
- Upstreams: third-party skill sources folded into local skills, tracked in
  `merged-skills-registry/` with a `.sources/<skill>` provenance line each. Audited on a
  cadence; not cloned.

## What a skill is, and the conventions

- One top-level directory per skill, each holding a `SKILL.md`. `.sources/<name>` records the
  upstream (`<repo-url> <path-in-repo>`) for a third-party skill; a self-authored skill has none.
- **Frontmatter must parse as YAML.** The base builder runs a frontmatter gate and refuses the
  whole build (exit 7) on any `SKILL.md` whose frontmatter does not `yaml.safe_load`. Write the
  `description:` as a double-quoted scalar (escape inner `"`); the usual break is an unquoted
  description carrying a colon-space.
- **Every skill carries a skill-marker line** in its body, so a transcript shows the skill fired.
- **Voice:** British / Pacific English, no em dashes anywhere. This vault is public.
- Scripts: `add-skill.sh` adds a third-party skill and records its source, `update-skill.sh`
  refreshes one from its source, `list-skills.sh` lists installed skills. Re-run `bootstrap.sh`
  after adding, renaming, or removing a skill. `README.md` carries their detailed usage.

## More

`README.md` holds the user-facing quickstart, the repo layout, and the add / update / list
script usage. This file, `AGENTS.md`, is the operating SSOT and is canonical for the bootstrap
and the conventions above.
