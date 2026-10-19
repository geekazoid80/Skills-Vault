# macOS best-practices reference

Commands are checked against the man pages of a macOS 26.7.1 machine unless noted. Rules of thumb are marked.

## Hardening baseline

Start from a published benchmark (the CIS macOS benchmarks, Level 1 for everyone and Level 2 where the extra friction is acceptable) and your management service's baselines; treat the list below as the minimum to verify, not a replacement.

| Control | Verify | Notes |
|---|---|---|
| SIP on | `csrutil status` | Never disable as a fix |
| Authenticated root on | `csrutil authenticated-root status` | |
| Gatekeeper on | `spctl --status` | From macOS 15 `spctl` cannot disable it |
| FileVault on | `fdesetup status` | Escrow recovery keys to management, not to a spreadsheet |
| Firewall on | `socketfilterfw --getglobalstate`, `--getstealthmode`, `--getblockall` | Settings are not in `com.apple.alf.plist` any more |
| Remote Login off unless needed | listening port 22 | Limit to named users when on |
| Automatic updates | `defaults read /Library/Preferences/com.apple.SoftwareUpdate` | On managed Macs, enforce with declarative software update management |
| Guest account off | `defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled` | |
| Few local administrators | `dscl . -read /Groups/admin GroupMembership` | The list always includes `root`, so a limit of three allows two named accounts; a rule of thumb |
| Screen lock | managed through a profile | Per-user `defaults` settings are weak controls |
| Login window and sudo | managed through profiles; macOS 15 turned `sudo` logging off by default | Re-enable through a file in `/etc/sudoers.d` edited with `visudo`, never by editing `/etc/sudoers` directly, if you need it |

`fdesetup` subcommands that are safe to script: `status`, `isactive`, `list`, `haspersonalrecoverykey`, `hasinstitutionalrecoverykey` (these two print `false` on any error as well as when no key exists, so treat `false` as unconfirmed) and `supportsauthrestart`. `fdesetup validaterecovery` takes a recovery key, so never script it; `enable`, `disable`, `changerecovery` and `authrestart` change state.

## Software updates

- `softwareupdate -l` lists updates; `-i <label>` or `-a` installs; `--list-full-installers` and `--fetch-full-installer --full-installer-version <v>` handle full installers; `-r` restricts to recommended; `--background` forces a scan and `--schedule` reads the automatic check preference; `--install-rosetta` installs Rosetta.
- Managed Macs: updates, deferrals and deadlines are set with the declarations `com.apple.configuration.softwareupdate.enforcement.specific` (macOS 14 and later) and `com.apple.configuration.softwareupdate.settings` (macOS 15 and later). The legacy profile payload and MDM commands were deprecated in macOS 26 and no longer function in macOS 27 (`macos-mdm-ops`).
- Plan major upgrades like projects: hardware support first (macOS 27 is Apple silicon only), application and kernel-extension readiness, a pilot ring, and a rollback plan (a backup, because macOS cannot be downgraded in place).
- Background Security Improvements and Rapid Security Responses are small patches delivered outside point releases; confirm current behaviour on Apple's pages before relying on them.

## FileVault and Recovery

- Apple silicon: the Secure Enclave protects keys; Recovery Lock (set by management) protects Recovery. Intel: a firmware password protects Recovery on Macs that support it. Neither is a substitute for FileVault.
- Escrow personal recovery keys through management (a FileVault escrow payload with a bootstrap token lets management rotate keys). Rotate when a key may have been exposed.
- Unattended restarts: `fdesetup authrestart` restarts and unlocks once; it needs a credential and, per its man page, reduces protection by keeping an unlock key available across the restart, so use it deliberately.
- macOS 26 can unlock FileVault over SSH after a restart if Remote Login is on and the network is up; the man page `apple_ssh_and_filevault` describes password authentication for the unlock.

## Time Machine and backups

- Destinations: `tmutil destinationinfo`, `tmutil setdestination` (change), `tmutil removedestination` (change). Exclusions: `addexclusion`, `removeexclusion`, `isexcluded`. Backups: `startbackup`, `stopbackup`, `latestbackup`, `listbackups`. Local snapshots: `listlocalsnapshots`, `listlocalsnapshotdates`, `thinlocalsnapshots`, `deletelocalsnapshots`.
- Exclude large rebuildable data (virtual machine images, `node_modules`, caches) and test a restore, not only a backup.
- Network destinations use SMB; Apple deprecated the AFP client in macOS 15.5.
- A backup that nobody has restored is a hope. Record the date of the last successful restore test.

## Homebrew

Prefix `/opt/homebrew` (Apple silicon) or `/usr/local` (Intel); `brew --prefix` prints it. `eval "$(/opt/homebrew/bin/brew shellenv)"` belongs in `~/.zprofile`. Commands: `brew install`, `install --cask`, `upgrade`, `outdated`, `cleanup`, `doctor`, `bundle dump/install/check` for a reproducible Brewfile. On managed Macs decide who owns Homebrew (one admin user, not every user), and do not use `sudo brew`.

## Shell and scripting

- `zsh` is the default login shell; Terminal opens login shells, so `~/.zprofile` runs for every window.
- `/bin/bash` and `/bin/sh` are bash 3.2: no associative arrays or `${var,,}`. Portable scripts use `#!/bin/sh` and POSIX constructs, or `#!/bin/zsh`, or call a Homebrew bash explicitly. Check scripts with `shellcheck -s sh`.
- Do not parse output that the man page does not describe (`mdmclient`, `sfltool dumpbtm`, `app-sso` output) in anything that gates a decision.
- SSH: `ssh-keygen -t ed25519`, `ssh-add --apple-use-keychain`, and `UseKeychain yes` with `AddKeysToAgent yes` in `~/.ssh/config`.

## Privacy permissions and login items

TCC grants are per app and per service. `tccutil reset <service> [bundle id]` clears grants for a service (use `All` only on purpose). Management can pre-grant a subset through a privacy payload and, in macOS 27, a consolidated consent declaration. Review login items and background tasks in System Settings, General, Login Items and Extensions; management can lock them with a service management payload.

## Change discipline

State the blast radius, take a recent backup, schedule anything that restarts or erases, and write the rollback before the change. For anything that touches SIP, FileVault, Recovery or the bootstrap token on a managed Mac, check `macos-mdm-ops` first: a local change can break management state that is hard to restore.
