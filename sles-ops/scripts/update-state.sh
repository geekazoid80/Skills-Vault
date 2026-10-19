#!/bin/sh
# SLES registration and update state.
#
# READ ONLY: this script only reads state and changes nothing. Covers registration (SUSEConnect, as root; it contacts SCC or RMT and the output is never printed because it contains the registration code), enabled repositories, patches (zypper patch-check exit codes), reboot need (zypper needs-rebooting), processes using deleted files (zypper ps) and package locks. zypper may refresh repository metadata, which contacts the repository servers and writes /var/cache/zypp.
# POSIX sh (/bin/sh is bash on SLES). Run as root for the complete picture. Environment: ZYPPER_NO_REFRESH (1 uses cached data).
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings
# or an invalid setting (the message is on standard error).
# A required command that is missing, fails or returns nothing is a warning, never a pass; an optional
# component that is not installed (for example snapd, sshd, cloud-init) is reported as information.
#
# Not run on a live host in this vault: it is checked with shellcheck and exercised against stub commands
# only, so the output formats it parses are taken from manual pages and vendor documentation. Try it on a
# non-critical host first.
#
# Example: sudo sh update-state.sh
#
# shellcheck disable=SC2016,SC2034,SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops;
#  SC2016: where used, single-quoted format strings contain a literal ${...};
#  SC2034: release-phase table values are read through eval.)

set -u
LC_ALL=C
export LC_ALL
# sbin directories hold ufw, sshd, aa-status and similar, and are often missing from a normal user's PATH.
# SBIN_PATH exists so a test can set it empty; leave it unset in normal use.
PATH="$PATH${SBIN_PATH-:/usr/local/sbin:/usr/sbin:/sbin}"
export PATH
EXIT_CODE=2   # any path that does not reach a verdict exits 2
FINDINGS=$(mktemp "${TMPDIR:-/tmp}/linux-skill.XXXXXX") || { echo "cannot create a temporary file" >&2; exit 2; }
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
    if ! is_uint "$_crit" || ! is_uint "$_warn"; then echo 'internal error: the findings could not be counted' >&2; EXIT_CODE=2; return 0; fi
    if [ "$_crit" -eq 0 ] && [ "$_warn" -eq 0 ]; then
        echo 'No warnings or critical findings.'
        EXIT_CODE=0
        return 0
    fi
    grep '^Critical|' "$FINDINGS" | sed 's/^Critical|/  CRITICAL: /'
    grep '^Warning|' "$FINDINGS" | sed 's/^Warning|/  WARNING:  /'
    if [ "$_crit" -gt 0 ]; then EXIT_CODE=2; else EXIT_CODE=1; fi
}
# validate_uint NAME...: exit 2 with a message when a numeric setting is not a whole number.
validate_uint() { for _v in "$@"; do eval "_val=\$$_v"; if ! is_uint "$_val" || [ "${#_val}" -gt 9 ]; then echo "$_v must be a whole number of at most 9 digits (got '$_val')" >&2; exit 2; fi; done; }
# validate_pct NAME...: a whole number from 1 to 100.
validate_pct() { validate_uint "$@"; for _v in "$@"; do eval "_val=\$$_v"; if [ "$_val" -lt 1 ] || [ "$_val" -gt 100 ]; then echo "$_v must be between 1 and 100 (got '$_val')" >&2; exit 2; fi; done; }
# validate_flag NAME...: exactly 0 or 1.
validate_flag() { for _v in "$@"; do eval "_val=\$$_v"; case "$_val" in 0|1) : ;; *) echo "$_v must be 0 or 1 (got '$_val')" >&2; exit 2 ;; esac; done; }
# validate_decimal NAME...: a non-negative number such as 1 or 0.5.
validate_decimal() { for _v in "$@"; do eval "_val=\$$_v"; case "$_val" in ''|.|*[!0-9.]*|*.*.*) echo "$_v must be a non-negative number (got '$_val')" >&2; exit 2 ;; esac; done; }
# in_list WORD LIST: is WORD one of the newline-separated entries of LIST?
in_list() { printf '%s\n' "$2" | grep -Fqx -- "$1"; }
# osr KEY: value of KEY in the os-release file named by $OS_RELEASE, without quotes.
osr() { sed -n "s/^$1=//p" "$OS_RELEASE" | head -1 | tr -d '"'; }
# first_lines N TEXT: the first N lines of TEXT, indented, for a finding's detail.
first_lines() { printf '%s\n' "$2" | head -n "$1" | sed 's#://[^/@ ]*@#://[redacted]@#g' | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
# in_words WORD WORDS: is WORD one of the space-separated entries of WORDS?
in_words() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

ZYPPER_NO_REFRESH=${ZYPPER_NO_REFRESH:-0}
validate_flag ZYPPER_NO_REFRESH

# zy: zypper without prompts; with ZYPPER_NO_REFRESH=1 it does not auto-refresh repositories.
zy() { if [ "$ZYPPER_NO_REFRESH" = 1 ]; then zypper --non-interactive --quiet --no-refresh "$@"; else zypper --non-interactive --quiet "$@"; fi; }

echo 'SLES update state (does not change configuration)'
printf 'Generated: %s (UTC); zypper may refresh repository metadata (contacts the repository servers and writes /var/cache/zypp): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$( [ "$ZYPPER_NO_REFRESH" = 1 ] && echo 'disabled by ZYPPER_NO_REFRESH=1, so results use cached data' || echo 'allowed')"

check_registration() {
    need SUSEConnect || return 0
    is_root || { add_finding Warning 'SUSEConnect --status needs root; the registration state was not checked'; return 0; }
    capture rs SUSEConnect --status
    if [ $? -ne 0 ]; then add_finding Warning 'SUSEConnect --status failed (output withheld: it can contain registration codes)'; return 0; fi
    # Only extracted status words are printed, never the raw output, which includes the registration code.
    st=$(printf '%s' "$rs" | grep -o '"status": *"[A-Za-z ]*"' | sed 's/.*: *"\(.*\)"/\1/' | sort | uniq -c | tr '\n' ' ')
    sub=$(printf '%s' "$rs" | grep -o '"subscription_status": *"[A-Za-z ]*"' | sed 's/.*: *"\(.*\)"/\1/' | sort -u | tr '\n' ' ')
    note "Registration status words:${st:- none} subscription status:${sub:- none}"
    if printf '%s' "$rs" | grep -q '"status": *"Not Registered"'; then add_finding Warning 'SUSEConnect reports a product as Not Registered, so it cannot receive updates'; return 0; fi
    if ! printf '%s' "$rs" | grep -q '"status": *"Registered"'; then add_finding Warning 'could not read a Registered status from SUSEConnect --status (output withheld)'; return 0; fi
    if [ -z "${sub# }" ]; then add_finding Warning 'no subscription_status was reported, so expiry could not be checked'
    else
        case " $sub " in
            *' ACTIVE '*) : ;;
            *) add_finding Warning "SUSEConnect reports subscription status:${sub} (not ACTIVE); the subscription may be expired or about to expire" ;;
        esac
    fi
    return 0
}
check_repos() {
    need zypper || return 0
    capture lr zy lr -E
    lr_rc=$?
    case "$lr_rc" in
        0) : ;;
        6) add_finding Warning 'zypper reports no repositories are defined (exit 6)'; return 0 ;;
        *) add_finding Warning "zypper lr failed with exit $lr_rc: $(first_lines 3 "$lr")"; return 0 ;;
    esac
    n=$(printf '%s\n' "$lr" | grep -c '^[[:space:]]*[0-9][0-9]*[[:space:]]*|')
    if [ "$n" -lt 1 ]; then add_finding Warning "zypper lr -E listed no enabled repositories: $(first_lines 2 "$lr")"; else note "$n enabled repositor(ies)"; fi
    return 0
}
check_patches() {
    need zypper || return 0
    capture pc zy patch-check
    pc_rc=$?
    case "$pc_rc" in
        0) note 'zypper patch-check: no patches are needed (cached data)' ;;
        100) add_finding Warning "Patches are available (zypper patch-check exit 100): $(first_lines 3 "$pc")" ;;
        101) add_finding Warning "Security patches are available (zypper patch-check exit 101): $(first_lines 3 "$pc")" ;;
        5) add_finding Warning 'zypper patch-check needs more privileges (exit 5); run as root' ;;
        7) add_finding Warning 'zypper is locked by another process (exit 7); try again later' ;;
        *) add_finding Warning "zypper patch-check failed with exit $pc_rc: $(first_lines 3 "$pc")" ;;
    esac
    return 0
}
check_reboot() {
    need zypper || return 0
    capture nb zy needs-rebooting
    nb_rc=$?
    case "$nb_rc" in
        0) note 'zypper needs-rebooting: no reboot suggested' ;;
        102) add_finding Warning 'A reboot is suggested (zypper needs-rebooting exit 102)' ;;
        *) add_finding Warning "zypper needs-rebooting returned $nb_rc: $(first_lines 3 "$nb")" ;;
    esac
    is_root || { add_finding Warning 'zypper ps needs root to see all processes; the restart check was not performed'; return 0; }
    capture ps_out zy ps -s
    ps_rc=$?
    if [ "$ps_rc" -ne 0 ]; then add_finding Warning "zypper ps -s failed with exit $ps_rc: $(first_lines 3 "$ps_out")"; return 0; fi
    n=$(printf '%s\n' "$ps_out" | grep -c '|')
    n=$(( n > 1 ? n - 1 : 0 ))
    if [ "$n" -gt 0 ]; then add_finding Warning "$n process(es) use files that were deleted by an update and need a restart (zypper ps -s)"; else note 'zypper ps -s: no processes need a restart'; fi
    return 0
}
check_locks() {
    have zypper || return 0
    capture ll zy locks
    if [ $? -ne 0 ]; then add_finding Warning "zypper locks failed, so package locks were not listed: $(first_lines 2 "$ll")"; return 0; fi
    n=$(printf '%s\n' "$ll" | grep -c '^[[:space:]]*[0-9][0-9]*[[:space:]]*|')
    if [ "$n" -gt 0 ]; then add_finding Warning "$n package lock(s) are set (review at each maintenance window)"; else note 'No package locks'; fi
    return 0
}

section '1. REGISTRATION';  run_check Registration check_registration
section '2. REPOSITORIES';  run_check Repositories check_repos
section '3. PATCHES';       run_check Patches check_patches
section '4. REBOOT AND RESTARTS'; run_check Reboot check_reboot
section '5. LOCKS';         run_check Locks check_locks

complete_report
exit "$EXIT_CODE"
