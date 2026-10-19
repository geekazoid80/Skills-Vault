---
name: rhel-family-ops
description: "Use for administering Red Hat Enterprise Linux 8, 9 and 10 and its rebuilds Rocky Linux and AlmaLinux: the support lifecycle (full support, maintenance, Extended Life Cycle Premium), subscriptions and Simple Content Access, dnf security updates, history and dnf-automatic, Application Streams and the end of modules in 10, SELinux workflow, system-wide crypto policies and FIPS, firewalld, NetworkManager keyfiles, the x86-64-v3 baseline and cgroup v1 removal in 10, in-place upgrades with Leapp, ELevate and migrate2rocky, Rocky's security repository, Secure Boot certificate changes, and EPEL and CRB. Triggers include \"RHEL\", \"Red Hat Enterprise Linux\", \"RHEL 10\", \"RHEL 9\", \"Rocky Linux\", \"AlmaLinux\", \"dnf\", \"subscription-manager\", \"Simple Content Access\", \"rhc connect\", \"SELinux\", \"AVC denial\", \"audit2allow\", \"crypto-policies\", \"firewalld\", \"Leapp\", \"ELevate\", \"migrate2rocky\", \"x86-64-v3\", \"CentOS migration\", \"RHEL end of life\". NOT for Ubuntu or Debian (ubuntu-ops, debian-ops), NOT for SUSE (sles-ops), NOT for generic Linux operation such as systemd units, journalctl, LVM and backups (linux-host-ops), NOT for first-boot commissioning (linux-host-bringup), NOT for rootless Podman internals (podman-ops), NOT for choosing a distribution (operating-system-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# RHEL family operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: rhel-family-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Red Hat Enterprise Linux (RHEL) is built from Fedora through CentOS Stream. Rocky Linux and AlmaLinux are community distributions that rebuild or track RHEL without a subscription; they share RHEL's tooling (`dnf`, `rpm`, SELinux, `firewalld`, NetworkManager, `systemd`) and its major-release lifecycle, but not its support contract, subscription system or some defaults. This skill covers what is specific to the family; generic Linux work (systemd units, journalctl, LVM, backups, the apt and dnf basics) lives in `linux-host-ops`, and rootless Podman internals in `podman-ops`.

**Core principle:** identify the major release, the minor release and the distribution first, because defaults and removed features differ sharply between 8, 9 and 10, and because "supported" means something different on RHEL (a contract and a phase), on Rocky (a community project) and on AlmaLinux (a foundation).

> **Caveat on provenance.** The content was reshaped from a community upstream that carried version errors (for example `dnf5` shipped in RHEL 10, which Red Hat's documentation does not say) and was corrected against Red Hat's product life-cycle data and documentation (including the RHEL 10 considerations and release notes, the upgrade guides, the SELinux and DNF guides), AlmaLinux's and Rocky Linux's pages and release notes, and the DNF manual pages, read on 2026-10-19. The scripts are checked with `shellcheck` and stub commands only; they have not been run on an RHEL-family host.

## Step 0: establish what you are running

```sh
. /etc/os-release && echo "$PRETTY_NAME (ID=$ID, VERSION_ID=$VERSION_ID)"   # rhel, rocky or almalinux
uname -r; getenforce                                                       # kernel; SELinux mode
subscription-manager identity                                              # RHEL only: registered? (exit status 0 when registered)
dnf repolist                                                               # enabled repositories
update-crypto-policies --show                                              # DEFAULT, LEGACY, FUTURE or FIPS
```

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Disruptive, get explicit approval |
|---|---|---|
| `getenforce`, `sestatus`, `ausearch -m AVC -ts today`, `sealert -l "*"`, `dnf history list`, `dnf needs-restarting -r`, `firewall-cmd --list-all`, `nmcli connection show`, `update-crypto-policies --show`, `subscription-manager identity`, `chronyc tracking`, `systemctl --failed` | `dnf check-update` and `dnf updateinfo` (they contact the repositories and can refresh the dnf cache), `dnf upgrade`, `dnf install`, `setenforce 0`, `setsebool -P`, `semanage fcontext`, `restorecon -R`, `firewall-cmd --permanent`, `firewall-cmd --reload`, `nmcli connection modify`, `update-crypto-policies --set`, `subscription-manager register`, `rhc connect` | `leapp upgrade`, `migrate2rocky`, `almalinux-deploy`, SELinux disabled with `selinux=0` on the kernel command line, `dnf history undo` or `rollback`, `fips=1` changes, `update-crypto-policies --set LEGACY` on a production host, removing kernels, `fdisk`/`lvremove`, `reboot` of a host that is not yours |

`audit2allow` generates policy from denials mechanically; Red Hat's SELinux guide says it should not be the first fix. `dnf history undo` is not a supported way to downgrade RHEL system packages (RHEL 10 DNF guide).

## Releases and support

Dates are from Red Hat's product life-cycle data (the Customer Portal API behind `access.redhat.com/product-life-cycles`), read on 2026-10-19; Red Hat states that future phase dates are approximate. A minor release is supported for six months under a Standard subscription; longer coverage of a minor release needs Premium or Extended Life Cycle Premium (ELCP).

| Release | General availability | End of full support | End of maintenance support | Extended life cycle support (add-on) ends |
|---|---|---|---|---|
| RHEL 10 | 20 May 2025 | 31 May 2030 | 31 May 2035 | 31 May 2039 |
| RHEL 9 | 18 May 2022 | 31 May 2027 | 31 May 2032 | 31 May 2036 |
| RHEL 8 | 7 May 2019 | 31 May 2024 (ended) | 31 May 2029 | 31 May 2033 |

- Latest minors seen (Red Hat's release-dates page): RHEL 10.2 and 9.8 (19 May 2026) and 8.10 (the last 8 minor, 22 May 2024). Major-release dates in the table are from the life-cycle data; the release-dates page gives 17 May 2022 for 9.0. Full Support delivers minor releases; Maintenance Support delivers errata only. After maintenance the Extended Life Phase gives no fixes and no security updates.
- ELCP is the extended-support model from RHEL 9: six years from general availability for eligible even-numbered minors (.2, .4, .6, .8) and nine for the terminal .10 release; it replaces EUS, Enhanced EUS and ELS (for RHEL 8 only the terminal 8.10, from 1 June 2029). E4S continues for RHEL 8 and 9; ELCP replaces it for SAP from 10.6. Red Hat's policy page states security errata cover Critical, Important and Moderate CVEs with a CVSS score of 7 or higher (effective 1 April 2025), so not every CVE gets an RHSA.
- **AlmaLinux** states 10 has active support to 31 May 2030 and security support to 31 May 2035, 9 to 31 May 2027 and 31 May 2032, and each minor reaches end of life when the next minor is released. **Rocky Linux** tracks the RHEL minors (9.8 on 27 May and 10.2 on 28 May 2026); its pages read for this skill do not publish a separate lifecycle, so take the major-release dates from RHEL and confirm on Rocky's site.
- Treat a rebuild as supported by the project, not by Red Hat, and read each project's current compatibility statement (the rebuilds differ in how closely they follow RHEL).

## Subscriptions, registration and repositories

- **RHEL** is registered with `subscription-manager register` (an activation key and organisation ID are preferred to a username and password) or `rhc connect --activation-key=<key> --organization=<org id>` on RHEL 8.8 and later, which also enables Red Hat Lightspeed (the name the current registration guide uses for the Insights service). **Simple Content Access (SCA)** removes the need to attach a subscription to each system: content is available to any registered system in the organisation; on Satellite, repositories are disabled by default for a host with no subscription attached (Satellite procedure). `subscription-manager identity` shows registration; read the status text with care, because SCA changes what "status" reports.
- **Rocky and AlmaLinux** need no registration. Enable **CRB** (CodeReady Builder; named `powertools` on Rocky and Alma 8) for build dependencies and **EPEL** for extra packages, deliberately, following the EPEL documentation for your distribution and release: on RHEL the builder repository is enabled through `subscription-manager repos` and EPEL comes from the Fedora project's `epel-release` package, on Rocky and Alma `dnf install epel-release` is the usual route. EPEL packages are community-supported.
- `dnf repolist`, `dnf repoquery`, `dnf versionlock` (plugin) and `dnf history` are the daily tools. On RHEL 10 Red Hat's DNF guide still describes the `dnf` tool and does not mention DNF 5; RPM is 4.19.

## dnf and updates

- `dnf check-update` exits 100 when updates are available, 0 when none, 1 on error. `dnf updateinfo list --security` lists security advisories (one line each: advisory ID, type and severity such as `Important/Sec.`, and the package). `dnf upgrade --security` and `dnf upgrade-minimal --security` apply them.
- `dnf needs-restarting -r` exits 1 when a reboot is required; `-s` lists the systemd services that use updated files.
- `dnf history list|info|undo|rollback`: undo is not a supported way to downgrade RHEL system packages.
- **dnf-automatic** (`dnf-automatic-notifyonly.timer`, `-download.timer`, `-install.timer`) schedules updates; choose a mode on purpose.
- **Application Streams:** RHEL 8 and 9 deliver some software as modules (`dnf module list`, `enable`, `install nodejs:18`, `reset`); RHEL 10 has no modular Application Streams (Red Hat states it does not intend to provide any), and MariaDB, MySQL and PostgreSQL ship as RPM packages. Initial Application Stream versions can have a shorter life cycle than the release.

## SELinux

SELinux is enforcing by default. The workflow in Red Hat's guide is: `getenforce` and `sestatus`; find denials with `ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts today` (start `auditd` if nothing is found) or `sealert -l "*"`; fix file contexts with `semanage fcontext -a -t <type> "<path regex>"` then `restorecon -R -v <path>`; label ports with `semanage port -a -t <type> -p tcp <port>`; flip booleans with `setsebool -P`; only then consider a local module with `audit2allow`. `setenforce 0` is temporary and for debugging only. Persistent mode is in `/etc/selinux/config`; Red Hat documents disabling SELinux through the kernel command line (`selinux=0`, for example with `grubby --update-kernel ALL --args selinux=0`), not through the config file, and says not to do it except in specific cases. RHEL 10.2's policy treats `/var/opt` as equivalent to `/opt`, so custom rules for `/var/opt` may be ignored after an upgrade. Generic SELinux guidance stays in `linux-host-ops`.

## Crypto policies, FIPS and Secure Boot

- `update-crypto-policies --show` reports the system-wide policy (`DEFAULT`, `LEGACY`, `FUTURE`, `FIPS`); `--set <POLICY>` changes it. RHEL 10 tightened the defaults: SHA-1 signatures are no longer allowed in TLS under LEGACY, TLS ciphers that use RSA key exchange are not accepted under DEFAULT, and the FIPS policy does not permit AES HMAC-SHA1 Kerberos key derivation (an IdM interoperability point). `fips-mode-setup` is removed in 10: enable FIPS at installation with `fips=1` (Red Hat's security hardening guide for 10 treats installation as the supported route; read it before switching an installed host) and check the policy with `update-crypto-policies --show`.
- **Secure Boot:** Microsoft's 2011 third-party UEFI CA expires in 2026 and firmware updates that enrol the 2023 CAs and KEK arrive from mid-2026. Rocky and AlmaLinux ship dual-signed shims (2011 and 2023); do not enrol the new CAs or KEK by hand without a vendor-supported method (Rocky's June 2026 post). Check enrolled certificates with `mokutil --db`.

## Network, firewall and time

- NetworkManager is the network stack. **RHEL 10 does not support ifcfg profiles** (NetworkManager ignores them and they cannot be converted on 10), and the `network-scripts` package was removed in RHEL 9. Profiles are keyfiles in `/etc/NetworkManager/system-connections/`; run `nmcli connection reload` after editing one.
- `firewalld` is the host firewall; the default zone is `public`. Add rules with `--permanent` and `--reload`, or `--runtime-to-permanent`. The iptables direct rules are unmaintained: replace them with nftables. RHEL 10 removed firewalld's lockdown feature and moved the iptables kernel modules to `kernel-modules-extra`.
- Time is `chronyd`; `chronyc tracking` shows leap status and offset.

## RHEL 10 hardware and platform changes

x86-64-v3 is the minimum for AMD and Intel (AlmaLinux additionally ships an x86-64-v2 build; plan third-party software for v3 on RHEL 10). A commonly used check is `/lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v`, which marks the levels the CPU supports (a widespread glibc method, not from a Red Hat page). Kernel 6.12 with the EEVDF scheduler. cgroups v1 boot support is removed. The `runc` runtime and the CNI network stack are removed (use netavark). Python 3.12 is the system Python (8 has 3.6, 9 has 3.9). OpenSSH is 9.9 (9 has 8.7). `teamd` and `dhclient` are removed. Image mode (bootc) is available; most file systems are read-only in image mode.

## In-place upgrades and migrations

- **RHEL:** `leapp` (the Leapp utility) upgrades to the next major release only. Red Hat's 9-to-10 guide lists RHEL 9.6 (EUS) to 10.0 and 9.8 to 10.2; its 8-to-9 guide upgrades from RHEL 8.10 (the table lists the 9.6 and 9.8 targets by subscription). Requirements include registration with RHSM, the source release's BaseOS and AppStream repositories enabled, up to 4 GB free in `/var/lib/leapp`, and a backup; Leapp sets SELinux to permissive during the upgrade and you must set enforcing again afterwards.
- **Rocky and AlmaLinux:** AlmaLinux's ELevate (Leapp-based) upgrades AlmaLinux 8 to 9 and 9 to 10 and migrates CentOS 7; its page says Rocky Linux migration through ELevate is no longer supported. `migrate2rocky` converts CentOS (including CentOS Stream), AlmaLinux, RHEL and Oracle Linux 8 and 9 (not 10 at the time of reading) to Rocky in place, with no documented rollback. Rocky has no in-place major-version upgrade tool on the pages read (ELevate dropped Rocky): plan a fresh install and data migration for Rocky 8 to 9 and 9 to 10. Treat all of these as one-way and test on a clone.

## Rocky Linux specifics

Rocky offers an opt-in `security` repository (disabled by default) for urgent fixes ahead of upstream: `dnf --enablerepo=security update`. Its packages are versioned to be superseded by the next upstream release, carry no errata records (so `dnf update --security` does not show them), and are a temporary bridge.

## Pitfalls

1. Quoting a RHEL date without Red Hat's page, or assuming Rocky or Alma inherits Red Hat's support contract.
2. `dnf history undo` as a downgrade method on a production RHEL host.
3. Disabling SELinux through `/etc/selinux/config`, or `audit2allow` as the first fix.
4. Moving to RHEL 10 on hardware below x86-64-v3, or on a host still using cgroup v1.
5. Carrying ifcfg network profiles to RHEL 10.
6. Using `fips-mode-setup` on 10.
7. Leaving SELinux permissive after a Leapp upgrade.
8. `migrate2rocky` or ELevate on a host with no snapshot.
9. Enabling CRB or EPEL on a RHEL host without checking the support implications.
10. Expecting a Rocky `security`-repo fix to appear in `dnf update --security`.

## Red flags

- A support date, default or removal stated without a Red Hat, AlmaLinux or Rocky page behind it.
- A subscription activation key, Satellite password or registry token pasted into a command, ticket or script.
- `setenforce 0`, `selinux=0` or `LEGACY` crypto policy offered as the first fix.
- An in-place upgrade started without a backup and a rollback plan.

## References and scripts

- `references/architecture.md`: the lineage of RHEL, Rocky and Alma, repositories and streams, dnf and rpm, SELinux, crypto policies, networking, image mode.
- `references/best-practices.md`: patching, SELinux practice, firewall, subscription hygiene, upgrades and migrations.
- `references/diagnostics.md`: dnf and repository errors, SELinux denials, boot, network and time, Leapp reports.
- `references/version-notes.md`: dated lifecycle table and what changed in 8, 9 and 10, plus Rocky and Alma notes.
- `scripts/system-health.sh`, `update-state.sh`, `security-posture.sh`, `network-and-time.sh`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings or an invalid setting (the message is on standard error).

The scripts are POSIX `sh` (`/bin/sh` is bash on this family), do not change configuration, and take thresholds from environment variables. Their active probes are one name lookup and, with `PING_GATEWAY=1`, a gateway ping (`network-and-time.sh`), and `update-state.sh`, whose `dnf check-update` and `dnf updateinfo` calls contact the repositories and can refresh the dnf cache (and, on RHEL, the subscription-manager plugin). Set `ACCEPT_MAINTENANCE=1` on `system-health.sh` for hosts you knowingly keep in the maintenance phase (every RHEL 8 host is). A required tool that is missing or a command that fails is a warning; an optional component that is not installed is reported as information. Several checks need root; without it they warn that the check was not performed. The release-stage check uses a built-in table dated 2026-10-19 and says so when it is more than 180 days old. They pass `shellcheck -s sh` and were run against stub commands in an empty-result world, a throwing world, and healthy and unhealthy worlds, but not on an RHEL-family host.

## Boundaries

- Ubuntu: `ubuntu-ops`. Debian: `debian-ops`. SUSE: `sles-ops`.
- Generic Linux operation: `linux-host-ops`; first-boot commissioning: `linux-host-bringup`.
- Containers: `podman-ops`, `docker-ops`, `container-security`.
- Vulnerability handling and benchmarks: `vulnerability-management`, `compliance-benchmark-audit`.
- Subscription tokens and activation keys: `secrets-hygiene`.

## Bottom line

Know the major, the minor and the distribution; take dates from the vendor; fix SELinux with contexts and booleans, not by turning it off; check x86-64-v3 and cgroup v1 before RHEL 10; and treat in-place upgrades and migrations as one-way.
