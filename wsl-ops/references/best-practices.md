# WSL best-practices reference

Defaults quoted are from Microsoft Learn (2026-10-19). Confirm them against the Learn page for the WSL version in use.

## Configuration

### `.wslconfig` (Windows, `%UserProfile%`, applies to the WSL 2 VM, needs `wsl --shutdown`)

```ini
[wsl2]
memory=8GB                  # default is 50% of Windows memory
processors=4                # default is all logical processors
swap=2GB                    # default 25% of Windows memory, rounded up to a whole GB
networkingMode=mirrored     # Windows 11 22H2 or later; default is NAT
dnsTunneling=true           # default true on Windows 11 22H2 or later
autoProxy=true              # default true on Windows 11 (dnsTunneling needs 22H2 or later)
firewall=true               # default true: Windows and Hyper-V firewall rules filter WSL traffic

[experimental]
autoMemoryReclaim=gradual   # default dropCache; gradual is gentler on cache-heavy work
```

Size `memory` from the workload (development with a language toolchain is often a few gigabytes; machine learning and container-heavy work needs more) and leave the host enough memory. Only set experimental keys deliberately. `sparseVhd` is experimental, defaults to false and only affects newly created disks; avoid it on disks you cannot afford to lose.

### `/etc/wsl.conf` (inside the distribution, per distribution)

```ini
[boot]
systemd=true

[automount]
enabled=true
options="metadata,umask=22,fmask=11"

[network]
generateResolvConf=true     # set false only when you maintain /etc/resolv.conf yourself

[interop]
enabled=true
appendWindowsPath=true      # false shortens PATH and speeds command lookup

[user]
default=<username>
```

Do not disable `generateResolvConf` as a first response to a DNS problem: fix the networking mode and DNS tunnelling first, then pin DNS only if split-horizon or a VPN requires it, and document why.

## Distribution lifecycle

- Treat distributions as disposable: keep a base image (`wsl --export`), create work environments with `wsl --import`, and re-create rather than repair.
- Name distributions for purpose and owner; keep a list of what runs where.
- Update the WSL package with `wsl --update` on a schedule, and the distribution's packages with its own package manager. Microsoft does not patch distributions through Windows tools.
- Use WSL 2 for everything unless a measured cross-filesystem workload says otherwise; convert with `wsl --set-version`.
- Before `--unregister` or `--import` over a name, export and check the export file exists and is non-empty.
- Move or resize: `wsl --manage <name> --resize <size>` (WSL 2.5 and later; `wsl --shutdown` first; whole numbers only) grows the limit; `wsl --manage <name> --move <location>` relocates a distribution on current releases, or `wsl --export` then `--import` to a new location does it on any release.

## Memory and disk hygiene

1. Cap memory; choose `autoMemoryReclaim` for long-running sessions.
2. `wsl --shutdown` releases the VM's memory when you finish.
3. For disk: clean inside the distribution (package caches, container images, build artefacts), run `sudo fstrim -av`, `wsl --shutdown`, then compact the VHDX (`wsl --manage <name> --compact` where the WSL package has it, otherwise `Optimize-VHD -Path <ext4.vhdx> -Mode Full` where the Hyper-V module exists, or `diskpart` with `select vdisk file=...`, `attach vdisk readonly`, `compact vdisk`, `detach vdisk`). Export first.
4. Keep the volume holding the VHDX with at least 20 per cent free so the disk can grow.

## Development workflow

- Clone and build inside the Linux filesystem; open the folder from the Windows side with the editor's WSL integration (for example `code .` from the distribution) so the editor's server runs in Linux.
- Git: one set of credentials, shared via a credential helper that you trust; consistent line endings (`core.autocrlf=input` is common inside WSL); avoid editing the same working tree from both sides.
- Docker: either a desktop container product with its WSL 2 backend, or an engine inside the distribution (with systemd enabled); see `docker-ops` and `container-runtime-selection`.
- Cross-compilers and toolchains are ordinary Linux packages. Windows executables can be called from Linux through interop, which is convenient and a security boundary to remember.

## Networking

- Prefer mirrored mode with DNS tunnelling and auto proxy on Windows 11 22H2 or later, especially behind VPNs and proxies; on Windows 10 expect NAT limits.
- Decide the Hyper-V firewall default for inbound traffic on purpose, and log the decision. If a service must be reachable from the LAN, add a specific Hyper-V firewall rule rather than flipping the default.
- Avoid port proxy rules except where mirrored mode is not available; document each rule and remove it when the address changes.

## Enterprise deployment

1. **Baseline:** Windows 10 22H2 or Windows 11 22H2 or later, WSL 2.0.9 or later (Microsoft's enterprise guidance), with `wsl --version` as the check.
2. **Control with Intune (Settings catalog):** Microsoft's recommended-settings table sets Disabled for the inbox WSL component, WSL 1, the debug shell, custom kernels, kernel command lines, custom system distributions, custom networking, user firewall settings, nested virtualisation and kernel debugging; there are also settings for the passthrough disk mount and for WSL itself. Disable what a team has no reviewed need for and allow WSL for the people who need it.
3. **Visibility:** deploy the Microsoft Defender for Endpoint plug-in for WSL 2 (Defender for Endpoint Plan 2 with the device onboarded; WSL 2.0.7 or later; Windows 10 build 19044 or later or Windows 11; not on ARM64 or multi-session Windows; custom kernels unsupported; allow up to 30 minutes to onboard). It surfaces events, not antimalware scanning.
4. **Images:** distribute an approved base through `wsl --import`; build it with your configuration management; keep a patch cadence for the image.
5. **Support:** Microsoft's enterprise page (last updated 2024-08-16) lists patching distributions through Windows, Windows Update updating distribution contents, restricting which distributions are installable and controlling root as not yet supported, so plan compensating controls (an approved image, endpoint monitoring, and policy that disallows unmanaged distributions through application control where appropriate).
6. **Windows 10 machines** are past end of support for most editions (14 October 2025); advanced networking features are Windows 11 only (`windows-client-ops`).

## Security

- A distribution is a Linux system with its own users, packages and sudo. Anything in it runs with the Windows user's rights on Windows files that the user can reach.
- Do not store secrets in `.wslconfig`, `wsl.conf`, shell history or scripts; use an agent with timeouts or hardware-backed keys.
- Review what is exposed on the network: the Hyper-V firewall default, mirrored mode, port proxy rules and services bound to all interfaces.
- Treat third-party distributions and images as untrusted software.
