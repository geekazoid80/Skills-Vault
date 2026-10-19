<#
.SYNOPSIS
    Short Hyper-V performance counter snapshot.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Samples hypervisor processor run time, Dynamic Memory pressure, virtual storage device counters and virtual switch drops, then evaluates averages. Counter names are discovered, not assumed.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\performance-snapshot.ps1 -Samples 12 -IntervalSeconds 5
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 120)] [int]$Samples = 6,
    [ValidateRange(1, 60)] [int]$IntervalSeconds = 5
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

Write-Output 'Hyper-V performance snapshot'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); {1} sample(s) every {2} second(s)" -f (Get-Date).ToUniversalTime(), $Samples, $IntervalSeconds)

# Returns averages per counter path for paths in a counter set matching a pattern. A missing set or no match is a warning.
function Get-CounterAverage {
    param([string]$SetName, [string]$Pattern, [switch]$EmptyIsOk)
    $set = Get-Counter -ListSet $SetName -ErrorAction Stop
    $paths = @($set.PathsWithInstances | Where-Object { $_ -match $Pattern })
    if ($paths.Count -eq 0) {
        if (-not $EmptyIsOk) { Add-Finding 'Warning' ("No counters matching '{0}' in set '{1}' (names vary by build)" -f $Pattern, $SetName) }
        return @()
    }
    $s = Get-Counter -Counter $paths -SampleInterval $IntervalSeconds -MaxSamples $Samples -ErrorAction Stop
    $out = @()
    foreach ($g in ($s.CounterSamples | Group-Object Path)) {
        $avg = ($g.Group | Measure-Object -Property CookedValue -Average).Average
        $out += [pscustomobject]@{ Path = $g.Name; Average = [math]::Round($avg, 2) }
    }
    return $out
}

Write-Section '1. HOST PROCESSOR (hypervisor view)'
Invoke-Check 'Logical processor run time' {
    $a = @(Get-CounterAverage -SetName 'Hyper-V Hypervisor Logical Processor' -Pattern '\(_Total\)\\% (Total|Guest|Hypervisor) Run Time$')
    if (-not (Assert-Data $a 'Hyper-V Hypervisor Logical Processor counters')) { return }
    foreach ($x in $a) { Write-Output ("  {0} = {1}" -f $x.Path, $x.Average) }
    $total = $a | Where-Object { $_.Path -match 'Total Run Time' } | Select-Object -First 1
    $hyp = $a | Where-Object { $_.Path -match 'Hypervisor Run Time' } | Select-Object -First 1
    if ($total -and $total.Average -gt 90) { Add-Finding 'Warning' ("Host processors average {0}% total run time (saturation)" -f $total.Average) }
    if ($hyp -and $hyp.Average -gt 10) { Add-Finding 'Warning' ("Hypervisor run time averages {0}% (heavy exits: emulation, timers, nested virtualisation, or overload)" -f $hyp.Average) }
}

Write-Section '2. DYNAMIC MEMORY PRESSURE'
Invoke-Check 'Memory pressure' {
    $a = @(Get-CounterAverage -SetName 'Hyper-V Dynamic Memory VM' -Pattern '\\Current Pressure$' -EmptyIsOk)
    if ($a.Count -eq 0) { Write-Output '  no Dynamic Memory VMs reported'; return }
    foreach ($x in $a | Where-Object { $_.Path -notmatch '_total' }) {
        Write-Output ("  {0} = {1}" -f $x.Path, $x.Average)
        if ($x.Average -gt 150) { Add-Finding 'Critical' ("Memory pressure {0} on {1} (guest likely paging)" -f $x.Average, $x.Path) }
        elseif ($x.Average -gt 100) { Add-Finding 'Warning' ("Memory pressure {0} on {1} (VM wants more memory than it has)" -f $x.Average, $x.Path) }
    }
}

Write-Section '3. VIRTUAL STORAGE DEVICES (printed without thresholds)'
Invoke-Check 'Virtual storage' {
    $a = @(Get-CounterAverage -SetName 'Hyper-V Virtual Storage Device' -Pattern '\\(Latency|Queue Length)$')
    if (-not (Assert-Data $a 'Hyper-V Virtual Storage Device latency or queue counters')) { return }
    foreach ($x in $a) { Write-Output ("  {0} = {1}" -f $x.Path, $x.Average) }
    Write-Output '  (units for these counters are not confirmed; compare disks with each other and over time)'
}

Write-Section '4. VIRTUAL SWITCH DROPPED PACKETS'
Invoke-Check 'Dropped packets' {
    $a = @(Get-CounterAverage -SetName 'Hyper-V Virtual Switch' -Pattern '\\Dropped[^\\]*$')
    if (-not (Assert-Data $a 'Hyper-V Virtual Switch dropped-packet counters')) { return }
    $bad = @($a | Where-Object { $_.Average -gt 0 })
    Write-Output ("  {0} dropped-packet counter(s) sampled; {1} with a non-zero average" -f $a.Count, $bad.Count)
    foreach ($b in $bad | Select-Object -First 5) { Write-Output ("      {0} = {1}" -f $b.Path, $b.Average) }
    if ($bad.Count -gt 0) { Add-Finding 'Warning' ("{0} virtual switch dropped-packet counter(s) average above zero" -f $bad.Count) }
}

Complete-Report
exit $script:ExitCode
