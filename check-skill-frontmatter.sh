#!/usr/bin/env bash
#
# Verify that every SKILL.md frontmatter in a vault parses as YAML.
#
# Part of the two-part skills farm, and deliberately standalone so either vault
# can run it. The base builder runs it on the generic vault; the private overlay
# builder runs this same script against the overlay vault, so there is one
# implementation rather than a copy per repo.
#
# Why this exists as a BUILD gate rather than a checklist item: the authoring
# skill already carries a yaml.safe_load check, but that only fires when a
# session sets out to author a skill. A pull request that merely edits an
# existing description never takes that path, so nothing catches a description
# being re-emitted as a plain scalar. That is not hypothetical: the same fault
# was fixed once, regressed across four subsequent pull requests within two
# days, and was fixed again. A gate on the build fires for everyone, every
# rebuild, regardless of how the file was edited.
#
# The fault it catches: an unquoted (plain) YAML scalar containing a colon
# followed by a space. YAML reads that as a nested mapping key and aborts the
# whole document with "mapping values are not allowed here". Nothing else
# reports it. The harness tolerates such a file, a field-presence eyeball passes,
# and a dash scan passes, so the skill silently stops loading under any stricter
# reader.
#
# Exit codes (shared across the farm scripts):
#   0  every frontmatter parses
#   2  the vault directory is missing
#   7  one or more frontmatters do not parse
#
# Usage: check-skill-frontmatter.sh [vault-dir]   (default: this script's dir)

set -euo pipefail

VAULT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LABEL="${2:-$(basename "$VAULT")}"

if [ ! -d "$VAULT" ]; then
  echo "error: vault not found at $VAULT" >&2
  exit 2
fi

# Prefer a real YAML parse. Fall back to a targeted scan for the one fault class
# that actually recurs, so a machine without PyYAML still gets a gate rather than
# a silent skip. Which mode ran is always printed, so a weaker check is visible.
if python3 -c 'import yaml' >/dev/null 2>&1; then
  mode="strict YAML parse"
  bad="$(python3 - "$VAULT" <<'PY'
import glob, os, sys, yaml
vault = sys.argv[1]
for path in sorted(glob.glob(os.path.join(vault, "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(path))
    text = open(path, encoding="utf-8").read()
    parts = text.split("---", 2)
    if len(parts) < 3:
        print(f"{name}: no frontmatter block")
        continue
    try:
        yaml.safe_load(parts[1])
    except Exception as exc:
        detail = str(exc).splitlines()[0]
        print(f"{name}: {type(exc).__name__}: {detail}")
PY
)"
else
  mode="fallback scan, PyYAML unavailable"
  bad=""
  for file in "$VAULT"/*/SKILL.md; do
    [ -f "$file" ] || continue
    name="$(basename "$(dirname "$file")")"
    line="$(grep -m1 '^description:' "$file" || true)"
    [ -n "$line" ] || continue
    value="${line#description:}"
    value="${value# }"
    case "$value" in
      '"'*|"'"*) ;;                                     # already a quoted scalar
      *": "*) bad="${bad}${name}: unquoted description contains a colon-space"$'\n' ;;
    esac
  done
  bad="$(printf '%s' "$bad")"
fi

count=$(find "$VAULT" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')

if [ -n "$bad" ]; then
  echo "error: SKILL.md frontmatter does not parse in $LABEL ($mode):" >&2
  echo "$bad" | sed 's/^/  /' >&2
  echo "" >&2
  echo "Fix: re-emit the description: as a DOUBLE-QUOTED scalar, escaping every" >&2
  echo "backslash and double quote in the value, then assert the round trip, that" >&2
  echo "the frontmatter parses AND the loaded value equals the original raw text." >&2
  echo "Only the quoting should change; no wording should move." >&2
  exit 7
fi

echo "frontmatter: $count/$count SKILL.md parse in $LABEL ($mode)"
