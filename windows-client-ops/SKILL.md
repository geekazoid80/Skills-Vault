---
name: windows-client-ops
description: "Use for day-to-day Windows 10 and Windows 11 desktop administration and troubleshooting: Intune and MDM enrolment (Autopilot), update rings and Windows Update for Business, Delivery Optimisation, BitLocker deployment and recovery keys, Windows Hello, Defender and attack surface reduction settings, SFC and DISM repair, driver and GPU problems, Reliability Monitor, storage cleanup analysis, winget and MSIX, edition and LTSC questions, Windows 10 end of support and ESU, and Windows 11 readiness. Triggers include \"Windows 11\", \"Windows 10 end of support\", \"ESU\", \"Autopilot\", \"Intune compliance\", \"Windows Update for Business\", \"BitLocker recovery key\", \"TPM 2.0 requirement\", \"SFC DISM\", \"driver problem code 43\", \"event 4101\", \"winget\", \"LTSC\", \"Windows 11 24H2 end of support\". NOT for Windows Server (windows-server-ops), NOT for Defender for Endpoint tenant configuration or EDR (defender-for-endpoint, endpoint-detection-response), NOT for patch tooling products (action1-patch-management), NOT for macOS (macos-ops, macos-mdm-ops), NOT for choosing an operating system (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Windows client operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: windows-client-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Windows desktops are managed through Group Policy, Intune or another MDM, or both during migration, and serviced with annual feature updates and monthly quality updates. Behaviour depends on the Windows version (10 or 11 and the feature update), the edition (Home, Pro, Enterprise, Education, LTSC) and the management plane, so pin all three first.

**Core principle:** read first, change second; check lifecycle, edition and policy facts against Microsoft's current pages and say which page and date. Support dates for Windows 10 and 11 have repeatedly differed between editions, and the community upstream these notes replace had several wrong.

> **Caveat on provenance.** Commands, thresholds and scripts were reshaped from a community upstream, corrected against Microsoft Learn pages fetched on 2026-10-19, and reviewed independently. Syntax has not been run on live systems.

## Step 0: establish what you are on

```powershell
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cv | Select-Object ProductName, DisplayVersion, CurrentBuild, UBR, EditionID
Get-ComputerInfo | Select-Object WindowsProductName, OsVersion, OsBuildNumber
dsregcmd /status | Select-String 'AzureAdJoined|DomainJoined|MdmUrl'   # join and management state
```

A build below 22000 is Windows 10. Then check the Microsoft Lifecycle page for the edition (`references/version-notes.md` has the dated table).

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive, disruptive or security-sensitive, get explicit approval |
|---|---|---|
| `Get-*` cmdlets, `Get-BitLockerVolume`, `Get-MpComputerStatus`, `Get-MpPreference`, `Get-PnpDevice`, `winget list`, `dsregcmd /status`, `manage-bde -status`, `DISM /Online /Cleanup-Image /CheckHealth`, `/ScanHealth` and `/AnalyzeComponentStore`, `sfc /verifyonly`, `powercfg /a` | `winget install` and `upgrade`, `Set-MpPreference`, `Set-ItemProperty` on HKLM, `Add-BitLockerKeyProtector`, `Backup-BitLockerKeyProtector`, `sfc /scannow`, `DISM /RestoreHealth`, `Add-AppxPackage`, `pnputil /add-driver`, `Set-ProcessMitigation` | `Enable-BitLocker` and `Disable-BitLocker`, `Clear-Tpm`, `Remove-AppxPackage -AllUsers`, `DISM /StartComponentCleanup /ResetBase` (removes rollback), `pnputil /delete-driver`, driver Verifier, `Reset-PhysicalDisk`, wiping or resetting a device, `Delete-DeliveryOptimizationCache`, BIOS or TPM resets |

On a user's device, say what will restart, what will be unrecoverable and what the rollback is before running a middle-column command, and wait for approval before a right-column one.

## Management plane

**Intune** enrols devices by Windows Autopilot (out-of-box provisioning), bulk provisioning packages, automatic enrolment from Group Policy (hybrid), user-initiated enrolment, or Entra ID join at setup. Core objects: compliance policies (minimum security bar, enforced through Conditional Access), configuration profiles (Settings catalog, security baselines, endpoint security, administrative templates, custom OMA-URI), update rings and app deployment. Co-management with Configuration Manager moves workloads one at a time.

| Group Policy | Intune |
|---|---|
| Domain-joined, ADMX from SYSVOL, applies offline from cache | Entra ID-joined or hybrid, CSP over HTTPS, needs connectivity |
| Reporting with `gpresult` and RSOP | Intune device and compliance reports |

Avoid configuring the same setting in both planes. Defender and Intune tenant design belongs to `defender-for-endpoint`.

## Updates

Windows Update for Business gives policy-based updates without WSUS. Typical deployment: ring 0 pilot with no deferral, ring 1 early after about a week, ring 2 broad after about two weeks, with a pause available when a bad update ships. Deferring quality updates for long periods lengthens exposure. Delivery Optimisation reduces WAN use through peer download; watch its bandwidth on shared segments. Pin a feature version with the target release policy only deliberately, and remember that a pinned version still reaches end of support on its date.

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue   # read the policy that is applied
```

## BitLocker

Methods: TPM only (device encryption, no pre-boot secret), TPM plus PIN, TPM plus network unlock, password for removable drives. Enterprise practice is managed BitLocker with recovery keys escrowed to Entra ID or Active Directory **before** encryption completes and before any firmware, TPM or hardware change.

```powershell
Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionMethod, KeyProtector
manage-bde -status C:
```

Enabling BitLocker with a PIN is state-changing. **Never put a PIN or recovery password in a script**; supply the PIN with `Read-Host -AsSecureString` or let policy and Intune set the method, and read the recovery key from the escrow, not from the device log. A TPM reset, firmware update or board replacement invalidates the TPM protector, so confirm the key is escrowed first. Device encryption on a personal Microsoft account escrows to that account, outside corporate control.

## Defender and attack surface reduction

Microsoft Defender Antivirus provides real-time and cloud-delivered protection and tamper protection. Attack surface reduction (ASR) rules block specific behaviours (Office child processes, obfuscated scripts, executable content from mail). Deploy with Intune or `Set-MpPreference`, starting in **audit** mode (action 2) and moving to **block** (1) once the audit events are understood. Controlled folder access protects folders from ransomware-like writes and needs an allow-list. SmartScreen, Exploit Protection and App Control for Business (WDAC; AppLocker is the older option) complete the set; policy design and EDR are in `defender-for-endpoint` and `endpoint-detection-response`.

## Diagnostics

1. **Reliability Monitor** (`perfmon /rel`) correlates a complaint with the first crash or install.
2. **System file repair** order: `DISM /Online /Cleanup-Image /RestoreHealth` first, then `sfc /scannow`, then restart. `/CheckHealth` and `/ScanHealth` are read-only.
3. **Drivers:** `Get-PnpDevice | Where-Object Status -ne 'OK'` for problem codes (28 no driver, 43 device reported a problem, 10 cannot start); System event 4101 for display driver timeouts; `pnputil /enum-drivers` for the store.
4. **Performance:** processor time sustained above about 90 per cent, available memory below about 10 per cent, disk latency above about 20 ms on SSD-class storage, as rules of thumb.
5. **Storage:** the component store looks inflated in Explorer because of hard links; `DISM /AnalyzeComponentStore` reports actual size. Cleanup with `/ResetBase` removes the ability to uninstall updates.

## Windows 10 end of support and Windows 11

- **Windows 10** reached end of support on 14 October 2025 for all editions of 22H2 listed by Microsoft (the Enterprise and Education lifecycle page shows 22H2 ending that date, not 2027 as the upstream said). A paid Extended Security Updates programme exists: per Microsoft's ESU page, commercial enrolment is by year for up to three years, pricing is published per device and doubles each year, and Windows 10 virtual machines in Windows 365, Azure Virtual Desktop and Azure get ESU at no extra cost. LTSC and IoT LTSC releases have their own dates. Read the current ESU page and the Lifecycle page before advising.
- **Windows 11 requirements** (Microsoft, 2026-10-19): 1 GHz or faster with two or more cores on a compatible 64-bit processor; 4 GB RAM; 64 GB storage; UEFI with Secure Boot; TPM 2.0; DirectX 12 with a WDDM 2.0 driver; 720p display of 9 inches or more. Virtual machines need generation 2, a virtual TPM and Secure Boot. Direct upgrade needs Windows 10 version 2004 or later with the September 2021 security update or later. The approved processor list is separate; check it with Microsoft's tools.
- **Lifecycle table** for Windows 11 versions is in `references/version-notes.md`; versions retire on different dates for Home and Pro versus Enterprise and Education.

## Pitfalls

1. Windows 10 devices left unmanaged after end of support with no ESU and no migration plan.
2. Upgrading to Windows 11 without checking TPM 2.0 and Secure Boot first.
3. BitLocker enabled without escrowing recovery keys, then a firmware update.
4. Long quality-update deferrals.
5. SMBv1 left enabled.
6. HVCI enabled before auditing unsigned drivers.
7. ASR rules set to block without an audit period.
8. Windows 11 version pinned past its end of support date.
9. Group Policy and Intune both setting the same thing.
10. LTSC chosen for general knowledge workers.

## Red flags

- A PIN, recovery key or password in a script or ticket.
- An end-of-support date quoted without the edition and the Microsoft page.
- A cleanup command with `/ResetBase` run without telling the user it removes rollback.
- A "block" ASR deployment with no audit evidence.

## References and scripts

- `references/architecture.md`: application models, display, power, management planes, update plumbing.
- `references/best-practices.md`: hardening, Intune, updates, BitLocker, applications, Group Policy versus Intune.
- `references/diagnostics.md`: system file repair, Reliability Monitor, drivers, startup and performance, storage, power.
- `references/editions-and-licensing.md`: editions, stable feature differences, hardware requirements and upgrade paths.
- `references/version-notes.md`: dated Windows 10 and 11 lifecycle tables and version notes.
- `scripts/client-health.ps1`, `update-compliance.ps1`, `security-posture.ps1`, `network-diagnostics.ps1`, `driver-health.ps1`, `app-inventory.ps1`, `disk-space-analysis.ps1`, `windows11-readiness.ps1`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a query that fails or returns nothing), 2 critical findings. A check that could not run is therefore never a clean pass.

The scripts only read state (the disk script only analyses; nothing is cleaned) and work on Windows PowerShell 5.1 and PowerShell 7. They are parse-checked and exercised against mocked cmdlets, including an empty-result world and a throwing world where none exits 0, but none has been run on a live Windows system. Run them on a test device first.

## Boundaries

- Windows Server: `windows-server-ops`. AD, GPO design and DNS: `ad-ds`, `windows-dns-ops`.
- Defender tenant policy and EDR: `defender-for-endpoint`, `endpoint-detection-response`; patch tooling: `action1-patch-management`.
- Benchmarks and baselines: `compliance-benchmark-audit`.
- WSL: `wsl-ops`. macOS: `macos-ops` and `macos-mdm-ops`.
- OS choice and lifecycle planning: `operating-system-selection`.
- PowerShell module issues: `powershell-module-compat`. Credentials: `secrets-hygiene`.

## Bottom line

Pin version, edition and management plane; check lifecycle pages for the edition on the day; escrow BitLocker keys before anything touches the TPM; start ASR in audit mode; repair with DISM then SFC; and treat every script as unproven until run on a test device.
