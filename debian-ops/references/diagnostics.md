# Debian diagnostics reference

Read-only unless marked. Options were checked against the Debian 13 manual pages (`apt`, `apt-get`, `apt-mark`, `apt-config`, `apt-secure`, `sources.list`, `debsecan`, `check-support-status`, `needrestart`, `unattended-upgrade`, `apt-listchanges`) on 2026-10-19.

## Packages

| Symptom | Command | Notes |
|---|---|---|
| Interrupted install | `dpkg --configure -a` then `apt --fix-broken install` | Changes state; in that order |
| Broken or half-configured packages | `dpkg --audit` | Prints nothing when healthy |
| Which version would install | `apt-cache policy <package>` | Shows pins and suites |
| What an upgrade would do | `apt-get -s full-upgrade` | Simulation; a non-root run may not read all apt configuration, which can distort it (`apt-get(8)`) |
| Held packages | `apt-mark showhold` | |
| Packages not from Debian | `apt list '?narrow(?installed, ?not(?origin(Debian)))'` | From the 13 release notes; includes packages Debian once provided |
| Who owns a file | `dpkg -S /path` | Installed files only |
| Effective apt configuration | `apt-config dump` | Includes `APT::Periodic` settings |

## apt errors

- **"The repository ... is not signed" or `NO_PUBKEY`:** the key is missing or the source has no `Signed-By`. Add the key under `/etc/apt/keyrings/` and reference it; see `apt-secure(8)`.
- **"Release file ... is not valid yet" or expired:** the clock is wrong; fix time before anything else.
- **A source still names the old codename after an upgrade, or `stable`:** check every file in `/etc/apt/sources.list.d/`; a third-party `.list` file is the usual culprit.
- **An index that does not seem to update:** the Debian 13 release notes list, among known severe bugs, that `apt update` can silently leave old index data (Debian bug 1078608). Check the dates of the files under `/var/lib/apt/lists/`, and retry or use another mirror.
- **Packages "kept back":** a hold, a pin, a changed dependency set or a new dependency. `apt-get -s full-upgrade` shows what a full upgrade would do; `apt full-upgrade` is the command that can add and remove packages.

## Boot and kernel

`journalctl -b -1 -p err` for the previous boot; `systemd-analyze blame`. A host that fails to boot after a kernel update may have a full `/boot` (check `df -h /boot`; the release notes recommend 768 MB for a separate partition) or an initramfs built without the storage driver; rebuild the initramfs of the affected kernel after freeing space (`update-initramfs -u -k <version>`; this changes state, and `-k all` rewrites every kernel's initramfs, including the fallbacks you may need). After a reboot into trixie, `systemctl is-system-running --wait` and `systemctl --failed` show the state.

## Network and time

```sh
ip -br addr; ip route show default
resolvectl status                # when systemd-resolved is in use
getent hosts example.com         # what libc applications see
timedatectl                      # clock, time zone, NTP synchronisation
```

A system that changed interface names after the upgrade (the release notes warn about the i40e driver and ACPI `_SUN` objects) loses its network configuration for the old name; boot from the console, rename in the configuration or pin names with `systemd.link` files. `ping` failing as an ordinary user on 13 means `net.ipv4.ping_group_range` does not include the user's group (normally set by `linux-sysctl-defaults`).

## Security tooling

`check-support-status` reports packages with limited or ended support (nothing printed means nothing to report; treat it as an inference from the manual page, not a documented exit code). `debsecan --suite <codename> --only-fixed` needs network access to fetch its data. `needrestart -b` prints `NEEDRESTART-KSTA`, `NEEDRESTART-UCSTA` and `NEEDRESTART-SVC` lines. `aa-status --enabled` and `--profiled` give script-friendly AppArmor facts. `/var/log/unattended-upgrades/` holds the unattended-upgrade logs.

## Logs and accounting after the move to 13

`journalctl` is the main log source. `lslogins` shows when accounts last logged in; `lslogins --failed` is the `lastb` replacement. Install `wtmpdb` (with `libpam-wtmpdb`) and `lastlog2` (with `libpam-lastlog2`) if you want the old commands' information; old `lastlog` and `btmp` files cannot be read after the change and can be deleted.
