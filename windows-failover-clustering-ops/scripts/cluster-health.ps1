<#
.SYNOPSIS
    Failover cluster health summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers nodes, roles, resources and the main cluster events in the System log (1135, 1177, 1146, 1069, 5120, 5142).
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on a cluster node (or a machine with the Failover Clustering tools and rights to the cluster).
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\cluster-health.ps1 -Hours 72
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 720)] [int]$Hours = 24
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

Write-Output 'Failover cluster health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); event window {1} hour(s)" -f (Get-Date).ToUniversalTime(), $Hours)

$script:ClOk = $false
Invoke-Check 'Failover Clustering module' {
    if (-not (Get-Command Get-Cluster -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-Cluster is not available: the Failover Clustering PowerShell module is not installed here'
        return
    }
    $c = Get-Cluster
    if (-not (Assert-Data $c 'Get-Cluster')) { return }
    $script:ClOk = $true
    Write-Output ("  Cluster: {0}; functional level: {1}; dynamic quorum: {2}" -f $c.Name, $c.ClusterFunctionalLevel, $c.DynamicQuorum)
}
if (-not $script:ClOk) { Add-Finding 'Critical' 'Could not reach a cluster from this host; run this on a cluster node or a machine with the clustering tools and rights' }

Write-Section '1. NODES'
Invoke-Check 'Nodes' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $nodes = @(Get-ClusterNode)
    if (-not (Assert-Data $nodes 'Get-ClusterNode')) { return }
    foreach ($n in $nodes) {
        $info = if ($n.PSObject.Properties['StatusInformation']) { "$($n.StatusInformation)" } else { 'n/a' }
        Write-Output ("  {0}: state={1}, status={2}, drain={3}, weight={4}, dynamic weight={5}" -f $n.Name, $n.State, $info, $n.DrainStatus, $n.NodeWeight, $n.DynamicWeight)
        if ("$($n.State)" -eq 'Down') { Add-Finding 'Critical' ("Node {0} is Down" -f $n.Name) }
        elseif ("$($n.State)" -ne 'Up') { Add-Finding 'Warning' ("Node {0} state is {1}" -f $n.Name, $n.State) }
        if ($info -match 'Isolated|Quarantined|DrainFailed') { Add-Finding 'Warning' ("Node {0} status is '{1}' (an isolated or quarantined node hosts no roles; a failed drain left roles behind)" -f $n.Name, $info) }
        elseif ($info -match 'Drain|AvoidPlacement') { Write-Output ("      note: {0} status is '{1}' (expected while paused for maintenance)" -f $n.Name, $info) }
        elseif ($info -ne 'n/a' -and $info -ne '' -and $info -ne 'Normal') { Add-Finding 'Warning' ("Node {0} status information is '{1}'" -f $n.Name, $info) }
    }
}

Write-Section '2. ROLES (cluster groups)'
Invoke-Check 'Groups' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $groups = @(Get-ClusterGroup)
    if (-not (Assert-Data $groups 'Get-ClusterGroup')) { return }
    foreach ($g in $groups) {
        Write-Output ("  {0}: state={1}, owner={2}" -f $g.Name, $g.State, $g.OwnerNode)
        if ("$($g.State)" -eq 'Failed') { Add-Finding 'Critical' ("Role {0} is Failed" -f $g.Name) }
        elseif ("$($g.State)" -ne 'Online' -and "$($g.GroupType)" -ne 'AvailableStorage') { Add-Finding 'Warning' ("Role {0} is {1} (may be intentional)" -f $g.Name, $g.State) }
    }
}

Write-Section '3. RESOURCES'
Invoke-Check 'Resources' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $res = @(Get-ClusterResource)
    if (-not (Assert-Data $res 'Get-ClusterResource')) { return }
    $byState = $res | Group-Object State
    foreach ($s in $byState) { Write-Output ("  {0}: {1}" -f $s.Name, $s.Count) }
    foreach ($r in $res | Where-Object { "$($_.State)" -eq 'Failed' }) { Add-Finding 'Critical' ("Resource {0} ({1}) in role {2} is Failed" -f $r.Name, $r.ResourceType, $r.OwnerGroup) }
    foreach ($r in $res | Where-Object { "$($_.State)" -match 'Pending' }) { Add-Finding 'Warning' ("Resource {0} is {1}" -f $r.Name, $r.State) }
}

Write-Section '4. CLUSTER EVENTS IN THE SYSTEM LOG'
function Get-ClusterEventCount {
    param([int]$Id)
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-FailoverClustering'; Id = $Id; StartTime = (Get-Date).AddHours(-$Hours) } -ErrorAction Stop
        return @($e).Count
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return 0 }
        throw
    }
}
$events = @(
    @{ Id = 1135; Level = 'Critical'; Label = '1135: node removed from active cluster membership' },
    @{ Id = 1177; Level = 'Critical'; Label = '1177: cluster service shut down because quorum was lost' },
    @{ Id = 1146; Level = 'Warning';  Label = '1146: Resource Hosting Subsystem process terminated' },
    @{ Id = 1069; Level = 'Warning';  Label = '1069: cluster resource failed' },
    @{ Id = 5120; Level = 'Warning';  Label = '5120: Cluster Shared Volume paused after a failure' },
    @{ Id = 5142; Level = 'Warning';  Label = '5142: Cluster Shared Volume no longer accessible from this node' }
)
foreach ($ev in $events) {
    Invoke-Check $ev.Label {
        $n = Get-ClusterEventCount -Id $ev.Id
        Write-Output ("  {0}: {1}" -f $ev.Label, $n)
        if ($n -gt 0) { Add-Finding $ev.Level ("{0} event(s) in {1} hour(s): {2} (this node's System log only)" -f $n, $Hours, $ev.Label) }
    }
}

Complete-Report
exit $script:ExitCode
