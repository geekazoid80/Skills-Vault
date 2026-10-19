#!/bin/sh
# Ubuntu package and update state.
#
# READ ONLY: this script only reads state and changes nothing. Covers apt index freshness, dpkg state, held packages, pending and security updates (a simulation), unattended-upgrades, kernel and service restarts (needrestart) and pending snap refreshes.
# POSIX sh (the Ubuntu /bin/sh is dash). Run as root for the restart check. Environment: APT_STALE_DAYS, UPGRADE_WARN_COUNT.
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
# shellcheck disable=SC2016,SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops;
#  SC2016: where used, dpkg-query format strings contain a literal ${Status}.)

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
first_lines() { printf '%s\n' "$2" | head -n "$1" | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
# in_words WORD WORDS: is WORD one of the space-separated entries of WORDS?
in_words() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

APT_STALE_DAYS=${APT_STALE_DAYS:-7}
UPGRADE_WARN_COUNT=${UPGRADE_WARN_COUNT:-50}
APT_STAMP=${APT_STAMP:-/var/lib/apt/periodic/update-success-stamp}
validate_uint APT_STALE_DAYS UPGRADE_WARN_COUNT

echo 'Ubuntu update state (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

check_index_age() {
    if [ ! -e "$APT_STAMP" ]; then add_finding Warning "No record of a successful apt update ($APT_STAMP is missing); check that apt-daily.timer is enabled"; return 0; fi
    need stat || return 0
    capture mt stat -c %Y "$APT_STAMP" || { add_finding Warning "stat $APT_STAMP failed"; return 0; }
    is_uint "$mt" || { add_finding Warning "could not parse the modification time of $APT_STAMP ('$mt')"; return 0; }
    age=$(( ($(date +%s) - mt) / 86400 ))
    note "Last successful apt update: $age day(s) ago"
    if [ "$age" -gt "$APT_STALE_DAYS" ]; then add_finding Warning "The package index was last refreshed $age days ago (threshold $APT_STALE_DAYS)"; fi
    return 0
}
check_dpkg() {
    need dpkg || return 0
    capture aud dpkg --audit
    if [ $? -ne 0 ]; then add_finding Warning "dpkg --audit failed: $aud"; return 0; fi
    if [ -n "$aud" ]; then add_finding Warning "dpkg reports broken or half-configured packages: $(first_lines 3 "$aud")"; else note 'dpkg --audit is clean'; fi
    need apt-mark || return 0
    capture holds apt-mark showhold
    if [ $? -ne 0 ]; then add_finding Warning "apt-mark showhold failed: $holds"; return 0; fi
    if [ -n "$holds" ]; then add_finding Warning "Held packages (review at each maintenance window): $(first_lines 8 "$holds")"; else note 'No held packages'; fi
    return 0
}
check_pending() {
    need apt-get || return 0
    capture sim apt-get -s dist-upgrade
    if [ $? -ne 0 ]; then add_finding Warning "apt-get -s dist-upgrade failed: $(first_lines 3 "$sim")"; return 0; fi
    if ! printf '%s\n' "$sim" | grep -q '^[0-9][0-9]* upgraded, [0-9][0-9]* newly installed'; then add_finding Warning "apt-get -s returned no upgrade summary line, so the pending-update check is unreliable: $(first_lines 2 "$sim")"; return 0; fi
    is_root || note 'Not root: a non-root simulation may not read all apt configuration, so the counts can be distorted'
    total=$(printf '%s\n' "$sim" | grep -c '^Inst ')
    secn=$(printf '%s\n' "$sim" | grep '^Inst ' | sed -n 's/^Inst [^(]*(\(.*\))[^)]*$/\1/p' | grep -c -e '-security')
    rem=$(printf '%s\n' "$sim" | grep -c '^Remv ')
    note "Pending: $total upgrade(s), of which $secn from a security pocket; $rem removal(s)"
    if [ "$secn" -gt 0 ]; then add_finding Warning "$secn security update(s) are pending"; fi
    if [ "$total" -ge "$UPGRADE_WARN_COUNT" ]; then add_finding Warning "$total updates are pending (threshold $UPGRADE_WARN_COUNT)"; fi
    if [ "$rem" -gt 0 ]; then add_finding Warning "A full upgrade would remove $rem package(s); review before applying"; fi
    if printf '%s\n' "$sim" | grep -q -e 'have been kept back' -e 'deferred due to phasing'; then add_finding Warning 'Some packages are kept back or deferred by phasing (held, phased, or a dependency problem); apt-get -s dist-upgrade shows which'; fi
    return 0
}
check_unattended() {
    if have pro; then
        capture uj pro api u.unattended_upgrades.status.v1
        if [ $? -eq 0 ] && printf '%s' "$uj" | grep -q '"result": *"success"'; then
            if printf '%s' "$uj" | grep -q '"unattended_upgrades_running": *true'; then note 'The Ubuntu Pro client reports unattended-upgrades is configured and running'; return 0; fi
            if printf '%s' "$uj" | grep -q '"unattended_upgrades_running": *false'; then
                why=$(printf '%s' "$uj" | sed -n 's/.*"unattended_upgrades_disabled_reason": *{[^}]*"msg": *"\([^"]*\)".*/\1/p' | head -1)
                add_finding Warning "The Ubuntu Pro client reports unattended-upgrades is not running${why:+ ($why)}; that is fine only if another tool patches this host"
                return 0
            fi
        fi
        note 'The Pro client API for unattended-upgrades was unavailable; falling back to apt configuration'
    fi
    need apt-config || return 0
    capture cfg apt-config dump
    if [ $? -ne 0 ]; then add_finding Warning 'apt-config dump failed (output withheld: it can contain proxy credentials)'; return 0; fi
    ua=$(printf '%s\n' "$cfg" | sed -n 's/^APT::Periodic::Unattended-Upgrade "\([^"]*\)";.*/\1/p' | head -1)
    ul=$(printf '%s\n' "$cfg" | sed -n 's/^APT::Periodic::Update-Package-Lists "\([^"]*\)";.*/\1/p' | head -1)
    note "APT::Periodic::Update-Package-Lists=${ul:-unset}; Unattended-Upgrade=${ua:-unset}"
    case "$ua" in
        ''|0) add_finding Warning 'unattended-upgrades is not enabled (APT::Periodic::Unattended-Upgrade is unset or 0); that is fine only if another tool patches this host' ;;
    esac
    return 0
}
check_restart() {
    need needrestart || return 0
    is_root || { add_finding Warning 'needrestart -b needs root to list outdated services; the restart check was not performed'; return 0; }
    capture nr needrestart -b
    if [ $? -ne 0 ]; then add_finding Warning "needrestart -b failed: $(first_lines 3 "$nr")"; return 0; fi
    ksta=$(printf '%s\n' "$nr" | sed -n 's/^NEEDRESTART-KSTA: *//p' | head -1)
    ucsta=$(printf '%s\n' "$nr" | sed -n 's/^NEEDRESTART-UCSTA: *//p' | head -1)
    svc=$(printf '%s\n' "$nr" | sed -n 's/^NEEDRESTART-SVC: *//p')
    case "$ksta" in
        1) note 'Running kernel is current' ;;
        2) add_finding Warning 'A kernel update with a compatible ABI is pending; reboot to use it' ;;
        3) add_finding Warning 'A kernel version upgrade is pending; reboot to use it' ;;
        *) add_finding Warning "needrestart could not determine the kernel state (NEEDRESTART-KSTA='${ksta:-missing}')" ;;
    esac
    if [ "$ucsta" = 2 ]; then add_finding Warning 'The CPU microcode is obsolete (NEEDRESTART-UCSTA=2)'; fi
    if [ -n "$svc" ]; then add_finding Warning "Services need a restart to load updated libraries: $(first_lines 8 "$svc")"; else note 'No services need a restart'; fi
    return 0
}
check_snaps() {
    if ! have snap; then note 'snapd is not installed; snap refreshes were not checked'; return 0; fi
    capture sr snap refresh --list
    sr_rc=$?
    case "$sr" in
        *'All snaps up to date'*) note 'All snaps are up to date'; return 0 ;;
    esac
    if [ "$sr_rc" -ne 0 ]; then add_finding Warning "snap refresh --list failed: $(first_lines 3 "$sr")"; return 0; fi
    n=$(printf '%s\n' "$sr" | grep -c '[^[:space:]]')
    n=$(( n - 1 ))
    if [ "$n" -gt 0 ]; then add_finding Warning "$n snap refresh(es) are pending: $(first_lines 6 "$(printf '%s\n' "$sr" | sed 1d | awk '{ print $1 }')")"; else add_finding Warning "snap refresh --list returned nothing recognisable: $sr"; fi
    return 0
}

section '1. PACKAGE INDEX';         run_check 'Package index' check_index_age
section '2. DPKG STATE AND HOLDS';  run_check dpkg check_dpkg
section '3. PENDING UPDATES';       run_check 'Pending updates' check_pending
section '4. UNATTENDED UPGRADES';   run_check 'Unattended upgrades' check_unattended
section '5. RESTARTS AND REBOOT';   run_check 'Restart check' check_restart
section '6. SNAP REFRESHES';        run_check Snaps check_snaps

complete_report
exit "$EXIT_CODE"
