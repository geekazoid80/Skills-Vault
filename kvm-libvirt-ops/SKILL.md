---
name: kvm-libvirt-ops
description: "Use for day-to-day KVM/QEMU operations with libvirt on a Linux host: virsh domain lifecycle, virt-install provisioning, qemu-img disk work, storage pools, NAT, bridged and macvtap networking, snapshots and live migration, CPU, NUMA, hugepages and cache-mode tuning, VFIO and IOMMU passthrough, and offline guest image tools. Triggers include \"KVM\", \"QEMU\", \"libvirt\", \"virsh\", \"virt-install\", \"qemu-img\", \"virt-manager\", \"libvirtd\", \"virtqemud\", \"virtiofs\", \"VFIO\", \"/dev/kvm\", \"VM will not start permission denied\", \"migration failed unsupported CPU\", \"external snapshot chain\", \"bridge drops VM traffic\", \"virt-customize\". NOT for choosing between hypervisors (virtualization-platform-selection), NOT for Proxmox VE (proxmox-ops), NOT for Docker, Podman or Kubernetes (the container skills), NOT for generic Linux host chores such as systemd, packages or LVM basics (linux-host-ops, linux-host-bringup)."
license: MIT
metadata:
  version: 1.0.0
---

# KVM and libvirt operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: kvm-libvirt-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

KVM is the Linux kernel hypervisor (`kvm` plus `kvm_intel` or `kvm_amd`, exposed as `/dev/kvm`). QEMU runs one userspace process per guest and emulates devices. libvirt is the management layer in front of them: it stores domain XML, manages storage pools and virtual networks, and serves `virsh`, `virt-install`, virt-manager and Cockpit. There is no built-in cluster manager; clustering and HA are built from Pacemaker and Corosync or from higher layers.

**Core principle:** inspect, then change. Know which libvirt daemon model and connection URI you are talking to, read the domain XML, and treat anything that deletes disks, undefines domains or edits live XML as destructive.

> **Caveat on provenance.** Commands and thresholds were reshaped from a community upstream, corrected against the libvirt documentation where checked, and reviewed independently. Syntax has not been run on live systems. Package names, default daemons and option support differ between distributions and versions, so check `man virsh` and the libvirt documentation for the installed release.

## Step 0: establish what you are on

```bash
virsh version                       # library, hypervisor and API versions
virsh uri                           # which connection you are using (qemu:///system for host-wide guests)
systemctl list-units 'libvirtd*' 'virt*d*' --no-legend   # which daemon model is running
lsmod | grep -E '^kvm'              # kvm plus kvm_intel or kvm_amd
ls -l /dev/kvm
```

The libvirt documentation describes two daemon models: the monolithic `libvirtd` and modular per-driver daemons (`virtqemud`, `virtnetworkd`, `virtstoraged` and others, with `virtproxyd` for remote access). Which one a host runs is distribution-dependent, and an upgrade keeps whichever was already in use. Do not run both models on one host; if you change model, stop and disable the old units first and enable the new socket units, as the libvirt daemons page describes.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive or hard to reverse, get explicit approval |
|---|---|---|
| `virsh list --all`, `dominfo`, `domstate`, `dumpxml`, `domstats`, `domblklist`, `domiflist`, `net-list`, `pool-list`, `vol-list`, `nodeinfo`, `capabilities`, `qemu-img info`, `qemu-img check` (on an image no guest is using) | `virsh start`, `shutdown`, `reboot`, `suspend`, `define`, `edit`, `attach-device`, `snapshot-create-as`, `blockcommit`, `blockpull`, `migrate`, `net-start`, `pool-start`, `qemu-img create`, `qemu-img convert` (both write files and can overwrite an existing target, so use a new name), `virt-install`, `vol-create-as` | `virsh destroy` (power off), `undefine --remove-all-storage`, `undefine --nvram`, `snapshot-delete`, `snapshot-revert`, `blockcommit --pivot` (and `--delete`), `vol-delete`, `pool-destroy` on a pool in use, `qemu-img resize --shrink`, `qemu-img check -r`, running `qemu-img` write operations on an image a running guest uses |

On a production host, state the change and its rollback before running a middle-column command, and wait for approval before a right-column one. Never run `qemu-img` write operations against a disk image that a running guest has open.

## Domain lifecycle

```bash
virsh list --all
virsh dominfo myvm
virsh start myvm
virsh shutdown myvm            # ACPI request; needs guest cooperation
virsh destroy myvm             # immediate power off, like pulling the plug; it does not delete anything
virsh dumpxml myvm > myvm.xml  # keep a copy before editing
virsh edit myvm                # edits persistent XML; running guests pick it up at next start
virsh autostart myvm
```

`virsh undefine myvm` removes the definition and keeps disks; `--remove-all-storage` also deletes them, and a UEFI guest needs `--nvram` (or `--keep-nvram`) stated explicitly. Undefining a running domain leaves it running as transient. Use the connection URI deliberately: `qemu:///system` is host-wide, `qemu:///session` is per user, and `qemu+ssh://user@host/system` is remote.

## Provisioning (virt-install)

```bash
virt-install --name ubuntu-24 --memory 4096 --vcpus 4 \
  --disk size=40,format=qcow2,bus=virtio --cdrom /srv/isos/ubuntu-24.04.iso \
  --os-variant ubuntu24.04 --network network=default,model=virtio \
  --graphics spice --video virtio --boot uefi \
  --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 --noautoconsole
```

- `--os-variant` must match a known OS (`virt-install --osinfo list`, or `osinfo-query os` on older versions).
- Cloud images: resize a copy of the image, attach a cloud-init seed, and use `--import`. Do not boot from the shared base image.
- Windows: attach the virtio-win ISO as a second CD-ROM and load the storage driver during setup; use `--boot uefi`, `--machine q35` and a TPM (`--tpm backend.type=emulator,backend.version=2.0`) for Windows 11.

## Disks and storage (qemu-img, pools)

```bash
qemu-img create -f qcow2 myvm.qcow2 50G
qemu-img create -f qcow2 -b base.qcow2 -F qcow2 child.qcow2   # overlay; base must stay unchanged
qemu-img convert -f vmdk -O qcow2 in.vmdk out.qcow2           # writes a new file, leaves the source
qemu-img info --backing-chain myvm.qcow2
virsh pool-define-as vmdisks dir --target /srv/vmdisks && virsh pool-build vmdisks && virsh pool-start vmdisks && virsh pool-autostart vmdisks
virsh vol-create-as vmdisks myvm.qcow2 50G --format qcow2
```

Formats: qcow2 for snapshots, thin provisioning and backing files; raw for the lowest overhead and for LVM or block-device backing. Shrinking an image can destroy data and needs `--shrink`; shrink the filesystem and partitions inside the guest first, and keep a copy. Preallocation (`-o preallocation=metadata` or `full`) trades creation time for steadier write latency.

## Snapshots

libvirt supports two kinds, and the choice matters:

- **External snapshots** redirect new writes into an overlay file. Create a disk-only one with `virsh snapshot-create-as myvm snap1 --disk-only --atomic`; add `--quiesce` when the guest agent is running to freeze filesystems. The libvirt documentation notes external snapshots are quick when memory is not also saved. The overlay chain grows until you merge it with `virsh blockcommit` (and `--pivot`) or `blockpull`; an unmerged chain wastes space and slows reads.
- **Internal snapshots** store state inside the qcow2 file. The libvirt documentation notes that for QEMU they currently cause lengthy downtime that is incompatible with freezing guest I/O, so avoid them for running production guests.

`virsh snapshot-revert` support differs by snapshot type and version; check `man virsh` before relying on a revert of an external snapshot, and prefer restoring from a tested backup. A snapshot is not a backup.

## Live migration

```bash
virsh migrate --live --persistent --undefinesource myvm qemu+ssh://dest/system
virsh migrate --live --copy-storage-all myvm qemu+ssh://dest/system   # no shared storage
virsh domjobinfo myvm          # progress
virsh domjobabort myvm         # cancel an in-progress job
```

- By default migration changes no configuration on either host: `--persistent` creates the definition on the destination and `--undefinesource` removes it from the source.
- With `--copy-storage-all` the destination images must already exist with the correct format and size unless they live in a libvirt storage pool; with `--copy-storage-inc` you must always pre-create them.
- Tunnelled transport needs one firewall port, but the libvirt migration documentation says non-shared-storage migration, parallel migration and post-copy may not be available with it. Native transport may need a wide port range open.
- `--postcopy` only enables post-copy; the migration starts in pre-copy and switches with `virsh migrate-postcopy` or `--postcopy-after-precopy` (see `man virsh`). Once switched, the guest depends on the source host until the transfer ends, so a source failure loses the guest.
- CPU compatibility decides most failures. `host-model` keeps a reproducible guest CPU; `host-passthrough` is only safe between hosts that match in hardware, QEMU version and microcode, even with `migratable='on'`.

## Networking

| Type | Use | Note |
|---|---|---|
| NAT (`virbr0`, network `default`) | Outbound access for lab guests | dnsmasq DHCP and DNS; not reachable from the LAN |
| Bridge (`br0`) | Guests as LAN peers | Build the bridge with NetworkManager, netplan or ifupdown, not by hand |
| macvtap | Direct on a NIC | The host cannot talk to the guest through the same NIC |
| Open vSwitch | VLAN trunks, tunnels | Needs `<virtualport type='openvswitch'/>` |
| SR-IOV VF | Near-native NIC | Needs IOMMU; usually ties the guest to the host for migration |
| Isolated | Guest-to-guest only | |

```bash
virsh net-list --all ; virsh net-dumpxml default ; virsh net-dhcp-leases default
virsh net-autostart default
```

**Bridge netfilter:** with the `br_netfilter` module loaded, bridged frames pass through the host firewall. If bridged guest traffic is dropped, look at the host firewall rules first. Setting `net.bridge.bridge-nf-call-iptables=0` stops that filtering altogether, and it also affects libvirt network filters and container firewalls that rely on it, so treat it as a deliberate, documented decision rather than a routine fix.

## Performance and CPU

- **VirtIO everywhere:** VirtIO disk (`virtio-blk` or `virtio-scsi`), VirtIO network, balloon, RNG and a guest-agent channel. Emulated e1000 or IDE devices cost more CPU; use them only to get a Windows installer started.
- **CPU mode:** `host-model` for clusters, `host-passthrough` for one host or matched hosts, custom models for mixed estates.
- **Disk cache:** `cache='none'` (direct I/O) is the usual production choice. `writeback` honours the guest's flush requests but uses host page cache; `unsafe` ignores flushes and is for throwaway guests only. `io='native'` needs `cache='none'` and suits block devices and fully allocated images; `io='threads'` is safer for sparse files. Use `iothreads` for busy disks. Measure before and after; defaults differ by version.
- **Memory:** hugepages (2 MiB or 1 GiB) cut TLB misses for large guests; reserve them at boot where fragmentation matters. Ballooning needs the guest driver. KSM saves RAM at some CPU cost and is a side-channel consideration on mixed-tenancy hosts.
- **NUMA:** size latency-sensitive guests to fit one node, and pin vCPUs and memory to the same node (`virsh capabilities`, `numatune`, `cputune`). Keep emulator threads off the pinned cores.

## Passthrough (VFIO, SR-IOV)

Enable the IOMMU in firmware and on the kernel command line (`intel_iommu=on` or `amd_iommu=on`; many kernels enable AMD by default), check IOMMU groups under `/sys/kernel/iommu_groups`, bind the device to `vfio-pci`, then add a `hostdev` to the domain. A device that shares a group with others can only be passed with the whole group. A guest with a passed-through device is generally not live-migratable; VFIO variant-driver devices can be, where the kernel, QEMU and libvirt versions all support it (libvirt added support in 9.8; verify for your stack).

## Guest image tools

`virt-customize`, `virt-sysprep`, `virt-filesystems`, `virt-df` and `virt-cat` (libguestfs) work on an image **offline**; never run them on an image a running guest uses. Do not put passwords on the command line: use `--root-password file:/path` or `--ssh-inject root:file:/path/key.pub`, and see `secrets-hygiene`.

## Backup

A disk-only external snapshot with `--quiesce`, copy of the now read-only base image, then `blockcommit --active --pivot` is the classic pattern. Recent libvirt versions also offer `virsh backup-begin` for push or pull backups (check your version). Keep backups on separate storage from the guest disks, keep several generations, and test a restore every month.

## Security

Keep SELinux (sVirt) or AppArmor enabled; they confine each guest process. Control who may manage guests with polkit rather than shared root. Use isolated networks for traffic that must not reach the LAN, and protect remote libvirt access with SSH or TLS; plain `qemu+tcp` is unencrypted. Patch QEMU and the kernel promptly.

## Common pitfalls

1. IOMMU not enabled before a passthrough attempt.
2. Emulated devices left in place after the OS has VirtIO drivers.
3. No guest agent, so no graceful shutdown, no quiesce and no IP reporting.
4. External snapshot overlays never merged.
5. `virsh undefine --remove-all-storage` run to "clean up" without checking what else uses the disk.
6. Mixing libvirtd and modular daemons, or a stale daemon on the other model.
7. `host-passthrough` on hosts that are later mixed into a migration pool.
8. Migration tested only on the happy path; CPU, storage and firewall faults appear in production.
9. Disabling bridge netfilter as a first response to dropped traffic.
10. Running `qemu-img` write operations on an image that a live guest has open.

## Red flags

- A destructive command in the right-hand column with no stated rollback.
- A password or token on a `virt-customize`, `virsh` or `qemu-img` command line.
- An image shared between a running guest and an offline tool.
- "Snapshot" offered as the backup plan.
- A migration plan with no CPU model decision.

## References and scripts

- `references/architecture.md`: KVM, QEMU, libvirt daemons, XML, storage, networking, migration.
- `references/best-practices.md`: VirtIO, CPU, NUMA, hugepages, cache modes, I/O threads, security, backup.
- `references/diagnostics.md`: statistics, logs, KVM-level checks, failure tables.
- `scripts/virsh-health.sh`: read-only host health (modules, daemons, pools, networks, guests, disk space). Run on a KVM host.
- `scripts/virsh-inventory.sh`: read-only inventory of guests, disks, NICs and pools.

Both scripts only read state. They pass `shellcheck` and their logic (including failed queries) was exercised against stubbed command output, but neither has been run against a live host; run them on a non-critical host first. Thresholds in `virsh-health.sh`: host memory and filesystem warn at 90 per cent or more; storage pools warn at 80 and are critical at 90.

## Boundaries

- Hypervisor choice and migration between platforms: `virtualization-platform-selection`.
- Proxmox VE (which wraps KVM with its own tooling): `proxmox-ops`.
- Host-level Linux work, LVM basics, systemd, backups: `linux-host-ops`, `linux-host-bringup`.
- Containers and Kubernetes: `container-runtime-selection`, `podman-ops`, `kubernetes-ops`.
- Overlay networking: `evpn-vxlan-fabric`.
- Guests as code: `terraform-iac-ops`, `ansible-automation-platform`.
- Credentials: `secrets-hygiene`.

## Bottom line

Know the daemon model and URI, read the XML before editing it, use VirtIO and the guest agent, pick the CPU model before you need to migrate, merge external snapshots, and never treat a snapshot as a backup.
