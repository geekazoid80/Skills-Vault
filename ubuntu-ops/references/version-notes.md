# Ubuntu version notes

Dated 2026-10-19. Sources: Canonical's "List of releases" (documentation.ubuntu.com/project/release-team/list-of-releases), the release notes at documentation.ubuntu.com/release-notes for 22.04, 24.04, 26.04, 26.04.1 and 26.10, the Ubuntu Pro page, and the Ubuntu 26.04 manual pages. Re-check the list of releases before quoting a date; the release notes record what Canonical shipped.

## Lifecycle snapshot

| Release | Released | Latest point release seen | Standard support ends | End of life (Pro with Legacy) |
|---|---|---|---|---|
| 26.10 Stonking Stingray | 15 Oct 2026 | 26.10 | Jul 2027 | Jul 2027 |
| 26.04 LTS Resolute Raccoon | 23 Apr 2026 | 26.04.1 (27 Aug 2026) | May 2031 | Apr 2041 |
| 24.04 LTS Noble Numbat | 25 Apr 2024 | 24.04.5 (10 Sep 2026) | Jun 2029 | Apr 2039 |
| 22.04 LTS Jammy Jellyfish | 21 Apr 2022 | 22.04.5 (12 Sep 2024) | Jun 2027 | Apr 2037 |
| 20.04 LTS Focal Fossa | 23 Apr 2020 | 20.04.6 | May 2025 (ended) | Apr 2035 |
| 18.04 LTS Bionic Beaver | 26 Apr 2018 | 18.04.6 | Jun 2023 (ended) | Apr 2033 |
| 27.04 Tenacious T-Rex | in development | none | planned Jan 2028 | planned Jan 2028 |

- Canonical's table has a separate Expanded Security Maintenance entry for 20.04: ESM from June 2025 to April 2030 (five years, free with Ubuntu Pro for personal use, paid for organisations); the Legacy add-on extends it five more years. For 22.04, 24.04 and 26.04 ESM begins after standard support and runs to ten years after release.
- Older LTS releases on Canonical's tables: 18.04 ESM Jun 2023 to Apr 2028; 16.04 ESM Apr 2021 to Apr 2026, then the Legacy add-on to Apr 2031; 14.04 ESM Apr 2019 to Apr 2024, then Legacy to Apr 2029.
- Interim releases (such as 26.10) are supported for nine months.
- `ubuntu-distro-info --supported-esm` reads the local `distro-info-data` package, which is updated by apt but can lag; use it as a quick check, not as the source of a date.

## What changed, by release

### 22.04 LTS (Jammy)

- Kernel 5.15 on servers (non-rolling `linux-generic`); desktop uses a rolling HWE kernel. systemd 249.11, with `systemd-oomd` enabled. OpenSSL 3.0, which disables legacy algorithms by default (certificates signed with SHA-1 or MD5 are invalid under the default security level). Python 3.10, GCC 11, glibc 2.35.
- The journal defaults to zstd compression and keyed hashes, so journals written on 22.04 cannot be read by the journal tools of 18.04 or 20.04.
- Wayland is the default desktop session on most hardware without an NVIDIA desktop graphics card.
- Standard support ends in June 2027, so plan the move to 24.04 or 26.04 now.

### 24.04 LTS (Noble)

- Kernel 6.8, systemd 255.4, Netplan 1.0, Python 3.12, GCC 14, glibc 2.39. Year 2038 support on armhf (64-bit `time_t`).
- Repositories moved to `/etc/apt/sources.list.d/ubuntu.sources` in the deb822 format. APT warns about repositories signed with 1024-bit RSA keys (acceptable keys are RSA 2048 bits or larger, Ed25519 and Ed448); the release notes say a later APT 2.8.0 would turn the warning into an error.
- Unprivileged user namespaces are restricted by default for unconfined programs through AppArmor (`kernel.apparmor_restrict_unprivileged_userns`); the release notes describe the profile options and the sysctl to turn it off.
- `needrestart` restarts services affected by a library upgrade systematically, including non-interactively.
- TLS 1.0, 1.1 and DTLS 1.0 are disabled for programs using GnuTLS as well as OpenSSL.
- `irqbalance` is no longer installed and enabled by default; OpenSSH no longer depends on `libsystemd`.
- TPM-backed full-disk encryption is available as an experimental installer option (from 23.10).

### 26.04 LTS (Resolute)

From the 26.04 release notes (summary for LTS users and changes since 25.10):

- Kernel 7.0 for the GA kernel (from 6.8) and for HWE (from 6.17); crash dumps enabled by default; Livepatch on arm64; the real-time kernel is in the main archive without Pro.
- systemd 259 (from 255): cgroup v1 support removed (hosts running cgroup v1 are not allowed to upgrade, and 26.04 containers will not run on them); last release with SysV service script compatibility; `/tmp` is a tmpfs by default.
- Netplan 1.2; APT 3.1 (fallback solver, OpenSSL, pager, `apt history-*`, `apt-key` removed); dracut is the default initramfs generator (initramfs-tools remains supported); `pkcon` removed in favour of `pkgcli`.
- `sudo-rs` is the default sudo and `sudo.ws` is the original; `sudo-ldap` is removed. `rust-coreutils` provides the core utilities except `cp`, `mv` and `rm`, which remain GNU; GNU versions are available with a `gnu` prefix.
- chrony replaces systemd-timesyncd for new installations, with NTS to Ubuntu's servers.
- OpenSSH 10.2p1: hybrid post-quantum key exchange `mlkem768x25519-sha256` by default, a warning when a non-post-quantum exchange is negotiated, DSA removed, no DSA host keys generated, `PerSourcePenalties`, `sshd.service` alias for `ssh.service`.
- OpenSSL has post-quantum algorithm support (ML-KEM, ML-DSA, SLH-DSA) and QUIC. SSSD 2.12 runs as the `sssd` user and drops the implicit files provider. Samba 4.23, PHP 8.5, PostgreSQL 18, MySQL 8.4, HAProxy 3.2, Python 3.14, GCC 15.2, glibc 2.43, OpenJDK 25, Go 1.25, Rust 1.93.
- MySQL 8.4 locks accounts that use `mysql_native_password` unless it is enabled in `mysqld.cnf`; RabbitMQ cannot be upgraded directly because of feature flags; Dovecot 2.4 changes its configuration format; Squid 7 rejects removed directives at startup.
- Cloud images for amd64 are built for the `amd64v3` microarchitecture level by default. Canonical lists AWS instance families (M1 to M4, C1, C3, C4, R3, R4, I2, G3, P2, P3, P3dn) and two Google Cloud CPU platforms (Ivy Bridge, Sandy Bridge) as unsupported.
- IBM Z requires z15 or newer. TPM-backed full-disk encryption is available in the installer with documented limitations. GNOME 50 is Wayland-only (no Xorg session for GNOME). The release notes also announce Ubuntu Pro for WSL 1.0 and a new hardware-enablement virtualisation stack (`qemu-hwe`, `libvirt-hwe`, `seabios-hwe`, `edk2-hwe`).
- authd (cloud identity logins) is in the archive with Microsoft Entra ID, Google and generic OIDC brokers.

### 26.04.1 and 26.10

26.04.1 (27 Aug 2026) is the point release after which `do-release-upgrade` offers 24.04 hosts the move to 26.04 (Canonical's upgrade guide: an LTS-to-LTS upgrade is offered after the first point release; the 26.04.1 notes also set `Prompt=lts` for resolute in the upgrader data). 26.10 is an interim release (released 15 Oct 2026, supported until July 2027).

## Using this file

Quote a row with its date. When asked "is Ubuntu N supported", answer with Canonical's standard-support and Pro columns, say which coverage the host actually has (`pro status`), and recommend a decision on that evidence.
