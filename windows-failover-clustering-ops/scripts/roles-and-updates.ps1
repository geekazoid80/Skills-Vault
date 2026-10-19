<#
.SYNOPSIS
    Role placement, failover policy and Cluster-Aware Updating.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reads role owners and failover policy, and the CAU self-updating role and last report without starting a scan or a run.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on a cluster node (or a machine with the Failover Clustering tools and rights to the cluster).
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\roles-and-updates.ps1
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

Write-Output 'Failover cluster role placement and Cluster-Aware Updating (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:ClOk = $false
$script:ClName = $null
Invoke-Check 'Cluster access' {
    if (-not (Get-Command Get-Cluster -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-Cluster is not available: the Failover Clustering PowerShell module is not installed here'
        return
    }
    $c = Get-Cluster
    if (-not (Assert-Data $c 'Get-Cluster')) { return }
    $script:ClOk = $true
    $script:ClName = $c.Name
    Write-Output ("  Cluster: {0}" -f $c.Name)
}
if (-not $script:ClOk) { Add-Finding 'Critical' 'Could not reach a cluster from this host; run this on a cluster node or a machine with the clustering tools and rights' }

Write-Section '1. ROLE PLACEMENT AND FAILOVER POLICY'
Invoke-Check 'Role placement' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    $all = @(Get-ClusterGroup)
    if (-not (Assert-Data $all 'Get-ClusterGroup')) { return }
    $groups = @($all | Where-Object { $_.GroupType -ne 'Cluster' -and $_.GroupType -ne 'AvailableStorage' })
    if ($groups.Count -eq 0) { Write-Output '  no clustered roles other than the core groups'; return }
    foreach ($g in $groups) {
        $anti = ($g.AntiAffinityClassNames | ForEach-Object { $_ }) -join ','
        Write-Output ("  {0}: type={1}, owner={2}, state={3}, failover threshold={4} per {5} h, failback={6}, anti-affinity='{7}'" -f $g.Name, $g.GroupType, $g.OwnerNode, $g.State, $g.FailoverThreshold, $g.FailoverPeriod, $g.AutoFailbackType, $anti)
    }
    $byNode = $groups | Group-Object { "$($_.OwnerNode)" }
    foreach ($n in $byNode) { Write-Output ("  roles on {0}: {1}" -f $n.Name, $n.Count) }
    $nodes = @(Get-ClusterNode)
    if ($nodes.Count -ge 3 -and $groups.Count -ge 4) {
        $max = ($byNode | Measure-Object -Property Count -Maximum).Maximum
        if ($max -gt ($groups.Count * 0.7)) { Add-Finding 'Warning' ("One node hosts {0} of {1} roles; check placement and N+1 capacity" -f $max, $groups.Count) }
    }
}

Write-Section '2. CLUSTER-AWARE UPDATING (read only; no scan is started)'
Invoke-Check 'CAU self-updating role' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    if (-not (Get-Command Get-CauClusterRole -ErrorAction SilentlyContinue)) { Add-Finding 'Warning' 'The Cluster-Aware Updating module is not available here'; return }
    try {
        $role = Get-CauClusterRole -ClusterName $script:ClName -ErrorAction Stop
        if ($role) { Write-Output ("  Self-updating role present: {0}" -f (($role | Format-List | Out-String).Trim())) }
        else { Add-Finding 'Warning' 'No CAU self-updating role was returned (clusters updated in remote-updating mode have none; otherwise patching is not automated)' }
    } catch {
        Add-Finding 'Warning' ("The CAU self-updating role could not be read: {0} (a cluster updated in remote-updating mode has none)" -f $_.Exception.Message)
    }
}
Invoke-Check 'CAU last run' {
    if (-not $script:ClOk) { Write-Output '  skipped: no cluster'; return }
    if (-not (Get-Command Get-CauReport -ErrorAction SilentlyContinue)) { return }
    try {
        $rep = Get-CauReport -ClusterName $script:ClName -Last -ErrorAction Stop
        if ($rep) { Write-Output ("  Last CAU report: {0}" -f (($rep | Format-List | Out-String).Trim())) }
        else { Add-Finding 'Warning' 'No CAU report was returned (no run has completed, or the query returned nothing)' }
    } catch {
        Add-Finding 'Warning' ("The last CAU report could not be read: {0}" -f $_.Exception.Message)
    }
    Write-Output '  Per-node update recency is not evaluated here; use the windows-server-ops update-and-backup-status script on each node.'
}

Complete-Report
exit $script:ExitCode
