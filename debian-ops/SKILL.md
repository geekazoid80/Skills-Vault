---
name: debian-ops
description: "Use for Debian-specific administration on 11 (bullseye), 12 (bookworm) and 13 (trixie): the release and support model (stable, oldstable, LTS, ELTS, point releases), apt sources in the deb822 format, archive components and the security pocket, backports and pinning, security tracking with debian-security-support, debsecan and unattended-upgrades, needrestart, release-to-release upgrades and their per-release gotchas, the tmpfs /tmp and sysctl.conf changes in 13, and preseed. Triggers include \"Debian\", \"trixie\", \"bookworm\", \"bullseye\", \"Debian 13\", \"Debian LTS\", \"Debian ELTS\", \"oldstable\", \"backports\", \"sources.list\", \"deb822\", \"non-free-firmware\", \"debsecan\", \"check-support-status\", \"apt full-upgrade\", \"preseed\", \"upgrade Debian 12 to 13\". NOT for Ubuntu (ubuntu-ops), NOT for RHEL-family hosts (rhel-family-ops), NOT for SUSE (sles-ops), NOT for generic Linux operation such as systemd units, journalctl, LVM and backups (linux-host-ops), NOT for first-boot commissioning (linux-host-bringup), NOT for Proxmox VE hosts (proxmox-ops), NOT for choosing a distribution (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Debian operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: debian-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Debian is a community-governed distribution with three suites in development (unstable, testing) and release (stable), a package archive that Ubuntu and Proxmox VE build on, and a security model that changes character as a release ages: the Debian Security Team, then the volunteer-and-company Long Term Support (LTS) project, then paid Extended LTS from Freexian. This skill covers what is specific to Debian; generic Linux work (systemd units, journalctl, LVM, backups, apt and dnf basics) lives in `linux-host-ops`.

**Core principle:** know which release you run and who patches it today. A host on "Debian 12" in October 2026 is in LTS, not in the Security Team's care, and a host on 11 is in paid ELTS territory. Upgrade one release at a time, read that release's release notes before you start, and keep `apt` sources in step with the release you are on.

> **Caveat on provenance.** The content was reshaped from a community upstream that carried version errors (for example Python, systemd and GNOME versions for trixie, and a support timeline that omitted the dates) and was corrected against the Debian releases page, the Debian 12 and 13 release notes, Debian's manual pages and the Freexian ELTS page, read on 2026-10-19. The scripts are checked with `shellcheck` and stub commands only; they have not been run on a Debian host.

## Step 0: establish what you are running

```sh
cat /etc/debian_version; . /etc/os-release && echo "$PRETTY_NAME ($VERSION_CODENAME)"
dpkg --print-architecture; uname -r
apt-cache policy | head -20          # configured archives and pins
check-support-status                 # installed packages with limited or ended support (debian-security-support)
```

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Disruptive, get explicit approval |
|---|---|---|
| `apt-cache policy`, `apt-get -s dist-upgrade`, `apt list --upgradable`, `apt-mark showhold`, `dpkg --audit`, `dpkg -l`, `needrestart -b`, `check-support-status`, `debsecan`, `aa-status`, `systemctl --failed` | `apt install`, `apt upgrade`, `apt full-upgrade`, `apt-mark hold`, edits to `/etc/apt/sources.list.d/`, pinning files, `dpkg --configure -a`, `aa-enforce`, `aa-complain` | `apt full-upgrade` across a release boundary, `apt autoremove --purge` after one, removing a kernel, `dpkg --force-*`, switching the init system, changing the network configuration over SSH |

`debsecan` downloads its vulnerability data from the Internet each time it needs it (a network request; read its manual page before running it in a restricted network). `needrestart -b` is batch mode and restarts nothing.

## Releases and support

Dates are from Debian's releases page (debian.org/releases), read on 2026-10-19. Debian's wording on that page lags its dates, so read the dates, not the status words.

| Release | Released | End of full support (Security Team) | End of LTS | End of ELTS (Freexian) |
|---|---|---|---|---|
| 13 trixie (stable; 13.7 on 12 Sep 2026) | 9 Aug 2025 | 9 Aug 2028 | 30 Jun 2030 | 30 Jun 2035 |
| 12 bookworm (oldstable) | 10 Jun 2023 | 11 Jul 2026 (passed) | 30 Jun 2028 | 30 Jun 2033 |
| 11 bullseye (oldoldstable) | 14 Aug 2021 | 14 Aug 2024 (passed) | 31 Aug 2026 (passed) | 30 Jun 2031 |
| 10 buster | 6 Jul 2019 | 10 Sep 2022 | 30 Jun 2024 | 30 Jun 2029 |
| 14 forky | not scheduled | none | none | none |

- The life cycle is about five years: roughly three of full support, then two of LTS, per the Debian releases page. LTS is run by a separate group of volunteers and companies, not by the Security Team; ELTS is a paid service that covers only the packages its customers use, a limited set of architectures, and the kernel only through a backport of a newer one (Freexian's page).
- Forky is `testing`; it has no release date. `sid` is the permanent unstable suite and is never released.
- LTS for bookworm covers only i386, amd64, armhf, arm64 and ppc64el (Debian's bookworm page); other architectures have had no security updates since 11 July 2026.
- Security coverage has limits at every stage: Debian's release notes state that web browser engines such as Qt WebEngine are not covered, that Go and Rust packages have limited security support and often receive fixes only in point releases, and that Chromium in oldstable receives about six months of security support rather than twelve. `check-support-status` (package `debian-security-support`) reports installed packages affected.

## Package management

- **Sources:** Debian's release notes use the deb822 format (`/etc/apt/sources.list.d/*.sources`, with `Types`, `URIs`, `Suites`, `Components`) for their examples; the one-line `sources.list` still works. The security archive is `https://security.debian.org/debian-security` with suite `<codename>-security`. A typical server uses `<codename>`, `<codename>-updates` and `<codename>-security`.
- **Components:** `main`, `contrib`, `non-free` and `non-free-firmware`. `non-free-firmware` was split out of `non-free` in Debian 12, so that firmware can be installed without enabling the rest of `non-free`.
- **Backports:** `<codename>-backports` provides newer versions of selected packages built for stable; it is off by default and is installed package by package (`apt install -t <codename>-backports <package>`). Backports for the old stable are available for one year after a new stable release (the backports page): `bookworm-backports` and `bookworm-backports-sloppy` were updated until 9 August 2026. `-sloppy` holds packages from testing rebuilt for oldstable, gives up the clean upgrade path, and is unsupported. The release notes ask you to remove old `-backports` entries before an upgrade and add the new release's afterwards.
- **Keys:** repository keys belong in `/etc/apt/keyrings/` or a path referenced by `Signed-By`; see `apt-secure(8)`. Do not use `apt-key`: bookworm's `apt` package ships `/usr/bin/apt-key` and trixie's does not (packages.debian.org file lists, 2026-10-19), so scripts that call it fail on 13.
- **Pinning and holds:** `/etc/apt/preferences.d/` and `apt-mark hold`. A hold or pin forgotten on a package makes a release upgrade fail late.
- **Packages that did not come from Debian:** `apt list '?narrow(?installed, ?not(?origin(Debian)))'` lists them (the Debian 13 release notes give this command; it also lists packages Debian once provided, such as old kernels). Review them, and remove obsolete packages, before an upgrade.

## Security tracking and unattended patching

- `unattended-upgrades` applies updates from the origins in its `Origins-Pattern` (the packaged `50-unattended-upgrades` file lists them; read it, because the default includes the stable release's own archive as well as security); `apt-listchanges` shows changelogs and NEWS before they install.
- `needrestart` finds services and sessions that still run old libraries and reports a pending kernel or microcode update in batch mode (`needrestart -b`).
- `debsecan --suite <codename> --only-fixed --format simple` lists one line per vulnerability and package pair with a fix available; it needs the correct suite to be accurate, flags every binary package built from a vulnerable source, and compares an unknown version (such as a backport) with unstable, so expect some false positives.
- `check-support-status` lists packages with limited support or support that has ended or will end before the release's.
- Subscribe to the `debian-security-announce` list or watch the Debian Security Advisories (DSA) and LTS advisories (DLA).

## Upgrading to the next release

Source: the Debian 13 release notes (chapters 4 and 5).

- Upgrade from the previous release only; skipping releases is not supported. Install every point release first. For trixie, finish the bookworm upgrade (the usr-merge) before starting.
- Run it under `tmux` or `screen`, with a backup and a way back into the console. If the host is remote, first update OpenSSH to 1:9.2p1-2+deb12u7 or later (an interrupted upgrade over SSH could otherwise lock you out; release notes 5.1.1).
- `/boot` should be at least 768 MB with about 300 MB free if it is a separate partition (very likely too small on systems installed with Debian 10 or earlier).
- Edit the sources to the new codename (`<codename>`, `<codename>-updates` and `<codename>-security`; remove the old `-backports` entries and add the new release's afterwards), `apt update`, then check space with `apt -o APT::Get::Trivial-Only=true full-upgrade` (it can report an error until the minimal upgrade has run), then `apt upgrade --without-new-pkgs`, `apt full-upgrade` and a reboot. The release notes list no special action before the first reboot for trixie.
- Trixie changes to expect: `/tmp` is a tmpfs (up to 50% of memory; change with `systemctl edit tmp.mount`, or `systemctl mask tmp.mount` to go back) and `/tmp` (10 days after last use) and `/var/tmp` (30 days) are cleaned on a schedule on new installations (an upgraded host keeps the old behaviour through `/etc/tmpfiles.d/tmp.conf`), and files left in the old `/tmp` are hidden once the tmpfs mounts; `/etc/sysctl.conf` is no longer read (use `/etc/sysctl.d/*.conf`; the `linux-sysctl-defaults` package ships the defaults); `ping` no longer has the raw-socket capability and relies on `net.ipv4.ping_group_range`; `last`, `lastb` and `lastlog` are replaced (use `wtmpdb`, `lastlog2`, `lslogins`); OpenSSH no longer supports DSA keys and the server no longer reads `~/.pam_environment`; interface names may change on some systems (check with `udevadm test-builtin net_setup_link` before the reboot); i386 has reduced support and armel is in its last release.
- Read the "Known severe bugs" list in the release notes for the target release.

## Pitfalls

1. Treating "Debian 12" as supported by the Security Team in late 2026; it is in LTS.
2. Running 11 without ELTS or an upgrade plan; its LTS ended on 31 Aug 2026.
3. Leaving `-backports` entries for the old release in place during an upgrade, or still counting on `bookworm-backports` after August 2026.
4. Skipping a release, or starting an upgrade without the latest point release.
5. A separate `/boot` too small for the new kernel.
6. Editing `/etc/sysctl.conf` on 13 and expecting it to apply.
7. Large files in `/tmp` on 13 (it is memory-backed) or long-lived data that the cleaner now removes.
8. Relying on `lastlog` or `last` after the move to 13 without installing the replacements.
9. Assuming a web-engine application is covered by security support.
10. Using `apt-key` in new automation; use `Signed-By`.
11. Enabling `non-free` when only firmware was needed (`non-free-firmware`).

## Red flags

- A support date given without the Debian releases page behind it.
- An upgrade advised across more than one release, or without a rollback plan.
- `dpkg --force-all` or `--force-depends` offered as a routine fix.
- ELTS or any repository token pasted into a script or ticket.

## References and scripts

- `references/architecture.md`: suites and the release process, the archive, apt and dpkg, security processes, installer automation.
- `references/best-practices.md`: patching, unattended-upgrades, backports and pinning, hardening, upgrade checklist.
- `references/diagnostics.md`: broken packages, apt errors, boot and initramfs, time and network, logs.
- `references/version-notes.md`: dated lifecycle table and what changed in 11, 12 and 13.
- `scripts/system-health.sh`, `update-state.sh`, `security-posture.sh`, `network-and-time.sh`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings or an invalid setting (the message is on standard error).

The scripts are POSIX `sh` (the default `/bin/sh` on Debian is dash), read state and change nothing (`update-state.sh` runs `debsecan`, which downloads data, only with `CHECK_DEBSECAN=1`; `network-and-time.sh` does one name lookup and pings the gateway only with `PING_GATEWAY=1`), and take thresholds from environment variables. They use the packages `distro-info`, `debian-security-support`, `needrestart`, `debsecan` and `unattended-upgrades`; a missing package is reported as a warning for the check that needs it. The release-stage check uses built-in LTS and ELTS lists dated 2026-10-19 (`LTS_CODENAMES`, `ELTS_CODENAMES`) and says so when they are more than 180 days old. Several checks need root; without it they warn that the check was not performed. They pass `shellcheck -s sh` and were run against stub commands in an empty-result world, a throwing world, and healthy and unhealthy worlds, but not on a Debian host; the output formats they parse come from manual pages and Debian documentation.

## Boundaries

- Ubuntu: `ubuntu-ops`. RHEL, Rocky, AlmaLinux: `rhel-family-ops`. SUSE: `sles-ops`.
- Generic Linux operation: `linux-host-ops`; first-boot commissioning: `linux-host-bringup`.
- Proxmox VE, which is built on Debian: `proxmox-ops`.
- Containers on Debian: `podman-ops`, `docker-ops`, `container-security`.
- Vulnerability handling and benchmarks: `vulnerability-management`, `compliance-benchmark-audit`.

## Bottom line

Know the release and who patches it, keep sources and backports in step with it, upgrade one release at a time from the release notes, and take support dates from debian.org rather than memory.
