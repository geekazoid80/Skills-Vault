# Microsoft Defender for Endpoint operations

This reference is the operational playbook: how to tune ASR rules, hunt in KQL over the Device tables, run AIR and the Action Center, operate Defender Vulnerability Management, use Threat Analytics, keep tamper protection and live response sound, manage performance and exclusions, and run a read-only posture audit. All queries assume Plan 2 (advanced hunting is Plan 2 only).

## ASR rule tuning: audit first, then block

### Pre-deployment audit analysis (KQL)

Put every ASR rule in audit mode for two to four weeks, then read the audit hits before enabling block anywhere.

```kql
// Most-triggered ASR rules by volume (find high-false-positive candidates)
DeviceEvents
| where Timestamp > ago(7d)
| where ActionType startswith "Asr"
| summarize EventCount = count(), DeviceCount = dcount(DeviceName)
    by ActionType, FileName, FolderPath, InitiatingProcessFileName
| order by EventCount desc
| take 50

// Unique processes triggering ASR rules (for building exclusions)
DeviceEvents
| where Timestamp > ago(14d)
| where ActionType startswith "Asr"
| summarize HitCount = count() by InitiatingProcessFileName, FolderPath, ActionType
| where HitCount > 5
| order by HitCount desc
```

### Priority order for enabling block mode

**Enable in block immediately (very low false-positive in most estates):** block credential stealing from LSASS, block executable content from email, block Win32 API calls from Office macros.

**Enable after about two weeks of audit:** block Office from creating child processes, block Office from creating executable content, block JavaScript or VBScript launching downloaded executables, use advanced ransomware protection.

**Enable after four or more weeks (complex estates):** block obfuscated scripts (IT automation triggers it), block process creations from PsExec and WMI (SCCM, Tanium, RMM tools), block untrusted unsigned processes from USB (test hardware).

### Common false-positive sources

| Rule | Common false positive | Exclusion strategy |
|---|---|---|
| Block Office child processes | SCCM deployment script run from an Office macro | Exclude the SCCM process path |
| Block obfuscated scripts | Vendor Base64-encoded PowerShell | Exclude the vendor script directory |
| Block PsExec / WMI process creation | SCCM, Tanium, remote-management tools | Exclude the management-tool process path |
| Block LSASS credential theft | An EDR or backup agent legitimately reading LSASS | Exclude that specific process path |
| Block low-prevalence executables | Internal custom apps not in the Microsoft cloud | Add the app to the organisation's software catalogue |

Remember exclusions are estate-wide across all ASR rules; scope them to a specific process or file, never a broad folder.

## Advanced hunting: KQL playbooks over the Device tables

The core tables are `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceRegistryEvents`, `DeviceLogonEvents`, `DeviceImageLoadEvents`, and `DeviceEvents` (miscellaneous, including ASR and firewall), plus `AlertInfo`, `AlertEvidence`, the identity tables, and the `DeviceTvm` vulnerability tables. Retention is roughly 30 days.

**Suspicious PowerShell:**
```kql
DeviceProcessEvents
| where Timestamp > ago(7d)
| where FileName =~ "powershell.exe"
| where ProcessCommandLine has_any ("-enc", "-encodedcommand", "-nop", "bypass", "hidden")
| project Timestamp, DeviceName, AccountName, ProcessCommandLine, InitiatingProcessFileName
| order by Timestamp desc
```

**Office spawning suspicious children:**
```kql
DeviceProcessEvents
| where Timestamp > ago(24h)
| where InitiatingProcessFileName in~ ("winword.exe", "excel.exe", "outlook.exe", "powerpnt.exe")
| where FileName in~ ("cmd.exe", "powershell.exe", "wscript.exe", "cscript.exe",
                      "mshta.exe", "regsvr32.exe", "rundll32.exe", "certutil.exe")
| project Timestamp, DeviceName, AccountName, FileName, ProcessCommandLine, InitiatingProcessFileName
| order by Timestamp desc
```

**LSASS credential dumping:**
```kql
DeviceEvents
| where Timestamp > ago(24h)
| where ActionType == "LsassProcessAccess"
| where InitiatingProcessFileName !in~ ("MsMpEng.exe", "csrss.exe", "werfault.exe", "taskmgr.exe")
| project Timestamp, DeviceName, InitiatingProcessFileName, InitiatingProcessCommandLine
| order by Timestamp desc
```

**Lateral movement over SMB / admin shares:**
```kql
DeviceNetworkEvents
| where Timestamp > ago(24h)
| where RemotePort in (445, 139)
| where ActionType == "ConnectionSuccess"
| summarize TargetCount = dcount(RemoteIP), Targets = make_set(RemoteIP, 20)
    by DeviceName, InitiatingProcessFileName, AccountName
| where TargetCount > 3
| order by TargetCount desc
```

**Ransomware behaviour (mass rename plus shadow-copy deletion):**
```kql
DeviceFileEvents
| where Timestamp > ago(1h)
| where ActionType == "FileRenamed"
| summarize FileCount = count() by DeviceName, InitiatingProcessFileName, bin(Timestamp, 5m)
| where FileCount > 50
| order by FileCount desc

DeviceProcessEvents
| where Timestamp > ago(24h)
| where (FileName =~ "vssadmin.exe" and ProcessCommandLine has "delete")
   or (FileName =~ "wmic.exe" and ProcessCommandLine has "shadowcopy" and ProcessCommandLine has "delete")
   or (FileName =~ "bcdedit.exe" and ProcessCommandLine has "recoveryenabled")
| project Timestamp, DeviceName, AccountName, ProcessCommandLine
```

**Living-off-the-land binary abuse:**
```kql
DeviceProcessEvents
| where Timestamp > ago(24h)
| where FileName in~ ("mshta.exe", "regsvr32.exe", "certutil.exe", "bitsadmin.exe",
                      "regasm.exe", "installutil.exe", "cmstp.exe", "wmic.exe", "msiexec.exe")
| where ProcessCommandLine has_any ("http", "https", "ftp", "\\\\")
| project Timestamp, DeviceName, AccountName, FileName, ProcessCommandLine, InitiatingProcessFileName
| order by Timestamp desc
```

**Persistence (Run keys and scheduled tasks):**
```kql
DeviceRegistryEvents
| where Timestamp > ago(24h)
| where RegistryKey has_any (
    @"Software\Microsoft\Windows\CurrentVersion\Run",
    @"Software\Microsoft\Windows\CurrentVersion\RunOnce")
| where ActionType in ("RegistryValueSet", "RegistryKeyCreated")
| project Timestamp, DeviceName, AccountName, RegistryKey, RegistryValueName, InitiatingProcessFileName
```

### Alert-investigation queries

```kql
// Device timeline around an alert time
let AlertTime = datetime(2026-01-15 14:30:00);
DeviceProcessEvents
| where DeviceName == "WORKSTATION001"
| where Timestamp between ((AlertTime - 30m) .. (AlertTime + 30m))
| project Timestamp, FileName, ProcessCommandLine, InitiatingProcessFileName, AccountName
| order by Timestamp asc

// All activity from a suspicious process id
let SuspiciousPID = 4872;
DeviceNetworkEvents
| where DeviceName == "WORKSTATION001" and InitiatingProcessId == SuspiciousPID
| project Timestamp, RemoteIP, RemotePort, RemoteUrl, SentBytes, ReceivedBytes
```

### Custom detection rules

A proven hunting query becomes a scheduled custom detection (Hunting > Custom detections > Create detection rule). Configure the run frequency (hourly to daily), the alert severity, the MITRE ATT&CK technique mapping, and the response actions (alert, isolate device, quarantine file, run antivirus scan). The query must project `ReportId` and `DeviceId` so the rule can attach evidence.

## Automated Investigation and Response (AIR)

### Automation levels

Set per device group under Settings > Endpoints > Advanced features > Automated Investigation. The levels are: no automated response (investigate only), semi (require approval for core folders), semi (require approval for non-temp folders), and full (remediate automatically).

```
Conservative start (first ~90 days):
- Servers (Critical): semi, require approval for core folders
- Servers (Application): semi, require approval for non-temp folders
- Workstations: semi, require approval for non-temp folders

After tuning (stable estate):
- Workstations: full, remediate automatically
- Servers (Application): semi, require approval for core folders
- Servers (Critical): keep manual review
```

### Action Center review

Process pending actions within about 24 hours of creation:

1. Incidents and alerts > Action Center, filter Status = Pending.
2. For each action, open the investigation graph, check the affected entities (files, processes, users), and review the evidence classification (malicious, suspicious, clean).
3. Approve, approve a selected subset, or reject with a documented reason. Rejected actions escalate to the SOC for manual investigation.
4. Review the History tab for completed automated actions.

AIR remediation actions include file quarantine, process kill, service disable, registry value restore, scheduled-task removal, network isolation (if configured), and antivirus scan.

### Tuning false positives

When AIR misclassifies legitimate software: classify the alert as false positive (Manage alert > Classification), create a suppression rule scoped precisely (process name plus parent plus file path, this device or the whole organisation), and submit the false positive to Microsoft to improve the cloud model. Never suppress by alert title alone, always add process-path context, set an expiry (six months maximum) with a review, and document the justification.

## Defender Vulnerability Management (MDVM)

### Exposure-based prioritisation

MDVM scores risk from CVSS, public-exploit availability, active exploitation in current campaigns (Threat Analytics correlation), asset criticality (device group), and internet exposure. Triage order:

1. Critical CVSS + active exploitation + internet-facing: emergency patch (24 to 48 hours).
2. Critical CVSS + public exploit available: urgent patch (7 days).
3. High CVSS + no public exploit: standard patch (30 days).
4. Medium or low CVSS: scheduled patching cycle.

### Remediation and exceptions

Drive remediation from Vulnerability management > Recommendations (sorted by exposure score); a recommendation raises a remediation request that can integrate with ServiceNow or Jira, or export to CSV. Track progress under Remediation; a recommendation clears after the next scan (24 to 48 hours) once patched. For anything that cannot be fixed now, request an exception with a type (planned remediation with a due date, accepted risk, or third-party responsibility), a justification, and a review date. Exceptions are visible under Exception management; a silent unpatched critical is the finding, an exception with a date is acceptable.

```kql
// Devices with critical or high CVEs that have a public exploit
DeviceTvmSoftwareVulnerabilities
| where VulnerabilitySeverityLevel in ("Critical", "High")
| join kind=inner (
    DeviceTvmSoftwareVulnerabilitiesKB
    | where IsExploitAvailable == "1" and CvssScore >= 7.0
) on CveId
| summarize UnpatchedDevices = dcount(DeviceId), DeviceList = make_set(DeviceName, 20)
    by CveId, SoftwareName
| order by UnpatchedDevices desc

// Software inventory: find every device running a given product
DeviceTvmSoftwareInventory
| where SoftwareName =~ "log4j"
| project DeviceName, SoftwareName, SoftwareVersion, OSPlatform
```

## Threat Analytics

Threat Analytics provides curated intelligence reports on active threats (Plan 2). Each report carries the actor overview, impacted assets in your estate, related incidents, analyst insights, mitigations, and detection-coverage notes. Operationally, run a weekly review: filter to reports with an "impacted" status, note the ATT&CK techniques the actor uses, cross-reference with your detection coverage and ASR state, check whether the report's CVEs are in your MDVM queue, and create custom detections for technique gaps. Reports link to MDVM so you can see which of your devices carry the exploited CVEs.

## Tamper protection

Tamper protection stops local changes to Defender's security settings (disabling real-time protection, altering exclusions, stopping the service) even by a local administrator, so an attacker who lands on a host cannot quietly turn the sensor off. Enforce it centrally via Intune or the portal rather than per-device, and treat a device with tamper protection off as an audit finding.

## Live response

Live response opens an interactive shell to an onboarded device (Plan 2) and is gated by RBAC: a read-only role gets `cd`, `dir`, `ls`, `ps`, `connections`, `trace`, and `getfile`; the advanced role adds `putfile`, `run` (execute an uploaded script), and `remediate` (quarantine, kill, undo). Pre-upload collection and triage scripts to the file library (Settings > Endpoints > Automation uploads) so they are available in any session. In a read-only audit, live response is out of scope: it can isolate and remediate.

## Performance impact and exclusion hygiene

High CPU is usually a missing exclusion on an I/O-heavy workload. Prefer process exclusions over path exclusions, and never exclude a whole drive or `C:\Windows\`.

```powershell
# Review current exclusions
Get-MpPreference | Select ExclusionPath, ExclusionExtension, ExclusionProcess

# Build servers: exclude the compiler and toolchain, not the whole disk
Add-MpPreference -ExclusionProcess "cl.exe"
Add-MpPreference -ExclusionPath "C:\BuildOutput\"

# Database servers: the data-file extensions and the data directory
Add-MpPreference -ExclusionExtension "mdf", "ldf", "ndf"

# VDI: stagger scans so every VM does not scan at once
Set-MpPreference -RandomizeScheduleTaskTimes $true
Set-MpPreference -ScanOnlyIfIdleEnabled $true
```

Document every exclusion with a business justification and review it; the portal surfaces an "attack surface" risk for broad exclusions. Schedule full scans off-hours (`Set-MpPreference -ScanScheduleTime`).

## Read-only audit lens

An MDE posture audit is read-only: it queries the portal, advanced hunting, and the Graph, and it never isolates a device, kills a process, or runs a live-response remediation.

### Threshold table

| Signal | Healthy | Investigate | Finding |
|---|---|---|---|
| Onboarded sensors reporting | All report within 24h | A few stale over 7d | A group silent, or a whole OS family not reporting |
| Defender Antivirus mode | Active | Passive with EDR block on (documented) | Passive with EDR block off |
| ASR high-value rules (LSASS, email exec, macro Win32) | Block | Audit with a dated plan to block | Disabled or indefinitely in audit |
| Tamper protection | Enforced estate-wide | Enforced on most groups | Off |
| AIR automation | Tuned per group with a daily Action Center review | Semi everywhere, reviewed | No-automation, Action Center unreviewed |
| Exclusions | Process-scoped, justified, reviewed | A few broad but documented | Whole-drive or `C:\Windows\` exclusions |
| Critical exploited CVEs | None outstanding, or all under a dated exception | A handful in remediation within SLA | Exposed, exploited, unremediated, no exception |

### Remediation decision trees

- **Sensor onboarded but not reporting** -> check connectivity (proxy, the cloud endpoints, run the MDE Client Analyzer) -> if connectivity is fine, check the Sense service and onboarding-state value -> re-onboard if the org identifier is missing.
- **ASR rule triggering false positives in audit** -> identify the process-plus-parent-plus-path from the audit KQL -> add a surgical exclusion (remember it is estate-wide) -> then promote the rule to block; do not leave it in audit as the answer.
- **AIR pending actions piling up** -> if the estate is stable, raise the automation level on low-risk workstation groups -> keep critical servers on manual review -> set a daily Action Center SLA.
- **Critical exploited CVE outstanding** -> if internet-facing, emergency patch (24 to 48 hours) -> if it genuinely cannot be patched now, file a dated exception with a type, never leave it silent.
