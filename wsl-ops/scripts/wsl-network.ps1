<#
.SYNOPSIS
    WSL networking review.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers .wslconfig networking settings, host adapters, the Hyper-V firewall settings for WSL and port proxy rules. With -ProbeGuest it reads resolv.conf, addresses and a name lookup inside distributions that wsl --list reports as running at that moment.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run as the Windows user who owns the WSL distributions.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\wsl-network.ps1 -ProbeGuest -DnsTestName www.example.com
#>
[CmdletBinding()]
param(
    [switch]$ProbeGuest,
    [ValidatePattern('^[A-Za-z0-9.-]+$')] [string]$DnsTestName = 'www.microsoft.com'
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

# wsl.exe's own output is UTF-16 when captured; output of a command run inside a distribution is UTF-8 (use -Utf8).
# Native stderr text must not become a terminating error under Windows PowerShell 5.1, so the preference is relaxed here.
function Invoke-Wsl {
    param([string[]]$Arguments, [switch]$Utf8)
    $ErrorActionPreference = 'Continue'
    $enc = if ($Utf8) { New-Object System.Text.UTF8Encoding($false) } else { [System.Text.Encoding]::Unicode }
    $prev = $null
    try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = $enc } catch { $prev = $null }
    try {
        $out = & wsl.exe @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        if ($null -ne $prev) { try { [Console]::OutputEncoding = $prev } catch { } }
    }
    $lines = @($out | ForEach-Object { ("$_" -replace "`0", '').TrimEnd() } | Where-Object { $_ -ne '' })
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}
# Reads the user's .wslconfig into a hashtable keyed "section.key" (lower case). Returns $null when the file does not exist.
function Read-WslConfig {
    $path = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $cfg = @{}
    $section = ''
    foreach ($raw in (Get-Content -LiteralPath $path -ErrorAction Stop)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].ToLower(); continue }
        $eq = $line.IndexOf('=')
        if ($eq -gt 0) {
            $k = $line.Substring(0, $eq).Trim().ToLower()
            $v = $line.Substring($eq + 1).Trim()
            $hash = $v.IndexOf(' #')
            if ($hash -ge 0) { $v = $v.Substring(0, $hash).Trim() }
            $cfg["$section.$k"] = $v
        }
    }
    return $cfg
}

Write-Output 'WSL networking'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); guest probes {1}" -f (Get-Date).ToUniversalTime(), $(if ($ProbeGuest) { 'ON (runs commands inside running distributions)' } else { 'off' }))

$script:Build = 0
$script:WslOk = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
$script:Mode = 'nat'

Write-Section '1. WINDOWS BUILD AND NETWORKING SETTINGS'
Invoke-Check 'Windows build' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (Assert-Data $os 'Win32_OperatingSystem') { $script:Build = [int]$os.BuildNumber; Write-Output ("  Windows build {0}" -f $os.BuildNumber) }
}
Invoke-Check '.wslconfig networking' {
    $cfg = Read-WslConfig
    if ($null -eq $cfg) { Write-Output '  no .wslconfig: NAT networking; on Windows 11 22H2 or later DNS tunnelling, auto proxy and the Hyper-V firewall default to on (Microsoft Learn)'; return }
    foreach ($k in 'wsl2.networkingmode', 'wsl2.dnstunneling', 'wsl2.autoproxy', 'wsl2.firewall', 'wsl2.localhostforwarding', 'wsl2.dnsproxy') {
        if ($cfg.ContainsKey($k)) { Write-Output ("  {0} = {1}" -f $k, $cfg[$k]) }
    }
    if ($cfg.ContainsKey('wsl2.networkingmode')) { $script:Mode = $cfg['wsl2.networkingmode'].ToLower() }
    if ($script:Mode -eq 'mirrored' -and $script:Build -gt 0 -and $script:Build -lt 22621) { Add-Finding 'Warning' 'networkingMode=mirrored needs Windows 11 22H2 (build 22621) or later' }
    if ($script:Mode -eq 'bridged') { Add-Finding 'Warning' 'networkingMode=bridged is marked deprecated in Microsoft documentation' }
    if ($cfg.ContainsKey('wsl2.firewall') -and $cfg['wsl2.firewall'] -eq 'false') { Add-Finding 'Warning' 'wsl2.firewall=false: Windows and Hyper-V firewall rules do not filter WSL traffic' }
}

Write-Section '2. HOST ADAPTERS'
Invoke-Check 'Adapters' {
    $a = @(Get-NetAdapter)
    if (-not (Assert-Data $a 'Get-NetAdapter')) { return }
    $wslNic = @($a | Where-Object { $_.Name -match 'WSL' })
    if ($wslNic.Count -eq 0) { Write-Output '  no vEthernet (WSL) adapter (normal in mirrored mode, or when no WSL 2 VM is running)' }
    foreach ($n in $wslNic) { Write-Output ("  {0}: {1}" -f $n.Name, $n.Status) }
    $vpn = @($a | Where-Object { $_.InterfaceDescription -match 'VPN|AnyConnect|GlobalProtect|PANGP|Fortinet|WireGuard|TAP-|OpenVPN|Zscaler' -and $_.Status -eq 'Up' })
    if ($vpn.Count -gt 0) { Write-Output ("  VPN-like adapters up: {0} (NAT-mode WSL often loses DNS or routes behind a VPN; mirrored mode with DNS tunnelling is the documented mitigation)" -f (($vpn | ForEach-Object { $_.Name }) -join ', ')) }
}

Write-Section '3. HYPER-V FIREWALL FOR WSL'
Invoke-Check 'Hyper-V firewall' {
    if (-not (Get-Command Get-NetFirewallHyperVVMSetting -ErrorAction SilentlyContinue)) { Write-Output '  Hyper-V firewall cmdlets not available on this Windows build'; return }
    $s = Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
    if (-not (Assert-Data $s 'Get-NetFirewallHyperVVMSetting for WSL')) { return }
    Write-Output ("  Enabled: {0}; default inbound: {1}; default outbound: {2}; loopback: {3}" -f $s.Enabled, $s.DefaultInboundAction, $s.DefaultOutboundAction, $s.LoopbackEnabled)
    if ("$($s.Enabled)" -match 'False') { Add-Finding 'Warning' 'The Hyper-V firewall is disabled for WSL' }
    if ("$($s.DefaultInboundAction)" -eq 'Allow') { Add-Finding 'Warning' 'Hyper-V firewall default inbound action for WSL is Allow (LAN hosts can reach WSL services); confirm it was set on purpose' }
}

Write-Section '4. PORT PROXY RULES'
Invoke-Check 'Port proxy' {
    $ErrorActionPreference = 'Continue'
    $out = & netsh.exe interface portproxy show all 2>&1
    if ($LASTEXITCODE -ne 0) { Add-Finding 'Warning' 'netsh interface portproxy show all failed'; return }
    $lines = @($out | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) { Write-Output '  no port proxy rules'; return }
    $lines | ForEach-Object { Write-Output "  $_" }
    if (($lines -join "`n") -match '0\.0\.0\.0') { Add-Finding 'Warning' 'A port proxy rule listens on 0.0.0.0 (all interfaces), which exposes the forwarded port to the network; in NAT mode the WSL address also changes at restart, so such rules go stale' }
}

Write-Section '5. GUEST VIEW (only with -ProbeGuest, only running WSL 2 distributions)'
if (-not $ProbeGuest) { Write-Output '  skipped: pass -ProbeGuest to read resolv.conf, addresses and test name resolution inside a running distribution' }
elseif (-not $script:WslOk) { Add-Finding 'Warning' 'wsl.exe not found; guest probes skipped' }
else {
    Invoke-Check 'Guest probes' {
        $l = Invoke-Wsl -Arguments @('--list', '--verbose')
        if ($l.ExitCode -ne 0 -or $l.Lines.Count -eq 0) { Add-Finding 'Warning' 'wsl --list --verbose failed or returned nothing; guest probes skipped'; return }
        $running = @()
        $parsed = 0
        foreach ($line in $l.Lines) {
            if ($line -match '^\s*\*?\s*(\S+)\s+(Running|Stopped|Installing|Uninstalling|Converting)\s+[12]\s*$') { $parsed++ }
            if ($line -match '^\s*\*?\s*(\S+)\s+Running\s+2\s*$') { $running += $Matches[1] }
        }
        if ($parsed -eq 0) { Add-Finding 'Warning' 'wsl --list --verbose output could not be parsed (localised or changed format); guest probes skipped'; return }
        if ($running.Count -eq 0) { Write-Output '  no WSL 2 distribution is running; none was started'; return }
        foreach ($d in $running) {
            $cmd = 'cat /etc/resolv.conf; ip -brief addr 2>/dev/null; if getent hosts ' + $DnsTestName + ' >/dev/null 2>&1; then echo RESOLVE_OK; else echo RESOLVE_FAIL; fi'
            $r = Invoke-Wsl -Utf8 -Arguments @('-d', $d, '--', 'sh', '-c', $cmd)
            if ($r.Lines.Count -eq 0) { Add-Finding 'Warning' ("Guest probe of {0} failed or returned nothing" -f $d); continue }
            Write-Output ("  {0}:" -f $d)
            $r.Lines | ForEach-Object { Write-Output ("      {0}" -f $_) }
            if ($r.Lines -contains 'RESOLVE_FAIL') { Add-Finding 'Warning' ("{0}: name '{1}' did not resolve inside the distribution" -f $d, $DnsTestName) }
            elseif (-not ($r.Lines -contains 'RESOLVE_OK')) { Add-Finding 'Warning' ("{0}: the name lookup result was not returned" -f $d) }
        }
    }
}

Complete-Report
exit $script:ExitCode
