# SLES diagnostics reference

Changes no configuration unless marked (zypper commands may refresh repository metadata and write the zypp cache). Options were checked against the zypper and snapper manual pages (Tumbleweed versions on manpages.opensuse.org) and SUSE's SLES 16 guides on 2026-10-19; check `zypper help` on your service pack.

## zypper and repositories

| Symptom | Command | Notes |
|---|---|---|
| Are patches needed | `zypper patch-check` | Exit 100 patches, 101 security patches, 0 none |
| Which patches | `zypper lp`, `zypper lp --cve=<id>`, `zypper lp -g security` | `lp` is `list-patches` |
| Reboot needed | `zypper needs-rebooting` | Exit 102 when a reboot is suggested |
| Restart needed | `zypper ps -s` | `-ss` services only, `-sss` service names |
| Locks | `zypper ll` | `addlock` and `removelock` change state |
| Repositories | `zypper lr -u`, `zypper ref -f` | A skipped repository gives exit 106 |
| Repair dependencies | `zypper verify` | Changes state if you confirm |
| History | `/var/log/zypp/history` | |

Exit 7 means the zypper lock is held (another zypper or the package kit); wait or find it with `ps`. Exit 103 means the package manager itself was patched and the command must be run again. Exit 107 means a package script failed after unpacking; read the output.

## Registration (SLES 15)

`SUSEConnect --status-text`, `SUSEConnect --list-extensions` (the status output includes the registration code and the subscription status; redact before sharing). A host that is not registered has no update repositories; a system registered against an RMT that has not mirrored a module cannot enable it. Check the RMT's mirrored products and its logs before blaming the client.

## Btrfs and Snapper

```sh
findmnt -no FSTYPE,OPTIONS /; btrfs filesystem usage /
btrfs device stats /                 # error counters; any non-zero count is worth a look; empty output is itself a problem
btrfs scrub status /
snapper list; snapper status <a>..<b>; snapper diff <a>..<b>
```

"No space left on device" with free data blocks usually means metadata space is exhausted by snapshots; list and delete old snapshots with `snapper`, then see SUSE's Btrfs guidance before balancing. Snapper's cleanup is driven by systemd timers; `systemctl list-timers 'snapper*'` shows them; if `snapper-cleanup.timer` is not enabled, snapshots are never cleaned up. `snapper rollback` changes the default subvolume and needs a reboot.

## SELinux (SLES 16)

`getenforce`, `sestatus -v`, `ausearch -m AVC -ts recent` (logs are in `/var/log/audit/audit.log` with auditd, otherwise the journal), `ls -Z`, `ps -Z`. Fix with `semanage fcontext` and `restorecon`, `semanage port`, `setsebool -P`; review `audit2allow` output before installing a module. A host that will not boot because of SELinux can be started once with `enforcing=0`.

## AppArmor (SLES 15)

`aa-status`, `journalctl -k | grep -i apparmor`, `aa-complain <profile>` to learn, `aa-logprof` to update, `aa-enforce <profile>` to return.

## Boot, network and logs

`journalctl -b -p err`, `systemctl --failed`, `systemd-analyze blame`. On 16 network problems are NetworkManager problems (`nmcli connection show`, `nmcli device status`); on 15 check whether wicked or NetworkManager is active (`systemctl is-active wicked NetworkManager`). `supportconfig` collects a support archive (review it before sending: it contains host and configuration details). YaST logs on 15: `/var/log/YaST2/y2log`.

## Migration problems

The migration writes to its own log; an error before the upgrade starts reverts the system (per SUSE's guide). `run_migration` uses kexec, which does not work under Xen; if kexec panics, set the `soft_reboot` option. Custom udev rules that need drivers missing from the migration image can fail.
