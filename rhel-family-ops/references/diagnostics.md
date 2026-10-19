# RHEL family diagnostics reference

Read-only unless marked. Options were checked against the DNF manual page, the dnf-plugins-core `needs-restarting` page, Red Hat's SELinux, firewall and networking guides, and AlmaLinux and Rocky pages on 2026-10-19.

## Packages and repositories

| Symptom | Command | Notes |
|---|---|---|
| Are updates available | `dnf check-update` | Exit 100 yes, 0 no, 1 error; contacts the repositories and can refresh the cache |
| Security advisories | `dnf updateinfo list --security` | One line per advisory: ID, type and severity, package |
| Which repos are enabled | `dnf repolist --all` | Disabled repos are the first suspect for "package not found" |
| Why a package is held | `dnf versionlock list` | Needs the versionlock plugin |
| Transaction history | `dnf history list`, `dnf history info <id>` | `undo` and `rollback` change state |
| Package files and ownership | `rpm -ql <pkg>`, `rpm -qf /path`, `rpm -V <pkg>` | `rpm -V` flags changed files |
| Reboot or restarts needed | `dnf needs-restarting -r`, `dnf needs-restarting -s` | `-r` exits 1 when a reboot is required |
| Registration | `subscription-manager identity` | RHEL only; exit status 0 when registered |

A GPG key error means the repository's key is not imported or the repository changed key; do not set `gpgcheck=0` as a fix.

## SELinux

```sh
getenforce; sestatus
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts today
sealert -l "*"                      # needs setroubleshoot-server
ls -Z /path; ps -eZ | grep <name>   # labels
restorecon -Rvn /path               # -n: show what would change (no changes)
```

If `ausearch` finds nothing and `auditd` is not running, start it and repeat the action. A denial for a file in a non-standard location means the context is wrong: add an fcontext rule and run `restorecon`. A denial for a port means a port label is missing. After a Leapp upgrade, a boot failure caused by SELinux can be diagnosed by booting once with `enforcing=0`.

## Boot and kernel

`journalctl -b -1 -p err`, `systemd-analyze blame`, `dmesg --level=err,warn`. On RHEL 10 a host booted with cgroup v1 options is unsupported; remove `systemd.unified_cgroup_hierarchy=0` from the kernel command line. A Leapp upgrade that fails before the reboot leaves its log under `/var/log/leapp/`; the pre-upgrade report is `/var/log/leapp/leapp-report.txt`.

## Network and time

```sh
nmcli connection show --active; nmcli device status
ip -br addr; ip route show default
firewall-cmd --state; firewall-cmd --list-all
getent hosts example.com
chronyc tracking; chronyc sources -v
```

A profile that has no effect on RHEL 10 may be an ifcfg file, which is ignored. `firewall-cmd --state` reports `running` or an error when firewalld is not running. Time: leap status `Normal` and a small offset mean chrony is synchronised.

## Crypto and FIPS

`update-crypto-policies --show` shows the policy; applications that cannot connect after a move to RHEL 10 may be using SHA-1 signatures or RSA key exchange, which the DEFAULT policy no longer accepts. `cat /proc/sys/crypto/fips_enabled` shows whether FIPS mode is on.

## Rocky and Alma notes

`rpm -q rocky-release` or `almalinux-release` identify the distribution and minor. For a fix that Rocky shipped through its `security` repository, `rpm -q --changelog <package>` shows it; `dnf updateinfo` will not. After the 2026 Secure Boot certificate transition, a machine that fails to boot a newer shim may have firmware that only knows the 2011 certificate; check `mokutil --db` before changing keys.
