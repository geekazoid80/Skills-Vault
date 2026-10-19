<#
.SYNOPSIS
    Physical disk, volume, Storage Spaces and shadow copy health.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports health status, free space, reliability counters and VSS shadow storage.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\storage-health.ps1
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

Write-Output 'Windows Server storage health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. PHYSICAL DISKS'
Invoke-Check 'Physical disks' {
    $d = Get-PhysicalDisk
    if (-not (Assert-Data $d 'Get-PhysicalDisk')) { return }
    foreach ($x in $d) {
        Write-Output ("  {0}: {1}, {2}, health={3}, operational={4}" -f $x.FriendlyName, $x.MediaType, $x.BusType, $x.HealthStatus, $x.OperationalStatus)
        if ($x.HealthStatus -ne 'Healthy') { Add-Finding 'Critical' ("Physical disk {0} health is {1}" -f $x.FriendlyName, $x.HealthStatus) }
    }
}

Write-Section '2. VOLUMES'
Invoke-Check 'Volumes' {
    $v = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }
    if (-not (Assert-Data $v 'Get-Volume')) { return }
    foreach ($x in $v) {
        $free = [math]::Round(100 * $x.SizeRemaining / $x.Size, 1)
        Write-Output ("  {0} [{1}] {2}: {3:N1} GB, {4}% free, health={5}" -f $x.DriveLetter, $x.FileSystemLabel, $x.FileSystem, ($x.Size / 1GB), $free, $x.HealthStatus)
        if ($free -lt 10) { Add-Finding 'Critical' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
        elseif ($free -lt 20) { Add-Finding 'Warning' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
        if ($x.HealthStatus -ne 'Healthy') { Add-Finding 'Critical' ("Volume {0} health is {1}" -f $x.DriveLetter, $x.HealthStatus) }
    }
}

Write-Section '3. STORAGE SPACES VIRTUAL DISKS (if any)'
Invoke-Check 'Virtual disks' {
    if (-not (Get-Command Get-VirtualDisk -ErrorAction SilentlyContinue)) { Write-Output '  Storage module not available'; return }
    $vd = @(Get-VirtualDisk)
    if ($vd.Count -eq 0) { Write-Output '  none'; return }
    foreach ($x in $vd) {
        Write-Output ("  {0}: operational={1}, health={2}" -f $x.FriendlyName, $x.OperationalStatus, $x.HealthStatus)
        if ($x.HealthStatus -ne 'Healthy') { Add-Finding 'Critical' ("Virtual disk {0} health is {1}" -f $x.FriendlyName, $x.HealthStatus) }
    }
}

Write-Section '4. DISK RELIABILITY COUNTERS'
Invoke-Check 'Reliability counters' {
    $r = Get-PhysicalDisk | Get-StorageReliabilityCounter
    if (-not (Assert-Data $r 'Get-StorageReliabilityCounter')) { return }
    foreach ($x in $r) {
        if ($null -eq $x.ReadErrorsTotal -and $null -eq $x.WriteErrorsTotal) { Write-Output ("  disk {0}: reliability counters not reported by this device or virtual disk" -f $x.DeviceId); continue }
        Write-Output ("  disk {0}: read errors={1}, write errors={2}, temperature={3}" -f $x.DeviceId, $x.ReadErrorsTotal, $x.WriteErrorsTotal, $x.Temperature)
        if ($x.ReadErrorsTotal -gt 0 -or $x.WriteErrorsTotal -gt 0) { Add-Finding 'Warning' ("Disk {0} reports media errors (read {1}, write {2})" -f $x.DeviceId, $x.ReadErrorsTotal, $x.WriteErrorsTotal) }
    }
}

Write-Section '5. SHADOW COPY STORAGE'
Invoke-Check 'Shadow storage' {
    $out = & vssadmin list shadowstorage 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'vssadmin list shadowstorage failed (needs elevation)'; return }
    $hits = @($out | Where-Object { $_ -match 'For volume|Used Shadow|Maximum Shadow' })
    if ($hits.Count -eq 0) { Write-Output '  no shadow storage configured, or the output was not recognised (English labels)'; return }
    $hits | ForEach-Object { Write-Output "  $_" }
}

Complete-Report
exit $script:ExitCode
