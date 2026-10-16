<#
.SYNOPSIS
    vSphere inventory report. READ ONLY: it uses Get-* cmdlets only and changes nothing
    in vSphere. With -OutputDirectory it writes CSV files to that local directory.

.DESCRIPTION
    Lists hosts, VMs (with hardware version, Tools status and snapshot count) and
    datastores. Requires the PowerCLI module (VMware.PowerCLI, renamed VCF.PowerCLI by Broadcom). Authenticate interactively, with an
    existing session, or by passing a PSCredential you obtained from a secret store. There
    is deliberately no password parameter.

    Not run against a live vSphere environment in this vault. Try it on a non-critical
    environment first. Inventory CSVs describe your estate; store them accordingly.

.EXAMPLE
    .\powercli-inventory.ps1 -VCenterServer vcenter.example.com
    .\powercli-inventory.ps1 -VCenterServer vcenter.example.com -OutputDirectory .\inventory
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$VCenterServer,
    [pscredential]$Credential,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$code = 2   # any path that does not reach a verdict exits 2

try {
    if ($Credential) { $conn = Connect-VIServer -Server $VCenterServer -Credential $Credential }
    else { $conn = Connect-VIServer -Server $VCenterServer }
} catch {
    [Console]::Error.WriteLine("Cannot connect to ${VCenterServer}: $($_.Exception.Message)")
    exit 2
}

try {
    Write-Output "vSphere inventory"
    Write-Output "Generated: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) (UTC)"
    Write-Output "vCenter:   $($conn.Name) version $($conn.Version) build $($conn.Build)"

    $hosts = @(Get-VMHost | Select-Object Name, Version, Build, ConnectionState, PowerState, NumCpu, MemoryTotalGB,
        @{N = 'Cluster'; E = { ($_ | Get-Cluster -ErrorAction SilentlyContinue).Name } })
    $vms = @(Get-VM | Select-Object Name, PowerState, NumCpu, MemoryGB, ProvisionedSpaceGB, UsedSpaceGB,
        @{N = 'Host'; E = { $_.VMHost.Name } },
        @{N = 'HardwareVersion'; E = { $_.ExtensionData.Config.Version } },
        @{N = 'ToolsStatus'; E = { $_.ExtensionData.Guest.ToolsVersionStatus } },
        @{N = 'GuestId'; E = { $_.GuestId } },
        @{N = 'Folder'; E = { $_.Folder.Name } })
    $snapCounts = @{}
    foreach ($s in @(Get-VM | Get-Snapshot)) { $snapCounts[$s.VM.Name] = 1 + [int]$snapCounts[$s.VM.Name] }
    foreach ($vm in $vms) { $vm | Add-Member -NotePropertyName Snapshots -NotePropertyValue ([int]$snapCounts[$vm.Name]) -Force }
    $stores = @(Get-Datastore | Select-Object Name, Type, CapacityGB, FreeSpaceGB,
        @{N = 'UsedPct'; E = { if ($_.CapacityGB -gt 0) { [math]::Round(100 * ($_.CapacityGB - $_.FreeSpaceGB) / $_.CapacityGB, 1) } else { $null } } })

    Write-Output "`nHOSTS ($($hosts.Count))"
    $hosts | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
    Write-Output "VMS ($($vms.Count))"
    $vms | Format-Table Name, PowerState, NumCpu, MemoryGB, HardwareVersion, ToolsStatus, Snapshots, Host -AutoSize | Out-String -Width 200 | Write-Output
    Write-Output "DATASTORES ($($stores.Count))"
    $stores | Sort-Object UsedPct -Descending | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

    if ($OutputDirectory) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
        $hosts | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'hosts.csv') -NoTypeInformation
        $vms | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'vms.csv') -NoTypeInformation
        $stores | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'datastores.csv') -NoTypeInformation
        Write-Output "CSV files written to $OutputDirectory"
    }
    $code = 0
} catch {
    [Console]::Error.WriteLine("Inventory failed part-way: $($_.Exception.Message)")
    $code = 2
} finally {
    if ($conn) { Disconnect-VIServer -Server $conn -Confirm:$false -ErrorAction SilentlyContinue }
}
exit $code
