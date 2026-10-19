# Windows Server diagnostics reference

Read-only diagnostics first; commands that change state or add load are marked. Thresholds are rules of thumb, not Microsoft limits. Syntax has not been run on live systems.

---

## Event logs

| Log | Purpose |
|---|---|
| System | OS components, drivers, services |
| Application | Applications and the .NET runtime |
| Security | Audit events (needs elevation to read) |
| Setup | Updates and feature installs |
| Microsoft-Windows-SMBServer/Operational | SMB connection problems |
| Microsoft-Windows-PowerShell/Operational | Script block logging |
| Microsoft-Windows-NTLM/Operational | NTLM audit events when NTLM auditing is configured |

### Event IDs worth knowing

| ID | Log | Meaning |
|---|---|---|
| 41 (Kernel-Power) | System | Restart without a clean shutdown |
| 6008 | System | Previous shutdown was unexpected |
| 1074 | System | Planned shutdown or restart, with who and why |
| 7034 | System | Service terminated unexpectedly |
| 7036 | System | Service entered the running or stopped state |
| 7045 | System | A new service was installed (review each one) |
| 104 | System | Event log cleared |
| 1102 | Security | Audit log cleared |
| 1000 | Application | Application crash with faulting module |
| 4625 | Security | Failed logon (read the SubStatus) |
| 4672 | Security | Special privileges assigned to a logon |
| 4740 | Security | Account lockout |

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008, 1074; StartTime = (Get-Date).AddDays(-7) }
```

`Get-WinEvent` raises `NoMatchingEventsFound` when nothing matches; scripts must treat that error as zero, and any other error as a failure to check. Failed logon detail (user, workstation, sub status) is in the event XML:

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddDays(-1) } | ForEach-Object {
    $x = [xml]$_.ToXml()
    [pscustomobject]@{
        Time        = $_.TimeCreated
        Account     = ($x.Event.EventData.Data | Where-Object Name -eq 'TargetUserName').'#text'
        Workstation = ($x.Event.EventData.Data | Where-Object Name -eq 'WorkstationName').'#text'
        SubStatus   = ($x.Event.EventData.Data | Where-Object Name -eq 'SubStatus').'#text'
    }
}
```

---

## Performance counters

| Counter | Warning | Critical |
|---|---|---|
| `\Processor(_Total)\% Processor Time` | sustained above about 70 | above about 90 |
| `\System\Processor Queue Length` | above about 2 per logical CPU | above about 4 per logical CPU |
| `\Processor(*)\% Privileged Time` | above about 20 | above about 35 (suspect a driver) |
| `\Memory\Available MBytes` | below 10 per cent of RAM | below 5 per cent |
| `\Memory\Pages/sec` | above about 100 | above about 500 |
| `\Memory\% Committed Bytes In Use` | above 80 | above 95 |
| `\PhysicalDisk(*)\Avg. Disk sec/Read` and `/Write` | above about 0.02 s | above about 0.05 s |
| `\PhysicalDisk(*)\Current Disk Queue Length` | above about 2 | above about 4 sustained |
| `\LogicalDisk(*)\% Free Space` | below 20 | below 10 |
| `\Network Interface(*)\Output Queue Length` | above 2 | above 4 |
| `\Network Interface(*)\Packets Received Errors` | above 0 | any sustained |

```powershell
Get-Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes' -SampleInterval 5 -MaxSamples 12
```

Counter names are English; on a localised install use `Get-Counter -ListSet *` to find the localised paths. `logman create counter ...` followed by `logman start` creates a Data Collector Set and is state-changing; use it for a 24-hour baseline in the first week.

---

## Workflows

**High CPU:** top processes (`Get-Process | Sort-Object CPU -Descending`), per-core counters, processor queue length, then privileged versus user time (high privileged time points at a driver).

**Memory pressure:** available MB and pages per second over time; top working sets; nonpaged pool growth over a long sample (a leak pattern); commit charge against the limit.

**Disk latency:** confirm with the latency and queue counters, check Storage Spaces health (`Get-VirtualDisk`, `Get-PhysicalDisk`), then reliability counters (`Get-PhysicalDisk | Get-StorageReliabilityCounter`).

**Network:** `Test-NetConnection -ComputerName <host> -Port <port>`, `Resolve-DnsName <name> -Server <dns>`, `Get-NetTCPConnection -State Listen`, `Get-SmbConnection`.

---

## System information

```powershell
Get-ComputerInfo | Select-Object CsName, OsName, OsVersion, OsArchitecture, OsLastBootUpTime
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
Get-NetAdapter | Select-Object Name, Status, LinkSpeed
```

---

## Packet capture

```powershell
netsh trace start capture=yes tracefile=C:\Logs\capture.etl maxsize=512   # adds load; state-changing
netsh trace stop
pktmon filter add -p 445                       # state-changing
pktmon start --capture ; pktmon stop           # state-changing; writes PktMon.etl in the current directory by default
pktmon etl2pcap PktMon.etl                     # pktmon is available on 2019 and later
```

Capture only as long as needed and treat capture files as sensitive.

---

## Stop errors (blue screens)

Check dump settings: `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl | Select-Object CrashDumpEnabled, DumpFile, MiniDumpDir, AutoReboot`. Dump files are `%SystemRoot%\MEMORY.DMP` (kernel or complete) and `%SystemRoot%\Minidump\`.

| Stop code | Hex | Common causes |
|---|---|---|
| IRQL_NOT_LESS_OR_EQUAL | 0xA | Driver touching memory at the wrong IRQL |
| SYSTEM_SERVICE_EXCEPTION | 0x3B | Driver or system service exception |
| PAGE_FAULT_IN_NONPAGED_AREA | 0x50 | Driver bug, bad RAM, corrupt system file |
| KERNEL_DATA_INPAGE_ERROR | 0x7A | Disk read failure |
| CRITICAL_PROCESS_DIED | 0xEF | A critical process exited |

In WinDbg: `!analyze -v`, `lm o m *` (non-Microsoft modules), `kp` (stack), `!poolused 2`. Driver Verifier (`verifier /standard /driver <name>`) forces crashes on violations: test machines only, and `verifier /reset` to turn it off.

---

## WinRM and remoting

```powershell
winrm enumerate winrm/config/listener                 # read-only
Test-WSMan -ComputerName server01 -Authentication Kerberos
Enable-PSRemoting -Force                              # state-changing
```

TCP 5985 (HTTP) and 5986 (HTTPS). For an HTTPS listener choose a certificate whose subject matches the name clients use. For workgroup targets use TrustedHosts with the narrowest scope possible; it weakens mutual authentication.

---

## DTrace (Windows Server 2025)

Microsoft lists `dtrace` as a native tool in Windows Server 2025. It needs administrator rights and instruments kernel and user code, so scope probes with predicates and never leave broad probes running. Check installation with `Get-Command dtrace` before assuming it; installation and feature naming can differ by build.
