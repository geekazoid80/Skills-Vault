<#
.SYNOPSIS
    Windows 11 hardware readiness check.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Checks 64-bit, cores, clock, RAM, boot disk size and style, Secure Boot and TPM 2.0. It does not check the approved CPU list.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\windows11-readiness.ps1
#>
[CmdletBinding()]
param(

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

Write-Output 'Windows 11 readiness check (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())
Write-Output 'Requirements checked: 64-bit, 2+ cores at 1 GHz or faster, 4 GB RAM, 64 GB storage, UEFI with Secure Boot, TPM 2.0. The approved-CPU check is NOT done here; confirm the CPU against the Microsoft processor list or the PC Health Check app.'

Write-Section 'CHECKS'
Invoke-Check 'Processor' {
    $c = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    if (-not (Assert-Data $c 'Win32_Processor')) { return }
    $cores = ($c | Measure-Object -Property NumberOfCores -Sum).Sum
    Write-Output ("  CPU: {0}; {1} core(s); max {2} MHz; architecture code {3} (9 x64, 12 ARM64)" -f $c.Name, $cores, $c.MaxClockSpeed, $c.Architecture)
    if ($c.Architecture -notin 9, 12) { Add-Finding 'Critical' 'Processor architecture is not 64-bit x64 or ARM64' }
    if ($cores -lt 2) { Add-Finding 'Critical' 'Fewer than two processor cores' }
    if ($c.MaxClockSpeed -lt 1000) { Add-Finding 'Critical' 'Processor is slower than 1 GHz' }
}
Invoke-Check 'Memory' {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if (-not (Assert-Data $cs 'Win32_ComputerSystem')) { return }
    $gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-Output ("  RAM: {0} GB" -f $gb)
    if ($gb -lt 3.5) { Add-Finding 'Critical' "RAM is $gb GB (4 GB required; usable RAM reads a little lower than installed RAM)" }
}
Invoke-Check 'Storage' {
    $d = Get-Disk | Where-Object { $_.IsBoot }
    if (-not (Assert-Data $d 'Boot disk')) { return }
    $gb = [math]::Round($d.Size / 1GB, 0)
    Write-Output ("  boot disk: {0} GB, partition style {1}" -f $gb, $d.PartitionStyle)
    if ($gb -lt 64) { Add-Finding 'Critical' "Boot disk is $gb GB (64 GB required)" }
    if ($d.PartitionStyle -ne 'GPT') { Add-Finding 'Warning' 'Boot disk is not GPT; UEFI conversion is needed before an in-place upgrade (for example with MBR2GPT after review)' }
}
Invoke-Check 'Firmware and Secure Boot' {
    try { $sb = Confirm-SecureBootUEFI }
    catch { Add-Finding 'Critical' ('Secure Boot could not be confirmed: legacy BIOS firmware, or not running elevated ({0})' -f $_.Exception.Message); return }
    Write-Output ("  UEFI with Secure Boot enabled: {0}" -f $sb)
    if (-not $sb) { Add-Finding 'Critical' 'Secure Boot is not enabled' }
}
Invoke-Check 'TPM' {
    $t = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm
    if (-not (Assert-Data $t 'Win32_Tpm')) { Add-Finding 'Critical' 'No TPM reported'; return }
    Write-Output ("  TPM spec version: {0}; enabled={1}; activated={2}" -f $t.SpecVersion, $t.IsEnabled_InitialValue, $t.IsActivated_InitialValue)
    if ($t.SpecVersion -notmatch '^2\.0') { Add-Finding 'Critical' ("TPM spec version is '{0}' (2.0 required)" -f $t.SpecVersion) }
}
Invoke-Check 'Current build' {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Write-Output ("  {0} {1} build {2}.{3}" -f $cv.ProductName, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
    if ([int]$cv.CurrentBuild -lt 19041) { Add-Finding 'Warning' 'Windows 10 version 2004 or later is required to upgrade directly' }
}

Complete-Report
exit $script:ExitCode
