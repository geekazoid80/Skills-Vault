---
name: windows-failover-clustering-ops
description: "Use for Windows Server Failover Clustering (WSFC) administration and troubleshooting on Windows Server 2016, 2019, 2022 and 2025: quorum and witnesses (disk, file share, cloud), dynamic quorum and vote arithmetic, cluster networks and heartbeat settings, Cluster Shared Volumes and redirected I/O, roles and failover policy, node drain and maintenance, Cluster-Aware Updating, rolling cluster OS upgrade, stretch clusters, cluster sets, Storage Spaces Direct sizing, and cluster event IDs. Triggers include \"failover cluster\", \"WSFC\", \"quorum\", \"cloud witness\", \"file share witness\", \"CSV\", \"redirected I/O\", \"Suspend-ClusterNode\", \"Cluster-Aware Updating\", \"CAU\", \"Test-Cluster\", \"Get-ClusterLog\", \"event ID 1135\", \"event ID 1177\", \"event ID 5120\", \"cluster functional level\", \"cluster sets\", \"split brain\", \"node quarantine\". NOT for Hyper-V VM settings, live migration or Replica (hyper-v-ops), NOT for choosing a hypervisor (virtualization-platform-selection), NOT for the Windows Server base (windows-server-ops), NOT for Linux Pacemaker and Corosync clusters (kvm-libvirt-ops mentions them for KVM), NOT for SQL Server Always On internals."
license: MIT
metadata:
  version: 1.0.0
---

# Windows Failover Clustering operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: windows-failover-clustering-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A Windows Server failover cluster is a set of nodes that share a configuration database, vote on membership (quorum), and move clustered roles to a healthy node when a node or resource fails. Behaviour, defaults and limits vary by Windows Server release (2016, 2019, 2022, 2025) and by the cluster functional level, so pin both before advising.

**Core principle:** protect quorum first. Nearly every destructive cluster event starts with a change that reduced the vote margin, so check the margin before draining, evicting or rebooting a node, and state the effect on running roles before any change.

> **Caveat on provenance.** Commands, defaults and scripts were reshaped from a community upstream, corrected against Microsoft Learn and Microsoft troubleshooting pages read on 2026-10-19, and reviewed independently. Syntax has not been run against a live cluster. Where Microsoft documents conflicting defaults the text says so; read the value on your own cluster.

## Step 0: establish what you are on

```powershell
Get-Cluster | Format-List Name, ClusterFunctionalLevel, DynamicQuorum, SameSubnetThreshold, CrossSubnetThreshold
Get-ClusterNode | Format-Table Name, State, DrainStatus, NodeWeight, DynamicWeight
Get-ClusterQuorum | Format-List
Get-ClusterGroup | Format-Table Name, State, OwnerNode
```

Then read `references/diagnostics.md` for events and the cluster log, or run the scripts in `scripts/`. Run them on a cluster node (or a machine with the clustering tools and rights to the cluster).

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Disruptive or destructive, get explicit approval |
|---|---|---|
| `Get-Cluster*`, `Get-ClusterSharedVolumeState`, `Get-ClusterLog`, `Get-CauClusterRole`, `Get-CauReport`, `Get-CauRun`, `Get-WinEvent`, `Test-Cluster -Include "Inventory","Network","System Configuration"` (non-disruptive, but it writes a report) | `Suspend-ClusterNode` (with or without `-Drain`), `Resume-ClusterNode`, `Move-ClusterGroup`, `Set-ClusterQuorum`, `Set-ClusterOwnerNode`, `(Get-Cluster).<property> =`, `Add-ClusterSharedVolume`, `Add-CauClusterRole`, `Invoke-CauScan` (contacts the update source on every node) | `Test-Cluster` with the Storage tests on a live cluster (can take disks offline), `Start-ClusterNode -FixQuorum` (alias of `-ForceQuorum`; `-PreventQuorum` is for the other partition), `Remove-ClusterNode` (evict), `Stop-Cluster`, `Update-ClusterFunctionalLevel` (one way), `Remove-ClusterSharedVolume`, `Invoke-CauRun`, `Clear-ClusterNode`, force-quorum on one partition while another may be running |

## Quorum

Each node holds one vote, a witness adds one more, and the cluster runs while it can see more than half of the votes. For N possible votes you need floor(N / 2) + 1. **Dynamic quorum** (on by default) recalculates the majority as nodes leave membership, so a cluster survives a sequence of failures as long as quorum held at each step; losing a majority of votes at once still stops it. A paused node stays a member and keeps its vote. **Dynamic witness** adds or removes the witness vote so the total stays odd. Microsoft's pages differ on emphasis: the witness deployment page advises a witness on every cluster (Windows Server 2012 R2 and later), while the quorum overview calls one required for two nodes, strongly recommended for three or four and unnecessary for five or more. The practical advice is to configure one and let the cluster manage the votes. Before a full shutdown with a file share or cloud witness, restart the cluster service on the last active node (event 1561 relates).

| Witness | Requirements (Microsoft Learn) |
|---|---|
| Disk | A shared disk visible to all nodes, larger than 512 MB, basic disk (not dynamic), no drive letter, not used for other data |
| File share | SMB 2 or later share with at least 5 MB free, on a Windows server in the same forest or on a non-domain device such as a NAS, a workgroup Windows machine or a router with USB storage (a non-domain share needs a 2019 or later cluster); dedicated to one cluster per share, never on DFS or replicated storage; one file server can serve many clusters |
| Cloud | An Azure Standard general-purpose v2 storage account; port 443 open from every node; the `msft-cloud-witness` container is created for you; rotate access keys on the secondary first |

There is no separate "USB witness": the router-with-USB case is a file share witness. Pick a cloud witness when nodes have reliable outbound internet; a file share witness where they do not; a disk witness only where shared disks already exist (a Storage Spaces Direct cluster, SQL Server Availability Group or Exchange DAG has no shared disks). Multi-site clusters put the witness in a third location. After a forced start (`Start-ClusterNode -FixQuorum`), stop the forced node's partition from running alongside a healthy one: that is how split brain happens.

## Networking and heartbeat

- **Roles** on `Get-ClusterNetwork`: 0 not used by the cluster, 1 cluster traffic only, 3 cluster and client; 2 is not a supported value. Default is 3.
- Use at least two independent networks for cluster traffic. Heartbeats use UDP 3343.
- **Heartbeat tuning** (`SameSubnetDelay`, `SameSubnetThreshold`, `CrossSubnetDelay`, `CrossSubnetThreshold`): Microsoft sources give delay 1,000 ms with thresholds of 10 (same subnet) and 20 (cross subnet) as the Windows Server 2016 and 2019 defaults, with a maximum of 120; older 2012 R2 material and some API pages list 5. Microsoft's pages do not state the 2022 and 2025 defaults, so read them with `Get-Cluster | Format-List *Subnet*` on a new cluster. Raise thresholds for stretch clusters over WAN links only with measured latency, since a higher threshold also slows genuine failure detection.
- **Quarantine:** a node isolated `QuarantineThreshold` times (default 3) within an hour is quarantined for `QuarantineDuration` (7,200 seconds in the `Get-Cluster` documentation). A quarantined node hosts no roles; find the cause (see diagnostics) before letting it back.
- Hyper-V clusters: use SET for virtual switches (`hyper-v-ops`); live migration network settings live in Hyper-V, not in the cluster.

## Cluster Shared Volumes

A CSV lets every node read and write one NTFS or ReFS volume. I/O is **direct** when the node has storage connectivity, **file system redirected** (per volume: backups, maintenance mode, or ReFS on SAN) or **block redirected** (per node: it lost its storage path), when I/O flows over SMB through the coordinator node. Microsoft advises NTFS for CSVs on SAN-attached storage (ReFS CSVs on a SAN run redirected) and ReFS for Storage Spaces Direct. `Get-ClusterSharedVolumeState` shows the state and the reason per node. Events 5120 (volume paused after a failure) and 5142 (no longer accessible from this node) are the usual alarms. Keep CSV free space above 20 per cent (a rule of thumb) and investigate any redirected volume that is not in maintenance mode.

## Roles, failover and maintenance

- Failover policy is per role: failover threshold and period, preferred and possible owners, failback (prevent, allow, window), and anti-affinity class names (a soft constraint: it is dropped to keep a role running). Read the live defaults; do not assume 3 per 6 hours.
- **Drain before maintenance:** `Suspend-ClusterNode -Name <node> -Drain`, wait for `DrainStatus` to complete, patch, restart, `Resume-ClusterNode -Failback Immediate` (or `NoFailback`). Check the vote margin first.
- **N+1:** after one node is lost the survivors must carry every role (memory, CPU, storage throughput, licensing).
- **Cluster-Aware Updating** drains, patches and restarts one node at a time in self-updating mode (a cluster role on a schedule) or remote-updating mode (an update coordinator outside the cluster). Plug-ins: the default Windows Update/WSUS plug-in and a hotfix plug-in for offline fixes. Keep `MaxFailedNodes` low, require all nodes connected, and review the report after every run. Patch tooling products are outside this skill (`action1-patch-management`).

## Upgrades, stretch clusters, cluster sets, Storage Spaces Direct

- **Rolling cluster OS upgrade** (Microsoft Learn): upgrade one OS version at a time (2022 to 2025; 2016 to 2025 takes three passes or a new cluster). The process is reversible until you run `Update-ClusterFunctionalLevel` and the storage pool update; after that no older node can join. VMs older than configuration version 8.0 cannot run on a 2022 or later cluster, and an LBFO team under a Hyper-V switch must be removed before an in-place upgrade to 2022 or later, with a SET switch created afterwards. Network ATC is available on Windows Server 2025.
- **Fault domains** (site, rack, chassis, node) arrived in 2016; on 2019 fault domain awareness is off by default and is enabled with the `AutoAssignNodeSite` cluster property (Microsoft Learn). Plan stretch clusters with a witness in a third site, Storage Replica between sites, and cross-subnet thresholds from measured latency. Storage Replica on Standard edition (2019 and later) is limited to a single volume of up to 2 TB (Microsoft Learn); without those limits it needs Datacenter.
- **Cluster sets** (2019 and later) group clusters under one namespace for VM mobility; tested up to 64 total nodes. Storage Spaces Direct stays inside each member cluster.
- **Storage Spaces Direct** is a Datacenter feature (and Azure Local): 2 to 16 servers, local drives, RDMA networking recommended, and drive and cache layout from the hardware requirements page. Design belongs with the storage owner; this skill covers its cluster behaviour.
- **Limits:** 64 nodes per failover cluster with Hyper-V hosts and 8,000 running VMs per cluster (Microsoft Learn scale limits).

## Pitfalls

1. No witness on an even-node cluster, or a witness that nobody monitors.
2. Draining or rebooting a node when the vote margin is already zero.
3. Running `Test-Cluster` with Storage tests on a live cluster.
4. ReFS on a SAN-attached CSV that then runs in redirected I/O.
5. A CSV left in redirected mode for days.
6. Raising heartbeat thresholds to hide a network fault.
7. Forcing quorum on one side of a partition while the other side is alive.
8. Raising the cluster functional level before every node, VM and driver is validated.
9. Hardware, firmware and driver drift between nodes.
10. Treating the System log of one node as the whole picture (read the cluster log from every node).

## Red flags

- A cluster event ID quoted from memory (1146 is the Resource Hosting Subsystem terminating; 1177 is the cluster service shutting down for lost quorum).
- A default value, limit or feature-by-release claim with no source and date.
- Quorum or witness changes made without stating the vote arithmetic.
- Access keys, SAS tokens or credentials written into a command or script.

## References and scripts

- `references/architecture.md`: cluster service internals, CLUSDB and GUM, heartbeat, quorum arithmetic, resource model, CSV, networks, upgrade mechanics.
- `references/best-practices.md`: design, witness choice, network and storage design, CAU, maintenance procedure, stretch clusters, monitoring targets.
- `references/diagnostics.md`: validation, cluster log, event IDs, workflows for unexpected failover, resource failure, quorum loss, CSV errors and quarantine.
- `scripts/cluster-health.ps1`, `quorum-and-witness.ps1`, `network-and-heartbeat.ps1`, `csv-health.ps1`, `roles-and-updates.ps1`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a query that returns nothing where something is expected), 2 critical findings. A check that could not run is therefore never a clean pass; a cluster with no Cluster Shared Volumes is reported as informational.

The scripts only read state, need the Failover Clustering PowerShell module (and the Cluster-Aware Updating module for the last one), and are compatible with Windows PowerShell 5.1 and PowerShell 7. They are parse-checked and were run against mocked cmdlets, including an empty-result world and a throwing world (none exits 0), but not on a live cluster, and property names are unconfirmed against a real session. They deliberately do not run `Test-Cluster` or start a CAU scan.

## Boundaries

- Hyper-V VM settings, live migration, Replica and GPU features: `hyper-v-ops`.
- Hypervisor choice and migration planning: `virtualization-platform-selection`.
- Windows Server base operations, patching, backup, SMB and storage: `windows-server-ops`.
- Active Directory, the cluster name object and DNS records: `ad-ds`, `windows-dns-ops`.
- SQL Server Always On availability group configuration and application clustering: not covered here.
- Linux high availability: Pacemaker and Corosync are mentioned for KVM hosts in `kvm-libvirt-ops`; Linux clustering is otherwise not covered.
- Credentials and keys: `secrets-hygiene`. PowerShell module problems: `powershell-module-compat`.

## Bottom line

Know the vote arithmetic before touching a node, keep a witness on the cluster, drain before maintenance, treat redirected I/O and quarantine as symptoms to explain, upgrade one OS version at a time, and verify every default or event meaning against Microsoft's current pages.
