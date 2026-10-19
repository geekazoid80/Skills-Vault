---
name: ubuntu-ops
description: "Use for Ubuntu-specific administration on 22.04, 24.04 and 26.04 LTS (and 20.04 under Ubuntu Pro): the support lifecycle and which release to run, apt and the deb822 sources format, snap, Netplan and cloud-init, UFW, AppArmor (including the unprivileged user namespace restriction), Ubuntu Pro with ESM, Livepatch and USG, unattended-upgrades and needrestart, chrony versus systemd-timesyncd, sudo-rs and the other 26.04 defaults, do-release-upgrade, and autoinstall. Triggers include \"Ubuntu\", \"Ubuntu 26.04\", \"Resolute Raccoon\", \"Noble\", \"apt\", \"deb822\", \"snap\", \"Netplan\", \"cloud-init\", \"UFW\", \"AppArmor\", \"aa-status\", \"Ubuntu Pro\", \"ESM\", \"Livepatch\", \"pro attach\", \"unattended-upgrades\", \"needrestart\", \"do-release-upgrade\", \"autoinstall\", \"Ubuntu end of life\". NOT for Debian (debian-ops), NOT for RHEL-family or SUSE hosts (see operating-system-selection for the platform skill), NOT for generic Linux operation such as systemd units, journalctl, LVM and backups (linux-host-ops), NOT for first-boot commissioning (linux-host-bringup), NOT for choosing a distribution (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Ubuntu operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: ubuntu-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Ubuntu is a Debian derivative with a fixed release rhythm: an LTS every two years in April, interim releases every six months, and Canonical-specific layers on top of Debian's apt and dpkg (snap, Netplan, cloud-init, UFW, Ubuntu Pro). This skill covers the parts that are specific to Ubuntu; generic Linux work (systemd units, journalctl, LVM, backups, the apt and dnf basics) lives in `linux-host-ops`.

**Core principle:** identify the release and its support status first, because package format, defaults and the available security coverage all depend on it. A host past standard support without Ubuntu Pro receives no security updates, and a statement about "Ubuntu" without a version is usually wrong for at least one of the LTS releases still in use.

> **Caveat on provenance.** The content was reshaped from a community upstream that carried version errors (for example an `apt-key` removal in the wrong release, a Python version, and "initramfs-tools removed") and was then corrected against Canonical's release notes and list of releases, the Ubuntu Pro client documentation and the Ubuntu manual pages, read on 2026-10-19. The scripts are checked with `shellcheck` and stub commands only; they have not been run on an Ubuntu host.

## Step 0: establish what you are running

```sh
. /etc/os-release && echo "$PRETTY_NAME ($VERSION_CODENAME)"   # release and codename
uname -r                                  # kernel
pro status                                # attached to Ubuntu Pro? which services?
ubuntu-distro-info --supported-esm        # releases in standard support or ESM (local data file, can lag; Legacy-only releases are not listed)
apt-cache policy | head -20               # configured archives
```

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Disruptive, get explicit approval |
|---|---|---|
| `pro status`, `pro security-status`, `pro cves --fixable`, `pro fix --dry-run`, `pro system reboot-required`, `pro api u.pro.status.is_attached.v1`, `apt-mark showhold`, `apt-get -s dist-upgrade`, `apt list --upgradable`, `dpkg --audit`, `needrestart -b`, `snap list`, `snap refresh --list`, `ufw status`, `aa-status`, `netplan get`, `netplan status`, `cloud-init status`, `ubuntu-distro-info` | `apt install`, `apt upgrade`, `apt full-upgrade`, `apt-mark hold`, `snap refresh`, `snap remove`, `ufw allow`, `ufw delete`, `aa-enforce`, `aa-complain`, `netplan apply`, `pro enable`, `pro attach`, `pro fix`, `systemctl restart` | `netplan apply` on a remote host without `netplan try`, `ufw enable` or `ufw reset` over SSH, `do-release-upgrade`, `apt autoremove --purge`, `aa-disable`, `pro detach`, `cloud-init clean`, removing a kernel, switching the initramfs generator or the sudo implementation |

`needrestart -b` is batch mode: it restarts nothing and prints machine-readable lines. `pro fix` can install packages and may require a reboot (exit code 2 means a reboot is needed). Run `netplan try` instead of `netplan apply` on a remote host: it reverts after a timeout (default 120 seconds) unless you confirm.

## Releases and support

Ubuntu publishes its dates on Canonical's "List of releases" page. Standard support is five years for an LTS; Ubuntu Pro adds Expanded Security Maintenance (ESM) for ten years in total; the Legacy add-on extends that to fifteen. Interim releases are supported for nine months. The table is the state on 2026-10-19; check the page before quoting a date.

| Release | Standard support ends | End of life (Pro with the Legacy add-on) | Notes |
|---|---|---|---|
| 26.04 LTS (Resolute Raccoon) | May 2031 | Apr 2041 | Released 23 Apr 2026; 26.04.1 on 27 Aug 2026 |
| 24.04 LTS (Noble Numbat) | Jun 2029 | Apr 2039 | 24.04.5 on 10 Sep 2026 |
| 22.04 LTS (Jammy Jellyfish) | Jun 2027 | Apr 2037 | Last point release 22.04.5 (Sep 2024) |
| 20.04 LTS (Focal Fossa) | May 2025 (ended) | Apr 2035 | ESM without Legacy ends Apr 2030; needs Ubuntu Pro for security fixes |
| 18.04 LTS (Bionic Beaver) | Jun 2023 (ended) | Apr 2033 | ESM ends Apr 2028 (Canonical's ESM table); 16.04 and 14.04 are in `references/version-notes.md` |
| 26.10 (Stonking Stingray) | Jul 2027 | Jul 2027 | Interim, released 15 Oct 2026 |

Canonical's table gives one "End of Life" per release, and for an LTS that is the Legacy add-on date; Pro without Legacy ends ten years after release (Canonical's ESM table lists 20.04 ending April 2030). Ubuntu Pro is free for personal use on up to five machines (fifty for official Ubuntu community members); organisations need a subscription, with a 30-day trial.

## Package management

- **apt** uses the deb822 format from 24.04: sources live in `/etc/apt/sources.list.d/ubuntu.sources`, with `Signed-By` for third-party keys kept under `/etc/apt/keyrings/`. `/etc/apt/sources.list` is the legacy one-line format and may be empty on 24.04 and later.
- **`apt-key` was removed in the APT 3 series (26.04 has APT 3.1)**, so do not use it on any release. Import keys with `gpg --dearmor` into `/etc/apt/keyrings/` and reference them with `Signed-By`.
- **APT 3.1 (26.04)** adds a fallback dependency solver with better failure context, OpenSSL for TLS and hashing, a pager, and `apt history-list`, `history-info`, `history-undo`, `history-redo` and `history-rollback`.
- **Architecture variants (since 25.10):** the `amd64v3` variant is opt-in on a normal host with `APT::Architecture-Variants "amd64v3";`, but the 26.04 cloud images are built for `amd64v3` by default, so older instance families on AWS and Google Cloud are not supported (Canonical lists the unsupported AWS families and two Google CPU platforms in the release notes).
- **snap** delivers sandboxed applications with automatic refreshes. `snap refresh --list` shows pending refreshes (and asks the Snap Store), `snap refresh --hold=48h <snap>` defers one for 48 hours (a hold with no duration is indefinite), and `snap set system refresh.timer=...` sets a window.
- **needrestart** (24.04 and later) restarts services affected by a library upgrade even in non-interactive runs such as unattended-upgrades; exclude a service through `override_rc` in a snippet under `/etc/needrestart/conf.d/` (or in `needrestart.conf`).
- **PPAs** are disabled during a release upgrade and are the most common cause of upgrade trouble.

## Ubuntu Pro, ESM, Livepatch and compliance

`pro attach <token>` attaches a machine; `pro status` shows services; `pro enable esm-infra` and `esm-apps` add security fixes for the `main` and `universe` archives; `pro enable livepatch` applies critical and high kernel fixes without a reboot; `pro enable usg` followed by `apt install usg` provides the Ubuntu Security Guide (CIS and DISA STIG profiles; `usg audit` and `usg fix`); `pro fix CVE-...` or a USN resolves one issue. `pro api <endpoint>` returns JSON for scripts (`u.pro.status.is_attached.v1`, `u.pro.status.enabled_services.v1`, `u.unattended_upgrades.status.v1`, `u.pro.security.status.reboot_required.v1`). Livepatch on arm64 arrived in 26.04. Real-time kernel packages are in the main archive in 26.04 rather than behind Pro.

## Networking, time and name resolution

- **Netplan** (1.0 in 24.04, 1.2 in 26.04) is the declarative layer over systemd-networkd (servers) and NetworkManager (desktops). Files in `/etc/netplan/*.yaml`; `netplan get` shows the merged configuration, `netplan generate` writes backend configuration, `netplan try` applies with automatic rollback, `netplan status` shows runtime state.
- **cloud-init** writes `/etc/netplan/50-cloud-init.yaml` when it applies network configuration (on first boot by default; on every boot only if its `updates` setting says so), so manual Netplan edits can be overwritten unless `network: {config: disabled}` is set in a file under `/etc/cloud/cloud.cfg.d/`. cloud-init is disabled on hosts installed from the ISO. On 26.04 server images, user-data that needs the network must have at least one required interface (`optional: false`) in `network-config`.
- **SSH** is socket-activated since 22.10; from 24.04 a systemd generator reads `sshd_config` and `sshd_config.d` to configure `ssh.socket`, so a `Port` change is applied through the socket.
- **Time:** chrony is the default for new 26.04 installations (NTS against Ubuntu's servers); systemd-timesyncd remains the default on 24.04 and 22.04. To migrate an upgraded host, `apt-mark auto systemd-timesyncd` then `apt install chrony`, and make sure the Ubuntu pool servers in `/etc/chrony/sources.d/ubuntu-ntp-pools.sources` are not listed twice.
- **UFW** is the default firewall front end; it is installed but inactive until `ufw enable`. Container engines that edit iptables or nftables rules directly can bypass UFW rules for published ports (read the container engine's firewall documentation).

## AppArmor

AppArmor is the default mandatory access control: path-based profiles in `/etc/apparmor.d/`, modes enforce, complain and unconfined. `aa-status --enabled`, `--profiled`, `--enforced` and `--complaining` are the script-friendly forms. Since 24.04, the kernel restricts unprivileged user namespaces for unconfined applications (`kernel.apparmor_restrict_unprivileged_userns`); an application that builds its own sandbox may need a profile with the `userns` permission rather than turning the restriction off. Fix a denial with a profile change (`aa-complain` to learn, `aa-logprof` to update), not by disabling AppArmor. Snaps are confined with AppArmor and seccomp. Generic MAC guidance is in `linux-host-ops`.

## 26.04 defaults that change operations

Kernel 7.0 (GA; HWE moves from 6.17); systemd 259, which no longer supports cgroup v1 (a host booted with cgroup v1 cannot upgrade, and 26.04 container workloads will not run on it) and is the last release with SysV script compatibility; `/tmp` is a tmpfs; dracut is the default initramfs generator (initramfs-tools remains supported and switchable); `sudo-rs` is the default sudo (the original is `sudo.ws`, and `sudo-ldap` is gone: use PAM); `rust-coreutils` provides the core utilities (the release notes name `cp`, `mv` and `rm` as still GNU, and Ubuntu Server's utility-replacement documentation may list more, so check it for your release; `apt install coreutils-from-gnu coreutils-from-uutils- --allow-remove-essential` switches back); OpenSSH 10.2p1 with the hybrid `mlkem768x25519-sha256` key exchange by default and DSA removed (no DSA host keys are generated); SSSD 2.12 runs as the `sssd` user; Python 3.14; PostgreSQL 18; MySQL 8.4 (accounts using `mysql_native_password` are locked unless enabled). Known issues in the release notes include a PostgreSQL throughput regression on Linux 7.0 unless huge pages are on, `mkdir -p` not inheriting POSIX ACLs under rust-coreutils, and Apache's `MemoryDenyWriteExecute` setting breaking PHP JIT. Details and sources are in `references/version-notes.md`.

## Release upgrades

`do-release-upgrade` upgrades one LTS to the next LTS only (no skipping) and, from an LTS, is offered only after the first point release (for example 26.04.1) unless `-d` forces it. Before a run: fully update (`apt update` then `apt dist-upgrade`, including phased updates), reboot if `/run/reboot-required` exists, free several gigabytes, back up, expect third-party repositories to be disabled, and run it in `tmux` or `screen`. A cgroup v1 host cannot upgrade to 26.04. `Prompt=` in `/etc/update-manager/release-upgrades` controls whether LTS or interim releases are offered.

## Pitfalls

1. Quoting a support date without checking Canonical's list; 22.04 standard support ends June 2027.
2. Treating a host past standard support as patched without checking `pro status`.
3. Editing `/etc/apt/sources.list` on 24.04 and later instead of `ubuntu.sources`.
4. Using `apt-key` in scripts that must run on 26.04.
5. `netplan apply` over SSH with no `netplan try`.
6. Manual edits to `50-cloud-init.yaml` overwritten at boot.
7. `ufw allow` without `ufw enable`, or relying on UFW for container-published ports.
8. Disabling AppArmor, or the user namespace restriction, to fix one application.
9. Assuming `systemd-timesyncd` commands on 26.04, or leaving both timesyncd and chrony active.
10. Running 26.04 container workloads on a cgroup v1 host.
11. `snap` refreshes landing during a maintenance window nobody chose.
12. Mixing `apt` and `snap` copies of the same software and fixing the wrong one.

## Red flags

- A version, date or default stated without a Canonical page behind it.
- `apt-key`, `ufw disable`, `aa-disable`, `setenforce`-style advice offered as the first fix.
- A `pro attach` token, a cloud-init password hash or an autoinstall `identity` password pasted into a command, ticket or script.
- A release upgrade started on a production host without a backup and a rollback plan.

## References and scripts

- `references/architecture.md`: apt and dpkg, snap, Netplan and cloud-init, AppArmor, Ubuntu Pro services, autoinstall.
- `references/best-practices.md`: patching, unattended-upgrades, UFW, AppArmor, Pro and USG, backups, release upgrades.
- `references/diagnostics.md`: broken packages, snap, Netplan and resolver, AppArmor denials, time sync, boot and initramfs, logs.
- `references/version-notes.md`: dated lifecycle table and what changed in 20.04, 22.04, 24.04 and 26.04.
- `scripts/system-health.sh`, `update-state.sh`, `security-posture.sh`, `network-and-time.sh`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings or an invalid setting (the message is on standard error).

The scripts are POSIX `sh` (the default `/bin/sh` on Ubuntu is dash), read state and change nothing, and take thresholds from environment variables. Their active probes are one name lookup and, with `PING_GATEWAY=1`, a gateway ping (`network-and-time.sh`), and `snap refresh --list`, which asks the Snap Store (`update-state.sh`). A missing required tool or a failed command is a warning; an optional component that is not installed (snapd, sshd, netplan, resolvectl, cloud-init) is reported as information. Several checks need root (`ufw status`, `aa-status`, `sshd -T`, `needrestart -b`); run without root they warn that the check was not performed. They pass `shellcheck -s sh` and were run against stub commands in an empty-result world, a throwing world, and healthy and unhealthy worlds, but not on an Ubuntu host; the output formats they parse come from the manual pages and Canonical documentation.

## Boundaries

- Debian itself: `debian-ops`. RHEL-family and SUSE hosts: `operating-system-selection` routes to the platform skill.
- Generic Linux operation: `linux-host-ops`; first-boot commissioning: `linux-host-bringup`.
- Containers on Ubuntu: `podman-ops`, `docker-ops`, `container-security`; Kubernetes: `kubernetes-ops`.
- Vulnerability handling and benchmarks: `vulnerability-management`, `compliance-benchmark-audit`.
- Secrets in tokens and autoinstall files: `secrets-hygiene`.

## Bottom line

Know the release and its support status, keep security coverage alive (standard support or Pro), use `netplan try` and `ubuntu.sources`, fix AppArmor denials with profiles, and read Canonical's pages for dates rather than recalling them.
