---
name: sles-ops
description: "Use for administering SUSE Linux Enterprise Server 15 SP4 to SP7 and SLES 16.0: the support lifecycle (general support, LTSS, per-minor dates on 16), registration with SUSEConnect, SCC and RMT, zypper patches and the exit codes scripts can use, Btrfs and Snapper snapshots and rollback, AppArmor on 15 versus SELinux on 16, YaST and wicked on 15 versus Agama, Cockpit and NetworkManager on 16, supportconfig, firewalld, and upgrades to 16. Triggers include \"SLES\", \"SUSE Linux Enterprise\", \"SLES 16\", \"SLES 15 SP7\", \"zypper\", \"zypper patch\", \"SUSEConnect\", \"SCC\", \"RMT\", \"Snapper\", \"snapper rollback\", \"Btrfs\", \"YaST\", \"Agama\", \"wicked\", \"supportconfig\", \"LTSS\", \"SLES end of life\". NOT for openSUSE Leap or Tumbleweed as products, NOT for RHEL-family hosts (rhel-family-ops), NOT for Ubuntu or Debian (ubuntu-ops, debian-ops), NOT for generic Linux operation such as systemd units, journalctl, LVM and backups (linux-host-ops), NOT for first-boot commissioning (linux-host-bringup), NOT for choosing a distribution (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# SLES operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: sles-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

SUSE Linux Enterprise Server (SLES) is SUSE's commercial enterprise distribution. SLES 15 (2018 to 2031 and beyond) is organised as service packs (SP) with modules, YaST, wicked and AppArmor. **SLES 16.0 (November 2025) is a different system in the ways that matter to administrators**: YaST and wicked are removed, NetworkManager is the only network stack, SELinux replaces AppArmor, the module concept is gone, and installation is by Agama. Generic Linux work (systemd units, journalctl, LVM, backups, the apt and dnf basics) lives in `linux-host-ops`.

**Core principle:** identify the product version, the service pack or minor, and whether the host is registered, before you give advice: tooling, security framework and support dates all depend on it, and a host that is not registered receives no updates.

> **Caveat on provenance.** The content was reshaped from a community upstream that covered only SLES 15 SP5 and SP6 and was corrected and extended against SUSE's lifecycle page, the SLES 15 SP7 and 16.0 release notes, the SLES 16 documentation (comparison with SLE 15, upgrading, SELinux and Snapper guides) and the zypper and snapper manual pages, read on 2026-10-19. Some SUSE pages were summarised by a fetching tool and are marked where a figure rests on one. The scripts are checked with `shellcheck` and stub commands only; they have not been run on a SLES host.

## Step 0: establish what you are running

```sh
. /etc/os-release && echo "$PRETTY_NAME ($VERSION_ID)"        # 15-SP7 or 16.0
uname -r; zypper lr -u                                         # kernel; configured repositories
SUSEConnect --status-text                                      # registration (15; check the 16 tooling in SUSE's guide)
snapper list | tail -5; findmnt -no FSTYPE /                   # snapshots; root file system
getenforce 2>/dev/null; aa-status --enabled 2>/dev/null; echo $?   # SELinux (16) or AppArmor (15)
```

## Which commands change state

| Changes no configuration (some contact servers or write caches) | Changes state, confirm first | Disruptive, get explicit approval |
|---|---|---|
| `zypper lr`, `zypper lp`, `zypper patch-check`, `zypper needs-rebooting`, `zypper ps -s`, `zypper se`, `snapper list`, `snapper status`, `snapper diff`, `btrfs filesystem usage /`, `btrfs device stats /`, `getenforce`, `sestatus`, `aa-status`, `firewall-cmd --list-all`, `supportconfig -h`; `zypper` commands may refresh repository metadata, which contacts the repository servers and writes the zypp cache; `SUSEConnect --status` contacts SCC or RMT and prints the registration code | `zypper patch`, `zypper update`, `zypper install`, `zypper addlock`, `snapper create`, `snapper delete`, `semanage fcontext`, `restorecon`, `setsebool -P`, `SUSEConnect -r <code>`, `firewall-cmd --permanent` | `snapper rollback`, `zypper dist-upgrade`, `zypper migration`, `run_migration`, `SUSEConnect --de-register`, `btrfs balance`, `btrfs check --repair`, `setenforce 0` as a fix, `selinux=0`, deleting snapshots by hand, removing a kernel |

`zypper patch` applies officially released patches and reports conflicts for vulnerable packages; `zypper update` installs newer versions, ignores problematic packages such as locked ones and does not report those conflicts (SUSE's software guide). `supportconfig` collects system data into an archive: review it before it leaves the host.

## Releases and support

Dates are from SUSE's lifecycle page, read on 2026-10-19. SUSE adds Long Term Service Pack Support (LTSS) after general support. The tables are the state on that date; check the page before quoting.

| Release | FCS | General support ends | LTSS ends |
|---|---|---|---|
| SLES 16.0 | 4 Nov 2025 | 30 Nov 2027 | 30 Nov 2030 |
| SLES 16.1 | Nov 2026 (planned) | 30 Nov 2028 | 30 Nov 2031 |
| SLES 16 (whole product) | | 30 Nov 2035 | 30 Nov 2038 |
| SLES 15 SP7 | 17 Jun 2025 | 31 Jul 2031 | 31 Jul 2034 (LTSS Core to Dec 2037) |
| SLES 15 SP6 | 26 Jun 2024 | 31 Dec 2025 (ended) | 31 Dec 2028 |
| SLES 15 SP5 | 20 Jun 2023 | 31 Dec 2024 (ended) | 31 Dec 2027 |
| SLES 15 SP4 | 21 Jun 2022 | 31 Dec 2023 (ended) | 31 Dec 2026 |
| SLES 15 (whole product) | | 31 Jul 2031 | 31 Jul 2037 |

- On 15, each service pack gets about 18 months of general support, so a host must follow the service packs; SP7 is the latest SUSE lists. Staying on an old SP without LTSS means no fixes. On 16, the first minors have two years of general support and three of LTS (the last listed minor, 16.6, has longer), and minors arrive each November.
- SUSE's lifecycle page also lists "SUSE Multi-Linux Support", described as replacing SUSE Linux Enterprise Server with Expanded Support; read SUSE's product page if you run mixed RHEL and SUSE estates.

## Registration and repositories

- On 15, register with `SUSEConnect` against SUSE Customer Center (SCC) or an RMT server (`SUSEConnect -r <regcode>`, `--url https://<rmt>` for RMT, `--status-text`, `--list-extensions`, `-p <product>` for a module, `--de-register`). Modules (Basesystem, Server Applications, Containers and so on) and extensions are enabled through registration; RMT replaces SMT from SLES 15. `SUSEConnect --status` and `--status-text` print the registration code: never paste their output into a ticket or chat.
- SLES 16 has **no modules and no separate pool and update channels**; minor releases (16.1, 16.2) use separate repositories. RMT must run on SLE 15 until 16.1 to serve 16 clients. SUSE's pages read for this skill do not describe the registration command for 16: follow the registration section of the current SLES 16 guide.
- `zypper lr -u` lists repositories and URLs; `zypper ref` refreshes; `zypper ps -s` lists processes that use deleted files after an update.

## Patching with zypper

- `zypper lp` (`list-patches`) lists needed patches (`--cve`, `--bugzilla`, `-g/--category`, `--severity` filter them). `zypper patch` installs them; `zypper patch --updatestack-only` patches the package manager first.
- Exit codes a script can use (zypper manual): `zypper patch-check` returns 100 when patches are available and 101 when security patches are available; `zypper needs-rebooting` returns 102 when a reboot is suggested (the flag comes from packages with `installhint(reboot-needed)` and the list in `/etc/zypp/needreboot`); 103 means the package manager itself was updated and the command must be run again; 106 means a repository was skipped because it failed to refresh; 107 means a package script failed. Codes below 100 are errors (for example 7, the zypper lock is held).
- Lock a package with `zypper addlock`; list locks with `zypper ll`. `zypper dist-upgrade` and `zypper migration` change the product version and are not routine patching.

## Btrfs and Snapper

- Btrfs is the default root file system on SLES; Snapper creates read-only snapshots: installation snapshots, pre/post pairs around zypper and YaST changes, and timeline snapshots (hourly where enabled; off for the root file system by default). Configuration is per subvolume in `/etc/snapper/configs/`; cleanup keeps the last ten important and ten regular numbered snapshots by default, with timeline limits set by `TIMELINE_*` variables.
- `snapper list`, `snapper create -d "<text>"`, `snapper status <a>..<b>`, `snapper diff`, `snapper undochange <a>..<b>`, `snapper delete`, `snapper cleanup number`. `snapper rollback [number]` creates two snapshots and sets the default subvolume (rollback is Btrfs-only and needs a properly configured system); you then reboot. Excluded subvolumes (such as `/home`, `/opt`, `/srv`, `/tmp`, `/var`, `/run`) are not reverted, and bootloader configuration is not rolled back.
- Snapshots live on the same file system as the data (SUSE advises roughly double the space for partitions with snapshots); copy-on-write means deleting files may not free space. Watch `btrfs filesystem usage /`, run `btrfs scrub` and `btrfs balance` only through the maintenance tooling or with care, and never run `btrfs check --repair` on a mounted file system.

## SLES 15: YaST, wicked and AppArmor

SLES 15 uses YaST for administration and installation (AutoYaST for automation), wicked for networking, and AppArmor by default for confinement (`aa-status`, `aa-complain`, `aa-logprof`); SELinux is available as an option on 15 SP7 (confirm in SUSE's SP7 documentation before relying on it). Python 3.6 remains the system interpreter on SP7, with newer versions in the Python 3 module. SP7's kernel is 6.4.

## SLES 16: what changed

From SUSE's comparison and release notes: YaST is removed (Agama installs, Cockpit administers, Ansible automates; some YaST functions have no Cockpit module yet); wicked is removed and NetworkManager is the only network stack (teaming through `teamd` is gone, use NetworkManager bonding); AppArmor is removed and SELinux is enforcing by default (reported permissive on SLES for SAP; summarised); the module concept is gone; kernel 6.12; GRUB 2.12; TPM-based full disk encryption on supported hardware; x86-64-v2 or higher is required; 32-bit execution is disabled by default (`ia32_emulation=1` re-enables it on x86-64 and 32-bit binary support is removed); SysV init scripts, NIS and `nscd` are removed (ISC DHCP is replaced by Kea); `/tmp` is a tmpfs; password-based root login over SSH is disabled by default (`openssh-server-config-rootlogin` re-enables it); the first installer-created user is in `wheel`. Transactional updates are not supported on SLES 16 (SUSE points to SLE Micro for that).

## SELinux on SLES 16

The same tools as the rest of the family: `getenforce`, `sestatus -v`, `ausearch -m AVC -ts recent`, `semanage fcontext` then `restorecon`, `semanage port`, `setsebool -P`, `semanage permissive -a <domain>`, `audit2allow` last. Persistent mode is `SELINUX=` in `/etc/selinux/config`; `setenforce` is temporary. SUSE says not to disable SELinux and documents `selinux=0` on the kernel command line for the exceptional case; to boot past a boot failure caused by SELinux, add `enforcing=0` once.

## Upgrading to 16

SUSE's upgrade guide says only SLES 15 SP7 is a supported source for 16.0 ("upgrades from other SLES versions are not supported"); the 16.0 release notes mention direct migration from SP6. Read both and confirm with SUSE before planning from SP6. The method is the distribution migration system: the host must be registered, patched (`zypper patch`), have `/etc` and key parts of `/var` and `/opt` backed up, run on a single partition (a separate `/home` is fine, a separate `/var` is not), have a key-based SSH login available (root password login is off in 16), and then install `suse-migration-sle16-activation` and reboot (on s390x, run `run_migration`). The system is offline during the upgrade. SUSE recommends fresh installation in most scenarios.

## Pitfalls

1. A host that is not registered or whose LTSS has lapsed, patched by habit, not by contract.
2. Quoting one lifecycle for "SLES 15" when each service pack has its own dates.
3. `zypper update` where `zypper patch` is wanted.
4. `snapper rollback` without knowing the excluded subvolumes, or without rebooting.
5. Snapshots on a nearly full Btrfs, or a Btrfs balance run at the wrong time.
6. Advice for AppArmor or YaST given for a SLES 16 host, or SELinux advice for a SLES 15 host that is still on AppArmor (check `getenforce` and `aa-status` first).
7. `setenforce 0` or `selinux=0` as a fix on 16.
8. Planning a 16 upgrade from a layout with a separate `/var`.
9. Relying on password root SSH on 16.
10. Running `supportconfig` and sending the archive without reading it.

## Red flags

- A support date given without SUSE's lifecycle page behind it.
- A registration code, SCC credentials or RMT token pasted into a command, ticket or script, including the output of `SUSEConnect --status`.
- A migration started without a backup, and without registration and patches current.
- `btrfs check --repair` on a mounted file system.

## References and scripts

- `references/architecture.md`: product structure, modules and registration on 15, 16's changes, Btrfs and Snapper, the HA extension, containers and transactional systems.
- `references/best-practices.md`: patching, snapshots, SELinux and AppArmor practice, upgrade checklist.
- `references/diagnostics.md`: zypper and repository problems, Btrfs, Snapper, SELinux denials, boot, supportconfig.
- `references/version-notes.md`: dated lifecycle table and what changed in 15 SP4 to SP7 and 16.0.
- `scripts/system-health.sh`, `update-state.sh`, `security-posture.sh`, `storage-and-snapshots.sh`: checks that change no configuration (`update-state.sh` contacts SCC or RMT and the repositories unless `ZYPPER_NO_REFRESH=1`, and never prints the registration code). Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings or an invalid setting (the message is on standard error).

The scripts are POSIX `sh` (`/bin/sh` is bash on SLES), change no configuration, and take thresholds from environment variables. A required tool that is missing or a command that fails is a warning; an optional component that is not installed is reported as information. Several checks need root; without it they warn that the check was not performed. The release-stage check uses a built-in table dated 2026-10-19 and says so when it is more than 180 days old. They pass `shellcheck -s sh` and were run against stub commands in an empty-result world, a throwing world, and healthy and unhealthy worlds, but not on a SLES host.

## Boundaries

- RHEL, Rocky, AlmaLinux: `rhel-family-ops`. Ubuntu: `ubuntu-ops`. Debian: `debian-ops`.
- Generic Linux operation: `linux-host-ops`; first-boot commissioning: `linux-host-bringup`.
- Containers: `podman-ops`, `docker-ops`, `container-security`; Kubernetes on SUSE (Rancher, RKE2): `rancher-ops`, `kubernetes-ops`.
- Registration codes and credentials: `secrets-hygiene`.

## Bottom line

Know the product version and service pack, keep the host registered and inside a supported phase, use `zypper patch` and Snapper's rollback with their limits understood, and remember that SLES 16 replaces YaST, wicked and AppArmor.
