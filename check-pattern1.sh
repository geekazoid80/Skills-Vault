#!/usr/bin/env bash
# Check (and optionally refresh) pattern-1 adopt-as-is skills against their upstream version.
#
# Pattern-1 skills are verbatim copies of an upstream skill (no local fold), tracked in
# pattern1-skills.tsv. Their "update" is a version check: has upstream shipped a newer
# release? If so, re-pull verbatim. This is distinct from the merged-skills-registry
# content-drift audit, which diffs upstream prose against a local fold.
#
# Usage:
#   ./check-pattern1.sh                 # report version drift for all pattern-1 skills (read-only)
#   ./check-pattern1.sh --refresh NAME  # refresh one skill from its upstream
#
# Exit status (default mode): 0 = all current, 1 = at least one drift or unresolved.
set -Eeuo pipefail

# Defaults (overridable by skills.conf), matching the sibling scripts.
AUTO_COMMIT=false
AUTO_PUSH=false
SHOW_DIFF=true
VAULT_DIR=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "${script_dir}/skills.conf" ]] && source "${script_dir}/skills.conf"
VAULT_DIR="${VAULT_DIR:-$script_dir}"
cd "$VAULT_DIR"

MANIFEST="pattern1-skills.tsv"
[[ -f "$MANIFEST" ]] || { echo "error: ${MANIFEST} not found in ${VAULT_DIR}" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found on PATH" >&2; exit 1; }; }

# Emit data rows only (skip comments, blank lines, and the header row).
read_manifest() { awk -F'\t' 'NF>=6 && $1!="name" && $1 !~ /^#/' "$MANIFEST"; }

# Resolve the latest upstream version for a given check_type.
latest_version() {
  local check_type="$1" upstream_id="$2"
  case "$check_type" in
    pypi)
      need curl; need python3
      curl -fsSL "https://pypi.org/pypi/${upstream_id}/json" \
        | python3 -c 'import sys, json; print(json.load(sys.stdin)["info"]["version"])'
      ;;
    git-dir)
      need git
      git ls-remote --tags --refs "$upstream_id" 2>/dev/null \
        | awk -F/ '{print $NF}' | sort -V | tail -1
      ;;
    *)
      echo "error: unknown check_type '${check_type}'" >&2
      return 1
      ;;
  esac
}

refresh_one() {
  local name="$1" row _ check_type upstream_id version_file repo repo_path
  row="$(read_manifest | awk -F'\t' -v n="$name" '$1==n')"
  [[ -n "$row" ]] || { echo "error: '${name}' is not a pattern-1 skill in ${MANIFEST}" >&2; exit 1; }
  IFS=$'\t' read -r _ check_type upstream_id version_file repo repo_path <<<"$row"

  case "$check_type" in
    pypi)
      need uv; need git; need curl; need python3
      echo "upgrading package '${upstream_id}' via uv ..."
      uv tool upgrade "$upstream_id" 2>&1 | tail -3 || true
      local tmp; tmp="$(mktemp -d)"
      # shellcheck disable=SC2064
      trap "rm -rf '${tmp}'" RETURN
      git clone --depth 1 -q "$repo" "$tmp"
      [[ -f "${tmp}/${repo_path}" ]] || { echo "error: '${repo_path}' not found in ${repo}" >&2; return 1; }
      cp "${tmp}/${repo_path}" "./${name}/SKILL.md"
      local newv; newv="$(latest_version "$check_type" "$upstream_id")"
      [[ -n "$newv" ]] || { echo "error: could not resolve new version for ${upstream_id}" >&2; return 1; }
      printf '%s\n' "$newv" > "./${version_file}"
      echo "refreshed ${name}: SKILL.md re-copied from ${repo}#${repo_path}, pin -> ${newv}"
      ;;
    git-dir)
      echo "git-dir refresh delegates to update-skill.sh ..."
      ./update-skill.sh "$name"
      return $?
      ;;
    *)
      echo "error: unknown check_type '${check_type}'" >&2
      return 1
      ;;
  esac

  [[ "$SHOW_DIFF" == "true" ]] && { git diff --stat -- "$name" "$version_file" || true; }
  if [[ "$AUTO_COMMIT" == "true" ]] && ! git diff --quiet -- "$name" "$version_file"; then
    git add "$name" "$version_file"
    git commit -m "refresh ${name} from upstream"
    [[ "$AUTO_PUSH" == "true" ]] && git push
  fi
}

if [[ "${1:-}" == "--refresh" ]]; then
  refresh_one "${2:?usage: $0 --refresh <skill-name>}"
  exit 0
fi

# Default mode: report version drift (read-only; safe for cron).
drift=0
count=0
while IFS=$'\t' read -r name check_type upstream_id version_file _repo _repo_path; do
  count=$((count + 1))
  pinned="$(tr -d '[:space:]' < "./${version_file}" 2>/dev/null || true)"
  latest="$(latest_version "$check_type" "$upstream_id" 2>/dev/null || true)"
  if [[ -z "$latest" ]]; then
    printf '  %-22s UNKNOWN (could not resolve latest %s for %s)\n' "$name" "$check_type" "$upstream_id"
    drift=1
  elif [[ "$pinned" == "$latest" ]]; then
    printf '  %-22s CURRENT (pinned %s)\n' "$name" "$pinned"
  else
    printf '  %-22s DRIFT (pinned %s, latest %s)\n' "$name" "${pinned:-none}" "$latest"
    drift=1
  fi
done < <(read_manifest)

[[ "$count" -eq 0 ]] && echo "  (no pattern-1 skills registered)"
exit "$drift"
