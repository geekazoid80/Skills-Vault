# VMware vSphere architecture reference

How the platform works. Operating rules and the command safety table are in `SKILL.md`. Syntax here has not been run on live systems; check Broadcom documentation for the installed release, because limits, defaults and names change between versions.

---

## ESXi

The VMkernel is the hypervisor operating system: CPU scheduling (NUMA-aware, proportional fair share), memory management, device drivers, the Pluggable Storage Architecture and Network I/O Control. ESXi runs on the hardware with no host OS underneath.

**CPU scheduler:** ready time (%RDY) is time a vCPU waited for a physical core, the main contention signal. Co-stop (%CSTP) is time an SMP VM waited to synchronise its vCPUs; over-allocated vCPUs amplify it.

**Memory:** transparent page sharing (TPS, between VMs disabled by default since vSphere 6.0 for security), ballooning (the `vmmemctl` driver in VMware Tools reclaims guest memory), compression, host swap (`.vswp`, slow, a sign of severe pressure), and large pages (2 MB by default, shattered under pressure).

**Pluggable Storage Architecture:** the Native Multipathing Plugin (NMP) with a Storage Array Type Plugin (SATP, array behaviour) and Path Selection Plugin (PSP: Fixed, MRU, Round Robin). Third-party multipathing plugins can replace NMP.

**Network I/O Control:** bandwidth reservations and shares per traffic class on a distributed switch.

### Management processes

| Process | Role | Restart (disruptive; avoid on a busy host) |
|---|---|---|
| `hostd` | Local VM management and the API endpoint | `/etc/init.d/hostd restart` |
| `vpxa` | vCenter agent relaying commands to hostd | `/etc/init.d/vpxa restart` |
| `fdm` | HA Fault Domain Manager | managed by HA |
| `sfcbd` | CIM broker for hardware health | `/etc/init.d/sfcbd-watchdog restart` |
| `vobd` | Observability daemon | automatic |

Restarting all agents (`/sbin/services.sh restart`) briefly disconnects the host from vCenter. Prefer restarting only the agent that is faulty.

### Access

DCUI (local console), ESXi Shell and SSH (off by default), vSphere Client, APIs. Lockdown mode forces management through vCenter: **normal** keeps the DCUI for permitted users, **strict** disables it. Exception users keep direct access for break-glass.

---

## Virtual machines

Files: `.vmx` (configuration), `.vmdk` descriptor plus `-flat.vmdk` data, `.vmsd` and `.vmsn` for snapshots, `.nvram`, logs, `.vswp`.

Provisioning types: thin, thick lazy zeroed, thick eager zeroed. Snapshot deltas are `-00000N.vmdk` or `-sesparse` files; every write after a snapshot goes to the delta, reads may traverse the chain, and consolidation merges deltas back.

VM hardware versions are backward-compatible only in the sense that newer hosts run older versions; a VM at a newer version may not run on older hosts. Upgrade VMware Tools first, then hardware version, with a power cycle (not a guest reboot). Consult the VMware hardware-version compatibility documentation for which version each release supports.

VMware Tools and `open-vm-tools` provide PVSCSI and VMXNET3 drivers, guest heartbeat for VM Monitoring, quiescing (VSS on Windows, filesystem freeze on Linux), time sync and guest customisation.

---

## vMotion and EVC

**Process:** pre-checks, iterative memory pre-copy (dirty pages copied each round), a brief switchover where the VM is stunned and the last pages move, then activation on the destination and source cleanup. Needs a vMotion-enabled VMkernel port on each host, ideally 10 GbE or faster.

**EVC** masks CPU features at the cluster level to a baseline named for a CPU generation, per vendor. Hosts can be newer than the baseline; they cannot be older. Choose the baseline from the oldest host, and check the documentation before lowering a baseline on a cluster with running VMs.

**Cross-vCenter vMotion** moves VMs between vCenter instances; it needs connectivity between them and matching networks, and licensing requirements depend on the edition and release. **Storage vMotion** moves disks while running.

---

## High availability

### vSphere HA

Hosts form an HA cluster with one primary elected by the Fault Domain Manager; the others are secondaries. The primary watches secondaries by network heartbeats (every second) and, before declaring a host failed, checks heartbeat datastores to tell failure from isolation or partition. Isolation checks use the configured isolation addresses (default: the management gateway). The isolation response (leave powered on, shut down, power off) applies when a host is alive but loses the management network. Failure-detection and isolation timings depend on version and advanced options; read the documentation for your release.

- **Admission control:** cluster resource percentage, slot policy, or dedicated failover hosts. Choose the failures to tolerate and size the reservation for them.
- **Restart priority and dependencies:** order restarts; infrastructure first.
- **VM Monitoring and VMCP:** guest-level and storage-fault responses.
- **Proactive HA:** moves VMs off hosts whose hardware is degrading, with vendor support.

### Fault Tolerance

FT keeps a secondary VM on another host in sync for zero-downtime protection (SMP-FT uses fast checkpointing; the older vLockstep model was removed in vSphere 6.5). It needs a dedicated FT logging VMkernel port and has disk, vCPU-count, feature and licence requirements that vary by version; check them before promising FT. Snapshots, linked clones and Storage vMotion have restrictions on FT VMs.

### DRS

DRS watches CPU and memory demand and uses vMotion to rebalance, and since vSphere 7 scores VM happiness rather than only host balance. Modes: fully automated, partially automated, manual. Migration threshold is a 1 (conservative) to 5 (aggressive) setting. Rules: VM-VM affinity and anti-affinity, VM-Host (must or should, affinity or anti-affinity). Predictive DRS uses forecasts from an operations product.

---

## Networking

**Standard switch:** per host, uplinks to vmnics, port groups for segments. Teaming: originating port ID (default), source MAC hash, IP hash (needs EtherChannel or LACP on the physical switch), explicit failover order.

**Distributed switch:** configuration pushed to all member hosts from vCenter; adds Network I/O Control, LACP, port mirroring (including ERSPAN), network health check, per-port policies, and rollback and recovery to avoid management lockout.

**VMkernel ports and traffic:** management, vMotion, vSAN, FT logging, NFS and iSCSI, replication. Separate VLANs; jumbo frames only where proven end to end.

**VLAN modes:** VST (port group VLAN ID), EST (VLAN 0, physical switch tags), VGT (VLAN 4095, guest tags).

**NSX:** GENEVE overlay, distributed firewall and micro-segmentation, integrated with the distributed switch.

---

## Storage

**VMFS 6:** cluster filesystem, ATS locking, automatic space reclamation for thin-provisioned arrays.

**NFS:** v3 and v4.1 (v4.1 adds session trunking and Kerberos). Dedicated NICs and VLAN; jumbo frames where tested.

**iSCSI:** software initiator in the VMkernel, port binding for multipathing, CHAP.

**Fibre Channel:** HBAs and fabric; the lowest latency.

**SPBM:** storage policies describe requirements (tier, protection, encryption, replication) and are applied per disk with vSAN, vVols and compatible arrays; compliance is checked against the policy.

**Storage DRS:** balances space and I/O latency across a datastore cluster using Storage vMotion. Defaults are 80 per cent space and 15 ms latency thresholds.

**vVols:** per-VM objects on the array through a VASA provider. Check current support status for your release before designing around them.

---

## vSAN

Pools local storage across hosts into a shared datastore. At least three hosts for a standard cluster; a dedicated VMkernel port on a fast network.

**OSA:** disk groups with one cache device and capacity devices; a cache device failure fails the disk group.

**ESA (vSAN 8 onwards):** a single flat pool of NVMe devices with no cache tier, built-in compression, a separate hardware compatibility list, and improved snapshots. It is chosen per cluster. Global deduplication for ESA arrived later with prerequisites; do not describe deduplication as always on in ESA without checking the release.

**Storage policies:** failures to tolerate, RAID method (mirror or erasure coding), stripe width, object space reservation, force provisioning (avoid).

**Stretched clusters:** two data sites plus a witness. Inter-site round-trip latency and witness latency limits are documented per release (commonly cited as 5 ms between data sites and under 200 ms to the witness for up to 10 hosts per site, under 100 ms for 11 or more; confirm for your version).

**Health:** Cluster, Monitor, vSAN, Health in the vSphere Client covers network, data, physical disk, cluster and performance checks.

---

## Backup and data protection (VADP)

Backup applications use the vStorage APIs for Data Protection for agentless image-level backup:

1. The backup tool takes a VM snapshot (quiesced if Tools are present).
2. It reads the base disk, using changed block tracking (CBT, `ctkEnabled`) for incrementals.
3. It deletes the snapshot; the VMkernel consolidates the delta.

| Transport | Path | Note |
|---|---|---|
| Hot-add | Proxy VM mounts the disk | Common default |
| NBD, NBDSSL | Over the network | When hot-add is unavailable |
| SAN | Direct from the LUN | Fastest where the proxy sees the LUNs |

CBT is reset after some operations (for example some Storage vMotion and consolidation cases) and the tool then does a full pass. Orphaned snapshots after failed jobs raise a consolidation warning in vCenter; treat it as an action item.
