<#
.SYNOPSIS
    Device problems, unsigned drivers, display driver and GPU timeout events.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports devices with a problem status, drivers that report as unsigned, display driver versions and event 4101 counts.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\driver-health.ps1 -Days 14
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 90)] [int]$Days = 7
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

Write-Output 'Windows client driver and device health (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. DEVICES WITH PROBLEMS'
Invoke-Check 'Problem devices' {
    $all = Get-PnpDevice
    if (-not (Assert-Data $all 'Get-PnpDevice')) { return }
    $bad = @($all | Where-Object { $_.Present -and ($_.Status -in 'Error', 'Degraded' -or $_.ConfigManagerErrorCode -gt 0) })
    foreach ($d in $bad) { Write-Output ("  {0} [{1}] status={2} error code={3} ({4})" -f $d.FriendlyName, $d.Class, $d.Status, $d.ConfigManagerErrorCode, $d.Problem) }
    if ($bad.Count -gt 0) { Add-Finding 'Warning' ("{0} present device(s) report a problem status" -f $bad.Count) } else { Write-Output '  none' }
}

Write-Section '2. UNSIGNED DRIVERS'
Invoke-Check 'Driver signing' {
    $d = Get-CimInstance -ClassName Win32_PnPSignedDriver
    if (-not (Assert-Data $d 'Win32_PnPSignedDriver')) { return }
    $u = @($d | Where-Object { $_.DeviceName -and $_.IsSigned -eq $false })
    foreach ($x in $u) { Write-Output ("  {0} {1} ({2})" -f $x.DeviceName, $x.DriverVersion, $x.InfName) }
    if ($u.Count -gt 0) { Add-Finding 'Warning' ("{0} driver(s) report an unsigned status" -f $u.Count) } else { Write-Output '  none reported' }
    Write-Output '  note: a signed driver can still be incompatible with HVCI; test that separately in audit mode.'
}

Write-Section '3. DISPLAY DRIVER AND GPU RESETS'
Invoke-Check 'Display driver' {
    $g = Get-CimInstance -ClassName Win32_VideoController
    if (-not (Assert-Data $g 'Win32_VideoController')) { return }
    foreach ($x in $g) { Write-Output ("  {0}: driver {1} dated {2:yyyy-MM-dd}" -f $x.Name, $x.DriverVersion, $x.DriverDate) }
}
Invoke-Check 'GPU timeout events' {
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction Stop
        $n = @($e).Count
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $n = 0 } else { throw }
    }
    Write-Output ("  display driver timeout (event 4101) in {0} day(s): {1}" -f $Days, $n)
    if ($n -gt 0) { Add-Finding 'Warning' ("{0} display driver timeout event(s) in {1} day(s)" -f $n, $Days) }
}

Write-Section '4. DRIVER STORE'
Invoke-Check 'Driver store' {
    $o = & pnputil /enum-drivers 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'pnputil /enum-drivers failed'; return }
    $count = @($o | Where-Object { $_ -match 'Published Name' }).Count
    Write-Output ("  third-party driver packages in the driver store: {0}" -f $count)
}

Complete-Report
exit $script:ExitCode
