# WSL diagnostics reference

## Command quick reference (Windows side)

| Purpose | Command |
|---|---|
| Install | `wsl --install`, `wsl --install -d <name>`, `wsl --list --online` |
| State | `wsl --version`, `wsl --status`, `wsl --list --verbose` |
| Update | `wsl --update` (add `--pre-release` only on purpose) |
| Stop | `wsl --terminate <name>`, `wsl --shutdown` |
| Version | `wsl --set-default-version 2`, `wsl --set-version <name> 2`, `wsl --set-default <name>` |
| Backup and clone | `wsl --export <name> <file.tar>`, `wsl --import <name> <dir> <file.tar> --version 2`, `wsl --import-in-place <name> <file.vhdx>` |
| Disk | `wsl --manage <name> --resize <size>` (WSL 2.5 and later; run `wsl --shutdown` first; whole numbers only), `wsl --manage <name> --compact` and `--move <location>` (current WSL 3.0 series; check `wsl --manage --help` on your build), `wsl --mount <disk>` |
| Remove | `wsl --unregister <name>` (deletes the distribution and its data) |
| Run in a distribution | `wsl -d <name> -- <command>` (starts the distribution if stopped) |

Inside the distribution: `uname -r`, `cat /etc/wsl.conf`, `ps -p 1 -o comm=` (init), `df -h /`, `free -h`, `ip -brief addr`, `cat /etc/resolv.conf`, `systemctl status` (with systemd).

## By symptom

### No network, or DNS fails

1. Mode and build: `.wslconfig` `networkingMode` and the Windows build (mirrored needs Windows 11 22H2 or later).
2. VPN or proxy: NAT mode behind VPN clients often loses DNS or routes. Move to mirrored mode with `dnsTunneling=true` (and `autoProxy=true` where a proxy is used); on Windows 10 restart WSL after the VPN connects.
3. `cat /etc/resolv.conf` and `getent hosts <name>` inside the distribution; compare with Windows `Resolve-DnsName`.
4. Firewall: Windows and Hyper-V firewall rules apply to WSL; inspect `Get-NetFirewallHyperVVMSetting` and `Get-NetFirewallHyperVRule` for the WSL creator ID.
5. Only after the above, consider `generateResolvConf=false` with a documented resolver.

### Services reachable from Windows but not from the LAN (or the reverse)

NAT mode hides WSL behind the host; use mirrored mode and an explicit Hyper-V firewall inbound rule, or a port proxy as a last resort. In mirrored mode reach Windows from Linux at `127.0.0.1`.

### `vmmem` uses too much memory

Set `memory`, choose `autoMemoryReclaim=gradual`, and run `wsl --shutdown` when finished. Container-heavy work legitimately needs memory; measure inside with `free -h`.

### Slow builds or Git

The tree is probably under `/mnt/c/`. Move it into the Linux filesystem; keep editors and tools on the same side as the files.

### Out of disk space (inside) or a huge `ext4.vhdx` (outside)

Inside: `df -h /` against the VHD limit (1 TB default); delete data; grow with `wsl --manage <name> --resize`. Outside: free the space inside first, `sudo fstrim -av`, `wsl --shutdown`, then compact the VHDX (`wsl --manage <name> --compact` where available, otherwise `Optimize-VHD` or `diskpart`). Check the Windows volume has room to grow. A distribution that mounts read-only after a power loss may need `e2fsck` from a repair route (Microsoft's disk-space page describes repairing a VHD mounting error); export what you can first.

### systemd does not start

`[boot] systemd=true` in `/etc/wsl.conf` inside the distribution (not `.wslconfig`), WSL version 0.67.6 or later (`wsl --update`), then `wsl --shutdown`. If the distribution waits at start, check `[boot] initTimeout` and failed units with `systemctl --failed`.

### GPU or CUDA not working

Update the Windows vendor driver; do not install a Linux display driver in the distribution; confirm Windows 11 or Windows 10 21H2 or later and a current WSL package; use the vendor's WSL instructions for the toolkit.

### `wsl --install` fails or WSL 2 will not start

Windows build below 19041; Virtual Machine Platform not enabled (check with `Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform`; the remedy, which changes state and needs an elevated prompt and a restart, is `dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart`); virtualisation disabled in firmware; another hypervisor product without Windows Hypervisor Platform support; an enterprise policy that blocks WSL, WSL 1 or the inbox component.

### Distribution will not start or is damaged

Try `wsl --shutdown` then start again; `safeMode=true` in `.wslconfig` (Windows 11, WSL 0.66.2 or later) to recover a distribution in a bad state; export from the VHDX if it still mounts (`wsl --export`), or register the VHDX with `--import-in-place`.

### Output looks garbled in a script

`wsl.exe`'s own output (`--list`, `--version`, `--status`) is UTF-16 when captured: set `[Console]::OutputEncoding` to Unicode for the call, or strip NUL characters. Output of a command run inside the distribution (`wsl -d <name> -- ...`) is UTF-8: decode it as UTF-8 instead.

## Collecting logs

Microsoft's WSL repository provides a log collection script and issue templates for bugs; the WSL release notes list fixes by version. Capture `wsl --version`, the Windows build, `.wslconfig`, and the output of `wsl --status` with any report.
