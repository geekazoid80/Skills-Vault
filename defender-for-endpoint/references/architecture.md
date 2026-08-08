# Microsoft Defender for Endpoint architecture

MDE is Microsoft's cloud-native endpoint EDR, built on the Microsoft security graph and delivered as part of the Defender XDR suite. A kernel-level sensor on each device streams telemetry to a cloud backend that does the detection, correlation, automated investigation, and threat analytics. Understanding the sensor-and-cloud split, how onboarding differs per operating system, and how device groups tie policy to RBAC is what lets you reason about coverage, blocking, and blast radius.

## Platform architecture overview

### Core components

**Endpoint sensor (the Sense service).** On Windows 10 1607+ and Windows Server 2019+ the sensor is built in and runs as the `Sense` service; Server 2012 R2 and 2016 use a separate modern unified agent; macOS, Linux, and mobile use their own packages. The sensor collects kernel-level telemetry through ETW providers and the Windows Filtering Platform (WFP), and communicates to the cloud over TLS.

**Defender Antivirus.** The next-generation antivirus component, distinct from the EDR sensor in the capability model. It runs active by default; on servers, or where a third-party AV is present, it can run in passive mode (it still feeds detections but does not block at the AV layer). EDR behavioural detection continues regardless of the AV mode, but passive mode is a common cause of "why did nothing get blocked".

**The Defender portal.** `security.microsoft.com` is the single pane for MDE alongside Defender for Office 365, Defender for Identity, and Defender for Cloud Apps. All EDR investigation, advanced hunting, and response happens here.

**The Microsoft security graph.** The cloud backend that processes all telemetry, correlates endpoint events with identity (Entra ID), email, and cloud-app signal, and powers AIR and Threat Analytics.

### Sensor communication

Sensors reach a set of Microsoft cloud endpoints over port 443 (TLS 1.2+):

```
- *.endpoint.security.microsoft.com
- *.oms.opinsights.azure.com   (log analytics for some features)
- *.azure-automation.net
- *.blob.core.windows.net       (malware sample submission)

Proxy options:
- System proxy (WinHTTP)
- Sensor-specific proxy: netsh winhttp set proxy proxy.corp.example:8080
- AutoDiscover (WPAD)
```

A sensor that shows onboarded but sends no telemetry is very often a blocked endpoint or an unconfigured proxy; the MDE Client Analyzer (`aka.ms/mdeclientanalyzer`) is the connectivity test.

## Plan 1 versus Plan 2 capability matrix

| Capability | Plan 1 (E3) | Plan 2 (E5) |
|---|---|---|
| Next-generation antivirus (NGAV) | Yes | Yes |
| Attack Surface Reduction (ASR) rules | Yes | Yes |
| Device control (USB, printer) | Yes | Yes |
| Web content filtering | Yes | Yes |
| Network protection | Yes | Yes |
| Endpoint firewall management | Yes | Yes |
| Tamper protection | Yes | Yes |
| EDR behavioural detection | No | Yes |
| Advanced hunting (KQL) | No | Yes |
| Automated Investigation and Response (AIR) | No | Yes |
| Threat Analytics | No | Yes |
| Defender Vulnerability Management (core) | No | Yes |
| Defender Vulnerability Management (add-on) | No | Add-on licence |
| Live response | No | Yes |
| Device timeline | No | Yes |

Pin the tier before advising: EDR, hunting, AIR, Threat Analytics, MDVM, and live response are Plan 2 only.

## Onboarding architecture

### What onboarding does

The onboarding package from the portal (Settings > Endpoints > Onboarding) carries an onboarding script (`.cmd` on Windows, a Python script on Linux), a telemetry baseline, and the organisation identifier that links the sensor to the tenant. On Windows it writes an `OnboardingInfo` blob under `HKLM\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection\` and starts the Sense service (automatic start).

### Windows onboarding methods

**Intune (cloud-managed, preferred).** Endpoint security > Endpoint detection and response, create the onboarding policy, assign to device groups. Sensor data appears in the portal within 24 to 48 hours.

**Group Policy (on-premises AD).** Copy the onboarding package to SYSVOL and reference `WindowsDefenderATPOnboardingScript.cmd` from a GPO startup script; the MDATP settings live under Computer Configuration > Administrative Templates > Windows Components > Microsoft Defender Antivirus.

**Configuration Manager (SCCM).** Import the onboarding package under Endpoint Protection and deploy to a collection.

**Local script (testing and small deployments).** Run `WindowsDefenderATPOnboardingScript.cmd` as administrator, then verify (see below).

### Server onboarding

- **Server 2019+ and 2022**: same methods as Windows clients (Intune, GPO, local script). Requires the server licence (Plan 2, or Defender for Servers via Defender for Cloud).
- **Server 2012 R2 and 2016**: install the modern unified agent (`md4ws.msi /quiet`), then run the onboarding script. Do not use the older MMA-based agent.
- **Server 2008 R2 SP1 (legacy)**: MMA-based only, limited telemetry; upgrade the OS.

### macOS onboarding

Deploy via Intune (preferred) or manually: push the `com.microsoft.wdav` configuration profile, install `wdav.pkg` (`sudo installer -pkg wdav.pkg -target /`), and grant Full Disk Access to `com.microsoft.wdav` and `com.microsoft.wdav.epsext` through an MDM profile. Verify with `mdatp health`.

### Linux onboarding

Add the Microsoft package repository, install `mdatp`, then onboard with the Python onboarding script from the portal. Verify with `mdatp health` and `systemctl status mdatp`.

### Health verification (Windows)

```powershell
# Sense service should be Running, StartType Automatic
Get-Service Sense | Select Name, Status, StartType

# OnboardingState = 1 means onboarded
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status"
Get-ItemProperty $regPath | Select OnboardingState, SenseGuid

# Recent sensor operational events confirm telemetry is flowing
Get-WinEvent -LogName "Microsoft-Windows-SENSE/Operational" -MaxEvents 20 |
    Select TimeCreated, Id
```

### Offboarding

On device replacement, decommission, or migration to another EDR, run the offboarding script from the portal (Settings > Endpoints > Offboarding); the Sense service stops. Onboarding and offboarding use different packages; do not reuse an expired offboarding package.

## Device groups and RBAC

### Device group strategy

A device group determines which policy applies, which AIR automation level runs, and which roles can act on those devices, all at once. A tiered structure typically looks like:

```
- Critical Infrastructure (domain controllers, PKI): automation semi (require approval), maximum protection
- Servers, Application: automation semi (approval for core folders), server-tuned policy
- Workstations, Standard: automation full, full enforcement
- Workstations, Privileged Access (admin workstations): automation semi, maximum plus all ASR rules in block
- Test / Pilot: automation full, pilots new settings before estate rollout
```

### RBAC roles

Roles are configured under Settings > Endpoints > Roles and map to Entra ID security groups. A typical ladder:

| Role | Permissions | Assigned to |
|---|---|---|
| SOC Tier 1 | Alerts read, investigation read | L1 analysts |
| SOC Tier 2 | + live response read, action review | L2 analysts |
| SOC Tier 3 | + live response write, device isolation, full response | L3 / IR |
| SOC Manager | + role management, settings read | SOC leads |
| Vulnerability Management | Vulnerability read, remediation manage | VM team |

RBAC scoping is device-group aware, so a Tier 2 analyst can be granted response on workstations but not on critical servers.

## EDR block mode, network protection, and web content filtering

**EDR in block mode** lets the EDR component block malicious artefacts behaviourally even when Defender Antivirus is passive (for example on a server running a third-party AV). Without it, on a passive-AV device EDR detects but does not block. Turn it on under Settings > Endpoints > Advanced features.

**Network protection** extends web protection to all outbound connections at the OS level (not just the browser), blocking connections to malicious domains and IPs. It is a prerequisite for web content filtering and for the network-indicator side of custom indicators.

**Web content filtering** blocks categories of sites (adult content, high-bandwidth, legal-liability, and so on) across supported browsers; it depends on network protection being on.

## ASR rules architecture

### How ASR rules work

ASR rules operate at the kernel level through Defender Antivirus's attack surface reduction engine. Each rule has three modes: disabled (0), block (1), and audit (2). In audit the rule logs a match without stopping the action; in block it prevents the action before it completes. Events land in the Windows event log (`Microsoft-Windows-Windows Defender/Operational`, event ID 1121 = blocked, 1122 = audited) with the rule GUID, the file path, and the offending process, and in the portal under Reports > Security reports.

### ASR rule reference (GUIDs)

| Rule | GUID | Technique |
|---|---|---|
| Block executable content from email and webmail | BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550 | T1566 phishing |
| Block all Office apps from creating child processes | D4F940AB-401B-4EFC-AADC-AD5F3C50688A | T1566.001 |
| Block Office apps from creating executable content | 3B576869-A4EC-4529-8536-B80A7769E899 | T1566.001 |
| Block Office apps from injecting code into other processes | 75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84 | T1055 injection |
| Block JavaScript or VBScript from launching downloaded executables | D3E037E1-3EB8-44C8-A917-57927947596D | T1059.005/007 |
| Block execution of potentially obfuscated scripts | 5BEB7EFE-FD9A-4556-801D-275E5FFC04CC | T1027 |
| Block Win32 API calls from Office macros | 92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B | T1559.001 |
| Block credential stealing from LSASS | 9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2 | T1003.001 |
| Block process creations from PsExec and WMI commands | D1E49AAC-8F56-4280-B9BA-993A6D77406C | T1047 WMI |
| Block untrusted and unsigned processes that run from USB | B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4 | USB execution |
| Block persistence through WMI event subscription | E6DB77E5-3DF2-4CF1-B95A-636979351E5B | T1546.003 |
| Block Adobe Reader from creating child processes | 7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C | Adobe exploitation |
| Block abuse of exploited vulnerable signed drivers | 56A863A9-875E-4185-98A7-B882C64B5CE5 | T1068 |
| Use advanced protection against ransomware | C1DB55AB-C21A-4637-BB3F-A12568109D35 | T1486 |
| Block Office communication apps from creating child processes | 26190899-1602-49E8-8B27-EB1D0A1CE869 | T1566 Outlook |
| Block executable files unless they meet prevalence, age, or trusted-list criteria | 01443614-CD74-433A-B99E-2ECDC07BFC25 | Low-prevalence executables |

### Exclusions are estate-wide across ASR

ASR exclusions are separate from Defender Antivirus exclusions and are set with `Add-MpPreference -AttackSurfaceReductionOnlyExclusions` or via the Intune ASR policy. The critical property: there is no per-rule granularity. A path excluded from ASR is excluded from every ASR rule at once, so every exclusion widens the whole attack surface. Keep exclusions to specific process or file paths, never folders that an attacker can write to.

## Defender XDR and platform integration

### Defender XDR correlation

MDE shares its device entity, alerts, and incidents with the rest of Defender XDR, so a single incident in `security.microsoft.com` can join endpoint, identity, email, and cloud-app alerts:

```
Defender XDR
  - Defender for Endpoint (this skill): device entity, alerts, incidents
  - Defender for Identity: correlates endpoint activity with AD / Entra ID identity events
  - Defender for Office 365: links an email threat to the endpoint that opened it
  - Defender for Cloud Apps: links cloud-app activity to endpoint behaviour
```

Unified entity pages (user, device, file, IP) and a single advanced-hunting KQL surface span all four. This is why an MDE alert is often only one camera on a wider incident.

### Microsoft Sentinel

MDE streams to Microsoft Sentinel for long-term retention and SOAR. The Defender XDR data connector (preferred) streams all incidents and alert evidence bidirectionally; raw event streaming (Settings > Advanced features > Raw data streaming) sends selected event types to an Event Hub or storage account for custom analysis. Portal advanced-hunting retention is roughly 30 days; Sentinel retention is configurable and usually the answer to a compliance-driven retention requirement. Correlation depth beyond the portal is `siem-soar-investigation`.

### Intune and Entra ID

The Intune connection (Settings > Advanced features > Microsoft Intune connection) exposes the MDE device risk level as an Intune compliance attribute, so a compliance policy can require risk at or under a threshold and a conditional-access policy can block a high-risk endpoint from corporate resources. Entra ID provides the RBAC group mapping, device registration, the conditional-access risk signal, and identity-based hunting. The identity platform itself is `identity-access-management`.
