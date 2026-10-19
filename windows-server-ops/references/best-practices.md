# Windows Server best practices reference

Hardening, policy structure, patching, backup, storage and network practice. Every command below that sets something is **state-changing**: test on one server, state the reboot or restart it needs, and keep a rollback. Exact baseline values come from the current CIS benchmark or the Microsoft security baseline for the release, not from this file. Syntax has not been run on live systems.

---

## Post-installation workflow

1. Pin version, edition and install type; update to the current cumulative update.
2. Install only needed roles; prefer Server Core.
3. Apply a baseline (Microsoft Security Compliance Toolkit baseline or CIS) through Group Policy, Intune or local policy tooling, in audit or pilot mode first.
4. Configure logging (audit policy, event log sizes), time sync, firewall, remote management, backups and monitoring.
5. Record the result as the server's baseline.

### Audit policy

`auditpol /get /category:*` reads it. Setting subcategories is state-changing:

```powershell
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /failure:enable
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable
auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable
```

Prefer delivering audit policy through Group Policy advanced audit configuration so it survives and is consistent. Use the exact subcategory names shown by `auditpol /list /subcategory:*`.

### Event log sizes

CIS-style examples: Security 196608 KB, System and Application 32768 KB. `wevtutil sl` takes bytes:

```powershell
wevtutil sl Security /ms:201326592   # 196608 KB
wevtutil sl System /ms:33554432      # 32768 KB
wevtutil sl Application /ms:33554432
```

### Services to review (disable only after confirming nothing depends on them)

Print Spooler on servers without the Print role (PrintNightmare class of issues), Remote Registry unless remote management needs it, the legacy Computer Browser service, and Xbox services on Desktop Experience servers. Record each decision.

```powershell
Set-Service -Name Spooler -StartupType Disabled   # state-changing
Stop-Service -Name Spooler                        # state-changing
```

### Windows Firewall

```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -LogBlocked True -LogMaxSizeKilobytes 32767
New-NetFirewallRule -DisplayName "RDP - management network" -Direction Inbound -Protocol TCP -LocalPort 3389 `
    -RemoteAddress "<management-subnet>" -Action Allow -Profile Domain
```

Scope remote administration ports (RDP 3389, WinRM 5985 and 5986, SMB 445) to management networks. A change to the default inbound action can cut your own session; keep out-of-band access.

### SMBv1 and RDP

```powershell
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Uninstall-WindowsFeature -Name FS-SMB1                 # removes the feature; needs a restart
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1   # NLA
```

### TLS and ciphers

Read the current state first (`scripts/security-audit.ps1`). Microsoft is deprecating TLS 1.0 and 1.1 in Windows starting with Windows 11 Insider builds, and a server release default is not something to assume. Disabling protocols or ciphers is a Schannel registry change that needs a restart and can break legacy clients, SQL Server connections and LDAPS, so enable Schannel event logging, test, and roll out by group. Graphical helpers such as IIS Crypto exist, but record what they change.

---

## Group Policy structure

Prefer a few well-structured GPOs per tier over many overlapping ones: a base member-server baseline GPO, role-specific GPOs for file, web and database servers, and a separate domain-controller baseline that does not edit the Default Domain Controllers Policy. Name GPOs with a prefix that shows purpose. Use Enforced and Block Inheritance sparingly. Use item-level targeting for preferences and WMI filters only when needed (they cost CPU). GPO design, links and recovery belong to `ad-ds`.

Security baselines: Microsoft Security Compliance Toolkit baselines applied with LGPO.exe, compared with Policy Analyzer; CIS benchmarks through your compliance tooling.

---

## Patching

- **Cadence:** Patch Tuesday cumulative update, optional preview in the following weeks, out-of-band updates for emergencies (days, not weeks, for exploited vulnerabilities).
- **Rings:** lab at once, pilot a week later, production waves after that, with a documented rollback.
- **WSUS:** on SQL Server rather than the Windows Internal Database for large estates; decline superseded updates regularly. Microsoft publishes Windows Server update guidance and the WSUS deprecation status; check it before building new WSUS dependence.
- **Hotpatch:** quarterly baseline plus two hotpatch months; see `SKILL.md` for the supported platforms and the Microsoft page for current terms.
- **Tooling:** product-level patch management is `action1-patch-management`; Update Manager and Arc are Azure features.

---

## Server Core and remote management

`sconfig` handles hostname, domain join, network, updates and remoting on Server Core. Enable remoting with `Enable-PSRemoting` (state-changing), manage with RSAT or Windows Admin Center.

```powershell
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"   # on the management machine; check names with Get-WindowsCapability
```

**Windows Admin Center:** run it as a gateway on a dedicated, domain-joined host for shared use; replace the self-signed certificate with one from your CA; port 443 conflicts with IIS on the same host; install with the vendor MSI and verify the `ServerManagementGateway` service.

---

## Monitoring and logging

- **Windows Event Forwarding:** `wecutil qc` on the collector, a Group Policy subscription manager on sources.
- **Azure Monitor Agent:** for Azure Arc-connected servers; follow the current Azure documentation for installation.
- Collect the Security events that matter (4624, 4625, 4648, 4688, 4720, 4740) and System service and restart events; keep them off-host.

---

## Backup and recovery

- Install Windows Server Backup only if it is your tool: `Install-WindowsFeature Windows-Server-Backup`. Examples: `wbadmin start backup -backuptarget:\\backup\share -include:C: -quiet` (state-changing).
- **Domain controllers:** daily system state backup (`wbadmin start systemstatebackup`). Authoritative restore is a destructive, procedure-bound action; follow `ad-ds`.
- **VSS:** `vssadmin list shadowstorage` reads it; size shadow storage for churn.
- 3-2-1 rule, encrypted backups, a monthly restore test and a quarterly bare-metal recovery test.

---

## Storage

- NTFS or ReFS per `SKILL.md`; align allocation unit size to the application guidance (64 KB commonly advised for SQL Server and Hyper-V storage). GPT disks align partitions automatically.
- Watch free space (alert at 20 per cent free, treat 10 as critical) and physical disk health.

```powershell
Format-Volume -DriveLetter D -FileSystem NTFS -AllocationUnitSize 65536 -NewFileSystemLabel Data   # destructive to existing data
```

## Networking

- LBFO for non-Hyper-V teaming, SET for Hyper-V and RDMA.
- SMB encryption per share for sensitive data (`Set-SmbShare -EncryptData $true`); signing as required by policy and the release default.
- Two or more DNS servers per interface; conditional forwarders for cross-forest resolution.
