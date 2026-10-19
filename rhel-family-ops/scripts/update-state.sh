#!/bin/sh
# RHEL family package and update state.
#
# READ ONLY: this script only reads state and changes nothing. Covers Red Hat registration (RHEL only, as root), enabled repositories, available updates and security advisories (dnf check-update and updateinfo; dnf contacts the repositories and may refresh its cache), reboot need (dnf needs-restarting), dnf-automatic timers and version locks.
# POSIX sh (/bin/sh is bash on the RHEL family). Run as root for the most complete picture. Environment: SECURITY_WARN_COUNT.
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

OS_RELEASE=${OS_RELEASE:-/etc/os-release}
SECURITY_WARN_COUNT=${SECURITY_WARN_COUNT:-1}
validate_uint SECURITY_WARN_COUNT
if [ "$SECURITY_WARN_COUNT" -lt 1 ]; then echo 'SECURITY_WARN_COUNT must be at least 1' >&2; exit 2; fi

echo 'RHEL family update state (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

RID=''
check_registration() {
    RID=$(osr ID)
    if [ "$RID" != rhel ]; then note "ID is '${RID:-unset}': no Red Hat registration is expected (Rocky and AlmaLinux need none)"; return 0; fi
    need subscription-manager || return 0
    is_root || { add_finding Warning 'subscription-manager identity needs root; the registration state was not checked'; return 0; }
    capture id_out subscription-manager identity
    if [ $? -eq 0 ]; then note 'The system is registered (subscription-manager identity succeeded)'; else add_finding Warning "The system is not registered with Red Hat through RHSM (subscription-manager identity failed; public-cloud images served by RHUI are not RHSM-registered, so ignore this there): $(first_lines 2 "$id_out")"; fi
    return 0
}
check_repos() {
    need dnf || return 0
    capture rl dnf -q repolist
    if [ $? -ne 0 ]; then add_finding Warning "dnf repolist failed: $(first_lines 3 "$rl")"; return 0; fi
    n=$(printf '%s\n' "$rl" | grep -v -e '^repo id' -e '^Updating' -e '^Last metadata' -e '^Warning' | grep -c '[^[:space:]]')
    if [ "$n" -lt 1 ]; then add_finding Warning "dnf lists no enabled repositories, so no updates can be found: $(first_lines 2 "$rl")"; else note "$n enabled repositor(ies)"; fi
    return 0
}
check_updates() {
    need dnf || return 0
    capture cu dnf -q check-update
    cu_rc=$?
    case "$cu_rc" in
        0) note 'dnf check-update: no updates available' ;;
        100) add_finding Warning "Updates are available (dnf check-update exited 100): $(first_lines 4 "$cu")" ;;
        *) add_finding Warning "dnf check-update failed with exit $cu_rc: $(first_lines 3 "$cu")"; return 0 ;;
    esac
    capture sec dnf -q updateinfo list --security
    if [ $? -ne 0 ]; then add_finding Warning "dnf updateinfo list --security failed: $(first_lines 3 "$sec")"; return 0; fi
    secn=$(printf '%s\n' "$sec" | grep '/Sec\.' | awk '{ print $1 }' | sort -u | grep -c .)
    note "Security advisories listed: $secn"
    if [ "$secn" -ge "$SECURITY_WARN_COUNT" ]; then add_finding Warning "$secn security advisor(ies) apply to this host: $(first_lines 5 "$sec")"; fi
    return 0
}
check_restart() {
    need dnf || return 0
    capture nr dnf needs-restarting -r
    nr_rc=$?
    case "$nr_rc" in
        0) note 'dnf needs-restarting -r: no reboot is required' ;;
        1) case "$nr" in
               *'No such command'*) add_finding Warning 'The dnf needs-restarting command is not available (install dnf-utils or dnf-plugins-core), so the reboot check was not performed' ;;
               *) add_finding Warning "A reboot is required to use updated core libraries or the kernel: $(first_lines 3 "$nr")" ;;
           esac ;;
        *) add_finding Warning "dnf needs-restarting -r returned $nr_rc: $(first_lines 3 "$nr")" ;;
    esac
    return 0
}
check_automatic() {
    need systemctl || return 0
    found=''
    for t in dnf-automatic dnf-automatic-install dnf-automatic-download dnf-automatic-notifyonly; do
        if systemctl is-enabled "$t.timer" >/dev/null 2>&1; then found="$found $t.timer"; fi
    done
    if [ -n "$found" ]; then note "dnf-automatic timers enabled:$found"; else add_finding Warning 'No dnf-automatic timer is enabled; that is fine only if another tool patches this host'; fi
    return 0
}
check_locks() {
    have dnf || return 0
    capture vl dnf -q versionlock list
    if [ $? -ne 0 ]; then note 'dnf versionlock is not available or failed; held versions were not listed'; return 0; fi
    n=$(printf '%s\n' "$vl" | grep -c '[^[:space:]]')
    if [ "$n" -gt 0 ]; then add_finding Warning "$n version lock(s) are set (review at each maintenance window): $(first_lines 5 "$vl")"; else note 'No version locks'; fi
    return 0
}

section '1. REGISTRATION';           run_check Registration check_registration
section '2. REPOSITORIES';           run_check Repositories check_repos
section '3. UPDATES AND ADVISORIES'; run_check Updates check_updates
section '4. REBOOT';                 run_check Reboot check_restart
section '5. AUTOMATIC UPDATES';      run_check 'Automatic updates' check_automatic
section '6. VERSION LOCKS';          run_check 'Version locks' check_locks

complete_report
exit "$EXIT_CODE"
