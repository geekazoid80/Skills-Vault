<#
.SYNOPSIS
    Adapters, IP and DNS configuration, SMB, firewall profiles and listening ports.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. An optional TCP test to a target is the only active probe.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\network-diagnostics.ps1 -Target dc01.example.com -Port 389
#>
[CmdletBinding()]
param(
    [string]$Target,
    [int]$Port = 443
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

Write-Output 'Windows Server network diagnostics'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. ADAPTERS'
Invoke-Check 'Adapters' {
    $a = Get-NetAdapter -Physical
    if (-not (Assert-Data $a 'Get-NetAdapter')) { return }
    foreach ($x in $a) {
        Write-Output ("  {0}: {1}, {2}, {3}" -f $x.Name, $x.Status, $x.LinkSpeed, $x.InterfaceDescription)
        if ($x.Status -ne 'Up') { Add-Finding 'Warning' ("Physical adapter {0} is {1} (a spare port may be expected)" -f $x.Name, $x.Status) }
    }
}

Write-Section '2. IP CONFIGURATION AND DNS'
Invoke-Check 'IP configuration' {
    $c = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
    if (-not (Assert-Data $c 'Get-NetIPConfiguration')) { return }
    foreach ($x in $c) {
        $dns = @($x.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) | Select-Object -Unique
        Write-Output ("  {0}: IPv4={1}; gateway={2}; DNS={3}" -f $x.InterfaceAlias, ($x.IPv4Address.IPAddress -join ','), ($x.IPv4DefaultGateway.NextHop -join ','), ($dns -join ','))
        if (@($dns).Count -lt 2) { Add-Finding 'Warning' ("Interface {0} has fewer than two IPv4 DNS servers" -f $x.InterfaceAlias) }
    }
}

Write-Section '3. SMB'
Invoke-Check 'SMB configuration' {
    $s = Get-SmbServerConfiguration
    if (-not (Assert-Data $s 'Get-SmbServerConfiguration')) { return }
    Write-Output ("  SMB1={0} SMB2={1} signing required={2} encrypt data={3}" -f $s.EnableSMB1Protocol, $s.EnableSMB2Protocol, $s.RequireSecuritySignature, $s.EncryptData)
    if ($s.EnableSMB1Protocol) { Add-Finding 'Critical' 'SMBv1 server protocol is enabled' }
    if (-not $s.RequireSecuritySignature) { Add-Finding 'Warning' 'SMB signing is not required on the server (check the version default and local policy)' }
}

Write-Section '4. FIREWALL PROFILES'
Invoke-Check 'Firewall profiles' {
    $f = Get-NetFirewallProfile
    if (-not (Assert-Data $f 'Get-NetFirewallProfile')) { return }
    foreach ($x in $f) {
        Write-Output ("  {0}: enabled={1}, inbound default={2}" -f $x.Name, $x.Enabled, $x.DefaultInboundAction)
        if (-not $x.Enabled) { Add-Finding 'Critical' ("Windows Firewall profile {0} is disabled" -f $x.Name) }
    }
}

Write-Section '5. LISTENING TCP PORTS'
Invoke-Check 'Listening ports' {
    $l = Get-NetTCPConnection -State Listen
    if (-not (Assert-Data $l 'Get-NetTCPConnection')) { return }
    $l | Sort-Object LocalPort -Unique | ForEach-Object {
        $p = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Write-Output ("  {0} {1} ({2})" -f $_.LocalAddress, $_.LocalPort, $p)
    }
}

if ($Target) {
    Write-Section ("6. CONNECTIVITY TO {0}:{1} (active probe)" -f $Target, $Port)
    Invoke-Check 'Connectivity' {
        $t = Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue
        Write-Output ("  TCP test succeeded: {0}; remote address {1}" -f $t.TcpTestSucceeded, $t.RemoteAddress)
        if (-not $t.TcpTestSucceeded) { Add-Finding 'Warning' ("TCP connection to {0}:{1} failed" -f $Target, $Port) }
    }
}

Complete-Report
exit $script:ExitCode
