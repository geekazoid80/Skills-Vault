#!/bin/sh
# macOS network summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports network services, the default route and address, DNS servers and a name lookup, proxy settings, gateway packet loss and host names. The name lookup and the gateway ping are the only active probes.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Environment: DNS_TEST_NAME, PING_COUNT.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: DNS_TEST_NAME=www.example.com sh network-diagnostics.sh
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

DNS_TEST_NAME=${DNS_TEST_NAME:-www.apple.com}
PING_COUNT=${PING_COUNT:-3}
for _v in PING_COUNT; do
    eval "_val=\$$_v"
    is_uint "$_val" || { echo "$_v must be a whole number (got '$_val')" >&2; exit 2; }
done

echo 'macOS network diagnostics'
printf 'Generated: %s (UTC); DNS test name %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$DNS_TEST_NAME"

check_services() {
    need networksetup || return 0
    capture svc networksetup -listallnetworkservices
    if [ $? -ne 0 ]; then add_finding Warning "networksetup -listallnetworkservices failed: $svc"; return 0; fi
    printf '%s\n' "$svc" | sed '1d' | sed 's/^/  /'
    n=$(printf '%s\n' "$svc" | sed '1d' | grep -vc '^\*')
    if [ "$n" -eq 0 ]; then add_finding Warning 'No enabled network service was listed'; fi
    return 0
}
GATEWAY=''
check_route() {
    need route || return 0
    capture rt route -n get default
    if [ $? -ne 0 ]; then
        capture rt6 route -n get -inet6 default
        if [ $? -eq 0 ]; then note 'No IPv4 default route; an IPv6 default route exists'; return 0; fi
        add_finding Critical 'There is no default route (IPv4 or IPv6)'
        return 0
    fi
    iface=$(printf '%s\n' "$rt" | sed -n 's/^ *interface: *//p' | head -1)
    GATEWAY=$(printf '%s\n' "$rt" | sed -n 's/^ *gateway: *//p' | head -1)
    note "Default route: interface ${iface:-unknown}, gateway ${GATEWAY:-none}"
    if [ -z "$iface" ]; then add_finding Warning 'could not read the default interface from route output'; return 0; fi
    [ -n "$GATEWAY" ] || add_finding Warning 'The default route has no gateway (a VPN or point-to-point interface?), so gateway reachability will not be tested'
    if ! have ipconfig; then add_finding Warning 'ipconfig not found; the interface address was not read'; else
        capture ip ipconfig getifaddr "$iface"
        if [ $? -eq 0 ] && [ -n "$ip" ]; then note "Address on $iface: $ip"; else add_finding Warning "No IPv4 address on $iface (ipconfig getifaddr): $ip"; fi
    fi
    return 0
}
check_dns() {
    need scutil || return 0
    capture dns scutil --dns
    if [ $? -ne 0 ]; then add_finding Warning "scutil --dns failed: $dns"; return 0; fi
    ns=$(printf '%s\n' "$dns" | sed -n 's/^ *nameserver\[[0-9]*\] : *//p' | sort -u)
    if [ -z "$ns" ]; then add_finding Critical 'No DNS nameserver is configured'; return 0; fi
    printf '%s\n' "$ns" | sed 's/^/  nameserver /'
    if have dscacheutil; then
        capture look dscacheutil -q host -a name "$DNS_TEST_NAME"
        if printf '%s\n' "$look" | grep -q 'ip_address'; then
            note "Name lookup of $DNS_TEST_NAME succeeded"
        else
            add_finding Warning "Name lookup of $DNS_TEST_NAME returned no address"
        fi
    else
        add_finding Warning 'dscacheutil not found; name resolution was not tested'
    fi
    return 0
}
check_proxy() {
    need scutil || return 0
    capture px scutil --proxy
    if [ $? -ne 0 ]; then add_finding Warning "scutil --proxy failed: $px"; return 0; fi
    printf '%s\n' "$px" | grep -E 'Enable|Proxy|PAC' | sed 's/^ */  /'
    if printf '%s\n' "$px" | grep -Eq '(HTTP|HTTPS|SOCKS|ProxyAutoConfig)Enable : 1'; then note 'A proxy is configured; confirm it is the managed one'; fi
    return 0
}
check_gateway() {
    if [ -z "$GATEWAY" ]; then note 'No gateway known; reachability not tested'; return 0; fi
    need ping || return 0
    capture pg ping -c "$PING_COUNT" -t 5 "$GATEWAY"
    loss=$(printf '%s\n' "$pg" | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' | head -1)
    if [ -z "$loss" ]; then add_finding Warning "Gateway $GATEWAY did not answer ping or the output could not be read"; return 0; fi
    note "Gateway $GATEWAY packet loss: $loss%"
    pos=$(awk -v l="$loss" 'BEGIN { if (l > 0) print "warn"; else print "ok" }')
    case "$pos" in warn) add_finding Warning "Gateway $GATEWAY packet loss is $loss% (a gateway that drops ICMP also shows 100%)" ;; esac
    return 0
}
check_names() {
    for k in ComputerName LocalHostName HostName; do
        capture v scutil --get "$k"
        if [ $? -eq 0 ]; then note "$k: $v"; else note "$k: not set"; fi
    done
    return 0
}

section '1. NETWORK SERVICES';        run_check Services check_services
section '2. DEFAULT ROUTE';           run_check Route check_route
section '3. DNS';                     run_check DNS check_dns
section '4. PROXY';                   run_check Proxy check_proxy
section '5. GATEWAY REACHABILITY (active: pings the gateway)'; run_check Gateway check_gateway
section '6. HOST NAMES';              run_check Names check_names

complete_report
exit "$EXIT_CODE"
