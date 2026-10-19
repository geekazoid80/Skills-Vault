<#
.SYNOPSIS
    Version-specific state for Windows Server 2016, 2019, 2022 and 2025.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Detects the build (or takes -Version) and prints the state of version-specific features. It reports state and does not judge it.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\version-checks.ps1 -Version 2025
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', '2016', '2019', '2022', '2025')] [string]$Version = 'Auto'
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

Write-Output 'Windows Server version-specific state (read only; reports state, does not judge it)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$build = 0
Invoke-Check 'Build detection' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not (Assert-Data $os 'Win32_OperatingSystem')) { return }
    $script:build = [int]$os.BuildNumber
    Write-Output ("Build {0}: {1}" -f $os.BuildNumber, $os.Caption)
}
$vp = $Version
if ($vp -eq 'Auto') {
    $vp = if ($build -ge 26100) { '2025' } elseif ($build -ge 20348) { '2022' } elseif ($build -ge 17763) { '2019' } elseif ($build -ge 14393) { '2016' } else { 'Unknown' }
}
Write-Output ("Version profile: {0}" -f $vp)
if ($vp -eq 'Unknown') { Add-Finding 'Warning' 'Build number not recognised; no version-specific checks were run' }

Write-Section 'ALL VERSIONS: containers and virtualisation-based security'
Invoke-Check 'Containers feature' {
    if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { Write-Output '  Get-WindowsFeature unavailable'; return }
    $c = Get-WindowsFeature -Name Containers
    Write-Output ("  Containers feature installed: {0}" -f $c.Installed)
}
Invoke-Check 'VBS' {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard'
    if (-not (Assert-Data $dg 'Win32_DeviceGuard')) { return }
    Write-Output ("  VBS status={0}; services running={1}" -f $dg.VirtualizationBasedSecurityStatus, ($dg.SecurityServicesRunning -join ','))
}

if ($vp -in '2019', '2022', '2025') {
    Write-Section '2019 AND LATER: Windows Admin Center gateway, System Insights'
    Invoke-Check 'Admin Center gateway' {
        $g = Get-Service -Name ServerManagementGateway -ErrorAction SilentlyContinue
        if ($g) { Write-Output ("  Windows Admin Center gateway service: {0}" -f $g.Status) } else { Write-Output '  gateway service not present on this host' }
    }
    Invoke-Check 'System Insights' {
        if (-not (Get-Command Get-InsightsCapability -ErrorAction SilentlyContinue)) { Write-Output '  System Insights feature not installed'; return }
        Get-InsightsCapability | ForEach-Object { Write-Output ("  {0}: {1}" -f $_.Name, $_.Status) }
    }
}
if ($vp -in '2022', '2025') {
    Write-Section '2022 AND LATER: secured-core indicators and SMB'
    Invoke-Check 'Secure Boot and TPM' {
        Write-Output ("  Secure Boot: {0}" -f (Confirm-SecureBootUEFI))
        $t = Get-Tpm
        Write-Output ("  TPM present={0} ready={1}" -f $t.TpmPresent, $t.TpmReady)
    }
    Invoke-Check 'SMB features' {
        $s = Get-SmbServerConfiguration
        if (-not (Assert-Data $s 'Get-SmbServerConfiguration')) { return }
        $s | Select-Object -Property * | Format-List -Property *Compress*, *QUIC*, EncryptData, RequireSecuritySignature | Out-String | ForEach-Object { Write-Output $_.TrimEnd() }
        $m = @(Get-SmbServerCertificateMapping -ErrorAction SilentlyContinue)
        Write-Output ("  SMB over QUIC certificate mappings: {0}" -f $m.Count)
    }
}
if ($vp -eq '2025') {
    Write-Section '2025: NVMe, Hotpatch enrolment, DTrace, AD functional level, GPU partitioning'
    Invoke-Check 'NVMe devices' {
        $n = @(Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' })
        Write-Output ("  NVMe physical disks: {0}" -f $n.Count)
        $n | ForEach-Object { Write-Output ("    {0}: health={1}" -f $_.FriendlyName, $_.HealthStatus) }
    }
    Invoke-Check 'Azure Arc agent (Hotpatch enrolment)' {
        $a = Get-Command azcmagent -ErrorAction SilentlyContinue
        if (-not $a) { Write-Output '  azcmagent not installed; Arc-enabled Hotpatch is not available on this host'; return }
        $o = & azcmagent show 2>&1
        if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'azcmagent show failed'; return }
        $o | Where-Object { $_ -match 'Agent Status|Agent Version|Resource Name' } | ForEach-Object { Write-Output "  $_" }
    }
    Invoke-Check 'DTrace' {
        $d = Get-Command dtrace -ErrorAction SilentlyContinue
        Write-Output ("  dtrace on PATH: {0}" -f [bool]$d)
    }
    Invoke-Check 'AD domain functional level' {
        if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) { Write-Output '  ActiveDirectory module not present'; return }
        $d = Get-ADDomain
        Write-Output ("  domain mode: {0}" -f $d.DomainMode)
    }
    Invoke-Check 'GPU partitioning' {
        if (-not (Get-Command Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue)) { Write-Output '  Hyper-V module not present'; return }
        $g = @(Get-VMHostPartitionableGpu)
        Write-Output ("  partitionable GPUs: {0}" -f $g.Count)
    }
}

Complete-Report
exit $script:ExitCode
