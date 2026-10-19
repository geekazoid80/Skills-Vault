# SLES architecture reference

Sources: SUSE's lifecycle page, the SLES 15 SP7 and 16.0 release notes, the SLES 16 documentation (comparison with SLE 15, upgrading, SELinux basics, Snapper basics), and the zypper and snapper manual pages, read on 2026-10-19. A figure that rests on a summary made by a fetching tool is marked.

## Product structure

- **SLES 15** is one product with service packs (SP1 to SP7). Functionality is split into **modules** (included in the subscription, for example Basesystem, Server Applications, Containers, Python 3) and **extensions** (separately licensed, for example High Availability); modules are based on service packs and refreshed with each. Registration (SCC or RMT) enables the repositories.
- **SLES 16** has no modules and no separate pool and update channels; minor releases (16.0, 16.1, ...) use separate repositories and are installed with Agama.
- **SLES for SAP applications** is a separate product on the same lifecycle table; SELinux is reported permissive by default in SAP builds of 16 (summarised from the 16.0 notes).
- **SLE Micro** is the immutable, transactional product; `transactional-update` manages it. SLES 16 does not support transactional updates.
- **SUSE Multi-Linux Support** appears on SUSE's lifecycle page as the successor of "SLES with Expanded Support".

## Registration, SCC and RMT

SUSE Customer Center (SCC) is the subscription portal and repository source; the Repository Mirroring Tool (RMT) mirrors the repositories for air-gapped or controlled environments (it replaces SMT from SLES 15). On SLES 15 `SUSEConnect` registers the host, lists extensions (`--list-extensions`), enables a module (`-p <product>/<version>/<arch>`) and deregisters (`--de-register`). RMT in SLES 15 supports 16.0 clients; RMT cannot run on 16 until 16.1. Registration state is also needed for a distribution migration.

## Package management

`zypper` handles repositories, patches and packages. Patches are the unit SUSE ships fixes in (categories security, recommended, optional, feature); `zypper patch` installs them, `zypper update` installs newer package versions. `zypper search-packages` (15 SP7) searches all SLE repositories including disabled modules. `zypper ps` shows processes that use deleted files. `zypper needs-rebooting` and `patch-check` give script-friendly exit codes (see the skill). Locks are `zypper addlock`, `ll`, `removelock`; they are also recorded in `/etc/zypp/locks`. History is in `/var/log/zypp/history`. `rpm` queries the database. SLES 15 SP7 deprecates `pam_unix2`, drops Redis for Valkey, and deprecates XFS v4 (upstream support ends around September 2030, per the release notes; summarised).

## YaST, Agama and Cockpit

On 15, YaST (text and graphical, with `yast2 <module>` direct launches and AutoYaST for unattended installs) is the administration framework. On 16 it is removed: **Agama** installs (manually, with `agama config`, or with an AutoYaST profile loaded by Agama), **Cockpit** administers, and Ansible and SUSE Multi-Linux Manager automate. SUSE's comparison says some YaST modules have no Cockpit equivalent yet.

## Networking and services

SLES 15 uses wicked (ifcfg files under `/etc/sysconfig/network/`) or NetworkManager; SLES 16 uses NetworkManager only. `firewalld` is the firewall (an "Introduction to firewalld" guide exists for 16; the 16.0 release notes list a known `firewalld` slowness with many interfaces). SysV init scripts are removed on 16; every service needs a systemd unit. Time synchronisation has its own guide for NTP/NTS on 16.

## Btrfs and Snapper

Btrfs is the default root file system with subvolumes (`/.snapshots` holds Snapper snapshots, with `/home`, `/opt`, `/srv`, `/tmp`, `/var` and `/run` excluded from rollback). Snapper takes installation snapshots, administration pre/post pairs through `snapper-zypp-plugin`, and timeline snapshots, and cleans them by algorithm (number, timeline, empty-pre-post). `snapper rollback` is Btrfs-only. Snapshots are copy-on-write and share the file system with the data; enabling Snapper after installation yields a different subvolume layout from an installation that had it. File-system maintenance (`btrfs scrub`, `balance`, `trim`) is commonly scheduled by the `btrfsmaintenance` package on 15 (not confirmed on the pages read; check your release).

## Security frameworks

SLES 15: AppArmor by default (SELinux is an option on 15 SP7; confirm in SUSE's documentation) (profiles in `/etc/apparmor.d/`, `aa-status`, `aa-complain`, `aa-enforce`). SLES 16: SELinux in enforcing mode with the targeted policy (a `minimum` policy is also shipped), policies for more than 400 modules, managed with `semanage`, `semodule`, `restorecon`, `ausearch` and `audit2allow`. Both have `audit` and `sudo`; the 16 wheel group uses its own password for `sudo -i` (package `sudo-policy-wheel-auth-self`). Hardening guidance: SUSE's OpenSCAP guide for 16.

## High Availability extension

The SUSE Linux Enterprise High Availability extension (Pacemaker, Corosync, SBD fencing, Hawk) is a separate extension with its own lifecycle entries (16.0 and 16.1 are listed). Clustering needs fencing, tested fail-over and a quorum design; use SUSE's HA documentation for the release you run. The generic cluster concepts are in `linux-host-ops` and, for Windows, `windows-failover-clustering-ops`.

## Containers and Kubernetes

SUSE's container tooling follows the family (Podman, Buildah, Skopeo); the 16.0 notes state that `crun` is removed and `runc` is used. Rancher and RKE2 or K3s run on SLES (`rancher-ops`, `kubernetes-ops`).
