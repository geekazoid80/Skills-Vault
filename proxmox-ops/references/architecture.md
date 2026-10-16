# Proxmox VE architecture reference

How the platform is put together. Read this for "how does X work" questions; the operating rules are in `SKILL.md`. Syntax here has not been run on live systems; check version-specific items against the admin guide for the installed release.

---

## Platform

Proxmox VE is Debian Linux with a Proxmox-built kernel, QEMU/KVM for virtual machines, LXC for system containers, and a management layer exposed on HTTPS port 8006 and over a REST API. PVE 8.x is built on Debian 12 and the 9.x line on Debian 13. Check the Proxmox roadmap for the exact kernel, QEMU, LXC, ZFS and Ceph versions of the installed minor release rather than trusting a copied table.

**Hardware requirement:** Intel VT-x (`vmx` flag) with EPT, or AMD-V (`svm` flag) with NPT. Verify with `grep -E 'vmx|svm' /proc/cpuinfo`, and check the firmware has virtualisation (and IOMMU, for passthrough) enabled.

**KVM and QEMU:** KVM is the kernel module that makes Linux a hypervisor; QEMU supplies device emulation. Together they run each VM as a QEMU process.

**LXC system containers:** share the host kernel with isolated namespaces (PID, network, mount, user). They run a full init system and are not Docker or Podman application containers.

### Node components

```
Proxmox VE node
  Proxmox kernel (KVM, ZFS, drivers)
  QEMU/KVM            VM execution
  LXC                 container execution
  pvedaemon           API daemon
  pveproxy            web UI and API proxy, port 8006
  pvestatd            status collection
  Corosync            cluster messaging
  pmxcfs              cluster filesystem mounted at /etc/pve
  pve-ha-crm, pve-ha-lrm   HA Manager (cluster and local resource managers)
  pve-firewall        firewall service
  storage layer       ZFS, LVM, LVM-thin, Ceph, NFS, iSCSI, directory
```

---

## Virtual machines

Config files are at `/etc/pve/qemu-server/<vmid>.conf`. On a cluster `/etc/pve` is shared, so a config is visible from every node.

### Disk formats

| Format | Snapshots | Thin | Notes |
|---|---|---|---|
| qcow2 | yes | yes | Default on directory-type storage |
| raw | storage-dependent | storage-dependent | Used on LVM, LVM-thin, ZFS zvols and Ceph RBD |
| vmdk | n/a | n/a | Import and export from VMware only |

Snapshot capability comes mostly from the **storage type**, not the image format: ZFS, LVM-thin and Ceph RBD snapshot natively, directory and NFS only with qcow2.

### VirtIO devices

| Device | Function | Note |
|---|---|---|
| VirtIO SCSI (single) | Disk controller | Recommended for performance with IO Thread on each disk; supports discard |
| VirtIO Block | Disk controller | Simple; discard needs a guest kernel 5.0 or later; no SSD-emulation flag |
| VirtIO network | NIC | Highest throughput, lowest CPU |
| Balloon | Memory reclaim | Reports guest memory use even with fixed memory |
| VirtIO RNG | Entropy | Fed from the host |
| QEMU Guest Agent | Shutdown, IP reporting, filesystem freeze | Needs the agent package inside the guest and `agent: 1` |

Windows guests need the virtio-win driver ISO during installation or injected beforehand.

### Firmware, Cloud-Init, templates

- **OVMF (UEFI):** set the BIOS to OVMF and add an EFI disk. Needed for Secure Boot and some modern Windows installs.
- **Cloud-Init:** Proxmox attaches a generated drive carrying user, network and SSH-key data for unattended provisioning.
- **Templates and clones:** `qm template <vmid>` freezes a VM as a template. A **full clone** is independent. A **linked clone** references the template's disk and needs snapshot-capable storage; it is fast and small but cannot outlive the template.

---

## Containers

**Unprivileged (default and recommended):** container UID 0 maps to a high host UID, so container root has no host privileges. **Privileged:** container root equals host root for device access; use only when a workload needs it.

Templates come from `pveam` (`pveam update`, `pveam available --section system`, `pveam download <storage> <file>`). Per-container features include `nesting=1` (Docker or Podman inside LXC), `keyctl=1` and `fuse=1` (the container documentation advises strongly against FUSE mounts inside containers because they can break freezing for suspend and snapshot backups). Host directories can be bound in with `pct set <ctid> -mp0 /host/path,mp=/container/path`.

---

## Storage

| Type | Level | Shared | Snapshots | Note |
|---|---|---|---|---|
| ZFS | file and block | no | yes | Copy-on-write, checksums, compression, send/receive |
| Directory | file | no | qcow2 only | |
| LVM | block | only on shared block back ends | yes (volume chains are a technology preview) | |
| LVM-thin | block | no | yes | Allocates blocks on write; can be over-provisioned |
| Ceph RBD | block | yes | yes | Distributed, self-healing, installable from the UI |
| CephFS | file | yes | yes | Templates, ISOs, backups; use RBD for VM disks |
| NFS, CIFS | file | yes | qcow2 only | |
| iSCSI | block | yes | yes (snapshot as volume chain, technology preview) | |
| Proxmox Backup Server | both | yes | n/a | Backup target |

The storage documentation states that a full storage makes every guest on it receive I/O errors. Over-provisioned thin storage therefore needs monitoring; see `SKILL.md`.

### Selection guide

| Scenario | Choice |
|---|---|
| Single node, general use | ZFS mirror, or RAID-Z2 for capacity |
| Single node, RAM-constrained or spinning disks | LVM-thin |
| HA cluster | Ceph RBD for guests, CephFS for files |
| Backup target | Proxmox Backup Server on its own host |
| ISOs and templates | Directory, CephFS or NFS |

---

## Networking

- **Linux bridges** (`vmbr0`, `vmbr1`) over physical NICs, defined in `/etc/network/interfaces`. A **VLAN-aware** bridge lets guests set an 802.1Q tag on their NIC.
- **Open vSwitch** is optional (`openvswitch-switch`) for flow tables and tunnels.
- **Bonding:** `active-backup` (failover only), `802.3ad` LACP (needs switch support), `balance-alb` (no switch support needed).
- **SDN:** cluster-wide zones (Simple, VLAN, QinQ, VXLAN, EVPN) and VNets, applied from the Datacenter SDN panel or `pvesh set /cluster/sdn` (community-confirmed).
- **Firewall:** datacenter, node and guest levels, rules in `/etc/pve/firewall/`, security groups to reuse rule sets. Two backends exist (iptables-based and nftables-based); the nftables one has been described in the roadmap as a technology preview, so confirm which is active.

---

## Clustering

**Corosync** carries cluster messaging, ideally on a dedicated network. The admin guide asks for latency under 5 ms between nodes, and supports multiple links for redundancy.

**pmxcfs** is the cluster filesystem at `/etc/pve`, a database replicated by Corosync. Config changes on any node are visible on all.

**Quorum:** each node has one vote and the cluster needs a majority.

| Nodes | Quorum | Node failures tolerated |
|---|---|---|
| 2 | 2 | 0, unless a QDevice adds a vote |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |

Without quorum the cluster filesystem is read-only and guest changes are refused.

### HA Manager

The CRM (cluster resource manager) decides placement; each node's LRM (local resource manager) acts on it. Service states include `started`, `stopped`, `disabled`, `error`, `migrate`, `relocate`, `fence` and `recovery`.

**Fencing is watchdog-based.** A node that loses quorum stops renewing its watchdog and resets after the timeout (about 60 seconds). Only then does the manager place the node's services elsewhere. A hardware watchdog is preferred (enable it with `WATCHDOG_MODULE` in `/etc/default/pve-ha-manager`); the kernel `softdog` is the fallback. A service that cannot be recovered after the allowed attempts goes to `error` and is left alone until it is set `disabled` and then restarted deliberately.

---

## Backup

`vzdump` writes `.vma` archives for VMs and tar archives for containers, compressed with zstd, gzip or lzo. Modes:

| Mode | VM | Container |
|---|---|---|
| snapshot | Live backup; filesystem freeze via guest agent if running; works on any storage | Temporary storage snapshot; needs snapshot-capable storage |
| suspend | Compatibility mode, then snapshot behaviour | Rsync copy with a brief suspend |
| stop | Shuts down, backs up, restarts | Stops for the duration |

**Proxmox Backup Server (PBS)** is a separate product: chunk-level deduplication and incremental transfer, client-side encryption (AES-256-GCM), verification jobs, and prune policies. Backups are scheduled under Datacenter, Backup, with a storage target, schedule, retention and notification.
