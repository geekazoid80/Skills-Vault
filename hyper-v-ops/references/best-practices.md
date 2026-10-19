# Hyper-V best-practices reference

Rules of thumb below are planning guidance, not Microsoft limits; Microsoft figures are marked as such.

## Host design

- **Server Core** for hosts where practical: fewer binaries to patch and a smaller attack surface (Core is about 4 GB smaller on disk per Microsoft's hardware requirements). Manage remotely with PowerShell, RSAT and Windows Admin Center.
- **Dedicate the host to Hyper-V.** Other roles in the parent partition compete with VMs and widen the blast radius. The management OS should run the minimum.
- **Keep hosts identical** within a cluster: CPU generation (or use processor compatibility), NICs, drivers, firmware and Windows build.
- **Separate traffic** onto separate NICs, VLANs or SET virtual NICs: VM traffic, management, live migration, storage (SMB or iSCSI) and cluster heartbeat. Reserve bandwidth for each class.
- **Separate volumes** for the parent OS and for VM storage. Keep VM files off the system volume.
- **Time:** the host syncs to the domain hierarchy or a reliable source; leave the Time Synchronisation integration service on for non-domain-controller guests and review it for domain controllers per your Active Directory guidance.
- **Updates:** patch hosts in a rolling pattern (drain, patch, resume) and keep integration components current. On a cluster use Cluster-Aware Updating (`windows-failover-clustering-ops`).
- **Antivirus:** follow the antivirus vendor's Hyper-V exclusion list for VM configuration, virtual disk and checkpoint file types and the `vmwp.exe` process, and test that scanning does not touch them.
- **Backup:** use a Hyper-V-aware backup that uses the VSS writer; test restores of a VM, not only of files. Replica is not a backup.

## VM sizing and placement

- Start small and add; a VM with more virtual processors than it uses still costs scheduler time.
- Plan around **NUMA**: fit a VM inside one node; large VMs get an explicit virtual topology.
- **Memory:** Dynamic Memory for web, application and file workloads; static for databases and any workload with its own cache; weights higher for critical VMs; never allow total Maximum RAM to exceed what the host can supply with headroom for the parent partition.
- **vCPU ratio:** a common planning ceiling is about 4:1 for production and 8:1 for light loads. Validate with hypervisor run-time counters, not the ratio.
- **Generation 2** for new VMs; Generation 1 only for guests that need it.
- **Anti-affinity** (clusters): keep redundant pairs on different hosts (`windows-failover-clustering-ops`).

## Storage

- VHDX for all disks; fixed disks for latency-sensitive databases on spinning or mixed media, dynamic on all-flash.
- Align allocation units with the application guidance (64 KB is commonly advised for SQL Server data); check the vendor.
- Store VMs on Cluster Shared Volumes in clusters, or on SMB 3 file shares with RDMA where the design calls for it.
- Use Storage QoS minimums for important VMs and maximums for noisy ones.
- Watch free space: dynamic disks and checkpoints grow on demand, and a full volume pauses VMs ("Paused-Critical").

## Checkpoints

- Treat checkpoints as short-lived. Take one before a risky change, delete it after the change is proven, and never keep long chains on production VMs.
- Production checkpoints for production use; Standard checkpoints only for lab VMs.
- Do not use checkpoints on domain controllers, databases with external logs, or replicating systems unless the vendor documents it.
- Delete through `Remove-VMSnapshot`, wait for the merge, and never delete `.avhdx` files in the file system.
- Keep a report of checkpoints older than a week (`scripts/storage-and-checkpoints.ps1` does).

## Networking

- SET for virtual switches with more than one NIC; identical adapters and drivers; Hyper-V Port or Dynamic load balancing as advised for the speed. Do not build new LBFO teams under Hyper-V.
- Enable RDMA on dedicated storage or migration vNICs only after the physical network is configured for it (PFC, ETS and a matching traffic class); a half-configured RDMA network is worse than none.
- Enable VMQ and virtual RSS where the NIC supports them; check driver and firmware versions before blaming the switch.
- Use MAC address spoofing only where needed (nested virtualisation, virtual appliances).

## Live migration

- Dedicate a network of 10 Gbps or more where possible and name it with `Add-VMMigrationNetwork` (use `Set-VMMigrationNetwork` only to change an existing entry; its priority parameter is `-NewPriority`).
- `Set-VMHost -VirtualMachineMigrationPerformanceOption` accepts `TCPIP`, `Compression` and `SMB`. Prefer SMB with RDMA when at least 5 Gbps is available to migration traffic; use Compression on slower networks (Microsoft guidance).
- Limit simultaneous migrations to what the network sustains (`-MaximumVirtualMachineMigrations`, `-MaximumStorageMigrations`).
- Kerberos with constrained delegation on domain-joined hosts; CredSSP only where delegation cannot be set up (and it needs an interactive session).
- Processor compatibility mode (`Set-VMProcessor -CompatibilityForMigrationEnabled $true`, VM off) when hosts differ in CPU generation; it hides newer instruction sets from the guest.
- Run `Compare-VM -Name <vm> -DestinationHost <host>` before a planned move and have an explicit rollback.

## Hyper-V Replica

- Choose the interval from the recovery point objective and the link: 30 seconds for the tightest, 5 or 15 minutes otherwise. Microsoft's page notes bandwidth must be checked first.
- Enable additional recovery points only where needed; they cost storage and I/O. Use application-consistent points (`-VSSSnapshotFrequencyHour`) for VSS-aware applications.
- Use certificates when either host is outside the domain; encrypt over untrusted links.
- Monitor replication health and lag (`Measure-VMReplication`); alert when the last replication time is older than twice the interval.
- Rehearse test failover on a schedule; write the planned and unplanned failover steps down, including reverse replication afterwards.

## Monitoring targets

| Check | Frequency | Alert on (rule of thumb) |
|---|---|---|
| VM state | 1 minute | Anything other than the intended state (Off, Saved, Paused, Paused-Critical) |
| Heartbeat integration service | 1 minute | Lost Communication or No Contact on a running VM |
| Host processor | 5 minutes | Guest plus hypervisor run time above 90 per cent sustained |
| Memory pressure (Dynamic Memory VMs) | 5 minutes | Pressure above 100 sustained, above 150 serious |
| Volume free space for VM storage | 15 minutes | Below 20 per cent warning, below 10 per cent critical |
| Replication health and lag | 15 minutes | Not Normal, or lag above twice the interval |
| Checkpoint age | Daily | Older than 7 days |
| Event logs (VMMS, Worker, Hypervisor, Migration) | Continuous | New errors |

## Change discipline

State the blast radius, take a recent backup, schedule a window for anything that powers a VM off, upgrade configuration versions only after every host in the cluster is on the new release, and write the rollback before the change.
