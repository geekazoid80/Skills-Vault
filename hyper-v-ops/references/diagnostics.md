# Hyper-V diagnostics reference

Start from the symptom, gather the event logs for the window, then use counters to separate host, storage, network and guest causes. Read-only commands unless marked.

## Quick health commands

```powershell
Get-VM | Select-Object Name, State, Status, CPUUsage, MemoryAssigned, Uptime, Generation, Version
Get-VMHost | Select-Object ComputerName, LogicalProcessorCount, MemoryCapacity, NumaSpanningEnabled,
    VirtualMachineMigrationEnabled, VirtualMachineMigrationAuthenticationType, VirtualMachineMigrationPerformanceOption
Get-Service vmms, vmcompute, hvhost -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
Get-VM | Get-VMSnapshot | Select-Object VMName, Name, SnapshotType, CreationTime
Get-VMReplication | Select-Object VMName, State, Health, Mode, LastReplicationTime
Get-VM | ForEach-Object { $hb = Get-VMIntegrationService -VM $_ -Name Heartbeat; [pscustomobject]@{ VM = $_.Name; State = $_.State; Heartbeat = $hb.PrimaryStatusDescription } }
```

The `Status` column of `Get-VM` and the Heartbeat description come from the heartbeat integration service: a VM that is Running but has no heartbeat may have a hung or booting guest, or no integration components.

## Event logs

| Log | Use |
|---|---|
| `Microsoft-Windows-Hyper-V-VMMS-Admin` | VM lifecycle, configuration and management errors |
| `Microsoft-Windows-Hyper-V-VMMS-Operational` | Start, stop and pause operations |
| `Microsoft-Windows-Hyper-V-Worker-Admin` | Per-VM worker process events |
| `Microsoft-Windows-Hyper-V-Hypervisor-Admin` and `-Operational` | Hypervisor-level events |
| `Microsoft-Windows-Hyper-V-VID-Admin` | Virtualisation infrastructure driver (memory, NUMA, virtual processors) |
| `Microsoft-Windows-Hyper-V-StorageVSP-Admin` | Storage provider errors |
| `Microsoft-Windows-Hyper-V-VmSwitch-Operational` | Virtual switch events |
| `Microsoft-Windows-Hyper-V-Compute-Admin` | Compute service (containers and VMs) |

Log names are listed with `Get-WinEvent -ListLog *Hyper-V*`; names vary a little by release, so list them rather than assuming. Query the last day:

```powershell
$since = (Get-Date).AddHours(-24)
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Hyper-V-VMMS-Admin'; StartTime = $since; Level = 1,2,3 } -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, Message
```

(`-ErrorAction SilentlyContinue` hides the "no events found" error; the shipped scripts handle that case explicitly.)

## Performance counters

Names below are those most commonly cited; confirm what exists on your build with `Get-Counter -ListSet 'Hyper-V*'` before relying on a name.

| Set | Counter | Reading |
|---|---|---|
| `Hyper-V Hypervisor Logical Processor` | `% Total Run Time`, `% Guest Run Time`, `% Hypervisor Run Time` | Host CPU; guest plus hypervisor run time above 90 per cent sustained is saturation; sustained hypervisor run time above about 10 per cent suggests heavy exits (emulation, many timers, nested virtualisation) |
| `Hyper-V Hypervisor Virtual Processor` | `% Total Run Time` | Per virtual processor load |
| `Hyper-V Dynamic Memory VM` | `Current Pressure` | Above 100 means the VM wants more memory than it has; above about 150 is serious and usually means guest paging |
| `Hyper-V Virtual Storage Device` | read and write bytes per second, queue length, latency | Latency: if the counter reports milliseconds on your build (the unit is not stated in the sources read for this skill, so confirm it), common rules of thumb are under about 1 ms on flash and under about 10 ms on RAID of SAS disks, and 20 ms or more sustained points at storage |
| `Hyper-V Virtual Switch` and `Hyper-V Virtual Network Adapter` | bytes per second and dropped packets | Any steady drop count needs investigating |

Method: confirm host CPU first, then memory pressure, then storage latency, then network drops. If the host is quiet and one VM is slow, look inside the guest and at NUMA and integration services.

## Workflows

### A VM will not start

1. Read the VMMS-Admin and Worker-Admin events for the start time.
2. "The virtual machine could not be started because the hypervisor is not running": virtualisation is off in firmware, or `bcdedit /enum` shows `hypervisorlaunchtype` as Off. Fix firmware, set it to Auto (a change; needs a reboot).
3. Not enough memory: compare Startup RAM with free host memory, lower Startup RAM or free memory; Smart Paging is a slow bridge only.
4. Access denied or file not found: the VM worker runs as `NT VIRTUAL MACHINE\<GUID>`, so check NTFS permissions on the VHDX and the VM directory, that the path exists, that the volume is online, and that no other process holds the file. For files on SMB shares, the share and NTFS permissions must include the host computer account.
5. A disk in a "Paused-Critical" state: the volume is full or storage went offline. Free space or restore the path, then resume.
6. Corrupt configuration: restore the VM's configuration from backup, or create a new VM and attach the existing VHDX files.
7. A checkpoint chain with a missing parent `.avhdx`: stop, copy the whole folder first, then inspect the chain with `Get-VHD` before any merge.

### Live migration fails or is slow

1. Run `Compare-VM -Name <vm> -DestinationHost <host>` (or the equivalent in Windows Admin Center) and read the compatibility report.
2. Authentication: Kerberos needs constrained delegation configured in Active Directory for the CIFS and Microsoft Virtual System Migration Service on the other host; CredSSP needs an interactive session on the source.
3. "Incompatible processor": enable processor compatibility mode on the VM (VM off), or use identical hosts.
4. Insufficient resources on the target: free memory or CPU, or pick another host. For VMs with GPU partitions, the target needs a matching GPU and driver.
5. Storage not reachable: share and NTFS permissions on the destination path, SMB reachability and the firewall.
6. Slow: check which network carries the migration (`Get-VMMigrationNetwork`, `Get-VMHost` `UseAnyNetworkForMigration`), the transport option, and RDMA state (`Get-NetAdapterRdma`). Check `Microsoft-Windows-Hyper-V-VMMS-Admin` for the failure reason.
7. A VM using Discrete Device Assignment cannot live migrate by design.

### Slow VM

1. Host first: processor run time, memory pressure, storage latency, network drops.
2. NUMA: a VM larger than a node, or with NUMA spanning, pays remote-memory latency. `Get-VMHostNumaNode` shows the topology; `Get-VMHostNumaNodeStatus` shows VM placement per node but returns an error while NUMA spanning is enabled.
3. Overcommit: count virtual processors against logical processors; look at `% Guest Run Time`.
4. Memory: Dynamic Memory pressure above 100 sustained; static memory too small; a minimum that is too low.
5. Storage: deep checkpoint chain, a dynamic VHDX on slow media, a full volume, antivirus scanning.
6. Network: no VMQ, driver issues, SR-IOV disabled after migration, wrong team mode.
7. Guest: missing integration components, time sync fighting a domain time source.

### Replication problems and RPO

```powershell
Get-VMReplication | ForEach-Object {
    [pscustomobject]@{ VM = $_.VMName; State = $_.State; Health = $_.Health
        LagMinutes = if ($_.LastReplicationTime) { [math]::Round(((Get-Date) - $_.LastReplicationTime).TotalMinutes, 1) } else { $null } }
}
Measure-VMReplication -VMName <vm>
```

Causes: WAN saturation or loss, a change rate above what the link carries, a replica host with slow storage, certificate expiry, a stopped listener or blocked port on the replica host, or a paused replication that nobody resumed. `Resume-VMReplication` is a change; resynchronisation after a long pause can be large.

### Integration services

`Get-VMIntegrationService -VMName <vm>` shows each service, whether it is enabled and its status. "Protocol version mismatch" means the guest components are old (update the guest through Windows Update, or update the Linux kernel). Heartbeat "Lost Communication" with a running guest means a hung or overloaded guest. A disabled Time Synchronisation service is deliberate on many domain-joined VMs.

### Checkpoint problems

A merge that never finishes usually needs the VM off or the storage to have space for the merged disk. Check free space on the volume holding the chain, check `Get-VHD` for each `.avhdx` and `Get-VMSnapshot` for the tree, and let Hyper-V do the merge. Do not rename or delete files in the VM folder.

## Reference: services, ports, paths

| Item | Detail |
|---|---|
| Services | `vmms`, `vmcompute`, `hvhost`; per-VM `vmwp.exe` processes |
| Live migration | TCP 6600 is the figure commonly cited for the migration listener (not confirmed on the Microsoft pages read for this skill), plus SMB 445 when using the SMB transport; take the ports from the enabled Hyper-V firewall rules on your host rather than from a table |
| Replica | The listener port you choose in Replica settings (HTTP for Kerberos, HTTPS for certificates); the host firewall rules named Hyper-V Replica HTTP and HTTPS Listener must be enabled |
| Default VM storage | Set with `Set-VMHost -VirtualMachinePath -VirtualHardDiskPath`; check `Get-VMHost` |
