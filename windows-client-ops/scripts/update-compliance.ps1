<#
.SYNOPSIS
    Build support state, installed updates and update policy.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports build, newest hotfix age, pending reboot, Windows Update for Business policy keys, Delivery Optimisation and update services.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\update-compliance.ps1 -MaxUpdateAgeDays 45
#>
[CmdletBinding()]
param(
    [int]$MaxUpdateAgeDays = 45
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

Write-Output 'Windows client update compliance (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. BUILD AND SUPPORT STATE'
Invoke-Check 'Build' {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if (-not (Assert-Data $cv 'CurrentVersion registry key')) { return }
    Write-Output ("  {0} {1}, build {2}.{3}" -f $cv.ProductName, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
    if ([int]$cv.CurrentBuild -lt 22000) {
        if ($cv.EditionID -like '*S') { Write-Output '  Windows 10 LTSC edition: it follows its own lifecycle, which is later than the general Windows 10 date; check the Microsoft Lifecycle page for the exact LTSC release.' }
        else { Add-Finding 'Warning' 'This is a Windows 10 build; Windows 10 reached end of support on 14 October 2025 (check ESU enrolment or migrate)' }
    }
    Write-Output '  Compare the version against the Microsoft Lifecycle page for your edition (Home and Pro end earlier than Enterprise and Education).'
}

Write-Section '2. INSTALLED UPDATES'
Invoke-Check 'Hotfixes' {
    $h = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending
    if (-not (Assert-Data $h 'Get-HotFix')) { return }
    $h | Select-Object -First 5 | ForEach-Object { Write-Output ("  {0:yyyy-MM-dd} {1} {2}" -f $_.InstalledOn, $_.HotFixID, $_.Description) }
    $age = ((Get-Date) - $h[0].InstalledOn).TotalDays
    if ($age -gt $MaxUpdateAgeDays) { Add-Finding 'Warning' ("Newest installed update is {0:N0} days old (threshold {1})" -f $age, $MaxUpdateAgeDays) }
}
Invoke-Check 'Pending reboot' {
    $p = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    Write-Output ("  reboot pending: {0}" -f $p)
    if ($p) { Add-Finding 'Warning' 'A reboot is pending' }
}

Write-Section '3. UPDATE POLICY (Windows Update for Business and WSUS keys)'
Invoke-Check 'Update policy' {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (-not (Test-Path $k)) { Write-Output '  no WindowsUpdate policy key (no policy applied, or managed another way)'; return }
    (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Write-Output ("  {0} = {1}" -f $_.Name, $_.Value) }
    $p = Get-ItemProperty $k
    foreach ($n in 'DeferQualityUpdatesPeriodInDays') { if ($p.$n -gt 30) { Add-Finding 'Warning' ("{0} is {1}; long quality-update deferrals extend exposure" -f $n, $p.$n) } }
}

Write-Section '4. DELIVERY OPTIMISATION'
Invoke-Check 'Delivery Optimisation' {
    if (-not (Get-Command Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue)) { Write-Output '  cmdlet not available'; return }
    $d = @(Get-DeliveryOptimizationStatus)
    Write-Output ("  active transfers: {0}" -f $d.Count)
    $mode = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -ErrorAction SilentlyContinue).DODownloadMode
    Write-Output ("  policy download mode: {0}" -f $(if ($null -ne $mode) { $mode } else { 'not set' }))
}

Write-Section '5. WINDOWS UPDATE SERVICES'
Invoke-Check 'Services' {
    foreach ($n in 'wuauserv', 'bits', 'UsoSvc') {
        $s = Get-Service -Name $n
        Write-Output ("  {0}: {1}, start type {2}" -f $n, $s.Status, $s.StartType)
        if ($s.StartType -eq 'Disabled') { Add-Finding 'Warning' ("Service {0} is disabled" -f $n) }
    }
}

Complete-Report
exit $script:ExitCode
