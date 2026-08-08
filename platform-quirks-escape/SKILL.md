---
name: platform-quirks-escape
description: "Use when about to write a shell script that will be committed to a repo or run repeatedly across environments. Triggers include \"write a bash script\", \"shell script for X\", \"script needs to run on Mac and Linux\", \"this needs to be portable\", \"declare -A\", \"bash 3.2\", \"macOS bash failing\", \"mapfile\", \"readarray\", \"BSD sed vs GNU sed\", \"sed -i not working on Mac\", \"cross-platform script\", \"Windows CMD vs PowerShell vs bash\", \"PowerShell escaping\", \"WSL quoting\", \"shell quoting hell\", \"platform-specific hack\". Iron rule: when the script is heading into platform-quirks territory (or is already there), STOP patching the workaround and ESCAPE to Python. The vault has rediscovered the same two hacks more than once (macOS default bash 3.2 lacking `declare -A`; Windows CMD / PowerShell / WSL quoting hell); this skill makes the escape automatic, not a per-session re-derivation. NOT for one-off interactive bash at the prompt. NOT for shell one-liners in CI YAML. NOT for the bash hardening itself (see `bash-defensive`). Cross-refs `bash-defensive` (when bash IS right), `subagent-delegation` (when the script runs on a remote host)."
metadata:
  version: 1.0.0
---

# Platform-Quirks Escape

> **Skill marker**: When applying this skill, begin your reply with `[skill: platform-quirks-escape]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

Before writing a non-trivial shell script, ask three questions:

1. **Will this script be committed to a repo OR run more than once across environments?** If no, ignore this skill; ad-hoc bash at the prompt is fine.
2. **Does the script touch platform-variable surface?** File globs, recursive directory walks, path joining, subprocess invocation with arguments, JSON parsing, HTTP, env-var case manipulation, associative collections, or string substitution all qualify.
3. **Is there a non-trivial chance this script will run on macOS, Linux, AND Windows (or WSL)?** Or even just macOS + Linux?

If 1 is yes AND (2 or 3 is yes), default to Python from the start. Do not write the bash version "to see how it goes". The two known hacks below are the canonical examples of why.

## The Iron Rule

When a shell-script approach hits a platform quirk, STOP patching the workaround and ESCAPE to a portable runtime. Python is the default escape target because it ships on every developer machine and its stdlib (`os`, `subprocess`, `pathlib`, `shutil`, `json`, `urllib`, `re`) abstracts away the entire platform-portability problem.

The wrong response: "let me rewrite this with parallel arrays so it works on bash 3.2". The right response: "this is what Python is for; rewrite the whole script".

## The Two Known Hacks

These are the friction points the vault has rediscovered more than once.

### Hack 1: macOS default `/bin/bash` is bash 3.2

macOS ships `/bin/bash` 3.2 (Apple frozen it at the last GPLv2 release). Bash 4+ features fail silently or with cryptic errors:

| Bash 4+ feature | Symptom on macOS 3.2 | Portable Python equivalent |
|---|---|---|
| `declare -A map` | `declare: -A: invalid option` | `map = {}` |
| `mapfile -t arr < file` | `mapfile: command not found` | `arr = open(file).read().splitlines()` |
| `readarray -t arr < <(cmd)` | `readarray: command not found` | `arr = subprocess.check_output(cmd).decode().splitlines()` |
| `${var^^}` (uppercase) | `bad substitution` | `var.upper()` |
| `${var,,}` (lowercase) | `bad substitution` | `var.lower()` |
| `${var^}` (titlecase first char) | `bad substitution` | `var[:1].upper() + var[1:]` |

The workarounds inside bash are ugly: parallel arrays + function calls, AWK pipelines, `tr '[:lower:]' '[:upper:]'`. Each workaround is a maintenance debt.

**Escape options, in order of preference:**

1. **Rewrite in Python.** Default choice.
2. **Invoke `/opt/homebrew/bin/bash` (bash 5) explicitly** via shebang `#!/opt/homebrew/bin/bash`. Only works if Homebrew's bash is installed; brittle in CI; loses the "ships everywhere" property.
3. **Patch with bash-3.2 workarounds.** Last resort. Only if the script is short, the workaround is one-line, and there is a clear reason it cannot be Python.

### Hack 2: Windows CMD / PowerShell / WSL quoting hell

A shell script that must run on Windows hits four shells with different escaping rules: CMD, PowerShell, Git-Bash, and WSL. Path separators (`\` vs `/`), quote types (`"`, `'`, `` ` ``), variable syntax (`%VAR%` vs `$VAR` vs `$env:VAR`), and tool flag conventions diverge. Every script becomes an escape-character archaeology dig.

**Escape:** write the logic in Python. Python's `subprocess.run([...], check=True)` takes a list of arguments and handles quoting per-platform. `pathlib.Path` handles path joining. `shutil` covers copy / move / rmtree / which. No escape chars to debug.

```python
# Cross-platform, no quoting issues
import subprocess
from pathlib import Path

target = Path.home() / "Documents" / "report.pdf"
subprocess.run(["pdfunite", str(target), "merged.pdf"], check=True)
```

vs the bash equivalent that has to handle Windows paths with spaces, PowerShell vs CMD quoting, and the difference between `pdfunite` on Linux vs `pdfunite.exe` on Git-Bash.

## When to Reach for Python by Default

Even before a platform quirk surfaces, default to Python when the script does any of:

- Recursive directory walk with filtering (`pathlib.Path.rglob`).
- JSON parsing or generation (`json` stdlib).
- HTTP requests (`urllib.request` for stdlib only; `requests` if available).
- Process invocation with structured arguments (`subprocess.run`).
- File-content transformation with regex (`re` stdlib).
- Cross-platform path joining (`pathlib.Path`).
- Temp-file handling (`tempfile.NamedTemporaryFile`).
- Anything with associative lookups, sets, or iteration over a collection of records.

Bash is fine for: glue-code wrapping a single CLI tool, environment-variable setup, exec'ing into another process, init scripts that are 100% systemd / launchd interaction.

## See `references/python-vs-bash-cheatsheet.md`

For a longer mapping of common bash patterns to Python stdlib equivalents (file iteration, env vars, subprocess pipes, path manipulation, JSON, HTTP, regex), see the bundled reference. Loaded on demand; do not pull into context unless writing the Python version and unsure of the idiom.

## When NOT to Use This Skill

- **One-off interactive commands.** A `for` loop at the shell prompt that runs once and is never committed. Bash is fine; do not over-engineer.
- **Shell one-liners in CI YAML.** `run: npm test && npm run lint` stays bash; the CI runner already controls the shell.
- **Hardening an existing bash script that is already the right tool** (small, glue-code, single-platform). See `bash-defensive` for `set -euo pipefail`, ShellCheck, traps.
- **Remote-host scripts the agent does not control.** If the script must run on a remote box without Python, you may have no choice; see `subagent-delegation` for delegation patterns.
- **systemd unit `ExecStart=` lines or launchd plist entries.** Use what the init system expects.

## Cross-references

- `bash-defensive`: when bash IS the right tool, harden it (strict mode, traps, ShellCheck, Bats tests). This skill says "do not write the bash"; that one says "if you must write the bash, write it well".
- `subagent-delegation`: when a script must run on a remote host the agent does not directly control, delegate via sub-agent rather than emit a portable script.
- `secrets-hygiene`: when the script handles credentials, env vars containing tokens, or device passwords, layer that skill on top.

## Red Flags

- About to type `declare -A` in a script that will be committed to the repo.
- About to type `sed -i ` without `''` after `-i` (BSD sed needs the empty backup arg; GNU sed does not; the same line breaks across platforms).
- About to chain `cmd && other-cmd | jq '.foo' | tail -1` and target Windows.
- About to escape backslashes inside nested quotes ("how many backslashes do I need here") for cross-shell portability.
- About to add `if [[ "$(uname)" == "Darwin" ]]; then ... else ... fi` inside a script bigger than 50 lines.
- About to write `${var^^}`, `${var,,}`, `mapfile`, `readarray`, or other bash 4+ syntax in a script with no Homebrew-bash shebang.
- "It works on my machine" tied to a bash 4+ feature, a GNU-only flag, or a Linux-only path.
- Reaching for `cygpath`, `wslpath`, or any path-translation utility inside script logic.
- Writing the same logic three times because each platform needs its own variant.

## Bottom Line

When a shell script is heading into platform-quirks territory, the right move is not to patch the bash. It is to delete the bash and write Python. Python ships on every developer machine, has rich stdlib coverage for the operations that bite (file ops, paths, subprocess, JSON, HTTP, regex, collections), and sidesteps the entire platform-portability problem. Two hacks have been rediscovered enough to make this automatic: macOS bash 3.2 lacking `declare -A` and friends; Windows shell-quoting chaos across CMD / PowerShell / WSL / Git-Bash. Both have one answer: rewrite in Python.
