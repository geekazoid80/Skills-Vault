<#
.SYNOPSIS
    Windows Server health summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers operating system, edition, load, automatic services that stopped, roles, pending reboot and time synchronisation.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\server-health.ps1 -MaxUptimeDays 60
#>
[CmdletBinding()]
param(
    [int]$MaxUptimeDays = 90
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

Write-Output 'Windows Server health report'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())
Write-Output ("Host:      {0}" -f $env:COMPUTERNAME)

Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; some queries may be incomplete' }
}

Write-Section '1. OPERATING SYSTEM'
Invoke-Check 'Operating system' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not (Assert-Data $os 'Win32_OperatingSystem')) { return }
    $up = (Get-Date) - $os.LastBootUpTime
    Write-Output ("{0}, version {1}, build {2}" -f $os.Caption, $os.Version, $os.BuildNumber)
    Write-Output ("Last boot: {0:yyyy-MM-dd HH:mm} ({1:N1} days ago)" -f $os.LastBootUpTime, $up.TotalDays)
    $memPct = [math]::Round(100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize, 1)
    Write-Output ("Memory in use: {0}%" -f $memPct)
    if ($memPct -ge 90) { Add-Finding 'Warning' "Memory in use at $memPct per cent" }
    if ($up.TotalDays -gt $MaxUptimeDays) { Add-Finding 'Warning' ("No reboot for {0:N0} days; check for pending updates" -f $up.TotalDays) }
}

Write-Section '2. EDITION AND INSTALL TYPE'
Invoke-Check 'Edition' {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if (-not (Assert-Data $cv 'CurrentVersion registry key')) { return }
    Write-Output ("EditionID: {0}; InstallationType: {1}; build revision: {2}" -f $cv.EditionID, $cv.InstallationType, $cv.UBR)
}

Write-Section '3. PROCESSOR'
Invoke-Check 'Processor' {
    $cpu = Get-CimInstance -ClassName Win32_Processor
    if (-not (Assert-Data $cpu 'Win32_Processor')) { return }
    $load = ($cpu | Where-Object { $null -ne $_.LoadPercentage } | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $load) { Add-Finding 'Warning' 'Processor load percentage was not reported'; return }
    Write-Output ("{0} socket(s), {1} logical processor(s), load {2}%" -f @($cpu).Count, ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum, $load)
    if ($load -ge 90) { Add-Finding 'Warning' "Processor load at $load per cent" }
}

Write-Section '4. SERVICES SET TO AUTOMATIC BUT NOT RUNNING (non-zero exit code)'
Invoke-Check 'Services' {
    $all = Get-CimInstance -ClassName Win32_Service
    if (-not (Assert-Data $all 'Win32_Service')) { return }
    # ExitCode 1077 means never started (delayed or trigger-start services), which is normal and excluded.
    $bad = @($all | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' -and $_.ExitCode -ne 0 -and $_.ExitCode -ne 1077 })
    foreach ($s in $bad) { Write-Output ("  {0} ({1}) state={2} exit={3}" -f $s.Name, $s.DisplayName, $s.State, $s.ExitCode) }
    if ($bad.Count -gt 0) { Add-Finding 'Warning' ("{0} automatic service(s) stopped with a non-zero exit code" -f $bad.Count) }
    else { Write-Output '  none' }
}

Write-Section '5. INSTALLED ROLES AND FEATURES'
Invoke-Check 'Roles and features' {
    if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { Add-Finding 'Warning' 'Get-WindowsFeature is not available (not Windows Server, or ServerManager module missing)'; return }
    $f = Get-WindowsFeature | Where-Object { $_.Installed }
    if (-not (Assert-Data $f 'Get-WindowsFeature')) { return }
    Write-Output ("{0} role/feature entries installed" -f @($f).Count)
    $f | Where-Object { $_.FeatureType -eq 'Role' } | ForEach-Object { Write-Output ("  role: {0}" -f $_.Name) }
}

Write-Section '6. PENDING REBOOT'
Invoke-Check 'Pending reboot' {
    $flags = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $flags += 'Component Based Servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $flags += 'Windows Update' }
    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop).PendingFileRenameOperations
    if ($pfro) { $flags += 'PendingFileRenameOperations' }
    if ($flags.Count -gt 0) {
        Write-Output ("Reboot pending: {0}" -f ($flags -join ', '))
        Add-Finding 'Warning' ("Reboot pending ({0})" -f ($flags -join ', '))
    } else { Write-Output 'No pending reboot flags set' }
}

Write-Section '7. TIME SYNCHRONISATION'
Invoke-Check 'Time service' {
    $out = & w32tm /query /status 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'w32tm /query /status failed (time service stopped?)'; return }
    $lines = @($out | Where-Object { $_ -match 'Source|Last Successful Sync Time|Stratum' })
    if ($lines.Count -eq 0) { Add-Finding 'Warning' 'w32tm output was not recognised (the labels are English; localised systems need a manual check)'; return }
    $lines | ForEach-Object { Write-Output "  $_" }
    if (($out -join "`n") -match 'Local CMOS Clock|Free-running') { Add-Finding 'Warning' 'Time source is the local clock (not synchronised to an external source)' }
}

Complete-Report
exit $script:ExitCode
