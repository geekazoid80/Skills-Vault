---
name: operating-system-selection
description: "Use when choosing between operating systems or distributions, planning OS lifecycle and end-of-support work, comparing patching or package-management approaches across platforms, or when the OS is unclear. Triggers include \"which Linux distribution\", \"Windows Server or Linux\", \"RHEL vs Ubuntu vs Debian vs SLES\", \"Rocky vs Alma\", \"OS end of life planning\", \"EOL date\", \"Windows 10 end of support\", \"Group Policy vs MDM\", \"SELinux vs AppArmor\", \"patching cadence\", \"package management strategy\", \"which filesystem\", \"systemd vs launchd vs service control manager\", \"OS hardening approach\". Vendor-neutral comparison and lifecycle method; routes to the platform skill once the OS is known. NOT for day-to-day Windows Server (windows-server-ops) or Windows client (windows-client-ops) work, NOT for generic Linux host operation (linux-host-ops), NOT for choosing a hypervisor (virtualization-platform-selection), NOT for container runtimes (container-runtime-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Operating system selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: operating-system-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Operating systems differ less in what they can do than in who supports them, for how long, how they are patched and managed, and what the team already knows. A good choice starts from requirements; a good lifecycle plan starts from the vendor's own dates, fetched on the day.

**Core principle:** decide on requirements first (workload, vendor certification, support model, lifecycle length, management tooling, skills, licence cost), then compare. Version, support-date and licensing facts change, so cite the vendor page and the date for every figure.

## Pin the OS and version first

```bash
cat /etc/os-release ; uname -r        # Linux
sw_vers                                # macOS
```

```powershell
Get-ComputerInfo | Select-Object WindowsProductName, OsVersion, OsBuildNumber   # Windows
```

Capabilities, defaults and support status are version-bound. Never state an end-of-support date from memory.

## Router: once the OS is known

| Signal | Platform | Skill |
|---|---|---|
| Windows Server 2016 to 2025, Server Core, roles and features, Hotpatch | Windows Server | `windows-server-ops` |
| Windows 10 or 11, Intune, BitLocker, Windows Update for Business, ESU | Windows client | `windows-client-ops` |
| Hyper-V, Windows failover clustering, WSL | Windows features | no dedicated skill yet; Hyper-V comparison is in `virtualization-platform-selection` |
| macOS, MDM, Platform SSO | macOS | no dedicated skill yet |
| Ubuntu, Debian | Debian family | no dedicated skill yet; generic Linux in `linux-host-ops` and `linux-host-bringup` |
| RHEL, Rocky Linux, AlmaLinux | RHEL family | no dedicated skill yet; generic Linux in `linux-host-ops` |
| SLES, SUSE, Btrfs and Snapper | SUSE family | no dedicated skill yet; generic Linux in `linux-host-ops` |
| Any Linux host (systemd, journald, packages, LVM, backups) | Generic Linux | `linux-host-ops`, `linux-host-bringup` |
| Containers on any OS | Container runtimes | `container-runtime-selection` |

## Cross-platform fundamentals

### Service management

| Platform | System | Key operations |
|---|---|---|
| Linux (mainstream server distributions) | systemd | `systemctl` status, enable and edit, units, targets, `journalctl` |
| Windows | Service Control Manager | `Get-Service`, `sc.exe`, recovery options, scheduled tasks |
| macOS | launchd | `launchctl`, LaunchDaemons versus LaunchAgents |

### Packaging and patching

| Platform | Package system | Patch mechanism |
|---|---|---|
| RHEL, Rocky, AlmaLinux | rpm and dnf (modules, streams) | `dnf update`, vendor errata, Red Hat Satellite or equivalent |
| Ubuntu, Debian | deb and apt | unattended-upgrades; Ubuntu Pro for extended coverage; Landscape |
| SLES | rpm and zypper | patches versus updates, SUSE's management server product |
| Windows | MSI, MSIX, winget | Windows Update, WSUS, Windows Update for Business, Autopatch, Azure Update Manager |
| macOS | pkg, Homebrew (unmanaged) | `softwareupdate`, MDM-driven enforcement |

### Security frameworks

| Platform | Mandatory access control | Policy and configuration control |
|---|---|---|
| RHEL family, SLES | SELinux on the RHEL family; SLES 15 used AppArmor and SUSE documents SELinux as the default on SLES 16 | firewalld, OpenSCAP, vendor hardening guides |
| Ubuntu, Debian | AppArmor | `ufw` (Ubuntu's default front end, also available on Debian), CIS tooling |
| Windows | Integrity levels, App Control for Business, AppLocker | Group Policy, Intune, Defender stack |
| macOS | SIP, TCC, Gatekeeper | MDM configuration profiles |

Test-first is universal: permissive, complain, audit or report-only mode before enforcement, on every platform, with a rollback. Do not disable the framework to make a problem go away.

### Filesystems

xfs (default on the RHEL family, grows but does not shrink), ext4 (common on Debian and Ubuntu, offline shrink possible), Btrfs (default on SLES for the root; snapshots and rollback with Snapper), ZFS (available on Ubuntu and as an option on others), NTFS and ReFS on Windows (ReFS cannot be a boot volume), APFS on macOS. Choose by the operational features you actually need: snapshots, quotas, growth and shrink, integrity checksums.

## Selection method

1. **Workload and certification:** does the application vendor certify or support this OS (SAP and some databases pin to specific distributions; AD-centric estates lean towards Windows Server)?
2. **Support model:** vendor-paid support, community support, or a RHEL-compatible rebuild; what the contract covers (OS only, or also security patches after standard support).
3. **Lifecycle:** how many years of security updates, the cost of extended coverage, and the cadence of major releases.
4. **Management fit:** existing configuration management, patching tooling, directory integration, device management.
5. **Skills and runbooks:** a familiar OS you can patch on time beats a better one you cannot.
6. **Cost:** licences, subscriptions, support, and the cost of migrating later.

Rocky Linux and AlmaLinux are the no-subscription RHEL-compatible path; they differ in how closely they track RHEL and in who backs them, so read each project's current compatibility statement before committing.

## Lifecycle planning

Fetch the vendor's lifecycle page on the day, record the URL and date, and plan from the **end of security updates** for the exact edition.

| Vendor | Where the dates live | Note |
|---|---|---|
| Microsoft | Microsoft Lifecycle pages per product and edition | Windows Server follows the Fixed policy with mainstream and extended phases; Windows client follows the Modern policy per feature version (LTSC releases follow the Fixed policy), and Home and Pro end earlier than Enterprise and Education |
| Red Hat, SUSE | Vendor lifecycle pages | Paid extended coverage exists beyond standard phases |
| Canonical, Debian | Release and support pages | Ubuntu LTS and Debian each have separate standard and extended or LTS arrangements; read the current wording |
| Apple | Apple security releases page | Apple publishes no fixed per-version end dates; track which versions still receive security fixes |

Practical rules: start migration planning at least a year before the end of security updates; treat the extended phase as a bridge, not a destination; count dependencies (application support, hardware drivers, certificates, cipher support) in the plan; and re-check dates at each planning review because vendors have moved them.

## Patching strategy (any platform)

- Define rings (lab, pilot, wave 1, wave 2) and a cadence tied to the vendor's release rhythm; shorten it for actively exploited vulnerabilities.
- Know the restart and service-impact of each update class and schedule accordingly.
- Keep a tested rollback (snapshot, backup, uninstall path).
- Report patch compliance from the management system, not from a spot check.
- Vulnerability prioritisation lives in `vulnerability-management`; product-level patch tooling in `action1-patch-management`.

## Hardening approach

Start from a recognised baseline (CIS benchmark, vendor security baseline or STIG), apply in audit mode, measure, then enforce in rings. Record deviations with a reason and an owner. Benchmarks and audit evidence: `compliance-benchmark-audit`.

## Guardrails

- Never present destructive commands (`rm -rf`, `mkfs`, `diskpart clean`, registry deletions) without an explicit impact warning.
- Flag anything that needs a restart or service interruption.
- Hardening ships with a test-first mode and a rollback path.
- Read a shipped script before running it; do not assume it is read-only because it is in a skill.

## Pitfalls

1. Choosing on familiarity or licence price alone, ignoring vendor certification.
2. Planning from a remembered end-of-support date.
3. Running an operating system into the extended phase with no migration plan.
4. Disabling SELinux, AppArmor or the Windows firewall to fix an application.
5. Mixing patching tools that fight each other.
6. Treating a rebuild distribution as identical to the upstream product without checking its compatibility statement.
7. Picking a filesystem without checking whether you need to shrink or snapshot.

## Red flags

- A support date with no source and no date of retrieval.
- "It is the same on all versions" about a default setting.
- A migration with no rollback.
- A recommendation that does not mention the vendor certification of the main application.

## Boundaries

- Windows Server and client day-to-day: `windows-server-ops`, `windows-client-ops`.
- Generic Linux host operation: `linux-host-ops`, `linux-host-bringup`.
- Hypervisor choice and migration between platforms: `virtualization-platform-selection`.
- Containers: `container-runtime-selection`.
- Benchmarks, CVE handling and patch tooling: `compliance-benchmark-audit`, `vulnerability-management`, `action1-patch-management`.
- Directory services: `ad-ds`.
- Credentials: `secrets-hygiene`.

## Bottom line

Decide on requirements, fetch lifecycle dates on the day and cite them, test every hardening step in audit mode, keep a rollback, and route to the platform skill once the OS is known.
