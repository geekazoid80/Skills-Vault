# Skills Vault

Personal Claude skills, version-controlled and synced across machines.
Each top-level folder containing a `SKILL.md` is a skill that Claude Code
and the Claude Desktop app pick up via `~/.claude/skills/`.

`~/.claude/skills/` is a symlink **farm**: a real directory of per-skill
symlinks, one per skill, pointing into this vault. Run `bootstrap.sh`
(which builds the base via `build-farm-base.sh`) after cloning, and
re-run it after adding, renaming, or removing a skill. Claude Code
watches the directory; no restart needed. This base builder is
standalone and overlay-agnostic: if you also keep a private or overlay
vault, compose it on top by running that vault's overlay builder after
this one.

## First pull (bootstrap)

**Clone it where you want it, then build the farm.** Nothing here writes outside `~/.claude/skills/`.

```
git clone git@github.com:geekazoid80/Skills-Vault.git ~/Documents/Skills-Vault
cd ~/Documents/Skills-Vault && ./bootstrap.sh
```

`bootstrap.sh` links every skill into `~/.claude/skills/` and prints the count. The full bootstrap
(prerequisites, credentials, exit codes, path overrides, the overlay model, the related-repo graph) and the
operating conventions live in [`AGENTS.md`](AGENTS.md), the operating SSOT.

## Layout

    Skills-Vault/
      <skill-name>/         one folder per skill, contains SKILL.md
      .sources/             upstream source per third-party skill
        <skill-name>        single line: <repo-url> <path-in-repo>
      add-skill.sh          add a skill (and record its source)
      update-skill.sh       refresh a third-party skill from its source
      list-skills.sh        show installed skills with their sources
      bootstrap.sh          link the vault into ~/.claude/skills
      build-farm-base.sh    build the generic base farm into ~/.claude/skills
      skills.conf           shared defaults for the scripts
      README.md
      .gitignore

## Bootstrap on a new machine

See [`AGENTS.md`](AGENTS.md) § First pull for the full bootstrap, including running from a
different location (`SKILLS_VAULT_BASE` / `SKILLS_FARM`), the builder exit codes, and the
overlay model. Verify with `ls -la ~/.claude/skills` (one symlink per skill) and, in a Claude
Code session, `/skills` or "what skills are available".

## Browse a repo's skills

    ./add-skill.sh vercel-labs/skills --list

## Add a third-party skill

    ./add-skill.sh <repo> <path-in-repo> [local-name]

`<repo>` accepts `owner/name` shorthand, full HTTPS, SSH, or any git URL.

Examples:

    ./add-skill.sh vercel-labs/skills skills/find-skills
    ./add-skill.sh vercel-labs/skills skills/frontend-design my-frontend
    ./add-skill.sh https://github.com/some/repo skills/foo

Then commit (or set AUTO_COMMIT=true in skills.conf):

    git add <name> .sources/<name> && git commit -m "add <name>" && git push

## Add a self-authored skill

    mkdir my-skill
    $EDITOR my-skill/SKILL.md   # YAML frontmatter with name + description
    git add my-skill && git commit -m "add my-skill" && git push

No `.sources/` entry needed. `update-skill.sh` ignores skills with no
recorded source.

## Update a third-party skill

    ./update-skill.sh find-skills

Shows a diff stat. With AUTO_COMMIT=true in skills.conf, it commits
(and pushes if AUTO_PUSH=true) automatically.

## List installed skills

    ./list-skills.sh

## Sync from another machine

    cd ~/Documents/Skills-Vault && git pull

## Configuration: skills.conf

    AUTO_COMMIT=false        # auto git add+commit after add/update
    AUTO_PUSH=false          # auto git push (only if AUTO_COMMIT=true)
    SHOW_DIFF=true           # show git diff --stat after update
    CONFIRM_OVERWRITE=true   # prompt before update-skill.sh overwrites
    VAULT_DIR=""             # empty = auto-detect from script location

## Source file format

`.sources/<skill-name>` is one line:

    <repo-url> <path-in-repo>

`<path-in-repo>` is the directory inside the upstream repo containing
`SKILL.md`. For Vercel's repo, skills nest under `skills/`, so the path
is e.g. `skills/find-skills`. For repos where the skill is at the root,
the path is just `.` or the skill name.

## Notes

- Don't commit secrets. Reference env vars in SKILL.md instead.
- For confidential or internal skills, keep the repo private or self-host
  the remote.
- Project-scoped skills belong in the project's own `.claude/skills/`,
  not here.
- Bundled Claude Code skills (`/simplify`, `/batch`, `/debug`, `/loop`,
  `/claude-api`) ship inside the binary, independent of this vault.
- Cowork-built skills are ephemeral; copy them into the vault before
  the session ends if you want to keep them.
