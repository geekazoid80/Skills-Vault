#!/bin/sh
# Debian system health summary.
#
# READ ONLY: this script only reads state and changes nothing. Covers the release and its support stage (full support, LTS, ELTS), kernel, uptime and reboot flag, load, memory, disk and inode use, free space in /boot, failed systemd units, clock synchronisation and Debian 13 changes that affect a host.
# POSIX sh (the Debian /bin/sh is dash). Environment: MAX_UPTIME_DAYS, DISK_WARN_PCT, DISK_CRIT_PCT, MEM_WARN_PCT, BOOT_MIN_FREE_MB, LTS_CODENAMES, ELTS_CODENAMES.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings
# or an invalid setting (the message is on standard error).
# A required command that is missing, fails or returns nothing is a warning, never a pass; an optional
# component that is not installed (for example snapd, sshd, cloud-init) is reported as information.
#
# Not run on a live host in this vault: it is checked with shellcheck and exercised against stub commands
# only, so the output formats it parses are taken from manual pages and vendor documentation. Try it on a
# non-critical host first.
#
# Example: sh system-health.sh
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

MAX_UPTIME_DAYS=${MAX_UPTIME_DAYS:-90}
DISK_WARN_PCT=${DISK_WARN_PCT:-85}
DISK_CRIT_PCT=${DISK_CRIT_PCT:-95}
MEM_WARN_PCT=${MEM_WARN_PCT:-90}
BOOT_MIN_FREE_MB=${BOOT_MIN_FREE_MB:-300}
OS_RELEASE=${OS_RELEASE:-/etc/os-release}
MEMINFO=${MEMINFO:-/proc/meminfo}
UPTIME_FILE=${UPTIME_FILE:-/proc/uptime}
LOADAVG_FILE=${LOADAVG_FILE:-/proc/loadavg}
REBOOT_FLAG=${REBOOT_FLAG:-/run/reboot-required}
SYSCTL_CONF=${SYSCTL_CONF:-/etc/sysctl.conf}
# Debian releases that are past full support but still covered by LTS or ELTS, from the Debian releases page
# (debian.org/releases) on 2026-10-19. Update both lists when that page changes; set them empty to disable.
LTS_CODENAMES=${LTS_CODENAMES-bookworm}
ELTS_CODENAMES=${ELTS_CODENAMES-bullseye buster stretch}
validate_uint MAX_UPTIME_DAYS BOOT_MIN_FREE_MB
validate_pct DISK_WARN_PCT DISK_CRIT_PCT MEM_WARN_PCT

echo 'Debian system health (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

VID=''
LISTS_EPOCH=1792368000   # 2026-10-19, the date of the built-in LTS and ELTS lists
STALE=''
_age=$(( ($(date +%s) - LISTS_EPOCH) / 86400 ))
if [ "$_age" -gt 180 ]; then STALE=" (the built-in LTS and ELTS lists date from 2026-10-19 and are $_age days old; check debian.org/releases)"; fi
check_identity() {
    if [ ! -r "$OS_RELEASE" ]; then add_finding Warning "cannot read $OS_RELEASE, so the release was not identified"; return 0; fi
    rid=$(osr ID); VID=$(osr VERSION_ID); code=$(osr VERSION_CODENAME); pretty=$(osr PRETTY_NAME)
    note "$pretty (VERSION_ID ${VID:-unset}, codename ${code:-unknown})"
    if [ "$rid" != debian ]; then add_finding Warning "ID is '${rid:-empty}', not debian; this script targets Debian"; fi
    if capture kern uname -r; then note "Kernel $kern"; else add_finding Warning 'uname -r failed'; fi
    if [ -z "$code" ]; then add_finding Warning 'VERSION_CODENAME is empty, so support status was not checked'; return 0; fi
    need debian-distro-info || return 0
    capture all debian-distro-info --all
    all_rc=$?
    capture sup debian-distro-info --supported
    sup_rc=$?
    if [ "$all_rc" -ne 0 ] || [ "$sup_rc" -ne 0 ] || [ -z "$all" ] || [ -z "$sup" ]; then
        add_finding Warning 'debian-distro-info failed or returned nothing, so support status was not checked'; return 0
    fi
    if ! in_list "$code" "$all"; then
        add_finding Warning "debian-distro-info does not know the release '$code' (its data file may be out of date); check debian.org/releases"
    elif in_list "$code" "$sup"; then
        capture stab debian-distro-info --stable || stab=''
        capture oldb debian-distro-info --old || oldb=''
        if [ "$code" != "$stab" ] && [ "$code" != "$oldb" ]; then
            add_finding Warning "Release $code is a development suite (testing or unstable); it has no security support guarantee and should not run production workloads"
        else
            capture dleft debian-distro-info --series="$code" --days=eol
            case "$dleft" in
                *[!0-9-]*|'') note "Release $code is in full security support (end date not available from the local data)" ;;
                *) note "Release $code is in full security support for about $dleft more day(s) (local distro-info data; confirm on debian.org/releases)"
                   if [ "$dleft" -lt 90 ]; then add_finding Warning "Full security support for $code ends in about $dleft day(s); plan the upgrade" ; fi ;;
            esac
        fi
    elif in_words "$code" "$LTS_CODENAMES"; then
        add_finding Warning "Release $code is past full security support and is covered by the LTS project (a subset of packages and architectures, not the Security Team); plan the upgrade$STALE"
    elif in_words "$code" "$ELTS_CODENAMES"; then
        add_finding Critical "Release $code is past Debian LTS; security fixes need a paid Extended LTS subscription (Freexian) or an upgrade$STALE"
    else
        add_finding Critical "Release $code is not in the supported list of the local distro-info data and is in neither LTS_CODENAMES nor ELTS_CODENAMES; it is unsupported$STALE"
    fi
    return 0
}
check_uptime() {
    if [ ! -r "$UPTIME_FILE" ]; then add_finding Warning "cannot read $UPTIME_FILE"; return 0; fi
    days=$(awk '{ printf "%d", $1 / 86400 }' "$UPTIME_FILE")
    if ! is_uint "$days"; then add_finding Warning "could not parse $UPTIME_FILE"; return 0; fi
    note "Uptime: $days day(s)"
    if [ "$days" -gt "$MAX_UPTIME_DAYS" ]; then add_finding Warning "Uptime is $days days, above $MAX_UPTIME_DAYS; a long uptime usually means kernel updates are not applied"; fi
    if [ -e "$REBOOT_FLAG" ]; then add_finding Warning "A reboot is required ($REBOOT_FLAG exists)"; else note "No $REBOOT_FLAG file (Debian only creates it when update-notifier-common or reboot-notifier is installed, so its absence proves nothing; update-state.sh checks the kernel through needrestart)"; fi
    return 0
}
check_load() {
    if [ ! -r "$LOADAVG_FILE" ]; then add_finding Warning "cannot read $LOADAVG_FILE"; return 0; fi
    need nproc || return 0
    capture ncpu nproc || { add_finding Warning 'nproc failed'; return 0; }
    l1=$(awk '{ print $1 }' "$LOADAVG_FILE")
    note "CPUs: $ncpu; load average (1 minute): ${l1:-unknown}"
    if [ -z "$l1" ] || ! is_uint "$ncpu"; then add_finding Warning "could not parse the load average or CPU count ('$l1', '$ncpu')"; return 0; fi
    over=$(awk -v l="$l1" -v n="$ncpu" 'BEGIN { if (l > n * 2) print "yes"; else print "no" }')
    if [ "$over" = yes ]; then add_finding Warning "1-minute load average $l1 is more than twice the CPU count ($ncpu)"; fi
    return 0
}
check_memory() {
    if [ ! -r "$MEMINFO" ]; then add_finding Warning "cannot read $MEMINFO"; return 0; fi
    tot=$(awk '/^MemTotal:/ { print $2 }' "$MEMINFO"); av=$(awk '/^MemAvailable:/ { print $2 }' "$MEMINFO")
    if ! is_uint "$tot" || ! is_uint "$av" || [ "$tot" -eq 0 ]; then add_finding Warning "MemTotal or MemAvailable could not be read from $MEMINFO"; return 0; fi
    used=$(( (tot - av) * 100 / tot ))
    note "Memory in use: $used% ($(( (tot - av) / 1024 )) of $(( tot / 1024 )) MiB, excluding reclaimable cache)"
    if [ "$used" -ge "$MEM_WARN_PCT" ]; then add_finding Warning "Memory in use is $used% (threshold $MEM_WARN_PCT%)"; fi
    return 0
}
check_disk() {
    need df || return 0
    seen=''
    for fs in / /var /boot /tmp; do
        [ -d "$fs" ] || continue
        capture line df -Pk "$fs" || { add_finding Warning "df -P $fs failed"; continue; }
        mp=$(printf '%s\n' "$line" | awk 'NR==2 { print $6 }'); pc=$(printf '%s\n' "$line" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
        avail=$(printf '%s\n' "$line" | awk 'NR==2 { print $4 }')
        case " $seen " in *" $mp "*) continue ;; esac
        seen="$seen $mp"
        if ! is_uint "$pc"; then add_finding Warning "could not parse df output for $fs"; continue; fi
        note "$mp: $pc% used"
        if [ "$pc" -ge "$DISK_CRIT_PCT" ]; then add_finding Critical "$mp is $pc% full (critical at $DISK_CRIT_PCT%)"; elif [ "$pc" -ge "$DISK_WARN_PCT" ]; then add_finding Warning "$mp is $pc% full (warning at $DISK_WARN_PCT%)"; fi
        if [ "$mp" = /boot ] && is_uint "$avail" && [ $(( avail / 1024 )) -lt "$BOOT_MIN_FREE_MB" ]; then
            add_finding Warning "/boot has $(( avail / 1024 )) MB free; the Debian 13 release notes ask for about 300 MB free (768 MB total) before an upgrade"
        fi
        capture iline df -Pi "$fs" || { add_finding Warning "df -Pi $fs failed"; continue; }
        ipc=$(printf '%s\n' "$iline" | awk 'NR==2 { gsub("%", "", $5); print $5 }')
        if is_uint "$ipc"; then
            if [ "$ipc" -ge "$DISK_WARN_PCT" ]; then add_finding Warning "$mp has $ipc% of its inodes used"; fi
        else
            note "$mp: inode usage not reported (some file systems do not report it)"
        fi
    done
    return 0
}
check_units() {
    need systemctl || return 0
    capture failed systemctl --failed --no-legend --plain
    if [ $? -ne 0 ]; then add_finding Warning "systemctl --failed failed (is this host running systemd?): $failed"; return 0; fi
    n=$(printf '%s\n' "$failed" | grep -c '[^[:space:]]')
    if [ "$n" -gt 0 ]; then add_finding Warning "$n failed unit(s): $(first_lines 5 "$(printf '%s\n' "$failed" | awk '{ print $1 }')")"; else note 'No failed units'; fi
    return 0
}
check_time() {
    need timedatectl || return 0
    capture sync timedatectl show -p NTPSynchronized --value
    if [ $? -ne 0 ]; then add_finding Warning "timedatectl show failed: $sync"; return 0; fi
    case "$sync" in
        yes) note 'Clock is synchronised' ;;
        no) add_finding Warning 'The clock is not synchronised (NTPSynchronized=no); check the NTP client (chrony or systemd-timesyncd)' ;;
        *) add_finding Warning "unexpected NTPSynchronized value '$sync'" ;;
    esac
    return 0
}
check_trixie_changes() {
    case "$VID" in
        ''|*[!0-9]*) note "VERSION_ID '${VID:-unset}' is not a number (testing or unstable?); the Debian 13 checks were skipped"; return 0 ;;
    esac
    if [ "$VID" -lt 13 ]; then note 'Debian 13 changes do not apply to this release'; return 0; fi
    if [ -r "$SYSCTL_CONF" ]; then
        n=$(grep -c -v -e '^[[:space:]]*#' -e '^[[:space:]]*;' -e '^[[:space:]]*$' "$SYSCTL_CONF")
        if [ "$n" -gt 0 ]; then add_finding Warning "$SYSCTL_CONF has $n active setting line(s), but systemd-sysctl no longer reads it on Debian 13; move them to /etc/sysctl.d/*.conf"; else note "$SYSCTL_CONF has no active settings"; fi
    else
        note "$SYSCTL_CONF is not present"
    fi
    return 0
}

section '1. RELEASE AND SUPPORT';  run_check Release check_identity
section '2. UPTIME AND REBOOT';    run_check Uptime check_uptime
section '3. LOAD';                 run_check Load check_load
section '4. MEMORY';               run_check Memory check_memory
section '5. DISK';                 run_check Disk check_disk
section '6. FAILED UNITS';         run_check Units check_units
section '7. TIME';                 run_check Time check_time
section '8. DEBIAN 13 CHANGES';    run_check 'Debian 13 changes' check_trixie_changes

complete_report
exit "$EXIT_CODE"
