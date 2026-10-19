---
name: hyper-v-ops
description: "Use for day-to-day Hyper-V administration and troubleshooting on Windows Server 2016, 2019, 2022 and 2025: VM generations and configuration versions, Dynamic Memory and NUMA, virtual switches and Switch Embedded Teaming, VHDX and checkpoints, live migration, Hyper-V Replica, integration services, nested virtualisation, GPU partitioning and Discrete Device Assignment. Triggers include \"Hyper-V\", \"vmms\", \"vmwp\", \"Get-VM\", \"VHDX\", \"avhdx\", \"checkpoint merge\", \"Update-VMVersion\", \"VM configuration version\", \"live migration failed\", \"Hyper-V Replica\", \"Set-VMProcessor ExposeVirtualizationExtensions\", \"nested virtualization\", \"SET team\", \"New-VMSwitch\", \"GPU-P\", \"DDA\", \"generation 1 or 2\". NOT for choosing a hypervisor (virtualization-platform-selection), NOT for cluster quorum, CSV or Cluster-Aware Updating (windows-failover-clustering-ops), NOT for the Windows Server base (windows-server-ops), NOT for WSL (wsl-ops), NOT for vSphere, Proxmox or KVM (vmware-vsphere-ops, proxmox-ops, kvm-libvirt-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Hyper-V operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: hyper-v-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Hyper-V is a type 1 hypervisor: the Windows installation becomes the parent partition and every VM is a child partition that reaches hardware through synthetic devices over VMBus. Behaviour, limits and defaults move by host release (2016, 2019, 2022, 2025), by VM generation and by VM configuration version, so pin all three before advising.

**Core principle:** read first, change second, and state the blast radius (VM downtime, host reboot, a one-way upgrade) before any change. Several Hyper-V changes cannot be undone (`Update-VMVersion`, deleting a checkpoint file by hand), so confirm those explicitly.

> **Caveat on provenance.** Commands, limits and scripts were reshaped from a community upstream, corrected against Microsoft Learn pages fetched on 2026-10-19, and reviewed independently. Syntax has not been run against a live Hyper-V host. Thresholds are rules of thumb, not Microsoft limits.

## Step 0: establish what you are on

```powershell
Get-VMHost | Select-Object ComputerName, LogicalProcessorCount, MemoryCapacity, NumaSpanningEnabled
Get-VMHostSupportedVersion -Default          # default VM configuration version on this host
Get-VM | Select-Object Name, State, Generation, Version, DynamicMemoryEnabled
```

Host builds: 14393 is 2016, 17763 is 2019, 20348 is 2022, 26100 is 2025. The scripts in `scripts/` gather most of this for you. Read `references/diagnostics.md` for event logs and counters and `references/architecture.md` for how the pieces fit.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive, disruptive or one-way, get explicit approval |
|---|---|---|
| `Get-VM`, `Get-VMHost`, `Get-VMHostSupportedVersion`, `Get-VHD`, `Get-VMSnapshot`, `Get-VMSwitch`, `Get-VMSwitchTeam`, `Get-VMNetworkAdapter`, `Get-VMReplication`, `Measure-VMReplication`, `Get-VMIntegrationService`, `Get-WinEvent`, `Get-Counter`, `Compare-VM` (compatibility report against a destination host; read only but contacts it) | `Set-VM`, `Set-VMMemory`, `Set-VMProcessor`, `Set-VMHost`, `New-VMSwitch`, `Set-VMNetworkAdapter`, `Checkpoint-VM`, `Enable-VMReplication`, `Add-VMMigrationNetwork`, `Move-VM` (live), `Set-VMHardDiskDrive` (QoS) | `Update-VMVersion`, `Remove-VMSnapshot` and `Remove-VM`, `Remove-VMSavedState`, `Merge-VHD`, `Resize-VHD`, `Move-VMStorage`, `Stop-VM -TurnOff`, `Restore-VMSnapshot`, `Start-VMFailover` and `Complete-VMFailover`, `Remove-VMReplication`, `Dismount-VMHostAssignableDevice`, `Remove-VMSwitch`, `Convert-VHD`, `Optimize-VHD`, deleting `.avhdx` files directly, `Set-VMProcessor -ExposeVirtualizationExtensions` on a running VM (it needs the VM off) |

## VM generation and configuration version

| Aspect | Generation 1 | Generation 2 |
|---|---|---|
| Firmware | BIOS (emulated) | UEFI |
| Boot controller | IDE | SCSI over VMBus |
| Secure Boot and vTPM | No | Yes (Secure Boot on by default) |
| Largest boot disk | 2 TB for VHDX, 2,040 GB for VHD | 64 TB |
| Choose when | Legacy or 32-bit guests, or an OS that cannot use UEFI | Anything new and supported |

The generation cannot be changed after creation. Choose Generation 2 for new VMs; on a Linux guest with Secure Boot pick the UEFI CA template or turn Secure Boot off.

The **configuration version** is separate: it records which Hyper-V features the VM can use. Highest version each host supports (Microsoft Learn, 2026-10-19): 2016 is 8.0, 2019 is 9.0, 2022 is 10.0, 2025 is 12.0. `Update-VMVersion` is one-way: after it, the VM cannot start on an older host. Upgrade only after every host in the cluster is on the new release and the cluster functional level is raised, and never as a routine step. `Get-VMHostSupportedVersion` lists what a host accepts.

## Memory, CPU and NUMA

- **Dynamic Memory** (Startup, Minimum, Maximum, buffer, weight) suits variable workloads. Use static memory for databases and for anything that manages its own cache; check the application vendor's guidance.
- **Never let total Maximum RAM exceed host RAM less the parent partition's needs.** If a VM needs more than its Startup RAM to boot and the host cannot supply it, Smart Paging uses a host file, which is slow and only a bridge.
- **vCPU ratio:** roughly 4:1 virtual processors per physical core is a common planning ceiling for production and up to 8:1 for light or test loads. These are rules of thumb; measure `Hyper-V Hypervisor Logical Processor` run time instead of trusting a ratio.
- **NUMA:** a VM that fits in one NUMA node is scheduled there. Size VMs to fit a node where possible; NUMA spanning exists for VMs that must exceed a node and costs remote-memory latency. `Get-VMHostNumaNode` shows the host topology; `Get-VMHostNumaNodeStatus` shows VM placement per node but returns an error while NUMA spanning is enabled (the default).
- **Limits per VM** (Microsoft Learn, 2026-10-19): 2025 allows 2,048 virtual processors and 240 TB of memory on Generation 2 (the processor figure needs PowerShell to configure); 2022 allows 1,024 and 240 TB; 2019 and 2016 allow 240 and 12 TB. Generation 1 is limited to 64 virtual processors and 1 TB. Checkpoints: 50 per VM.

## Virtual networking

- **Switch types:** external (bound to a physical NIC), internal (host and VMs only), private (VMs only).
- **Switch Embedded Teaming (SET)** is the supported team for Hyper-V switches. It supports up to eight adapters, switch-independent mode only, and Dynamic or Hyper-V Port load balancing (Hyper-V Port is advised for adapters at 10 Gbps and above). It carries RDMA, and Dynamic VMMQ requires it (Microsoft Learn, Azure Local host network requirements). LBFO teams are not supported with Hyper-V on Windows Server 2022 and later, so remove an LBFO team before an in-place upgrade and rebuild it as SET.
- **VLANs:** set access or trunk mode on the vNIC (`Set-VMNetworkAdapterVlan`) and match the physical port.
- **SR-IOV** bypasses the software switch; the virtual function is released during live migration and the VM falls back to the synthetic path.
- **Dedicate** a NIC or team to live migration where possible; do not let it share the management network by accident.

## Storage and checkpoints

- **VHDX** for all new disks (64 TB, journalled, online resize, UNMAP). VHD tops out at 2,040 GB. Fixed disks suit latency-sensitive databases on spinning media; dynamic disks are fine on all-flash storage.
- **Shared disks for guest clusters:** use VHD Sets (`.vhds`) rather than shared VHDX.
- **Checkpoints** (Microsoft Learn): Production checkpoints (default) use VSS in Windows guests or a file-system freeze in Linux guests and take no memory state; Standard checkpoints capture memory and can cause consistency problems with replicating systems such as Active Directory. `ProductionOnly` refuses to fall back to Standard. Each checkpoint creates an `.avhdx` differencing disk; delete checkpoints through Hyper-V (never delete the files) and let the merge finish. Keep checkpoints short-lived: long chains add read latency and a large merge when deleted.
- **Antivirus:** exclude the VM files and the `vmwp.exe` worker per the antivirus vendor's Hyper-V guidance, and test that the exclusions work.
- **Storage QoS** (`-MinimumIOPS`, `-MaximumIOPS`) caps noisy neighbours per virtual disk.

## Live migration and Hyper-V Replica

- **Live migration** works with shared storage, shared nothing (storage moves too) or storage migration alone. It also works without failover clustering (shared nothing). Choose Kerberos authentication with constrained delegation on domain-joined hosts, name a dedicated migration network with `Add-VMMigrationNetwork`, and pick the transport: SMB with RDMA when at least 5 Gbps is available for migration, compression otherwise. VMs migrating between different processor generations need processor compatibility mode (`Set-VMProcessor -CompatibilityForMigrationEnabled`); Windows Server 2025 adds a dynamic compatibility mode for clusters. Run `Compare-VM -Name <vm> -DestinationHost <host>` before a planned move to read the compatibility report.
- **Hyper-V Replica** replicates asynchronously every 30 seconds, 5 minutes or 15 minutes, with up to 24 hourly recovery points and optional extended replication to a third host. Use Kerberos inside a domain and certificates otherwise. It is disaster recovery, not high availability and not a backup: test failover regularly, and plan planned failover (no data loss) separately from unplanned failover (up to one interval lost).

## Nested virtualisation, GPU partitioning and DDA

- **Nested:** Intel VT-x with EPT on 2016 or later hosts; AMD EPYC or Ryzen on 2022 or later hosts. Enable with `Set-VMProcessor -ExposeVirtualizationExtensions $true` while the VM is off, turn MAC address spoofing on for nested VM networking, and note that a VM running Hyper-V cannot change memory while running, so Dynamic Memory has no effect. The host needs VM configuration version 8.0 or higher for Intel and 9.3 or higher for AMD. Microsoft supports one level of nesting in production for Hyper-V and Hyper-V isolated containers, and does not recommend it for failover clustering or performance-sensitive applications.
- **GPU partitioning (GPU-P)** is Windows Server 2025: it shares a GPU across VMs using SR-IOV, supports live migration between hosts (CPUs need IOMMU DMA bit tracking; migration falls back to TCP with compression) and clustering on Datacenter. It needs a homogeneous GPU configuration across hosts and a vendor driver that supports it (NVIDIA vGPU software 18 or later for NVIDIA). Check the current supported GPU list on Microsoft Learn before buying hardware.
- **DDA** hands an entire PCIe device to one VM and blocks live migration of that VM. A device cannot be both DDA and partitioned.

## Version highlights (verify against the host)

| Release | Notable for Hyper-V |
|---|---|
| 2016 | Production checkpoints, nested virtualisation (Intel), PowerShell Direct, hot add of NICs on Generation 2, shielded VMs |
| 2019 | Config version 9.0, shielded VM support for Linux guests |
| 2022 | AMD nested virtualisation, config version 10.0, 1,024 virtual processors per VM, LBFO not supported with Hyper-V |
| 2025 | Config version 12.0, 2,048 virtual processors and 240 TB memory per Generation 2 VM, GPU-P live migration and clustering, updated dynamic processor compatibility for clusters, AccelNet for SR-IOV on clusters, Generation 2 default in Hyper-V Manager, Hyper-V workgroup clusters |

Microsoft's free standalone Hyper-V Server ended with 2019; there is no Hyper-V Server 2022 or 2025. Lifecycle dates are in `windows-server-ops/references/version-notes.md`.

## Pitfalls

1. Generation 1 VMs created out of habit.
2. Dynamic Memory on database VMs.
3. Long-lived checkpoints, especially on domain controllers and database VMs.
4. Live migration over the management NIC.
5. `Update-VMVersion` run before every host is upgraded.
6. Antivirus scanning VHDX files on the host without exclusions, or exclusions that were never tested.
7. Overcommitting RAM so Smart Paging or host paging starts.
8. Deleting `.avhdx` files in the file system instead of through Hyper-V.
9. Treating Replica as a backup.
10. Assuming a "Running" VM state means the guest OS works (check the heartbeat integration service).

## Red flags

- A state-changing or one-way command presented as a check.
- A cmdlet name taken from memory (for example `Get-VMNumaNodeStatus`, which does not exist; the cmdlet is `Get-VMHostNumaNodeStatus`) without confirming it.
- A limit, version or feature-by-release claim with no source and date.
- Credentials, replication keys or certificate passwords written into a command or script.

## References and scripts

- `references/architecture.md`: partitions, VMBus, enlightenments, generations and configuration versions, memory, NUMA, virtual networking, virtual storage, integration services.
- `references/best-practices.md`: host design, VM sizing, memory, storage and checkpoints, live migration, Replica, monitoring targets.
- `references/diagnostics.md`: event logs, counters, and workflows for a VM that will not start, failed live migration, slow VMs, replication lag.
- `scripts/host-health.ps1`, `vm-inventory.ps1`, `network-and-switches.ps1`, `storage-and-checkpoints.ps1`, `replication-and-migration.ps1`, `performance-snapshot.ps1`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a query that fails or returns nothing), 2 critical findings. A check that could not run is therefore never a clean pass.

The scripts only read state, need the Hyper-V PowerShell module on the host, and are compatible with Windows PowerShell 5.1 and PowerShell 7. They are parse-checked and were run against mocked cmdlets, including an empty-result world and a throwing world (none exits 0), but not on a live host, and property names are unconfirmed against a real session. Run them on a non-critical host first.

## Boundaries

- Choosing between hypervisors, or planning a migration to or from Hyper-V: `virtualization-platform-selection`.
- Failover cluster quorum, CSV, Cluster-Aware Updating, cluster networking: `windows-failover-clustering-ops`.
- Windows Server base operations, patching, backup, licensing: `windows-server-ops`.
- WSL 2 (which runs on the Hyper-V platform): `wsl-ops`.
- Shielded VM and Host Guardian Service design, System Center Virtual Machine Manager and Azure Local: not covered here.
- Other hypervisors: `vmware-vsphere-ops`, `proxmox-ops`, `kvm-libvirt-ops`.
- Credentials: `secrets-hygiene`. PowerShell module problems: `powershell-module-compat`.

## Bottom line

Pin host release, generation and configuration version; read before changing; keep checkpoints short and live migration on its own network; treat the configuration version upgrade as one-way; and verify every limit or version claim against Microsoft's current pages.
