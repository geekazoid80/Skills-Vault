# Debian best practices

Statements come from the Debian release notes and manual pages unless a line says it is a rule of thumb.

## Choosing and tracking a release

- Run stable. Plan the next upgrade before the Security Team stops: Debian's page puts bookworm's end of full support at 11 July 2026 and trixie's at 9 August 2028.
- Decide for each host what coverage it has: full support, LTS, paid ELTS, or none. Write the date and the page you took it from next to it.
- Do not run `testing` or `unstable` on production machines.

## Patching

- Enable `unattended-upgrades` for security updates, with `apt-listchanges` so changes are visible and a mail or log destination someone reads. Check that the daily timers run.
- Install `needrestart` and act on its output; a library update is not applied to a running daemon until it restarts. In batch mode (`needrestart -b`) it reports the kernel state in `NEEDRESTART-KSTA` (2 or 3 means a newer kernel is installed than the one running).
- Hold deliberately and review holds at each maintenance window (`apt-mark showhold`).
- Keep `debian-security-support` installed and run `check-support-status` after upgrades and when a release enters LTS. Rule of thumb: read it before an upgrade, because it names packages you should replace.
- `debsecan --suite <codename> --only-fixed --format simple` lists vulnerable packages that have a fix; fix by updating, then re-run. Give it the right suite, or its output is less informative.

## Backports and pinning

- Prefer stable's own packages. When you need a newer version, install it from `<codename>-backports` for that package only (`apt install -t <codename>-backports <package>`); backports are built for stable and receive fewer guarantees. The old stable's backports stop one year after the new stable release (`bookworm-backports` ended updates on 9 August 2026).
- Pin third-party repositories to a low priority and to specific packages so they cannot replace system packages. Prefer the vendor's repository for that vendor's product only.
- Before a release upgrade, remove the old release's `-backports` entries and add the new release's afterwards (release notes, 4.2.3).

## Release upgrades (bookworm to trixie as the worked example)

1. Read the release notes for the target release, chapters 4 and 5, and the "known severe bugs" list.
2. Bring the host to the latest point release of the current release. Confirm your sources still say `bookworm` (not `stable`). Remove obsolete and non-Debian packages you do not need; review leftover configuration files.
3. Make sure `/boot` has room (768 MB total and about 300 MB free if it is a separate partition). If the host is remote, update OpenSSH to 1:9.2p1-2+deb12u7 or later first (release notes 5.1.1).
4. Take a backup you have restored from. Work in `tmux` or `screen` with console access; the release notes warn about interrupted remote upgrades.
5. Change the sources to `trixie`, `trixie-updates` and `trixie-security`; add `non-free-firmware` if you use firmware from it; `apt update`; then check space with `apt -o APT::Get::Trivial-Only=true full-upgrade` (it can error until the minimal upgrade has run).
6. `apt upgrade --without-new-pkgs`, then `apt full-upgrade`; answer configuration-file prompts by looking at the differences, not by defaulting.
7. Before rebooting, if the machine has no out-of-band access, check whether interface names will change (`udevadm test-builtin net_setup_link /sys/class/net/<if>`) and pin names with `.link` files if needed.
8. Reboot. Afterwards `apt autoremove`, review `/etc/sysctl.conf` (no longer read; move settings to `/etc/sysctl.d/`), `/tmp` sizing (tmpfs, up to half of memory by default), the replacements for `last`, `lastb` and `lastlog` (`wtmpdb`, `lastlog2`, `lslogins`), and the OpenSSH changes (no DSA keys, no `~/.pam_environment`).

## Hardening (Debian-specific)

- Use `Signed-By` keyrings for third-party repositories; avoid `[trusted=yes]`.
- Keep AppArmor enforcing where profiles exist; use `aa-complain` to learn a profile and return it to enforce. `aa-status` reports state.
- Treat `non-free` and `contrib` as opt-in per host; enable `non-free-firmware` alone where you only need firmware.
- Do not put secrets in preseed files stored where others can read them (`secrets-hygiene`).

## Backups and recovery

Take the backup before the upgrade, test the restore, and keep the old kernel installed until the new one has booted. Debian's installer media (the point release image) is the rescue tool; keep a copy matching your release.
