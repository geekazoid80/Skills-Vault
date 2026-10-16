# KVM and libvirt diagnostics reference

Read-only diagnostics first; commands that change state or generate load are marked. Syntax here has not been run on live systems; check `man virsh` for the installed release.

---

## Monitoring

```bash
virt-top                           # top-like view of guests (package virt-top)
virsh domstats myvm                # all counters
virsh domblkstat myvm vda          # block I/O
virsh domifstat myvm vnet0         # network I/O (device name from virsh domiflist)
virsh vcpuinfo myvm
virsh dommemstat myvm              # balloon statistics need the guest driver
virsh domjobinfo myvm              # migration or backup job progress
virsh domblklist myvm ; virsh domiflist myvm ; virsh dominfo myvm
```

---

## KVM level

```bash
lsmod | grep kvm
cat /sys/module/kvm_intel/parameters/ept   # or kvm_amd/parameters/npt
cat /sys/module/kvm_intel/parameters/nested
grep -i huge /proc/meminfo
ls /sys/kernel/debug/kvm/                  # needs debugfs and root; one file per counter, which kvm_stat reads for you
```

`perf kvm stat live` shows VM exit reasons but adds load; use it briefly. Many `io_exits` or `mmio_exits` point to emulated rather than VirtIO devices.

---

## Logs

| What | Where |
|---|---|
| Per-guest QEMU log | `/var/log/libvirt/qemu/<name>.log` |
| Monolithic daemon | `journalctl -u libvirtd` |
| Modular daemons | `journalctl -u virtqemud`, `virtstoraged`, `virtnetworkd` |
| Audit denials (SELinux) | `ausearch -m avc -ts recent` |

The per-guest log holds the QEMU command line, device initialisation errors and crash output; read it first for any "failed to start" report.

---

## Guest will not start

| Message or symptom | Check | Likely cause |
|---|---|---|
| Cannot access storage file | `virsh dumpxml`, file path, ownership and mode | Wrong path, missing pool, permissions |
| Permission denied | SELinux or AppArmor denials, image label | Image outside the labelled location; fix the label, do not disable the policy |
| Failed to connect to monitor | QEMU log | QEMU exited early |
| Network not found | `virsh net-list --all` | Network defined but not started |
| CPU model or feature unsupported | `virsh capabilities`, domain `<cpu>` | Host lacks the feature; change the CPU mode or model |
| Firmware or loader not found | OVMF package installed? | Install `ovmf` or `edk2-ovmf` |
| `/dev/kvm` missing | `lsmod`, firmware settings | Virtualisation disabled in firmware or module not loaded |

## Migration failures

| Error | Cause | Fix |
|---|---|---|
| Unsupported CPU or feature | Source and destination CPUs differ | Use `host-model` or a custom model |
| Cannot access storage | Disk is local to the source | Use shared storage or a storage-copy option |
| Destination image missing | `--copy-storage-*` needs the target image first | Pre-create it (or use a pool) |
| Connection refused | Daemon or firewall on the destination | Check units, sockets and ports |
| Timed out or never converges | Dirty page rate exceeds the link | More bandwidth, compression, or post-copy with its risk |
| Domain already exists | Same name on the destination | Rename, or remove the stale definition deliberately |

## Storage

```bash
qemu-img info --backing-chain myvm.qcow2   # read-only
qemu-img check myvm.qcow2                  # only on an image no guest has open; add -r only after a backup
virsh pool-info mypool ; virsh pool-refresh mypool   # refresh rescans the pool
lvs -a                                     # when pools are LVM thin
```

A long backing chain means unmerged external snapshots; merge with `blockcommit` in a planned window.

## Network

```bash
virsh net-list --all ; virsh net-dhcp-leases default
ip -br link ; ip -d link show virbr0 ; bridge fdb show br virbr0
sysctl net.bridge.bridge-nf-call-iptables   # reading only
nft list ruleset | head -60                  # or iptables-save; look for bridge drops
```

## Performance

| Symptom | Diagnostic | Resolution |
|---|---|---|
| High CPU | `virt-top`, `virsh vcpuinfo`, host `top` | Check overcommit, steal time in the guest, pinning |
| Slow disk | `virsh domblkstat`, guest `iostat` | VirtIO, `cache='none'`, I/O threads, check the snapshot chain |
| Slow network | `virsh domifstat`, `iperf3` between guest and peer | VirtIO, vhost, multi-queue, MTU |
| Memory pressure | `virsh dommemstat`, host `free` | More RAM, hugepages, balloon tuning |
| NUMA penalty | `numastat -c qemu-system-x86_64` | Fit the guest to one node and pin |

`fio` and `iperf3` generate load; run them off peak and never against production disks without agreement.

## Handy

```bash
virsh list --all --title
ps -eo pid,args | grep '[q]emu-system'
cat /run/libvirt/qemu/myvm.pid                         # the QEMU process ID (the libvirt domain ID is not a PID)
tr '\0' '\n' < /proc/"$(cat /run/libvirt/qemu/myvm.pid)"/cmdline   # its command line; the pid file path can differ by setup
virsh qemu-monitor-command myvm --hmp 'info status'      # read-only query, but the monitor bypasses libvirt; stay with info commands
```
