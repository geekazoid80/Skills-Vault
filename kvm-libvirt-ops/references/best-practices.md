# KVM and libvirt best practices reference

Performance and operational practice. Operating rules and the command safety table are in `SKILL.md`. Syntax here has not been run on live systems; defaults vary by QEMU and libvirt version, so measure before and after any tuning.

---

## VirtIO

Use VirtIO for disk, network, balloon and RNG, plus the guest agent channel. For disks, `virtio-scsi` suits many disks, hot-plug and discard; `virtio-blk` is simpler. Emulated devices (e1000, rtl8139, IDE) cost more CPU and belong only in the first minutes of a Windows install, before drivers load.

Windows: attach the virtio-win ISO during setup, load the storage driver to see the disk, and install the guest tools package afterwards for the remaining drivers and the guest agent.

Guest agent: install `qemu-guest-agent` in every guest. It enables graceful shutdown, filesystem freeze for consistent snapshots (`--quiesce`), IP reporting and file operations from the host.

---

## CPU

| Mode | Migration | Use |
|---|---|---|
| `host-passthrough` | Safe only between hosts matching in hardware, QEMU version and microcode | Single host, maximum performance |
| `host-model` | Reproducible guest CPU across similar hosts | Clusters with similar CPUs |
| custom model | Any host that supports the model | Mixed CPU generations |

`<cpu mode='host-passthrough' migratable='on'/>` removes features that would block migration, but the libvirt documentation is explicit that this does not make migration safe by itself.

### Pinning

```xml
<cputune>
  <vcpupin vcpu='0' cpuset='2'/>
  <vcpupin vcpu='1' cpuset='3'/>
  <emulatorpin cpuset='0-1'/>
</cputune>
```

Pin vCPUs to cores on the same NUMA node as the guest memory, keep the emulator threads off the pinned cores, and do not pin two guests to the same cores unless overcommit is intentional. Pinning reduces scheduling freedom, so use it where latency demands it, not by default.

### NUMA

A guest wider than one NUMA node pays remote-memory latency. Fit latency-sensitive guests to a node (`virsh capabilities`, `lscpu`), and bind memory with `<numatune><memory mode='strict' nodeset='0'/></numatune>`. For guests that must span nodes, expose a matching virtual NUMA topology rather than hiding it. Verify with `numastat -c qemu-system-x86_64`.

---

## Memory

**Hugepages** reduce TLB misses for large guests. Reserve them early (kernel command line, e.g. `hugepagesz=1G hugepages=8`) because runtime allocation of 1 GiB pages can fail on a fragmented host. In the domain: `<memoryBacking><hugepages><page size='1' unit='G'/></hugepages></memoryBacking>`. Hugepage memory is not available to the rest of the host.

**Ballooning** (`<memballoon model='virtio'><stats period='10'/></memballoon>`) lets the host reclaim guest memory; it needs the guest driver and adds latency when reclaiming.

**KSM** merges identical pages across guests. It trades CPU for RAM, and merging memory between guests is a side-channel consideration on shared hosts; check `/sys/kernel/mm/ksm/` and disable it for latency-sensitive or mixed-tenancy hosts.

---

## Disk I/O

| `cache=` | Host page cache | Behaviour |
|---|---|---|
| `none` | bypassed (O_DIRECT) | Usual production choice; guest flushes honoured |
| `writethrough` | read cache, writes synchronous | Safe, slow writes |
| `writeback` | used | Fast; guest flush requests are honoured, but host memory holds dirty data |
| `directsync` | bypassed, synchronous | Safest, slowest |
| `unsafe` | used, flushes ignored | Throwaway guests only |

`io='native'` requires direct I/O (`cache='none'`) and suits block devices and fully allocated images; `io='threads'` is the safer choice for sparse files. Libvirt chooses defaults by version, so state what you set and measure it.

**I/O threads:** give busy disks their own thread:

```xml
<iothreads>2</iothreads>
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native' discard='unmap' iothread='1'/>
```

`discard='unmap'` passes guest TRIM to thin storage, which matters on thin-provisioned LVM and on sparse images (see the thin-pool section of `proxmox-ops` for the failure it prevents).

**Formats:** qcow2 for flexibility, raw for latency-sensitive workloads. Preallocate metadata or data to smooth write latency (`qemu-img create -f qcow2 -o preallocation=metadata`).

---

## Network

- Multi-queue VirtIO: `<driver name='vhost' queues='4'/>` and `ethtool -L <nic> combined 4` inside the guest.
- vhost-net moves virtio-net processing into the kernel and is the usual default on current versions; confirm with `lsmod | grep vhost_net`.
- **Bridge netfilter:** with `br_netfilter` loaded, bridged frames traverse the host firewall. If bridged guest traffic is dropped, add explicit allow rules first. Setting `net.bridge.bridge-nf-call-iptables=0` (persist in a file under `/etc/sysctl.d/`) stops that filtering entirely and affects libvirt network filters and container firewalls, so record it as a decision.
- Isolated libvirt networks keep guest-to-guest traffic off the LAN.

---

## Security

- **SELinux (sVirt) or AppArmor** confine each guest. Keep them enabled and fix labels (`restorecon`) instead of disabling them.
- **Access control:** polkit rules decide who may manage guests; avoid shared root. Use `qemu:///session` for unprivileged guests where that is enough.
- **Remote access:** SSH or TLS only.
- **VFIO passthrough:** enable the IOMMU, check IOMMU groups, bind to `vfio-pci`, add the `hostdev`. A device sharing a group with others needs the whole group passed.
- **Network isolation:** isolated networks, host nftables rules for bridge traffic, SR-IOV with MAC and VLAN filtering for hardware-enforced separation.
- Keep QEMU, libvirt and the kernel patched.

---

## Backup

Pattern with an external snapshot:

```bash
virsh snapshot-create-as myvm backup-snap --disk-only --atomic --quiesce
cp /var/lib/libvirt/images/myvm.qcow2 /backup/myvm-$(date +%Y%m%d).qcow2   # the base is now read-only
virsh blockcommit myvm vda --active --pivot --delete   # merge the overlay back
virsh snapshot-delete myvm backup-snap --metadata       # drop the metadata
```

Each step changes state; run them in order on a test guest first, and check `--delete` support in your version. Recent libvirt versions also offer `virsh backup-begin` for push or pull backups with changed-block tracking. Whatever the method: keep several generations, store them off the guest storage, and restore one monthly.
