#!/bin/sh
# macOS Platform SSO state for the current user.
#
# READ ONLY: this script only reads state and changes nothing. Prints app-sso platform -s (a documented command whose output format is not documented, so it is shown and not judged) and checks whether an Extensible SSO payload is installed.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Run as the logged-in user for the state and with sudo for the payload check: under sudo it asks for the state of $SUDO_USER. Either way one of the two checks is reported as skipped (a warning).
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sh psso-state.sh; sudo sh psso-state.sh
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

echo 'macOS Platform SSO state (read only, current user)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo 'Note: the output of app-sso is not a documented format and may contain account names; do not paste it into tickets unreviewed.'

check_version() {
    need sw_vers || return 0
    capture ver sw_vers -productVersion || { add_finding Warning 'sw_vers failed'; return 0; }
    major=${ver%%.*}
    note "macOS $ver"
    is_uint "$major" || { add_finding Warning "could not parse the macOS version '$ver'"; return 0; }
    if [ "$major" -lt 13 ]; then add_finding Critical "Platform SSO needs macOS 13 or later; this Mac runs $ver"; fi
    return 0
}
check_state() {
    need app-sso || return 0
    if is_root; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
            note "Running as root: asking for the state of user $SUDO_USER (sudo -u)"
            capture out sudo -u "$SUDO_USER" app-sso platform -s
        else
            add_finding Warning 'Running as root without SUDO_USER, so the logged-in user state was not read; run the script as that user'
            return 0
        fi
    else
        capture out app-sso platform -s
    fi
    if [ $? -ne 0 ]; then add_finding Warning "app-sso platform -s failed: $out"; return 0; fi
    if [ -z "$out" ]; then add_finding Warning 'app-sso platform -s returned nothing; Platform SSO may not be configured for this user'; return 0; fi
    printf '%s\n' "$out" | head -60 | sed 's/^/  /'
    note 'Registration is not judged here: Apple documents app-sso platform -s as diagnostic only, so read the output above.'
    return 0
}
check_profile() {
    need profiles || return 0
    is_root || { add_finding Warning 'The installed payload was not checked: profiles show -type configuration needs root'; return 0; }
    capture out profiles show -type configuration
    if [ $? -ne 0 ]; then add_finding Warning "profiles show -type configuration failed: $out"; return 0; fi
    if printf '%s\n' "$out" | grep -q 'com.apple.extensiblesso'; then note 'An Extensible SSO configuration profile payload is installed'; else add_finding Warning 'No com.apple.extensiblesso payload is installed (a declarative extensible-sso configuration, macOS 27 and later, would not show here)'; fi
    return 0
}

section '1. PLATFORM';          run_check Platform check_version
section '2. PLATFORM SSO STATE'; run_check 'Platform SSO state' check_state
section '3. CONFIGURATION';     run_check Configuration check_profile

complete_report
exit "$EXIT_CODE"
