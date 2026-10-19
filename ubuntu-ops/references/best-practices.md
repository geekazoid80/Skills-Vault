# Ubuntu best practices

Statements come from Canonical's documentation and the Ubuntu manual pages unless a line says it is a rule of thumb.

## Choosing and keeping a release

- Run an LTS for servers. Interim releases are supported for nine months and exist to preview the next LTS.
- Plan the next LTS upgrade a year before standard support ends. Upgrade one LTS at a time; Canonical's guide says you cannot skip one.
- A host past standard support is not patched unless it is attached to Ubuntu Pro (`pro status`). Free personal use covers five machines; organisations need a subscription.
- Pin your decision to a Canonical page and a date, not to a remembered table.

## Patching

- Security updates only is the default for unattended-upgrades. Check that it runs: `pro api u.unattended_upgrades.status.v1` (Pro client 27.14 and later) reports whether the timer and configuration are active, or read `apt-config dump APT::Periodic` and `/var/log/unattended-upgrades/`.
- Keep `needrestart` installed. On 24.04 and later it restarts services affected by a library upgrade automatically; exclude one that must not restart through `override_rc` in a snippet under `/etc/needrestart/conf.d/` (or `needrestart.conf`).
- A new kernel needs a reboot unless Livepatch covers the CVE. `/run/reboot-required` and `needrestart -b` (`NEEDRESTART-KSTA` of 2 or 3) tell you; `pro api u.pro.security.status.reboot_required.v1` also reports `yes-kernel-livepatches-applied` when the reboot can wait for a maintenance window.
- Hold deliberately: `apt-mark hold <package>`, listed by `apt-mark showhold`. Review holds at every maintenance window; a forgotten hold blocks a release upgrade.
- Stage snap refreshes: `snap set system refresh.timer=...` for a window, `snap refresh --hold=48h <snap>` for a time-limited deferral (a hold with no duration is indefinite). Do not disable refreshes altogether.
- Phased updates may show as upgradable but not install; rerunning later is normal.
- Reboots: `Unattended-Upgrade::Automatic-Reboot`, `Automatic-Reboot-WithUsers` and `Automatic-Reboot-Time` control whether and when unattended-upgrades reboots the host (default: no reboot). Decide this on purpose for hosts that run kernel updates.

## Ubuntu Pro, Livepatch and compliance

- Attach with an attach configuration file or the cloud's auto-attach rather than typing a token on a shared terminal; store the token in your secrets system (`secrets-hygiene`).
- Enable `esm-infra` and `esm-apps` on any release past standard support or where `universe` packages matter; enable `livepatch` where a reboot is expensive.
- `usg` audits against CIS and DISA STIG profiles (CIS profile names are `cis_level1_server`, `cis_level2_server`, `cis_level1_workstation` and `cis_level2_workstation`). Install it first (`sudo pro enable usg`, then `sudo apt install usg`; per the `pro` manual page Livepatch cannot be enabled on a FIPS system, and `fips` gives no security patches, so use `fips-updates`). Audit first (`sudo usg audit cis_level1_server`), review the report, then `sudo usg fix <profile>` in a change window; some rules change SSH, PAM and mounts.
- `pro security-status` summarises how many installed packages are covered by standard support, ESM, third-party sources or no source.

## Firewall

- `ufw` is off by default. Set defaults first (`ufw default deny incoming`, `ufw default allow outgoing`), allow SSH from management networks, then `ufw enable`. Use `ufw limit ssh` to rate-limit.
- Container engines that manage firewall rules directly can publish ports around UFW. Read the engine's firewall page (Docker documents this for UFW) and test from another host; do not assume a UFW deny covers a published container port.
- Keep one firewall manager. Do not mix UFW with hand-written nftables or firewalld on the same host.

## AppArmor

- Leave AppArmor enforcing. To learn a new profile, put only that profile in complain mode, exercise the application, then update it from the log with `aa-logprof` and return it to enforce.
- Customise through `/etc/apparmor.d/local/` rather than editing a packaged profile, so package updates do not overwrite your change.
- For software that builds its own sandbox with unprivileged user namespaces (browsers, some container tools), add a profile that grants `userns` instead of setting `kernel.apparmor_restrict_unprivileged_userns=0` for the host.
- Review profiles in complain mode on production hosts; a profile left in complain mode protects nothing.

## Networking and time

- Make remote changes with `netplan try`. Keep a console route (hypervisor, BMC or serial) for anything that can change the management interface.
- One owner for network configuration: Netplan, or cloud-init that writes Netplan, not both editing the same file.
- Use one time client. On 26.04 that is chrony for new installations; if you upgrade a host that used `systemd-timesyncd`, follow Canonical's migration (`apt-mark auto systemd-timesyncd`, `apt install chrony`) and avoid listing the Ubuntu pool servers twice. Check with `chronyc tracking` (leap status Normal, offset small).

## Backups and recovery

- Take a backup and test a restore before a release upgrade. Snapshots (LVM, ZFS or the hypervisor's) are not a backup if they live on the same storage.
- Keep the previous kernel until the new one has booted. Do not remove kernels by hand while the host depends on one of them; use `apt autoremove` after a successful reboot.
- Record the output of `pro status`, `apt-mark showhold`, `dpkg -l` and the contents of `/etc/apt/sources.list.d/` before a release upgrade.

## Release upgrades

- Fully update, then reboot if needed (`/run/reboot-required`), then free several gigabytes, then run `do-release-upgrade` inside `tmux` or `screen` (or on a console) so a dropped session does not stop it.
- Expect third-party repositories and PPAs to be disabled; re-enable them only after checking they publish packages for the new series.
- On 26.04 upgrade paths, check cgroup version first: systemd 259 does not support cgroup v1, and Canonical states that cgroup v1 installations are not allowed to upgrade.
- `Prompt=lts` in `/etc/update-manager/release-upgrades` offers only the next LTS; an LTS-to-LTS offer appears after the first point release unless you force it with `-d`.
- Read the release notes' "Known issues" page for the target release before you start.

## Moving to 26.04 defaults

- Scripts that call `apt-key` must move to keyrings with `Signed-By`.
- The release notes name `cp`, `mv` and `rm` as still GNU; check other tools if you rely on GNU-only options and read Ubuntu Server's utility-replacement documentation for the exact list; the `gnu` prefix runs the GNU version (for example `gnuls`).
- Scripts that call `sudo` plugins or `sudo-ldap` need review: `sudo-rs` is the default and `sudo-ldap` is removed.
- Agents and exporters that read cgroup v1 files need updating.
- Check cloud instance families before choosing a 26.04 image: the `amd64v3` build excludes older instance families (the release notes list them).
