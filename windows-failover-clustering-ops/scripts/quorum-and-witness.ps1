<#
.SYNOPSIS
    Quorum configuration, witness state and vote margin.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reads the quorum type and witness resource, node weights, and computes votes present, votes needed and the margin.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on a cluster node (or a machine with the Failover Clustering tools and rights to the cluster).
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\quorum-and-witness.ps1
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

Write-Output 'Failover cluster quorum and witness'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:ClOk = $false
$script:Nodes = @()
Invoke-Check 'Cluster access' {
    if (-not (Get-Command Get-Cluster -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-Cluster is not available: the Failover Clustering PowerShell module is not installed here'
        return
    }
    $c = Get-Cluster
    if (-not (Assert-Data $c 'Get-Cluster')) { return }
    $script:ClOk = $true
    $script:Cluster = $c
    $script:Nodes = @(Get-ClusterNode)
    Write-Output ("  Cluster: {0}; nodes: {1}" -f $c.Name, $script:Nodes.Count)
}
if (-not $script:ClOk) { Add-Finding 'Critical' 'Could not reach a cluster from this host; run this on a cluster node or a machine with the clustering tools and rights' }

Write-Section '1. QUORUM CONFIGURATION'
$script:Witness = $null
Invoke-Check 'Quorum configuration' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $q = Get-ClusterQuorum
    if (-not (Assert-Data $q 'Get-ClusterQuorum')) { return }
    Write-Output ("  Quorum type: {0}" -f $q.QuorumType)
    $script:Witness = $q.QuorumResource
    if ($script:Witness) {
        Write-Output ("  Witness resource: {0} ({1}), state {2}" -f $script:Witness.Name, $script:Witness.ResourceType, $script:Witness.State)
        if ("$($script:Witness.State)" -ne 'Online') { Add-Finding 'Critical' ("Witness resource {0} is {1}" -f $script:Witness.Name, $script:Witness.State) }
    } else {
        Write-Output '  No witness configured'
        if ($script:Nodes.Count % 2 -eq 0) { Add-Finding 'Warning' ("Even number of nodes ({0}) and no witness: a split in half loses quorum; configure a witness" -f $script:Nodes.Count) }
        else { Write-Output '  (odd node count; Microsoft still recommends a witness)' }
    }
    Write-Output ("  Dynamic quorum: {0}" -f $script:Cluster.DynamicQuorum)
    if ($script:Cluster.PSObject.Properties['WitnessDynamicWeight']) { Write-Output ("  Witness dynamic weight: {0}" -f $script:Cluster.WitnessDynamicWeight) }
}

Write-Section '2. VOTES AND MARGIN'
Invoke-Check 'Vote arithmetic' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    if (-not (Assert-Data $script:Nodes 'Get-ClusterNode')) { return }
    $possible = 0
    $present = 0
    foreach ($n in $script:Nodes) {
        if ($null -eq $n.DynamicWeight) { Add-Finding 'Warning' ("Node {0}: DynamicWeight was not returned; the vote arithmetic below is incomplete" -f $n.Name); continue }
        $w = [int]$n.DynamicWeight
        $possible += $w
        if ("$($n.State)" -eq 'Up' -or "$($n.State)" -eq 'Paused') { $present += $w }
        Write-Output ("  {0}: state={1}, assigned weight={2}, dynamic weight={3}" -f $n.Name, $n.State, $n.NodeWeight, $n.DynamicWeight)
    }
    $wvote = 0
    if ($script:Witness -and $script:Cluster.PSObject.Properties['WitnessDynamicWeight']) { $wvote = [int]$script:Cluster.WitnessDynamicWeight }
    elseif ($script:Witness) { $wvote = 1 }
    $possible += $wvote
    if ($script:Witness -and "$($script:Witness.State)" -eq 'Online') { $present += $wvote }
    $needed = [math]::Floor($possible / 2) + 1
    $margin = $present - $needed
    Write-Output ("  Votes present: {0}; possible: {1}; needed for quorum: {2}; margin: {3}" -f $present, $possible, $needed, $margin)
    if ($margin -lt 0) { Add-Finding 'Critical' 'Votes present are below the quorum requirement as computed here (the cluster should not be running; re-check weights)' }
    elseif ($margin -eq 0) { Add-Finding 'Warning' 'Quorum margin is zero: if one more vote were lost at once the cluster would stop (sequential graceful or verified failures are handled by dynamic quorum)' }
    $zero = @($script:Nodes | Where-Object { [int]$_.NodeWeight -eq 0 })
    if ($zero.Count -gt 0) { Write-Output ("  Nodes with assigned weight 0: {0}" -f (($zero | ForEach-Object { $_.Name }) -join ', ')) }
}

Complete-Report
exit $script:ExitCode
