<#
.SYNOPSIS
    Short performance counter snapshot with rule-of-thumb thresholds.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Samples processor, memory, paging, disk latency and queue counters, then evaluates averages. It does not create a Data Collector Set.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\performance-baseline.ps1 -Samples 12 -IntervalSeconds 5
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

Write-Output 'Windows Server performance snapshot'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC); {1} samples, {2} s apart" -f (Get-Date).ToUniversalTime(), $Samples, $IntervalSeconds)
Write-Output 'Counter names below are the English names; on a localised Windows install they may not resolve and will be reported as a warning.'

$paths = @(
    '\Processor(_Total)\% Processor Time',
    '\System\Processor Queue Length',
    '\Memory\Available MBytes',
    '\Memory\Pages/sec',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
    '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
    '\PhysicalDisk(_Total)\Current Disk Queue Length',
    '\Network Interface(*)\Output Queue Length'
)

Write-Section 'SAMPLING'
$avg = @{}
Invoke-Check 'Performance counters' {
    $s = Get-Counter -Counter $paths -SampleInterval $IntervalSeconds -MaxSamples $Samples
    if (-not (Assert-Data $s 'Get-Counter')) { return }
    foreach ($g in ($s.CounterSamples | Group-Object -Property Path)) {
        $m = ($g.Group | Measure-Object -Property CookedValue -Average -Maximum)
        $avg[$g.Name] = [pscustomobject]@{ Average = $m.Average; Maximum = $m.Maximum }
        Write-Output ("  {0}: avg {1:N2}, max {2:N2}" -f $g.Name, $m.Average, $m.Maximum)
    }
}

function Get-Avg { param([string]$Like)
    $hit = $avg.Keys | Where-Object { $_ -like $Like } | Select-Object -First 1
    if ($hit) { return $avg[$hit].Average } else { return $null }
}

Write-Section 'THRESHOLDS (rules of thumb, not Microsoft limits)'
Invoke-Check 'Threshold evaluation' {
    if ($avg.Count -eq 0) { Add-Finding 'Warning' 'No counter data to evaluate'; return }
    $cpu = Get-Avg '*processor(_total)*% processor time'
    if ($null -ne $cpu) {
        if ($cpu -ge 90) { Add-Finding 'Critical' ("Processor time averaged {0:N0} per cent" -f $cpu) }
        elseif ($cpu -ge 70) { Add-Finding 'Warning' ("Processor time averaged {0:N0} per cent" -f $cpu) }
    }
    $queue = Get-Avg '*processor queue length'
    $logical = [Environment]::ProcessorCount
    if ($null -ne $queue -and $queue -gt (2 * $logical)) { Add-Finding 'Warning' ("Processor queue length averaged {0:N1} on {1} logical processors" -f $queue, $logical) }
    $free = Get-Avg '*available mbytes'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($null -ne $free -and $os) {
        $totalMb = $os.TotalVisibleMemorySize / 1024
        $pct = 100 * $free / $totalMb
        if ($pct -lt 5) { Add-Finding 'Critical' ("Available memory averaged {0:N1} per cent of RAM" -f $pct) }
        elseif ($pct -lt 10) { Add-Finding 'Warning' ("Available memory averaged {0:N1} per cent of RAM" -f $pct) }
    }
    $pages = Get-Avg '*pages/sec'
    if ($null -ne $pages) {
        if ($pages -gt 500) { Add-Finding 'Critical' ("Pages/sec averaged {0:N0}; heavy paging" -f $pages) }
        elseif ($pages -gt 100) { Add-Finding 'Warning' ("Pages/sec averaged {0:N0}" -f $pages) }
    }
    $onq = Get-Avg '*output queue length'
    if ($null -ne $onq) {
        if ($onq -gt 4) { Add-Finding 'Critical' ("Network output queue length averaged {0:N1}" -f $onq) }
        elseif ($onq -gt 2) { Add-Finding 'Warning' ("Network output queue length averaged {0:N1}" -f $onq) }
    }
    foreach ($need in 'processor(_total)*% processor time', 'available mbytes', 'pages/sec', 'avg. disk sec/read') {
        if ($null -eq (Get-Avg ("*{0}" -f $need))) { Add-Finding 'Warning' ("No data for counter matching '{0}' (localised counter names?)" -f $need) }
    }
    foreach ($op in 'Read', 'Write') {
        $lat = Get-Avg ("*avg. disk sec/{0}" -f $op.ToLower())
        if ($null -ne $lat) {
            if ($lat -ge 0.05) { Add-Finding 'Critical' ("Disk {0} latency averaged {1:N0} ms" -f $op.ToLower(), (1000 * $lat)) }
            elseif ($lat -ge 0.02) { Add-Finding 'Warning' ("Disk {0} latency averaged {1:N0} ms" -f $op.ToLower(), (1000 * $lat)) }
        }
    }
}

Complete-Report
exit $script:ExitCode
