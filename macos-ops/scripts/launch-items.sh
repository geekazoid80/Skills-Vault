#!/bin/sh
# macOS launch items and system extensions.
#
# READ ONLY: this script only reads state and changes nothing. Reads third-party LaunchDaemons and LaunchAgents property lists for missing programs and unsafe ownership or permissions, and lists the state of system extensions.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Reads files and queries system extensions; no job is loaded or unloaded. Environment: SYSTEM_LAUNCH_DIRS, USER_LAUNCH_DIR.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sh launch-items.sh
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

echo 'macOS launch items and system extensions (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# One property from a plist; empty output means the key is absent.
plist_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
check_dir() {
    dir=$1; kind=$2
    if [ ! -d "$dir" ]; then note "$dir: not present"; return 0; fi
    count=0
    for f in "$dir"/*.plist; do
        [ -e "$f" ] || continue
        count=$((count + 1))
        label=$(plist_get "$f" Label)
        prog=$(plist_get "$f" Program)
        [ -n "$prog" ] || prog=$(plist_get "$f" ProgramArguments.0)
        if [ -z "$label" ] && [ -z "$prog" ]; then add_finding Warning "$f could not be read as a launchd property list"; continue; fi
        note "$(basename "$f"): label=${label:-?} program=${prog:-?}"
        if [ -z "$prog" ]; then add_finding Warning "$f names no Program or ProgramArguments"
        elif [ ! -e "$prog" ]; then add_finding Warning "$f points at $prog, which does not exist"
        fi
        if [ "$kind" = system ]; then
            perm=$(stat -f '%Su %Sg %Mp%Lp' "$f" 2>/dev/null)
            owner=${perm%% *}
            mode=${perm##* }
            if [ "$owner" != root ]; then add_finding Warning "$f is owned by '$owner'; launchd expects root for system items"; fi
            case "$mode" in *[2367]) add_finding Warning "$f is writable by others (mode $mode)" ;; esac
            case "$mode" in *[2367]?) add_finding Warning "$f is writable by its group (mode $mode)" ;; esac
        fi
    done
    note "$dir: $count item(s)"
    return 0
}
check_launch() {
    need plutil || return 0
    # shellcheck disable=SC2086
    for d in ${SYSTEM_LAUNCH_DIRS:-/Library/LaunchDaemons /Library/LaunchAgents}; do check_dir "$d" system; done
    if [ -z "${USER_LAUNCH_DIR:-${HOME:-}}" ]; then add_finding Warning "HOME is not set, so the user LaunchAgents folder was not checked"; else check_dir "${USER_LAUNCH_DIR:-${HOME:-}/Library/LaunchAgents}" user; fi
    return 0
}
check_extensions() {
    need systemextensionsctl || return 0
    capture ext systemextensionsctl list
    if [ $? -ne 0 ]; then add_finding Warning "systemextensionsctl list failed: $ext"; return 0; fi
    list=$(printf '%s\n' "$ext" | grep '\[' | grep -v 'teamID')
    printf '%s\n' "$list" | sed 's/^/  /'
    bad=$(printf '%s\n' "$list" | grep -v 'activated enabled' | grep -c '.')
    if [ "$bad" -gt 0 ]; then add_finding Warning "$bad system extension(s) are not in the 'activated enabled' state"; fi
    return 0
}

section '1. LAUNCHD PROPERTY LISTS (third-party locations)'; run_check 'Launch items' check_launch
section '2. SYSTEM EXTENSIONS';   run_check 'System extensions' check_extensions

complete_report
exit "$EXIT_CODE"
