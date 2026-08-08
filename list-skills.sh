#!/usr/bin/env bash
# List skills installed in this vault, with their sources.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR=""
# shellcheck source=/dev/null
[[ -f "${script_dir}/skills.conf" ]] && source "${script_dir}/skills.conf"
VAULT_DIR="${VAULT_DIR:-$script_dir}"
cd "$VAULT_DIR"

shopt -s nullglob
found=0
for d in */; do
  name="${d%/}"
  [[ "$name" == ".sources" || "$name" == ".git" ]] && continue
  [[ -f "${d}SKILL.md" ]] || continue
  found=1
  tag=""
  if [[ -f "pattern1-skills.tsv" ]]; then
    p1row="$(awk -F'\t' -v n="$name" '$1==n && $1 !~ /^#/' pattern1-skills.tsv)"
    if [[ -n "$p1row" ]]; then
      p1vf="$(printf '%s' "$p1row" | cut -f4)"
      p1pin="$(tr -d '[:space:]' < "$p1vf" 2>/dev/null || true)"
      tag=" [pattern-1: pinned ${p1pin:-unknown}]"
    fi
  fi
  if [[ -f ".sources/${name}" ]]; then
    src="$(cat ".sources/${name}")"
    printf "  %-30s%s  %s\n" "$name" "$tag" "$src"
  else
    printf "  %-30s%s  (self-authored)\n" "$name" "$tag"
  fi
done
[[ "$found" == "0" ]] && echo "  (no skills installed)"
