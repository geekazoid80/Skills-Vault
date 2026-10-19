# Debian architecture reference

Sources: the Debian releases page, the Debian 12 and 13 release notes, Debian manual pages (apt, apt-secure, sources.list, debsecan, check-support-status, needrestart) and the Freexian ELTS page, read on 2026-10-19. Statements from experience rather than a page are marked.

## Suites and the release process

- **unstable (sid)** receives new uploads and is never released. **testing** is the suite that becomes the next stable; today that is forky (Debian 14), which has no release date. **stable** is the current release (13, trixie); **oldstable** is the previous one (12, bookworm); **oldoldstable** is the one before (11, bullseye).
- A stable release is changed only by security updates and by point releases, which collect important fixes and security updates into new installation media (13.7 on 12 September 2026, per the releases page). Point releases are not new versions of Debian; a host that has run `apt full-upgrade` is already on the point release.
- The releases page records, per release: release date, end of full support (Security Team), end of LTS and end of ELTS. Debian's own words: the life cycle is five years, three years of full support and then two of LTS.

## Who patches what

| Stage | Run by | Scope |
|---|---|---|
| Full support | The Debian Security Team and the stable maintainers | All of `main`, subject to the limits below |
| LTS | A separate project of volunteers and companies (Debian LTS) | A subset of packages and architectures chosen by the LTS team |
| ELTS | Freexian (paid service) | Only the packages its customers use, at least amd64, the kernel through a newer-kernel backport |

Advisories are published as DSA (Debian Security Advisory) and DLA (LTS advisory). The Debian Security Tracker holds per-package vulnerability status; `debsecan` reads it. Coverage limits stated in the release notes: Qt WebEngine and similar engines are not covered; Go and Rust packages mostly receive fixes only in point releases; Chromium in oldstable has a shorter coverage period.

## The archive

- **Components:** `main` (DFSG-free), `contrib` (free but depends on non-free), `non-free`, and `non-free-firmware` (split from `non-free` in Debian 12).
- **Suites per release:** `<codename>`, `<codename>-updates`, `<codename>-security`, `<codename>-backports` (and `-backports-sloppy`, which holds packages from testing rebuilt for the old stable and gives up the clean upgrade path; the backports page says the old stable's backports are available for one year after a new stable release). The security archive lives at `security.debian.org/debian-security`.
- **Sources format:** deb822 (`.sources`) is the format the release notes use; one-line `.list` files still work. A `.sources` stanza has `Types:`, `URIs:`, `Suites:`, `Components:` and optionally `Signed-By:`.
- **Architectures (trixie):** amd64, arm64, armel (last release), armhf, ppc64el, riscv64 (new, official) and s390x, with a partial i386 userland. All architectures except i386 use a 64-bit `time_t`.

## apt and dpkg

`dpkg` handles single packages (`dpkg -l`, `-L`, `-S`, `--audit`, `--configure -a`); `apt` and `apt-get` resolve and download. APT 3 appears in trixie. `apt-secure(8)` describes repository signing: use `Signed-By` or a keyring in a directory apt reads, not the global keyring. Pinning (`/etc/apt/preferences.d/`) sets priorities by origin, suite or version; `apt-cache policy` shows the result. `apt-mark` records auto/manual state and holds. `debconf` stores package configuration answers; `dpkg-reconfigure` re-asks.

## Installation automation

The installer (`debian-installer`) can be driven by a preseed file (answers to the installer's debconf questions) delivered by network, boot parameter or media. Preseed files can contain password hashes and mirror credentials; treat them as secrets. Cloud and VM images are built with tools such as `debootstrap`, `mmdebstrap` and the official cloud images; `cloud-init` is used on cloud images. HTTP Boot of the installer and live images is supported in trixie on UEFI and U-Boot firmware.

## Mandatory access control and hardening

AppArmor is available in Debian's kernel and is a normal choice on servers; confirm the state of a given host with `aa-status`. Landlock is a kernel feature for unprivileged sandboxing that applications can use; Debian's kernel configuration decides whether it is built in (check `/sys/kernel/security/lsm`). Trixie adds Pointer Authentication and Branch Target Identification hardening on arm64 where the hardware supports it. Generic hardening (SSH, sysctl, auditd) is in `linux-host-ops`.

## Networking and time in trixie (from the release notes)

systemd 257 is the init system. Network interface naming can change across the upgrade on some systems (see best-practices). `isc-dhcp-client` is deprecated upstream; NetworkManager and systemd-networkd ship their own DHCP clients, and `dhcpcd-base` replaces it for ifupdown. LXD is no longer updated in Debian; Debian recommends Incus. `sudo-ldap` will be removed in forky; use `libsss-sudo`.
