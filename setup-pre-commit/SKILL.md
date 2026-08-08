---
name: setup-pre-commit
description: "Use when adding or hardening git pre-commit hooks on a repository so that staged-file format / lint and full-repo typecheck / test gate every commit. Triggers include \"set up pre-commit\", \"add commit hooks\", \"gate commits with formatting and tests\", \"husky\", \"lint-staged\", \"pre-commit framework\", \"format and lint before commit\", \"set up pre-commit-config.yaml\", \"add prettier hook\", \"add ruff hook\", \"add ansible-lint hook\", \"wire shellcheck into pre-commit\", \"stop bad commits landing\". Stack-neutral: detects JS/TS, Python, Ansible, shell, or markdown-only repos and lays down the appropriate recipe (Husky + lint-staged for JS/TS; the Yelp `pre-commit` framework for everything else). NOT for Claude Code session hooks (see `author-hook`, which covers `.claude/settings.json` hook events; entirely different concept despite the shared word). Localised consolidation lifted from `mattpocock/skills/misc/setup-pre-commit` (JS/TS recipe) and broadened with Python / Ansible / shell / markdown recipes authored from each tool's public docs."
metadata:
  version: 1.0.0
---

# Setup Pre-Commit

> **Skill marker**: When applying this skill, begin your reply with `[skill: setup-pre-commit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A pre-commit hook is a git client-side hook that runs before each commit lands. Two payloads matter:

1. **Staged-file step** (fast): format / lint only the files actually about to be committed. Cheap; runs in seconds; catches formatting drift and trivial lint failures before they hit a PR.
2. **Full-repo step** (slower but cheaper than CI): typecheck and test the whole project. Catches "this commit broke an unrelated file" before push.

The hook lives in the repo, not the developer's home directory, so the rules ship with the code. The mechanism varies by stack (Husky for JS/TS, the Yelp `pre-commit` framework for everything else), but the shape is the same.

**Distinct from Claude Code session hooks.** Despite the shared word, `.claude/settings.json` hooks fire on session events (Stop, PreToolUse, etc.) and are a Claude Code concept. Git pre-commit hooks fire on `git commit` and are git-native. Use `author-hook` for the former; use this skill for the latter.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the repo's stack conventions, existing tooling, CI parity expectations, and any prior hook-related decisions. Only ask the user for information not already covered or specific to this setup.

Before laying down hooks, understand:

1. **Stack detection**
   - Which lockfile / manifest is present at the repo root? (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `pyproject.toml`, `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `uv.lock`, `ansible.cfg`, `playbooks/`, mostly `.sh`, mostly `.md`).
   - Multi-language repo (e.g. Python backend + JS frontend)? Each stack gets its own recipe; the hook chains them.
   - Monorepo with per-package tooling, or single-package?

2. **Existing tooling**
   - Formatter in place (Prettier, ruff, black, shfmt, prettier-md, markdownlint)?
   - Linter in place (eslint, ruff, flake8, ansible-lint, shellcheck)?
   - Typechecker (tsc, mypy, pyright)?
   - Test runner (jest, vitest, pytest, bats, molecule)?
   - Anything already wired into CI that the hook should mirror?

3. **Constraints**
   - CI parity requirement (the hook should run a subset of what CI runs; not a superset).
   - Performance ceiling (the user's expectation for "how long is too long for a commit"; default ~10s for staged-file + ~30s for full-repo).
   - Bypass policy (is `--no-verify` allowed, and if so, when? Default: never; raise to the user if they push back).

---

## When to use

- Adding pre-commit hooks to a repo that has none.
- Adding a missing stack's recipe to a multi-language repo that already has hooks for one stack.
- Hardening an existing hook config (adding missing tools; moving from "warn" to "error" severity; bringing CI parity into the hook).
- Migrating from one hook framework to another (rare; usually only when moving JS/TS repos from Husky v8 to v9, or consolidating multi-stack repos onto the `pre-commit` framework).

Do NOT use this skill for:

- Claude Code session hooks (`author-hook` covers `.claude/settings.json` hook events; different concept).
- Server-side git hooks (`pre-receive`, `update`); the framework discussed here is client-side only.
- Repo-wide CI configuration (different surface; the hook is a fast subset of CI, not a substitute for it).

## The shape every recipe shares

Five steps, regardless of stack:

1. **Staged-file step.** Format only the files about to be committed. JS/TS uses `lint-staged`; everything else uses `pre-commit` framework hooks that natively operate on staged files.
2. **Full-repo step.** Run typecheck + test on the whole repo. Slower; still well under CI time because no fresh checkout / install.
3. **Idempotent install.** When the user re-runs the setup (or another contributor clones the repo and the hooks need re-installing), the install does the right thing: skips files that already exist, refuses to overwrite custom config without confirmation, exits cleanly when re-run.
4. **Verify step.** After installation, smoke-test the hook locally: stage a known-good file and run the hook by hand (e.g. `npx lint-staged` or `pre-commit run --all-files`). Confirms the install actually works before the first commit goes through it.
5. **Commit step.** Make the setup commit itself go through the new hook. Live fire confirms the hook is wired correctly; a green commit is the strongest signal everything works.

## Stack detection

| Detected artefact | Recipe |
|---|---|
| `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, or `package.json` with no other manifest | JS/TS (Husky + lint-staged) |
| `pyproject.toml`, `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `uv.lock`, or `setup.py` | Python (`pre-commit` framework) |
| `ansible.cfg`, `playbooks/`, `roles/`, or `requirements.yml` with Ansible collections | Ansible (`pre-commit` framework) |
| `.sh` / `.bash` files predominant; no other manifest; or explicit user request for shell-only | Shell (`pre-commit` framework) |
| `.md` files predominant; no code; docs-vault shape (like this Skills-Vault) | Markdown-only (`pre-commit` framework) |

Multi-stack repos: detect each present stack and lay down its recipe; the `pre-commit` framework chains them in a single `.pre-commit-config.yaml`. For repos that mix JS/TS with anything else, either use the `pre-commit` framework for everything (drop Husky entirely) or run Husky for the JS/TS layer with `pre-commit run` invoked from inside the Husky hook. Default: consolidate onto the `pre-commit` framework when more than one stack is present.

## Recipe: Ansible

For repos with `ansible.cfg`, `playbooks/`, `roles/`, or `requirements.yml`.

### Install

```bash
# Install the pre-commit framework itself (one-off per developer)
pip install --user pre-commit

# Add the project-level config
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v24.9.0
    hooks:
      - id: ansible-lint
        args: [--profile=production]
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.35.1
    hooks:
      - id: yamllint
        args: [-c=.yamllint]
EOF

# Generate a sensible .yamllint
cat > .yamllint <<'EOF'
extends: default
rules:
  line-length: disable
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no']
  comments:
    min-spaces-from-content: 1
EOF

# Install the git hook
pre-commit install
```

### Adapt

- `--profile=basic` for legacy playbooks not yet ansible-lint-clean; `--profile=production` for new / clean repos.
- Skip `vendor/`, `molecule/`, `collections/` via `exclude:` patterns under each hook.
- For repos that also run `ansible-test sanity`, add a `repo: local` hook that invokes it on the full repo (`pre-commit run --hook-stage=manual` keeps it out of every commit; runs on demand or in CI parity).

### Per-tool docs

- ansible-lint: `https://ansible.readthedocs.io/projects/lint/`
- yamllint: `https://yamllint.readthedocs.io/`
- pre-commit framework: `https://pre-commit.com/`

## Recipe: JS/TS

For repos with a `package.json` and one of the JS/TS lockfiles. Lifted from `mattpocock/skills/misc/setup-pre-commit` and voice-cleaned.

### Detect package manager

Check for `package-lock.json` (npm), `pnpm-lock.yaml` (pnpm), `yarn.lock` (yarn), `bun.lockb` (bun). Use whichever is present. Default to npm if unclear. Replace `npm` with the detected manager in the snippets below.

### Install

```bash
# Install as devDependencies
npm install --save-dev husky lint-staged prettier

# Initialise Husky (creates .husky/ and adds prepare: "husky" to package.json)
npx husky init
```

### Write `.husky/pre-commit`

Husky v9+ does not need a shebang. The file content:

```
npx lint-staged
npm run typecheck
npm run test
```

If the repo has no `typecheck` or `test` script in `package.json`, omit those lines and tell the user that the hook will be format-only until they add a typecheck and test setup.

### Write `.lintstagedrc`

```json
{
  "*": "prettier --ignore-unknown --write"
}
```

For repos with eslint installed, add the eslint command for `.js,.jsx,.ts,.tsx`:

```json
{
  "*": "prettier --ignore-unknown --write",
  "*.{js,jsx,ts,tsx}": "eslint --fix"
}
```

### Write `.prettierrc` (if missing)

Only create if no Prettier config exists (check for `.prettierrc`, `.prettierrc.json`, `prettier.config.js`, or a `prettier` key in `package.json`). Defaults:

```json
{
  "useTabs": false,
  "tabWidth": 2,
  "printWidth": 80,
  "singleQuote": false,
  "trailingComma": "es5",
  "semi": true,
  "arrowParens": "always"
}
```

### Verify

- `.husky/pre-commit` exists and is executable.
- `.lintstagedrc` exists.
- `prepare` script in `package.json` is `"husky"`.
- Prettier config exists.
- `npx lint-staged` runs cleanly against current staged files.

### Commit

Stage all changed / created files and commit with: `chore: add pre-commit hooks (husky + lint-staged + prettier)`. The setup commit runs through the new hook; a green commit is the smoke test.

### Per-tool docs

- Husky: `https://typicode.github.io/husky/`
- lint-staged: `https://github.com/lint-staged/lint-staged`
- Prettier: `https://prettier.io/docs/en/`

## Recipe: Markdown-only

For docs vaults and other repos where `.md` predominates and there is no other code surface (this Skills-Vault is the prototypical example).

### Install

```bash
pip install --user pre-commit

cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.42.0
    hooks:
      - id: markdownlint
        args: [--config, .markdownlint.json]
EOF

# Reasonable rule set for prose-heavy markdown
cat > .markdownlint.json <<'EOF'
{
  "MD013": false,
  "MD033": false,
  "MD034": false,
  "MD041": false
}
EOF

pre-commit install
```

### Adapt

- `MD013` disabled because the line-length rule fights prose.
- `MD033` disabled to allow inline HTML (some markdown vaults use `<details>` / `<summary>`).
- `MD034` disabled to allow bare URLs (citation-heavy docs use them).
- `MD041` disabled because a vault's first line is often frontmatter, not an H1.

Add other rule overrides as the vault matures and individual rules get in the way; document each disable next to the rule with a one-line WHY.

### Per-tool docs

- markdownlint: `https://github.com/DavidAnson/markdownlint`
- markdownlint-cli: `https://github.com/igorshubovych/markdownlint-cli`

## Recipe: Python

For repos with `pyproject.toml`, `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `uv.lock`, or `setup.py`.

### Install

```bash
pip install --user pre-commit

cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.2
    hooks:
      - id: mypy
        additional_dependencies: []  # add typed deps here as project grows
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest
        language: system
        pass_filenames: false
        stages: [pre-commit]
EOF

pre-commit install
```

### Adapt

- ruff replaces black, isort, and flake8 in one tool; the format hook covers what black did.
- mypy needs `additional_dependencies` populated with any typed third-party stubs the project uses (e.g. `types-requests`, `pydantic`); otherwise mypy passes on missing-stub paths and misses real bugs.
- pytest as a `local` hook because it needs the project's venv (not a sandboxed one); `pass_filenames: false` so pytest selects its own tests rather than running only on staged files (the full-repo discipline).
- Venv-aware invocation: if the project uses `uv`, replace `entry: pytest` with `entry: uv run pytest`; for poetry, `entry: poetry run pytest`.

### Per-tool docs

- ruff: `https://docs.astral.sh/ruff/`
- mypy: `https://mypy.readthedocs.io/`
- pytest: `https://docs.pytest.org/`
- pre-commit framework: `https://pre-commit.com/`

## Recipe: Shell

For repos where `.sh` / `.bash` predominate, or as the shell-layer of a multi-stack repo.

### Install

```bash
pip install --user pre-commit

cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        args: [--severity=warning]
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.10.0-1
    hooks:
      - id: shfmt
        args: [-i, "2", -ci, -bn, -w]
EOF

pre-commit install
```

### Adapt

- `--severity=warning` gates on warning-or-above (matches CI defaults); raise to `--severity=style` if the project wants the strictest pass.
- `shfmt` args set: 2-space indent, switch-case indentation, binary operators on next line, write changes in place. Adjust to project style if it diverges.
- Per `bash-defensive`: pre-commit hook scripts themselves should follow `set -euo pipefail`; lint catches missed cases.
- For mixed `.sh` and `.bash`, shellcheck auto-detects via the shebang; for files without a shebang, set the project's `.shellcheckrc` `shell=` directive.

### Per-tool docs

- shellcheck: `https://www.shellcheck.net/`
- shfmt: `https://github.com/mvdan/sh`

## Cross-references

- `author-hook`: distinct concept (Claude Code session hooks via `.claude/settings.json`). The shared word "hook" causes confusion; this skill is git-native, that one is Claude-native.
- `bash-defensive`: pre-commit hook scripts themselves should follow `set -Eeuo pipefail` discipline; the shell recipe enforces it via shellcheck.
- `secrets-hygiene`: a future addendum may add `detect-secrets` or `gitleaks` to the pre-commit pipeline; flagged here as warm pointer. For now, secret-scanning belongs in CI rather than at commit-time (false-positive cost is too high to gate every commit on it).
- `tdd`: pre-commit is the discipline that catches what TDD missed; both gate the same surface from different angles.
- `using-git-worktrees`: pre-commit installs into the main repo's `.git/hooks/`, not per-worktree. The hook fires from every worktree of the same repo automatically.
- `forward-compatible-schemas`: when pinning tool versions in `.pre-commit-config.yaml`, pin the major version (e.g. `rev: v0.6.9` for ruff 0.x) to avoid surprise breakage from upstream; refresh during the next mattpocock audit pass.

## Common mistakes

- `--no-verify` becomes the default. Once a developer learns the bypass, the hook stops being a gate. Policy: never bypass; if the hook is wrong, fix the hook.
- Full test suite in the staged-file step. Pre-commit hooks blocked on a 5-minute test suite are bypassed; keep staged-file under 10s and full-repo under 30s.
- Hook does more than CI. If pre-commit gates on rules CI doesn't, "but it passes CI" arguments multiply; keep the hook a SUBSET of CI's checks.
- Husky and `pre-commit` framework both installed. Pick one per repo; mixing causes hooks to run twice and the second one's failure to mask the first's success.
- `.pre-commit-config.yaml` floats on `rev: main`. Floating refs break commits when upstream changes overnight; always pin to a version tag.
- Markdown-only repo with line-length enabled. The MD013 rule fights prose every commit; disable it explicitly with a documented reason.
- Python recipe without `additional_dependencies` populated for mypy. mypy passes on stub-missing paths and the typecheck step becomes a no-op.
- Ansible recipe with `--profile=production` on a legacy playbook tree. Every commit fails on pre-existing lint debt; start with `--profile=basic` and ratchet up.

## Red flags

- The project's CI runs a tool the pre-commit hook doesn't (CI parity broken from day one).
- `.pre-commit-config.yaml` with `rev: main` or `rev: HEAD` on any hook (floating refs).
- A pre-commit hook that takes more than 30s on a small change set.
- `--no-verify` in any committed script or runbook (the bypass is the policy now).
- A repo with both Husky and `.pre-commit-config.yaml` (pick one).
- A markdown-only repo gating on MD013 (line length) without an explicit reason.
- mypy in the Python recipe with empty `additional_dependencies` for a project that uses typed third-party libs.
- ansible-lint with `--profile=production` on a tree that has not been linted in months.

## Bottom line

Stage-file step for speed, full-repo step for safety, both fast enough that nobody reaches for `--no-verify`. JS/TS uses Husky + lint-staged; everything else uses the `pre-commit` framework. The recipe shape is the same across stacks; only the tools change. Pin every tool version; mirror CI; refuse the bypass.
