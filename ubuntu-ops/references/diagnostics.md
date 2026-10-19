# Ubuntu diagnostics reference

Read-only unless marked. Options were checked against the Ubuntu 26.04 manual pages (`apt`, `apt-get`, `apt-mark`, `dpkg-query`, `needrestart`, `aa-status`, `ufw`, `netplan`, `pro`, `snap`, `chronyc`, `resolvectl`, `timedatectl`, `cloud-init`) on 2026-10-19.

## Packages

| Symptom | Command | Notes |
|---|---|---|
| Interrupted install | `sudo dpkg --configure -a` then `sudo apt --fix-broken install` | Changes state; do both, in that order |
| Which packages are broken | `dpkg --audit` | Prints nothing when healthy |
| Package state letters | `dpkg -l` and read the first column | `ii` installed, `rc` removed with configuration left, `iF` half-configured, `iU` unpacked |
| Which version would install | `apt-cache policy <package>` | Shows pins and pockets |
| Who owns a file | `dpkg -S /path` | Installed files only; `apt-file search` needs the `apt-file` package |
| What would an upgrade do | `apt-get -s dist-upgrade` | Simulation; no root needed |
| Held packages | `apt-mark showhold` | |
| Why is an update held back | `apt-cache policy <package>` and the phased-update note in `apt-get -s` output | Phased updates reach a fraction of hosts first |
| Lock held | `sudo lsof /var/lib/dpkg/lock-frontend` | Often `unattended-upgrade` running; wait rather than delete the lock |
| History | `apt history-list` (APT 3, 25.10 and later) or `/var/log/apt/history.log` | `history-undo` changes state |
| Third-party sources | `grep -r -e '^Types' -e '^URIs' -e '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/` | Check each has `Signed-By` |

A signature error naming a key means the repository's key is missing from `/etc/apt/keyrings/` or the source has no `Signed-By`. Do not reach for `apt-key`; it is removed in the APT 3 series.

## snap

`snap list --all` (disabled lines are old revisions), `snap changes` then `snap tasks <id>`, `snap logs <name>`, `snap connections <name>`, `snap info <name>`, `snap refresh --list`, `snap refresh --time` (timer and last/next refresh). `sudo snap set system refresh.retain=2` limits kept revisions (changes state). A snap that will not start often has a missing interface connection or an AppArmor denial.

## Networking and name resolution

```sh
netplan get                      # merged YAML; fails on a syntax error
netplan status                   # runtime state, per interface
sudo netplan try                 # apply with rollback (changes state)
ip -br addr; ip route show default
resolvectl status                # per-link DNS servers, search domains, DNSSEC
resolvectl query www.example.com # which server answered, and via which link
getent hosts www.example.com     # what libc applications see
cloud-init status --long         # extended_status shows degraded; exit code 2 means recoverable errors
```

If `getent` works but `resolvectl query` does not (or the reverse), the application and the stub resolver disagree: check `/etc/nsswitch.conf` and `/etc/resolv.conf` (normally a link to the stub at 127.0.0.53). If Netplan keeps reverting after a reboot, look for `50-cloud-init.yaml` being regenerated.

## Time

On 26.04 new installs use chrony: `chronyc tracking` (leap status, offset), `chronyc sources -v`, `chronyc sourcestats`. `chronyc makestep` steps the clock and changes state. On 24.04 and 22.04 the default is `systemd-timesyncd`: `timedatectl timesync-status`, and `timedatectl show -p NTPSynchronized`. Do not run both clients. If a host moved from timesyncd to chrony, confirm `systemd-timesyncd` is no longer active.

## AppArmor

```sh
sudo aa-status                          # modes and counts
aa-status --enabled; echo $?            # 0 when AppArmor is enabled
sudo journalctl -k --since '1 hour ago' | grep -i 'apparmor="DENIED"'
sudo aa-complain /etc/apparmor.d/<profile>   # learn (changes state)
sudo aa-logprof                         # update from the log (changes state)
sysctl kernel.apparmor_restrict_unprivileged_userns
```

A denial with `operation="userns_create"` points at the user namespace restriction: give the program a profile with the `userns` permission (see the 24.04 release notes) rather than disabling the restriction host-wide. A snap denial names the snap's profile (`snap.<name>.<app>`).

## Boot, kernel and initramfs

`journalctl -b -1 -p err` for the previous boot, `systemd-analyze blame`, `systemd-analyze critical-chain`. On 26.04 the initramfs generator is dracut: `lsinitrd` inspects an image, `dracut --force` rebuilds one (changes state), and `rd.debug` goes on the kernel command line; on earlier releases it is `update-initramfs -u` and `lsinitramfs`. A machine that boots to the initramfs prompt after an update usually has a full `/boot` or an initramfs built without the storage driver; check `df -h /boot`, remove superseded kernels with `apt autoremove` (changes state), and rebuild. Kernel crash dumps are enabled by default on 26.04 (`/var/crash`).

## Pro, Livepatch and updates

`pro status` (entitled and enabled services), `pro security-status` (coverage by origin), `pro api u.pro.status.is_attached.v1` (contract status and remaining days), `pro api u.unattended_upgrades.status.v1` (is the unattended job running, and why not), `canonical-livepatch status --verbose` (when Livepatch is enabled). `pro collect-logs` writes a tarball for a support case; review it before sending because it contains host details.

## Services and logs

`systemctl --failed`, `systemctl status <unit>`, `journalctl -u <unit> -b`, `journalctl -p err -b`, `journalctl --disk-usage`. For unattended-upgrades: `/var/log/unattended-upgrades/unattended-upgrades.log` and `-dpkg.log`. For crashes: `ls /var/crash`, `apport-cli` or `coredumpctl` if `systemd-coredump` is installed. `sudo ubuntu-bug` and `pro collect-logs` collect data that may include hostnames and package lists.

## Upgrades that stop

`do-release-upgrade` logs to `/var/log/dist-upgrade/`. It refuses while the system has pending updates, phased updates not yet installed, a pending reboot, or (for 26.04) cgroup v1 active. Disable or remove the offending third-party sources, finish the updates, reboot, and run it again; do not edit the upgrader's tables.
