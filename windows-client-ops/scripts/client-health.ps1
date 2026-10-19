<#
.SYNOPSIS
    Windows client health summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers build, hardware, memory, processor, volumes, disk health, top processes and battery.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\client-health.ps1
#>
[CmdletBinding()]
param(
    [int]$MaxUptimeDays = 30
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

Write-Output 'Windows client health report'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())
Write-Output ("Host:      {0}" -f $env:COMPUTERNAME)

Write-Section '1. SYSTEM'
Invoke-Check 'Operating system' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not (Assert-Data $os 'Win32_OperatingSystem')) { return }
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $up = (Get-Date) - $os.LastBootUpTime
    Write-Output ("{0}, build {1}.{2}, display version {3}, edition {4}" -f $os.Caption, $os.BuildNumber, $cv.UBR, $cv.DisplayVersion, $cv.EditionID)
    Write-Output ("Last boot: {0:yyyy-MM-dd HH:mm} ({1:N1} days ago)" -f $os.LastBootUpTime, $up.TotalDays)
    if ($up.TotalDays -gt $MaxUptimeDays) { Add-Finding 'Warning' ("No restart for {0:N0} days; updates may be waiting" -f $up.TotalDays) }
}
Invoke-Check 'Hardware summary' {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    if (-not (Assert-Data $cs 'Win32_ComputerSystem')) { return }
    Write-Output ("{0} {1}; RAM {2:N1} GB; BIOS {3} ({4})" -f $cs.Manufacturer, $cs.Model, ($cs.TotalPhysicalMemory / 1GB), $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
}

Write-Section '2. MEMORY, CPU AND DISK'
Invoke-Check 'Memory and CPU' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = Get-CimInstance -ClassName Win32_Processor
    if (-not (Assert-Data $os 'Win32_OperatingSystem') -or -not (Assert-Data $cpu 'Win32_Processor')) { return }
    $mem = [math]::Round(100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize, 1)
    $load = ($cpu | Where-Object { $null -ne $_.LoadPercentage } | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $load) { Add-Finding 'Warning' 'Processor load percentage was not reported'; return }
    Write-Output ("Memory in use {0}%; processor load {1}%" -f $mem, $load)
    if ($mem -ge 90) { Add-Finding 'Warning' "Memory in use at $mem per cent" }
    if ($load -ge 90) { Add-Finding 'Warning' "Processor load at $load per cent" }
}
Invoke-Check 'Fixed volumes' {
    $v = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }
    if (-not (Assert-Data $v 'Get-Volume')) { return }
    foreach ($x in $v) {
        $free = [math]::Round(100 * $x.SizeRemaining / $x.Size, 1)
        Write-Output ("  {0}: {1:N0} GB, {2}% free, health={3}" -f $x.DriveLetter, ($x.Size / 1GB), $free, $x.HealthStatus)
        if ($free -lt 10) { Add-Finding 'Critical' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
        elseif ($free -lt 20) { Add-Finding 'Warning' ("Volume {0}: {1}% free" -f $x.DriveLetter, $free) }
    }
}
Invoke-Check 'Physical disk health' {
    $d = Get-PhysicalDisk
    if (-not (Assert-Data $d 'Get-PhysicalDisk')) { return }
    foreach ($x in $d) {
        Write-Output ("  {0}: {1}, health={2}" -f $x.FriendlyName, $x.MediaType, $x.HealthStatus)
        if ($x.HealthStatus -ne 'Healthy') { Add-Finding 'Critical' ("Physical disk {0} health is {1}" -f $x.FriendlyName, $x.HealthStatus) }
    }
}

Write-Section '3. TOP PROCESSES BY MEMORY'
Invoke-Check 'Processes' {
    $p = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8
    if (-not (Assert-Data $p 'Get-Process')) { return }
    $p | ForEach-Object { Write-Output ("  {0} (id {1}): {2:N0} MB" -f $_.ProcessName, $_.Id, ($_.WorkingSet64 / 1MB)) }
}

Write-Section '4. BATTERY (laptops)'
Invoke-Check 'Battery' {
    $b = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if (-not $b) { Write-Output '  no battery reported'; return }
    foreach ($x in $b) { Write-Output ("  charge {0}%, status {1}" -f $x.EstimatedChargeRemaining, $x.BatteryStatus) }
}

Complete-Report
exit $script:ExitCode
