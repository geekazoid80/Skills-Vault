#!/usr/bin/env bash
# Proxmox VE node and cluster health check. READ ONLY: it runs status and list
# commands and changes nothing. Run as root on a PVE node.
#
# Usage: bash pve-health.sh
# Exit:  0 healthy, 1 warnings only, 2 critical findings.
#
# Not run against a live node in this vault. Try it on a non-critical node first.
# Thresholds: filesystem and memory warn at 90 per cent or more, thin pool data
# and metadata warn at 80 and are critical at 90.

set -u
export LC_ALL=C   # dot-decimal numbers from lvs and friends, whatever the host locale

CLUSTERED=no
[ -e /etc/pve/corosync.conf ] && CLUSTERED=yes

WARN=()
CRIT=()

hr() { printf '%s\n' "------------------------------------------------------------------------"; }
section() { printf '\n%s\n' "$1"; hr; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "Proxmox VE health report"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
echo "Host:      $(hostname -f 2>/dev/null || hostname)"
echo "Version:   $(pveversion 2>/dev/null || echo unknown)"

if ! have pveversion; then
    echo "pveversion not found: this does not look like a Proxmox VE node." >&2
    exit 2
fi

section "1. NODE"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
echo "Load:   $(cut -d' ' -f1-3 /proc/loadavg)"
free -h | grep -E '^(Mem|Swap)'
mem_total=$(free | awk '/^Mem/ {print $2}')
mem_used=$(free | awk '/^Mem/ {print $3}')
if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
    mem_pct=$((mem_used * 100 / mem_total))
    [ "$mem_pct" -ge 90 ] && WARN+=("Node memory use at ${mem_pct} per cent")
fi

section "2. CLUSTER AND QUORUM"
if [ "$CLUSTERED" = "yes" ]; then
    if pvecm_out=$(pvecm status 2>&1); then
        printf '%s\n' "$pvecm_out" | sed -n '1,40p'
        quorate=$(printf '%s\n' "$pvecm_out" | awk -F: '/^Quorate/ {gsub(/ /, "", $2); print $2}')
        if [ "$quorate" != "Yes" ]; then
            CRIT+=("Cluster is not quorate (Quorate: ${quorate:-unknown})")
        fi
    else
        printf '%s\n' "$pvecm_out"
        CRIT+=("Node has a cluster configuration but pvecm status fails (Corosync down or cluster filesystem unavailable)")
    fi
else
    echo "Standalone node (no /etc/pve/corosync.conf)."
fi

section "3. HA MANAGER"
if have ha-manager; then
    ha_out=$(ha-manager status 2>/dev/null)
    echo "${ha_out:-No HA status available.}"
    if printf '%s\n' "$ha_out" | grep -qE ',[[:space:]]*(error|fence)\)'; then
        CRIT+=("An HA resource is in error or fence state")
    fi
else
    echo "ha-manager not available."
fi

section "4. STORAGE"
pvesm status 2>/dev/null || echo "(pvesm status failed)"
while read -r use mount; do
    use=${use%\%}
    case "$use" in ''|*[!0-9]*) continue ;; esac
    [ "$use" -ge 90 ] && WARN+=("Filesystem ${mount} at ${use} per cent")
done < <(df -P -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {print $5, $6}')

echo
echo "LVM thin pools (data and metadata use):"
if have lvs; then
    if ! lvs_out=$(lvs --noheadings --separator '|' -o lv_name,vg_name,lv_size,data_percent,metadata_percent,lv_attr 2>&1); then
        echo "  lvs failed: ${lvs_out}"
        WARN+=("lvs failed, thin pool use could not be read")
        lvs_out=""
    fi
    # Thin pools only: the first character of lv_attr is 't' for a thin pool.
    while IFS='|' read -r lv vg size data meta attr; do
        lv=${lv// /}; vg=${vg// /}; size=${size// /}; data=${data// /}; meta=${meta// /}; attr=${attr// /}
        [ "${attr:0:1}" = "t" ] || continue
        printf '  %s/%s size=%s data=%s%% metadata=%s%%\n' "$vg" "$lv" "$size" "$data" "$meta"
        for kind in data meta; do
            val=${!kind}
            val=${val%%.*}
            case "$val" in ''|*[!0-9]*) continue ;; esac
            if [ "$val" -ge 90 ]; then CRIT+=("Thin pool ${vg}/${lv} ${kind} use at ${val} per cent")
            elif [ "$val" -ge 80 ]; then WARN+=("Thin pool ${vg}/${lv} ${kind} use at ${val} per cent"); fi
        done
    done <<< "$lvs_out"
    echo
    echo "Volume group free space:"
    vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null | sed 's/^/  /'
else
    echo "  lvs not available."
fi

section "5. ZFS"
if have zpool && [ -n "$(zpool list -H 2>/dev/null)" ]; then
    zpool list
    echo
    zpool_x=$(zpool status -x 2>&1)
    echo "$zpool_x"
    case "$zpool_x" in
        *"all pools are healthy"*) : ;;
        *) CRIT+=("zpool status -x reports a pool that is not healthy") ;;
    esac
    arcstats=/proc/spl/kstat/zfs/arcstats
    if [ -r "$arcstats" ]; then
        awk '$1 == "size" {s=$3} $1 == "c_max" {m=$3} END {printf "ARC size %.1f GiB, ARC max %.1f GiB\n", s/1073741824, m/1073741824}' "$arcstats"
    fi
else
    echo "No ZFS pools."
fi

section "6. CEPH"
if have ceph; then
    if ceph_health=$(ceph --connect-timeout 10 health 2>&1); then
        echo "Health: ${ceph_health}"
        ceph --connect-timeout 10 status 2>/dev/null | sed -n '1,25p'
        case "$ceph_health" in
            HEALTH_ERR*) CRIT+=("Ceph health is HEALTH_ERR") ;;
            HEALTH_WARN*) WARN+=("Ceph health is HEALTH_WARN") ;;
        esac
    else
        echo "ceph is installed but the health query failed: ${ceph_health}"
        WARN+=("ceph is installed but its health could not be read")
    fi
else
    echo "Ceph not installed."
fi

section "7. GUESTS"
vm_total=$(qm list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
vm_run=$(qm list 2>/dev/null | awk 'NR>1 && $3=="running"' | wc -l | tr -d ' ')
ct_total=$(pct list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
ct_run=$(pct list 2>/dev/null | awk 'NR>1 && $2=="running"' | wc -l | tr -d ' ')
echo "VMs on this node:        ${vm_total} (${vm_run} running)"
echo "Containers on this node: ${ct_total} (${ct_run} running)"

section "8. SERVICES"
for svc in pvedaemon pveproxy pvestatd pve-cluster corosync pve-ha-lrm pve-ha-crm pve-firewall; do
    state=$(systemctl is-active "$svc" 2>/dev/null || true)
    echo "  ${svc}: ${state:-not checked}"
    case "$svc:$state" in
        *:) : ;; # systemctl unavailable, nothing to judge
        corosync:inactive|corosync:unknown) [ "$CLUSTERED" = "no" ] || WARN+=("Service corosync is ${state:-unknown} on a clustered node") ;; # not used on a standalone node
        *:active) : ;;
        *:*) WARN+=("Service ${svc} is ${state:-unknown}") ;;
    esac
done

section "SUMMARY"
if [ "${#CRIT[@]}" -eq 0 ] && [ "${#WARN[@]}" -eq 0 ]; then
    echo "No warnings or critical findings."
    exit 0
fi
for c in "${CRIT[@]:-}"; do [ -n "$c" ] && echo "  CRITICAL: $c"; done
for w in "${WARN[@]:-}"; do [ -n "$w" ] && echo "  WARNING:  $w"; done
[ "${#CRIT[@]}" -gt 0 ] && exit 2
exit 1
