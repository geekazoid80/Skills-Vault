<#
.SYNOPSIS
    Virtual disk, volume and checkpoint review.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reads each attached virtual disk, flags legacy VHD files and deep differencing chains, checks free space on local volumes and lists checkpoints by age.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\storage-and-checkpoints.ps1 -MaxChainDepth 2
#>
[CmdletBinding()]
param(
    [int]$CheckpointWarnDays = 7,
    [int]$MaxChainDepth = 3
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

Write-Output 'Hyper-V storage and checkpoints'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); checkpoint warning age {1} day(s); chain depth warning above {2}" -f (Get-Date).ToUniversalTime(), $CheckpointWarnDays, $MaxChainDepth)

$script:HvOk = [bool](Get-Command Get-VM -ErrorAction SilentlyContinue)
if (-not $script:HvOk) { Add-Finding 'Critical' 'Get-VM is not available: the Hyper-V PowerShell module is not installed here' }
$script:vms = @()
if ($script:HvOk) {
    Invoke-Check 'Elevation' {
        if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; Get-VM may return no VMs' }
    }
    Invoke-Check 'VM list' {
        $script:vms = @(Get-VM)
    }
}

Write-Section '1. VIRTUAL DISKS'
function Get-ChainDepth {
    param([string]$Path)
    $depth = 0
    $cur = $Path
    while ($cur -and $depth -lt 30) {
        $d = Get-VHD -Path $cur -ErrorAction Stop
        if ($d.VhdType -ne 'Differencing') { break }
        $depth++
        $cur = $d.ParentPath
    }
    return $depth
}
Invoke-Check 'Virtual disks' {
    if ($script:vms.Count -eq 0) { Add-Finding 'Warning' 'Get-VM returned no VMs (an empty host, or not elevated, or not in the Hyper-V Administrators group)'; return }
    $seen = @{}
    foreach ($v in $script:vms) {
        foreach ($drive in @(Get-VMHardDiskDrive -VM $v)) {
            if (-not $drive.Path) { continue }
            if ($seen.ContainsKey($drive.Path)) { continue }
            $seen[$drive.Path] = $true
            try {
                $vhd = Get-VHD -Path $drive.Path -ErrorAction Stop
            } catch {
                Add-Finding 'Critical' ("VM {0}: virtual disk {1} could not be read ({2})" -f $v.Name, $drive.Path, $_.Exception.Message)
                continue
            }
            Write-Output ("  {0}: {1}, {2}, size {3:N1} GB, file {4:N1} GB" -f $v.Name, $vhd.VhdFormat, $vhd.VhdType, ($vhd.Size / 1GB), ($vhd.FileSize / 1GB))
            if ("$($vhd.VhdFormat)" -eq 'VHD') { Add-Finding 'Warning' ("VM {0}: {1} is a legacy VHD (2,040 GB limit, no journalling); convert to VHDX in a planned window" -f $v.Name, $drive.Path) }
            if ("$($vhd.VhdType)" -eq 'Differencing') {
                try { $depth = Get-ChainDepth -Path $drive.Path }
                catch { Add-Finding 'Warning' ("VM {0}: the differencing chain of {1} could not be followed ({2})" -f $v.Name, $drive.Path, $_.Exception.Message); continue }
                Write-Output ("      differencing disk, chain depth {0}" -f $depth)
                if ($depth -gt $MaxChainDepth) { Add-Finding 'Warning' ("VM {0}: differencing chain depth {1} exceeds {2} (rule of thumb); long chains add latency" -f $v.Name, $depth, $MaxChainDepth) }
            }
        }
    }
}

Write-Section '2. VOLUMES HOLDING VM FILES'
Invoke-Check 'Volume free space' {
    if ($script:vms.Count -eq 0) { Write-Output '  nothing to check'; return }
    $letters = @{}
    $csv = $false
    $unc = $false
    foreach ($v in $script:vms) {
        foreach ($drive in @(Get-VMHardDiskDrive -VM $v)) {
            if (-not $drive.Path) { continue }
            if ($drive.Path -match '\\ClusterStorage\\') { $csv = $true; continue }
            if ($drive.Path.StartsWith('\\')) { $unc = $true; continue }
            if ($drive.Path -match '^([A-Za-z]):') { $letters[$Matches[1].ToUpper()] = $true }
        }
    }
    if ($csv) { Write-Output '  some disks are on Cluster Shared Volumes; check those with the failover clustering csv-health script' }
    if ($unc) { Write-Output '  some disks are on SMB shares; free space on the file server was not checked' }
    foreach ($l in $letters.Keys) {
        $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $l)
        if (-not (Assert-Data $vol "Win32_LogicalDisk ${l}:")) { continue }
        $free = [math]::Round(100 * $vol.FreeSpace / $vol.Size, 1)
        Write-Output ("  {0}: {1}% free of {2:N0} GB" -f $l, $free, ($vol.Size / 1GB))
        if ($free -lt 10) { Add-Finding 'Critical' ("Volume {0}: holding VM files has {1}% free (VMs pause when it fills)" -f $l, $free) }
        elseif ($free -lt 20) { Add-Finding 'Warning' ("Volume {0}: holding VM files has {1}% free" -f $l, $free) }
    }
}

Write-Section '3. CHECKPOINT INVENTORY'
Invoke-Check 'Checkpoints' {
    if ($script:vms.Count -eq 0) { Write-Output '  nothing to check'; return }
    $count = 0
    foreach ($v in $script:vms) {
        foreach ($s in @(Get-VMSnapshot -VM $v)) {
            $count++
            $age = [math]::Round(((Get-Date) - $s.CreationTime).TotalDays, 1)
            Write-Output ("  {0}: '{1}' ({2}) {3} day(s) old" -f $v.Name, $s.Name, $s.SnapshotType, $age)
            if ($age -gt $CheckpointWarnDays) { Add-Finding 'Warning' ("VM {0}: checkpoint '{1}' is {2} day(s) old" -f $v.Name, $s.Name, $age) }
        }
        $cfg = "$($v.CheckpointType)"
        if ($cfg -eq 'Standard') { Write-Output ("      note: {0} is set to Standard checkpoints (memory state; avoid on production VMs)" -f $v.Name) }
    }
    if ($count -eq 0) { Write-Output '  no checkpoints' }
}

Complete-Report
exit $script:ExitCode
