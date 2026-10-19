<#
.SYNOPSIS
    Cluster Shared Volume state, redirection and free space.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports CSV state, owner, file system, free space and per-node I/O state including the redirection reasons.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on a cluster node (or a machine with the Failover Clustering tools and rights to the cluster).
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\csv-health.ps1
#>
[CmdletBinding()]
param()

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

Write-Output 'Cluster Shared Volume health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:ClOk = $false
Invoke-Check 'Cluster access' {
    if (-not (Get-Command Get-ClusterSharedVolume -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-ClusterSharedVolume is not available: the Failover Clustering PowerShell module is not installed here'
        return
    }
    $c = Get-Cluster
    if (-not (Assert-Data $c 'Get-Cluster')) { return }
    $script:ClOk = $true
    Write-Output ("  Cluster: {0}; CSV block cache size: {1} MB" -f $c.Name, $c.BlockCacheSize)
}
if (-not $script:ClOk) { Add-Finding 'Critical' 'Could not reach a cluster from this host; run this on a cluster node or a machine with the clustering tools and rights' }

Write-Section '1. VOLUMES'
Invoke-Check 'Volumes' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $csv = @(Get-ClusterSharedVolume)
    if ($csv.Count -eq 0) { Write-Output '  no Cluster Shared Volumes in this cluster'; return }
    foreach ($v in $csv) {
        $infos = @($v.SharedVolumeInfo)
        $pct = $null; $fs = 'unknown'; $redir = $false; $maint = $false
        foreach ($info in $infos) {
            if ($null -eq $info) { continue }
            if ($info.RedirectedAccess) { $redir = $true }
            if ($info.MaintenanceMode) { $maint = $true }
            foreach ($part in @($info.Partition)) {
                if ($null -eq $part) { continue }
                $p = [math]::Round([double]$part.PercentFree, 1)
                if ($null -eq $pct -or $p -lt $pct) { $pct = $p }
                $fs = $part.FileSystem
            }
        }
        Write-Output ("  {0}: state={1}, owner={2}, file system={3}, lowest partition free={4}%, redirected access={5}, maintenance mode={6}" -f $v.Name, $v.State, $v.OwnerNode, $fs, $pct, $redir, $maint)
        if ("$($v.State)" -ne 'Online') { Add-Finding 'Critical' ("CSV {0} is {1}" -f $v.Name, $v.State) }
        if ($redir -and -not $maint) { Add-Finding 'Warning' ("CSV {0} is in redirected access outside maintenance mode" -f $v.Name) }
        if ($null -eq $pct) { Add-Finding 'Warning' ("CSV {0}: free space was not returned" -f $v.Name) }
        elseif ($pct -lt 10) { Add-Finding 'Critical' ("CSV {0} has {1}% free" -f $v.Name, $pct) }
        elseif ($pct -lt 20) { Add-Finding 'Warning' ("CSV {0} has {1}% free" -f $v.Name, $pct) }
    }
}

Write-Section '2. PER-NODE I/O STATE'
Invoke-Check 'Per-node state' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    if (@(Get-ClusterSharedVolume).Count -eq 0) { Write-Output '  no Cluster Shared Volumes, so no per-node state'; return }
    $st = @(Get-ClusterSharedVolumeState)
    if (-not (Assert-Data $st 'Get-ClusterSharedVolumeState')) { return }
    foreach ($s in $st) {
        Write-Output ("  {0} on {1}: {2} (file system reason: {3}; block reason: {4})" -f $s.Name, $s.Node, $s.StateInfo, $s.FileSystemRedirectedIOReason, $s.BlockRedirectedIOReason)
        if ("$($s.StateInfo)" -eq 'BlockRedirected') { Add-Finding 'Critical' ("CSV {0} is block redirected on {1} (storage connectivity loss on that node)" -f $s.Name, $s.Node) }
        elseif ("$($s.StateInfo)" -eq 'FileSystemRedirected') {
            if ("$($s.FileSystemRedirectedIOReason)" -match 'UserRequest') { Write-Output ("      {0} on {1} is redirected at the user's request (maintenance mode)" -f $s.Name, $s.Node) }
            else { Add-Finding 'Warning' ("CSV {0} is file system redirected on {1}, reason {2} (a backup, an incompatible filter, BitLocker initialising, or ReFS on SAN storage)" -f $s.Name, $s.Node, $s.FileSystemRedirectedIOReason) }
        }
        elseif ("$($s.StateInfo)" -ne 'Direct') { Add-Finding 'Warning' ("CSV {0} on {1} reports state '{2}'" -f $s.Name, $s.Node, $s.StateInfo) }
    }
    Write-Output '  (Microsoft: ReFS CSVs on SAN-attached storage run in redirected I/O; NTFS is advised there. ReFS is advised for Storage Spaces Direct.)'
}

Complete-Report
exit $script:ExitCode
