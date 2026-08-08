---
name: linux-host-ops
description: Use when running ongoing operations on a Linux host (after the host is commissioned per linux-host-bringup). Triggers include "this systemd service keeps restarting", "the cron didn't fire", "the disk is full", "the package update broke X", "rotate the logs", "add a new sudoer", "extend the LVM volume", "set up a backup job", "upgrade the OS", "investigate this journalctl entry", "audit2allow this denial", "the host is slow", "what's eating CPU on this box". Sections cover systemd unit authoring (services, timers, restart policies), journalctl triage, cron vs systemd timer choice, package management discipline (apt and dnf side by side), log rotation, user / group / sudoers / SSH key management, disk / filesystem ops (df, du, LVM, fstab, UUID), SELinux / AppArmor primer (do NOT just disable), backup patterns (restic / borg / rsync with encryption), OS upgrade playbook with pre-upgrade snapshot and post-upgrade verification. Vendor-agnostic; covers Debian / Ubuntu and RHEL / Alma / Rocky family explicitly with both apt and dnf shown side by side per command. Sibling to linux-host-bringup (which covers commissioning); cross-references systematic-debugging, secrets-hygiene, bash-defensive, oncall-runbooks, plan-time-tooling, completion-gate.
metadata:
  version: 1.0.0
---

# Linux Host Ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: linux-host-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Day-2 operations on a commissioned Linux host. The bringup skill (`linux-host-bringup`) gets the host to a safe baseline; this skill keeps it healthy through the next year of operation. Both Debian / Ubuntu (apt) and RHEL / Alma / Rocky (dnf) are shown side by side per command.

**Core principle:** evidence before action; small reversible steps; backup before mutation. Verify with `completion-gate` Layer 3 before claiming a change is done.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the service estate, init system, change-control posture, and any platform-specific conventions before commanding the host. Only ask the user for information not already covered or specific to this task.

Before commanding the host, understand:

1. **Host and distro**
   - Distro family and version (LTS branch matters; some commands diverge across major versions)?
   - Init system (systemd is assumed; sysvinit / OpenRC needs different patterns)?
   - Role (web host, database host, build runner, jump box, others)?

2. **Change context**
   - Routine maintenance, post-incident remediation, or capacity tuning?
   - Maintenance window and rollback plan if a service is impacted?
   - Backups / snapshots in place before destructive operations?

3. **Tooling and access**
   - SSH path (direct, bastion, agent forwarding)?
   - Privilege escalation (sudo, doas, root login)?
   - Logs and telemetry surface (journalctl, rsyslog, remote log sink)?

---

## When to use

- A systemd service / timer is misbehaving (restart loop, missed schedule, env-var gap).
- A cron job didn't fire or fired with the wrong PATH / cwd / env.
- Disk is full or a filesystem needs resizing.
- A package update broke something or needs holding back.
- Logs are eating disk; logrotate config needs tuning.
- A user / group / sudoer needs adding, modifying, or auditing.
- SELinux or AppArmor denied something; need to fix the policy (NOT disable).
- A backup job needs setting up, or a restore drill is due.
- OS major-version upgrade is planned.
- A host is slow and you don't yet know which subsystem.

Do NOT use this skill for:

- Fresh-host commissioning (use `linux-host-bringup`).
- Application-level debugging (the host is fine; the app is the problem).
- Container orchestration (Kubernetes, etc.; out of scope).

## systemd unit authoring

A service unit for a long-running process:

```ini
# /etc/systemd/system/myservice.service
[Unit]
Description=My service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=myservice
Group=myservice
ExecStart=/usr/local/bin/myservice
Restart=on-failure
RestartSec=5s
EnvironmentFile=-/etc/myservice.env

[Install]
WantedBy=multi-user.target
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myservice.service
systemctl status myservice.service     # should be active (running)
```

A timer + companion service for a scheduled task:

```ini
# /etc/systemd/system/mytask.service
[Unit]
Description=My task

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mytask
```

```ini
# /etc/systemd/system/mytask.timer
[Unit]
Description=Run mytask hourly

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mytask.timer
systemctl list-timers --all | grep mytask
```

Key choices:

- `Type=simple` for long-running; `Type=oneshot` for tasks that exit.
- `Restart=on-failure` (not `always`) to avoid restart loops on bad config.
- `RestartSec=5s` minimum; lower can deadlock the unit-restart logic.
- `OnCalendar=` over `OnUnitActiveSec=` for human-readable schedules.
- `Persistent=true` on timers so a missed run during downtime fires on next boot.
- `RandomizedDelaySec=` for fleet-wide tasks (avoid thundering herd).

## journalctl triage

```bash
# Last 100 lines of one unit
journalctl -u myservice.service -n 100 --no-pager

# Since boot
journalctl -u myservice.service -b

# Time window
journalctl --since "1 hour ago" --until "now"
journalctl --since "2026-05-09 14:00" --until "2026-05-09 15:00"

# Priority (errors and worse)
journalctl -p err -b

# Grep
journalctl -u myservice.service --grep "connection refused"

# Follow
journalctl -u myservice.service -f

# By PID or by structured field
journalctl _PID=1234
journalctl _SYSTEMD_UNIT=myservice.service _COMM=python3
```

Useful priorities (low number = more severe): 0 emerg, 1 alert, 2 crit, 3 err, 4 warning, 5 notice, 6 info, 7 debug.

## cron vs systemd timer choice

Use systemd timers for almost everything new. Cron is fine for legacy and for one-line trivial schedules.

| Need | Pick |
|---|---|
| Tied to a service unit (run before / after some service) | systemd timer (uses `Unit=` and `After=`) |
| Need accurate "missed" handling on boot | systemd timer (`Persistent=true`) |
| Need randomised delay across fleet | systemd timer (`RandomizedDelaySec=`) |
| Need explicit user / group / env | systemd timer (cleaner) |
| Trivial one-liner under a shared crontab | cron (`@hourly /usr/local/bin/x`) |
| Per-user tasks under `crontab -e` | cron (still standard for personal jobs) |

Cron gotchas (the ones that bite):

- PATH is minimal (`/usr/bin:/bin`); set explicit PATH in the crontab or use absolute paths.
- Working directory is `$HOME`, not the script's own dir; `cd` first.
- Environment is empty; export what you need at the top.
- Output goes to mail; if no MTA, output is dropped silently. Redirect to a log: `>>/var/log/mytask.log 2>&1`.
- `MAILTO=""` at the top of crontab to suppress the silent mail attempts.

## Package management

### apt (Debian / Ubuntu)

```bash
# Update package index, then list upgradeable
sudo apt update
apt list --upgradable

# Upgrade everything (dist-upgrade keeps held packages held)
sudo apt full-upgrade

# Hold a package back from upgrades
sudo apt-mark hold mypackage
apt-mark showhold

# Unhold
sudo apt-mark unhold mypackage

# Remove (keep config)
sudo apt remove mypackage

# Purge (remove config too)
sudo apt purge mypackage

# Autoremove orphaned dependencies
sudo apt autoremove

# History
ls /var/log/apt/history.log*
cat /var/log/apt/history.log | grep "Install:"
```

### dnf (RHEL / Alma / Rocky)

```bash
# Update package metadata, then list updates
sudo dnf check-update

# Upgrade everything
sudo dnf upgrade

# Hold a package back (versionlock plugin)
sudo dnf install dnf-plugins-core   # provides versionlock
sudo dnf versionlock add mypackage
sudo dnf versionlock list

# Remove versionlock
sudo dnf versionlock delete mypackage

# Remove
sudo dnf remove mypackage

# Autoremove orphaned dependencies
sudo dnf autoremove

# History
sudo dnf history
sudo dnf history info <transaction-id>
sudo dnf history undo <transaction-id>     # rollback a transaction (when supported)
```

Cross-platform discipline:

- Always `sudo dnf check-update` / `sudo apt update` BEFORE upgrading. Stale metadata leads to "package not found" surprises.
- Hold the kernel and any pinned-version packages explicitly. A surprise kernel upgrade plus a reboot can lose access to a remote host.
- Audit installed packages periodically: `apt list --installed | wc -l` / `dnf list installed | wc -l`. Anomalous growth signals drift.
- The transaction log (`/var/log/apt/history.log` for apt; `dnf history` for dnf) is the audit trail. Read it after any "what changed?" question.

## Log rotation

Most distros ship `logrotate` running daily via cron or systemd timer. Per-package configs live under `/etc/logrotate.d/`.

A typical config:

```
# /etc/logrotate.d/myservice
/var/log/myservice/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        systemctl reload myservice.service > /dev/null 2>&1 || true
    endscript
}
```

Choices:

- `daily` / `weekly` / `monthly` for time-based; `size 100M` for size-based. Use `daily` plus `size` for both gates.
- `rotate N` keeps N old copies; tune to match the disk budget.
- `compress` reduces disk; `delaycompress` keeps the most recent rotation uncompressed (easier to grep).
- `postrotate` / `endscript` runs after rotation; usually a service reload so the service reopens its log file. The `|| true` keeps logrotate from failing on a stopped service.

Test a config without waiting for the next rotation:

```bash
sudo logrotate -d /etc/logrotate.d/myservice          # debug; no changes
sudo logrotate -f /etc/logrotate.d/myservice          # force; rotates now
```

## User / group / sudoers / SSH

### Users and groups

```bash
# Create a user with a home and bash shell (apt + dnf both)
sudo useradd -m -s /bin/bash alice

# Add to a group
sudo usermod -aG docker alice
groups alice                 # verify

# Set initial password (or skip; key-only access)
sudo passwd alice

# Lock account
sudo passwd -l alice
sudo passwd -u alice         # unlock
```

### sudoers

NEVER edit `/etc/sudoers` directly. Always use `visudo` (validates before saving).

```bash
sudo visudo                              # main file
sudo visudo -f /etc/sudoers.d/alice      # drop-in for a single user
```

Drop-in pattern (preferred over editing the main file):

```
# /etc/sudoers.d/alice
alice ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart myservice
```

Discipline:

- Drop-ins under `/etc/sudoers.d/` are easier to audit and easier to revert per user.
- `NOPASSWD:` is convenient but it's a credential. Limit to specific commands.
- Avoid `ALL=(ALL) ALL` for human users; prefer named commands.
- For service accounts, prefer systemd's `User=` over sudo entirely.

### SSH key rollout

```bash
# Add a new public key for an existing user
sudo -u alice mkdir -p /home/alice/.ssh
sudo -u alice tee -a /home/alice/.ssh/authorized_keys < ed25519.pub
sudo chmod 700 /home/alice/.ssh
sudo chmod 600 /home/alice/.ssh/authorized_keys
sudo chown -R alice:alice /home/alice/.ssh

# Audit existing keys
sudo cat /home/alice/.ssh/authorized_keys
sudo grep "" /home/*/.ssh/authorized_keys 2>/dev/null
```

Cross-reference: SSH keys ARE credentials. Per `secrets-hygiene`, never paste the private key into prose / commits / chat; manage via the secret store. Public keys are fine to track.

## Disk / filesystem

```bash
# Space
df -h
df -hi              # inodes
du -sh /var/log/*   # per-directory under a path
ncdu /              # interactive drill-down (install separately)

# What's eating disk?
sudo du -h --max-depth=1 / 2>/dev/null | sort -h
sudo find /var/log -type f -size +100M -exec ls -lh {} \;

# Mount table
mount | column -t
findmnt           # tree view
cat /etc/fstab    # canonical config

# Identify a disk by UUID (use UUID in fstab, NOT /dev/sdX which can change)
sudo blkid
lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINT
```

### LVM resize

```bash
# Extend a logical volume + resize the filesystem (ext4 / xfs)
sudo lvextend -l +100%FREE /dev/myvg/mylv
sudo resize2fs /dev/myvg/mylv     # ext4
sudo xfs_growfs /mountpoint        # xfs

# Verify
df -h /mountpoint
```

The order matters: extend the LV first, then grow the filesystem.

### fstab safety

- Always use UUID (or LABEL), never `/dev/sdX`. Disk reordering across reboots will mount the wrong filesystem.
- After editing fstab, test with `sudo mount -a` before rebooting. A bad fstab line that fails at boot drops to emergency console; a remote host then needs out-of-band access.

```bash
sudo blkid /dev/sda1                        # get UUID
echo 'UUID=... /mnt/data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a                               # test
findmnt /mnt/data                           # verify
```

The `nofail` option means the system still boots if the filesystem isn't there (handy for removable / network mounts).

## SELinux / AppArmor

Two different MAC frameworks; one or the other depending on distro:

- **SELinux:** RHEL / Alma / Rocky / Fedora.
- **AppArmor:** Debian / Ubuntu / SUSE.

The first instinct on a denial is "just disable". DO NOT. Disabling MAC removes a defensive layer that protects against compromised processes. Fix the policy instead.

### SELinux denial workflow

```bash
# Check the current mode
getenforce       # Enforcing | Permissive | Disabled

# Look for recent denials
sudo ausearch -m AVC -ts recent
sudo journalctl --since "1 hour ago" | grep -i "AVC\|SELinux"

# Generate a policy that allows the denied operation
sudo ausearch -m AVC -ts recent | audit2allow -m mypolicy

# Inspect the generated policy; only proceed if the policy makes sense
# (don't blindly allow; the denial may be flagging a real bug)

# Compile and load
sudo ausearch -m AVC -ts recent | audit2allow -M mypolicy
sudo semodule -i mypolicy.pp

# Verify the denial stops recurring
sudo ausearch -m AVC -ts recent
```

For label fixes (file in wrong context):

```bash
# What context does the file have? What should it have?
ls -Z /path/to/file
matchpathcon /path/to/file

# Restore the default for the path
sudo restorecon -v /path/to/file
sudo restorecon -Rv /path/to/dir
```

### AppArmor profile workflow

```bash
# Status
sudo aa-status

# Profile mode (enforce | complain | disable)
sudo aa-enforce /etc/apparmor.d/<profile>
sudo aa-complain /etc/apparmor.d/<profile>     # logs without blocking; use for debugging
sudo aa-disable /etc/apparmor.d/<profile>

# Generate / update a profile interactively from logged events
sudo aa-logprof
```

The principle is the same: complain mode for debugging, enforce mode for production. Generate profile updates from real denials (`aa-logprof`); don't disable.

## Backup patterns

Three good options; pick one and standardise per host class.

### restic (recommended for general use)

```bash
# Initialise a repo
restic init --repo /backup/restic

# Backup
restic -r /backup/restic backup /etc /home /var/lib/myservice

# List snapshots
restic -r /backup/restic snapshots

# Restore
restic -r /backup/restic restore latest --target /tmp/restore

# Prune old (keep last 30 daily, 12 weekly, 6 monthly)
restic -r /backup/restic forget --keep-daily 30 --keep-weekly 12 --keep-monthly 6 --prune
```

### borg

Similar shape to restic; deduplicating + encrypted. Choose between restic and borg based on team familiarity; both are good.

### rsync (simplest; no encryption / dedup built in)

```bash
# Mirror a directory to a backup target
rsync -aHAX --delete /etc/ /backup/etc/

# To a remote host
rsync -aHAX --delete /var/lib/myservice/ backup-host:/backup/myservice/
```

Rsync is fine for "snapshot a directory" use cases; for full-host backups with retention + dedup + encryption, prefer restic / borg.

### Encryption discipline

Backup destinations carry secrets. Per `secrets-hygiene`:

- restic and borg encrypt by default; the password lives in the secret store, not in the repo.
- rsync to a remote host: ensure the remote disk is encrypted at rest, OR pipe through GPG before transfer.
- Per-host backup credentials per `secrets-hygiene`; one credential per backup target, scoped to the smallest path needed.

### Restore drill cadence

A backup that has never been restored is not a backup; it is hope. Quarterly minimum:

1. Pick a backup at random.
2. Restore to a sandbox host (NOT prod).
3. Verify the restored data is usable (read a file, query a DB, etc.).
4. Document the restore time-to-recovery in the runbook.
5. Tear down the sandbox.

Cross-reference: this is the same cadence as `oncall-runbooks` recommends for incident-response readiness.

## OS upgrade playbook

Major-version upgrades are the highest-risk routine maintenance. Plan them as a chunk per `plan-time-tooling`'s `engineering:deploy-checklist` trigger.

### Pre-upgrade checklist

1. Snapshot the host (VM snapshot, LVM snapshot, or backup that can be restored quickly).
2. Read the upstream release notes and the deprecations list.
3. Identify packages that must NOT upgrade automatically (kernel, custom modules, vendor agents). Hold them.
4. Free disk space (`df -h`); upgrades cache packages.
5. Schedule a maintenance window with downtime tolerance.
6. Notify stakeholders.

### Upgrade sequence (apt)

```bash
sudo apt update
sudo apt full-upgrade                     # bring current major version fully up to date
sudo apt autoremove
sudo reboot                                # if kernel was updated

# Then the major upgrade (Debian / Ubuntu specific)
sudo do-release-upgrade                    # Ubuntu LTS to LTS
# OR
sudo apt edit-sources                      # manually flip release name
sudo apt update
sudo apt full-upgrade
sudo apt --purge autoremove
sudo reboot
```

### Upgrade sequence (dnf)

```bash
sudo dnf upgrade                           # full minor-version upgrade first
sudo dnf install -y dnf-plugin-system-upgrade
sudo dnf system-upgrade download --releasever=<NEW_VERSION>
sudo dnf system-upgrade reboot             # reboots into upgrade mode
```

### Post-upgrade verification

After the host comes back:

1. `uname -r` matches the expected new kernel.
2. `cat /etc/os-release` shows the new release name and version.
3. All previously-running services are running: `systemctl list-units --type=service --state=running`.
4. Any service the host serves is reachable from off-host (per the validation step in `linux-host-bringup`).
5. Hold list still respected: `apt-mark showhold` / `dnf versionlock list`.
6. Logs show no recurring errors: `journalctl -p err -b`.

Use `completion-gate` Layer 3 for the "upgrade succeeded" claim; do not declare done without running the verification.

### Rollback

If something is broken:

- VM snapshot: roll back the VM.
- LVM snapshot: revert the snapshot.
- No snapshot: the upgrade is one-way; restore from backup or fix forward. This is why the snapshot is mandatory pre-upgrade.

## Cross-references

- `linux-host-bringup`: sibling skill covering fresh-host commissioning. This skill picks up after that one finishes.
- `systematic-debugging`: when something on the host is broken and you don't yet know why; Phase 1 evidence-gathering at component boundaries.
- `secrets-hygiene`: SSH keys, sudoers credentials, backup encryption passwords, vendor agent secrets. All live in the gitignored secret store; never in tracked files.
- `bash-defensive`: any custom scripts called by systemd units or cron jobs follow strict mode + traps + ShellCheck.
- `oncall-runbooks`: when a host issue becomes an incident, the runbook structure applies. Restore-drill cadence in this skill mirrors the runbook-readiness cadence there.
- `plan-time-tooling`: OS upgrades and any production-mutating ops fire `engineering:deploy-checklist`. Run before the change, not after.
- `completion-gate` Layer 3: every risky change (LVM resize, fstab edit, OS upgrade, SELinux policy load) needs fresh verification before the "done" claim.

## Common mistakes

- Editing `/etc/fstab` without `sudo mount -a` test before reboot (host fails to boot; needs console access).
- `sudo dd` / `mkfs` on the wrong device because identification was by `/dev/sdX` instead of UUID.
- "Just disable SELinux" / "set AppArmor to disable" as a workaround for a real denial (defensive layer removed; root cause hidden).
- `Restart=always` on a service with bad config (restart loop; logs flood).
- cron job with implicit PATH / cwd assumption (works manually, fails from cron).
- Backup script with no encryption to a network target with no at-rest encryption (credentials and data leak via the backup channel).
- OS upgrade with no snapshot (no rollback path; one-way).
- Holding the kernel for so long that security patches accumulate (defeats the purpose of holds; review monthly).

## Red flags

- About to recommend disabling SELinux / AppArmor entirely (do NOT; fix the policy).
- About to edit `/etc/sudoers` directly without `visudo` (validation skipped; one bad line locks all sudo).
- About to write a systemd unit with `Restart=always` and no rate-limit (`StartLimitIntervalSec=` / `StartLimitBurst=`).
- About to run an LVM extend without a snapshot of the underlying volume.
- Backup config with the encryption password in the script itself.
- OS upgrade plan without the snapshot step.
- Hold list with no review cadence (security patches accumulate).
- Disk full and the script's first instinct is `rm -rf /var/log/` instead of investigating what filled it.

## Bottom line

Day-2 operations on a Linux host. systemd over cron for new schedules. journalctl with `-u` and `-b`. Both apt and dnf shown side by side. Drop-in sudoers under `/etc/sudoers.d/`. UUID in fstab. Fix SELinux / AppArmor policies, do NOT disable. restic / borg for backups; restore drill quarterly. OS upgrade always starts with a snapshot.
