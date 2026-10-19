---
name: windows-server-ops
description: "Use for day-to-day Windows Server 2016, 2019, 2022 and 2025 administration and troubleshooting: roles and features, Server Core versus Desktop Experience, PowerShell remoting and CIM, event log and performance counter triage, SMB and networking, storage (NTFS, ReFS, Storage Spaces), security settings (Credential Guard, VBS, SMBv1, TLS, LAPS, audit policy), patching and Hotpatch, Windows Server Backup and VSS, editions and licensing, and version differences. Triggers include \"Windows Server\", \"Server Core\", \"sconfig\", \"WinRM\", \"PowerShell remoting\", \"Get-WindowsFeature\", \"event ID 41\", \"event ID 4625\", \"Hotpatch\", \"SMB over QUIC\", \"Storage Spaces\", \"ReFS\", \"Windows Server 2025\", \"2022 end of mainstream support\", \"WSUS\", \"Windows Admin Center\", \"server won't boot BSOD stop code\". NOT for Active Directory, Group Policy design or DNS (ad-ds, ad-cs, ad-fs, windows-dns-ops), NOT for choosing an operating system (operating-system-selection), NOT for Linux hosts (linux-host-ops), NOT for patch tooling products (action1-patch-management)."
license: MIT
metadata:
  version: 1.0.0
---

# Windows Server operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: windows-server-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Windows Server is managed mainly through PowerShell, CIM, Server Manager, Windows Admin Center and Group Policy or its cloud equivalents. Behaviour and defaults shift by release (2016, 2019, 2022, 2025), by edition (Standard, Datacenter, Datacenter: Azure Edition) and by install type (Server Core or Desktop Experience), so pin all three before advising.

**Core principle:** read first, change second, and state the blast radius (reboot, service restart, users affected) before any change. Version, edition and lifecycle facts change; check them against Microsoft's documentation on the day and say which source you used.

> **Caveat on provenance.** Commands, thresholds and scripts were reshaped from a community upstream, corrected against Microsoft Learn pages fetched on 2026-10-19, and reviewed independently. Syntax has not been run on live systems. Counter thresholds are rules of thumb, not Microsoft limits.

## Step 0: establish what you are on

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion') | Select-Object EditionID, InstallationType, UBR
```

Builds: 14393 is 2016, 17763 is 2019, 20348 is 2022, 26100 is 2025. `InstallationType` is `Server Core` or `Server`. Then read `references/version-notes.md` for support dates and version differences. The scripts in `scripts/` do this for you.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive, disruptive or security-sensitive, get explicit approval |
|---|---|---|
| `Get-*` cmdlets, `Get-WinEvent`, `Get-Counter`, `Get-CimInstance`, `Get-HotFix`, `Get-SmbServerConfiguration`, `Get-WindowsFeature`, `auditpol /get`, `vssadmin list`, `w32tm /query`, `winrm enumerate`, `dism /online /get-*` | `Install-WindowsFeature`, `Uninstall-WindowsFeature` (without `-Remove`, and `FS-SMB1`), `Set-Service`, `Set-SmbServerConfiguration`, `Set-NetFirewallProfile`, `New-NetFirewallRule`, `Enable-PSRemoting`, `Set-ItemProperty` on HKLM, `wevtutil sl`, `auditpol /set`, `wbadmin start backup`, `vssadmin create shadow`, `logman create` and `start` | `Uninstall-WindowsFeature -Remove`, `Restart-Computer`, `Stop-Service` on a production service, `Disable-NetAdapter`, Schannel or LSA registry changes, `wevtutil cl`, `wbadmin start recovery`, `ntdsutil` authoritative restore, `DISM /Set-Edition`, `dism /StartComponentCleanup /ResetBase`, raising a domain or forest functional level, `Format-Volume`, `Clear-Disk` |

On a production server, state the change, the reboot or restart it needs, and the rollback before running a middle-column command, and wait for approval before a right-column one.

## Roles, features and Server Core

Install only the roles the server needs; every role adds attack surface and patches. Audit with `Get-WindowsFeature | Where-Object Installed` against a known baseline.

| Factor | Server Core | Desktop Experience |
|---|---|---|
| Disk | About 4 GB smaller (Microsoft hardware requirements) | Full |
| Local management | PowerShell, `sconfig`, Windows Admin Center, RSAT | Local GUI consoles as well |
| Typical fit | AD DS, DNS, DHCP, file, Hyper-V, IIS | Remote Desktop Session Host and GUI-dependent applications |

Choose Server Core unless a role or application needs the GUI, and manage it remotely. Hardware floor (Microsoft, 2026-10-19): 1.4 GHz 64-bit CPU with SLAT; 2 GB RAM on 2025 (1 GB Core on earlier releases); 32 GB disk as an absolute minimum; 2025 also needs SSE4.2 and POPCNT.

## Remote administration

Prefer CIM (`Get-CimInstance`) to WMI cmdlets. Use `Enter-PSSession` for interactive sessions and `Invoke-Command` for batches; use JEA endpoints to grant constrained rights and DSC or equivalent for repeatable configuration. Authenticate with `-Credential (Get-Credential)` or Kerberos; never put a password in a script, profile or command line (see `secrets-hygiene`). Workgroup targets need TrustedHosts or an HTTPS WinRM listener (TCP 5985 HTTP, 5986 HTTPS); scope TrustedHosts narrowly.

## Triage

**Events** (`references/diagnostics.md` has the full table): 41 and 6008 unexpected restart, 1074 planned restart, 7034 service crash, 7045 new service installed, 1000 application crash, 4625 failed logon, 4740 lockout, 104 System log cleared and 1102 Security log cleared (treat both as tampering until explained). Read the Security log only elevated.

**Counters** (rules of thumb): processor time sustained above about 70 per cent warrants a look and 90 per cent is critical; processor queue length above about twice the logical processor count; available memory below 10 per cent of RAM; pages per second above about 500; disk latency above about 20 ms warning and 50 ms critical; network output queue above 2. Take a baseline in the first week of service so later numbers mean something.

**Stop codes:** keep a kernel or automatic memory dump configured, then analyse with WinDbg `!analyze -v`. Driver Verifier forces crashes by design; use it only on a test machine.

## Security

- **Authentication:** Kerberos by default in a domain; NTLM is the fallback. Audit NTLM use through the `Microsoft-Windows-NTLM/Operational` log and the Restrict NTLM audit policies before restricting it. `auditpol` has no NTLM subcategory, so do not look for one.
- **Credential Guard and VBS:** Microsoft states Credential Guard is enabled by default from Windows Server 2025 on devices that meet the requirements; its Credential Guard documentation limits default enablement to domain-joined systems that are not domain controllers and meet the licence, hardware and software requirements. Earlier releases need it configured. VBS needs hardware virtualisation and UEFI Secure Boot, with a TPM recommended; test HVCI against drivers in audit mode first.
- **SMB:** SMBv1 off on every server (on Server, remove the `FS-SMB1` feature as well as setting the server option). SMB signing and encryption settings are version- and policy-dependent; read them with `Get-SmbServerConfiguration`. SMB over QUIC is available on Standard and Datacenter in 2025 (Azure Edition only in 2022).
- **TLS:** Microsoft is deprecating TLS 1.0 and 1.1 starting with Windows 11 Insider builds; do not assume a server release disables them. Read the actual Schannel state (`security-audit.ps1` prints it), and disable protocols only after testing legacy clients, SQL and LDAPS; Schannel registry changes need a reboot.
- **Service accounts:** gMSA, and delegated managed service accounts (dMSA) on 2025 with a domain functional level that supports them; avoid LocalSystem for application services.
- **Local admin passwords:** Windows LAPS is built in on current releases; 2025 adds automatic managed local account management.
- **LDAP:** Microsoft states new AD deployments on 2025 require LDAP signing (sealing) by default after a SASL bind. Audit existing clients before raising enforcement on older domains.
- **Audit policy and logs:** enable logon, lockout, privilege use, account management and policy change auditing; size logs to your baseline (the CIS benchmark examples are Security 196608 KB, System and Application 32768 KB).
- **Exposure:** Windows Firewall on for all profiles with inbound default block; RDP with network level authentication; restrict management ports to a management network; disable the Print Spooler on servers without the Print role.

Baselines (CIS, Microsoft security baselines) belong to `compliance-benchmark-audit`; copy exact values from the current benchmark, not from here.

## Storage and networking

- **NTFS** for boot and general volumes. **ReFS** for integrity checksums and Hyper-V or Storage Spaces Direct volumes; it cannot be the boot volume. Storage Spaces Direct is Datacenter only.
- **Allocation unit size:** 64 KB is commonly advised for SQL Server data and Hyper-V storage; check the application vendor's guidance.
- **NIC teaming:** LBFO for non-Hyper-V servers; Switch Embedded Teaming (SET) for Hyper-V hosts, especially with RDMA. Do not use LBFO with RDMA NICs.
- **DNS client settings:** two or more DNS servers per NIC; resolution troubleshooting goes to `windows-dns-ops`.

## Patching, Hotpatch, backup

- **Cadence:** Patch Tuesday cumulative updates, optional preview updates in the following weeks, out-of-band fixes for emergencies. Roll through rings (lab, pilot, wave 1, wave 2) with a documented rollback (`wusa /uninstall /kb:<number>` or DISM).
- **Hotpatch** (Microsoft Learn, 2026-10-19): supported on Datacenter: Azure Edition in Azure and Azure Local, and on Azure Arc-connected Windows Server 2025 Standard and Datacenter once enabled in the Azure Arc portal, which the Hotpatch page describes as available at no extra cost. A quarterly baseline needs a restart; the two months after it carry hotpatches without one. Non-security, .NET and driver updates still need restarts, and there is no automatic rollback (uninstall the update and install the last good baseline, which restarts). Read the Hotpatch page and calendar for current terms and supported SKUs.
- **Backup:** system state backups for domain controllers; VSS shadow storage sized for the churn; 3-2-1 copies with one off-site; encrypt backups; test a restore monthly and a full bare-metal recovery at least quarterly. Restore procedures for AD belong to `ad-ds`.

## Pitfalls

1. Desktop Experience installed by habit.
2. SMBv1 left on, or turned off by setting the option but leaving the feature installed.
3. Assuming TLS 1.0 and 1.1 are off.
4. Event logs left at default sizes, losing evidence.
5. No performance baseline.
6. Services running as LocalSystem or as a human account.
7. Driver and firmware updates ignored (a leading cause of stop errors).
8. Patches not piloted, and no tested rollback.
9. Credential Guard or LDAP signing changes made without auditing legacy clients.
10. Raising a functional level (one-way) before every domain controller is upgraded.

## Red flags

- A password, PIN or key written into a command or script.
- A state-changing command presented as a check.
- A lifecycle date, price or feature-by-version claim with no source and date.
- "NTLMv1 is blocked by default" or similar absolutes quoted without checking the release notes.
- Backups described without a restore test.

## References and scripts

- `references/architecture.md`: NT internals, boot, registry, services, memory, storage and network stacks, security architecture, WMI/CIM.
- `references/best-practices.md`: hardening workflow, firewall, logging, Group Policy structure, patching, Server Core, Windows Admin Center, backup, storage and networking practice.
- `references/diagnostics.md`: event logs and IDs, counters, workflows, packet capture, WinRM, stop-error analysis.
- `references/editions-and-licensing.md`: edition roster, feature gates, licensing and upgrade paths.
- `references/version-notes.md`: lifecycle dates (dated and sourced) and what changed in 2016, 2019, 2022 and 2025.
- `scripts/server-health.ps1`, `performance-baseline.ps1`, `event-log-summary.ps1`, `storage-health.ps1`, `network-diagnostics.ps1`, `security-audit.ps1`, `update-and-backup-status.ps1`, `version-checks.ps1`: read-only checks. Exit codes: 0 none, 1 warnings, 2 critical or the check itself failed; a query that fails or returns nothing is a warning, never a pass.

The scripts only read state and are compatible with Windows PowerShell 5.1 and PowerShell 7. They are parse-checked, and each was run against mocked cmdlets in an empty-result world and a throwing world (none exits 0) plus selected healthy and unhealthy worlds, but none has been run on a live Windows system and the property names are unconfirmed against a real session. Run them on a non-critical server first.

## Boundaries

- AD DS, GPO design, certificate services, federation and DNS: `ad-ds`, `ad-cs`, `ad-fs`, `windows-dns-ops`.
- Windows desktops and Intune: `windows-client-ops`.
- Hyper-V, failover clustering and WSL: `hyper-v-ops`, `windows-failover-clustering-ops`, `wsl-ops`.
- OS selection and lifecycle planning: `operating-system-selection`.
- Defender, EDR and patch tooling: `defender-for-endpoint`, `endpoint-detection-response`, `action1-patch-management`.
- Benchmarks and baselines: `compliance-benchmark-audit`; CVE handling: `vulnerability-management`.
- PowerShell module problems: `powershell-module-compat`.
- Credentials: `secrets-hygiene`.

## Bottom line

Pin version, edition and install type; read before changing; keep Server Core and a small role set; treat security defaults as version-specific facts to check, not assumptions; baseline performance early; pilot patches; and prove restores.
