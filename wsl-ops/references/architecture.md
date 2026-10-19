# WSL architecture reference

## WSL 1

Introduced with the Windows 10 Anniversary Update (version 1607). No Linux kernel: kernel-mode components (`lxss.sys` and `lxcore.sys`) accept Linux system calls from ELF binaries and map them to NT operations. Linux paths are emulated on NTFS; access to Windows drives is fast because nothing crosses a VM boundary. Coverage of Linux system calls is partial, and there is no Docker daemon, KVM or full eBPF. The kernel components remain part of Windows rather than the open-source WSL package.

## WSL 2

A real Linux kernel (Microsoft builds it from the latest stable branch and publishes the source) runs in a lightweight utility virtual machine on the Windows hypervisor platform. By default all WSL 2 distributions share one VM and one kernel but have separate root filesystems and namespaces. The VM starts on demand, stops after the idle timeouts (`instanceIdleTimeout` for a distribution, `vmIdleTimeout` for the VM) and is managed with `wsl --shutdown`, `--terminate` and `--update`. Requires the Virtual Machine Platform feature and (for the VM) hardware virtualisation; running it inside another VM needs nested virtualisation.

The WSL package (Store or MSI) carries the user-mode components and the kernel, so WSL can be updated without a Windows feature update. The source of WSL (excluding the WSL 1 kernel drivers and the 9P redirector components) is open on GitHub, as are WSLg and the kernel.

## Storage

Each WSL 2 distribution's root filesystem is an ext4 filesystem in a `ext4.vhdx` file (under `%LOCALAPPDATA%\wsl\{GUID}` for current installs, or under the old Store package folders). Maximum size 1 TB by default. The VHDX grows on demand and does not shrink when files are deleted, because the host cannot see which blocks the guest freed unless the disk is trimmed and compacted. Registrations are stored per Windows user under `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`, so another Windows account sees none of them.

## Crossing the filesystem boundary

- **Windows to Linux:** `\\wsl.localhost\<distro>\` (the older `\\wsl$\` alias also works), served by a 9P server in the VM.
- **Linux to Windows:** drives mount under `/mnt/<letter>` (DrvFs). Options such as `metadata`, `umask` and `fmask` in `/etc/wsl.conf` `[automount]` control permission mapping.
- Each operation across the boundary pays a protocol round trip, so trees of many small files (package caches, `node_modules`, build directories) are much slower on the Windows side. Keep working trees in the Linux filesystem. Microsoft recommends against working across operating systems with the same files unless necessary.
- Interop: Linux can start Windows executables and Windows can start `wsl.exe`; `[interop] appendWindowsPath` adds the Windows PATH to Linux and can slow command lookup.

## Memory

The VM's memory comes from the host and is reported against a `vmmem` process. `memory` caps it (default half of Windows memory). `autoMemoryReclaim` (experimental) returns cached memory to Windows, either `gradual` or `dropCache` (the documented default), or `disabled`. Swap is a separate disk (`swap`, `swapFile`).

## Networking

Modes: NAT (default, private subnet behind the host), mirrored (Windows 11 22H2 and later; the VM sees the host's interfaces), `bridged` (deprecated), `consomme` (user-space networking, also used as a fallback when NAT fails from WSL 2.3.25), and `none`. In NAT mode `dnsProxy` points Linux at the host as DNS server; with `dnsTunneling` WSL answers DNS through a virtualisation channel rather than packets, which respects Windows DNS policy and VPN split DNS. `autoProxy` copies the Windows proxy settings. The Hyper-V firewall applies Windows and Hyper-V firewall rules to the WSL VM, per creator ID, with `firewall` in `.wslconfig` as the user switch. Mirrored mode needs inbound allowances set deliberately.

## GPU

GPU paravirtualisation exposes a virtual GPU (`dxgkrnl`) to the guest, which talks to the Windows driver through the hypervisor. The guest installs only user-mode libraries from the vendor's WSL packages. Limits: workload support depends on vendor driver versions; display output is not the purpose (use WSLg).

## WSLg

A Weston-based Wayland compositor with XWayland, audio and clipboard integration runs in a system distribution inside the VM and presents applications in Windows windows over an RDP-based path. Needs Windows 10 build 19044 or later or Windows 11 and a current WSL package (`wsl --update`).

## init, systemd and users

By default `/init` (a WSL-provided binary) starts the distribution. With `[boot] systemd=true` systemd becomes PID 1 and normal service management, `journalctl` and snap work; `[boot] command` runs a command at start without systemd. The default user is set with `[user] default`.

## Containers

WSL 2 supports Docker-style daemons in a distribution (with systemd or a boot command) and is the backend for several desktop container products. WSL containers (WSLc) is a Microsoft container feature built on WSL, announced generally available on 29 September 2026 with the WSL 3.0 package series; the Defender plug-in page asks for WSL 2.9.12 or later for it, and `.wslconfig` settings do not apply to `wslc`. Check Microsoft Learn for the current requirements.
