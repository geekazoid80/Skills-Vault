#!/bin/sh
# macOS system health summary.
#
# READ ONLY: this script only reads state and changes nothing. Covers version and architecture, uptime, CPU load, memory pressure, the data volume, battery and thermal state, and the busiest processes.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Environment: MACOS_MIN_MAJOR, MAX_UPTIME_DAYS, DISK_WARN_PCT, DISK_CRIT_PCT.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sh system-health.sh
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

MIN_MAJOR=${MACOS_MIN_MAJOR:-15}      # oldest major release still receiving security updates (Apple security releases page, 2026-10-19)
MAX_UPTIME_DAYS=${MAX_UPTIME_DAYS:-30}
DISK_WARN_PCT=${DISK_WARN_PCT:-85}
DISK_CRIT_PCT=${DISK_CRIT_PCT:-95}
for _v in MIN_MAJOR MAX_UPTIME_DAYS DISK_WARN_PCT DISK_CRIT_PCT; do
    eval "_val=\$$_v"
    is_uint "$_val" || { echo "$_v must be a whole number (got '$_val')" >&2; exit 2; }
done

echo 'macOS system health'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

check_platform() {
    need sw_vers || return 0
    capture ver sw_vers -productVersion || { add_finding Warning 'sw_vers -productVersion failed'; return 0; }
    capture build sw_vers -buildVersion || build='unknown'
    capture arch uname -m || { arch='unknown'; add_finding Warning 'uname -m failed, so the architecture is unknown'; }
    note "macOS $ver (build $build), architecture $arch"
    major=${ver%%.*}
    if ! is_uint "$major"; then add_finding Warning "could not parse the macOS version '$ver'"; return 0; fi
    if [ "$major" -lt "$MIN_MAJOR" ]; then
        add_finding Warning "macOS $major is older than the minimum major release $MIN_MAJOR set for this check (compare Apple's security releases page; Apple publishes no end dates)"
    fi
    if [ "$arch" = "x86_64" ]; then
        note 'Intel Mac: macOS 26 Tahoe is the last release for Intel Macs (Apple security releases page, 2026-10-19)'
        if [ "$major" -ge 27 ]; then add_finding Warning 'Intel architecture reported on macOS 27 or later; check whether this shell is running under Rosetta (uname -m reports x86_64 there)'; fi
    fi
    return 0
}
check_uptime() {
    need sysctl || return 0
    capture bt sysctl -n kern.boottime || { add_finding Warning 'sysctl kern.boottime failed'; return 0; }
    boot=$(printf '%s' "$bt" | sed -n 's/.*sec = \([0-9][0-9]*\),.*/\1/p')
    if ! is_uint "$boot"; then add_finding Warning "could not parse kern.boottime ('$bt')"; return 0; fi
    now=$(date +%s)
    days=$(( (now - boot) / 86400 ))
    note "Uptime: $days day(s)"
    if [ "$days" -gt "$MAX_UPTIME_DAYS" ]; then add_finding Warning "Uptime is $days days, above $MAX_UPTIME_DAYS; restart to apply updates"; fi
    return 0
}
check_cpu_memory() {
    need sysctl || return 0
    capture ncpu sysctl -n hw.ncpu || { add_finding Warning 'sysctl hw.ncpu failed'; return 0; }
    capture mem sysctl -n hw.memsize || mem=''
    capture load sysctl -n vm.loadavg || { add_finding Warning 'sysctl vm.loadavg failed'; return 0; }
    l1=$(printf '%s' "$load" | sed -n 's/^{ *\([0-9.]*\) .*/\1/p')
    note "CPU count: $ncpu; load average (1 minute): ${l1:-unknown}"
    if [ -z "$l1" ]; then add_finding Warning "could not parse vm.loadavg ('$load')"; elif is_uint "$ncpu"; then
        over=$(awk -v l="$l1" -v n="$ncpu" 'BEGIN { if (l > n * 2) print "yes"; else print "no" }')
        if [ "$over" = "yes" ]; then add_finding Warning "1-minute load average $l1 is more than twice the CPU count ($ncpu)"; fi
    fi
    if is_uint "$mem"; then note "Memory: $(( mem / 1073741824 )) GB"; fi
    capture free sysctl -n kern.memorystatus_level
    if is_uint "$free"; then
        note "Memory free: $free% (kern.memorystatus_level)"
        if [ "$free" -lt 10 ]; then add_finding Critical "Only $free% of memory is free"; elif [ "$free" -lt 20 ]; then add_finding Warning "Only $free% of memory is free"; fi
    else
        add_finding Warning 'kern.memorystatus_level was not readable, so memory pressure was not evaluated'
    fi
    return 0
}
check_disk() {
    need df || return 0
    target=/System/Volumes/Data
    [ -d "$target" ] || target=/
    capture dfout df -Pk "$target" || { add_finding Warning "df failed for $target"; return 0; }
    pct=$(printf '%s\n' "$dfout" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
    if ! is_uint "$pct"; then add_finding Warning "could not parse df output for $target"; return 0; fi
    note "Data volume ($target): $pct% used"
    if [ "$pct" -ge "$DISK_CRIT_PCT" ]; then add_finding Critical "$target is $pct% full"; elif [ "$pct" -ge "$DISK_WARN_PCT" ]; then add_finding Warning "$target is $pct% full"; fi
    return 0
}
check_power() {
    need pmset || return 0
    capture batt pmset -g batt || { add_finding Warning 'pmset -g batt failed'; return 0; }
    if printf '%s' "$batt" | grep -q 'InternalBattery'; then
        printf '%s\n' "$batt" | sed 's/^/  /'
        if ! have system_profiler; then
            add_finding Warning 'system_profiler not found; the battery condition was not checked'
        else
            capture cond system_profiler SPPowerDataType
            c=$(printf '%s\n' "$cond" | sed -n 's/^ *Condition: *//p' | head -1)
            if [ -n "$c" ]; then
                note "Battery condition: $c"
                [ "$c" = "Normal" ] || add_finding Warning "Battery condition is '$c'"
            else
                add_finding Warning 'Battery present but system_profiler reported no condition'
            fi
        fi
    else
        note 'No internal battery reported'
    fi
    capture therm pmset -g therm || add_finding Warning "pmset -g therm failed: $therm"
    sl=$(printf '%s\n' "$therm" | sed -n 's/.*CPU_Speed_Limit *= *\([0-9][0-9]*\).*/\1/p' | head -1)
    if is_uint "$sl"; then
        note "CPU speed limit: $sl%"
        [ "$sl" -ge 100 ] || add_finding Warning "CPU speed is limited to $sl% by thermal conditions"
    else
        note 'No CPU speed limit recorded (or not available on this model)'
    fi
    return 0
}
check_processes() {
    capture top ps -Aceo pcpu,pmem,comm -r || { add_finding Warning 'ps failed'; return 0; }
    [ -n "$top" ] || { add_finding Warning 'ps returned nothing'; return 0; }
    printf '%s\n' "$top" | head -6 | sed 's/^/  /'
    return 0
}

section '1. PLATFORM';           run_check Platform check_platform
section '2. UPTIME';             run_check Uptime check_uptime
section '3. CPU AND MEMORY';     run_check 'CPU and memory' check_cpu_memory
section '4. DISK';               run_check Disk check_disk
section '5. POWER AND THERMAL';  run_check 'Power and thermal' check_power
section '6. TOP PROCESSES (by CPU)'; run_check Processes check_processes

complete_report
exit "$EXIT_CODE"
