#!/bin/sh
# macOS storage and Time Machine summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports the boot volume and SMART status, free space, local APFS snapshots, Time Machine destinations and the age of the latest backup.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. The terminal needs Full Disk Access for tmutil and, per its man page, tmutil latestbackup needs root. Environment: BACKUP_MAX_AGE_DAYS, DISK_WARN_PCT.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: BACKUP_MAX_AGE_DAYS=3 sh storage-and-backup.sh
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

BACKUP_MAX_AGE_DAYS=${BACKUP_MAX_AGE_DAYS:-7}
DISK_WARN_PCT=${DISK_WARN_PCT:-85}
for _v in BACKUP_MAX_AGE_DAYS DISK_WARN_PCT; do
    eval "_val=\$$_v"
    is_uint "$_val" || { echo "$_v must be a whole number (got '$_val')" >&2; exit 2; }
done

echo 'macOS storage and backup'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

check_volumes() {
    need diskutil || return 0
    capture info diskutil info /
    if [ $? -ne 0 ]; then add_finding Warning "diskutil info / failed: $info"; return 0; fi
    printf '%s\n' "$info" | grep -E 'Volume Name|File System Personality|Container Total Space|Container Free Space|Volume Free Space|Encrypted|FileVault|Solid State|SMART Status' | sed 's/^ */  /'
    smart=$(printf '%s\n' "$info" | sed -n 's/^ *SMART Status: *//p' | head -1)
    case "$smart" in
        Verified) : ;;
        "") note 'No SMART status reported for the boot volume' ;;
        "Not Supported") note 'SMART status: Not Supported (common on some internal and virtual disks)' ;;
        *) add_finding Warning "SMART status of the boot volume is '$smart'" ;;
    esac
    return 0
}
check_snapshots() {
    need tmutil || return 0
    capture snaps tmutil listlocalsnapshots /
    if [ $? -ne 0 ]; then add_finding Warning "tmutil listlocalsnapshots failed: $snaps"; return 0; fi
    n=$(printf '%s\n' "$snaps" | grep -c 'com.apple.TimeMachine' )
    note "Local APFS snapshots: $n"
    return 0
}
check_time_machine() {
    need tmutil || return 0
    capture dest tmutil destinationinfo
    if [ $? -ne 0 ]; then add_finding Warning "tmutil destinationinfo failed (Full Disk Access may be needed for this shell): $dest"; return 0; fi
    case "$dest" in
        *"No destinations configured"*) add_finding Warning 'Time Machine has no backup destination configured'; return 0 ;;
    esac
    printf '%s\n' "$dest" | grep -E '^(Name|Kind|URL|Mount Point|ID)' | sed 's/^/  /'
    capture latest tmutil latestbackup
    if [ $? -ne 0 ]; then add_finding Warning "tmutil latestbackup failed (it needs Full Disk Access for this terminal and, per its man page, root; or the destination is not mounted or has no backups): $latest"; return 0; fi
    stamp=$(printf '%s\n' "$latest" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{6\}' | tail -1)
    if [ -z "$stamp" ]; then add_finding Warning "could not read a backup date from: $latest"; return 0; fi
    then_s=$(date -j -f '%Y-%m-%d-%H%M%S' "$stamp" '+%s' 2>/dev/null)
    if ! is_uint "$then_s"; then add_finding Warning "could not convert the backup date '$stamp'"; return 0; fi
    age=$(( ( $(date +%s) - then_s ) / 86400 ))
    note "Latest backup: $stamp ($age day(s) ago)"
    if [ "$age" -gt "$BACKUP_MAX_AGE_DAYS" ]; then add_finding Warning "The latest Time Machine backup is $age days old (limit $BACKUP_MAX_AGE_DAYS)"; fi
    return 0
}
check_free_space() {
    need df || return 0
    capture out df -Pk /System/Volumes/Data
    if [ $? -ne 0 ]; then capture out df -Pk /; fi
    pct=$(printf '%s\n' "$out" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
    if ! is_uint "$pct"; then add_finding Warning 'could not parse df output'; return 0; fi
    note "Data volume used: $pct%"
    if [ "$pct" -ge "$DISK_WARN_PCT" ]; then add_finding Warning "The data volume is $pct% used"; fi
    return 0
}

section '1. BOOT VOLUME';        run_check 'Boot volume' check_volumes
section '2. FREE SPACE';         run_check 'Free space' check_free_space
section '3. LOCAL SNAPSHOTS';    run_check Snapshots check_snapshots
section '4. TIME MACHINE';       run_check 'Time Machine' check_time_machine

complete_report
exit "$EXIT_CODE"
