---
name: macos-ops
description: "Use for day-to-day macOS administration and troubleshooting on macOS 14 Sonoma, 15 Sequoia, 26 Tahoe and 27 Golden Gate, on Apple silicon and Intel: launchd and launchctl, APFS and snapshots, System Integrity Protection, Gatekeeper, code signing and quarantine, FileVault, the application firewall, softwareupdate, Time Machine, networksetup and scutil, unified logging, crash and hang triage, Rosetta, Homebrew and shell environment, and which macOS releases still get security updates. Triggers include \"macOS\", \"Mac\", \"Apple silicon\", \"Rosetta\", \"launchctl\", \"launchd plist\", \"APFS\", \"FileVault\", \"fdesetup\", \"SIP\", \"csrutil\", \"Gatekeeper\", \"spctl\", \"Time Machine\", \"tmutil\", \"networksetup\", \"softwareupdate\", \"log show\", \"sysdiagnose\", \"Homebrew prefix\", \"macOS 27\", \"Golden Gate\", \"macOS end of support\". NOT for MDM, configuration profiles, DDM, ADE or Platform SSO (macos-mdm-ops), NOT for Windows (windows-client-ops), NOT for generic Linux (linux-host-ops), NOT for Office document handling on a Mac (macos-office-docs), NOT for choosing an operating system (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# macOS operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: macos-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

macOS is a BSD-derived Unix with its own service manager (`launchd`), file system (APFS), security stack (SIP, the signed system volume, Gatekeeper, TCC, FileVault) and management plane (configuration profiles and declarative device management). It differs from Linux in the places that bite administrators: no `systemd`, no `apt` or `dnf`, `/bin/bash` is 3.2, `zsh` is the login shell, and Apple changes behaviour in every major release without published end dates.

**Core principle:** read first, change second, and state the blast radius (reboot, data loss, loss of managed state) before any change. Version and lifecycle facts move every September; check them against Apple's pages on the day and say which page and date.

> **Caveat on provenance.** Commands, release facts and scripts were reshaped from a community upstream that was written before macOS 27 shipped, then corrected against Apple Support pages, Apple's device-management schemas and the local man pages of a macOS 26.7.1 machine on 2026-10-19, and reviewed independently. Scripts are checked with `shellcheck` and stub commands only; they have not been run against a managed fleet.

## Step 0: establish what you are on

```sh
sw_vers                 # ProductVersion and BuildVersion
uname -m                # arm64 (Apple silicon) or x86_64 (Intel, or a shell running under Rosetta)
csrutil status          # System Integrity Protection
fdesetup status         # FileVault
profiles status -type enrollment   # managed or not (more in macos-mdm-ops)
```

Major version, architecture and management state decide almost every answer. `macOS 26` and `27` are year-based versions (Tahoe, then Golden Gate); `macOS 16` does not exist. The scripts in `scripts/` gather the rest.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Destructive, disruptive or security-sensitive, get explicit approval |
|---|---|---|
| `sw_vers`, `csrutil status`, `spctl --status`, `fdesetup status`, `diskutil list` and `info`, `tmutil destinationinfo`, `tmutil latestbackup`, `launchctl print` and `print-disabled`, `networksetup -get*` and `-list*`, `scutil --dns`, `log show`, `systemextensionsctl list`, `softwareupdate -l`, `codesign --verify`, `spctl --assess` | `softwareupdate -i`, `networksetup -set*`, `defaults write`, `launchctl bootstrap`, `bootout`, `enable`, `disable`, `kickstart`, `tmutil startbackup`, `tmutil addexclusion`, `brew install` and `upgrade`, `socketfilterfw --set*`, `fdesetup changerecovery` | `csrutil disable` (Recovery only), `fdesetup disable`, `diskutil eraseDisk` and `apfs deleteVolume`, `tmutil deletelocalsnapshots` and `delete`, `tccutil reset <service>` (without a bundle id it wipes that service for every app) and `tccutil reset All`, `bputil` (not for production use per its man page; it can leave a Mac unbootable), `xattr -d com.apple.quarantine` on software of unknown origin, `kmutil load`, `unload` and `clear-staging`, `systemextensionsctl reset`, erasing or reinstalling, removing a managed profile |

Two commands that look like checks but are not: `memory_pressure` is documented as a tool to **apply** or simulate memory pressure and its man page lists no read-only mode (read free memory from `sysctl kern.memorystatus_level` or `vm_stat` instead), and `mdmclient` arguments are private and change without notice (Apple's own man page says not to rely on them).

## Release lifecycle and hardware support (Apple pages, 2026-10-19)

Apple publishes no end-of-support dates for macOS. The evidence is [Apple's security releases page](https://support.apple.com/en-us/100100): on 28 September 2026 it listed macOS Golden Gate 27.0.1, Tahoe 26.7.1 and Sequoia 15.8.1; Sonoma's last entry was 14.8.9 on 6 August 2026 and it was absent from the 14 and 28 September updates, so treat Sonoma as no longer receiving security fixes unless a new entry appears (Safari 26.6.1 on 18 August 2026 still lists Sonoma, so the inference is about macOS itself, not every component). State this as an inference from the page, with its date.

| Release | Latest on 2026-10-19 | Notes |
|---|---|---|
| macOS 27 Golden Gate | 27.0.1 (28 Sep 2026) | Apple silicon only, including the MacBook Neo; legacy MDM software update management no longer functions |
| macOS 26 Tahoe | 26.7.1 (28 Sep 2026) | Last release for Intel Macs; four Intel models |
| macOS 15 Sequoia | 15.8.1 (28 Sep 2026) | Still receiving security updates |
| macOS 14 Sonoma | 14.8.9 (6 Aug 2026) | No update in September; treat as unsupported |

Intel Macs that Tahoe supports: MacBook Pro 16-inch (2019), MacBook Pro 13-inch (2020, four Thunderbolt 3 ports), iMac (27-inch, 2020), Mac Pro (2019). Apple has said Intel Macs keep receiving security updates for a period after Tahoe (reported as three years; confirm on Apple's page before planning a refresh around it). Rosetta is available on Apple silicon through macOS 27; from macOS 28 it covers only certain older games ([Apple Support 102527](https://support.apple.com/en-us/102527)). Rosetta is not reinstalled automatically on upgrade to 27 if it was installed before (macOS 27 enterprise notes). `references/version-notes.md` lists what changed for administrators in each release.

## launchd

`launchd` is PID 1 and replaces `init`, `cron` and `inetd`. LaunchDaemons (`/Library/LaunchDaemons`, root) run at boot; LaunchAgents (`/Library/LaunchAgents`, `~/Library/LaunchAgents`) run per login session. Apple's own live in `/System/Library`. Use the subcommands in `launchctl`'s man page:

```sh
launchctl print system/com.example.svc                 # state of one service
launchctl print-disabled system                        # persistent enable/disable overrides
sudo launchctl bootstrap system /Library/LaunchDaemons/com.example.svc.plist
sudo launchctl bootout system/com.example.svc
sudo launchctl kickstart -k system/com.example.svc     # restart
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.agent.plist
```

`load` and `unload` are legacy; prefer `bootstrap` and `bootout` with an explicit domain (`system`, `gui/<uid>`, `user/<uid>`). A system plist must be owned by root and not writable by group or others, or launchd will refuse it. Background items users see in System Settings are tracked by a database whose tooling (`sfltool dumpbtm`) is undocumented; do not script against it.

## Storage, snapshots, Time Machine

APFS containers share space between volumes; the system volume is sealed (signed system volume) and the data volume is `/System/Volumes/Data`. `diskutil apfs list` shows containers; `tmutil listlocalsnapshots /` shows local snapshots. `cp -c` makes copy-on-write clones. Time Machine is driven by `tmutil` (`destinationinfo`, `latestbackup`, `listbackups`, `startbackup`, `addexclusion`, `isexcluded`, `verifychecksums`); `tmutil status` is not in the man page, so prefer the documented verbs. The terminal app may need Full Disk Access before `tmutil` can read destinations. Apple deprecated the AFP client in macOS 15.5 and will remove it in a future release, so use SMB destinations for network backups.

## Security stack

| Control | Check | Notes |
|---|---|---|
| SIP | `csrutil status`, `csrutil authenticated-root status` | Changing either needs Recovery; leave it on |
| Gatekeeper | `spctl --status`, `spctl --assess` | From macOS 15 `spctl` can no longer disable Gatekeeper; use System Settings or management |
| Quarantine | `xattr -l <file>` | The attribute `com.apple.quarantine` drives first-launch checks |
| Code signing | `codesign --verify --verbose`, `codesign -dv --verbose=4` | Notarisation is checked by Gatekeeper |
| FileVault | `fdesetup status`, `fdesetup list`, `haspersonalrecoverykey`, `hasinstitutionalrecoverykey` | AES-XTS, hardware-accelerated; Apple's Platform Security guide gives AES-256 in XTS mode for A14 and later and M1 and later, and AES-128 in XTS mode for A9 to A13 and S5 and later, so quote the cipher per chip, not as one figure |
| Firewall | `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` | From macOS 15 the settings are no longer in `com.apple.alf.plist`; use `socketfilterfw` |
| TCC | no read command before macOS 27 (`tccutil reset` is a change, listed in the destructive column) | macOS 27 adds `tccutil list`; apps can no longer read the local TCC database |
| Remote Login | listening port 22 | macOS 26 can unlock FileVault over SSH after a restart when Remote Login is on (`apple_ssh_and_filevault` man page) |

## Updates

`softwareupdate -l` lists updates, `-i` installs, `--list-full-installers` and `--fetch-full-installer` handle full installers, and `--install-rosetta` installs Rosetta. On a managed Mac, updates are enforced by declarative software update management; the legacy `com.apple.SoftwareUpdate` payload and the update commands were deprecated in macOS 26 and no longer function in 27 (see `macos-mdm-ops`).

## Shell and package management

`zsh` is the default shell; Terminal opens login shells, so environment belongs in `~/.zprofile`. `/bin/bash` and `/bin/sh` are bash 3.2 (checked: 3.2.57 on macOS 26.7.1): no associative arrays, no `${var,,}`; write portable `sh` or use `zsh`. `/etc/paths` and `/etc/paths.d` feed `path_helper`. Homebrew installs under `/opt/homebrew` on Apple silicon and `/usr/local` on Intel; add `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile` on Apple silicon. `/etc/resolv.conf` is generated by the system; configure DNS with `networksetup -setdnsservers` or a profile.

## Diagnostics in one screen

`log show --last 1h --predicate 'subsystem == "..."'`, `log stream`, `log collect`; `sysdiagnose`; crash reports in `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports`; `diskutil verifyVolume`; `scutil --dns`, `networksetup -getinfo "Wi-Fi"`, `sudo wdutil info`; `networkQuality`. `references/diagnostics.md` has the workflows.

## Pitfalls

1. Treating `/usr/local` as the Homebrew prefix on Apple silicon.
2. Disabling SIP to fix something that has a supported route (system extensions, `/usr/local`).
3. Using `launchctl load` and `unload`, or the wrong domain.
4. Editing `/etc/resolv.conf` or `com.apple.alf.plist` by hand.
5. Writing bash 4 syntax into a script run by `/bin/bash`.
6. Running `memory_pressure` or any `tccutil reset` as if it were read-only.
7. Scripting against `mdmclient`, `sfltool dumpbtm` or other private interfaces.
8. Assuming a Mac supports the next release: macOS 27 needs Apple silicon.
9. Assuming an Intel shell means an Intel Mac (a shell under Rosetta reports `x86_64`).
10. Quoting a support end date for macOS: Apple publishes none.

## Red flags

- A version, hardware or lifecycle claim with no Apple page and date behind it.
- A command from memory that is not in the man page (check `man -w <tool>` and the options).
- A state-changing command presented as a check.
- Passwords, recovery keys or tokens written into a command or script.
- Advice to turn off SIP, Gatekeeper or the firewall as the first fix.

## References and scripts

- `references/architecture.md`: XNU, launchd, APFS and the sealed system volume, Apple silicon versus Intel, Rosetta, keychains and accounts, networking, frameworks.
- `references/best-practices.md`: hardening, updates, FileVault, Time Machine, Homebrew, shell, SSH keys, TCC and login items.
- `references/diagnostics.md`: unified logging, crash and hang triage, performance, disk and network tools.
- `references/version-notes.md`: dated release and hardware support, and what changed for administrators in macOS 14, 15, 26 and 27.
- `scripts/system-health.sh`, `security-posture.sh`, `storage-and-backup.sh`, `network-diagnostics.sh`, `launch-items.sh`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings. A check that could not run is therefore never a clean pass.

The scripts are POSIX `sh` that runs under the stock bash 3.2, read state and change nothing (`security-posture.sh` makes one TCP connection to localhost port 22 to test Remote Login, which can start `sshd` on demand), and take thresholds from environment variables (`MACOS_MIN_MAJOR` defaults to 15, so a Sonoma Mac is flagged as outside security updates; set it to 14 to accept that). They pass `shellcheck -s sh` and were run against stub commands in an empty-result world and a throwing world (neither exits 0) and in healthy and unhealthy worlds, but they have not been run on a managed fleet, and the output formats they parse come from documentation and man pages. Run them on a non-critical Mac first; `network-diagnostics.sh` pings the gateway and does one name lookup, and nothing else is active.

## Boundaries

- MDM, profiles, DDM, ADE, supervision, bootstrap token, Recovery Lock, Platform SSO: `macos-mdm-ops`.
- Identity provider tenant configuration: `entra-id`, `identity-access-management`.
- EDR and Defender on the Mac: `defender-for-endpoint`, `endpoint-detection-response`.
- Linux administration: `linux-host-ops`. Windows: `windows-client-ops`.
- Office document rendering and editing on a Mac: `macos-office-docs`.
- Benchmarks and CVE handling: `compliance-benchmark-audit`, `vulnerability-management`.
- Credentials: `secrets-hygiene`. Shell script conventions: `bash-defensive`.

## Bottom line

Pin major version, architecture and management state; use the documented subcommands; leave SIP, Gatekeeper and FileVault on; remember that Apple publishes no end dates, so cite the security releases page with its date; and treat macOS 27 as Apple silicon only.
