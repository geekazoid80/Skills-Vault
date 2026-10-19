<#
.SYNOPSIS
    Application inventory.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Lists desktop applications from the uninstall keys, packaged applications and the winget list size. With -OutputPath it writes a CSV file.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\app-inventory.ps1 -OutputPath .\apps.csv
#>
[CmdletBinding()]
param(
    [int]$Top = 25,
    [string]$OutputPath
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

Write-Output 'Windows client application inventory (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$apps = @()
Write-Section '1. INSTALLED DESKTOP APPLICATIONS (registry uninstall keys)'
Invoke-Check 'Installed applications' {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $found = Get-ItemProperty -Path $keys | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    if (-not (Assert-Data $found 'Uninstall registry keys')) { return }
    $script:apps = @($found | Sort-Object DisplayName -Unique)
    Write-Output ("  {0} applications" -f $script:apps.Count)
    $script:apps | Select-Object -First $Top | ForEach-Object { Write-Output ("  {0} {1} ({2})" -f $_.DisplayName, $_.DisplayVersion, $_.Publisher) }
    if ($script:apps.Count -gt $Top) { Write-Output ("  ... {0} more (use -OutputPath for the full list)" -f ($script:apps.Count - $Top)) }
}

Write-Section '2. PACKAGED (MSIX/Store) APPLICATIONS'
Invoke-Check 'Packaged applications' {
    $p = Get-AppxPackage
    if (-not (Assert-Data $p 'Get-AppxPackage')) { return }
    Write-Output ("  {0} packaged applications for the current user" -f @($p).Count)
}

Write-Section '3. WINGET (if installed)'
Invoke-Check 'winget' {
    $w = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $w) { Write-Output '  winget not installed'; return }
    $o = & winget list --disable-interactivity 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'winget list returned a non-zero exit code'; return }
    Write-Output ("  winget list produced {0} line(s)" -f @($o).Count)
}

if ($OutputPath) {
    Invoke-Check 'CSV output' {
        if ($script:apps.Count -eq 0) { Add-Finding 'Warning' 'No application data to write'; return }
        $script:apps | Export-Csv -LiteralPath $OutputPath -NoTypeInformation
        Write-Output ("Wrote {0}" -f $OutputPath)
    }
}

Complete-Report
exit $script:ExitCode
