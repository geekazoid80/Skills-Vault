#!/bin/sh
# SLES storage and Snapper summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports the root file system type, space, Btrfs allocation (metadata pressure and unallocated space), Btrfs device error counters, Snapper snapshot count and the Snapper timers.
# POSIX sh (/bin/sh is bash on SLES). Run as root for Snapper and Btrfs counters. Environment: META_WARN_PCT, DISK_WARN_PCT, DISK_CRIT_PCT, SNAPSHOT_WARN_COUNT, UNALLOC_MIN_MB.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings
# or an invalid setting (the message is on standard error).
# A required command that is missing, fails or returns nothing is a warning, never a pass; an optional
# component that is not installed (for example snapd, sshd, cloud-init) is reported as information.
#
# Not run on a live host in this vault: it is checked with shellcheck and exercised against stub commands
# only, so the output formats it parses are taken from manual pages and vendor documentation. Try it on a
# non-critical host first.
#
# Example: sudo sh storage-and-snapshots.sh
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

META_WARN_PCT=${META_WARN_PCT:-90}
DISK_WARN_PCT=${DISK_WARN_PCT:-85}
DISK_CRIT_PCT=${DISK_CRIT_PCT:-95}
SNAPSHOT_WARN_COUNT=${SNAPSHOT_WARN_COUNT:-50}
UNALLOC_MIN_MB=${UNALLOC_MIN_MB:-1024}
validate_pct META_WARN_PCT DISK_WARN_PCT DISK_CRIT_PCT
validate_uint SNAPSHOT_WARN_COUNT UNALLOC_MIN_MB

echo 'SLES storage and snapshots (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

ROOT_FS=''
check_root_fs() {
    need findmnt || return 0
    capture ROOT_FS findmnt -no FSTYPE /
    if [ $? -ne 0 ] || [ -z "$ROOT_FS" ]; then add_finding Warning "findmnt could not read the root file system type: $ROOT_FS"; ROOT_FS=''; return 0; fi
    note "Root file system: $ROOT_FS"
    if [ "$ROOT_FS" != btrfs ]; then note 'The root file system is not Btrfs, so Snapper rollback and the Btrfs checks do not apply'; fi
    return 0
}
check_space() {
    need df || return 0
    seen=''
    for fs in / /var /boot; do
        [ -d "$fs" ] || continue
        capture line df -Pk "$fs" || { add_finding Warning "df -Pk $fs failed"; continue; }
        mp=$(printf '%s\n' "$line" | awk 'NR==2 { print $6 }'); pc=$(printf '%s\n' "$line" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
        case " $seen " in *" $mp "*) continue ;; esac
        seen="$seen $mp"
        if ! is_uint "$pc"; then add_finding Warning "could not parse df output for $fs"; continue; fi
        note "$mp: $pc% used"
        if [ "$pc" -ge "$DISK_CRIT_PCT" ]; then add_finding Critical "$mp is $pc% full (critical at $DISK_CRIT_PCT%)"; elif [ "$pc" -ge "$DISK_WARN_PCT" ]; then add_finding Warning "$mp is $pc% full (warning at $DISK_WARN_PCT%); on Btrfs, snapshots hold deleted data until they are removed"; fi
    done
    return 0
}
META_PC=''
check_btrfs_space() {
    [ "$ROOT_FS" = btrfs ] || return 0
    need btrfs || return 0
    capture bd btrfs filesystem df -b /
    if [ $? -ne 0 ]; then add_finding Warning "btrfs filesystem df failed: $(first_lines 2 "$bd")"; return 0; fi
    for kind in Data Metadata System; do
        line=$(printf '%s\n' "$bd" | grep "^$kind," | head -1)
        tot=$(printf '%s\n' "$line" | sed -n 's/.*total=\([0-9][0-9]*\).*/\1/p')
        used=$(printf '%s\n' "$line" | sed -n 's/.*used=\([0-9][0-9]*\).*/\1/p')
        if ! is_uint "$tot" || ! is_uint "$used" || [ "$tot" -eq 0 ]; then add_finding Warning "could not read $kind allocation from btrfs filesystem df -b"; continue; fi
        pc=$(( used * 100 / tot ))
        note "Btrfs $kind: $pc% of allocated space used"
        if [ "$kind" = Metadata ]; then META_PC=$pc; fi
    done
    capture bu btrfs filesystem usage -b /
    if [ $? -ne 0 ]; then add_finding Warning "btrfs filesystem usage failed: $(first_lines 2 "$bu")"; return 0; fi
    un=$(printf '%s\n' "$bu" | sed -n 's/^[[:space:]]*Device unallocated:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
    if ! is_uint "$un"; then add_finding Warning 'could not read Device unallocated from btrfs filesystem usage -b, so the chunk-allocation check was not performed'; return 0; fi
    note "Btrfs unallocated space: $(( un / 1048576 )) MiB"
    if [ "$un" -lt $(( UNALLOC_MIN_MB * 1048576 )) ]; then
        if [ -n "${META_PC:-}" ] && [ "$META_PC" -ge "$META_WARN_PCT" ]; then add_finding Warning "Btrfs has under $UNALLOC_MIN_MB MiB unallocated and metadata is ${META_PC}% used: new chunks cannot be allocated, which causes 'no space left' errors while data blocks are free (snapshots are a common cause)"
        else add_finding Warning "Btrfs has under $UNALLOC_MIN_MB MiB unallocated, so new chunks cannot be allocated (check snapshots and consider a balance, with care)"; fi
    fi
    return 0
}
check_btrfs_errors() {
    [ "$ROOT_FS" = btrfs ] || return 0
    need btrfs || return 0
    capture ds btrfs device stats /
    if [ $? -ne 0 ]; then add_finding Warning "btrfs device stats failed: $(first_lines 2 "$ds")"; return 0; fi
    nl=$(printf '%s\n' "$ds" | grep -c '\.[a-z_]*errs')
    if [ "$nl" -lt 1 ]; then add_finding Warning "btrfs device stats returned no error-counter lines, so the counters could not be checked: $(first_lines 2 "$ds")"; return 0; fi
    bad=$(printf '%s\n' "$ds" | grep '\.[a-z_]*errs' | grep -v -c ' 0$')
    if [ "$bad" -gt 0 ]; then add_finding Warning "btrfs device stats reports $bad non-zero error counter(s): $(first_lines 4 "$(printf '%s\n' "$ds" | grep '\.[a-z_]*errs' | grep -v ' 0$')")"; else note 'btrfs device stats: all error counters are zero'; fi
    return 0
}
check_snapshots() {
    need snapper || return 0
    is_root || { add_finding Warning 'snapper list needs root; snapshots were not counted'; return 0; }
    capture sl snapper list
    if [ $? -ne 0 ]; then add_finding Warning "snapper list failed: $(first_lines 3 "$sl")"; return 0; fi
    n=$(printf '%s\n' "$sl" | grep -c '^[[:space:]]*[1-9][0-9]*[-+*]*[[:space:]]*|')
    note "Snapper snapshots listed (excluding snapshot 0, the current system): $n"
    if [ "$n" -ge "$SNAPSHOT_WARN_COUNT" ]; then add_finding Warning "$n Snapper snapshots exist (threshold $SNAPSHOT_WARN_COUNT); check the cleanup timers and free space"; fi
    return 0
}
check_snapper_timers() {
    have systemctl || return 0
    found=''
    for t in snapper-cleanup snapper-timeline snapper-boot; do
        if systemctl is-enabled "$t.timer" >/dev/null 2>&1; then found="$found $t.timer"; fi
    done
    note "Snapper timers enabled:${found:- none}"
    case " $found " in
        *' snapper-cleanup.timer '*) : ;;
        *) add_finding Warning 'snapper-cleanup.timer is not enabled, so snapshots are not cleaned up automatically and can fill the file system' ;;
    esac
    return 0
}

section '1. ROOT FILE SYSTEM';     run_check 'Root file system' check_root_fs
section '2. SPACE';                run_check Space check_space
section '3. BTRFS ALLOCATION';     run_check 'Btrfs allocation' check_btrfs_space
section '4. BTRFS ERROR COUNTERS'; run_check 'Btrfs errors' check_btrfs_errors
section '5. SNAPPER SNAPSHOTS';    run_check Snapshots check_snapshots
section '6. SNAPPER TIMERS';       run_check 'Snapper timers' check_snapper_timers

complete_report
exit "$EXIT_CODE"
