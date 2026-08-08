---
name: bash-defensive
description: Use when writing or reviewing a non-trivial Bash script (production automation, CI/CD pipeline, sysadmin utility, deploy script, backup runner). Triggers include "write a bash script for X", "this script keeps failing silently", "harden this shell script", "add error handling to Y.sh", "set up shellcheck", "write tests for this script", "TDD this bash utility". Covers strict-mode setup (set -Eeuo pipefail), trap-based cleanup, variable safety (always quote, required-var assertions), array safety, conditional safety ([[ ]] vs [ ]), safe script-directory detection, ShellCheck configuration (.shellcheckrc, CI integration, suppress-with-reason), Bats test patterns (file structure, setup / teardown, assertions, fixtures, mocks). Localised consolidation of wshobson/agents/plugins/shell-scripting (bash-defensive-patterns + shellcheck-configuration + bats-testing-patterns folded into one skill).
metadata:
  version: 1.0.0
---

# Bash Defensive

> **Skill marker**: When applying this skill, begin your reply with `[skill: bash-defensive]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Bash scripts fail silently by default. A typo in a variable name expands to empty; a pipe failure inside `cmd1 | cmd2` returns success because only the last command's exit code matters; an unset variable in a path expands to `rm -rf /usr/local/`. The defensive patterns below turn each failure mode into a hard stop.

**Core principle:** strict mode at the top of every script, trap-based cleanup at the bottom, ShellCheck on every commit, Bats tests for non-trivial scripts.

## When to use

- Writing or hardening a production automation script (deploy, backup, batch job, cron entry).
- Building or reviewing a CI / CD pipeline script.
- Sysadmin utilities run by the user manually but liable to be re-run by someone else later.
- A script that has been silently failing or producing unexpected output.
- Setting up linting / testing infrastructure for an existing scripts directory.

Do NOT use this skill for:

- One-off interactive shell commands (the cost of strict mode is friction; the win is durability).
- Three-line wrapper scripts where the failure mode is loud (`set -e` alone is enough).

## Strict mode (the iron rule)

Every non-trivial script starts with:

```bash
#!/bin/bash
set -Eeuo pipefail
```

What each flag does:

| Flag | Effect |
|---|---|
| `-E` | ERR trap is inherited by functions, command substitutions, and subshells. Without this, an error in a function does not trigger the trap. |
| `-e` | Exit immediately if any command returns a non-zero status. The single most-effective defence; every script gets it. |
| `-u` | Treat unset variables as an error and exit. Catches typos in variable names before they expand to empty. |
| `-o pipefail` | The exit status of a pipeline is the last non-zero status in the pipe, not just the final command's. Without this, `cmd1 | cmd2` succeeds even if `cmd1` failed. |

If the script has a section where set -e is genuinely too strict (intentional check that may fail), use `set +e ... set -e` to bracket the section narrowly. Do NOT disable strict mode for the whole script.

## Trap-based cleanup

Every script that creates temporary state (tmpdirs, lock files, partial output) cleans up on exit:

```bash
#!/bin/bash
set -Eeuo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
trap 'echo "Error on line $LINENO" >&2' ERR

# Script body uses $TMPDIR freely
```

Two traps:

- `EXIT` runs unconditionally on any exit (success, error, signal). Cleanup goes here.
- `ERR` runs when a command returns non-zero (with `set -e`). Use for diagnostic logging, not for cleanup (cleanup is in EXIT).

If the script also handles SIGINT / SIGTERM (long-running services), add `trap 'cleanup; exit 130' INT TERM` so Ctrl-C also runs cleanup.

## Variable safety

### Always quote

```bash
# Wrong: word-splits on spaces; globs expand
cp $source $dest

# Right: literal value, no splitting, no globbing
cp "$source" "$dest"
```

The cost of always quoting is zero; the cost of forgetting once is a script that "works on my machine".

### Required-var assertions

```bash
# Fail with a useful message if VAR is unset
: "${VAR:?VAR is not set; export it before running}"
```

`:` is the no-op; `${VAR:?message}` expands to the variable's value or fails the assertion with the message. Put these at the top of the script, right after strict mode, so the script fails before doing any work.

### Defaults for optional vars

```bash
# Use $LOG_LEVEL if set, otherwise "info"
LOG_LEVEL="${LOG_LEVEL:-info}"
```

The `${VAR:-default}` pattern is the safe way to read an optional env var. Do NOT use `${VAR-default}` (without the colon) unless you specifically want "set but empty" to use the empty value rather than the default.

## Array safety

Arrays prevent the word-splitting bugs that come from "list of items in a string" patterns:

```bash
# Wrong: breaks on items with spaces
items="item 1 item 2 item 3"
for item in $items; do
    echo "$item"   # prints "item", "1", "item", "2", ...
done

# Right: explicit array
declare -a items=("item 1" "item 2" "item 3")
for item in "${items[@]}"; do
    echo "$item"   # prints each full item
done
```

Reading command output into an array safely:

```bash
mapfile -t lines < <(some_command)
readarray -t numbers < <(seq 1 10)
```

The `< <(cmd)` is process substitution; `mapfile -t` strips the trailing newline per line.

## Conditional safety

Prefer `[[ ]]` (Bash test) for new scripts; reserve `[ ]` (POSIX test) for explicit POSIX portability:

```bash
# Bash; safer (no word-splitting inside)
if [[ -f "$file" && -r "$file" ]]; then
    content=$(<"$file")
fi

# POSIX; portable but quirkier
if [ -f "$file" ] && [ -r "$file" ]; then
    content=$(cat "$file")
fi
```

Test for "set and non-empty" with `[[ -z "${VAR:-}" ]]`; the `:-` default suppresses `set -u`'s "unbound variable" error if VAR is genuinely unset.

## Safe script-directory detection

To find the script's own directory (so the script can locate sibling files), use:

```bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
```

Why each piece:

- `${BASH_SOURCE[0]}` is the script's path even when sourced (vs `$0` which is the parent shell's name when sourced).
- `dirname` strips the filename; `cd` resolves to absolute path; `pwd -P` resolves symlinks.
- `--` ends option parsing so paths starting with `-` aren't mistaken for flags.

Do NOT use `$0` or `$(dirname $0)` for this; both break under sourcing or symlinks.

## ShellCheck

Static analysis for shell scripts. Catches the most common bugs (unquoted vars, unset vars, deprecated patterns, common typos). Run on every commit; gate CI on it.

### Project-level configuration

`.shellcheckrc` in the project root:

```
# Target shell (bash, sh, dash, ksh)
shell=bash

# Enable optional checks the project wants
enable=avoid-nullary-conditions
enable=require-variable-braces
enable=quote-safe-variables

# Disable specific warnings (with reason next to the line that uses them)
# disable=SC1091  # don't follow source files outside the script tree
```

### Per-line suppression with reason

When a warning genuinely doesn't apply, suppress it on the offending line with a reason:

```bash
# shellcheck disable=SC2086  # intentional word-splitting; ssh expects unquoted
ssh "$host" $command
```

Always include the WHY. A bare `# shellcheck disable=SC2086` decays into a "we always disable this" anti-pattern.

### CI integration

```bash
# Find every executable shell script and lint it
find . -type f \( -name "*.sh" -o -name "*.bash" \) -print0 | xargs -0 shellcheck

# Or with explicit error format for CI parsing
shellcheck --format=gcc --severity=warning ./scripts/*.sh
```

Severity levels: `error`, `warning`, `info`, `style`. CI typically gates on `warning`+ (errors fail the build).

### Common warnings worth knowing

| Code | Issue | Fix |
|---|---|---|
| SC2086 | Word-splitting on unquoted variable | Quote the variable: `"$var"` |
| SC2046 | Word-splitting on unquoted command substitution | Quote: `"$(cmd)"` |
| SC2154 | Variable referenced but not assigned | Assign or use `${var:-default}` |
| SC2155 | Declare and assign separately | Split: `declare -r var; var=$(cmd)` |
| SC1091 | Source file not followed | Suppress with reason if intentional |
| SC2034 | Variable appears unused | Either use it or rename `_unused` |

## Bats (Bash Automated Testing System)

TAP-compliant testing framework for shell scripts. Use for any script complex enough to warrant TDD (`tdd` skill applies; the only difference is the tool).

### File structure

```
project/
├── bin/
│   ├── deploy.sh
│   └── helpers.sh
├── tests/
│   ├── deploy.bats
│   ├── test_helper.sh
│   └── fixtures/
│       ├── valid-input.txt
│       └── expected-output.txt
└── README.md
```

### Basic test file

```bash
#!/usr/bin/env bats

load test_helper

setup() {
    # Runs before each test
    TMPDIR=$(mktemp -d)
}

teardown() {
    # Runs after each test
    rm -rf "$TMPDIR"
}

@test "deploy.sh fails when SERVICE_NAME is unset" {
    run ./bin/deploy.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"SERVICE_NAME is not set"* ]]
}

@test "deploy.sh succeeds with valid input" {
    SERVICE_NAME=test ./bin/deploy.sh
    [ "$status" -eq 0 ]
}
```

`run cmd` captures the exit status into `$status` and the output into `$output`. Assertions use shell test syntax. The `setup` and `teardown` functions run per test.

### TDD discipline

The `tdd` skill's red-green-refactor cycle applies to bash exactly as to TypeScript or Python:

1. Write the failing test FIRST. Run it; confirm it fails.
2. Write the minimal bash to make it pass. Run; confirm it passes.
3. Refactor (extract function, clean up); run again; still passes.

The vault's `testing-anti-patterns` skill applies too: don't mock the script under test; use real fixtures; don't add a `--test-mode` flag to the production script.

### Mocking external commands (use sparingly)

When the script calls an external tool (`gh`, `aws`, `kubectl`) that you don't want to actually invoke in tests:

```bash
# tests/test_helper.sh
function gh() {
    case "$1" in
        "pr") echo '{"number":42,"state":"OPEN"}' ;;
        *) echo "unhandled gh subcommand: $1" >&2; return 1 ;;
    esac
}
export -f gh
```

Per `testing-anti-patterns`: prefer integration tests against real tools when feasible. Mock only when the real tool is too slow, costs money, or has irreversible side effects.

## Cross-references

- `tdd`: red-green-refactor for bash via Bats. Same discipline; different test runner.
- `testing-anti-patterns`: don't mock the script under test; don't add test-only flags to production code; the five iron laws apply to bash too.
- `completion-gate` Layer 1: ShellCheck is the bash-side equivalent of typecheck; run it preemptively after writes.
- `secrets-hygiene`: never paste real credentials into bash scripts; use `${ENV_VAR:?}` to require them at runtime; the script reads from the secret store.
- `linux-host-bringup`: bash scripts are the artefact for a lot of the bring-up workflow's commands; defensive patterns apply to those too.
- `oncall-runbooks`: runbook commands embedded in markdown should still pass ShellCheck when extracted.

## Common mistakes

- Strict mode at the top, then `set +e` for the whole rest of the script ("strict mode broke my script"; usually means a command returns 1 in a non-error case; bracket narrowly with `set +e ... set -e`, don't disable globally).
- Trap on EXIT but not ERR (cleanup happens on success only; partial state survives errors).
- Unquoted variables ("but it works in my tests"; tests don't have spaces / globs).
- ShellCheck suppression without reason (decays into "we always disable this").
- Bats tests that source the script under test instead of running it via `run` (state pollution between tests).
- Mocking the script under test (per `testing-anti-patterns`; integration tests with real fixtures are better).
- Long-running scripts without trap on INT / TERM (Ctrl-C leaves partial state).
- `${VAR-default}` instead of `${VAR:-default}` (the colon-less form treats "set but empty" as set; usually a bug).

## Red flags

- `#!/bin/bash` without `set -Eeuo pipefail` on a script over 20 lines.
- `cp $src $dst` (unquoted; word-splits on spaces).
- `for x in $list` (unquoted list; word-splits and globs).
- `cd $(dirname $0)` (unsafe; breaks under sourcing and symlinks).
- ShellCheck suppression with no comment explaining why.
- A Bats test that doesn't `run` the command (assertions check the helper functions instead of the script).
- Mocking `gh` / `aws` / `kubectl` when a fixture-based integration test would work.
- A script with `trap` on EXIT only and no ERR trap (errors leave partial state).
- `set -e` followed by `set +e` for the entire script body.

## Bottom line

Strict mode, trap-based cleanup, always quote, required-var assertions, ShellCheck on every commit, Bats for non-trivial scripts. The iron rule is the four-flag set at the top; everything else is the rest of the toolkit.
