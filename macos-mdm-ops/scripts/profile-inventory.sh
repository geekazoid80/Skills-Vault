#!/bin/sh
# macOS configuration profile inventory.
#
# READ ONLY: this script only reads state and changes nothing. Lists installed configuration profiles, the com.apple.* strings in them (as root), managed preference domains, and legacy keys that macOS 27 removed.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Run as root for device-level profiles (without root it warns that they were not checked). Environment: MANAGED_PREFS.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sudo sh profile-inventory.sh
#
# shellcheck disable=SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops.)

set -u
LC_ALL=C
export LC_ALL
EXIT_CODE=2   # any path that does not reach a verdict exits 2
FINDINGS=$(mktemp "${TMPDIR:-/tmp}/macos-skill.XXXXXX") || { echo "cannot create a temporary file" >&2; exit 2; }
trap 'rm -f "$FINDINGS"' EXIT
trap 'exit 2' HUP INT TERM

add_finding() { printf '%s|%s\n' "$1" "$2" >> "$FINDINGS"; }
section() { printf '\n%s\n%s\n' "$1" '------------------------------------------------------------------------'; }
note() { printf '  %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" = "0" ]; }
# need CMD: a missing command is a warning, never a pass.
need() { if have "$1"; then return 0; fi; add_finding Warning "$1 not found; the related checks were skipped"; return 1; }
# capture VAR CMD ARGS...: store combined output in VAR and return the command's exit status.
capture() { _cap_var=$1; shift; _cap_out=$("$@" 2>&1); _cap_rc=$?; eval "$_cap_var=\$_cap_out"; return "$_cap_rc"; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
# run_check NAME FUNCTION: a check that returns non-zero is reported as a warning, never as a clean pass.
run_check() { _rc_name=$1; _rc_fn=$2; "$_rc_fn"; _rc_status=$?; if [ "$_rc_status" -ne 0 ]; then add_finding Warning "$_rc_name could not be completed (status $_rc_status)"; fi; }
complete_report() {
    section SUMMARY
    _crit=$(grep -c '^Critical|' "$FINDINGS" 2>/dev/null); _warn=$(grep -c '^Warning|' "$FINDINGS" 2>/dev/null)
    _crit=${_crit:-0}; _warn=${_warn:-0}
    if [ "$_crit" -eq 0 ] && [ "$_warn" -eq 0 ]; then
        echo 'No warnings or critical findings.'
        EXIT_CODE=0
        return 0
    fi
    grep '^Critical|' "$FINDINGS" | sed 's/^Critical|/  CRITICAL: /'
    grep '^Warning|' "$FINDINGS" | sed 's/^Warning|/  WARNING:  /'
    if [ "$_crit" -gt 0 ]; then EXIT_CODE=2; else EXIT_CODE=1; fi
}

MANAGED_PREFS=${MANAGED_PREFS:-/Library/Managed Preferences}

echo 'macOS configuration profile inventory (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

MAJOR=''
check_version() {
    need sw_vers || return 0
    capture ver sw_vers -productVersion || { add_finding Warning 'sw_vers failed'; return 0; }
    MAJOR=${ver%%.*}
    is_uint "$MAJOR" || { add_finding Warning "could not parse the macOS version '$ver'"; MAJOR=''; return 0; }
    note "macOS $ver"
    return 0
}
check_profiles() {
    need profiles || return 0
    capture out profiles list -type configuration
    if [ $? -ne 0 ]; then add_finding Warning "profiles list -type configuration failed: $out"; return 0; fi
    case "$out" in
        *"no configuration profiles"*) note 'No configuration profiles are installed in this domain'; return 0 ;;
    esac
    n=$(printf '%s\n' "$out" | grep -c 'profileIdentifier')
    if [ "$n" -eq 0 ]; then add_finding Warning "profiles list returned output with no profile identifiers: $out"; return 0; fi
    note "$n configuration profile(s) listed ($(is_root && echo 'device domain' || echo 'current user domain; run as root for device profiles'))"
    printf '%s\n' "$out" | grep 'profileIdentifier' | sed 's/^ *//; s/^/  /'
    return 0
}
check_payload_types() {
    need profiles || return 0
    is_root || { add_finding Warning 'Payload types were not checked: profiles show -type configuration needs root'; return 0; }
    capture out profiles show -type configuration
    if [ $? -ne 0 ]; then add_finding Warning "profiles show -type configuration failed: $out"; return 0; fi
    types=$(printf '%s\n' "$out" | grep -o 'com\.apple\.[A-Za-z0-9_.()-]*' | sort | uniq -c | sort -rn)
    if [ -z "$types" ]; then add_finding Warning 'No com.apple.* identifiers were found in the profiles show output'; return 0; fi
    note 'Counts below are of com.apple.* strings in the output, which include profile identifiers as well as payload types.'
    printf '%s\n' "$types" | head -40 | sed 's/^/  /'
    if printf '%s\n' "$types" | grep -q 'com.apple.extensiblesso'; then note 'An Extensible SSO string is present'; fi
    if [ -n "$MAJOR" ] && [ "$MAJOR" -ge 27 ]; then
        if printf '%s\n' "$types" | grep -q 'com\.apple\.SoftwareUpdate'; then add_finding Warning 'The string com.apple.SoftwareUpdate appears; Apple removed that payload in macOS 27, so it may be ignored (schema: apple/device-management)'; fi
        if printf '%s\n' "$out" | grep -q 'enforcedSoftwareUpdate\|forceDelayedSoftwareUpdates'; then add_finding Warning 'A software update deferral or enforcement key (enforcedSoftwareUpdate* or forceDelayedSoftwareUpdates) appears in a profile; Apple removed those in macOS 27, so they may be ignored'; fi
    fi
    return 0
}
check_managed_prefs() {
    if [ ! -d "$MANAGED_PREFS" ]; then note "$MANAGED_PREFS: not present (no managed preferences)"; return 0; fi
    count=0
    for f in "$MANAGED_PREFS"/*.plist; do
        [ -e "$f" ] || continue
        count=$((count + 1))
        note "$(basename "$f")"
    done
    note "$count managed preference domain(s) at the device level"
    return 0
}

if ! is_root; then add_finding Warning 'Not running as root: only the current user profiles were listed, and the device profiles and payload types were not checked'; fi
section '1. PLATFORM';                   run_check Platform check_version
section '2. INSTALLED PROFILES';         run_check Profiles check_profiles
section '3. PAYLOAD TYPES';              run_check 'Payload types' check_payload_types
section '4. MANAGED PREFERENCES';        run_check 'Managed preferences' check_managed_prefs

complete_report
exit "$EXIT_CODE"
