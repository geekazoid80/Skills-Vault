# Failover clustering best-practices reference

Rules of thumb are planning guidance, not Microsoft limits; Microsoft statements are marked.

## Design

- **Validate before you build and after you change.** Run `Test-Cluster` on new nodes, including Storage tests, before they host anything. On a running cluster use the non-disruptive categories only (`-Include "Inventory","Network","System Configuration"`); schedule Storage tests for a window.
- **Keep nodes identical:** CPU generation (or enable processor compatibility for VMs), NICs, drivers, firmware, BIOS settings and Windows build. Microsoft requires identical NICs, drivers and firmware for adapters used in a SET team across nodes.
- **Domain:** all nodes in the same domain. Workgroup and multi-domain clusters exist (since 2016, and Windows Server 2025 adds Hyper-V workgroup clusters with live migration); treat them as a deliberate design with their own authentication requirements.
- **Size for N+1:** after losing a node the remainder must carry all roles. Test by draining a node and watching memory, CPU and storage latency.
- **Edition:** Datacenter for Storage Spaces Direct and unrestricted Storage Replica; Standard supports clustering itself and a limited Storage Replica (single volume up to 2 TB on 2019 or later).
- **Limits (Microsoft Learn):** 64 nodes per cluster with Hyper-V hosts, 8,000 running VMs per cluster; Storage Spaces Direct 2 to 16 servers.

## Quorum and witness

- Configure a witness on every cluster; let dynamic quorum and dynamic witness manage votes.
- Cloud witness for sites with reliable internet access (no extra server, survives a site loss); file share witness elsewhere; disk witness only with shared disks. In multi-site clusters put the witness in a third location.
- Keep the witness out of the failure domain it protects: not on a cluster node, not behind the same switch or power feed as half the cluster.
- Record the vote arithmetic in the runbook (nodes, witness, margin) and check it before maintenance. The `quorum-and-witness.ps1` script prints the margin.
- Do not edit node weights unless you have a documented reason (for example, a disaster recovery node that should not vote).

## Networks

- At least two networks carrying cluster traffic; dedicate or reserve bandwidth for storage and live migration with SMB bandwidth limits and QoS.
- A heartbeat or backend network needs no default gateway and no DNS registration.
- SET (virtual switch) teaming for Hyper-V nodes; RDMA only after the physical network is configured for it.
- Leave heartbeat settings at defaults unless measured latency or a documented cause requires a change. Raising thresholds slows detection of a real failure.
- Multi-subnet clusters: OR dependencies, `RegisterAllProvidersIP` and a sensible `HostRecordTTL` for clients, and tested failover from each site.

## Storage

- Shared storage must support SCSI-3 persistent reservations; use MPIO with a documented policy on every node before adding disks.
- NTFS CSVs on SAN storage; ReFS CSVs on Storage Spaces Direct (Microsoft Learn).
- Keep CSVs above 20 per cent free (rule of thumb) and alert on redirected I/O.
- Back up through the CSV-aware path of the backup product and test restores; backup snapshots can place a CSV into file system redirection while they run.
- Storage Spaces Direct: use the validated hardware list, identical drive layout per node, and the Health Service for faults. Specify fault domains before enabling it where possible.

## Maintenance procedure (per node)

1. Confirm the vote margin and that roles fit on the remaining nodes.
2. `Suspend-ClusterNode -Name <node> -Drain`; wait until `DrainStatus` completes and roles have moved.
3. Patch, update firmware, restart.
4. `Resume-ClusterNode -Name <node> -Failback Immediate` (or `NoFailback` and move roles on purpose).
5. Check `Get-ClusterNode`, roles, CSV state (`Get-ClusterSharedVolumeState`) and storage health (Storage Spaces Direct repair jobs) before the next node.

## Cluster-Aware Updating

- Self-updating mode on a schedule for steady-state clusters; remote-updating mode for controlled one-off runs.
- Set `MaxFailedNodes` low (1 for most production clusters) and require all nodes connected so a run stops instead of draining a degraded cluster.
- Add pre and post scripts for application checks; read `Get-CauReport` after every run.
- Pilot updates on a non-production cluster; keep the source (WSUS or Windows Update for Business) rings aligned with CAU schedules.

## Patching and upgrades

- Treat cluster OS upgrades as projects: inventory VM configuration versions, LBFO teams, third-party filter drivers and backup agents; take backups; upgrade one node at a time; finish with `Update-ClusterFunctionalLevel` only when every node, role and VM has been validated, because that step is one way. Upgrade one OS version at a time (Microsoft Learn).
- Hotpatch and in-place feature upgrades are outside this skill (`windows-server-ops`).

## Stretch clusters

- Witness in a third site; site-aware fault domains; storage replication between sites (synchronous replication needs low round-trip latency, an average of 5 ms or less is the figure Microsoft's Storage Replica material uses); tune cross-subnet thresholds from measurement; test site failover with the business owners; decide in advance which site wins a tie.

## Monitoring targets

| Check | Frequency | Alert on (rule of thumb) |
|---|---|---|
| Node state | 1 minute | Any node not Up (Down or Paused outside a maintenance window) |
| Role state | 1 minute | Any role not Online outside a maintenance window |
| Quorum margin | 5 minutes | Margin of zero, or witness not Online |
| CSV state | 5 minutes | Any volume in redirected I/O outside maintenance mode |
| CSV free space | 15 minutes | Below 20 per cent warning, below 10 per cent critical |
| Events 1135, 1177, 1146, 1069, 5120, 5142 | Continuous | Any occurrence |
| CAU run | Daily | Failed or incomplete |
| Storage Spaces Direct health | 15 minutes | Any health fault |

## Anti-affinity and placement

Use anti-affinity class names to keep redundant pairs on different nodes and preferred owners for steady-state placement. Anti-affinity is soft: a role will run beside its pair to stay online, so design with enough nodes to honour it during a single-node failure and review placement after every failover.
