# SLES best practices

Statements come from SUSE documentation and manual pages unless a line says it is a rule of thumb.

## Choosing and tracking a release

- Decide per host: which service pack or minor, and who patches it after general support ends (LTSS, or an upgrade). A table row from SUSE's lifecycle page with its date belongs next to each host.
- On 15, move to the next service pack inside its general-support window; SP6 general support ended on 31 December 2025 and SP5's on 31 December 2024.
- For new builds, prefer SLES 16 unless software or tooling still needs 15 (YaST, wicked, AppArmor, modules, transactional systems on Micro).

## Registration and repositories

- Register every host (SCC or RMT) before patching; keep RMT or SCC credentials in your secrets system (`secrets-hygiene`). Use an activation approach that does not leave registration codes in shell history or tickets.
- Keep repositories to those SUSE or your RMT provides; third-party repositories go through a separate, tested path. Review `zypper lr -u` at each maintenance window.

## Patching

- Use `zypper patch` for routine patching and `zypper lp` to plan it; apply security patches first (`zypper patch --category security`), then reboot if `zypper needs-rebooting` returns 102.
- After a patch run, `zypper ps -s` lists services and processes that need a restart.
- Treat `zypper update` as a package-level tool; `zypper dist-upgrade` and `zypper migration` change the product version.
- Snapshot-aware patching: Snapper takes pre/post snapshots around zypper transactions; keep enough free space for them.

## Snapshots and Btrfs

- Plan the layout before installation (Snapper after installation changes the subvolume layout). Give snapshot-bearing partitions about twice the normal space (SUSE's rule of thumb).
- Keep the cleanup algorithms on (the `snapper-cleanup.timer` unit must be enabled; the number-based limits are per configuration); check `snapper list` and `btrfs filesystem usage /` regularly; investigate when metadata space runs out before data space.
- Before `snapper rollback`, read which subvolumes it excludes and decide what to do about data in them; reboot afterwards.
- Do not run `btrfs check --repair` on a mounted file system; do not delete snapshot subvolumes with plain `rm`.

## Security

- On 15, keep AppArmor (or SELinux, where you have chosen it on SP7) enforcing; use complain mode only to learn a profile. On 16, keep SELinux enforcing; fix file contexts, ports and booleans before generating a local module; use `semanage permissive -a <domain>` for one domain, not the host. Do not disable SELinux except on the kernel command line for a specific case (`selinux=0`), as SUSE documents.
- On 16, root password login over SSH is off by default; use keys and the `wheel` group.
- `firewalld` is the firewall: add rules with `--permanent` and `--reload`.

## Upgrades

1. Read SUSE's current upgrade guide for the target (on 16: only 15 SP7 is a supported source per the guide; the release notes mention SP6, so confirm).
2. Register the host, apply all patches, back up `/etc` and key parts of `/var` and `/opt`, and confirm key-based SSH access.
3. Check the layout: a single partition for the operating system (a separate `/home` is fine; a separate `/var` is not supported by the 16 migration).
4. Install the activation package, reboot into the migration image, expect downtime; review orphaned packages and `*.rpmnew` and `*.rpmsave` files afterwards.
5. SUSE recommends fresh installation in most cases; weigh that against the migration for stateful hosts.
