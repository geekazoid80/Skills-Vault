# Hyper-V architecture reference

## Partitions and the I/O path

When the role is enabled and the host restarts, the hypervisor loads first (the loader is hvix64 on Intel and hvax64 on AMD) and the Windows installation becomes the **parent partition**, a privileged partition that keeps the physical device drivers. Every VM is a **child partition**. The hypervisor handles CPU virtualisation (Intel VT-x or AMD-V), second-level address translation (EPT or NPT) and memory isolation; it does not own device drivers.

| Part | Where it runs | Job |
|---|---|---|
| VSP (virtualisation service provider) | Parent partition | Serves a synthetic device using the real driver |
| VSC (virtualisation service client) | Child partition | Sends I/O to the VSP |
| VMBus | Shared ring buffers between partitions | Transport for all synthetic devices |
| `vmms.exe` (Hyper-V Virtual Machine Management) | Parent | Management service behind the cmdlets and Hyper-V Manager |
| `vmwp.exe` (VM worker process) | Parent, one per running VM | Runs the VM's virtual devices; runs as `NT VIRTUAL MACHINE\<VM GUID>` |
| `vmcompute` (Hyper-V Host Compute Service) | Parent | Compute service shared with containers |

A synthetic disk request goes guest VSC, VMBus ring, parent VSP, physical driver. An emulated device (Generation 1 IDE and legacy NIC) is slower because the hypervisor emulates hardware registers; Generation 2 has no emulated boot path. **Enlightenments** are guest changes that avoid emulation or exits (synthetic timers, enlightened spinlocks, APIC and TLB flush hypercalls). Current Windows guests are fully enlightened, and the Hyper-V drivers (`hv_vmbus`, `hv_storvsc`, `hv_netvsc`, `hv_utils`) ship in the mainline Linux kernel, so supported Linux distributions need no extra package.

Services to check on a host: `vmms`, `vmcompute`, and the hypervisor itself (`(Get-CimInstance Win32_ComputerSystem).HypervisorPresent`). The BCD setting `hypervisorlaunchtype` must be `Auto`; `bcdedit /enum` shows it.

## Generations and configuration versions

Generation 1 uses emulated BIOS firmware and IDE boot. Generation 2 uses UEFI with a synthetic SCSI boot disk, Secure Boot (on by default; pick the "Microsoft UEFI Certificate Authority" template for most Linux guests), a virtual TPM, PXE over the synthetic NIC, and hot add of vNICs and memory. The generation is fixed at creation. Boot disk limits: Generation 1 2 TB (VHDX) or 2,040 GB (VHD); Generation 2 64 TB.

The **configuration version** (`Get-VM | Select Name, Version`) controls the on-disk format and the features a VM can use. It is independent of generation.

| Host | Highest configuration version supported |
|---|---|
| Windows Server 2016 | 8.0 |
| Windows Server 2019 | 9.0 |
| Windows Server 2022 | 10.0 |
| Windows Server 2025 | 12.0 |

(Microsoft Learn, "Upgrade virtual machine version", fetched 2026-10-19; the page lists every intermediate version each host can import.) A host imports a VM whose version it supports, so a VM can move to a newer host but a VM upgraded on a newer host cannot return. `Get-VMHostSupportedVersion` lists a host's range and `-Default` the version a new VM gets. To create a VM that stays portable to an older host use `New-VM -Version`. A cluster running Windows Server 2022 or later cannot run VMs older than version 8.0, so upgrade the version of old VMs as part of a cluster OS upgrade.

## Memory

- **Static:** fixed at startup.
- **Dynamic Memory:** Startup RAM, Minimum RAM, Maximum RAM, buffer percentage (default 20) and weight (0 to 10,000, default 5,000). A balloon driver in the guest reports demand; Hyper-V adds or removes memory between Minimum and Maximum. Windows guests report **memory pressure** (see diagnostics).
- **Runtime memory resize:** a running VM with static memory can have its memory changed on supporting hosts and guests, and a Dynamic Memory VM by changing Minimum and Maximum; confirm the host and configuration version (the version table on Microsoft Learn lists the feature).
- **Smart Paging:** a host-side file used only while a VM restarts and the host cannot supply Startup RAM; slow, and a symptom of overcommit.
- **NUMA:** the host is NUMA-aware and a VM that fits in a node is placed there. Virtual NUMA topology is exposed to the guest. `Set-VMProcessor -MaximumCountPerNumaNode` and `-MaximumCountPerNumaSocket` shape it for large VMs. NUMA spanning (`Set-VMHost -NumaSpanningEnabled`) allows memory from several nodes. Turn it off to protect latency-sensitive VMs; leave it on where a VM must exceed a node.

## Virtual networking

Switch types are external, internal and private. The vSwitch is an extensible switch (capture, filter and forwarding extensions: `Get-VMSwitchExtension`).

**Switch Embedded Teaming (SET)** puts teaming inside the vSwitch (`New-VMSwitch -EnableEmbeddedTeaming $true`). Microsoft Learn (Azure Local host network requirements; the `Set-VMSwitchTeam` reference gives the default algorithm as Dynamic) states: up to eight adapters per team, switch-independent configuration only, and Dynamic or Hyper-V Port load balancing (`Set-VMSwitchTeam -LoadBalancingAlgorithm`, default Dynamic; Hyper-V Port is advised at 10 Gbps and above). SET carries RDMA (SMB Direct), and Dynamic VMMQ requires it. LBFO is not supported with Hyper-V on Windows Server 2022 and later. Team members should have identical adapters, drivers and firmware.

**Other features:** VLAN access and trunk modes per vNIC; bandwidth weights and caps; port ACLs; MAC address spoofing (needed for nested VMs and some network virtual appliances); DHCP and router guard; VMQ and virtual RSS; **SR-IOV**, which presents a virtual function straight to the VM and is released during live migration; and on Windows Server 2025 clusters, **AccelNet**, which manages SR-IOV for VMs.

## Virtual storage

VHD tops out at 2,040 GB. **VHDX** supports 64 TB, a 4 KB logical sector option, journalled metadata updates, online resize and UNMAP. Disk types are fixed, dynamic and differencing. A differencing disk (`.avhdx`) is created by each checkpoint and chains to its parent. **VHD Sets (`.vhds`)** are the format for shared virtual disks in guest clusters (host-level VSS backup and online resize work, which shared VHDX lacks). **Storage QoS** applies minimum and maximum IOPS per virtual disk. **Virtual Fibre Channel** (NPIV) connects a VM to a SAN through a host HBA; Microsoft's scale page allows four virtual Fibre Channel adapters per VM.

## Integration services

Time synchronisation, operating system shutdown, data exchange (key-value pairs), heartbeat, VSS, and guest services (file copy with `Copy-VMFile`) run as services in the guest (`vmicheartbeat`, `vmicvss` and so on in Windows; `hv_utils`-based daemons such as `hv_vss_daemon` in Linux). On Windows guests they are updated through Windows Update. The heartbeat answers "did the guest boot": a VM state of Running only means Hyper-V set resources aside. **PowerShell Direct** (`Enter-PSSession -VMName`) uses VMBus and needs no guest network, only credentials in the guest.

## Checkpoints

A checkpoint is a point-in-time state with a differencing disk. **Production checkpoints** (the default) use VSS in Windows guests or a file-system freeze in Linux guests and capture no memory, so applying one boots the VM from a consistent disk state. **Standard checkpoints** also save memory and device state. Types are set with `Set-VM -CheckpointType` (`Disabled`, `Standard`, `Production`, `ProductionOnly`). Applying a checkpoint rolls state back and can corrupt replicating or time-sensitive systems (Active Directory domain controllers, databases with external transaction logs).

## Live migration

A live migration copies memory iteratively while the VM runs, then pauses briefly, transfers the last pages and resumes on the target. Variants: shared storage (state only), shared nothing (state and storage), and storage migration (VHDX files only). Authentication is Kerberos or CredSSP; transport options are plain TCP/IP, compression or SMB (SMB Direct over RDMA). The accepted `Set-VMHost` values are `TCPIP`, `Compression` and `SMB`. VMs with a GPU partition migrate over TCP with compression; VMs with Discrete Device Assignment cannot migrate.

## Hyper-V Replica

Changes are tracked at block level (resilient change tracking) and sent every 30 seconds, 5 minutes or 15 minutes. The replica can keep additional hourly recovery points (up to 24) and can itself replicate onward (extended replication). Authentication is Kerberos (HTTP) or certificates (HTTPS). Initial replication can be over the network, scheduled, from restored media or by shipping a disk. Failover kinds: test failover (isolated copy), planned failover (primary shut down, no loss), unplanned failover (loss up to one interval).

## Host management plane

PowerShell (Hyper-V module), Hyper-V Manager, Windows Admin Center, System Center Virtual Machine Manager and Azure Arc. Remote management uses WinRM/CIM and WMI. Keep hosts on Server Core where practical and manage them remotely.
