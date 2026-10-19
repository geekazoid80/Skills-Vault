<#
.SYNOPSIS
    Disk space analysis; nothing is cleaned.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports volume free space, sizes of common space consumers and Storage Sense policy. With -IncludeComponentStore it runs the read-only DISM analysis.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\disk-space-analysis.ps1 -IncludeComponentStore
#>
[CmdletBinding()]
param(
    [switch]$IncludeComponentStore,
    [switch]$SkipFolderSizes
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

Write-Output 'Windows client disk space analysis (analysis only; nothing is deleted or cleaned)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. VOLUMES'
Invoke-Check 'Volumes' {
    $v = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }
    if (-not (Assert-Data $v 'Get-Volume')) { return }
    foreach ($x in $v) {
        $free = [math]::Round(100 * $x.SizeRemaining / $x.Size, 1)
        Write-Output ("  {0}: {1:N0} GB total, {2:N1} GB free ({3}%)" -f $x.DriveLetter, ($x.Size / 1GB), ($x.SizeRemaining / 1GB), $free)
        if ($free -lt 10) { Add-Finding 'Critical' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
        elseif ($free -lt 20) { Add-Finding 'Warning' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
    }
}

Write-Section '2. COMMON SPACE CONSUMERS (sizes only)'
$script:partial = $false
function Get-FolderSizeMb { param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue -ErrorVariable gcErr
    if (@($gcErr).Count -gt 0) { $script:partial = $true }
    $sum = ($items | Measure-Object -Property Length -Sum).Sum
    return [math]::Round($sum / 1MB, 0)
}
Invoke-Check 'Folder sizes' {
    $targets = @{
        'Previous Windows installation (Windows.old)' = "$env:SystemDrive\Windows.old"
        'System temp'                                  = "$env:SystemRoot\Temp"
        'User temp'                                    = $env:TEMP
        'Windows Update download cache'                = "$env:SystemRoot\SoftwareDistribution\Download"
        'Delivery Optimisation cache'                  = "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"
        'Crash dumps'                                  = "$env:SystemRoot\Minidump"
    }
    if ($SkipFolderSizes) { Write-Output '  skipped (-SkipFolderSizes)'; return }
    foreach ($k in $targets.Keys) {
        $mb = Get-FolderSizeMb -Path $targets[$k]
        if ($null -eq $mb) { Write-Output ("  {0}: not present" -f $k) } else { Write-Output ("  {0}: {1:N0} MB" -f $k, $mb) }
    }
    if ($script:partial) { Add-Finding 'Warning' 'Some folders could not be read fully (access denied); sizes are partial. Run elevated for complete figures.' }
}

Write-Section '3. STORAGE SENSE POLICY'
Invoke-Check 'Storage Sense' {
    $k = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Write-Output ("  {0} = {1}" -f $_.Name, $_.Value) } } else { Write-Output '  Storage Sense policy not set for the current user' }
}

if ($IncludeComponentStore) {
    Write-Section '4. COMPONENT STORE ANALYSIS (read-only DISM analysis; takes a minute or more)'
    Invoke-Check 'Component store' {
        $o = & DISM /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
        if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'DISM AnalyzeComponentStore failed (needs elevation)'; return }
        $o | Where-Object { $_ -match 'Actual Size|Backups and Disabled|Reclaimable|Cleanup Recommended|Last Cleanup' } | ForEach-Object { Write-Output "  $_" }
        Write-Output '  Cleanup is a separate, state-changing step (DISM /StartComponentCleanup); this script does not run it.'
    }
}

Complete-Report
exit $script:ExitCode
