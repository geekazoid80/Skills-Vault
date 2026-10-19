<#
.SYNOPSIS
    Live migration settings and Hyper-V Replica health.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports migration enablement, authentication, transport, named migration networks, processor compatibility and replication state, health and lag.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\replication-and-migration.ps1
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

Write-Output 'Hyper-V live migration settings and Replica health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:HvOk = [bool](Get-Command Get-VMHost -ErrorAction SilentlyContinue)
if (-not $script:HvOk) { Add-Finding 'Critical' 'Get-VMHost is not available: the Hyper-V PowerShell module is not installed here' }

Write-Section '1. LIVE MIGRATION SETTINGS'
Invoke-Check 'Live migration' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $h = Get-VMHost
    if (-not (Assert-Data $h 'Get-VMHost')) { return }
    Write-Output ("  Enabled: {0}; authentication: {1}; transport option: {2}; simultaneous migrations: {3}; storage migrations: {4}" -f $h.VirtualMachineMigrationEnabled, $h.VirtualMachineMigrationAuthenticationType, $h.VirtualMachineMigrationPerformanceOption, $h.MaximumVirtualMachineMigrations, $h.MaximumStorageMigrations)
    Write-Output ("  Use any network for migration: {0}" -f $h.UseAnyNetworkForMigration)
    $nets = @(Get-VMMigrationNetwork)
    if ($nets.Count -eq 0) { Write-Output '  no migration networks named' }
    foreach ($n in $nets) { Write-Output ("  migration network: {0}, priority {1}" -f $n.Subnet, $n.Priority) }
    if ($h.VirtualMachineMigrationEnabled -and $h.UseAnyNetworkForMigration) {
        Add-Finding 'Warning' 'Live migration may use any network (the default); name a dedicated migration network so it does not use the management network'
    }
    if ($h.VirtualMachineMigrationEnabled -and "$($h.VirtualMachineMigrationAuthenticationType)" -eq 'CredSSP') {
        Add-Finding 'Warning' 'Live migration authentication is CredSSP; Kerberos with constrained delegation is the usual choice on domain-joined hosts'
    }
}
Invoke-Check 'Processor compatibility' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $vms = @(Get-VM)
    if ($vms.Count -eq 0) { Add-Finding 'Warning' 'Get-VM returned no VMs (an empty host, or not elevated, or not in the Hyper-V Administrators group)'; return }
    $without = @()
    foreach ($v in $vms) {
        $p = Get-VMProcessor -VM $v
        if ($p -and -not $p.CompatibilityForMigrationEnabled) { $without += $v.Name }
    }
    Write-Output ("  VMs without processor compatibility mode: {0} of {1} (informational; needed only when hosts differ in CPU generation)" -f $without.Count, $vms.Count)
}

Write-Section '2. HYPER-V REPLICA SERVER'
Invoke-Check 'Replica server' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $r = Get-VMReplicationServer
    if (-not (Assert-Data $r 'Get-VMReplicationServer')) { return }
    Write-Output ("  Replication enabled as replica server: {0}; allowed authentication: {1}" -f $r.ReplicationEnabled, $r.AllowedAuthenticationType)
}

Write-Section '3. REPLICATION RELATIONSHIPS'
Invoke-Check 'Replication health' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $reps = @(Get-VMReplication)
    if ($reps.Count -eq 0) { Write-Output '  no replication relationships on this host'; return }
    foreach ($r in $reps) {
        $freq = $null
        if ($r.FrequencySec) { $freq = [int]$r.FrequencySec } elseif ($r.ReplicationFrequencySec) { $freq = [int]$r.ReplicationFrequencySec }
        $last = $r.LastReplicationTime
        $lag = $null
        if ($last -and $last -gt [datetime]'2000-01-01') { $lag = [math]::Round(((Get-Date) - $last).TotalSeconds) }
        Write-Output ("  {0}: state={1}, health={2}, mode={3}, interval={4}s, last replication={5}" -f $r.VMName, $r.State, $r.Health, $r.Mode, $freq, $last)
        if ("$($r.Health)" -eq 'Critical') { Add-Finding 'Critical' ("Replication for {0} is Critical (state {1})" -f $r.VMName, $r.State) }
        elseif ("$($r.Health)" -ne 'Normal') { Add-Finding 'Warning' ("Replication for {0} health is {1} (state {2})" -f $r.VMName, $r.Health, $r.State) }
        if ("$($r.State)" -match 'Error|Suspended|Resynchroniz') { Add-Finding 'Warning' ("Replication for {0} is in state {1}" -f $r.VMName, $r.State) }
        if ("$($r.State)" -eq 'Replicating') {
            if ($null -eq $lag) { Add-Finding 'Warning' ("Replication for {0} is Replicating but has no last replication time" -f $r.VMName) }
            elseif ($null -eq $freq) { Add-Finding 'Warning' ("Replication for {0}: the replication interval was not returned, so lag was not evaluated (last replication {1})" -f $r.VMName, $last) }
            elseif ($lag -gt (2 * $freq)) { Add-Finding 'Warning' ("Replication for {0} last ran {1}s ago, more than twice its {2}s interval" -f $r.VMName, $lag, $freq) }
        }
    }
}

Complete-Report
exit $script:ExitCode
