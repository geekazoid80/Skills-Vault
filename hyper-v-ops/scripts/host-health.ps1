<#
.SYNOPSIS
    Hyper-V host health summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers the Hyper-V services, hypervisor state, host settings, processor and memory allocation, NUMA nodes and recent Hyper-V event log errors.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\host-health.ps1 -Hours 48
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 720)] [int]$Hours = 24,
    [double]$MaxVcpuRatio = 4
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

Write-Output 'Hyper-V host health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); event window {1} hour(s)" -f (Get-Date).ToUniversalTime(), $Hours)

$script:HvOk = $false

Write-Section '1. ROLE, SERVICES AND HYPERVISOR'
Invoke-Check 'Hyper-V module' {
    if (-not (Get-Command Get-VMHost -ErrorAction SilentlyContinue)) {
        Add-Finding 'Critical' 'Get-VMHost is not available: the Hyper-V role or its PowerShell module is not installed here'
        return
    }
    $script:HvOk = $true
    Write-Output '  Hyper-V module present'
}
Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; Hyper-V cmdlets may return nothing or fail' }
}
Invoke-Check 'Hyper-V services' {
    $svc = @(Get-Service -Name vmms, vmcompute)
    if (-not (Assert-Data $svc 'Get-Service vmms, vmcompute')) { return }
    foreach ($s in $svc) {
        Write-Output ("  {0}: {1} ({2})" -f $s.Name, $s.Status, $s.StartType)
        if ($s.Status -ne 'Running') { Add-Finding 'Critical' ("Service {0} is {1}" -f $s.Name, $s.Status) }
    }
}
Invoke-Check 'Hypervisor present' {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if (-not (Assert-Data $cs 'Win32_ComputerSystem')) { return }
    Write-Output ("  HypervisorPresent: {0}" -f $cs.HypervisorPresent)
    if (-not $cs.HypervisorPresent) { Add-Finding 'Critical' 'The hypervisor is not running (check firmware virtualisation support and the hypervisorlaunchtype boot setting)' }
}

Write-Section '2. HOST CONFIGURATION'
Invoke-Check 'Host configuration' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $h = Get-VMHost
    if (-not (Assert-Data $h 'Get-VMHost')) { return }
    Write-Output ("  Host: {0}; logical processors: {1}; memory: {2:N1} GB" -f $h.ComputerName, $h.LogicalProcessorCount, ($h.MemoryCapacity / 1GB))
    Write-Output ("  NUMA spanning enabled: {0}" -f $h.NumaSpanningEnabled)
    Write-Output ("  Default VM path: {0}" -f $h.VirtualMachinePath)
    Write-Output ("  Default VHD path: {0}" -f $h.VirtualHardDiskPath)
    $def = @(Get-VMHostSupportedVersion -Default)
    if ($def.Count -gt 0) { $dv = if ($def[0].PSObject.Properties['Version']) { $def[0].Version } else { $def[0].Name }; Write-Output ("  Default VM configuration version: {0}" -f $dv) }
    else { Add-Finding 'Warning' 'Get-VMHostSupportedVersion -Default returned nothing' }
    if ($h.VirtualMachinePath -match '^[A-Za-z]:') {
        $drive = $h.VirtualMachinePath.Substring(0, 2)
        $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive)
        if (Assert-Data $vol "Win32_LogicalDisk $drive") {
            $free = [math]::Round(100 * $vol.FreeSpace / $vol.Size, 1)
            Write-Output ("  Free space on {0}: {1}%" -f $drive, $free)
            if ($free -lt 10) { Add-Finding 'Critical' ("Default VM path volume {0} has {1}% free" -f $drive, $free) }
            elseif ($free -lt 20) { Add-Finding 'Warning' ("Default VM path volume {0} has {1}% free" -f $drive, $free) }
        }
    } else { Write-Output '  default VM path is not a local drive letter; free space not checked' }
}

Write-Section '3. CAPACITY'
Invoke-Check 'CPU and memory allocation' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $h = Get-VMHost
    if (-not (Assert-Data $h 'Get-VMHost')) { return }
    $vms = @(Get-VM)
    if ($vms.Count -eq 0) { Add-Finding 'Warning' 'Get-VM returned no VMs (an empty host, or not elevated, or not in the Hyper-V Administrators group)'; return }
    $running = @($vms | Where-Object { $_.State -eq 'Running' })
    $vcpu = [int](($running | Measure-Object -Property ProcessorCount -Sum).Sum)
    $ratio = [math]::Round($vcpu / [double]$h.LogicalProcessorCount, 2)
    Write-Output ("  VMs: {0} ({1} running); virtual processors on running VMs: {2}; ratio to logical processors: {3}:1" -f $vms.Count, $running.Count, $vcpu, $ratio)
    if ($ratio -gt $MaxVcpuRatio) { Add-Finding 'Warning' ("Virtual to logical processor ratio is {0}:1, above the {1}:1 planning ceiling (a rule of thumb; check hypervisor run time)" -f $ratio, $MaxVcpuRatio) }
    $potential = 0
    foreach ($v in $vms) {
        if ($v.DynamicMemoryEnabled) { $potential += $v.MemoryMaximum } else { $potential += $v.MemoryStartup }
    }
    $hostGb = $h.MemoryCapacity / 1GB
    $potGb = [math]::Round($potential / 1GB, 1)
    Write-Output ("  Memory the VMs could claim (maximum for Dynamic Memory VMs, startup otherwise): {0} GB of {1:N1} GB" -f $potGb, $hostGb)
    if ($potGb -gt ($hostGb - 2)) { Add-Finding 'Warning' ("VMs could claim {0} GB against {1:N1} GB of host memory; overcommit risks Smart Paging and host paging" -f $potGb, $hostGb) }
    $nodes = @(Get-VMHostNumaNode)
    if (Assert-Data $nodes 'Get-VMHostNumaNode') {
        foreach ($n in $nodes) { Write-Output ("  NUMA node {0}: memory total {1}, available {2} (raw values; the unit is not stated in the cmdlet reference)" -f $n.NodeId, $n.MemoryTotal, $n.MemoryAvailable) }
    }
}

Write-Section '4. HYPER-V EVENT LOGS (errors and warnings)'
function Get-LogProblemCount {
    param([string]$LogName)
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = $LogName; Level = 1, 2, 3; StartTime = (Get-Date).AddHours(-$Hours) } -ErrorAction Stop
        return @($e)
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @() }
        throw
    }
}
$logs = @('Microsoft-Windows-Hyper-V-VMMS-Admin', 'Microsoft-Windows-Hyper-V-Worker-Admin', 'Microsoft-Windows-Hyper-V-Hypervisor-Admin', 'Microsoft-Windows-Hyper-V-VID-Admin')
foreach ($l in $logs) {
    Invoke-Check ("Event log " + $l) {
        $ev = @(Get-LogProblemCount -LogName $l)
        Write-Output ("  {0}: {1} error/warning event(s)" -f $l, $ev.Count)
        if ($ev.Count -gt 0) {
            $top = $ev | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 3
            foreach ($t in $top) { Write-Output ("      event {0}: {1}" -f $t.Name, $t.Count) }
            Add-Finding 'Warning' ("{0} error or warning event(s) in {1} within {2} hour(s)" -f $ev.Count, $l, $Hours)
        }
    }
}

Complete-Report
exit $script:ExitCode
