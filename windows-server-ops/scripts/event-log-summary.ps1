<#
.SYNOPSIS
    Counts of significant events and event log sizes.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Counts unexpected restarts, service failures, new services, log-cleared events, application crashes, failed logons and lockouts.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\event-log-summary.ps1 -Days 14
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 90)] [int]$Days = 7,
    [int]$FailedLogonWarn = 50
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

Write-Output 'Windows Server event log summary'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC); window {1} day(s)" -f (Get-Date).ToUniversalTime(), $Days)

Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; the Security log cannot be read, so logon and log-cleared checks are incomplete' }
}

function Get-EventCount {
    param([string]$LogName, [int[]]$Id)
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $Id; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction Stop
        return @($e).Count
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return 0 }
        throw
    }
}

$checks = @(
    @{ Log = 'System';   Id = 41;   Label = 'Kernel-Power 41: unexpected restart';                  Level = 'Warning' },
    @{ Log = 'System';   Id = 6008; Label = '6008: previous shutdown was unexpected';              Level = 'Warning' },
    @{ Log = 'System';   Id = 7034; Label = '7034: service terminated unexpectedly';               Level = 'Warning' },
    @{ Log = 'System';   Id = 7045; Label = '7045: new service installed (review each one)';       Level = 'Warning' },
    @{ Log = 'System';   Id = 104;  Label = '104: System event log cleared';                       Level = 'Critical' },
    @{ Log = 'Application'; Id = 1000; Label = '1000: application crash';                          Level = 'Warning' },
    @{ Log = 'Security'; Id = 1102; Label = '1102: Security event log cleared';                    Level = 'Critical' },
    @{ Log = 'Security'; Id = 4740; Label = '4740: account locked out';                            Level = 'Warning' }
)

Write-Section 'EVENT COUNTS'
foreach ($c in $checks) {
    Invoke-Check $c.Label {
        $n = Get-EventCount -LogName $c.Log -Id $c.Id
        Write-Output ("  {0}: {1}" -f $c.Label, $n)
        if ($n -gt 0) { Add-Finding $c.Level ("{0} event(s) in {1} day(s): {2}" -f $n, $Days, $c.Label) }
    }
}
Invoke-Check '4625 failed logons' {
    $n = Get-EventCount -LogName 'Security' -Id 4625
    Write-Output ("  4625: failed logons: {0}" -f $n)
    if ($n -ge $FailedLogonWarn) { Add-Finding 'Warning' ("{0} failed logons in {1} day(s) (threshold {2}); review source addresses" -f $n, $Days, $FailedLogonWarn) }
}

Write-Section 'EVENT LOG SIZES (CIS-aligned examples: Security 196608 KB, System and Application 32768 KB)'
Invoke-Check 'Event log sizes' {
    $logs = Get-WinEvent -ListLog Security, System, Application
    if (-not (Assert-Data $logs 'Get-WinEvent -ListLog')) { return }
    foreach ($l in $logs) {
        Write-Output ("  {0}: {1:N0} KB maximum, {2} mode" -f $l.LogName, ($l.MaximumSizeInBytes / 1KB), $l.LogMode)
        $want = if ($l.LogName -eq 'Security') { 196608KB } else { 32768KB }
        if ($l.MaximumSizeInBytes -lt $want) { Add-Finding 'Warning' ("{0} log maximum is below {1:N0} KB" -f $l.LogName, ($want / 1KB)) }
    }
}

Complete-Report
exit $script:ExitCode
