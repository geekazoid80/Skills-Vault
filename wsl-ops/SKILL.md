---
name: wsl-ops
description: "Use for Windows Subsystem for Linux (WSL) administration and troubleshooting on Windows 10 and 11: installing and updating WSL, WSL 1 versus WSL 2, distribution management (import, export, move, resize), .wslconfig and wsl.conf settings, memory and virtual disk growth, networking (NAT, mirrored, DNS tunnelling, proxy, VPN, Hyper-V firewall, port proxy), systemd, GPU and USB access, WSLg, Windows filesystem performance, and enterprise control with Intune and the Defender for Endpoint plug-in. Triggers include \"WSL\", \"WSL2\", \"wsl --install\", \".wslconfig\", \"wsl.conf\", \"Vmmem\", \"ext4.vhdx\", \"wsl --shutdown\", \"mirrored networking\", \"WSL no internet behind VPN\", \"WSL disk space\", \"WSL systemd\", \"usbipd\", \"WSLg\", \"WSL containers\", \"Intune WSL policy\". NOT for administering the Linux distribution inside WSL as a server (linux-host-ops), NOT for Hyper-V hosts and VMs (hyper-v-ops), NOT for general Windows desktop administration (windows-client-ops), NOT for Docker or Podman themselves (docker-ops, podman-ops, container-runtime-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# WSL operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: wsl-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

WSL runs Linux distributions on Windows. **WSL 2** (the default) runs a real Linux kernel in a lightweight utility virtual machine managed by Windows; **WSL 1** translates Linux system calls to Windows. WSL is delivered and updated as a Microsoft Store or MSI package (`wsl --update`) separate from the Windows build, and its source has been open since May 2025, so versions move faster than Windows releases. Behaviour, defaults and settings depend on the WSL version and the Windows build, so pin both before advising.

**Core principle:** the Windows side and the Linux side have separate owners, settings files and failure modes. Say which side a command runs on (`.wslconfig` and `wsl.exe` are Windows; `/etc/wsl.conf` and everything else is inside the distribution), and treat destructive commands (`--unregister`, `--import` over an existing name, deleting a VHD) as irreversible until there is an export.

> **Caveat on provenance.** Settings, defaults and scripts were reshaped from a community upstream, corrected against Microsoft Learn pages and Microsoft's announcements read on 2026-10-19, and reviewed independently. Several upstream defaults were out of date (DNS tunnelling, auto proxy and the Hyper-V firewall now default to on for Windows 11 22H2 and later; memory reclaim defaults to `dropCache`; `sparseVhd` is still experimental and off). Scripts are mock-tested only.

## Step 0: establish what you are on

```powershell
wsl --version                 # WSL package version (an old inbox WSL has no --version: run wsl --update)
wsl --status
wsl --list --verbose          # NAME, STATE, VERSION (1 or 2) for each distribution
[System.Environment]::OSVersion.Version   # Windows build; 19041 is the minimum for wsl --install and .wslconfig, 22621 (Windows 11 22H2) for mirrored networking
```

Capturing `wsl.exe`'s own output (`--list`, `--version`, `--status`) in PowerShell yields UTF-16 text with embedded NUL characters; set `[Console]::OutputEncoding = [System.Text.Encoding]::Unicode` or strip them. Output of a command run inside a distribution (`wsl -d <name> -- ...`) is UTF-8 and must be decoded as such. The shipped scripts do both. The scripts in `scripts/` gather the rest.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive or disruptive, get explicit approval |
|---|---|---|
| `wsl --version`, `--status`, `--list`, `--list --online`, `wsl -d <name> -- cat ...` (starts the distribution if it is stopped), reading `.wslconfig` | `wsl --install`, `--update`, `--set-default-version`, `--set-version`, `--set-default`, editing `.wslconfig` or `/etc/wsl.conf`, `--export`, `--manage <name> --resize`, `--mount` | `wsl --shutdown` (stops every distribution and the VM), `--terminate`, `--unregister` (deletes the distribution and its data), `--import` or `--import-in-place` over an existing name, compacting or deleting a `.vhdx`, `--update --pre-release`, any enterprise policy change |

## WSL 1 and WSL 2

| | WSL 1 | WSL 2 |
|---|---|---|
| Kernel | None; syscall translation | Real Linux kernel in a utility VM (Microsoft-built, open source) |
| Linux file performance | Slower | Much faster (ext4 on a virtual disk) |
| Access to Windows files | Fast | Slower across the VM boundary (9P) |
| System call compatibility | Partial | Full |
| Docker daemon, KVM, eBPF | No | Yes (nested virtualisation permitting) |

Keep project files inside the Linux filesystem (`~/project`), not under `/mnt/c/`, for builds and Git. Reach Linux files from Windows at `\\wsl.localhost\<distro>\`. WSL 1 remains for the rare case of heavy cross-filesystem I/O with no need for a kernel; enterprise policy can disable it.

## Installation and distributions

- `wsl --install` needs Windows 10 version 2004 (build 19041) or later, or Windows 11; it enables Virtual Machine Platform and installs the default distribution. On older Windows 10 use `wsl --install -d <name>`. `--no-launch` and `--web-download` change how the install happens.
- `wsl --list --online` lists distributions; `wsl --set-default-version 2`; `wsl --set-version <name> 2` converts.
- **Backup and clone:** `wsl --export <name> <file.tar>`; `wsl --import <new-name> <install-dir> <file.tar> --version 2`; `wsl --import-in-place <name> <file.vhdx>` registers an existing virtual disk.
- **Disk:** each distribution's `ext4.vhdx` grows up to 1 TB by default (older releases 512 or 256 GB) and does not shrink by itself. Grow the limit with `wsl --manage <name> --resize <size>` after `wsl --shutdown` (WSL 2.5 and later; whole-number sizes only, so 2TB not 2.5TB). To reclaim space: delete files, run `sudo fstrim -av`, `wsl --shutdown`, then compact the VHDX with `wsl --manage <name> --compact` where the WSL package has it (it appears in the 3.0 series; absent in 2.7), or with `Optimize-VHD -Mode Full` where Hyper-V tools exist, or `diskpart` with `compact vdisk`. `wsl --manage <name> --move <location>` relocates a distribution on current releases. `sparseVhd` and `wsl --manage --set-sparse` are experimental, off by default, and have had corruption reports: export a backup first and prefer the compaction route.
- The shipped `wsl-health.ps1` reads each registered distribution's disk size from the user's `Lxss` registry key.

## Configuration files

| File | Where | Scope | Takes effect |
|---|---|---|---|
| `.wslconfig` | Windows `%UserProfile%` | All WSL 2 distributions (the VM) | After `wsl --shutdown` |
| `/etc/wsl.conf` | Inside each distribution | That distribution | After that distribution restarts |

Defaults worth knowing (Microsoft Learn, 2026-10-19): `memory` is 50 per cent of Windows memory, `processors` all logical processors, `swap` 25 per cent of Windows memory rounded up to a whole GB, `vmIdleTimeout` 60,000 ms, `defaultVhdSize` 1 TB, `nestedVirtualization` true (Windows 11, not ARM64), `networkingMode` NAT, `guiApplications` true, `autoMemoryReclaim` (experimental) `dropCache` with `gradual` and `disabled` available, `sparseVhd` (experimental) false and applying only to newly created disks. In `[general]`, `instanceIdleTimeout` defaults to 15,000 ms. In `/etc/wsl.conf`: `[boot] systemd` defaults to false for the key (but systemd is on by default in the current Ubuntu that `wsl --install` fetches), `[automount]`, `[network] generateResolvConf`, `[interop]`, `[user] default`, `[gpu]`, `[time]`. Some `.wslconfig` keys apply only on Windows 11 (marked in the documentation); read the table on the Learn page for the one you are setting.

Cap `memory` and `processors` on shared or small machines; the VM's memory shows against a `vmmem` process in Task Manager.

## Networking

- **NAT** (default): the VM gets a private address behind the host; localhost forwarding reaches Linux services from Windows; the address changes after a restart; VPN clients that change routes or DNS often break it.
- **Mirrored** (`networkingMode=mirrored`, Windows 11 22H2 or later): Linux sees the host's interfaces; IPv6, multicast, LAN access to WSL and better VPN behaviour; connect to Windows from Linux at `127.0.0.1` (`::1` is not supported). Allow inbound traffic through the Hyper-V firewall deliberately (below).
- **DNS tunnelling** (`dnsTunneling`, Windows 11 22H2 or later) and **auto proxy** (`autoProxy`, Windows 11) default to on. `bridged` is deprecated; a `consomme` mode exists and WSL 2.3.25 and later fall back to it when NAT fails. `networkingMode=none` disconnects WSL.
- **Hyper-V firewall:** on Windows 11 22H2 with WSL 2.0.9 or later Windows firewall rules apply to WSL by default. The WSL creator ID is `{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}`; inspect with `Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'` and `Get-NetFirewallHyperVRule -VMCreatorId ...`. Changing the default inbound action to Allow exposes WSL services to the network: do it only on purpose.
- **Port proxy** (`netsh interface portproxy`) forwards a Windows port to a NAT-mode address; rules go stale when the address changes. Prefer mirrored mode where available.
- For "no internet behind the VPN": check the mode, enable mirrored plus DNS tunnelling on Windows 11, check `/etc/resolv.conf`, and restart WSL after the VPN connects on Windows 10.

## systemd, GPU, USB, GUI

- **systemd:** needs WSL 0.67.6 or later; enable with `[boot] systemd=true` in `/etc/wsl.conf` and `wsl --shutdown`. The `[boot]` section is documented for Windows 11 and Windows Server 2022 and later.
- **GPU:** WSL 2 uses GPU paravirtualisation with the Windows host driver; install the vendor's Windows driver and do not install a Linux display driver inside the distribution. CUDA, DirectML and containers with GPU access have vendor-specific steps in Microsoft's tutorial. Windows 11, or Windows 10 21H2 or later.
- **USB:** not built in. Use `usbipd-win` (`winget install --interactive --exact dorssel.usbipd-win`) with kernel 5.10.60.1 or later; x64 and ARM64 only; share a device with `usbipd bind --busid <id>` (elevated, once) and then `usbipd attach --wsl --busid <id>` (no elevation); keep a WSL prompt open so the VM stays running.
- **WSLg:** Linux GUI applications; Windows 10 build 19044 or later, or Windows 11; install the vGPU driver for acceleration.

## Enterprise control and security

- **Intune** (Settings catalog, "Windows Subsystem for Linux"): allow or block WSL, the inbox component, WSL 1, the debug shell, custom kernel, kernel command line, custom system distribution, custom networking, user firewall settings, nested virtualisation and kernel debugging. There are also settings for the passthrough disk mount (`wsl --mount`) and for WSL itself. Microsoft's recommended-settings table sets the inbox component, WSL 1, the debug shell, custom kernel, kernel command line, custom system distribution, custom networking, user firewall setting, nested virtualisation and kernel debugging all to Disabled; most of these policies apply to the Store/MSI WSL only.
- **Defender for Endpoint plug-in for WSL 2:** gives security teams visibility of process, file and network events inside running distributions. Requirements include Microsoft Defender for Endpoint Plan 2 with the device onboarded, WSL 2.0.7 or later (2.9.12 or later for WSL containers), Windows 10 build 19044 (21H2) or later or Windows 11, no ARM64, no multi-session Windows; allow up to 30 minutes for a new instance to appear; custom kernels and kernel command lines are unsupported; antimalware and vulnerability management features are not available for the WSL logical device. See `defender-for-endpoint`.
- **Microsoft's enterprise page (last updated 2024-08-16) lists as not yet supported:** patching Linux distributions with Windows tools, Windows Update updating distribution contents, restricting which distributions users may install, and controlling root access inside WSL; check whether that has changed. Use Linux configuration management inside the distribution and your own image process (`wsl --export`, `--import`).
- **Files and credentials:** Linux files live inside the VHDX; Windows tools that scan paths do not see them unless the plug-in or an in-guest agent does. Processes in a distribution run with the Windows user's rights on Windows files. Keys and tokens in a distribution are readable by any process in it: do not paste credentials into commands (`secrets-hygiene`).
- **WSL containers (WSLc):** Microsoft announced general availability on 29 September 2026: a `wslc` command line and an API to run Linux containers on Windows, with Intune control, a container registry allow list (it limits which registries images may be pulled from) and Defender for Endpoint plug-in coverage. It shipped with the WSL 3.0 package series (3.0.1 on that date; 3.0.3 was the current stable release on 2026-10-09), the plug-in page asks for WSL 2.9.12 or later, and `.wslconfig` does not apply to `wslc`. Confirm details in Microsoft Learn and the WSL release notes before relying on it.

## Pitfalls

1. Repositories and `node_modules` under `/mnt/c/`.
2. No `memory` cap on a small machine, and surprise at `vmmem` size.
3. A virtual disk that only ever grows; compacting without an export first.
4. Editing `.wslconfig` and forgetting `wsl --shutdown`.
5. `wsl --unregister` run on the wrong name.
6. Installing a display driver inside the distribution for GPU use.
7. Port proxy rules left behind after the NAT address changed.
8. Treating a Windows 10 machine as if it had mirrored networking, DNS tunnelling or the Hyper-V firewall.
9. Assuming Windows security tooling sees inside the distribution.
10. Assuming a default from an old blog post (several have changed).

## Red flags

- A setting or default stated without checking the Learn page for the current WSL version.
- A destructive `wsl` command with no export or confirmation.
- Credentials or tokens written into a command, `.wslconfig` or a script.
- Advice to enable `sparseVhd` or `--set-sparse` (and the version-dependent `--allow-unsafe` override) without a backup.

## References and scripts

- `references/architecture.md`: WSL 1 and 2 internals, storage, filesystem boundary, networking modes, GPU, WSLg, systemd, interop.
- `references/best-practices.md`: configuration, memory and disk management, development workflow, distribution lifecycle, enterprise deployment, security.
- `references/diagnostics.md`: command quick reference and troubleshooting by symptom.
- `scripts/wsl-health.ps1`, `wsl-network.ps1`: read-only checks. With `-ProbeGuest` they run read-only commands only inside distributions that `wsl --list` reports as running at that moment (a distribution that idles out in between could be started by the call). Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a query that fails or returns nothing), 2 critical findings. A check that could not run is therefore never a clean pass.

The scripts only read state, run as the current user (`wsl-health.ps1` also warns when not elevated, because optional feature state needs elevation), and are compatible with Windows PowerShell 5.1 and PowerShell 7. They are parse-checked and were run against mocked `wsl.exe` and Windows cmdlets, including an empty-result world and a throwing world (none exits 0), but not on a live Windows system. Parsing of `wsl.exe` output assumes English state names; other languages produce a warning, not a pass.

## Boundaries

- Running a Linux server inside WSL: `linux-host-ops` and `linux-host-bringup`.
- Hyper-V hosts and VMs (WSL 2 uses the same platform): `hyper-v-ops`.
- Windows desktop management, Intune enrolment and Windows 10 end of support: `windows-client-ops`.
- Docker, Podman and container runtime choice: `docker-ops`, `podman-ops`, `container-runtime-selection`.
- Defender for Endpoint tenant configuration: `defender-for-endpoint`.
- Credentials: `secrets-hygiene`. PowerShell module problems: `powershell-module-compat`.

## Bottom line

Pin the WSL version and Windows build, keep files in the Linux filesystem, cap memory, export before anything destructive, choose mirrored networking where the build allows, and verify every default and enterprise control against Microsoft's current pages because WSL changes faster than Windows.
