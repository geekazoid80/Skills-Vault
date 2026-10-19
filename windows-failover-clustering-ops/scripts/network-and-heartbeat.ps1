<#
.SYNOPSIS
    Cluster networks, interfaces and heartbeat settings.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports network state and role, interface state, heartbeat delay and threshold values and the quarantine settings.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on a cluster node (or a machine with the Failover Clustering tools and rights to the cluster).
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\network-and-heartbeat.ps1
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

Write-Output 'Failover cluster networks and heartbeat settings'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:ClOk = $false
Invoke-Check 'Cluster access' {
    if (-not (Get-Command Get-Cluster -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-Cluster is not available: the Failover Clustering PowerShell module is not installed here'
        return
    }
    $c = Get-Cluster
    if (-not (Assert-Data $c 'Get-Cluster')) { return }
    $script:ClOk = $true
    $script:Cluster = $c
    Write-Output ("  Cluster: {0}" -f $c.Name)
}
if (-not $script:ClOk) { Add-Finding 'Critical' 'Could not reach a cluster from this host; run this on a cluster node or a machine with the clustering tools and rights' }

Write-Section '1. CLUSTER NETWORKS'
Invoke-Check 'Networks' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $nets = @(Get-ClusterNetwork)
    if (-not (Assert-Data $nets 'Get-ClusterNetwork')) { return }
    foreach ($n in $nets | Sort-Object Metric) {
        Write-Output ("  {0}: state={1}, role={2}, address={3}/{4}, metric={5}, auto metric={6}" -f $n.Name, $n.State, $n.Role, $n.Address, $n.AddressMask, $n.Metric, $n.AutoMetric)
        if ("$($n.State)" -eq 'Down' -or "$($n.State)" -eq 'Partitioned') { Add-Finding 'Critical' ("Cluster network {0} is {1}" -f $n.Name, $n.State) }
        elseif ("$($n.State)" -ne 'Up') { Add-Finding 'Warning' ("Cluster network {0} state is {1}" -f $n.Name, $n.State) }
    }
    $withCluster = @($nets | Where-Object { [int]$_.Role -eq 1 -or [int]$_.Role -eq 3 })
    if ($withCluster.Count -lt 2) { Add-Finding 'Warning' ("Only {0} network(s) carry cluster traffic; a second path avoids a single point of failure" -f $withCluster.Count) }
    Write-Output '  (role 0 = not used by the cluster, 1 = cluster traffic only, 3 = cluster and client; 2 is not a supported value)'
}

Write-Section '2. NETWORK INTERFACES'
Invoke-Check 'Interfaces' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $if = @(Get-ClusterNetworkInterface)
    if (-not (Assert-Data $if 'Get-ClusterNetworkInterface')) { return }
    foreach ($i in $if) {
        Write-Output ("  {0} / {1} on {2}: state={3}" -f $i.Node, $i.Name, $i.Network, $i.State)
        if ("$($i.State)" -eq 'Down') { Add-Finding 'Critical' ("Interface {0} on node {1} is Down" -f $i.Name, $i.Node) }
        elseif ("$($i.State)" -ne 'Up') { Add-Finding 'Warning' ("Interface {0} on node {1} state is {2}" -f $i.Name, $i.Node, $i.State) }
    }
}

Write-Section '3. HEARTBEAT AND QUARANTINE SETTINGS'
Invoke-Check 'Heartbeat settings' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $c = $script:Cluster
    Write-Output ("  Same subnet: delay {0} ms, threshold {1}" -f $c.SameSubnetDelay, $c.SameSubnetThreshold)
    Write-Output ("  Cross subnet: delay {0} ms, threshold {1}" -f $c.CrossSubnetDelay, $c.CrossSubnetThreshold)
    Write-Output ("  Quarantine: threshold {0}, duration {1} s" -f $c.QuarantineThreshold, $c.QuarantineDuration)
    Write-Output '  Microsoft sources give 10 (same subnet) and 20 (cross subnet) as the Windows Server 2016 and 2019 defaults; read the values on a new 2022 or 2025 cluster before treating any number as a default.'
    if ($null -eq $c.SameSubnetThreshold -or $null -eq $c.CrossSubnetThreshold) { Add-Finding 'Warning' 'Heartbeat thresholds were not returned by Get-Cluster'; return }
    if ([int]$c.SameSubnetThreshold -lt 10 -or [int]$c.CrossSubnetThreshold -lt 20) {
        Add-Finding 'Warning' ("Heartbeat thresholds ({0} same subnet, {1} cross subnet) are below the documented 2016 and 2019 defaults of 10 and 20; confirm the change was intended" -f $c.SameSubnetThreshold, $c.CrossSubnetThreshold)
    }
}

Complete-Report
exit $script:ExitCode
