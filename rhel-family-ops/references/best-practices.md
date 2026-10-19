# RHEL family best practices

Statements come from Red Hat, AlmaLinux and Rocky Linux documentation unless a line says it is a rule of thumb.

## Choosing and tracking a release

- Run the newest major release your software supports; plan the next major jump before maintenance support ends (RHEL 8 maintenance support ends 31 May 2029).
- Pin your decision to a vendor page and a date. For a rebuild, record who supports it (the project, a vendor, nobody) and what happens if the project's policy changes.
- Check the hardware baseline before RHEL 10 (x86-64-v3) and the runtime baseline (cgroup v2 only).

## Subscriptions and repositories

- Register RHEL hosts with an activation key and organisation ID, not a personal username and password. Store the key in your secrets system (`secrets-hygiene`).
- Use Simple Content Access, and decide who may enable CRB and EPEL. Keep a per-host record of enabled repositories; a surprise third-party repository is the most common cause of a failed upgrade.
- For fleets, use Satellite (RHEL) or a mirror; stage updates in a test channel first.

## Patching

- `dnf check-update` (exit 100 means updates) and `dnf updateinfo list --security` for planning; `dnf upgrade --security` for security-only runs; `dnf upgrade-minimal --security` for the smallest change.
- Use `dnf needs-restarting -r` and `-s` after updates and act on them; kernel and `glibc` updates need a reboot.
- Use `dnf-automatic` in notify-only or download mode on servers unless you have tested unattended installs.
- Hold packages with `versionlock` deliberately and review holds at every maintenance window. Do not rely on `dnf history undo` to go back.
- Remember the errata policy: Red Hat issues security errata for Critical, Important and Moderate CVEs with CVSS 7 or higher (from 1 April 2025), so a lower-scored CVE may have no fix in a minor release.

## SELinux

- Leave it enforcing. For a new application, run it permissive for one domain only (`semanage permissive -a <domain>`) rather than the host, then return the domain to enforcing.
- Fix labels first (`semanage fcontext` then `restorecon`), ports second (`semanage port`), booleans third (`setsebool -P`), and a local module last, after reading what `audit2allow` generated.
- Do not disable SELinux through `/etc/selinux/config`; Red Hat documents `selinux=0` on the kernel command line for the rare case, and warns against it.
- After a Leapp upgrade, set the mode back to enforcing and relabel if the report says so.

## Crypto, firewall and network

- Keep the policy at DEFAULT. If an old client needs LEGACY, apply a sub-policy for that need and set a date to remove it. Record any change to the system-wide policy.
- Use zones and services in firewalld; replace direct rules with nftables before they are removed.
- Move ifcfg profiles to keyfiles before RHEL 10 (Red Hat's NetworkManager guide for 9 documents a migration command; confirm it for your release, because ifcfg files cannot be converted on 10).

## Upgrades and migrations

1. Read the target release's considerations and release notes and the upgrade guide.
2. Fully update the source release to its latest minor; take a snapshot or ReaR backup you have restored from; work in `tmux` or on a console.
3. Run the pre-upgrade assessment (`leapp preupgrade`), read the report, fix inhibitors, repeat until clean; do not override an inhibitor without understanding it.
4. Upgrade, reboot, set SELinux back to enforcing, remove old kernels and Leapp leftovers after verifying, and re-test applications and the firewall.
5. For ELevate or `migrate2rocky`, do the same on a clone first and expect no rollback.

## Secure Boot

Before the 2026 certificate transition reaches your hardware, inventory firmware versions, record the enrolled certificates (`mokutil --db`), and take firmware updates through your hardware vendor's tooling (`fwupd` where supported). Do not enrol keys by hand without a tested recovery path.
