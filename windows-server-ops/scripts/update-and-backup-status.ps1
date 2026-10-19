<#
.SYNOPSIS
    Update recency, update policy and backup status.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports newest hotfix age, update policy keys, pending reboot, Windows Server Backup result and VSS writer state.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\update-and-backup-status.ps1 -MaxUpdateAgeDays 45
#>
[CmdletBinding()]
param(
    [int]$MaxUpdateAgeDays = 60
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

Write-Output 'Windows Server update and backup status (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. INSTALLED UPDATES'
Invoke-Check 'Installed hotfixes' {
    $h = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending
    if (-not (Assert-Data $h 'Get-HotFix')) { return }
    $h | Select-Object -First 5 | ForEach-Object { Write-Output ("  {0:yyyy-MM-dd} {1} {2}" -f $_.InstalledOn, $_.HotFixID, $_.Description) }
    $age = ((Get-Date) - $h[0].InstalledOn).TotalDays
    Write-Output ("  newest update installed {0:N0} day(s) ago" -f $age)
    if ($age -gt $MaxUpdateAgeDays) { Add-Finding 'Warning' ("Newest installed update is {0:N0} days old (threshold {1})" -f $age, $MaxUpdateAgeDays) }
}

Write-Section '2. UPDATE SERVICE AND POLICY'
Invoke-Check 'Windows Update service' {
    $s = Get-Service -Name wuauserv
    Write-Output ("  wuauserv: {0}, start type {1}" -f $s.Status, $s.StartType)
    if ($s.StartType -eq 'Disabled') { Add-Finding 'Warning' 'The Windows Update service is disabled' }
}
Invoke-Check 'Update policy keys' {
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU') {
        if (Test-Path $k) {
            Write-Output ("  {0}" -f $k)
            (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Write-Output ("    {0} = {1}" -f $_.Name, $_.Value) }
        } else { Write-Output ("  {0}: not set" -f $k) }
    }
}
Invoke-Check 'Pending reboot' {
    $p = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    Write-Output ("  reboot pending: {0}" -f $p)
    if ($p) { Add-Finding 'Warning' 'A reboot is pending' }
}

Write-Section '3. WINDOWS SERVER BACKUP (if installed)'
Invoke-Check 'Windows Server Backup' {
    if (-not (Get-Command Get-WBSummary -ErrorAction SilentlyContinue)) { Write-Output '  Windows Server Backup cmdlets not present (another backup product may be in use)'; return }
    $b = Get-WBSummary
    if (-not (Assert-Data $b 'Get-WBSummary')) { return }
    Write-Output ("  last successful backup: {0}; last result: {1}; next: {2}" -f $b.LastSuccessfulBackupTime, $b.LastBackupResultHR, $b.NextBackupTime)
    if ($null -ne $b.LastBackupResultHR -and $b.LastBackupResultHR -ne 0) { Add-Finding 'Warning' ("The most recent backup attempt failed (result code {0})" -f $b.LastBackupResultHR) }
    if (-not $b.LastSuccessfulBackupTime) { Add-Finding 'Warning' 'Windows Server Backup has no successful backup recorded' }
    elseif (((Get-Date) - $b.LastSuccessfulBackupTime).TotalDays -gt 2) { Add-Finding 'Warning' 'Last successful Windows Server Backup is more than two days old' }
}

Write-Section '4. VSS WRITERS'
Invoke-Check 'VSS writers' {
    $w = & vssadmin list writers 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'vssadmin list writers failed (needs elevation)'; return }
    $states = @($w | Where-Object { $_ -match 'State:' })
    if ($states.Count -eq 0) { Add-Finding 'Warning' 'vssadmin returned no writer states'; return }
    $bad = @($states | Where-Object { $_ -notmatch 'Stable' })
    Write-Output ("  writers: {0}; not stable: {1}" -f $states.Count, $bad.Count)
    if ($bad.Count -gt 0) { Add-Finding 'Warning' ("{0} VSS writer(s) are not in a stable state" -f $bad.Count) }
}

Complete-Report
exit $script:ExitCode
