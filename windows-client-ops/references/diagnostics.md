# Windows client diagnostics reference

Read-only diagnostics first; commands that change state or add load are marked. Syntax has not been run on live systems.

---

## System file repair

```powershell
sfc /verifyonly                                   # read-only
DISM /Online /Cleanup-Image /CheckHealth          # read-only, fast
DISM /Online /Cleanup-Image /ScanHealth           # read-only, slow
DISM /Online /Cleanup-Image /RestoreHealth        # state-changing: repairs the component store from Windows Update
sfc /scannow                                      # state-changing: repairs protected files
```

Order for repair: `DISM /RestoreHealth` first, then `sfc /scannow`, then restart. A local source is possible with `/Source:<path> /LimitAccess`. Logs: `C:\Windows\Logs\CBS\CBS.log` and `C:\Windows\Logs\DISM\dism.log`.

## Reliability Monitor and memory

`perfmon /rel` shows crashes, failures and installs on a timeline; use it first for user-reported problems. `mdsched.exe` schedules a memory test at the next restart (state-changing); read results from System events 1101 and 1201.

## Drivers

```powershell
Get-PnpDevice | Where-Object Status -ne 'OK' | Select-Object FriendlyName, Class, Status, Problem
pnputil /enum-drivers
Get-CimInstance Win32_PnPSignedDriver | Where-Object { -not $_.IsSigned } | Select-Object DeviceName, DriverVersion, InfName
```

Common problem codes: 1 not configured correctly, 10 cannot start, 28 no driver installed, 43 device reported a problem (common for USB and GPU), 45 not connected. GPU timeout events: System event 4101. Driver rollback is a Device Manager action (Driver tab, Roll Back Driver). Driver Verifier (`verifier /standard /driver <name>`, `verifier /reset`) forces crashes on violations; test machines only.

## Application compatibility

`msdt.exe -id PCWDiagnostic` starts the compatibility troubleshooter (the Microsoft Support Diagnostic Tool has been deprecated; check availability on current builds). Compatibility flags live under `AppCompatFlags\Layers` in HKLM and HKCU and are readable with `Get-ItemProperty`.

## Startup and performance

- Task Manager Startup tab shows startup impact. `msconfig` supports clean-boot testing (state-changing).
- Sysinternals Autoruns (`autorunsc -a * -c`) lists persistence locations; download it from Microsoft and verify the signature.
- Windows Performance Recorder and Analyzer capture and read ETW traces (`wpr -start GeneralProfile`, `wpr -stop <file>.etl`); traces are large and can contain sensitive data.
- Counters (rules of thumb): processor time sustained above about 70 per cent warning and 90 critical; available memory below 10 per cent of RAM; disk read latency above about 20 ms for SSD-class storage; privileged time above about 20 per cent suggests a driver.

```powershell
Get-Counter '\Processor(_Total)\% Processor Time','\Memory\Available MBytes','\PhysicalDisk(_Total)\Avg. Disk sec/Read' -SampleInterval 5 -MaxSamples 6
```

## Storage

- **Storage Sense** cleans temporary files and old downloads on a schedule (Settings, System, Storage, or policy under Administrative Templates, System, Storage Sense).
- **Disk Cleanup** (`cleanmgr /sageset:<n>` then `/sagerun:<n>`) is state-changing and deletes data.
- **Component store:** `DISM /Online /Cleanup-Image /AnalyzeComponentStore` reads the real size (the WinSxS folder size in Explorer is inflated by hard links). `StartComponentCleanup` removes superseded components; adding `/ResetBase` makes updates uninstallable, so it is a one-way step.
- **Compact OS:** `compact /compactos:query` reads state; `always` and `never` change it.
- **Delivery Optimisation cache:** `Get-DeliveryOptimizationStatus` reads; `Delete-DeliveryOptimizationCache -Force` deletes.

## Power and battery

```powershell
powercfg /a                    # available sleep states (read-only)
powercfg /lastwake
powercfg /devicequery wake_armed
powercfg /sleepstudy           # writes an HTML report
powercfg /batteryreport        # writes an HTML report
powercfg /energy               # runs a trace for about a minute and writes a report
```

Unexpected wake: check `lastwake` and `wake_armed`. Drain in Modern Standby: the sleep study. Slow boot: boot trace with WPR.
