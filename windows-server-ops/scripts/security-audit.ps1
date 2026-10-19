<#
.SYNOPSIS
    Security posture summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports Defender, firewall, SMBv1, LAN Manager level, Schannel protocol settings, RDP NLA, VBS, local administrators, Print Spooler, audit policy and LAPS state. It reports; it does not harden.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\security-audit.ps1
#>
[CmdletBinding()]
param(

)

$ErrorActionPreference = 'Continue'
$script:ExitCode = 2   # any path that does not reach a verdict exits 2
$script:Findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([ValidateSet('Critical', 'Warning')] [string]$Level, [string]$Message)
    $script:Findings.Add([pscustomobject]@{ Level = $Level; Message = $Message })
}
function Write-Section {
    param([string]$Title)
    Write-Output ''
    Write-Output $Title
    Write-Output ('-' * 72)
}
# Run one check. A check that throws is reported as a warning, never as a clean pass.
function Invoke-Check {
    param([string]$Name, [scriptblock]$Body)
    $ErrorActionPreference = 'Stop'
    try { & $Body }
    catch { Add-Finding 'Warning' ("{0} could not be checked: {1}" -f $Name, $_.Exception.Message) }
}
# An empty answer from a query that should always answer is a finding, not a pass.
function Assert-Data {
    param($Value, [string]$What)
    if ($null -eq $Value -or @($Value).Count -eq 0) {
        Add-Finding 'Warning' "$What returned no data"
        return $false
    }
    return $true
}
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Complete-Report {
    Write-Section 'SUMMARY'
    $crit = @($script:Findings | Where-Object { $_.Level -eq 'Critical' })
    $warn = @($script:Findings | Where-Object { $_.Level -eq 'Warning' })
    if ($crit.Count -eq 0 -and $warn.Count -eq 0) {
        Write-Output 'No warnings or critical findings.'
        $script:ExitCode = 0
        return
    }
    foreach ($f in $crit) { Write-Output "  CRITICAL: $($f.Message)" }
    foreach ($f in $warn) { Write-Output "  WARNING:  $($f.Message)" }
    $script:ExitCode = if ($crit.Count -gt 0) { 2 } else { 1 }
}

Write-Output 'Windows Server security posture (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; several checks below will be incomplete' }
}

Write-Section '1. DEFENDER AND FIREWALL'
Invoke-Check 'Defender' {
    $m = Get-MpComputerStatus
    if (-not (Assert-Data $m 'Get-MpComputerStatus')) { return }
    Write-Output ("  real-time protection={0}; antivirus signature age={1} day(s); tamper protection={2}" -f $m.RealTimeProtectionEnabled, $m.AntivirusSignatureAge, $m.IsTamperProtected)
    if (-not $m.RealTimeProtectionEnabled) { Add-Finding 'Warning' 'Defender real-time protection is off (expected only if another product is in use)' }
    if ($m.AntivirusSignatureAge -gt 3) { Add-Finding 'Warning' ("Defender signatures are {0} day(s) old" -f $m.AntivirusSignatureAge) }
}
Invoke-Check 'Firewall' {
    $f = Get-NetFirewallProfile
    if (-not (Assert-Data $f 'Get-NetFirewallProfile')) { return }
    foreach ($x in $f) {
        Write-Output ("  firewall {0}: enabled={1}" -f $x.Name, $x.Enabled)
        if (-not $x.Enabled) { Add-Finding 'Critical' ("Windows Firewall profile {0} is disabled" -f $x.Name) }
    }
}

Write-Section '2. PROTOCOLS AND AUTHENTICATION'
Invoke-Check 'SMB' {
    $s = Get-SmbServerConfiguration
    if (-not (Assert-Data $s 'Get-SmbServerConfiguration')) { return }
    Write-Output ("  SMB1 enabled={0}; signing required={1}" -f $s.EnableSMB1Protocol, $s.RequireSecuritySignature)
    if ($s.EnableSMB1Protocol) { Add-Finding 'Critical' 'SMBv1 is enabled' }
}
Invoke-Check 'LAN Manager compatibility level' {
    $lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $lm = $lsa.LmCompatibilityLevel
    if ($null -eq $lm) { Write-Output '  LmCompatibilityLevel not set (version default applies; read the Microsoft documentation for your release)'; return }
    Write-Output ("  LmCompatibilityLevel={0}" -f $lm)
    if ($lm -lt 3) { Add-Finding 'Warning' "LmCompatibilityLevel is $lm; clients send LM or NTLMv1 responses" }
    elseif ($lm -lt 5) { Write-Output '  note: levels 3 and 4 send NTLMv2 but domain controllers still accept NTLM (v1); only level 5 refuses LM and NTLM responses (Microsoft LAN Manager authentication level table)' }
}
Invoke-Check 'Schannel protocols' {
    foreach ($p in 'SSL 3.0', 'TLS 1.0', 'TLS 1.1', 'TLS 1.2', 'TLS 1.3') {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$p\Server"
        if (Test-Path $k) {
            $v = Get-ItemProperty $k
            Write-Output ("  {0} server: Enabled={1} DisabledByDefault={2}" -f $p, $v.Enabled, $v.DisabledByDefault)
        } else { Write-Output ("  {0} server: no explicit setting (OS default applies)" -f $p) }
    }
}
Invoke-Check 'RDP network level authentication' {
    $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').UserAuthentication
    $pol = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -ErrorAction SilentlyContinue).UserAuthentication
    Write-Output ("  UserAuthentication local={0}; policy={1}" -f $nla, $(if ($null -ne $pol) { $pol } else { 'not set' }))
    $effective = if ($null -ne $pol) { $pol } else { $nla }
    if ($effective -ne 1) { Add-Finding 'Warning' 'RDP network level authentication is not required' }
}

Write-Section '3. VIRTUALISATION-BASED SECURITY'
Invoke-Check 'Device Guard / VBS' {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard'
    if (-not (Assert-Data $dg 'Win32_DeviceGuard')) { return }
    Write-Output ("  VBS status={0} (0 off, 1 configured, 2 running); services running={1}; services configured={2}" -f $dg.VirtualizationBasedSecurityStatus, ($dg.SecurityServicesRunning -join ','), ($dg.SecurityServicesConfigured -join ','))
    Write-Output '  service codes: 1 Credential Guard, 2 HVCI, 3 System Guard Secure Launch, 4 SMM firmware measurement'
}

Write-Section '4. LOCAL ADMINISTRATORS AND SERVICES'
Invoke-Check 'Local administrators' {
    $m = Get-LocalGroupMember -Group 'Administrators'
    if (-not (Assert-Data $m 'Local Administrators group')) { return }
    $m | ForEach-Object { Write-Output ("  {0} ({1})" -f $_.Name, $_.ObjectClass) }
    if (@($m).Count -gt 5) { Add-Finding 'Warning' ("{0} members in local Administrators; review" -f @($m).Count) }
}
Invoke-Check 'Print Spooler' {
    $s = Get-Service -Name Spooler
    Write-Output ("  Print Spooler: {0}, start type {1}" -f $s.Status, $s.StartType)
    if ($s.Status -eq 'Running') {
        $role = Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue
        $print = if ($role) { (Get-WindowsFeature -Name Print-Services).Installed } else { $false }
        if (-not $print) { Add-Finding 'Warning' 'Print Spooler is running on a server without the Print Services role; consider disabling after review' }
    }
}

Write-Section '5. AUDIT POLICY'
Invoke-Check 'Audit policy' {
    $a = & auditpol /get /category:* 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'auditpol /get failed (needs elevation)'; return }
    $shown = @($a | Where-Object { $_ -match 'Logon|Account Lockout|Special Logon|Audit Policy Change|User Account Management|Security System Extension' })
    if ($shown.Count -eq 0) { Add-Finding 'Warning' 'auditpol output was not recognised (English subcategory names; localised systems need a manual check)'; return }
    $shown | ForEach-Object { Write-Output "  $_" }
    $noAudit = @($a | Where-Object { $_ -match '^\s+(Logon|Account Lockout)\s+No Auditing' })
    if ($noAudit.Count -gt 0) { Add-Finding 'Warning' 'Logon or Account Lockout auditing is set to No Auditing' }
}

Write-Section '6. WINDOWS LAPS (if present)'
Invoke-Check 'Windows LAPS' {
    if (-not (Get-Command Get-LapsDiagnostics -ErrorAction SilentlyContinue)) { Write-Output '  Windows LAPS cmdlets not present'; return }
    $found = $false
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Policies\LAPS', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\LAPS\Config') {
        if (Test-Path $k) { $found = $true; Write-Output ("  {0}" -f $k); (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Write-Output ("    {0} = {1}" -f $_.Name, $_.Value) } }
    }
    if (-not $found) { Write-Output '  no Windows LAPS policy found in the usual policy locations (key names are from documentation; confirm with Get-LapsDiagnostics)' }
}

Complete-Report
exit $script:ExitCode
