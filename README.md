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

**Prerequisites.** Bash and coreutils. No runtime, no packages, no credentials: this vault is markdown and
shell only, and the builder just makes symlinks.

**What working looks like.** `bootstrap.sh` prints the count it linked, and `ls ~/.claude/skills/` shows one
symlink per skill, each resolving into this clone. `find -L ~/.claude/skills -maxdepth 1 -type l` should
print nothing; anything it prints is a broken link. Claude Code watches the directory, so no restart is
needed.

**Paths matter.** `build-farm-base.sh` resolves the vault as the directory holding the script, and the farm
as `${SKILLS_FARM:-$HOME/.claude/skills}`. Both are overridable by environment variable
(`SKILLS_VAULT_BASE`, `SKILLS_FARM`), so a clone elsewhere is fine as long as you set them.

**If you also keep an overlay vault.** This base builder is deliberately standalone and overlay-agnostic.
Run this one first, then your overlay vault's own builder on top; the overlay owns the composition and the
verification of its own skills. Nothing in this repo needs to know that an overlay exists.

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

    git clone git@github.com:geekazoid80/Skills-Vault.git ~/Documents/Skills-Vault
    bash ~/Documents/Skills-Vault/bootstrap.sh

If you prefer a different location:

    VAULT=~/code/Skills-Vault bash ~/code/Skills-Vault/bootstrap.sh

Verify with `ls -la ~/.claude/skills` (should show one symlink per
skill) and, in a Claude Code session, `/skills` or "what skills are
available".

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
