<#
.SYNOPSIS
    Security posture summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports TPM, Secure Boot, BitLocker, Defender, ASR rule actions, firewall, SMBv1, VBS and Hello for Business policy.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\security-posture.ps1
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

Write-Output 'Windows client security posture (read only)'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())
Invoke-Check 'Elevation' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; BitLocker and Defender queries may be incomplete' }
}

Write-Section '1. TPM AND SECURE BOOT'
Invoke-Check 'TPM' {
    $t = Get-Tpm
    if (-not (Assert-Data $t 'Get-Tpm')) { return }
    Write-Output ("  TPM present={0} ready={1} enabled={2}" -f $t.TpmPresent, $t.TpmReady, $t.TpmEnabled)
    if (-not $t.TpmPresent -or -not $t.TpmReady) { Add-Finding 'Warning' 'TPM is absent or not ready' }
}
Invoke-Check 'Secure Boot' {
    $sb = Confirm-SecureBootUEFI
    Write-Output ("  Secure Boot enabled: {0}" -f $sb)
    if (-not $sb) { Add-Finding 'Warning' 'Secure Boot is not enabled' }
}

Write-Section '2. BITLOCKER'
Invoke-Check 'BitLocker' {
    $b = Get-BitLockerVolume
    if (-not (Assert-Data $b 'Get-BitLockerVolume')) { return }
    foreach ($v in $b) {
        $types = ($v.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ','
        Write-Output ("  {0}: status={1}, protection={2}, method={3}, protectors={4}" -f $v.MountPoint, $v.VolumeStatus, $v.ProtectionStatus, $v.EncryptionMethod, $types)
        if ($v.VolumeType -eq 'OperatingSystem' -and $v.ProtectionStatus -ne 'On') { Add-Finding 'Critical' ("Operating system volume {0} is not protected by BitLocker" -f $v.MountPoint) }
        if ($v.ProtectionStatus -eq 'On' -and $types -notmatch 'RecoveryPassword') { Add-Finding 'Warning' ("Volume {0} has no recovery password protector" -f $v.MountPoint) }
    }
}

Write-Section '3. DEFENDER'
Invoke-Check 'Defender' {
    $m = Get-MpComputerStatus
    if (-not (Assert-Data $m 'Get-MpComputerStatus')) { return }
    Write-Output ("  real-time={0} tamper protection={1} signature age={2} day(s)" -f $m.RealTimeProtectionEnabled, $m.IsTamperProtected, $m.AntivirusSignatureAge)
    if (-not $m.RealTimeProtectionEnabled) { Add-Finding 'Warning' 'Defender real-time protection is off (expected only if another product is in use)' }
    if ($m.AntivirusSignatureAge -gt 3) { Add-Finding 'Warning' ("Defender signatures are {0} day(s) old" -f $m.AntivirusSignatureAge) }
}
Invoke-Check 'Attack surface reduction rules' {
    $p = Get-MpPreference
    if (-not (Assert-Data $p 'Get-MpPreference')) { return }
    $ids = @($p.AttackSurfaceReductionRules_Ids | Where-Object { $_ })
    $act = @($p.AttackSurfaceReductionRules_Actions | Where-Object { $null -ne $_ })
    Write-Output ("  cloud-delivered protection (MAPS reporting): {0}" -f $p.MAPSReporting)
    Write-Output ("  ASR rules configured: {0} (action codes: 0 off, 1 block, 2 audit, 6 warn)" -f $ids.Count)
    if ($ids.Count -eq 0) { Add-Finding 'Warning' 'No attack surface reduction rules are configured on this device' }
    for ($i = 0; $i -lt $ids.Count; $i++) { Write-Output ("    {0} action {1}" -f $ids[$i], $act[$i]) }
    Write-Output ("  controlled folder access: {0}" -f $p.EnableControlledFolderAccess)
}

Write-Section '4. FIREWALL, SMB, VBS'
Invoke-Check 'Firewall' {
    $f = Get-NetFirewallProfile
    if (-not (Assert-Data $f 'Get-NetFirewallProfile')) { return }
    foreach ($x in $f) {
        Write-Output ("  firewall {0}: enabled={1}" -f $x.Name, $x.Enabled)
        if (-not $x.Enabled) { Add-Finding 'Critical' ("Windows Firewall profile {0} is disabled" -f $x.Name) }
    }
}
Invoke-Check 'SMBv1' {
    $s = Get-SmbServerConfiguration
    if (-not (Assert-Data $s 'Get-SmbServerConfiguration')) { return }
    Write-Output ("  SMB1 server protocol enabled: {0}" -f $s.EnableSMB1Protocol)
    if ($s.EnableSMB1Protocol) { Add-Finding 'Critical' 'SMBv1 is enabled' }
}
Invoke-Check 'VBS' {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard'
    if (-not (Assert-Data $dg 'Win32_DeviceGuard')) { return }
    Write-Output ("  VBS status={0} (0 off, 1 configured, 2 running); services running={1} (1 Credential Guard, 2 HVCI)" -f $dg.VirtualizationBasedSecurityStatus, ($dg.SecurityServicesRunning -join ','))
}

Write-Section '5. SIGN-IN'
Invoke-Check 'Windows Hello for Business policy' {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'
    if (Test-Path $k) { (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Write-Output ("  {0} = {1}" -f $_.Name, $_.Value) } } else { Write-Output '  no PassportForWork policy key' }
}

Complete-Report
exit $script:ExitCode
