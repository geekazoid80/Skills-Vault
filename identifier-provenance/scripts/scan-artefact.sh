#!/bin/sh
# Pre-ship scan for an artefact that names identifiers.
#
# Two jobs, deliberately different in strength:
#   1. FAIL CLOSED on an unresolved placeholder. Exit 2. Never advisory.
#   2. ENUMERATE every identifier-shaped literal, with line numbers and a count,
#      so the author resolves each one. The script cannot know whether an id is
#      real; stating the denominator is the point, because an id nobody noticed
#      is an id nobody resolved.
#
# POSIX sh, no dependencies, no network. Run it on the file BEFORE the call that
# publishes it, and on anything a subagent drafted for you.
#
# Usage: scan-artefact.sh FILE [FILE...]
#        scan-artefact.sh --selftest
set -u

PLACEHOLDER='<[A-Z][A-Z0-9_]*>|\bTBD\b|\bFIXME\b|\bXXX\b|\bTODO_[A-Z_]+\b'
# Deliberately broad: a long digit run, a hex object id, a #number reference, a
# uuid. Over-listing costs a glance; under-listing costs a phantom.
IDLIKE='\b[0-9]{9,}\b|\b[0-9a-f]{7,40}\b|#[0-9]{1,7}\b|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'

scan_one() {
  f=$1
  [ -f "$f" ] || { printf '  %s: NOT A FILE\n' "$f"; return 2; }
  rc=0
  ph=$(grep -nE "$PLACEHOLDER" "$f" 2>/dev/null)
  if [ -n "$ph" ]; then
    printf '  %s: UNRESOLVED PLACEHOLDER, do not ship\n' "$f"
    printf '%s\n' "$ph" | sed 's/^/      /'
    rc=2
  fi
  ids=$(grep -noE "$IDLIKE" "$f" 2>/dev/null)
  n=$(printf '%s' "$ids" | grep -c . 2>/dev/null || true)
  [ -z "$ids" ] && n=0
  printf '  %s: %s identifier-shaped literal(s) to resolve yourself\n' "$f" "$n"
  [ "$n" -gt 0 ] && printf '%s\n' "$ids" | sed 's/^/      /'
  return $rc
}

selftest() {
  d=$(mktemp -d) || exit 3
  printf 'TRACKING: <TRACKING_ID>\nsee #42\n' > "$d/bad"
  printf 'TRACKING: 1234567890123456\nmerged as abc1234\n' > "$d/ids"
  printf 'nothing to see here\n' > "$d/clean"
  fail=0
  scan_one "$d/bad" >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL: placeholder not caught"; fail=1; }
  scan_one "$d/ids" >/dev/null 2>&1; [ $? -eq 0 ] || { echo "FAIL: ids alone must not fail closed"; fail=1; }
  scan_one "$d/clean" >/dev/null 2>&1; [ $? -eq 0 ] || { echo "FAIL: clean file must pass"; fail=1; }
  # the control that makes the count meaningful: a file with ids must report >0,
  # and a clean file must report 0. A scanner that reports 0 for everything looks
  # identical to a working one.
  scan_one "$d/ids"   2>/dev/null | grep -q '2 identifier-shaped' || { echo "FAIL: expected 2 ids"; fail=1; }
  scan_one "$d/clean" 2>/dev/null | grep -q '0 identifier-shaped' || { echo "FAIL: expected 0 ids"; fail=1; }
  rm -rf "$d"
  [ "$fail" -eq 0 ] && { echo "selftest: all checks passed"; return 0; }
  echo "SELFTEST FAILED"; return 1
}

[ $# -eq 0 ] && { echo "usage: $0 FILE [FILE...] | --selftest" >&2; exit 3; }
[ "$1" = "--selftest" ] && { selftest; exit $?; }

worst=0
for f in "$@"; do
  scan_one "$f" || worst=$?
done
[ "$worst" -eq 0 ] && echo "scan: no unresolved placeholder; resolve the listed identifiers yourself"
exit "$worst"
