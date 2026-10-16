#!/usr/bin/env bash
# Proxmox VE inventory report. READ ONLY: it lists nodes, guests, storage,
# networking, backup jobs and HA resources and changes nothing. Run as root on a
# PVE node. Output is plain text for a human; redirect it to a file to keep it.
#
# Usage: bash pve-inventory.sh
#
# Not run against a live node in this vault. Try it on a non-critical node first.

set -u

hr() { printf '%s\n' "------------------------------------------------------------------------"; }
section() { printf '\n%s\n' "$1"; hr; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have pveversion; then
    echo "pveversion not found: this does not look like a Proxmox VE node." >&2
    exit 2
fi

echo "Proxmox VE inventory"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
echo "Host:      $(hostname -f 2>/dev/null || hostname)"
echo "Version:   $(pveversion)"

section "1. NODES"
if pvecm status >/dev/null 2>&1; then
    pvecm status | awk -F: '/^Name:|^Nodes:|^Quorate:|^Expected votes:|^Total votes:/ {print}'
    echo
    pvecm nodes
    echo
    pvesh get /nodes --output-format text 2>/dev/null || true
else
    echo "Standalone node: $(hostname)"
fi

section "2. VIRTUAL MACHINES"
qm list 2>/dev/null || echo "(qm list failed)"
echo
echo "Per-VM cores, memory and disk options (discard and agent shown):"
for vmid in $(qm list 2>/dev/null | awk 'NR>1 {print $1}'); do
    cfg=$(qm config "$vmid" 2>/dev/null)
    name=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="name" {print $2}')
    cores=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="cores" {print $2}')
    mem=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="memory" {print $2}')
    agent=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="agent" {print $2}')
    # Count real disks only: drop CD-ROM and Cloud-Init drives from both numbers.
    diskl=$(printf '%s\n' "$cfg" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' | grep -vE 'media=cdrom|cloudinit' || true)
    disks=$(printf '%s\n' "$diskl" | awk 'NF {n++} END {print n+0}')
    nodiscard=$(printf '%s\n' "$diskl" | awk 'NF && !/discard=on/ {n++} END {print n+0}')
    printf '  %-6s %-28s cores=%-3s mem=%-6sMB agent=%-5s disks=%s without_discard=%s\n' \
        "$vmid" "${name:--}" "${cores:--}" "${mem:--}" "${agent:-0}" "$disks" "$nodiscard"
done

section "3. CONTAINERS"
pct list 2>/dev/null || echo "(pct list failed)"
echo
for ctid in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
    cfg=$(pct config "$ctid" 2>/dev/null)
    host=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="hostname" {print $2}')
    cores=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="cores" {print $2}')
    mem=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="memory" {print $2}')
    unpriv=$(printf '%s\n' "$cfg" | awk -F': ' '$1=="unprivileged" {print $2}')
    printf '  %-6s %-28s cores=%-3s mem=%-6sMB unprivileged=%s\n' "$ctid" "${host:--}" "${cores:--}" "${mem:--}" "${unpriv:-0}"
done

section "4. STORAGE"
pvesm status 2>/dev/null || true
echo
echo "Definitions (/etc/pve/storage.cfg, allow-listed keys only):"
# Print only known structural keys, so nothing credential-like is ever echoed.
grep -E '^[a-z]+: |^[[:space:]]+(content|path|pool|vgname|thinpool|nodes|shared|mountpoint|sparse) ' /etc/pve/storage.cfg 2>/dev/null || echo "  (unreadable)"

section "5. NETWORK"
ip -br addr show 2>/dev/null
echo
bridge link 2>/dev/null | head -40
echo
for bond in /proc/net/bonding/*; do
    [ -f "$bond" ] || continue
    echo "Bond $(basename -- "$bond"):"
    grep -E 'Bonding Mode|MII Status|Slave Interface' "$bond" | head -12
done

section "6. BACKUP JOBS"
pvesh get /cluster/backup --output-format text 2>/dev/null || echo "No cluster backup jobs, or not clustered."

section "7. HA RESOURCES"
echo "Configured:"
ha-manager config 2>/dev/null || echo "  none, or ha-manager unavailable"
echo
echo "Current status:"
ha-manager status 2>/dev/null || echo "  none"

section "SUMMARY"
vm_count=$(qm list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
ct_count=$(pct list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
echo "  VMs on this node:        ${vm_count}"
echo "  Containers on this node: ${ct_count}"
echo "  Note: qm list and pct list show this node only; use the cluster view for all nodes."
