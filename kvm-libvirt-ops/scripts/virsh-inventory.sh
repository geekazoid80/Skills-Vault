#!/usr/bin/env bash
# KVM and libvirt inventory. READ ONLY: it lists guests, their disks and
# interfaces, storage pools and networks and changes nothing. Run on the KVM host.
#
# Usage: bash virsh-inventory.sh
#        LIBVIRT_URI=qemu:///session bash virsh-inventory.sh
#
# Not run against a live host in this vault. Try it on a non-critical host first.

set -u
export LC_ALL=C

URI=${LIBVIRT_URI:-qemu:///system}

hr() { printf '%s\n' "------------------------------------------------------------------------"; }
section() { printf '\n%s\n' "$1"; hr; }
v() { virsh -c "$URI" "$@"; }

if ! command -v virsh >/dev/null 2>&1; then
    echo "virsh not found: libvirt client tools are not installed." >&2
    exit 2
fi
if ! v version >/dev/null 2>&1; then
    echo "virsh cannot connect to ${URI}" >&2
    exit 2
fi

echo "KVM and libvirt inventory"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
echo "Host:      $(hostname -f 2>/dev/null || hostname)"
echo "URI:       ${URI}"

section "1. HOST"
v nodeinfo 2>&1 | sed -n '1,12p'

section "2. GUESTS"
printf '  %-28s %-12s %-6s %-10s %s\n' "NAME" "STATE" "VCPUS" "MEM(MiB)" "AUTOSTART"
total=0
while IFS= read -r dom; do
    [ -n "$dom" ] || continue
    total=$((total + 1))
    info=$(v dominfo "$dom" 2>&1)
    state=$(v domstate "$dom" 2>&1)
    vcpus=$(printf '%s\n' "$info" | awk -F': *' '/^CPU\(s\)/ {print $2}')
    memkib=$(printf '%s\n' "$info" | awk -F': *' '/^Max memory/ {print $2}' | awk '{print $1}')
    auto=$(printf '%s\n' "$info" | awk -F': *' '/^Autostart/ {print $2}')
    case "$memkib" in ''|*[!0-9]*) memmib="-" ;; *) memmib=$((memkib / 1024)) ;; esac
    printf '  %-28s %-12s %-6s %-10s %s\n' "$dom" "$state" "${vcpus:--}" "$memmib" "${auto:--}"
done <<< "$(v list --all --name 2>/dev/null)"
echo
echo "Total guests: ${total}"

section "3. DISKS AND INTERFACES PER GUEST"
while IFS= read -r dom; do
    [ -n "$dom" ] || continue
    echo "${dom}:"
    v domblklist "$dom" --details 2>/dev/null | awk 'NR>2 && NF {print "  disk  " $0}'
    v domiflist "$dom" 2>/dev/null | awk 'NR>2 && NF {print "  nic   " $0}'
done <<< "$(v list --all --name 2>/dev/null)"

section "4. STORAGE POOLS"
v pool-list --all --details 2>&1 || v pool-list --all 2>&1

section "5. NETWORKS"
v net-list --all 2>&1

section "SUMMARY"
echo "  Guests: ${total}"
