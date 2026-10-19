#!/bin/sh
# Ubuntu network, name resolution, time and cloud-init summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports Netplan parsing, the default route, resolver configuration, clock synchronisation (chrony or systemd-timesyncd) and cloud-init status. One name lookup is always made; a ping of the default gateway only with PING_GATEWAY=1.
# POSIX sh (the Ubuntu /bin/sh is dash). Environment: DNS_TEST_NAME, PING_GATEWAY, PING_COUNT, MAX_OFFSET_SEC.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings
# or an invalid setting (the message is on standard error).
# A required command that is missing, fails or returns nothing is a warning, never a pass; an optional
# component that is not installed (for example snapd, sshd, cloud-init) is reported as information.
#
# Not run on a live host in this vault: it is checked with shellcheck and exercised against stub commands
# only, so the output formats it parses are taken from manual pages and vendor documentation. Try it on a
# non-critical host first.
#
# Example: PING_GATEWAY=1 sh network-and-time.sh
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

DNS_TEST_NAME=${DNS_TEST_NAME:-example.com}
PING_GATEWAY=${PING_GATEWAY:-0}
PING_COUNT=${PING_COUNT:-3}
MAX_OFFSET_SEC=${MAX_OFFSET_SEC:-1}
validate_flag PING_GATEWAY
validate_uint PING_COUNT
validate_decimal MAX_OFFSET_SEC

echo 'Ubuntu network and time (read only)'
printf 'Generated: %s (UTC); active probes: one name lookup%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$( [ "$PING_GATEWAY" = 1 ] && echo ' and a gateway ping')"

GATEWAY=''
check_netplan() {
    if ! have netplan; then note 'netplan is not installed; Netplan configuration was not checked'; return 0; fi
    capture np netplan get
    if [ $? -ne 0 ]; then add_finding Warning "netplan get failed (a YAML error shows here)$(is_root || echo '; Netplan files are normally readable by root only, so try as root'): $(first_lines 3 "$np")"; return 0; fi
    if [ -z "$np" ]; then add_finding Warning 'netplan get returned an empty configuration (the host may be configured another way)'; else note 'Netplan configuration parses'; fi
    return 0
}
check_route() {
    need ip || return 0
    capture rt ip -4 route show default
    if [ $? -ne 0 ]; then add_finding Warning "ip route failed: $rt"; return 0; fi
    if [ -z "$rt" ]; then add_finding Warning 'There is no IPv4 default route'; return 0; fi
    GATEWAY=$(printf '%s\n' "$rt" | awk '$1 == "default" { for (i = 2; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
    note "Default route: $(printf '%s\n' "$rt" | head -1)"
    if [ -z "$GATEWAY" ]; then note 'The default route has no gateway address (point-to-point or VPN interface)'; fi
    return 0
}
check_dns() {
    if have resolvectl; then
        capture rs resolvectl status
        if [ $? -ne 0 ]; then add_finding Warning "resolvectl status failed: $(first_lines 2 "$rs")"; else
            if printf '%s\n' "$rs" | grep -q -E '^[[:space:]]*(Current )?DNS Servers?:'; then note 'systemd-resolved has DNS servers configured'; else add_finding Warning 'resolvectl status lists no DNS servers on any link'; fi
        fi
    else
        note 'resolvectl is not installed; resolver configuration was not inspected'
    fi
    need getent || return 0
    capture h getent hosts "$DNS_TEST_NAME"
    if [ $? -ne 0 ] || [ -z "$h" ]; then add_finding Warning "The lookup of $DNS_TEST_NAME failed"; else note "Lookup of $DNS_TEST_NAME: $(printf '%s\n' "$h" | head -1)"; fi
    return 0
}
check_gateway() {
    if [ "$PING_GATEWAY" != 1 ]; then note 'skipped: set PING_GATEWAY=1 to ping the default gateway'; return 0; fi
    if [ -z "$GATEWAY" ]; then add_finding Warning 'No gateway address is known, so the gateway ping was not run'; return 0; fi
    need ping || return 0
    capture pg ping -c "$PING_COUNT" -W 2 "$GATEWAY"
    loss=$(printf '%s\n' "$pg" | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' | head -1)
    if [ -z "$loss" ]; then add_finding Warning "could not read packet loss from the ping to $GATEWAY: $(first_lines 2 "$pg")"; return 0; fi
    note "Packet loss to $GATEWAY: $loss%"
    if [ "$loss" = 100 ]; then add_finding Warning "No replies from the gateway $GATEWAY (it may drop ICMP; check ARP and TCP reachability)"; elif [ "$loss" != 0 ]; then add_finding Warning "$loss% packet loss to the gateway $GATEWAY"; fi
    return 0
}
check_time() {
    chrony_failed=0
    if have chronyc; then
        if capture tr chronyc tracking; then chrony_ok=1; else chrony_ok=0; chrony_failed=1; add_finding Warning "chronyc tracking failed (is chrony running?): $(first_lines 2 "$tr")"; fi
    else
        chrony_ok=0
    fi
    if [ "$chrony_ok" = 1 ]; then
        leap=$(printf '%s\n' "$tr" | sed -n 's/^Leap status *: *//p' | head -1)
        off=$(printf '%s\n' "$tr" | sed -n 's/^System time *: *\([0-9.]*\) seconds.*/\1/p' | head -1)
        note "chrony: leap status ${leap:-unknown}; offset ${off:-unknown} s"
        if [ "$leap" != Normal ]; then add_finding Warning "chrony reports leap status '${leap:-unknown}' (not Normal); the clock is not synchronised"; fi
        if [ -z "$off" ]; then add_finding Warning 'could not read the clock offset from chronyc tracking'; else
            big=$(awk -v o="$off" -v m="$MAX_OFFSET_SEC" 'BEGIN { if (o > m) print "yes"; else print "no" }')
            if [ "$big" = yes ]; then add_finding Warning "The clock is $off s from NTP time (threshold $MAX_OFFSET_SEC s)"; fi
        fi
        return 0
    fi
    if have timedatectl; then
        if [ "$chrony_failed" = 0 ]; then note 'chrony is not installed; using timedatectl'; fi
        capture ts timedatectl show -p NTPSynchronized --value
        if [ $? -ne 0 ]; then add_finding Warning "timedatectl show failed: $ts"; return 0; fi
        if [ "$ts" = yes ]; then note 'timedatectl reports the clock is synchronised'; else add_finding Warning "timedatectl reports NTPSynchronized='$ts'"; fi
        return 0
    fi
    add_finding Warning 'Neither chronyc nor timedatectl is available, so time synchronisation was not checked'
    return 0
}
check_cloud_init() {
    if ! have cloud-init; then note 'cloud-init is not installed'; return 0; fi
    ci=$(cloud-init status --long 2>&1)
    ci_rc=$?
    st=$(printf '%s\n' "$ci" | sed -n 's/^status: *//p' | head -1)
    ext=$(printf '%s\n' "$ci" | sed -n 's/^extended_status: *//p' | head -1)
    note "cloud-init status: ${st:-unknown}; extended_status: ${ext:-unknown}; exit code $ci_rc"
    case "$st" in
        done) if [ "$ci_rc" -eq 2 ] || [ "$ext" = degraded ] || [ "${ext#degraded}" != "$ext" ]; then add_finding Warning 'cloud-init finished with recoverable errors (degraded); read /var/log/cloud-init.log'; fi ;;
        running) : ;;
        disabled) note 'cloud-init is disabled (normal on hosts installed from the ISO)' ;;
        error) add_finding Warning 'cloud-init reports an error; run cloud-init status --long and read /var/log/cloud-init.log' ;;
        *) add_finding Warning "could not read the cloud-init status from: $(first_lines 2 "$ci")" ;;
    esac
    return 0
}

section '1. NETPLAN';           run_check Netplan check_netplan
section '2. DEFAULT ROUTE';     run_check Route check_route
section '3. NAME RESOLUTION (active lookup)'; run_check DNS check_dns
section '4. GATEWAY (active, opt in)'; run_check Gateway check_gateway
section '5. TIME SYNCHRONISATION'; run_check Time check_time
section '6. CLOUD-INIT';        run_check cloud-init check_cloud_init

complete_report
exit "$EXIT_CODE"
