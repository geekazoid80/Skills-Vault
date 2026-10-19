# Debian version notes

Dated 2026-10-19. Sources: the Debian releases page (debian.org/releases, built 23 September 2026), the Debian 12 and 13 release notes, and the Freexian ELTS page. Re-check the releases page before quoting a date.

## Lifecycle snapshot

| Release | Codename | Released | End of full support | End of LTS | End of ELTS |
|---|---|---|---|---|---|
| 13 | trixie | 9 Aug 2025 | 9 Aug 2028 | 30 Jun 2030 | 30 Jun 2035 |
| 12 | bookworm | 10 Jun 2023 | 11 Jul 2026 | 30 Jun 2028 | 30 Jun 2033 |
| 11 | bullseye | 14 Aug 2021 | 14 Aug 2024 | 31 Aug 2026 | 30 Jun 2031 |
| 10 | buster | 6 Jul 2019 | 10 Sep 2022 | 30 Jun 2024 | 30 Jun 2029 |
| 9 | stretch | 17 Jun 2017 | 18 Jul 2020 | 1 Jul 2022 | 30 Jun 2027 |
| 14 | forky | none | none | none | none |

- 13.7 was released on 12 September 2026 and is the latest point release seen.
- On the page the status column still says bullseye is "under LTS support" although its end-of-LTS date has passed; trust the dates. Freexian's page lists ELTS end dates for 9 to 13 (June 2027, 2029, 2031, 2033 and 2035); its quote invitation names Debian 9, 10 and 11.
- A release in LTS is patched by the LTS team for a subset of packages and architectures (bookworm: i386, amd64, armhf, arm64 and ppc64el only); ELTS needs a subscription and a package list.

## Debian 11 (bullseye)

Out of Security Team support since 14 August 2024 and out of LTS since 31 August 2026. Upgrade to 12 and then 13, or buy ELTS (until 30 June 2031). This release has `non-free` carrying firmware; the separate `non-free-firmware` component arrived in 12, so the 11 to 12 upgrade involves adding it to sources.

## Debian 12 (bookworm)

Kernel 6.1 series, systemd 252 (from the 12 release notes). Introduced the `non-free-firmware` archive area (most non-free firmware moved there from `non-free`), which allows official installation images built from `main` and `non-free-firmware` without `contrib` or `non-free`. Out of Security Team support since 11 July 2026; LTS runs to 30 June 2028. Operational changes from the 12 release notes: Python interpreters are marked externally managed (PEP 668), so `pip` refuses system-wide installs unless `--break-system-packages` is given; `rsyslog` is no longer installed by default (use `journalctl`); the NTP packages changed to `ntpsec`. Plan the move to 13 now: the release notes require you to be on bookworm's latest point release first.

## Debian 13 (trixie)

From the 13 release notes: Linux 6.12 series, systemd 257, GCC 14.2, glibc 2.41, Python 3.13, OpenSSL 3.5, OpenSSH 10.0p1, PostgreSQL 17, MariaDB 11.8, PHP 8.4, Nginx 1.26, Samba 4.22, curl 8.14.1, GNOME 48, KDE Plasma 6.3.6, LLVM 19, Rust 1.85. riscv64 is an official architecture. HTTP Boot is supported for the installer. curl supports HTTP/3 and ships `wcurl`. 64-bit `time_t` on all architectures except i386.

Operational changes (release notes, chapter 5):

- `/tmp` is a tmpfs by default (50% of memory maximum); `/tmp` and `/var/tmp` are cleaned on a schedule on new installations; upgraded systems keep the old behaviour through `/etc/tmpfiles.d/tmp.conf`.
- `/etc/sysctl.conf` is no longer honoured; `linux-sysctl-defaults` supplies `/usr/lib/sysctl.d/50-default.conf`; use `/etc/sysctl.d/*.conf`.
- `ping` no longer has `CAP_NET_RAW` and uses ICMP datagram sockets controlled by `net.ipv4.ping_group_range`.
- `last`, `lastb` and `lastlog` are replaced (`wtmpdb`, `lastlog2`, `lslogins`).
- OpenSSH no longer supports DSA keys; the server no longer reads `~/.pam_environment`; `openssh-client-gssapi` and `openssh-server-gssapi` packages prepare for the removal of GSS-API from the main packages in forky.
- Encrypted file systems need the `systemd-cryptsetup` package; default encryption settings for plain-mode dm-crypt changed.
- Network interface names may change for the i40e driver and for firmware exposing the ACPI `_SUN` object.
- Deprecated for forky: `sudo-ldap` (use `libsss-sudo`), isc-dhcp, `lxd` (use Incus), fcitx 4, KDE Frameworks 5.
- Obsolete or removed: `deborphan` (use `apt autoremove` after `apt-mark minimize-manual`), `pcregrep`, `request-tracker4`.
- Security support limits: Qt WebEngine applications are not covered; Go and Rust packages have limited coverage.
- i386 has reduced support (a partial userland on 64-bit PCs) and armel is in its last release; MIPS ports are removed.

## Using this file

Quote a row with its date. For "is Debian N supported", state which stage it is in (Security Team, LTS, ELTS or none), the date that stage ends, and who runs it.
