<#
.SYNOPSIS
    vSphere cluster health check. READ ONLY: it uses Get-* cmdlets only and changes nothing.

.DESCRIPTION
    Checks per cluster: HA and DRS settings, host connection state and load, VMware Tools
    status, snapshot age, datastore use, active alarms and (if enabled) vSAN configuration.
    Exit code: 0 healthy, 1 warnings only, 2 critical findings.

    Requires the PowerCLI module (VMware.PowerCLI, renamed VCF.PowerCLI by Broadcom). Authenticate interactively, with an existing
    session, or by passing a PSCredential you obtained from a secret store. There is
    deliberately no password parameter.

    Not run against a live vSphere environment in this vault. Try it on a non-critical
    environment first. Thresholds: host CPU and memory warn at 90 per cent or more,
    datastores warn at 80 and are critical at 90, snapshots warn after SnapshotAgeDays.

.EXAMPLE
    .\powercli-health.ps1 -VCenterServer vcenter.example.com
    .\powercli-health.ps1 -VCenterServer vcenter.example.com -ClusterName Production -SnapshotAgeDays 2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$VCenterServer,
    [string]$ClusterName,
    [pscredential]$Credential,
    [int]$SnapshotAgeDays = 3
)

$ErrorActionPreference = 'Stop'
$code = 2   # any path that does not reach a verdict exits 2
$crit = [System.Collections.Generic.List[string]]::new()
$warn = [System.Collections.Generic.List[string]]::new()
$line = '-' * 72

try {
    if ($Credential) { $conn = Connect-VIServer -Server $VCenterServer -Credential $Credential }
    else { $conn = Connect-VIServer -Server $VCenterServer }
} catch {
    [Console]::Error.WriteLine("Cannot connect to ${VCenterServer}: $($_.Exception.Message)")
    exit 2
}

try {
    Write-Output "vSphere health report"
    Write-Output "Generated: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) (UTC)"
    Write-Output "vCenter:   $($conn.Name) version $($conn.Version) build $($conn.Build)"

    $clusters = if ($ClusterName) { @(Get-Cluster -Name $ClusterName) } else { @(Get-Cluster) }
    if ($clusters.Count -eq 0) { $warn.Add('No clusters were returned') }

    foreach ($cluster in $clusters) {
        Write-Output "`n$line`nCLUSTER $($cluster.Name)`n$line"

        Write-Output "[HA]  Enabled=$($cluster.HAEnabled) AdmissionControl=$($cluster.HAAdmissionControlEnabled)"
        if (-not $cluster.HAEnabled) { $warn.Add("Cluster $($cluster.Name): HA is disabled") }
        elseif (-not $cluster.HAAdmissionControlEnabled) { $warn.Add("Cluster $($cluster.Name): HA admission control is disabled") }

        Write-Output "[DRS] Enabled=$($cluster.DrsEnabled) Automation=$($cluster.DrsAutomationLevel) EVC=$($cluster.EVCMode)"
        if (-not $cluster.DrsEnabled) { $warn.Add("Cluster $($cluster.Name): DRS is disabled") }

        $vmhosts = @(Get-VMHost -Location $cluster)
        Write-Output "`n[HOSTS]"
        foreach ($h in $vmhosts) {
            $cpuPct = if ($h.CpuTotalMhz -gt 0) { [math]::Round(100 * $h.CpuUsageMhz / $h.CpuTotalMhz, 1) } else { $null }
            $memPct = if ($h.MemoryTotalGB -gt 0) { [math]::Round(100 * $h.MemoryUsageGB / $h.MemoryTotalGB, 1) } else { $null }
            Write-Output ("  {0}: state={1} cpu={2}% mem={3}% version={4} build={5}" -f $h.Name, $h.ConnectionState, $cpuPct, $memPct, $h.Version, $h.Build)
            if ($h.ConnectionState -ne 'Connected' -and $h.ConnectionState -ne 'Maintenance') { $crit.Add("Host $($h.Name): $($h.ConnectionState)") }
            if ($null -ne $cpuPct -and $cpuPct -ge 90) { $warn.Add("Host $($h.Name): CPU at $cpuPct per cent") }
            if ($null -ne $memPct -and $memPct -ge 90) { $warn.Add("Host $($h.Name): memory at $memPct per cent") }
        }
        $versions = @($vmhosts | Select-Object -ExpandProperty Version -Unique)
        if ($versions.Count -gt 1) { $warn.Add("Cluster $($cluster.Name): hosts run mixed ESXi versions ($($versions -join ', '))") }

        $vms = @(Get-VM -Location $cluster)
        $on = @($vms | Where-Object { $_.PowerState -eq 'PoweredOn' })
        Write-Output "`n[TOOLS] powered-on VMs: $($on.Count)"
        $toolsBad = @($on | Where-Object { $_.ExtensionData.Guest.ToolsVersionStatus -notin @('guestToolsCurrent', 'guestToolsUnmanaged') })
        $toolsDown = @($on | Where-Object { $_.ExtensionData.Guest.ToolsRunningStatus -ne 'guestToolsRunning' })
        Write-Output "  outdated or missing: $($toolsBad.Count); not running: $($toolsDown.Count)"
        if ($toolsDown.Count -gt 0) { $warn.Add("Cluster $($cluster.Name): VMware Tools is not running in $($toolsDown.Count) powered-on VMs") }
        if ($toolsBad.Count -gt 0) { $warn.Add("Cluster $($cluster.Name): $($toolsBad.Count) powered-on VMs have outdated or missing VMware Tools") }

        $snaps = @($vms | Get-Snapshot)
        $cutoff = (Get-Date).AddDays(-$SnapshotAgeDays)
        $old = @($snaps | Where-Object { $_.Created -lt $cutoff })
        Write-Output "`n[SNAPSHOTS] total: $($snaps.Count); older than ${SnapshotAgeDays} days: $($old.Count)"
        foreach ($s in ($old | Sort-Object Created)) {
            Write-Output ("  {0}: {1} created {2:yyyy-MM-dd} size {3} GB" -f $s.VM, $s.Name, $s.Created, [math]::Round($s.SizeGB, 1))
        }
        if ($old.Count -gt 0) { $warn.Add("Cluster $($cluster.Name): $($old.Count) snapshots older than $SnapshotAgeDays days") }

        Write-Output "`n[DATASTORES]"
        $datastores = @(Get-Datastore -RelatedObject $cluster)
        foreach ($ds in ($datastores | Sort-Object Name -Unique)) {
            if ($ds.CapacityGB -le 0) {
                Write-Output "  $($ds.Name): capacity reported as 0 (inaccessible or unmounted)"
                $warn.Add("Datastore $($ds.Name) reports no capacity (inaccessible or unmounted)")
                continue
            }
            $used = [math]::Round(100 * ($ds.CapacityGB - $ds.FreeSpaceGB) / $ds.CapacityGB, 1)
            Write-Output ("  {0}: {1}% used, {2} GB free" -f $ds.Name, $used, [math]::Round($ds.FreeSpaceGB, 1))
            if ($used -ge 90) { $crit.Add("Datastore $($ds.Name): $used per cent used") }
            elseif ($used -ge 80) { $warn.Add("Datastore $($ds.Name): $used per cent used") }
        }

        if ($cluster.VsanEnabled) {
            Write-Output "`n[VSAN]"
            try {
                $vc = Get-VsanClusterConfiguration -Cluster $cluster
                Write-Output (($vc | Format-List | Out-String).TrimEnd())
            } catch {
                $warn.Add("Cluster $($cluster.Name): vSAN configuration could not be read ($($_.Exception.Message))")
            }
            Write-Output "  Review vSAN Health in the vSphere Client; this script does not judge it."
        }

        Write-Output "`n[ALARMS]"
        $alarms = @($cluster.ExtensionData.TriggeredAlarmState)
        Write-Output "  triggered on the cluster object: $($alarms.Count)"
        if ($alarms.Count -gt 0) { $warn.Add("Cluster $($cluster.Name): $($alarms.Count) triggered alarms") }
    }

    Write-Output "`n$line`nSUMMARY`n$line"
    if ($crit.Count -eq 0 -and $warn.Count -eq 0) {
        Write-Output 'No warnings or critical findings.'
        $code = 0
    } else {
        foreach ($c in $crit) { Write-Output "  CRITICAL: $c" }
        foreach ($w in $warn) { Write-Output "  WARNING:  $w" }
        $code = if ($crit.Count -gt 0) { 2 } else { 1 }
    }
} catch {
    [Console]::Error.WriteLine("Health check failed part-way: $($_.Exception.Message)")
    $code = 2
} finally {
    if ($conn) { Disconnect-VIServer -Server $conn -Confirm:$false -ErrorAction SilentlyContinue }
}
exit $code
