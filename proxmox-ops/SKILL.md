---
name: proxmox-ops
description: "Use for day-to-day Proxmox VE (PVE) operations and troubleshooting: QEMU/KVM guests with qm, LXC containers with pct, clusters with pvecm and Corosync quorum, the HA Manager and watchdog fencing, ZFS and LVM-thin local storage, Ceph, vzdump and Proxmox Backup Server, bridges, VLANs, bonds and SDN, and the pvesh REST API. Triggers include \"Proxmox\", \"PVE\", \"qm\", \"pct\", \"pvecm\", \"pvesh\", \"vzdump\", \"PBS\", \"lost quorum\", \"VM is in io-error\", \"thin pool full\", \"LVM-thin data 100%\", \"discard\", \"HA resource in error\", \"node fenced\", \"migration failed\", \"ZFS ARC\", \"Ceph HEALTH_WARN on Proxmox\". NOT for choosing between hypervisors (virtualization-platform-selection), NOT for Docker, Podman or Kubernetes (the container skills; LXC here means only Proxmox system containers), NOT for generic Linux host chores such as systemd, journald or fstab (linux-host-ops), NOT for EVPN overlay design (evpn-vxlan-fabric)."
license: MIT
metadata:
  version: 1.0.0
---

# Proxmox VE operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: proxmox-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Proxmox VE is Debian plus a Proxmox kernel, QEMU/KVM for virtual machines, LXC for system containers, Corosync and the `pmxcfs` cluster filesystem under `/etc/pve`, an HA Manager, and a web UI on port 8006. Everything the UI does is a REST API call, and `pvesh` exposes the same API on the command line. This skill is the operating guide: how to look before touching, which commands change state, and the failure modes that actually take hosts down.

**Core principle:** read first, change second. Run the read-only health and inventory scripts, confirm the PVE version and whether the node is clustered, and only then reach for a command that changes state.

> **Caveat on provenance.** Command syntax and thresholds here were reshaped from a community upstream, corrected against the Proxmox VE documentation where checked, and reviewed independently. Syntax has not been run on live systems. Check anything version-specific with `man qm` or the admin guide for the installed version before relying on it.

## Step 0: establish what you are on

```bash
pveversion -v | head -5      # PVE and kernel versions
pvecm status                 # fails on a standalone node; that is itself the answer
pvesm status                 # storages, type, free space
```

Version matters. As of 2026-10-16 the Proxmox roadmap lists 9.1 (19 November 2025) and 9.2 (21 May 2026) as the Debian 13 line; 8.x is the Debian 12 line. Read the release notes for the installed minor version before advising on firewall backend, Ceph release, HA configuration (see HA below) or snapshot behaviour.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive or hard to reverse, get explicit approval |
|---|---|---|
| `qm list`, `qm status`, `qm config`, `qm showcmd`, `pct list`, `pct config`, `pvecm status`, `pvecm nodes`, `ha-manager status`, `pvesm status`, `pvesh get ...`, `zpool status`, `lvs`, `ceph status` | `qm start`, `qm shutdown`, `qm snapshot`, `qm migrate`, `qm set`, `qm disk move`, `pct set`, `vzdump`, `fstrim`, `ha-manager add`, `ha-manager set`, `ha-manager crm-command node-maintenance enable`, `pvesh set`, `pvesh create` | `qm stop`, `qm destroy`, `pct destroy`, `qm rollback`, `qm disk resize` (growth cannot be undone; shrinking is unsupported), `qm disk move --delete 1`, `pvecm expected`, `pvecm delnode`, `zpool destroy`, `lvremove`, `zfs destroy`, `ceph osd out`, `ceph osd purge` |

On a production node, state the change and the rollback before running a middle-column command, and wait for approval before a right-column one.

## Virtual machines (qm)

Config lives in `/etc/pve/qemu-server/<vmid>.conf` and is cluster-wide.

```bash
qm list
qm status 100
qm config 100
qm create 200 --name myvm --memory 4096 --cores 2 --cpu x86-64-v2-AES \
  --net0 virtio,bridge=vmbr0 --scsi0 local-lvm:32,discard=on,iothread=1 --scsihw virtio-scsi-single
qm disk resize 100 scsi0 +10G       # grow only; shrinking is unsupported
qm disk move 100 scsi0 ceph-vm       # copies; the source stays as an unused disk unless you pass --delete 1
qm snapshot 100 pre-update           # includes RAM only with --vmstate 1
qm migrate 100 node2 --online        # shared storage
qm migrate 100 node2 --online --with-local-disks   # copies local disks as well
```

Defaults worth setting for new guests:

- **Disk controller:** VirtIO SCSI single with the **IO Thread** option on each disk is the documented performance choice. IO Thread works only with VirtIO SCSI single or VirtIO Block.
- **Discard:** tick `discard=on` on thin-backed disks so a TRIM-enabled guest returns blocks to the pool. VirtIO Block needs a guest kernel 5.0 or later for discard. The SSD emulation flag is not supported on VirtIO Block. Without discard, deleting data inside the guest never shrinks the host-side image (see Thin-pool exhaustion).
- **Guest agent:** install `qemu-guest-agent` and set `agent: 1`. Backups in snapshot mode use the agent to freeze and thaw the guest filesystem, and it reports IP addresses.
- **CPU type:** the web UI defaults new VMs to `x86-64-v2-AES`, but the backend default (for example `qm create` with no `--cpu`) is `kvm64`, so set the type explicitly. `host` gives maximum performance but only suits a single node or identical hardware. For live migration across mixed hosts, pick the lowest CPU generation in the cluster. Migration between Intel and AMD hosts is not guaranteed to work.
- **Ballooning:** leave it enabled in general; the documentation does not recommend the balloon driver on Windows machines that are critical.
- **Windows:** install the virtio-win drivers before moving to VirtIO disks or NICs.
- **Snapshots are not backups.** They stay on the same storage and degrade over time. Use vzdump or Proxmox Backup Server.

## Containers (pct)

LXC here means Proxmox system containers: a full init system sharing the host kernel. They are not Docker or Podman application containers.

```bash
pct list
pct config 101
pct create 201 local:vztmpl/<template-file> --hostname myct --memory 512 \
  --rootfs local-lvm:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp --unprivileged 1
pct exec 101 -- systemctl --failed
pveam update && pveam available --section system   # template file names change; list before downloading
```

Prefer unprivileged containers (container root maps to a high host UID). Use privileged ones only when a workload needs host-level device access, and treat that as a security exception. Enable `nesting=1` only when running Docker or Podman inside the container, and restrict bind mounts to read-only where possible.

## Clustering and quorum

```bash
pvecm status           # look for "Quorate: Yes"
pvecm nodes
corosync-cfgtool -s    # link status per Corosync ring
```

- Corosync needs low latency more than bandwidth. The cluster admin guide asks for under 5 ms between nodes and says latencies above roughly 10 ms are unlikely to work with more than three nodes. A dedicated 1 Gbit link is enough in most cases; add a second link (`link1`) for redundancy.
- HA needs at least three nodes for a reliable quorum. A two-node cluster needs a QDevice for a third vote.
- Without quorum the cluster filesystem goes read-only and guest changes are refused. **Do not** run `pvecm expected 1` to "get going": it overrides the vote requirement and is for controlled recovery only (the documentation uses it when removing a node after quorum is lost). Find out why the nodes cannot see each other first.
- Joining a node overwrites `/etc/pve` on the joining node, and a joining node must not hold guests. Back up `/etc/pve` before any cluster change.

## HA Manager and fencing

Proxmox HA fences by **watchdog self-fencing**: a node that loses quorum stops renewing its watchdog and reboots after the timeout (about 60 seconds in the documentation), after which the HA Manager recovers its services elsewhere. It does not use IPMI or iDRAC power-off as its fencing mechanism, so do not design around "fence devices" or test by switching a node off through the BMC and calling that a fencing test.

- A **hardware watchdog** is preferred and must be enabled: set `WATCHDOG_MODULE` in `/etc/default/pve-ha-manager`. The fallback is `softdog`, which is less reliable because it depends on the same hardware and kernel it is guarding.
- HA expects shared storage for guests (Ceph, NFS, iSCSI and similar), at least three nodes, and redundant networking. Local ZFS with storage replication can also back HA guests, but a failover then loses writes made since the last replication sync, so state that trade-off before using it.
- Test fencing in a maintenance window by isolating a node from the cluster network, then watch `ha-manager status` and the `pve-ha-crm` and `pve-ha-lrm` journals.
- Put a node into maintenance with `ha-manager crm-command node-maintenance enable <node>`; services migrate away and return when you disable it.
- A resource in `error` is left alone by the HA stack. The documented way out is to make the resource safe, fix the cause, set `--state disabled`, and only then request a start. Never clear an error state by repeatedly restarting.
- Placement preferences: HA groups are deprecated and were migrated to HA node-affinity rules in 9.0 (stored in `/etc/pve/ha/rules.cfg`). On 8.x, groups still apply.

## Storage

| Storage | Snapshots | Thin | Shared | Note |
|---|---|---|---|---|
| ZFS (local) | yes | yes | no | Best default for a single node; uses RAM for ARC |
| LVM-thin | yes | yes | no | Light on RAM; pool can fill silently |
| LVM (thick) | yes (volume chains, technology preview) | no | only on iSCSI/FC/SAS | Check the release notes for current status |
| Directory | qcow2 only | qcow2 | no | Simple, slowest |
| Ceph RBD | yes | yes | yes | For HA clusters |
| NFS / CIFS | qcow2 only | qcow2 | yes | Good for ISOs and backups |

### Thin-pool exhaustion (the failure that takes guests down)

"If a storage runs full, all guests using volumes on that storage receive IO errors" (Proxmox storage documentation). On LVM-thin the used space is invisible from inside the guest, so a guest can report plenty of free space while the host pool is at 100 per cent and the VM sits in `running (io-error)` with an idle CPU.

Checks, host side:

```bash
lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent pve   # thin pool data and metadata use
vgs -o vg_name,vg_size,vg_free                                    # headroom to extend
grep -H discard /etc/pve/qemu-server/*.conf                        # which disks have discard set
```

Rules:

1. Alert on both `data_percent` and `metadata_percent`. Warn at 80, treat 90 as urgent. A full metadata area is as bad as a full data area.
2. Set `discard=on` on every thin-backed virtual disk and keep a working guest-side trim schedule (`fstrim.timer` enabled in the guest). A timer running with no `discard` on the disk reclaims nothing, so verify the disk option itself and not only the timer.
3. Before proposing "just extend the pool", check `vgs` for real free space. On a single-disk host the volume group may have none left.
4. Applying discard to a running guest needs a power cycle of that guest; do not mass-reboot guests as a reflex. Survey per guest, then change in a maintenance window.
5. After a recovery, run `fstrim -av` inside the guest and re-read `lvs` to prove the pool dropped.

### ZFS

- The installer limits the ARC to 10 per cent of RAM, clamped to 16 GiB, on Proxmox VE 8.1 and later. Older installs use the OpenZFS default (50 per cent, or 62.5 per cent on OpenZFS 2.3.0 and later). Rule of thumb from the documentation: at least 2 GiB plus 1 GiB per TiB of storage.
- To change it persistently, set `options zfs zfs_arc_max=<bytes>` in `/etc/modprobe.d/zfs.conf`, run `update-initramfs -u -k all` for root on ZFS, and reboot. A value written to `/sys/module/zfs/parameters/zfs_arc_max` lasts until reboot.
- Read ARC use from `/proc/spl/kstat/zfs/arcstats` (the `size` and `c_max` fields).
- Avoid swap on a zvol; the documentation warns it can block the server under load. Prefer enough RAM and a swap partition on a physical disk, and consider `vm.swappiness=10`.
- Mirrors give the best IOPS and resilience for small pools; prefer RAID-Z2 over RAID-Z1 for large-capacity pools. Leave deduplication off unless you have measured the need.

### Ceph

Three or more nodes, separate public and cluster networks, NVMe for WAL/DB when capacity is on HDD, `size=3` with `min_size=2`. Never share the Ceph cluster network with Corosync. Health: `ceph status`, `ceph health detail`, `ceph osd df`.

## Backup (vzdump and Proxmox Backup Server)

| Mode | VM behaviour | Container behaviour |
|---|---|---|
| `snapshot` | Live backup while the VM runs; with the guest agent running it freezes and thaws the filesystem. Works on any storage. | Needs a snapshot-capable storage for every backed-up volume. |
| `suspend` | Kept for compatibility; suspends then uses snapshot mode. Not recommended. | Rsync copy, brief suspend. Needs temporary space. |
| `stop` | Highest consistency, short downtime. | Stops the container for the whole backup. |

```bash
vzdump 100 --storage backup-store --mode snapshot --compress zstd   # --compress applies to file targets; PBS compresses on its own
```

Retention is set with `prune-backups` (`keep-last`, `keep-daily`, `keep-weekly`, `keep-monthly`, `keep-yearly`). Run Proxmox Backup Server on its own host, not on the PVE node it protects. PBS deduplicates at chunk level itself, so ZFS dedup on its datastore is not needed. Schedule PBS verify jobs, and **test a restore monthly**; an untested backup is a claim, not evidence.

## Networking

- Default model: Linux bridges (`vmbr0`) over physical NICs, configured in `/etc/network/interfaces`. Make a bridge VLAN-aware (`bridge-vlan-aware yes`) and set the tag on the guest NIC rather than building a bridge per VLAN.
- Bonds: `active-backup` for management, `802.3ad` (LACP, needs switch configuration) for storage and VM traffic.
- Jumbo frames (MTU 9000) on Ceph, NFS and migration networks only, set on switch ports, bonds, bridges and host interfaces end to end. Verify with `ping -M do -s 8972 <peer>`.
- SDN zones (Simple, VLAN, QinQ, VXLAN, EVPN) are cluster-wide. Apply pending SDN changes with the Apply button in the UI; the same action is available as `pvesh set /cluster/sdn` (community-confirmed, not described in the SDN chapter, so check `pvesh usage /cluster/sdn` first). For overlay design, hand off to `evpn-vxlan-fabric`.
- The built-in firewall has datacenter, node and guest levels, rules under `/etc/pve/firewall/`. The nftables-based firewall is described in the roadmap as a technology preview at the time of writing; confirm which backend is active before debugging rules.

## Security

Named admin accounts rather than shared `root`, TOTP two-factor on the UI, API tokens with limited privileges for automation (never a password in a script), restricted access to port 8006, role-based least privilege, regular `apt update && apt full-upgrade` tested on one node first, and the enterprise repository where a subscription exists. Keep secrets out of scripts and notes; see `secrets-hygiene`.

## Common pitfalls

1. Enabling HA before shared storage, three nodes and a tested watchdog exist.
2. Treating `pvecm expected 1` as a fix instead of a recovery tool.
3. Thin pool or Ceph at 80 per cent with no alert, and no `discard=on`.
4. `qm disk move` without `--delete 1`, leaving unused copies that eat the pool; or with `--delete 1` before verifying the guest boots from the new disk.
5. Memory overcommit on VMs without ballooning and monitoring. Containers tolerate overcommit better.
6. No guest agent, so snapshot backups cannot freeze the filesystem.
7. Privileged containers and `nesting=1` left on without a reason.
8. Editing `/etc/pve` files by hand during a cluster change without a backup.
9. Mixing Intel and AMD hosts in one live-migration domain, or choosing CPU type `host` on a heterogeneous cluster.
10. Counting a snapshot or an unrestored backup as protection.

## Red flags

- A guest reports free space while the host pool is full, and nobody has run `lvs` on the host.
- Someone proposes an IPMI power-off as the HA fencing design.
- A command from the destructive column is about to run on a production node without a stated rollback.
- A "restore tested" claim with no date or restore log.
- A script or note containing a password, token or `GOVC_PASSWORD`-style literal.

## References and scripts

- `references/architecture.md`: internals of QEMU/KVM, LXC, storage backends, networking, clustering and backup. Read for "how does X work".
- `references/best-practices.md`: storage selection, Ceph design, network separation, HA, resource management, hardening, backup practice.
- `references/diagnostics.md`: CLI diagnostics, cluster health, Ceph, logs, performance triage.
- `scripts/pve-health.sh`: read-only node, cluster, HA, storage (including thin-pool use), ZFS, Ceph and service health with warnings. Run on a PVE node as root.
- `scripts/pve-inventory.sh`: read-only inventory of nodes, guests, storage, networking, backup jobs and HA resources.

Both scripts only read state. They pass `shellcheck`, and the thin-pool thresholds were exercised against stubbed command output, but neither has been run against a live node; run them on a non-critical node first.

## Boundaries

- Choosing a hypervisor, comparing platforms, planning a migration between them: `virtualization-platform-selection`.
- Generic Linux host work on the Proxmox host (systemd, journald, apt discipline, LVM basics, backup tooling): `linux-host-ops`.
- Application containers, Kubernetes: `container-runtime-selection`, `docker-ops`, `podman-ops`, `containerd-ops`, `kubernetes-ops`.
- EVPN-VXLAN overlay design: `evpn-vxlan-fabric`.
- Provisioning guests as code: `terraform-iac-ops`, `ansible-automation-platform`.
- Credential handling for API tokens: `secrets-hygiene`.

## Bottom line

Look before you touch: version, cluster state, pool headroom. Proxmox HA is watchdog fencing on three or more nodes with shared storage, not BMC power control. The thin pool that nobody alerts on is the outage waiting to happen, so set `discard=on`, trim in the guest, and watch `lvs` on the host. Keep snapshots out of the backup story, and prove restores.
