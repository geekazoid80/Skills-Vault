# Ubuntu architecture reference

Sources: Canonical's release notes and list of releases, the Ubuntu Server documentation, the Ubuntu Pro client documentation and the Ubuntu manual pages for 26.04, all read on 2026-10-19. Where a statement is from experience rather than a page, it is marked as such.

## Relationship to Debian

Ubuntu is built from Debian packages with its own archive, kernel, installer, release schedule and defaults. The package format (`.deb`), `dpkg` and `apt` are shared; the archive layout is not. Ubuntu's archive components are `main` (supported by Canonical), `restricted` (proprietary drivers), `universe` (community packages) and `multiverse` (non-free). Standard security maintenance covers `main`; Expanded Security Maintenance extends it to the whole archive, including `universe` (Ubuntu Pro).

Canonical-specific layers: snap, Netplan, cloud-init integration, UFW as the default firewall front end, the AppArmor policy set, Livepatch, Landscape, Subiquity and autoinstall, LXD, MicroK8s and the Ubuntu Pro client.

## apt and dpkg

- `dpkg` installs, removes and queries individual `.deb` files (`dpkg -l`, `dpkg -L`, `dpkg -S`, `dpkg --audit`, `dpkg --configure -a`). `apt` and `apt-get` resolve dependencies and fetch from repositories.
- **Sources:** `/etc/apt/sources.list.d/ubuntu.sources` (deb822, 24.04 and later) or `/etc/apt/sources.list` (older). deb822 stanzas carry `Types`, `URIs`, `Suites`, `Components` and `Signed-By`. Third-party repositories belong in their own `.sources` or `.list` file in `sources.list.d/`, with the key in `/etc/apt/keyrings/`.
- **Pockets:** `<series>`, `<series>-updates`, `<series>-security`, `<series>-backports` and `<series>-proposed`. `proposed` is for testing; it is not enabled by default.
- **Phased updates:** Ubuntu releases some updates to a fraction of machines first. A phased package can show as upgradable yet be held back on a given host; a release upgrade needs them installed (`apt dist-upgrade -o APT::Get::Always-Include-Phased-Updates=true`, as in Canonical's upgrade guide).
- **APT 3 (26.04):** the fallback solver, OpenSSL transport, pager and `apt history-*` commands; `apt-key` is gone and signature checks use `gpgv` directly (see `apt-secure(8)`).
- **Preferences:** pinning in `/etc/apt/preferences.d/`; `apt-mark hold` and `unhold` for a single package.
- **Architecture variants:** since 25.10 a package can have a microarchitecture variant; the first is `amd64v3`, enabled with `APT::Architecture-Variants "amd64v3";` in `/etc/apt/apt.conf.d/`.

## snap

snapd installs sandboxed packages from the Snap Store with automatic refreshes. Confinement is `strict` (AppArmor and seccomp), `classic` (no sandbox) or `devmode` (violations only logged). Data is under `/var/snap/` and `~/snap/`. Interfaces connect plugs to slots (`snap connections <snap>`). Refreshes follow a system timer (`snap set system refresh.timer=...`), can be held (`snap refresh --hold`), and a snap can be reverted to its previous revision (`snap revert`). In 26.04 desktop snaps use XDG desktop portals, and the GNOME Shell search can find snap applications. Mixing a deb and a snap of the same application is a common source of confusion about which one is running.

## Netplan and name resolution

Netplan reads `/etc/netplan/*.yaml`, `/run/netplan` and `/lib/netplan` and renders configuration for systemd-networkd or NetworkManager (`renderer:` per file). The commands, from the `netplan` manual page: `generate`, `apply`, `try [--timeout 120]`, `get`, `set` and `status`. Netplan 1.2 (26.04) has its own `systemd-networkd-wait-online` logic that waits for link-local addresses and one routable interface. `systemd-resolved` provides the stub resolver (`resolvectl status`, `resolvectl query`). A YAML file in `/etc/netplan` should not be world-readable (Netplan warns); keep mode 600.

## cloud-init

cloud-init runs in stages (generator, local, network, config, final) and merges datasource metadata with user-data. `cloud-init status --wait` blocks until it finishes, `cloud-init status` reports `not started`, `running`, `done`, `error` or `disabled` (recoverable errors show as `degraded` in `extended_status` and as exit code 2; use `--long` or `--format json` to see it), `cloud-init query` dumps instance data and `cloud-init schema --config-file <file>` validates user-data. Network configuration written by cloud-init lands in `/etc/netplan/50-cloud-init.yaml` (first boot by default); disable it with `network: {config: disabled}` in a file under `/etc/cloud/cloud.cfg.d/` when you manage Netplan yourself. Never put credentials in user-data that is stored where others can read it.

## AppArmor

Profiles are text files in `/etc/apparmor.d/`, compiled and loaded by `apparmor_parser`; local additions go in `/etc/apparmor.d/local/`. Modes: enforce (block and log), complain (log only) and unconfined (no profile); a profile can also carry flags such as `flags=(unconfined)`. `aa-status` reports state; `aa-enforce` and `aa-complain` switch a profile; `aa-genprof` and `aa-logprof` build and update profiles from logged events. Denials appear in the kernel log as `apparmor="DENIED"` (in `journalctl -k`, or in the audit log if `auditd` is installed). 24.04 added a kernel restriction on unprivileged user namespaces for unconfined programs, applied through an AppArmor profile set. 25.04 added many sandboxing profiles. Application snaps are confined by generated AppArmor profiles.

## Ubuntu Pro services

| Service | What it does |
|---|---|
| `esm-infra` | Security fixes for `main` after standard support ends |
| `esm-apps` | Security fixes for `universe` |
| `livepatch` | In-memory kernel security patches for critical and high issues |
| `usg` | Ubuntu Security Guide: CIS and DISA STIG audit and hardening |
| `fips` | FIPS 140 validated modules (changes the kernel and crypto packages; plan it) |
| `landscape` | Registers the machine with Landscape |
| `realtime-kernel` | Real-time kernel (in the main archive without Pro from 26.04) |

`pro status` shows entitlement and state per service; `pro security-status` summarises package coverage by origin; `pro cves` and `pro fix` list and resolve vulnerabilities; `pro api <endpoint>` returns JSON. The client attaches with a token from the Pro dashboard or the cloud's auto-attach; protect that token as a credential.

## Installer and automation

Subiquity is the server installer; autoinstall is a YAML file (delivered through cloud-init user-data under an `autoinstall:` key) that answers its questions: `version`, `identity`, `storage`, `network`, `ssh`, `packages`, `snaps`, `early-commands`, `late-commands`. The `identity` section holds a password hash; treat the file as a secret. The desktop installer on 26.04 offers TPM-backed full-disk encryption with documented limitations. LXD (system containers and VMs) and MicroK8s are Canonical snaps; LXD and Kubernetes operations are outside this skill (`kubernetes-ops`).

## Ubuntu-specific services worth knowing

- **unattended-upgrades** applies security updates by default (`/etc/apt/apt.conf.d/50unattended-upgrades`, enabled through `APT::Periodic::Unattended-Upgrade`); its logs are in `/var/log/unattended-upgrades/`.
- **needrestart** restarts services affected by a library upgrade (24.04 changed it to do this non-interactively) and reports a pending kernel or microcode update in batch mode.
- **apport** collects crash reports; 24.04 can integrate with `systemd-coredump`.
- **Landscape** is Canonical's fleet management service (Pro).
- **authd** (26.04, `universe`) provides cloud identity logins with brokers for Microsoft Entra ID, Google IAM and generic OIDC; **ADSys** is the Active Directory Group Policy client.
