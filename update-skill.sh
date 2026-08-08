#!/usr/bin/env bash
# Refresh a third-party skill from its recorded upstream source.
#
# Usage:
#   ./update-skill.sh <skill-name>
#
# Reads .sources/<skill-name> which contains: <repo-url> <path-in-repo>
# Self-authored skills (no .sources/ entry) are not updatable from here.
set -euo pipefail

# Defaults (overridable by skills.conf)
AUTO_COMMIT=false
AUTO_PUSH=false
SHOW_DIFF=true
CONFIRM_OVERWRITE=true
VAULT_DIR=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "${script_dir}/skills.conf" ]] && source "${script_dir}/skills.conf"
VAULT_DIR="${VAULT_DIR:-$script_dir}"
cd "$VAULT_DIR"

# Refuse to run if the vault itself is in sparse-checkout mode
if [[ "$(git config --get core.sparseCheckout 2>/dev/null)" == "true" ]]; then
  echo "error: vault has sparse-checkout enabled. Run: git sparse-checkout disable" >&2
  exit 1
fi

name="${1:?usage: $0 <skill-name>}"
src_file=".sources/${name}"
[[ -f "$src_file" ]] || { echo "error: no source recorded at ${src_file}"; exit 1; }

# Pattern-1 skills with a non-git-dir check type (e.g. a skill file shipped inside a
# package repo, refreshed via PyPI) are not sparse-checkout targets. Redirect to
# check-pattern1.sh rather than failing on the directory/SKILL.md assumptions below.
if [[ -f "pattern1-skills.tsv" ]]; then
  p1ct="$(awk -F'\t' -v n="$name" '$1==n && $1 !~ /^#/ {print $2}' pattern1-skills.tsv)"
  if [[ "$p1ct" == "pypi" ]]; then
    echo "note: '${name}' is a pattern-1 ${p1ct} skill; refresh it with:" >&2
    echo "  ./check-pattern1.sh --refresh ${name}" >&2
    exit 0
  fi
fi

read -r repo path < "$src_file"
[[ -n "${repo:-}" && -n "${path:-}" ]] || \
  { echo "error: ${src_file} must contain '<repo-url> <path-in-repo>'"; exit 1; }

if [[ -d "./${name}" && "$CONFIRM_OVERWRITE" == "true" ]]; then
  printf "overwrite ./%s with fresh copy from %s? [y/N] " "$name" "$repo"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 --filter=blob:none --sparse "$repo" "$tmp"
( cd "$tmp" && git sparse-checkout set "$path" )

[[ -d "${tmp}/${path}" ]] || { echo "error: '${path}' not found in ${repo}"; exit 1; }
[[ -f "${tmp}/${path}/SKILL.md" ]] || { echo "error: no SKILL.md in '${path}'"; exit 1; }

rm -rf "./${name}"
mv "${tmp}/${path}" "./${name}"
echo "updated ${name} from ${repo}#${path}"

if [[ "$SHOW_DIFF" == "true" ]]; then
  git diff --stat -- "${name}" || true
fi

if [[ "$AUTO_COMMIT" == "true" ]]; then
  if ! git diff --quiet -- "${name}"; then
    git add "${name}"
    git commit -m "update ${name}"
    [[ "$AUTO_PUSH" == "true" ]] && git push
  else
    echo "no changes to commit"
  fi
fi
