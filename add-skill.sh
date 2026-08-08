#!/usr/bin/env bash
# Add a third-party skill from a git repo and record its source.
#
# Usage:
#   ./add-skill.sh <repo> <path-in-repo> [local-name]
#   ./add-skill.sh <repo> --list
#
# <repo> accepts:
#   owner/name                          (GitHub shorthand)
#   https://github.com/owner/name
#   git@github.com:owner/name.git
#   any git URL
#
# Examples:
#   ./add-skill.sh vercel-labs/skills --list
#   ./add-skill.sh vercel-labs/skills skills/find-skills
#   ./add-skill.sh obra/superpowers skills/verification-before-completion
#   ./add-skill.sh obra/superpowers skills/test-driven-development my-tdd
set -euo pipefail

# Defaults (overridable by skills.conf)
AUTO_COMMIT=false
AUTO_PUSH=false
VAULT_DIR=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${script_dir}/skills.conf" ]] && source "${script_dir}/skills.conf"
VAULT_DIR="${VAULT_DIR:-$script_dir}"
cd "$VAULT_DIR"

# Refuse to run if the vault itself is in sparse-checkout mode
if [[ "$(git config --get core.sparseCheckout 2>/dev/null)" == "true" ]]; then
  echo "error: vault has sparse-checkout enabled. Run: git sparse-checkout disable" >&2
  exit 1
fi

# Normalize <repo>: turn "owner/name" into a full GitHub URL
normalize_repo() {
  local r="$1"
  if [[ "$r" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "https://github.com/${r}"
  else
    echo "$r"
  fi
}

repo_in="${1:?usage: $0 <repo> <path-in-repo> [local-name]   |   $0 <repo> --list}"
arg2="${2:?usage: $0 <repo> <path-in-repo> [local-name]   |   $0 <repo> --list}"
repo="$(normalize_repo "$repo_in")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── List mode ─────────────────────────────────────────────────────────────
if [[ "$arg2" == "--list" || "$arg2" == "-l" ]]; then
  echo "scanning ${repo} for skills..."
  git clone --depth 1 --filter=blob:none "$repo" "$tmp" >/dev/null 2>&1
  ( cd "$tmp" && find . -name SKILL.md -not -path "./.git/*" \
      | sed 's|^\./||; s|/SKILL.md$||' | sort )
  exit 0
fi

# ── Add mode ──────────────────────────────────────────────────────────────
path="$arg2"
name="${3:-$(basename "$path")}"

[[ -e "./${name}" ]] && { echo "error: ./${name} already exists in vault"; exit 1; }

git clone --depth 1 --filter=blob:none --sparse "$repo" "$tmp"
( cd "$tmp" && git sparse-checkout set "$path" )

[[ -d "${tmp}/${path}" ]] || { echo "error: '${path}' not found in ${repo}"; exit 1; }
[[ -f "${tmp}/${path}/SKILL.md" ]] || { echo "error: no SKILL.md in '${path}'"; exit 1; }

mv "${tmp}/${path}" "./${name}"
mkdir -p .sources
echo "${repo} ${path}" > ".sources/${name}"
echo "added ${name} from ${repo}#${path}"

if [[ "$AUTO_COMMIT" == "true" ]]; then
  git add "${name}" ".sources/${name}"
  git commit -m "add ${name}"
  [[ "$AUTO_PUSH" == "true" ]] && git push
else
  echo "next: git add ${name} .sources/${name} && git commit -m 'add ${name}' && git push"
fi
