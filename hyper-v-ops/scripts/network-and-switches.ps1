<#
.SYNOPSIS
    Virtual switches, SET teams, VM adapters and dropped packets.

.DESCRIPTION
    READ ONLY: this script only reads state and changes nothing. Reports switch types, SET membership and load balancing, LBFO-bound switches on 2022 or later, VM adapter connectivity, RDMA and dropped-packet counters.
    Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows. Run elevated on the Hyper-V host, with the Hyper-V PowerShell module installed.
    Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
    A query that fails or returns nothing is reported as a warning, never as a pass.

    Not run against a live Windows system in this vault: it is parse-checked and exercised against mocked
    cmdlets only, so property names are taken from documentation. Try it on a non-critical machine first.

.EXAMPLE
    .\network-and-switches.ps1
#>
[CmdletBinding()]
param()

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

Write-Output 'Hyper-V networking and switches'
Write-Output ("Generated: {0:yyyy-MM-ddTHH\:mm\:ssZ} (UTC)" -f (Get-Date).ToUniversalTime())

$script:HvOk = [bool](Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)
if (-not $script:HvOk) { Add-Finding 'Critical' 'Get-VMSwitch is not available: the Hyper-V PowerShell module is not installed here' }
$osBuild = 0
Invoke-Check 'OS build' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (Assert-Data $os 'Win32_OperatingSystem') { $script:osBuild = [int]$os.BuildNumber; Write-Output ("  OS build: {0}" -f $os.BuildNumber) }
}

Write-Section '1. VIRTUAL SWITCHES'
Invoke-Check 'Virtual switches' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $sw = @(Get-VMSwitch)
    if (-not (Assert-Data $sw 'Get-VMSwitch')) { return }
    foreach ($s in $sw) {
        Write-Output ("  {0}: type={1}, adapter='{2}', SET={3}, SR-IOV={4}" -f $s.Name, $s.SwitchType, $s.NetAdapterInterfaceDescription, $s.EmbeddedTeamingEnabled, $s.IovEnabled)
        if ($script:osBuild -ge 20348 -and "$($s.NetAdapterInterfaceDescription)" -match 'Multiplexor') {
            Add-Finding 'Warning' ("Switch {0} is bound to an LBFO team; LBFO is not supported with Hyper-V on Windows Server 2022 or later (rebuild as a SET switch)" -f $s.Name)
        }
    }
}

Write-Section '2. SWITCH EMBEDDED TEAMS'
Invoke-Check 'SET teams' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $teams = @(Get-VMSwitchTeam)
    if ($teams.Count -eq 0) { Write-Output '  no SET teams'; return }
    foreach ($t in $teams) {
        if ($null -eq $t.NetAdapterInterfaceDescription) { Add-Finding 'Warning' ("SET team {0}: the member list was not returned" -f $t.Name); continue }
        $members = @($t.NetAdapterInterfaceDescription)
        Write-Output ("  {0}: {1} member(s), load balancing={2}, teaming mode={3}" -f $t.Name, $members.Count, $t.LoadBalancingAlgorithm, $t.TeamingMode)
        if ($members.Count -eq 1) { Add-Finding 'Warning' ("SET team {0} has a single member (no adapter redundancy)" -f $t.Name) }
    }
}

Write-Section '3. VM NETWORK ADAPTERS'
Invoke-Check 'VM adapters' {
    if (-not $script:HvOk) { Write-Output '  skipped: Hyper-V module not available'; return }
    $vms = @(Get-VM)
    if ($vms.Count -eq 0) { Add-Finding 'Warning' 'Get-VM returned no VMs (an empty host, or not elevated, or not in the Hyper-V Administrators group)'; return }
    foreach ($v in $vms) {
        $nics = @(Get-VMNetworkAdapter -VM $v)
        foreach ($n in $nics) {
            $vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $n
            $mode = if ($vlan) { "{0} {1}" -f $vlan.OperationMode, $vlan.AccessVlanId } else { 'unknown' }
            Write-Output ("  {0} / {1}: switch='{2}', VLAN={3}, MAC spoofing={4}, SR-IOV weight={5}" -f $v.Name, $n.Name, $n.SwitchName, $mode, $n.MacAddressSpoofing, $n.IovWeight)
            if ($v.State -eq 'Running' -and -not $n.SwitchName) { Add-Finding 'Warning' ("VM {0} adapter {1} is not connected to a switch" -f $v.Name, $n.Name) }
        }
    }
}

Write-Section '4. RDMA ADAPTERS'
Invoke-Check 'RDMA' {
    if (-not (Get-Command Get-NetAdapterRdma -ErrorAction SilentlyContinue)) { Write-Output '  Get-NetAdapterRdma not available'; return }
    $r = @(Get-NetAdapterRdma)
    if ($r.Count -eq 0) { Write-Output '  no RDMA-capable adapters reported'; return }
    foreach ($x in $r) { Write-Output ("  {0}: RDMA enabled={1}" -f $x.Name, $x.Enabled) }
}

Write-Section '5. DROPPED PACKET COUNTERS (single sample, a rate)'
Invoke-Check 'Dropped packets' {
    $paths = @()
    foreach ($setName in 'Hyper-V Virtual Switch', 'Hyper-V Virtual Network Adapter') {
        $set = Get-Counter -ListSet $setName -ErrorAction Stop
        $paths += @($set.PathsWithInstances | Where-Object { $_ -like '*Dropped*' })
    }
    if ($paths.Count -eq 0) { Add-Finding 'Warning' 'No dropped-packet counters were found in the Hyper-V switch or adapter counter sets'; return }
    $sample = Get-Counter -Counter $paths -ErrorAction Stop
    $bad = @($sample.CounterSamples | Where-Object { $_.CookedValue -gt 0 })
    Write-Output ("  {0} dropped-packet counter instance(s) sampled; {1} non-zero" -f $paths.Count, $bad.Count)
    foreach ($b in $bad | Select-Object -First 5) { Write-Output ("      {0} = {1}" -f $b.Path, [math]::Round($b.CookedValue, 2)) }
    if ($bad.Count -gt 0) { Add-Finding 'Warning' ("{0} dropped-packet counter(s) are non-zero right now (saturation, QoS or switch configuration)" -f $bad.Count) }
}

Complete-Report
exit $script:ExitCode
