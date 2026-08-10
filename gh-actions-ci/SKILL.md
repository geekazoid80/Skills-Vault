---
name: gh-actions-ci
description: Use for any GitHub Actions workflow authoring, CI pipeline debugging, release-pipeline design, or post-merge red-build triage. Triggers include "GitHub Actions failing", "workflow YAML", "actionlint", "yamllint", "pin action version", "generate-changelog from release tag", "diff against previous release tag", "changelog says none detected", "fail-fast vs continue-on-error", "drop continue-on-error", "mkdocs strict failing in CI", "stage content into docs/", "pandoc highlight-style", "marp per-module build", "PPTX missing from release", "preprocess filename in build script", "wire script into pipeline", "octal trap in bash printf", "printf invalid octal number", "BSD vs GNU grep in CI", "grep -P macOS", "gh run list instead of pr checks", "CI debug from fine-grained PAT". Covers workflow YAML hygiene (actionlint, yamllint, version pinning), changelog-from-tag-to-tag patterns (release-tag diff range, basename-vs-full-path resolution, tag-existence guards for shallow clones), the fail-fast vs continue-on-error maturity curve (defensive default while a step is unproven, drop once empirically stable so regressions block the release), build-time content staging for strict-mode builds (mkdocs --strict, pandoc, marp), and the gh run list / gh run view --log-failed workflow as the Checks-API substitute when running with a fine-grained PAT. Cross-refs bash-defensive (octal trap, printf %d with zero-padded inputs), platform-quirks-escape (BSD vs GNU grep -P portability), setup-pre-commit (catch issues before they hit CI), secrets-hygiene (CI secrets handling). Also fires on CI-poll correctness symptoms such as "CI poll exited early", "the poll reported green while jobs were still running", "false green", "completed+in_progress", "joined status string", "case completed* matched mid-run", "gh run list --jq join", where a loop summarising several runs into one joined status string is matched with a prefix glob and so breaks while jobs are still live; match the full terminal string plus explicit failure, cancelled and timed_out arms. Self-authored from CI lessons across the author's own projects; no upstream fold per ecosystem survey 2026-05-24.
metadata:
  version: 1.0.0
---

# GitHub Actions CI

> **Skill marker**: When applying this skill, begin your reply with `[skill: gh-actions-ci]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

GitHub Actions failures split into three buckets: workflow YAML problems (syntax, version pinning, action-input misuse), runner-environment shell gotchas (bash quirks, BSD vs GNU divergence, octal traps), and pipeline wiring (steps not wired together, content not staged, changelog comparing the wrong range). The first two buckets have dedicated skills (`bash-defensive`, `platform-quirks-escape`); this skill owns the third bucket and the GH-Actions-specific patterns that no other skill covers.

**Core principle:** treat CI red as a diagnostic signal, not as something to silence with `continue-on-error`. `continue-on-error: true` is a transitional default while a step is empirically unproven; the goal is always to drop it once the step is stable so a future regression blocks the release rather than silently dropping artifacts.

## When to use

- About to author or modify a `.github/workflows/*.yml` file.
- A workflow step has gone red on `main` after merge and needs triage.
- A release pipeline is producing partial artifacts (PPTX missing, slides in the wrong directory, changelog blank) and the cause is unclear.
- Designing a changelog generator that compares a new release against the previous one.
- Deciding whether a `continue-on-error: true` step should be hardened to fail-fast.
- A `mkdocs --strict` / `pandoc` / `marp` build is failing because content the build expects is not at the documented path.
- Running CI debugging from a fine-grained PAT that cannot call the Checks API.

Do NOT use this skill for:

- Bash hardening itself, that's `bash-defensive` (the octal trap, `set -Eeuo pipefail`, ShellCheck, Bats).
- Cross-platform shell portability beyond a single CI gotcha, that's `platform-quirks-escape` (BSD vs GNU sed, macOS bash 3.2, Windows PowerShell).
- Pre-commit hook setup as an alternative to CI gating, that's `setup-pre-commit`.
- Secrets storage and rotation in CI, that's `secrets-hygiene` (the canonical patterns) and `multi-pat-direnv` in memory (the multi-PAT direnv workflow specifically).
- Slash-command / claude-code-hook authoring, that's `author-hook` (different concept despite the shared "hook" word).

## Workflow YAML hygiene

The cheapest defects to prevent. Three rules:

1. **Run actionlint locally before pushing.** Catches typo'd `uses:`, undeclared `needs:`, malformed expressions. `brew install actionlint` on macOS; `gh extension install rhysd/actionlint` if you prefer the gh extension. Add it to `setup-pre-commit` so YAML mistakes never reach CI.
2. **Pin action versions by SHA, not by tag.** `uses: actions/checkout@v4` is convenient but resolves to a moving tag; `uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1` cannot be silently retargeted. Dependabot will PR SHA bumps.
3. **Quote anything that looks like YAML 1.1 might misparse it.** `on: push` is fine; `version: 035` is NOT, YAML 1.1 reads leading-zero strings as octal (this is the cousin of the bash octal trap; see `bash-defensive`). When in doubt, quote: `"035"`.

## Changelog generated from tag-to-tag diffs

A release changelog needs to compare the new release against the previous release, not against `HEAD~1`. Three rules layered:

1. **Diff range is `${OLD_TAG}..HEAD`, not `HEAD~1 HEAD`.** `HEAD~1` catches only the very last commit, missing everything that landed between releases. Resolve `OLD_TAG` from `git describe --tags --abbrev=0 HEAD^` or equivalent.
2. **Tag-existence guard for shallow clones and first release.** `actions/checkout` defaults to `fetch-depth: 1`; the previous tag will not be resolvable. Either set `fetch-depth: 0` in the checkout step, or guard with `git rev-parse --verify "$OLD_TAG" >/dev/null 2>&1 || { echo "first release, skipping change detection"; exit 0; }`. Without the guard, the diff returns the entire history as "changed" and the changelog flags everything spuriously.
3. **If a manifest records bare basenames and source files live in subdirectories, resolve via `git ls-files`.** `git diff -- "$FILE"` matches the literal path; `osi-model.md` will not match `modules/networking/osi/osi-model.md`. Resolve: `RESOLVED=$(git ls-files "**/${FILE}" | head -1)` then diff against `$RESOLVED`. Watch for the `head -1` ambiguity if multiple paths share a basename (record full paths in the manifest as the real fix).
4. **Watch tabular column indexing.** Markdown table columns are 1-indexed and `cut -f` / `awk` extractions are easy to off-by-one. If `extract_modules` returns `MOD_ID\tTITLE`, a downstream loop that treats column 2 as the filename will silently process titles as paths. Emit explicit `MOD_ID\tTITLE\tFILE` triples and let the loop pick the field by name, not by index.

## Fail-fast vs continue-on-error maturity curve

`continue-on-error: true` on a workflow step has one legitimate use: defending the rest of the pipeline while the step itself is empirically unproven. New step lands, you do not yet know whether it will be reliable across all content, you do not want one flaky step to block every release. So you tolerate it for a few runs.

**The discipline is to drop the tolerance once empirically stable.** If the step has produced clean output for 2+ consecutive releases and the failure modes are understood, remove `continue-on-error: true`. Otherwise it stays in indefinitely, and a future regression silently drops artifacts from releases until somebody notices the missing files (often months later, when a downstream consumer reports the gap).

Concrete pattern from this repo (PR #13): PPTX build was wrapped in `continue-on-error: true` while marp's per-module behaviour was untested; after two clean releases produced all 66 modules cleanly, the wrapping was removed so the next regression blocks the release rather than silently dropping slides.

The same pattern applies to `if: always()` on cleanup steps (legitimate forever, cleanup must run regardless), `if: failure()` on diagnostic-collection steps (legitimate forever), and `--ignore-errors` flags on tools like `cp` / `rm` (almost never legitimate, fix the underlying race or path issue instead).

## Build-time content staging

Strict-mode documentation builders (`mkdocs --strict`, `pandoc` with broken-link detection, `marp` per-deck) need content paths the builder expects. Two approaches when repo-root content (a top-level README.md, a CHANGELOG.md, an AI_GUARDRAILS.md) needs to appear in the published site:

1. **Stage content into the build root in a CI step before the build runs.** `cp README.md docs/index.md`, `cp CHANGELOG.md docs/changelog.md`, etc. The build sees a clean tree at the documented path. This is the recommended default.
2. **Relax strict mode.** Tempting, but defeats the point of strict mode. Strict mode catches broken links and missing files at build time; relaxing it pushes those failures to the published site. Reject this unless you cannot otherwise control the source tree (e.g. building third-party docs you do not own).

Concrete from this repo (PR #3): `mkdocs build --strict` was failing because repo-root content was not under `docs/`. The fix was to stage the content into `docs/` in a CI step, not to drop `--strict`. PR body explains the rationale.

Adjacent pitfall: tooling-flag drift. `pandoc --highlight-style=...` (PR #7), `build-pptx.sh` referencing the wrong preprocess module filename (PR #9). Both surface as `command not found` or `argument unknown` rather than as the actual missing-feature problem. When a CI step fails with a flag-related error, suspect the tool version on the runner first (compare `tool --version` between local and CI), then suspect a typo in your invocation, then suspect a renamed script in your own repo.

## CI debugging from a fine-grained PAT

Fine-grained PATs cannot call the GitHub Checks API; `gh pr checks` returns HTTP 403 with `Resource not accessible by personal access token`. The full background lives in the [Multi-PAT direnv setup](../../memory/multi-pat-direnv.md) memory entry (the Checks-API gap section).

**Practical CI-debug substitute under `Actions: Read/Write`** (which IS grantable to fine-grained PATs):

```bash
# Instead of: gh pr checks NN
gh run list --branch <branch> --limit 20 \
  --json status,conclusion,name,headSha,databaseId

# Instead of: gh pr view NN --json statusCheckRollup
gh run view <run-id> --json jobs --jq '.jobs[] | {name, conclusion}'

# Failed-step log
gh run view <run-id> --log-failed
```

Pipe `gh run view --log-failed` through `less` for long jobs. Use `gh run watch <run-id>` to follow a running job to completion (handy when iterating on a workflow change).

### Polling several runs at once: the joined-status glob trap

`gh run list` returns one row per run, so a loop that polls "the CI for this branch" almost always ends up
summarising several runs into a single string with a `--jq` join:

```bash
gh run list --branch "$BRANCH" --limit 10 --json status,conclusion,headSha \
  --jq '[.[] | select(.headSha == "'"$SHA"'")]
        | (map(.status) | unique | join("+")) + "/" + (map(.conclusion) | unique | join("+"))'
```

While one workflow has finished and another is still going, that emits exactly what it was asked for:

```
completed+in_progress/+success
```

The trap is on the matching side:

```bash
case "$row" in
  completed*) echo "CI green"; break ;;   # WRONG
esac
```

`completed+in_progress/+success` starts with `completed`, so the glob matches, the loop breaks, and the
poll reports green while jobs are still running. Nothing errors and nothing looks wrong. The empty
conclusion segment before the `+` is the only tell, and it reads as cosmetic.

Match the whole terminal string, and give the failure states their own arms:

```bash
case "$row" in
  "completed/success")               echo "CI green";     break  ;;
  *failure*|*cancelled*|*timed_out*) echo "CI red: $row"; exit 1 ;;
  *)                                 sleep 20            ;;  # still running
esac
```

Two rules generalise past this one loop:

- **A prefix glob against a joined summary is a bug waiting for a second workflow to exist.** It behaves
  correctly right up until the branch has more than one run, which is precisely when a poll is worth
  writing.
- **Give the failure states explicit arms rather than letting them fall through to "not green yet".** A
  catch-all `*)` that means "keep waiting" will patiently wait out a run that has already failed, until
  the loop's own timeout, and then report a timeout instead of the failure.

This costs more than an ordinary polling bug because of where it sits. A poll loop exists to gate a merge
decision, so its answer is consumed immediately, by someone who asked precisely because they did not want
to check by hand.

## Cross-references

- `bash-defensive`, every shell step inside a workflow is a bash script. Strict-mode (`set -Eeuo pipefail`) catches CI failures that would otherwise be silent partial successes. The **octal trap** specifically: `printf %d` with a zero-padded string input (`printf "v%03d" "039"` → `printf: 039: invalid octal number`) is a recurring bash gotcha that surfaces as a CI failure but is a bash issue. Cast first: `$((10#$X))`.
- `platform-quirks-escape`, CI runners are usually Linux (GNU coreutils), local dev is often macOS (BSD coreutils). `grep -P` is GNU-only; `sed -i` differs; `mapfile` is bash 4+. A script that "worked on the runner" may silently mis-behave on macOS or vice versa. The **`grep -P` trap** from PR #12: a script using `grep -P` returned empty on macOS BSD grep (with `2>/dev/null` hiding the `invalid option -- P` error), making the changelog appear correct in CI but broken locally. Iron rule from that skill: when bash hits platform-quirks, escape to Python.
- `setup-pre-commit`, actionlint, yamllint, shellcheck as pre-commit hooks catch CI failures before they reach CI. The cost is one local check; the saving is one less red-build cycle.
- `secrets-hygiene`, workflow secrets (`${{ secrets.X }}`) must never appear in `echo` / `printf` debug output, must be set via repo / org / environment secrets (never committed), and must rotate on a documented schedule.
- `multi-pat-direnv` (memory), full background on the fine-grained PAT Checks-API gap and the `gh run list` workaround.
- `multi-vendor-network-ops`, N/A here, but the nine-element response contract template is worth borrowing for CI-incident postmortems if a red build causes a release miss.
- `completion-gate`, before claiming a CI fix "shipped", verify the next post-merge run is green. The fix lives in the workflow YAML, but the proof lives in the next run's status.

## Common mistakes

- `continue-on-error: true` left on a step indefinitely after the step has stabilised. Artifacts silently drop and nobody notices.
- Changelog generator diffing `HEAD~1 HEAD` instead of `${PREV_TAG}..HEAD`. Catches only the merge commit, misses everything else in the release.
- `actions/checkout` with default `fetch-depth: 1` then trying to read git history beyond the last commit. Solution: `fetch-depth: 0` on the checkout step.
- Quoting / not-quoting drift in workflow expressions: `${{ matrix.x }}` (expression) vs `"${{ matrix.x }}"` (forced string). Forced-string is safer in 99% of cases.
- Re-using a third-party action by `@v4` tag without SHA pinning. A supply-chain compromise of that action becomes a compromise of your release.
- `printf %d "$X"` where `$X` might be `0NN`. Bash reads leading-zero as octal. Cast: `$((10#$X))`.
- `grep -P` in a script intended to run on both CI (GNU) and macOS local (BSD). Use BRE (`'^| [A-Z]'`) or escape to Python.
- mkdocs `--strict` failing because repo-root content was not staged into `docs/`. Stage in CI; do not relax strict mode.
- Treating `2>/dev/null` as harmless suppression. It hid the `grep -P` portability error for several releases (PR #12).
- Matching a CI poll's joined status with a prefix glob (`completed*`). It matches `completed+in_progress` and breaks the loop while jobs are live.
- A poll loop whose only exit conditions are "green" and "timed out". A run that failed ten minutes ago gets reported as a timeout.

## Red flags

- About to commit a workflow with a step wrapped in `continue-on-error: true` and no plan to remove it.
- About to write `git diff HEAD~1 HEAD` in a changelog generator (almost always wrong).
- About to use `grep -P` in a script that will also be run from macOS.
- About to write `printf %d "$VAR"` where `$VAR` is supplied externally (workflow env, action input, command-line arg) without an explicit base-10 cast.
- About to merge a workflow change without an actionlint pass.
- About to add a third-party action with `@vN` instead of `@SHA # vN.M.P`.
- About to relax `mkdocs --strict` to make a build pass.
- About to suppress a script error with `2>/dev/null` without first reading what the error said.
- About to debug CI failures via `gh pr checks` while running under a fine-grained PAT (use `gh run list` / `gh run view --log-failed` instead).
- About to break a CI poll loop on a prefix glob rather than the full terminal status string, on a branch that can have more than one workflow run.
- About to act on a poll that reported green, when the status string it matched contained a `+` or an empty conclusion segment.

## Bottom line

CI red means the system caught something. Fix the underlying issue rather than silencing the signal. Changelogs diff tag-to-tag, not commit-to-commit. `continue-on-error: true` is a temporary scaffold, not a permanent fix. Shell gotchas (octal traps, BSD vs GNU divergence) surface in CI but live in `bash-defensive` and `platform-quirks-escape`, cross-link, do not duplicate.
