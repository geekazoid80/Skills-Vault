# Proxmox VE best practices reference

Storage selection, Ceph design, network separation, HA, resource management, hardening and backup practice. Operating rules and the command safety table are in `SKILL.md`. Syntax here has not been run on live systems.

---

## Storage selection

### ZFS or LVM-thin

**Choose ZFS when** the node is single, or multi-node without Ceph; checksums to detect silent corruption matter; you want instant snapshots, compression and send/receive replication; and RAM can be spared for the ARC.

**Choose LVM-thin when** RAM is tight, the disks are spinning, and simple thin provisioning is enough. It has no checksumming, and the pool can fill without any visible warning inside the guests.

**ZFS notes**

- Size the ARC deliberately. On Proxmox VE 8.1 and later the installer sets it to 10 per cent of RAM, clamped to 16 GiB. The documented rule of thumb is at least 2 GiB plus 1 GiB per TiB of storage. Set it with `options zfs zfs_arc_max=<bytes>` in `/etc/modprobe.d/zfs.conf`, then `update-initramfs -u -k all` and a reboot for root on ZFS.
- Mirrors for small pools (best IOPS and resilience); RAID-Z2 for large capacity pools. Prefer RAID-Z2 over RAID-Z1 on large disks, where a second failure during rebuild is the risk.
- Compression (`lz4`, or `zstd` for a higher ratio) is close to free. Leave deduplication off unless a measured saving justifies the memory cost.
- Do not put swap on a zvol.

### Thin provisioning discipline

LVM-thin, qcow2 and Ceph all allocate on write, so real use grows silently.

- Alert at 80 per cent on both data and metadata use (`lvs -o lv_name,data_percent,metadata_percent`, `ceph df`).
- Set `discard=on` on thin-backed virtual disks and enable `fstrim.timer` in the guest. A timer alone reclaims nothing if the disk option is missing.
- Keep volume group headroom, and know the actual free space (`vgs`) before promising that a pool can be extended.

### Ceph

- Use for multi-node clusters needing shared guest disks and live migration.
- Minimum three nodes; the Proxmox Ceph documentation recommends at least 12 OSDs spread evenly across them. Use `size=3`, `min_size=2`.
- Separate the public (client) and cluster (replication) networks onto dedicated links or VLANs, 10 GbE or faster. Never share the Ceph cluster network with Corosync or management.
- NVMe for WAL/DB when capacity drives are HDD; NVMe-only OSDs for latency-sensitive random I/O.
- Keep OSD sizes uniform within a pool. Monitor with `ceph status`, `ceph osd df`, `ceph health detail`.

---

## Network design

| Network | Purpose | Notes |
|---|---|---|
| Management | UI, SSH | Bond for redundancy |
| Corosync | Cluster messaging | Latency matters more than bandwidth; dedicated link, add a second |
| Ceph public | Client to OSD | 10 to 25 GbE, dedicated VLAN |
| Ceph cluster | OSD replication | Dedicated, never shared with Corosync |
| Guest | VM and container traffic | VLAN-tagged, preferably as SDN VNets on the bridge (see SKILL.md) |
| Migration | Live migration | High bandwidth, dedicated if possible |

**Bonding:** `active-backup` for management; `802.3ad` LACP for storage and guest traffic where the switches are configured for it.

**Jumbo frames:** MTU 9000 on Ceph, NFS and migration paths, and on any same-VLAN east-west path where every switch on it is verified jumbo, set consistently on switch ports, bonds, bridges and host interfaces. Verify with `ping -M do -s 8972 <peer>`. Leave management at 1500 where the path is routed or unread, to keep troubleshooting simple. The SDN, QinQ and per-guest MTU detail is in SKILL.md, "Host ports, SDN and MTU".

---

## HA and fencing

- Proxmox HA fences by **watchdog**: the node resets itself if it loses quorum and cannot renew the watchdog. Plan for a hardware watchdog (enable it in `/etc/default/pve-ha-manager`) and treat `softdog` as the fallback.
- Requirements: at least three nodes, shared storage for guests, redundant networking.
- Test in a maintenance window by isolating a node from the cluster network, not by pulling power on production. Watch `ha-manager status` and the `pve-ha-crm` and `pve-ha-lrm` logs.
- Use `ha-manager crm-command node-maintenance enable <node>` for planned work.
- Do not design around BMC or IPMI power-off as the fencing mechanism; the HA stack does not use it.

---

## Resource management

- **CPU:** overcommit is normal. A vCPU to physical core ratio is workload-dependent (commonly several to one for mixed, mostly idle guests, much lower for latency-sensitive ones); measure CPU steal rather than trusting a fixed ratio. Use `cpuunits` for relative priority and `cpulimit` to cap a guest. Watch steal time inside guests.
- **CPU type:** use `host` only on a single node or identical hardware. For live migration choose the lowest CPU generation in an all-Intel or all-AMD cluster. Never rely on Intel to AMD migration.
- **Memory:** do not overcommit VM memory without ballooning and monitoring. Containers tolerate overcommit better. KSM (kernel same-page merging) saves RAM at some CPU cost; inspect `/sys/kernel/mm/ksm/pages_shared`.
- **NUMA:** size large guests to fit a single NUMA node where possible.

---

## Security hardening

- Replace shared `root` use with named administrators; enable TOTP two-factor for the web UI; consider LDAP or AD for central authentication.
- Use API tokens with limited privileges for automation; never put passwords in scripts. See `secrets-hygiene`.
- Restrict access to port 8006 with datacenter firewall rules. Use roles for least privilege, and review permissions on a schedule.
- Update regularly with `apt update && apt full-upgrade`, one node at a time in a cluster, on a non-critical node first. Use the enterprise repository where a subscription exists; the no-subscription repository suits non-critical systems.
- Containers: unprivileged only unless a workload requires otherwise; AppArmor profiles on; `nesting` only for Docker or Podman inside LXC; read-only bind mounts where possible.

---

## Backup practice

- Daily snapshot-mode backups of production guests; weekly verification of the retention chain; a restore test at least monthly for one VM and one container.
- Put Proxmox Backup Server on a separate host from the PVE nodes it protects. PBS deduplicates at chunk level on its own, so ZFS deduplication on its datastore is unnecessary; prefer fast local disks.
- Client-side encryption for offsite copies, with the key stored separately from the backups.
- Retention example: keep 7 daily, 4 weekly, 6 monthly (`prune-backups`). Schedule verification jobs to catch bit rot.
- Document recovery steps per workload tier and check that backup network bandwidth meets the recovery-time objective.
