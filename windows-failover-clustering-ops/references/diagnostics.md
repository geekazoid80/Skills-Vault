# Failover clustering diagnostics reference

Read-only unless marked. Start with what the cluster says about itself, then correlate across nodes.

## Validation

`Test-Cluster` writes an HTML report (default under the temp folder, or the path given with `-ReportName`). Categories: Inventory, Network, Storage, System Configuration, Hyper-V Configuration and Storage Spaces Direct. **The Storage tests can take cluster disks offline** (without `-Disk` and `-Force`, online in-use disks are skipped, and some CSV tests create a local test user on each node): run them before the cluster hosts workloads or in a maintenance window. On a live cluster run only:

```powershell
Test-Cluster -Node n1, n2 -Include "Inventory", "Network", "System Configuration"
```

Common findings: mismatched NIC drivers or firmware, DNS not resolving node names, a disk not visible on every node, no SCSI-3 persistent reservation support, OS or hotfix level differences, and time not synchronised.

## Logs

```powershell
Get-ClusterLog -Destination C:\ClusterLogs -TimeSpan 60 -UseLocalTime   # minutes of log, one file per node
(Get-Cluster).ClusterLogLevel                                            # read it before changing; put it back afterwards
```

The cluster log is the main artefact for failover analysis: read the same minute from every node, and search by the prefixes `[RCM]`, `[RHS]`, `[GUM]`, `[NETFT]`, `[QM]`, `[CSV]`. Use local time for correlation with other logs. The `Microsoft-Windows-FailoverClustering/Diagnostic` channel is off by default; enabling it adds detail and volume, so enable it for the investigation only.

## Event IDs (System log, provider Microsoft-Windows-FailoverClustering)

Meanings below are from Microsoft's Failover Clustering system log events article and the linked troubleshooting guides (those pages state they apply to Windows Server 2016 to 2022 and Azure Local; check newer releases).

| ID | Name | Meaning and first move |
|---|---|---|
| 1135 | Node down | A node was removed from active membership: its cluster service stopped or it lost communication. Run validation for the network; look at the same time on every node; see the 1135 guide's three patterns (one node unreachable by all, a site split, inconsistent reports) |
| 1177 | Arbitration failed | The cluster service shut down because quorum was lost: network loss between nodes or a witness failure. Restore connectivity or the witness; do not force quorum until you know the other partition is down |
| 1146 | RHS died | The Resource Hosting Subsystem process terminated and restarted. Find the faulty resource and resource DLL; common with third-party resource types |
| 1069 | Resource failed | A resource in a role failed; policy decides whether it restarts or moves. The event has variants that add the resource type and error |
| 5120 | CSV paused | A Cluster Shared Volume paused after a failure; I/O is queued until a path returns. Often SMB reachability to the owner node; check the status code in the event and that Client for Microsoft Networks and File and Printer Sharing are enabled on cluster adapters |
| 5142 | CSV no access | The volume is no longer accessible from this node; check the node's storage and network path to the owner |
| 5146 | CSV move vetoed | A move was blocked because a volume is dismounted; retry after the dismount ends |

Always read the event text for the status code and the resource name; the ID narrows the search, it does not finish it.

## Workflows

### A role or resource will not come online

1. `Get-ClusterResource | Where-Object State -ne 'Online'`, then the 1069 event for the resource and error code.
2. Cluster log for the resource name and `[RHS]` entries around the time.
3. By type: IP Address (duplicate address, wrong network role), Network Name (computer object in Active Directory, DNS registration, permissions), Physical Disk (visibility, MPIO, disk errors in the System log), Generic Service (service account, binary path, dependencies), Virtual Machine (see `hyper-v-ops`).
4. Try `Start-ClusterResource` once, only after you understand the cause (a change).
5. If the role keeps failing back and forth, check the failover threshold and period: exhausting them leaves the role Failed even when the fault is intermittent. Fix the cause before touching the threshold.

### Unexpected failover

1. Find 1135, 1177, 1146 and 1069 on every node and line them up by time.
2. Network: adapter statistics (`Get-NetAdapterStatistics`), switch logs, drops, firewall rules for UDP 3343, antivirus or security agents holding the stack.
3. Compare heartbeat settings with measured latency (`Get-Cluster | Format-List *Subnet*`).
4. Host: a node out of memory, a long pause (backup, snapshot, driver), a storage stall, a hypervisor or firmware fault.
5. Node status: `Get-ClusterNode | Format-List Name, State, StatusInformation` (isolated or quarantined). Microsoft publishes a quarantine troubleshooting guide; whichever the cause, fix the underlying network or node fault before releasing the node.

### Quorum lost

1. Count the votes (`scripts/quorum-and-witness.ps1`): which nodes are Up, whether the witness is reachable.
2. If nodes are healthy but the witness is not, restore the witness or change the witness type once quorum returns.
3. If a majority of nodes are really gone and the business needs the cluster, force a start on **one** partition only: `Start-ClusterNode -FixQuorum` (alias of `-ForceQuorum`; an emergency; confirm no other partition is running, and use `-PreventQuorum` on the nodes of the other partition if they could start). Afterwards bring the other nodes back, restart the cluster service normally and validate.
4. Review why: network partition, witness outage, simultaneous node failures, or too few votes.

### CSV in redirected I/O or paused

1. `Get-ClusterSharedVolumeState` for state and reasons per node: file system redirected (a backup, maintenance mode, or ReFS on SAN) or block redirected (a node lost its storage path).
2. Storage path: MPIO state, adapter or HBA errors, disk events in the System log (Disk, Ntfs, ReFS), `Get-PhysicalDisk` health on Storage Spaces Direct.
3. SMB path for the redirected traffic: SMB Multichannel (`Get-SmbMultichannelConnection`), firewall, network binding of Client for Microsoft Networks and File and Printer Sharing.
4. Resolve the cause before taking the volume out of maintenance mode.

### Node isolated or cannot rejoin

1. Ping and name resolution between nodes on every cluster network.
2. `Get-ClusterNetworkInterface` and adapter state; firewall rules named for clustering; the cluster service (`Get-Service ClusSvc`).
3. `StatusInformation` on the node and `[QM]` log entries; wait out or fix the cause of quarantine instead of clearing it blindly.
4. Time synchronisation and Kerberos: check that the cluster name object still exists in Active Directory and that the nodes agree on time.

## Reference

| Item | Detail |
|---|---|
| Heartbeat | UDP 3343 between nodes (Microsoft's event 1135 guide also lists TCP 3343 for joining) |
| Also needed | SMB (445) for CSV redirected I/O and file share witnesses; RPC endpoint mapper (135) and the dynamic RPC range; HTTPS (443) from every node for a cloud witness |
| Config database | `%SystemRoot%\Cluster\CLUSDB` and `HKLM\Cluster` when loaded |
| CSV root | `C:\ClusterStorage\` |
| Cluster log folder | `%SystemRoot%\Cluster\Reports` (default for `Get-ClusterLog`) |
