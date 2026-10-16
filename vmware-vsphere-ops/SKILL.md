---
name: vmware-vsphere-ops
description: "Use for day-to-day VMware vSphere operations and troubleshooting: ESXi hosts, vCenter, virtual machine lifecycle and snapshots, vMotion and EVC, vSphere HA and DRS, vSAN, vSwitch and distributed switch networking, VMFS, NFS and iSCSI storage, VADP backup, ESXi hardening, and automation with PowerCLI, esxcli and govc. Triggers include \"vSphere\", \"ESXi\", \"vCenter\", \"VCSA\", \"PowerCLI\", \"esxcli\", \"esxtop\", \"govc\", \"vMotion fails\", \"CPU ready\", \"datastore latency\", \"snapshot consolidation needed\", \"HA did not restart VMs\", \"vSAN health\", \"purple screen\", \"vm-support\", \"host not responding\". NOT for choosing between hypervisors or migrating off VMware (virtualization-platform-selection), NOT for NSX overlay design (evpn-vxlan-fabric covers overlay concepts), NOT for Proxmox VE (proxmox-ops), NOT for KVM with libvirt (kvm-libvirt-ops), NOT for generic backup product configuration."
license: MIT
metadata:
  version: 1.0.0
---

# VMware vSphere operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: vmware-vsphere-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

vSphere is ESXi hosts (the VMkernel hypervisor) managed by vCenter Server (the appliance, VCSA), with clustering services (HA, DRS, vMotion), software-defined storage (vSAN) and a distributed virtual switch layered on top. Automation comes from PowerCLI (PowerShell; Broadcom renamed it VCF PowerCLI, module `VCF.PowerCLI`, as a continuation of `VMware.PowerCLI`), `esxcli` (on the host), `govc` (Go CLI) and the REST and SOAP APIs.

**Core principle:** version and licence first, read-only checks second, changes last. vSphere product names, editions, licensing and support dates have changed repeatedly under Broadcom, so verify each against Broadcom's current documentation rather than relying on a table, including this one.

> **Caveat on provenance.** Commands and thresholds were reshaped from a community upstream, corrected against what could be verified, and reviewed independently. Syntax has not been run on live systems. Rules of thumb marked as such are field guidance, not VMware limits. Check anything version- or licence-specific against the vendor documentation for the installed release.

## Step 0: establish what you are on

```powershell
Connect-VIServer -Server <vcenter-fqdn>          # prompts for credentials; do not put a password in the command
$global:DefaultVIServer | Select-Object Name, Version, Build
Get-VMHost | Select-Object Name, Version, Build, ConnectionState, PowerState
Get-Cluster | Select-Object Name, HAEnabled, DrsEnabled, DrsAutomationLevel, EVCMode
```

```bash
esxcli system version get          # on an ESXi host
```

Record the vCenter and ESXi build numbers before advising. vCenter must be the same version as or newer than the hosts it manages. Windows-based vCenter no longer exists (VCSA only, since vSphere 7).

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive or disruptive, get explicit approval |
|---|---|---|
| `Get-*` cmdlets, `esxcli ... list` and `get`, `esxtop`, `vim-cmd vmsvc/getallvms`, `govc ls`, `govc vm.info`, `govc find`, `vm-support` bundle creation (it writes a file and adds load) | `Move-VM`, `New-Snapshot`, `Remove-Snapshot`, `Set-VM`, `Set-Cluster`, `Apply-DrsRecommendation`, `esxcli storage nmp device set`, `esxcli system syslog config set`, `esxcli system ntp set`, `govc vm.power`, `govc snapshot.create` | `esxcli vm process kill`, `esxcli system maintenanceMode set`, host reboot or shutdown, `Remove-VM -DeletePermanently`, `govc vm.destroy`, `Stop-VM`, `Restart-VM`, `Remove-Datastore`, `Set-VMHost -State`, restarting management agents (`/etc/init.d/hostd restart`, `/sbin/services.sh restart`), lowering an EVC mode, deleting a snapshot on a busy VM, changing HA or admission control on a production cluster |

On a production cluster, state the change and its rollback before running a middle-column command, and wait for approval before a right-column one.

## Virtual machines

A VM is a `.vmx` configuration file, one or more `.vmdk` disks and optional snapshot files. Provisioning: **thin** (allocated on demand; watch datastore space), **thick lazy zeroed**, **thick eager zeroed** (pre-zeroed; some features such as Fault Tolerance have disk requirements, so check them for your version). VMware Tools or `open-vm-tools` supplies PVSCSI and VMXNET3 drivers, heartbeat, quiescing and time sync; prefer `open-vm-tools` on Linux guests.

```powershell
Get-VM | Select-Object Name, NumCpu, MemoryGB, PowerState, VMHost
Get-VM | Get-Snapshot | Select-Object VM, Name, Created, SizeGB | Sort-Object Created
```

**Snapshots are not backups.** Each snapshot adds a delta disk; chains slow I/O and consolidation is I/O heavy. Rules of thumb: keep one to three snapshots, delete within a day or three, alert on age, never rely on them for recovery, and treat a "virtual machine disks consolidation needed" warning as a ticket, not noise.

**Order of upgrades:** VMware Tools first, then VM hardware version. A VM hardware version cannot be lowered casually and may stop the VM running on older hosts, so do not raise it until every host in the cluster can run it.

## vMotion, Storage vMotion, EVC

vMotion copies memory while the VM runs and finishes with a short switchover. Requirements: a VMkernel port enabled for vMotion on both hosts (10 GbE or faster is the recommended network for production), compatible CPUs (or EVC), matching network and storage visibility, and spare capacity. Storage vMotion moves disks between datastores without downtime. Shared-nothing migration combines both when no common storage exists.

EVC (Enhanced vMotion Compatibility) presents a common CPU baseline at the cluster level so hosts of different generations from the same vendor can exchange VMs. Choose the baseline of the oldest host, enable it before the cluster is full of VMs, and do not mix Intel and AMD hosts in one migration domain. Changing the baseline can require VMs to be powered off or moved; check the documentation before lowering it.

```powershell
Move-VM -VM web01 -Destination (Get-VMHost esxi02)                         # state change
Move-VM -VM web01 -Datastore (Get-Datastore DS-02)                         # Storage vMotion; state change
```

## vSphere HA

HA restarts VMs on surviving hosts after a host failure. Hosts exchange network heartbeats every second; datastore heartbeating lets the primary host tell a failed host from an isolated or partitioned one (it is isolation handling, not fencing). The failure-detection and isolation-response timings are version and advanced-option dependent, so read them from the documentation for your release rather than quoting a number. In vSAN clusters there are typically no heartbeat datastores.

- **Admission control** reserves capacity for failover. Size it for the failures you intend to tolerate (for a four-host cluster surviving one host failure, one host's share, which is 25 per cent when the hosts are equal).
- **VM restart priority and dependencies** decide order (infrastructure VMs first, databases before applications).
- **VM Monitoring** restarts guests whose Tools heartbeat stops; **VMCP** responds to storage APD and PDL events; **Proactive HA** can evacuate degrading hardware where the vendor plugin exists.
- Test HA in a maintenance window by simulating a host failure, and review the FDM log (`/var/log/fdm.log`).

## DRS

DRS balances CPU and memory with vMotion. Modes: fully automated (the usual production setting), partially automated, manual. Use VM-VM anti-affinity rules for redundant pairs, VM-Host rules for licence or hardware constraints, and groups rather than individual objects. Review DRS faults regularly; stuck rules cause imbalance. `Apply-DrsRecommendation` changes state.

## Networking

- **Standard switch (vSS):** per host. **Distributed switch (vDS):** managed by vCenter and pushed to all hosts; adds Network I/O Control, LACP, port mirroring, health checks and rollback and recovery.
- **VMkernel ports** carry management, vMotion, vSAN, FT logging, NFS and iSCSI, and replication. Put each on its own VLAN; MTU 9000 only where end-to-end support is proven.
- **VLAN tagging:** VST (port group tags), EST (physical switch tags), VGT (trunk to the guest, VLAN 4095).
- **NSX** adds GENEVE overlays and a distributed firewall; its design is outside this skill.

## Storage

| Type | Notes |
|---|---|
| VMFS 6 | Cluster filesystem for block storage; automatic space reclamation (UNMAP), ATS locking |
| NFS 3 and 4.1 | 4.1 adds Kerberos and session trunking |
| iSCSI | Software initiator; port binding for multipathing |
| Fibre Channel | Lowest latency, enterprise SAN |
| vVols | Per-VM array objects through a VASA provider; check current support for your version |
| vSAN | Hyper-converged; storage policies decide protection |

Multipathing: pick the path selection policy the array vendor recommends (Round Robin for many active-active arrays; the vendor's IOPS-per-path setting beats a generic number). Keep thin-provisioned datastores below roughly 80 per cent used and alert before that. Storage DRS can balance space and latency across a datastore cluster.

## vSAN

vSAN pools local devices across hosts. A standard cluster needs at least three hosts. **OSA** uses disk groups with cache and capacity devices; **ESA** (vSAN 8 onwards) uses a single flat pool of NVMe devices with its own hardware compatibility list. The choice is made per cluster and moving between them means migrating data. Storage policies (failures to tolerate, RAID-1, RAID-5 or RAID-6, stripe width) decide protection; never use force provisioning as a habit. Compression and deduplication behaviour differs by architecture and release (ESA compression is built in; ESA global deduplication arrived later and with prerequisites), so check the release notes. Stretched clusters need a witness at a third site and inter-site latency inside the documented limits.

## Backup (VADP)

Backup products use the vStorage APIs for Data Protection: snapshot, read the base disk and changed blocks (CBT), delete the snapshot. Transport modes are hot-add (proxy VM), NBD and SAN. Quiescing needs VMware Tools. Monitor for orphaned snapshots after failed jobs, reset CBT if the product reports inconsistency, and test a full restore monthly.

## Security and hardening

- **Lockdown mode:** normal on every production host, with named exception users for break-glass; strict where physical console access is controlled.
- Keep SSH and the ESXi Shell off, enabling them temporarily with an auto-disable timeout.
- Forward syslog off-host immediately after deployment, configure NTP, and keep certificates valid (VMCA, or a subordinate of the corporate CA); regenerate after hostname or address changes.
- Named administrator accounts through Active Directory or a vCenter identity source, strong lockout policy, and a quarterly review of local accounts.
- Keep ESXi, firmware and drivers at versions on the VMware compatibility guide.
- **Credentials:** never write a password into a script, shell profile or command line. For `govc`, take `GOVC_URL`, `GOVC_USERNAME` and `GOVC_PASSWORD` from a secret store or an interactive prompt at run time, and do not set `GOVC_INSECURE`; install the vCenter CA certificate instead. See `secrets-hygiene`.

## Performance triage (rules of thumb, not VMware limits)

`esxtop` in the ESXi Shell: CPU panel `c` (%RDY sustained above about 5 per vCPU, %CSTP above about 3, %MLMTD above 0), memory `m` (SWCUR above 0, MCTLSZ above 0, N%L below about 80), storage `d` (DAVG, KAVG, GAVG latencies), network `n` (drops, %USED). Right-size vCPUs before adding hosts, fit VMs to a NUMA node, and read the numbers in `references/diagnostics.md`.

## Common pitfalls

1. Snapshots left on VMs, or used as backups.
2. Over-allocated vCPUs (co-stop and ready time).
3. No EVC on a cluster with mixed CPU generations.
4. Hardware version raised before every host can run it.
5. Thick provisioning everywhere, or thin provisioning with no space alert.
6. Syslog not forwarded; NTP drift breaking certificates, vSAN or HA.
7. vSAN health warnings ignored; ESA and OSA hardware assumptions mixed.
8. Admission control disabled "to fit one more VM".
9. Automation with credentials in scripts, or `GOVC_INSECURE` left on.
10. Using vSwitches where a distributed switch is licensed and managed centrally would remove drift.
11. Restoring never tested.

## Red flags

- A password or token in a command, script, profile or note.
- A state-changing cmdlet in a "read-only" check.
- A version, edition or support-date claim with no source or date.
- HA described without admission control, heartbeat datastores or an isolation response.
- Hardening advice that disables the ESXi firewall.

## References and scripts

- `references/architecture.md`: ESXi internals, VM files, vMotion, HA, FT, DRS, networking, storage, vSAN, VADP.
- `references/best-practices.md`: sizing, NUMA, DRS and HA settings, snapshots, templates, hardening, backup, storage.
- `references/diagnostics.md`: esxtop, vm-support, PSOD, vMotion and HA failures, storage latency, logs, counters.
- `references/version-notes.md`: vSphere 8 and 9 and licensing notes with sources and caveats. Read before advising on versions or licences.
- `scripts/esxcli-health.sh`: read-only ESXi host health through `esxcli`, for the ESXi Shell (POSIX `sh`).
- `scripts/powercli-inventory.ps1`: read-only VM, host and datastore inventory (optional CSV output).
- `scripts/powercli-health.ps1`: read-only cluster health (HA, DRS, hosts, Tools, snapshots, datastores, alarms).

The scripts only read state. They parse and lint where tools were available (`shellcheck` for the shell script, the PowerShell parser for the two `.ps1` files; PSScriptAnalyzer was not available), and their threshold and failure logic was exercised against mocked command output, but none has been run against a live vSphere environment, and the PowerCLI property names are unconfirmed against a real session; run them on a non-critical environment first. Thresholds: datastores warn at 80 per cent and are critical at 90; host CPU and memory warn at 90 or more; snapshots warn after three days by default (the 72-hour rule of thumb). Exit codes are 0 healthy, 1 warnings, 2 critical or the check itself failed.

## Boundaries

- Choosing a platform, leaving VMware, V2V conversion: `virtualization-platform-selection`.
- Overlay networking and NSX concepts: `evpn-vxlan-fabric`.
- Other hypervisors: `proxmox-ops`, `kvm-libvirt-ops`.
- Automation as code: `terraform-iac-ops`, `ansible-automation-platform`.
- Monitoring products and dashboards: `monitoring-dashboard-audit`, `prtg-network-monitoring`.
- Credentials: `secrets-hygiene`.

## Bottom line

Know the version, edition and builds before advising; read before changing; keep snapshots short-lived; make HA, EVC and admission control deliberate settings; hold credentials out of scripts; and check licensing and support dates against Broadcom's current documents rather than any table.
