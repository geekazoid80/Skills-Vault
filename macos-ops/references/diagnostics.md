# macOS diagnostics reference

Read-only unless marked. Options below were checked against the man pages of a macOS 26.7.1 machine.

## Unified logging

`log` replaced syslog. Messages carry a subsystem, category, process and level, and are kept in a compressed binary store.

```sh
log show --last 1h --style compact --predicate 'process == "kernel"'
log show --last 30m --predicate 'subsystem == "com.apple.network" AND messageType == error'
log stream --predicate 'eventMessage CONTAINS "failed"'      # live
log show --info --debug --last 10m                           # include Info and Debug levels
sudo log collect --last 2h --output ~/Desktop/recent.logarchive   # archive for another Mac (needs root)
```

Predicate fields in common use: `subsystem`, `category`, `process`, `processID`, `eventMessage`, `messageType` (`default`, `info`, `debug`, `error`, `fault`). Info and Debug messages are stored only when requested or enabled, so an absence of Debug lines proves nothing. Subsystem names such as `com.apple.ManagedClient` (management) and `com.apple.AppSSO` (Platform SSO) are conventions seen in logs; confirm them with `log stream` before relying on them. `sysdiagnose` gathers a large diagnostic bundle (run as root; allow a couple of minutes and gigabytes); `Console.app` browses archives.

## Crashes, hangs and panics

- Reports: `~/Library/Logs/DiagnosticReports` (user processes) and `/Library/Logs/DiagnosticReports` (system, panics). Modern reports are `.ips` JSON files with exception type, threads and loaded images; older `.crash`, `.hang`, `.spin` and `.panic` files exist too.
- A hang: `sample <process> 10` (CPU sample, no root for your own processes) and `sudo spindump` (all threads of hung processes).
- A kernel panic: read the newest `.panic`/`.ips` report in the system folder, the macOS build, and recent third-party extensions (`systemextensionsctl list`, `kmutil showloaded`). Apple silicon and Intel reports differ in layout.

## Performance

```sh
top -o cpu -l 2 -n 10                  # CPU by process (second sample is the real one)
vm_stat 2                              # page statistics every 2 seconds
sysctl kern.memorystatus_level         # percent of memory free
iostat -d 2 5                          # disk throughput
sudo fs_usage -f filesys -w            # file system calls (root)
sudo powermetrics --samplers cpu_power,thermal -n 1   # power and thermal (root, Apple silicon and Intel)
pmset -g therm                         # thermal and CPU speed limit
```

Do not run `memory_pressure` to read state: its man page describes applying or simulating memory pressure. Activity Monitor's memory pressure graph (green, yellow, red) is the human-facing signal; `kern.memorystatus_level` is the scriptable one.

## Disk

```sh
diskutil list
diskutil info /
diskutil apfs list
diskutil verifyVolume /               # verify (read-only); repair needs Recovery for the boot volume
tmutil listlocalsnapshots /           # local snapshots
df -Pk /System/Volumes/Data           # free space on the data volume
```

`diskutil info` shows `SMART Status` where the device reports it (Apple silicon internal storage often reports Verified or Not Supported). `fsck_apfs` runs from Recovery or on an unmounted volume.

## Network

```sh
networksetup -listallnetworkservices
networksetup -getinfo "Wi-Fi"
networksetup -getdnsservers "Wi-Fi"
scutil --dns                           # resolver configuration
scutil --proxy                         # proxy configuration
scutil --nc list                       # VPN services
route -n get default                   # default interface and gateway
sudo wdutil info                       # Wi-Fi details (its man page marks only diagnose and log as needing sudo; info is shown with sudo here as a precaution)
networkQuality                         # throughput and responsiveness test (active)
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

`scutil --dns` is the truth for name resolution (several resolvers, scoped by domain); `dscacheutil -q host -a name <name>` resolves through the system resolver as applications do, where `dig` queries a server directly. Flush the DNS cache with `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` (changes state). Do not edit `/etc/resolv.conf`.

## Startup, login and launchd

`launchctl print system` and `launchctl print gui/$(id -u)` list jobs; `launchctl print system/<label>` shows one service's state, last exit status and program; `launchctl blame <service-target>` explains why a service started; `launchctl print-disabled system` shows persistent overrides (the man page says `print` and `print-disabled` output is not for automation, so read it by eye and do not parse it). A job that exits immediately usually has a missing program, wrong ownership or permissions, or a bad plist (`plutil -lint <file>`).

## Management and Platform SSO

Enrollment, profile, declaration and Platform SSO diagnostics are in `macos-mdm-ops`. `profiles status -type enrollment` is quick and local; `profiles show -type enrollment` contacts the server and may be rate limited.

## When to escalate

- Reproducible panic after a clean install: Apple Support with the `.ips`/`.panic` report and `sysdiagnose`.
- Hardware tests: Apple Diagnostics at startup (Apple silicon: hold the power button, then Command-D).
- Data at risk: stop writing to the volume, take a Time Machine or file-level copy, and verify it before any repair.
