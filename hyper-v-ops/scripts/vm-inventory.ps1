<#
.SYNOPSIS
    Hyper-V VM inventory and state checks.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Lists VMs with generation, configuration version, memory model, heartbeat, processor features, checkpoints and attached disks.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\vm-inventory.ps1 -CheckpointWarnDays 3
#>
[CmdletBinding()]
param(
    [int]$CheckpointWarnDays = 7
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

Write-Output 'Hyper-V VM inventory'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); checkpoint warning age {1} day(s)" -f (Get-Date).ToUniversalTime(), $CheckpointWarnDays)

Write-Section '1. VIRTUAL MACHINES'
$vms = @()
Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; Get-VM may return no VMs' }
}
Invoke-Check 'VM list' {
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-VM is not available: the Hyper-V PowerShell module is not installed here'
        return
    }
    $script:vms = @(Get-VM)
    if ($script:vms.Count -eq 0) { Add-Finding 'Warning' 'Get-VM returned no VMs (an empty host, or not elevated, or not in the Hyper-V Administrators group)'; return }
    $def = @(Get-VMHostSupportedVersion -Default)
    if ($def.Count -gt 0) { $dv = if ($def[0].PSObject.Properties['Version']) { $def[0].Version } else { $def[0].Name }; Write-Output ("  Host default configuration version: {0}" -f $dv) }
    foreach ($v in $script:vms) {
        $mem = if ($v.DynamicMemoryEnabled) { "dynamic {0:N1}/{1:N1}/{2:N1} GB (min/startup/max)" -f ($v.MemoryMinimum / 1GB), ($v.MemoryStartup / 1GB), ($v.MemoryMaximum / 1GB) } else { "static {0:N1} GB" -f ($v.MemoryStartup / 1GB) }
        Write-Output ("  {0}: state={1}, status={2}, gen={3}, config={4}, vCPU={5}, memory={6}, heartbeat={7}" -f $v.Name, $v.State, $v.Status, $v.Generation, $v.Version, $v.ProcessorCount, $mem, $v.Heartbeat)
        if ("$($v.State)" -match 'Paused|Critical') { Add-Finding 'Warning' ("VM {0} is {1} (a critical pause usually means its storage is full or offline)" -f $v.Name, $v.State) }
        if ($v.State -match 'Saved') { Add-Finding 'Warning' ("VM {0} is in a saved state" -f $v.Name) }
        if ("$($v.Status)" -match 'Critical|Degraded|Error') { Add-Finding 'Warning' ("VM {0} reports status '{1}'" -f $v.Name, $v.Status) }
        if ($v.State -eq 'Running' -and "$($v.Heartbeat)" -match 'NoContact|LostCommunication') {
            Add-Finding 'Warning' ("VM {0} is running but its heartbeat is {1} (hung guest, booting, or no integration components)" -f $v.Name, $v.Heartbeat)
        }
    }
    $gen1 = @($script:vms | Where-Object { $_.Generation -eq 1 })
    if ($gen1.Count -gt 0) { Write-Output ("  Generation 1 VMs: {0} (informational: Generation 2 is advised for new VMs)" -f $gen1.Count) }
}

Write-Section '2. PROCESSOR FEATURES'
Invoke-Check 'Processor settings' {
    if ($script:vms.Count -eq 0) { Write-Output '  nothing to check'; return }
    foreach ($v in $script:vms) {
        $p = Get-VMProcessor -VM $v
        if (-not (Assert-Data $p "Get-VMProcessor $($v.Name)")) { continue }
        Write-Output ("  {0}: compatibility mode={1}, nested virtualisation exposed={2}" -f $v.Name, $p.CompatibilityForMigrationEnabled, $p.ExposeVirtualizationExtensions)
        if ($p.ExposeVirtualizationExtensions -and $v.DynamicMemoryEnabled) {
            Write-Output ("      note: {0} has nested virtualisation and Dynamic Memory; the memory will not resize while Hyper-V runs inside it" -f $v.Name)
        }
    }
}

Write-Section '3. CHECKPOINTS'
Invoke-Check 'Checkpoints' {
    if ($script:vms.Count -eq 0) { Write-Output '  nothing to check'; return }
    $total = 0
    foreach ($v in $script:vms) {
        $snaps = @(Get-VMSnapshot -VM $v)
        if ($snaps.Count -eq 0) { continue }
        $total += $snaps.Count
        $oldest = ($snaps | Sort-Object CreationTime | Select-Object -First 1)
        $age = [math]::Round(((Get-Date) - $oldest.CreationTime).TotalDays, 1)
        Write-Output ("  {0}: {1} checkpoint(s), oldest '{2}' is {3} day(s) old" -f $v.Name, $snaps.Count, $oldest.Name, $age)
        if ($age -gt $CheckpointWarnDays) { Add-Finding 'Warning' ("VM {0} has a checkpoint {1} day(s) old (long-lived checkpoints slow I/O and make a large merge)" -f $v.Name, $age) }
    }
    if ($total -eq 0) { Write-Output '  no checkpoints' }
}

Write-Section '4. VIRTUAL DISK ATTACHMENTS'
Invoke-Check 'Disk attachments' {
    if ($script:vms.Count -eq 0) { Write-Output '  nothing to check'; return }
    foreach ($v in $script:vms) {
        $d = @(Get-VMHardDiskDrive -VM $v)
        Write-Output ("  {0}: {1} virtual disk(s) attached" -f $v.Name, $d.Count)
        foreach ($x in $d) { if ($x.Path) { Write-Output ("      {0}" -f $x.Path) } else { Write-Output ("      pass-through disk {0}" -f $x.DiskNumber) } }
    }
}

Complete-Report
exit $script:ExitCode
