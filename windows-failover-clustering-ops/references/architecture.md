# Failover clustering architecture reference

## Components

| Component | Role |
|---|---|
| Cluster service (`clussvc`) | Coordinates membership, quorum, configuration replication, failover and health |
| Resource Host Subsystem (`rhs.exe`) | Hosts resource DLLs in separate processes so a faulty DLL does not crash the cluster service; a resource can be given its own monitor process |
| NetFT (`netft.sys`) | Virtual adapter that carries intra-cluster communication and heartbeats over whichever physical networks are healthy (UDP 3343) |
| CLUSDB | The cluster configuration database, a registry hive on every node (loaded as `HKLM\Cluster`) |
| Global Update Manager (GUM) | Applies every configuration change on all nodes in step, so nodes never diverge |
| Resource Control Manager (RCM) | Decides on placement and failover |

Cluster log prefixes you will meet: `[GUM]`, `[RHS]`, `[RCM]`, `[NETFT]` or `[Netft]`, `[QM]` (quarantine), `[FM]`, `[NM]`, `[CSV]`. Event channels: `System` log (provider Microsoft-Windows-FailoverClustering, where the numbered events below appear), `Microsoft-Windows-FailoverClustering/Operational`, and the `Diagnostic` channel (off by default).

## Quorum arithmetic

Votes come from nodes (assigned weight 1 or 0, called `NodeWeight`; the live value under dynamic quorum is `DynamicWeight`) and from at most one witness. The cluster runs while the votes it can see exceed half of the possible votes: with N possible votes it needs floor(N / 2) + 1.

| Nodes | Witness | Possible votes | Needed | Node failures survived if lost at the same time |
|---|---|---|---|---|
| 2 | none | 2 | 2 | 0 |
| 2 | yes | 3 | 2 | 1 |
| 3 | none | 3 | 2 | 1 |
| 4 | yes | 5 | 3 | 2 |
| 5 | none | 5 | 3 | 2 |

Dynamic quorum recalculates the majority as nodes leave membership: whenever the surviving nodes verify they hold a majority, the definition of majority is updated, so a cluster survives a sequence of failures provided quorum held at each step, but losing a majority of votes simultaneously (two of three nodes at once) stops it. A node that is merely paused stays a member and keeps its vote; a node that is Down can still show a dynamic weight of 1. Dynamic witness changes the witness vote so the total stays odd. These automatic adjustments make a witness cheap insurance rather than a requirement to count, which is why Microsoft advises one on every cluster.

## Witness types

Disk (a small shared disk the cluster owns), file share (an SMB 2 or later share holding a small witness file; may live on a non-domain device), and cloud (an Azure blob in the `msft-cloud-witness` container, reached over HTTPS port 443, with a shared access signature kept in the cluster and refreshed when the storage account key rotates). See the main skill for requirements.

## Resource model

Roles (cluster groups) own resources with AND or OR dependencies (a network name depends on one or more IP addresses; a role depends on its storage). Common types: Physical Disk, IP Address, Network Name, Distributed Network Name, File Server, Scale-Out File Server, Virtual Machine, Generic Service, Generic Application, Cloud Witness, File Share Witness, SQL Server and SQL Server Availability Group. States: Online, Offline, Failed, Online Pending, Offline Pending, Initializing. Health checks are `LooksAlive` (light, frequent) and `IsAlive` (thorough, less frequent); the intervals are resource-type properties, so read them rather than assuming. Failover policy per role: failure threshold and period, preferred owners, possible owners, failback, anti-affinity.

## Networks

Role values: 0 none, 1 cluster only, 3 cluster and client (2 is not supported). A cluster network exists per subnet, built automatically from NIC settings. Route and metric choose which network carries cluster, CSV and SMB traffic; an automatic metric prefers the fastest networks for CSV and live migration. Multi-subnet clusters use OR dependencies on IP address resources and `RegisterAllProvidersIP` and `HostRecordTTL` on the network name so clients find the active address. Cross-subnet heartbeat settings are separate from same-subnet ones. Isolation behaviour: a node that repeatedly loses contact is first marked isolated and then quarantined (see the main skill for the thresholds).

## Cluster Shared Volumes

CSVFS sits on NTFS or ReFS and presents the same namespace on every node (`C:\ClusterStorage\VolumeN`). One node is the coordinator for each volume and performs metadata operations; other nodes read and write data directly when they have storage connectivity (direct I/O). Redirection modes: file system redirection per volume and block redirection per node (see the main skill). A block-level CSV cache in memory can serve repeated reads (cluster property `BlockCacheSize`, MB). A CSV is not the same as a non-CSV clustered disk, which one node owns and mounts at a time (a SQL Server failover cluster instance data drive, for example).

## Cluster-Aware Updating

An orchestrator drains one node, installs updates through a plug-in, restarts it if needed, resumes it and moves on, with run profiles for thresholds, retries and pre/post scripts. Self-updating mode runs the CAU role inside the cluster on a schedule; remote-updating mode runs from an update coordinator that is not a cluster member. In a Storage Spaces Direct cluster CAU waits for storage resynchronisation between nodes.

## Upgrade mechanics

Mixed-OS mode lets nodes of two adjacent OS versions coexist while the cluster functional level stays at the older version. `Update-ClusterFunctionalLevel` (and the storage pool version update) ends mixed mode and is one way. Upgrade one node at a time: drain, evict or in-place upgrade, rejoin, validate; Microsoft documents upgrading one OS version at a time. Plan around LBFO teams (not supported under Hyper-V from 2022), VM configuration versions (older than 8.0 cannot run on a 2022 or later cluster) and guest-cluster VHD Sets.

## Storage Spaces Direct in brief

Local drives across 2 to 16 servers form one pool; the capacity and cache tiers, resiliency (mirror, parity, mirror-accelerated parity), ReFS volumes and SMB Direct networking are covered on Microsoft's overview and hardware requirement pages. It is included in the Datacenter editions. The Health Service reports faults (`Get-HealthFault`).

## Fault domains and cluster sets

Fault domains describe the physical hierarchy (site, rack, chassis, node) so storage and role placement spread across failures; cmdlets `New-ClusterFaultDomain`, `Set-ClusterFaultDomain` and `Get-ClusterFaultDomain` manage them. Cluster sets present several clusters as one pool of VM capacity and a single SMB namespace through a management cluster; tested to 64 nodes in total.
