#!/usr/bin/env bash
# KVM and libvirt host health check. READ ONLY: it runs status and list commands
# and changes nothing. Run on the KVM host; use root or a user with libvirt access.
#
# Usage: bash virsh-health.sh            (uses qemu:///system)
#        LIBVIRT_URI=qemu:///session bash virsh-health.sh
# Exit:  0 healthy, 1 warnings only, 2 critical findings.
#
# Not run against a live host in this vault. Try it on a non-critical host first.
# Thresholds: memory and filesystem warn at 90 per cent or more, storage pools
# warn at 80 and are critical at 90.

set -u
export LC_ALL=C

URI=${LIBVIRT_URI:-qemu:///system}
WARN=()
CRIT=()

hr() { printf '%s\n' "------------------------------------------------------------------------"; }
section() { printf '\n%s\n' "$1"; hr; }
have() { command -v "$1" >/dev/null 2>&1; }
v() { virsh -c "$URI" "$@"; }

echo "KVM and libvirt health report"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
echo "Host:      $(hostname -f 2>/dev/null || hostname)"
echo "URI:       ${URI}"

if ! have virsh; then
    echo "virsh not found: libvirt client tools are not installed." >&2
    exit 2
fi

section "1. KVM"
lsmod 2>/dev/null | grep -E '^kvm' || echo "(no kvm modules listed; fine only if KVM is built into the kernel)"
if [ -c /dev/kvm ]; then
    ls -l /dev/kvm
else
    CRIT+=("/dev/kvm is missing (virtualisation disabled in firmware, or modules not loaded)")
fi
if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    echo "IOMMU: enabled ($(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') groups)"
else
    echo "IOMMU: not enabled (only matters for passthrough)"
fi

section "2. LIBVIRT DAEMONS"
for svc in libvirtd virtqemud virtstoraged virtnetworkd virtproxyd; do
    state=$(systemctl is-active "$svc" 2>/dev/null || true)
    echo "  ${svc}: ${state:-not found}"
done
if ! vi=$(v version 2>&1); then
    echo "$vi"
    CRIT+=("virsh cannot connect to ${URI}")
    echo
    section "SUMMARY"
    for c in "${CRIT[@]}"; do echo "  CRITICAL: $c"; done
    exit 2
fi
echo "$vi" | sed -n '1,4p'

section "3. HOST RESOURCES"
v nodeinfo 2>&1 | sed -n '1,12p'
echo "Load: $(cut -d' ' -f1-3 /proc/loadavg)"
free -h | grep -E '^(Mem|Swap)'
mem_total=$(free | awk '/^Mem/ {print $2}')
mem_used=$(free | awk '/^Mem/ {print $3}')
if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
    mem_pct=$((mem_used * 100 / mem_total))
    [ "$mem_pct" -ge 90 ] && WARN+=("Host memory use at ${mem_pct} per cent")
fi
grep -i '^HugePages_' /proc/meminfo 2>/dev/null | sed 's/^/  /'
for path in /var/lib/libvirt/images /var/lib/libvirt; do
    [ -d "$path" ] || continue
    use=$(df -P "$path" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    echo "Filesystem for ${path}: ${use}% used"
    case "$use" in ''|*[!0-9]*) ;; *) [ "$use" -ge 90 ] && WARN+=("Filesystem holding ${path} at ${use} per cent") ;; esac
    break
done

section "4. STORAGE POOLS"
pools=$(v pool-list --all --name 2>&1) || { echo "$pools"; WARN+=("pool-list failed"); pools=""; }
v pool-list --all 2>&1 | sed -n '1,30p'
while IFS= read -r pool; do
    [ -n "$pool" ] || continue
    info=$(v pool-info --bytes "$pool" 2>&1) || { WARN+=("pool-info failed for ${pool}"); continue; }
    state=$(printf '%s\n' "$info" | awk -F': *' '/^State/ {print $2}')
    auto=$(printf '%s\n' "$info" | awk -F': *' '/^Autostart/ {print $2}')
    cap=$(printf '%s\n' "$info" | awk -F': *' '/^Capacity/ {print $2}' | awk '{print $1}')
    alloc=$(printf '%s\n' "$info" | awk -F': *' '/^Allocation/ {print $2}' | awk '{print $1}')
    case "$state" in
        running) ;;
        inactive) [ "$auto" = "yes" ] && WARN+=("Pool ${pool} has autostart but is inactive"); continue ;;
        *) WARN+=("Pool ${pool} is ${state:-in an unknown state}"); continue ;;
    esac
    case "$cap:$alloc" in *[!0-9:]*|:*|*:) WARN+=("Pool ${pool} capacity or allocation could not be read"); continue ;; esac
    if [ "$cap" -gt 0 ]; then
        pct=$((alloc * 100 / cap))
        echo "  ${pool}: ${pct}% allocated"
        if [ "$pct" -ge 90 ]; then CRIT+=("Pool ${pool} at ${pct} per cent")
        elif [ "$pct" -ge 80 ]; then WARN+=("Pool ${pool} at ${pct} per cent"); fi
    fi
done <<< "$pools"

section "5. VIRTUAL NETWORKS"
v net-list --all 2>&1
nets=$(v net-list --all --name 2>&1) || { WARN+=("net-list failed: ${nets}"); nets=""; }
while IFS= read -r net; do
    [ -n "$net" ] || continue
    info=$(v net-info "$net" 2>&1) || { WARN+=("net-info failed for ${net}"); continue; }
    active=$(printf '%s\n' "$info" | awk -F': *' '/^Active/ {print $2}')
    auto=$(printf '%s\n' "$info" | awk -F': *' '/^Autostart/ {print $2}')
    [ "$active" = "no" ] && [ "$auto" = "yes" ] && WARN+=("Network ${net} has autostart but is not active")
done <<< "$nets"

section "6. GUESTS"
v list --all 2>&1
doms=$(v list --all --name 2>&1) || { WARN+=("list failed: ${doms}"); doms=""; }
running=0; total=0
while IFS= read -r dom; do
    [ -n "$dom" ] || continue
    total=$((total + 1))
    st=$(v domstate "$dom" 2>&1)
    case "$st" in
        running) running=$((running + 1)) ;;
        "shut off") ;;
        idle) running=$((running + 1)) ;;
        paused|crashed|pmsuspended|"in shutdown") WARN+=("Guest ${dom} is ${st}") ;;
        *) WARN+=("Guest ${dom} state could not be read: ${st}") ;;
    esac
done <<< "$doms"
echo "Guests: ${total} defined, ${running} running"

section "SUMMARY"
if [ "${#CRIT[@]}" -eq 0 ] && [ "${#WARN[@]}" -eq 0 ]; then
    echo "No warnings or critical findings."
    exit 0
fi
for c in "${CRIT[@]:-}"; do [ -n "$c" ] && echo "  CRITICAL: $c"; done
for w in "${WARN[@]:-}"; do [ -n "$w" ] && echo "  WARNING:  $w"; done
[ "${#CRIT[@]}" -gt 0 ] && exit 2
exit 1
