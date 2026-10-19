<#
.SYNOPSIS
    Adapters, IP, proxy, Wi-Fi, DNS and gateway reachability.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Active probes are a DNS lookup of one name and a ping of the default gateway.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated for complete results.
    Exit codes: 0 no findings, 1 warnings only, 2 critical findings or the check itself failed.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\network-diagnostics.ps1 -DnsTestName www.example.com
#>
[CmdletBinding()]
param(
    [string]$DnsTestName = 'www.microsoft.com'
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

Write-Output 'Windows client network diagnostics'
Write-Output ("Generated: {0:yyyy-MM-ddTHH:mm:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

Write-Section '1. ADAPTERS'
Invoke-Check 'Adapters' {
    $a = Get-NetAdapter
    if (-not (Assert-Data $a 'Get-NetAdapter')) { return }
    foreach ($x in $a) { Write-Output ("  {0}: {1}, {2}, {3}" -f $x.Name, $x.Status, $x.LinkSpeed, $x.InterfaceDescription) }
    if (@($a | Where-Object { $_.Status -eq 'Up' }).Count -eq 0) { Add-Finding 'Critical' 'No network adapter is up' }
}

Write-Section '2. IP CONFIGURATION'
Invoke-Check 'IP configuration' {
    $c = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
    if (-not (Assert-Data $c 'Get-NetIPConfiguration')) { return }
    foreach ($x in $c) {
        Write-Output ("  {0}: IPv4={1}; gateway={2}; DNS={3}" -f $x.InterfaceAlias, ($x.IPv4Address.IPAddress -join ','), ($x.IPv4DefaultGateway.NextHop -join ','), ($x.DNSServer.ServerAddresses -join ','))
        if (-not $x.IPv4DefaultGateway) { Add-Finding 'Warning' ("Interface {0} has no IPv4 default gateway" -f $x.InterfaceAlias) }
    }
    foreach ($x in $c) { if ($x.IPv4Address.IPAddress -match '^169\.254\.') { Add-Finding 'Warning' ("Interface {0} has an APIPA address; DHCP may have failed" -f $x.InterfaceAlias) } }
}

Write-Section '3. PROXY AND WI-FI'
Invoke-Check 'WinHTTP proxy' {
    $o = & netsh winhttp show proxy 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'netsh winhttp show proxy failed'; return }
    $o | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Output "  $_" }
}
Invoke-Check 'Wi-Fi' {
    $o = & netsh wlan show interfaces 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output '  no WLAN interface or service'; return }
    $o | Where-Object { $_ -match 'State|SSID|Signal|Radio type|Authentication' -and $_ -notmatch 'BSSID' } | ForEach-Object { Write-Output "  $_" }
}

Write-Section '4. DNS RESOLUTION'
Invoke-Check 'DNS' {
    $r = Resolve-DnsName -Name $DnsTestName -Type A
    if (-not (Assert-Data $r ("DNS lookup of {0}" -f $DnsTestName))) { return }
    Write-Output ("  {0} resolves to {1}" -f $DnsTestName, (($r | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) -join ','))
}

Write-Section '5. CONNECTIVITY'
Invoke-Check 'Default gateway ping' {
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if (-not (Assert-Data $gw 'Default route')) { return }
    $ok = Test-Connection -ComputerName $gw -Count 2 -Quiet
    Write-Output ("  gateway {0} answers ping: {1}" -f $gw, $ok)
    if (-not $ok) { Add-Finding 'Warning' ("Default gateway {0} did not answer ping (it may drop ICMP)" -f $gw) }
}

Complete-Report
exit $script:ExitCode
