#!/bin/sh
# ESXi host health check using esxcli. READ ONLY: it runs get and list commands
# and changes nothing. Written in POSIX sh for the ESXi Shell (BusyBox); copy it
# to the host or run it over SSH, both of which you enable only briefly.
#
# Usage: sh esxcli-health.sh
# Exit:  0 healthy, 1 warnings only, 2 critical findings.
#
# Not run against a live host in this vault. Try it on a non-critical host first.
# Thresholds: VMFS, NFS and vSAN datastores warn at 80 per cent used and are
# critical at 90. Parsing relies on the esxcli table layout, which can change
# between releases; if no datastore row can be evaluated the script says so and
# raises a warning rather than reporting the datastores healthy.

WARNS=""
CRITS=""
NL='
'
add_warn() { WARNS="${WARNS}${1}${NL}"; }
add_crit() { CRITS="${CRITS}${1}${NL}"; }
section() { printf '\n%s\n------------------------------------------------------------------------\n' "$1"; }

if ! command -v esxcli >/dev/null 2>&1; then
    echo "esxcli not found: run this on an ESXi host." >&2
    exit 2
fi

echo "ESXi host health report"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
echo "Host:      $(esxcli system hostname get 2>/dev/null | awk -F': *' '/Fully Qualified Domain Name/ {print $2}')"

section "1. VERSION AND PLATFORM"
esxcli system version get 2>&1
esxcli hardware platform get 2>&1 | sed -n '1,8p'
echo "Maintenance mode: $(esxcli system maintenanceMode get 2>&1)"

section "2. NETWORK ADAPTERS"
nics=$(esxcli network nic list 2>&1) || { echo "$nics"; add_warn "esxcli network nic list failed"; nics=""; }
echo "$nics"
# Columns: Name, PCI, Driver, Admin Status, Link Status, Speed, ...
# A spare port that is up with no cable also lands here; decide per site whether that matters.
down=$(printf '%s\n' "$nics" | awk '$4 == "Up" && $5 == "Down" {print $1}')
for n in $down; do add_crit "NIC $n is administratively up but has no link"; done
echo
esxcli network vswitch standard list 2>&1 | grep -E '^[A-Za-z]|Name:|Uplinks:|MTU:' | sed -n '1,30p'

section "3. STORAGE ADAPTERS AND PATHS"
esxcli storage core adapter list 2>&1 | sed -n '1,20p'
paths=$(esxcli storage core path list 2>&1) || { echo "$paths"; add_warn "esxcli storage core path list failed"; paths=""; }
dead=$(printf '%s\n' "$paths" | grep -c 'State: dead')
echo "Paths in dead state: ${dead}"
[ "$dead" -gt 0 ] && add_crit "${dead} storage path(s) are dead"
devs=$(esxcli storage core device list 2>&1) || { echo "$devs"; add_warn "esxcli storage core device list failed"; devs=""; }
off=$(printf '%s\n' "$devs" | grep -c 'Status: off')
echo "Devices with status off: ${off}"
[ "$off" -gt 0 ] && add_warn "${off} storage device(s) report status off"

section "4. DATASTORES"
fs=$(esxcli storage filesystem list 2>&1) || { echo "$fs"; add_warn "esxcli storage filesystem list failed"; fs=""; }
echo "$fs"
# Size and Free are the last two columns, in bytes.
ds_findings=$(printf '%s\n' "$fs" | awk '/VMFS|NFS|vsan/ {
    rows++
    size = $(NF-1); free = $NF
    if (size ~ /^[0-9]+$/ && free ~ /^[0-9]+$/ && size > 0) {
        evaluated++
        pct = int((size - free) * 100 / size)
        if (pct >= 90) print "CRIT " pct " " $1
        else if (pct >= 80) print "WARN " pct " " $1
    } else print "UNREAD 0 " $1
}
END { if (evaluated == 0) print "NONE " rows+0 " datastores" }')
while read -r level pct mount; do
    [ -n "$level" ] || continue
    case "$level" in
        CRIT) add_crit "Datastore ${mount} is ${pct} per cent used" ;;
        WARN) add_warn "Datastore ${mount} is ${pct} per cent used" ;;
        UNREAD) add_warn "Datastore ${mount} has no readable size (unmounted or inaccessible)" ;;
        NONE) add_warn "No datastore row could be evaluated (${pct} rows seen); check the esxcli output layout" ;;
    esac
done <<EOF
$ds_findings
EOF

section "5. TIME AND LOGGING"
if ntp=$(esxcli system ntp get 2>&1); then
    echo "$ntp"
    printf '%s\n' "$ntp" | grep -qi 'Enabled: true' || add_warn "NTP is not enabled"
    printf '%s\n' "$ntp" | grep -qi 'Time Synchronized: false' && add_warn "NTP is enabled but time is not synchronised"
else
    echo "$ntp"
    add_warn "esxcli system ntp get failed (the ntp namespace needs ESXi 7.0 U3 or later)"
fi
syslog=$(esxcli system syslog config get 2>&1) || add_warn "esxcli system syslog config get failed"
printf '%s\n' "$syslog" | grep -E 'Local Log Output|Remote Host'
printf '%s\n' "$syslog" | grep -qE 'Remote Host: *(<none>)?$' && add_warn "No remote syslog host is configured"

section "SUMMARY"
if [ -z "$CRITS" ] && [ -z "$WARNS" ]; then
    echo "No warnings or critical findings."
    exit 0
fi
printf '%s' "$CRITS" | while IFS= read -r l; do [ -n "$l" ] && echo "  CRITICAL: $l"; done
printf '%s' "$WARNS" | while IFS= read -r l; do [ -n "$l" ] && echo "  WARNING:  $l"; done
[ -n "$CRITS" ] && exit 2
exit 1
