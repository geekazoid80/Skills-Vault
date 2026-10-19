<#
.SYNOPSIS
    WSL health summary.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Covers Windows build, Virtual Machine Platform, WSL version, distributions and their WSL version, .wslconfig, and virtual disk sizes. With -ProbeGuest it runs read-only commands inside distributions that wsl --list reports as running at that moment.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run as the Windows user who owns the WSL distributions. This script warns when not elevated, because optional feature state needs elevation.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\wsl-health.ps1 -ProbeGuest
#>
[CmdletBinding()]
param(
    [switch]$ProbeGuest,
    [int]$VhdWarnGB = 100
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

Write-Output 'WSL health'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC); guest probes {1}" -f (Get-Date).ToUniversalTime(), $(if ($ProbeGuest) { 'ON (runs commands inside running distributions)' } else { 'off' }))

$script:WslOk = $false
$script:Build = 0
$script:Distros = @()

Write-Section '1. WINDOWS AND FEATURES'
Invoke-Check 'Windows build' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (-not (Assert-Data $os 'Win32_OperatingSystem')) { return }
    $script:Build = [int]$os.BuildNumber
    Write-Output ("  {0}, build {1}" -f $os.Caption, $os.BuildNumber)
    if ($script:Build -lt 18362) { Add-Finding 'Critical' ("Windows build {0} is below 18362 (Windows 10 version 1903), the earliest build Microsoft lists for WSL 2" -f $script:Build) }
    elseif ($script:Build -lt 19041) { Add-Finding 'Warning' ("Windows build {0} is below 19041 (Windows 10 version 2004), the minimum for wsl --install and .wslconfig" -f $script:Build) }
    elseif ($script:Build -lt 22000) { Write-Output '  Windows 10 build: mirrored networking, DNS tunnelling and auto proxy need Windows 11 22H2 or later; see windows-client-ops for Windows 10 end of support.' }
}
Invoke-Check 'Optional features' {
    if (-not (Test-IsAdmin)) { Add-Finding 'Warning' 'Not running elevated; Windows optional feature state cannot be read'; return }
    $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if (Assert-Data $vmp 'Get-WindowsOptionalFeature VirtualMachinePlatform') {
        Write-Output ("  VirtualMachinePlatform: {0}" -f $vmp.State)
        if ("$($vmp.State)" -ne 'Enabled') { Add-Finding 'Critical' 'Virtual Machine Platform is not enabled; WSL 2 cannot start' }
    }
    $sub = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if (Assert-Data $sub 'Get-WindowsOptionalFeature Microsoft-Windows-Subsystem-Linux') { Write-Output ("  Microsoft-Windows-Subsystem-Linux (inbox WSL component): {0}" -f $sub.State) }
}

Write-Section '2. WSL VERSION AND STATUS'
Invoke-Check 'wsl.exe' {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Add-Finding 'Critical' 'wsl.exe was not found on this system'; return }
    $script:WslOk = $true
    $v = Invoke-Wsl -Arguments @('--version')
    if ($v.ExitCode -ne 0 -or $v.Lines.Count -eq 0) {
        Add-Finding 'Warning' 'wsl --version failed or returned nothing (an old inbox WSL has no --version; run wsl --update)'
    } else {
        $v.Lines | ForEach-Object { Write-Output "  $_" }
        if ($v.Lines[0] -match '(\d+\.\d+\.\d+)') {
            if ([version]$Matches[1] -lt [version]'2.0.9') { Add-Finding 'Warning' ("WSL version {0} is older than 2.0.9, which Microsoft lists as the minimum for current enterprise controls and Hyper-V firewall integration" -f $Matches[1]) }
        } else { Add-Finding 'Warning' 'Could not read a version number from wsl --version (localised output?)' }
    }
    $s = Invoke-Wsl -Arguments @('--status')
    $s.Lines | ForEach-Object { Write-Output "  $_" }
}

Write-Section '3. DISTRIBUTIONS'
Invoke-Check 'Distributions' {
    if (-not $script:WslOk) { Write-Output '  skipped: wsl.exe not available'; return }
    $l = Invoke-Wsl -Arguments @('--list', '--verbose')
    if ($l.Lines.Count -eq 0) { Add-Finding 'Warning' 'wsl --list --verbose returned nothing'; return }
    if (($l.Lines -join ' ') -match '(?i)no installed distributions') { Write-Output '  no distributions installed'; return }
    $rows = @()
    foreach ($line in $l.Lines) {
        if ($line -match '^\s*(\*?)\s*(\S+)\s+(Running|Stopped|Installing|Uninstalling|Converting)\s+([12])\s*$') {
            $rows += [pscustomobject]@{ Name = $Matches[2]; State = $Matches[3]; Version = [int]$Matches[4]; Default = ($Matches[1] -eq '*') }
        }
    }
    if ($rows.Count -eq 0) { Add-Finding 'Warning' 'wsl --list --verbose produced output that this script could not parse (localised or changed format)'; $l.Lines | ForEach-Object { Write-Output "  $_" }; return }
    $script:Distros = $rows
    foreach ($r in $rows) {
        Write-Output ("  {0}{1}: {2}, WSL {3}" -f $r.Name, $(if ($r.Default) { ' (default)' } else { '' }), $r.State, $r.Version)
        if ($r.Version -eq 1) { Add-Finding 'Warning' ("Distribution {0} runs under WSL 1 (no real Linux kernel, no Docker daemon, limited syscall coverage); convert with wsl --set-version or retire it" -f $r.Name) }
    }
}

Write-Section '4. .WSLCONFIG'
Invoke-Check '.wslconfig' {
    $cfg = Read-WslConfig
    if ($null -eq $cfg) { Write-Output '  no .wslconfig in the user profile (all defaults: memory 50% of Windows RAM, processors all, NAT networking)'; return }
    foreach ($k in 'wsl2.memory', 'wsl2.processors', 'wsl2.swap', 'wsl2.networkingmode', 'wsl2.dnstunneling', 'wsl2.autoproxy', 'wsl2.firewall', 'wsl2.nestedvirtualization', 'wsl2.kernel', 'wsl2.kernelcommandline', 'wsl2.defaultvhdsize', 'wsl2.vmidletimeout', 'experimental.automemoryreclaim', 'experimental.sparsevhd') {
        if ($cfg.ContainsKey($k)) { Write-Output ("  {0} = {1}" -f $k, $cfg[$k]) }
    }
    if ($cfg.ContainsKey('wsl2.kernel')) { Write-Output '  note: a custom kernel is set; the Microsoft Defender for Endpoint plug-in for WSL does not support custom kernels.' }
    if ($cfg.ContainsKey('wsl2.networkingmode') -and $cfg['wsl2.networkingmode'] -eq 'mirrored' -and $script:Build -gt 0 -and $script:Build -lt 22621) {
        Add-Finding 'Warning' 'networkingMode=mirrored needs Windows 11 22H2 (build 22621) or later; this build ignores it'
    }
    if ($cfg.ContainsKey('wsl2.networkingmode') -and $cfg['wsl2.networkingmode'] -eq 'bridged') { Add-Finding 'Warning' 'networkingMode=bridged is marked deprecated in Microsoft documentation' }
    if (-not $cfg.ContainsKey('wsl2.memory')) { Write-Output '  memory is not capped; the VM defaults to 50% of Windows RAM' }
}

Write-Section '5. VIRTUAL DISK FILES (registered distributions of the current user)'
Invoke-Check 'Virtual disks' {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $root)) { Write-Output ("  no WSL registrations under {0} for user {1}" -f $root, $env:USERNAME); return }
    $keys = @(Get-ChildItem -LiteralPath $root | Where-Object { $_.PSChildName -like '{*}' })
    if ($keys.Count -eq 0) { Write-Output '  no registered distributions'; return }
    foreach ($k in $keys) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath
        $base = "$($p.BasePath)" -replace '^\\\\\?\\', ''
        $vhd = Join-Path $base 'ext4.vhdx'
        if (-not (Test-Path -LiteralPath $vhd)) {
            if ($p.PSObject.Properties['Version'] -and [int]$p.Version -eq 1) { Write-Output ("  {0}: WSL 1 distribution, no virtual disk" -f $p.DistributionName) }
            else { Add-Finding 'Warning' ("{0}: no ext4.vhdx at {1}; the disk may have another name (an imported disk) or the path moved, so its size was not checked" -f $p.DistributionName, $base) }
            continue
        }
        $f = Get-Item -LiteralPath $vhd
        $gb = [math]::Round($f.Length / 1GB, 1)
        Write-Output ("  {0}: {1} GB at {2}" -f $p.DistributionName, $gb, $vhd)
        if ($gb -gt $VhdWarnGB) { Add-Finding 'Warning' ("{0}: virtual disk is {1} GB; free space inside the distribution (fstrim), shut WSL down and compact the VHDX (wsl --manage <name> --compact where available, otherwise Optimize-VHD or diskpart); sparse VHD is experimental and has had corruption reports, so export a backup first" -f $p.DistributionName, $gb) }
        if ($vhd -match '^([A-Za-z]):') {
            $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $Matches[1])
            if ($vol) {
                $free = [math]::Round(100 * $vol.FreeSpace / $vol.Size, 1)
                if ($free -lt 10) { Add-Finding 'Critical' ("Volume holding {0}'s virtual disk has {1}% free; the VHD cannot grow" -f $p.DistributionName, $free) }
                elseif ($free -lt 20) { Add-Finding 'Warning' ("Volume holding {0}'s virtual disk has {1}% free" -f $p.DistributionName, $free) }
            }
        }
    }
}

Write-Section '6. GUEST PROBES (only with -ProbeGuest, only distributions already running)'
if (-not $ProbeGuest) { Write-Output '  skipped: pass -ProbeGuest to run uname, init and wsl.conf checks inside running distributions' }
else {
    foreach ($d in @($script:Distros | Where-Object { $_.State -eq 'Running' -and $_.Version -eq 2 })) {
        Invoke-Check ("Guest probe " + $d.Name) {
            $r = Invoke-Wsl -Utf8 -Arguments @('-d', $d.Name, '--', 'sh', '-c', 'echo KERNEL=$(uname -r); echo INIT=$(ps -p 1 -o comm= 2>/dev/null); echo CONF_START; cat /etc/wsl.conf 2>/dev/null')
            if ($r.ExitCode -ne 0 -or $r.Lines.Count -eq 0) { Add-Finding 'Warning' ("Guest probe of {0} failed or returned nothing" -f $d.Name); return }
            $k = @($r.Lines | Where-Object { $_ -like 'KERNEL=*' }) | Select-Object -First 1
            $i = @($r.Lines | Where-Object { $_ -like 'INIT=*' }) | Select-Object -First 1
            Write-Output ("  {0}: {1}; {2}" -f $d.Name, $k, $i)
            $idx = [array]::IndexOf($r.Lines, 'CONF_START')
            if ($idx -ge 0) { foreach ($x in @($r.Lines | Select-Object -Skip ($idx + 1))) { Write-Output ("      wsl.conf: {0}" -f $x) } }
        }
    }
    if (@($script:Distros | Where-Object { $_.State -eq 'Running' -and $_.Version -eq 2 }).Count -eq 0) { Write-Output '  no WSL 2 distribution is running; none was started' }
}

Complete-Report
exit $script:ExitCode
