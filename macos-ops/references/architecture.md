# macOS architecture reference

## Kernel and drivers

macOS runs the XNU kernel: Mach (tasks, threads, ports and IPC, virtual memory), a BSD layer (POSIX processes, signals, sockets, the VFS) and I/O Kit (the C++ driver framework). Its userland derives from FreeBSD, not Linux, so event notification is `kqueue`, the init system is `launchd`, and there is no `systemd`, `journald` or built-in package manager.

Drivers have moved out of the kernel. Kernel extensions (kexts) are legacy; new third-party code uses **system extensions**: DriverKit drivers, Network Extensions and Endpoint Security clients. `systemextensionsctl list` shows them with a state (for example `activated enabled`, `activated waiting for user`, or a terminated state awaiting removal); `kmutil` manages the remaining kexts. Endpoint Security clients need an Apple-granted entitlement; management can pre-approve system extensions through a profile (`macos-mdm-ops`).

## Boot, SIP and the sealed system volume

- **System Integrity Protection (SIP)** restricts changes to protected system paths and to the runtime of Apple processes, even for root. `csrutil status` reads it; changing it needs macOS Recovery (hold the power button on Apple silicon, Command-R on Intel).
- **Signed system volume (SSV)**: the system volume is sealed with a cryptographic hash tree and mounted read-only; user data lives on the Data volume (`/System/Volumes/Data`, firmlinked into `/`). `csrutil authenticated-root status` reports whether the seal is enforced.
- **Apple silicon boot policy** is managed with `bputil` (Recovery; its man page says it is not to be used in production environments, and a wrong policy can leave the Mac unbootable) and the Security Policy options in Startup Security Utility; kernel extensions require reduced security. **Intel Macs with a T2 chip** (2018 to 2020 models) have Secure Boot and hardware-encrypted storage controlled by the T2; older Intel Macs do neither.

## launchd

`launchd` is PID 1. It starts daemons and agents from property lists and replaces `init`, `cron`, `inetd` and `atd`.

| Kind | Location | Runs as |
|---|---|---|
| System daemon | `/Library/LaunchDaemons` | root or the named user, at boot |
| System agent | `/Library/LaunchAgents` | each logged-in user |
| User agent | `~/Library/LaunchAgents` | that user |
| Apple's own | `/System/Library/LaunchDaemons`, `/System/Library/LaunchAgents` | do not edit |

Common plist keys (see `man launchd.plist`): `Label`, `Program` or `ProgramArguments`, `RunAtLoad`, `KeepAlive`, `StartInterval`, `StartCalendarInterval`, `WatchPaths`, `StandardOutPath`, `StandardErrorPath`. Daemons and system agents must be owned by root and not writable by group or others. `launchctl` addresses a job as `<domain>/<label>` where the domain is `system`, `gui/<uid>`, `user/<uid>` or `pid/<pid>`; subcommands include `bootstrap`, `bootout`, `enable`, `disable`, `kickstart`, `kill`, `print`, `print-disabled`, `blame` and `managerpid`. `load` and `unload` are legacy. Scheduled work belongs in launchd (`StartCalendarInterval`), not `cron`.

## APFS

An APFS **container** holds several **volumes** that share its free space; there are no fixed partition sizes. A macOS boot container has volumes for the system (sealed), Data, Preboot, Recovery and VM (swap). APFS uses copy-on-write for metadata and data, so there is no journal fsck in the old sense; `diskutil verifyVolume` and `fsck_apfs` verify. Snapshots (used by Time Machine local snapshots and software update) are listed with `diskutil apfs listSnapshots` and `tmutil listlocalsnapshots /`. `cp -c` creates a clone that costs no space until modified. FileVault encryption is per volume.

## Apple silicon and Intel

Apple silicon (M-series, and the A-series chip in the MacBook Neo) has unified memory shared by CPU, GPU and Neural Engine, a Secure Enclave in the SoC, and hardware support for virtualisation, FileVault and Recovery Lock. `uname -m` reports `arm64` natively and `x86_64` for Intel or for a process running under Rosetta; `arch -arm64` and `arch -x86_64` launch a command in a chosen architecture, and `lipo -info <binary>` lists the slices of a universal binary. **Rosetta** translates Intel binaries on Apple silicon; install it with `softwareupdate --install-rosetta`. Apple's support page says Rosetta is available on macOS 27 or earlier, and from macOS 28 only for certain older games. `system_profiler SPHardwareDataType` reports the chip; the chip's feature set and memory limits belong on Apple's tech specs page, not in a table copied from memory.

Virtualization.framework runs Linux guests (and macOS guests on Apple silicon) with hardware acceleration; desktop virtualisation products and container tools on Apple silicon build on it.

## Application model

An `.app` bundle holds `Contents/Info.plist`, `Contents/MacOS/<executable>`, resources and a code signature. Gatekeeper checks the signature, notarisation and the `com.apple.quarantine` extended attribute on first launch; XProtect is Apple's signature-based scanner; sandboxed apps are confined to `~/Library/Containers/<bundle id>`. Privacy permissions (camera, microphone, files and folders, Full Disk Access, screen recording) are governed by **TCC**; the databases are protected, and macOS 27 stops apps reading the local TCC database directly.

## Users, groups and keychains

Local accounts live in the local directory node (`dscl .`); the `admin` group grants `sudo`. Keychains: the login keychain (per user, unlocked at login), the System keychain (`/Library/Keychains/System.keychain`, machine-wide) and iCloud Keychain. The `security` tool reads and writes them. Do not store secrets in command lines (`secrets-hygiene`).

## Networking

`configd` maintains the System Configuration dynamic store; `networksetup` edits service settings, `scutil` reads and sets names and shows DNS, proxy and VPN state; `mDNSResponder` provides DNS and Bonjour. `/etc/resolv.conf` is generated and must not be edited. The application firewall (`socketfilterfw`) filters inbound connections per application; from macOS 15 its configuration is no longer the `com.apple.alf.plist` property list. VPN uses the built-in IKEv2 client (macOS 26 removed DES, 3DES, SHA1-96, SHA1-160 and Diffie-Hellman groups below 14) or Network Extension providers.

## Frameworks worth knowing by name

Foundation, AppKit, SwiftUI, Core Data and SwiftData, Core ML, Metal, Security (keychain, code signing), Network Extension, Endpoint Security, System Extensions, DriverKit, Virtualization, and from macOS 27 the ManagedApp framework. Developer toolchain questions (Xcode, Swift) are outside this skill.
