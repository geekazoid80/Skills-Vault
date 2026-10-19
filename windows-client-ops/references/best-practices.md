# Windows client best practices reference

Hardening, management, updates, BitLocker and application practice. Anything that sets something is **state-changing**: pilot it, state the restart it needs and keep a rollback. Exact baseline values come from the current CIS benchmark or Microsoft security baseline for the release. Syntax has not been run on live systems.

---

## Hardening

- Apply a baseline (Microsoft Security Compliance Toolkit baseline or CIS) through Intune security baselines or Group Policy. Review in audit or pilot first; compare with Policy Analyzer; apply local GPO files with LGPO.exe where needed.
- Typical benchmark themes: do not show the last user name, require Ctrl+Alt+Del, UAC prompting on the secure desktop, firewall on with inbound default block, AutoPlay disabled, Bluetooth discovery restrictions. Take exact settings from the benchmark.
- Remove SMBv1 (`Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force`, then `Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart` on client SKUs).

### Attack surface reduction rules

Roll out in this order: **audit** (action 2), review events in the Defender operational log, add exclusions for proven false positives, then **block** (action 1) in rings. Action codes: 0 disabled, 1 block, 2 audit, 6 warn.

```powershell
Get-MpPreference | Select-Object AttackSurfaceReductionRules_Ids, AttackSurfaceReductionRules_Actions   # read
# State-changing; start with audit (2):
Add-MpPreference -AttackSurfaceReductionRules_Ids 'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' -AttackSurfaceReductionRules_Actions 2
```

Rule identifiers used often (verify names against the current ASR rules reference): `BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550` executable content from email, `D4F940AB-401B-4EFC-AADC-AD5F3C50688A` Office applications creating child processes, `3B576869-A4EC-4529-8536-B80A7769E899` Office creating executable content, `75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84` Office injecting into other processes, `D3E037E1-3EB8-44C8-A917-57927947596D` JavaScript or VBScript launching downloaded executables, `5BEB7EFE-FD9A-4556-801D-275E5FFC04CC` potentially obfuscated scripts, `92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B` Win32 API calls from Office macros, `01443614-CD74-433A-B99E-2ECDC07BFC25` executables that do not meet prevalence, age or trusted-list criteria. The USB rule is a different identifier; do not reuse this one for it.

### Exploit protection and controlled folder access

`Get-ProcessMitigation -System` reads exploit protection; `Set-ProcessMitigation` and exported XML policies change it. `Set-MpPreference -EnableControlledFolderAccess AuditMode` is the audit-first setting; `Add-MpPreference -ControlledFolderAccessAllowedApplications <path>` allows a trusted application.

---

## Intune and MDM

| Enrolment | Scenario |
|---|---|
| Windows Autopilot | New devices, out-of-box provisioning with the Enrolment Status Page |
| Provisioning package | Kiosk or shared devices |
| Automatic enrolment from Group Policy | Existing AD-joined devices moving to co-management |
| User-initiated | Personal devices (workplace registration) |
| Entra ID join at setup | Cloud-first organisations |

Compliance policies set the minimum bar (BitLocker, Secure Boot, minimum OS version, Defender real-time protection, firewall) and feed Conditional Access. Configuration profiles: Settings catalog, security baselines, endpoint security, administrative templates, custom OMA-URI for settings with no UI. Co-management workloads: compliance, resource access, endpoint protection, device configuration, Windows updates, Microsoft 365 apps, client apps.

Group Policy and Intune comparison:

| Capability | Group Policy | Intune |
|---|---|---|
| Scope | Domain-joined | Entra ID-joined or hybrid |
| Delivery | SYSVOL replication | HTTPS from the service |
| Offline enforcement | Yes, from cache | Needs connectivity |
| Reporting | `gpresult`, RSOP | Intune reports |

---

## Updates

Windows Update for Business: quality updates and feature updates deferred by ring, driver and Microsoft product updates optional. Update rings map to registry policy under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`. A pause lasts up to a limited period (see the Intune documentation for the current limit).

Delivery Optimisation download modes (policy values): 0 HTTP only, 1 LAN, 2 group, 3 Internet, 99 simple, 100 bypass (check the current documentation for the full list). Read with `Get-DeliveryOptimizationStatus`; `Get-DeliveryOptimizationPerfSnapThisMonth` for monthly statistics.

Feature update targeting: the target release version policies keep a device on a version; set them only with a plan to move before the version's end of support.

---

## BitLocker deployment

Policy path: Computer Configuration, Administrative Templates, Windows Components, BitLocker Drive Encryption (startup authentication, encryption method, recovery key backup, PIN length). Prefer XTS-AES 256 where policy allows. Escrow recovery keys to Entra ID or Active Directory and verify the escrow before enabling protection.

```powershell
Get-BitLockerVolume                                      # read
Add-BitLockerKeyProtector -MountPoint C: -RecoveryPasswordProtector   # state-changing
# Back up the recovery password protector to Active Directory (state-changing); take the ID from the protector list
Backup-BitLockerKeyProtector -MountPoint C: -KeyProtectorId '<id from Get-BitLockerVolume>'
# For Entra ID escrow on managed devices
BackupToAAD-BitLockerKeyProtector -MountPoint C: -KeyProtectorId '<id from Get-BitLockerVolume>'
```

Enabling protection with a PIN (`Enable-BitLocker -TpmAndPinProtector -Pin $securePin`) is state-changing and long-lived; collect the PIN with `Read-Host -AsSecureString`, never as a literal. Device encryption (automatic BitLocker on supported hardware) escrows to the user's Microsoft account unless the device is joined to Entra ID or a domain, so enterprise devices should use managed BitLocker.

---

## Application management

```powershell
winget search <name>
winget install --id <Publisher.Package> --silent --accept-package-agreements --accept-source-agreements   # state-changing
winget upgrade --all --silent                                                                              # state-changing
winget export -o apps.json ; winget import -i apps.json                                                  # import is state-changing
Add-AppxPackage -Path .\App.msix                                                                          # state-changing
```

AppLocker is the older allow-listing mechanism; App Control for Business (WDAC) is Microsoft's strategic direction and enforces at kernel level through code integrity. Compatibility: the Program Compatibility Assistant and compatibility modes for legacy applications, shims through the Compatibility Administrator for enterprise use.
