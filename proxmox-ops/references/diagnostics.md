# Proxmox VE diagnostics reference

Read-only diagnostics first. Commands that change state are marked. Syntax here has not been run on live systems; run `man <command>` on the installed version if an option is rejected.

---

## Web UI

The UI on port 8006 shows node summary graphs (CPU, memory, I/O), per-guest status, the Ceph dashboard, the task log with results and durations, and a per-node syslog viewer. The task log is the first place to look when an operation fails.

---

## Virtual machines

```bash
qm list
qm status <vmid>
qm config <vmid>
qm showcmd <vmid>                          # the exact QEMU command line
qm agent <vmid> ping                       # needs the guest agent running
qm agent <vmid> network-get-interfaces     # guest IP addresses
```

| Symptom | Check | Likely cause |
|---|---|---|
| Will not start | Error text from `qm start`; `qm config` | Storage unavailable, disk locked, missing bridge |
| `running (io-error)`, CPU idle | Host pool: `lvs`, `zpool list`, `ceph df` | Backing storage full (thin pool at 100 per cent) |
| Unresponsive | `qm agent <vmid> ping` | Agent absent, or guest hung |
| Slow disk | Per-VM I/O graphs, `iostat -x 1 5` on the host | Storage contention, long snapshot chain |
| No network | `qm config <vmid>` net0 | Bridge missing, wrong VLAN tag |
| Migration fails | Task log | Shared storage not shared, CPU mismatch, network |

---

## Containers

```bash
pct list
pct status <ctid>
pct config <ctid>
pct df <ctid>
pct exec <ctid> -- systemctl --failed
pct exec <ctid> -- df -h
```

---

## Cluster health

```bash
pvecm status                  # "Quorate: Yes" expected
pvecm nodes
corosync-quorumtool -s
corosync-cfgtool -s           # link status per ring
ha-manager status
pvesh get /cluster/resources --type node
```

| Check | Healthy |
|---|---|
| Quorum | `Quorate: Yes` |
| Nodes | All listed and online |
| HA resources | `started` (or the requested state); none in `error` or `fence` |
| Corosync links | All links connected |

A node that lost quorum shows a read-only `/etc/pve`. Diagnose the network between nodes before using `pvecm expected`, which is a recovery override and changes state.

---

## Storage

```bash
pvesm status
zpool list ; zpool status -x                # -x prints only unhealthy pools
lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent
vgs -o vg_name,vg_size,vg_free
grep -H discard /etc/pve/qemu-server/*.conf # which disks have discard set
```

Thin pool triage: read `data_percent` and `metadata_percent` on the host (the guest cannot see them). Compare with `vgs` free space before suggesting an extension. A running timer for `fstrim` in the guest does not prove reclaim works; confirm `discard` on the disk and watch `lvs` fall after a trim.

## Ceph

```bash
ceph status
ceph health detail
ceph osd status
ceph osd df
ceph df
ceph pg stat
ceph osd perf
```

| Symptom | Check | Next step |
|---|---|---|
| `HEALTH_WARN` | `ceph health detail` | Follow the specific warning |
| OSD down | `ceph osd status` | Check the node and disk, then the service |
| Degraded placement groups | `ceph pg stat` | Wait for recovery or add capacity |
| Near-full OSDs | `ceph osd df` | Add capacity or rebalance before they fill |
| Slow requests | `ceph health detail`, `ceph osd perf` | OSD latency, then the network |

`ceph tell osd.<id> bench` generates load; run it only when load is acceptable. `qm monitor <vmid>` opens an interactive QEMU monitor that can change a running guest; it is not a read-only diagnostic.

---

## Logs

| Component | Where |
|---|---|
| API daemon | `journalctl -u pvedaemon` |
| Web proxy | `journalctl -u pveproxy` |
| Corosync | `journalctl -u corosync` |
| HA | `journalctl -u pve-ha-crm`, `journalctl -u pve-ha-lrm` |
| Firewall | `journalctl -u pve-firewall` |
| Ceph | `journalctl -u 'ceph-*'` (or `ceph-mon@<host>`, `ceph-osd@<id>`) |
| Tasks | `/var/log/pve/tasks/` (UI task log is easier) |

```bash
journalctl -p err --since "1 hour ago"
journalctl -u corosync --since today | grep -iE 'member|join|leave|link'
journalctl -u pve-ha-crm --since today | grep -iE 'fence|recover|migrate|error'
journalctl --since today | grep -iE 'zfs|lvm|ceph|thin' | grep -iE 'error|fail|warn' | tail -20
```

---

## Network

```bash
ip -br link
ip -d link show vmbr0
bridge link
bridge vlan show
cat /proc/net/bonding/bond0
pvesh get /cluster/sdn/vnets
pvesh get /cluster/sdn/zones
ip -s link show vmbr0                       # drops and errors
ping -M do -s 8972 <peer>                   # MTU 9000 path check
ss -tlnp                                    # listening ports
```

`brctl` comes from the legacy `bridge-utils` package and may be absent; `bridge` and `ip` are always available.

---

## Performance

**High CPU:** node summary graphs, then the top guests; compare the vCPU to core ratio against the node's cores; inside the guest use `top` and check steal time.

**High memory:** `free -h` on the host; ZFS ARC size from `/proc/spl/kstat/zfs/arcstats` (`size` against `c_max`); KSM from `/sys/kernel/mm/ksm/pages_shared`; the largest guests in the UI.

**Storage:** `iostat -x 1 5` for devices, `zpool iostat -v 1 5` for pools, `ceph osd perf` for Ceph.

**Network:** `ip -s link`, `cat /proc/net/bonding/bond0`, and `iperf3 -c <peer>` between nodes. `iperf3` generates load, so run it off peak.
