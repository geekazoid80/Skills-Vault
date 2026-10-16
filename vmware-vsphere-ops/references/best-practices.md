# VMware vSphere best practices reference

Sizing, scheduling, availability, snapshots, hardening, backup and storage practice. Figures marked as rules of thumb are field guidance, not VMware limits. Operating rules and the safety table are in `SKILL.md`. Syntax has not been run on live systems.

---

## Sizing and resources

- **Right-size vCPUs.** Every extra vCPU raises scheduling overhead and co-stop for SMP VMs. Start small (often 2) and scale on evidence. Watch %RDY (rule of thumb: sustained above about 5 per vCPU means contention).
- **Memory:** size to the guest's working set. Keep ballooning available (Tools installed). Avoid reservations unless required (for example FT).
- **NUMA:** fit VMs within a NUMA node where latency matters (vCPUs no more than the cores per node, memory within node). Watch N%L in `esxtop` (rule of thumb: below about 80 means remote memory). vNUMA is exposed automatically to wide VMs.
- **Resource pools:** use shares for relative priority (CPU shares per vCPU are Low 500, Normal 1000, High 2000), reservations sparingly, and at most two levels of nesting. Do not mix VMs and resource pools as siblings at the same level, because a VM there competes with the whole pool on its share count.
- **Memory states:** high, soft, hard, low. Swap activity means hard or low.

---

## DRS

- Fully automated for production clusters, with the migration threshold set to the workload (less aggressive for latency-sensitive clusters).
- VM-VM anti-affinity for redundant pairs; VM-Host rules for licensing or hardware constraints; build groups first, then rules.
- Review DRS faults regularly. Enable predictive DRS only if its data source is in place.

---

## HA

- Choose the failures to tolerate and size admission control for it; do not disable it to fit more VMs.
- Select at least two heartbeat datastores where the design has shared storage; vSAN clusters have none.
- Set restart priority by tier (infrastructure and identity services first), and define dependencies (database before application).
- Configure VMCP responses for APD and PDL; enable Proactive HA where hardware plugins exist.
- Test by simulating a host failure in a maintenance window, at least yearly.

---

## Snapshots

Snapshots cause most preventable storage trouble in vSphere.

- Automate deletion in the backup tool; alert on age (rule of thumb: older than 24 to 72 hours).
- Keep chains short (rule of thumb: three or fewer).
- Never use snapshots as backups; they depend on the base disk.
- Consolidate orphaned deltas when vCenter reports "disks consolidation needed", in a low-activity window.
- Monitor datastore space: thin disks plus active snapshots grow fast.

```powershell
Get-VM | Get-Snapshot | Where-Object { $_.Created -lt (Get-Date).AddDays(-7) } |
    Select-Object VM, Name, Created, SizeGB | Sort-Object Created
```

---

## Templates and content libraries

Use a content library to distribute templates and ISOs across vCenters, version template names, convert a template to a VM for patching and back, and use customisation specifications (Sysprep for Windows, cloud-init or the Linux customisation engine for Linux) for post-clone configuration.

---

## ESXi hardening

- **Lockdown mode:** normal on all production hosts with exception users for break-glass.
- **Services:** SSH and the ESXi Shell off, enabled briefly with an auto-disable timeout (`UserVars.ESXiShellTimeOut`, `UserVars.ESXiShellInteractiveTimeOut`). Disable CIM and SNMP if unused. Keep the ESXi firewall on and manage rulesets with `esxcli network firewall ruleset`.
- **Syslog:** forward off-host immediately:

```bash
esxcli system syslog config set --loghost='tcp://syslog.example.com:514'
esxcli system syslog reload
esxcli network firewall ruleset set --ruleset-id=syslog --enabled=true
```

- **NTP:** configure on every host (certificates, vSAN, HA and log correlation depend on it):

```bash
esxcli system ntp set -s ntp1.example.com -s ntp2.example.com -e true   # the ntp namespace needs ESXi 7.0 U3 or later
```

- **Certificates:** VMCA-signed by default; subordinate the VMCA to the corporate CA where policy requires; regenerate after hostname or address changes.
- **Accounts:** change default passwords at deployment, use directory-backed named accounts, set lockout and complexity, and review local accounts quarterly.
- Baseline and benchmark checking belongs to `compliance-benchmark-audit`; patch cadence to `vulnerability-management`.

---

## Backup

- Backup proxy VMs per cluster for hot-add; SAN transport where the proxy sees the LUNs.
- Enable CBT on backed-up VMs and test it periodically; reset it if the product reports inconsistency.
- Daily incremental, periodic full or synthetic full, and a long-term copy off-site; stagger start times.
- Restore tests monthly, including a full VM and a file-level restore, with RTO and RPO recorded per workload tier. Use isolated restore validation where the product offers it.
- Large VMs need extended consolidation time; schedule jobs for low I/O periods.

---

## Storage

- Keep thin-provisioned datastores below roughly 80 per cent used and alert before that; size datastores for a manageable VM count; use datastore clusters with Storage DRS where it fits.
- Multipathing: use the path selection policy and settings the array vendor documents. Round Robin suits many active-active arrays; the vendor's per-path IOPS setting overrides a generic value.
- VMFS 6 aligns partitions and reclaims space automatically; watch for SCSI reservation conflicts on arrays without ATS.
- NFS: dedicated NICs and VLAN, jumbo frames only if the whole path supports them, NFS 4.1 where supported.

---

## Monitoring cadence (rules of thumb)

| Check | Frequency | Tool | Indicator |
|---|---|---|---|
| CPU ready per VM | Daily | `esxtop`, vCenter | Sustained above about 5 per vCPU |
| Memory swap | Daily | `esxtop`, vCenter | Any SWCUR above 0 |
| Datastore latency | Daily | `esxtop`, vCenter | Sustained device latency above about 20 ms on flash or 50 ms on disk |
| Snapshot age | Daily | PowerCLI | Older than 72 hours |
| Datastore free space | Weekly | vCenter alarm | Below about 20 per cent free |
| HA admission control and DRS faults | Weekly | vCenter | Warnings or faults present |
| vSAN health | Weekly | vSAN Health | Any red or yellow |
| Hardware health | Weekly | vCenter | Any warning |
| NTP synchronisation | Monthly | `esxcli system ntp get` (Time Synchronized) | Not synchronised |
