#!/usr/bin/env bash
#
# Build the generic skill BASE as a farm of per-skill symlinks.
#
# Part A of the two-part skills farm. Self-contained and overlay-agnostic: it
# knows nothing about any downstream (private/overlay) vault. A machine with no
# overlay vault runs this directly for a generic-only farm; bootstrap.sh does.
#
# A "skill" is any top-level directory in the vault that contains a SKILL.md.
# Non-skill top-level files/dirs (READMEs, scripts, .sources) are ignored.
#
# Exit codes (shared across the farm scripts):
#   0  success
#   2  the base vault directory is missing
#   3  the base vault ingested zero skills (wrong clone / empty vault)
#
# Env:
#   SKILLS_FARM        farm directory to build (default ~/.claude/skills)
#   SKILLS_VAULT_BASE  source vault (default: the directory holding this script)

set -euo pipefail

FARM="${SKILLS_FARM:-$HOME/.claude/skills}"
VAULT="${SKILLS_VAULT_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# 1. Validate the SOURCE before destroying anything (validate-before-destroy):
#    a missing or empty base vault must never wipe a working farm.
if [ ! -d "$VAULT" ]; then
  echo "error: base vault not found at $VAULT" >&2
  echo "Clone the public vault there, or set SKILLS_VAULT_BASE to an existing clone:" >&2
  echo "  git clone git@github.com:geekazoid80/Skills-Vault.git $VAULT" >&2
  exit 2
fi

skills=()
for d in "$VAULT"/*/; do
  d="${d%/}"
  [ -f "$d/SKILL.md" ] && skills+=("$d")
done

n=${#skills[@]}
if [ "$n" -eq 0 ]; then
  echo "error: base vault $VAULT ingested 0 skills (no */SKILL.md). Wrong clone?" >&2
  exit 3
fi

# 2. Only now reset the farm and lay down the base layer. Idempotent: each run
#    rebuilds from scratch. Removing the farm deletes only symlinks, never the
#    vault contents (symlinks do not recurse into their targets).
mkdir -p "$(dirname "$FARM")"
rm -rf "$FARM"
mkdir -p "$FARM"

for d in "${skills[@]}"; do
  ln -s "$d" "$FARM/$(basename "$d")"
done

echo "base: linked $n generic skills into $FARM"
