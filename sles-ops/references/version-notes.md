# SLES version notes

Dated 2026-10-19. Sources: SUSE's lifecycle page, the SLES 15 SP7 and 16.0 release notes, and the SLES 16 documentation. Some details rest on summaries of SUSE pages made by a fetching tool and are marked "summarised". Re-check the lifecycle page before quoting a date.

## Lifecycle snapshot

| Release | FCS | General support ends | LTSS ends | Notes |
|---|---|---|---|---|
| 16.0 | 4 Nov 2025 | 30 Nov 2027 | 30 Nov 2030 | First 16 minor |
| 16.1 | Nov 2026 | 30 Nov 2028 | 30 Nov 2031 | Planned |
| 15 SP7 | 17 Jun 2025 | 31 Jul 2031 | 31 Jul 2034 | LTSS Core to Dec 2037; latest 15 SP |
| 15 SP6 | 26 Jun 2024 | 31 Dec 2025 | 31 Dec 2028 | General support ended |
| 15 SP5 | 20 Jun 2023 | 31 Dec 2024 | 31 Dec 2027 | General support ended |
| 15 SP4 | 21 Jun 2022 | 31 Dec 2023 | 31 Dec 2026 | General support ended |
| 15 SP3 | 22 Jun 2021 | 31 Dec 2022 | 31 Dec 2025 | LTSS ended |

SUSE's table lists the whole 16 product as general support to 30 November 2035 and LTS to 30 November 2038, and the whole 15 product as general support to 31 July 2031 and LTSS to 31 July 2037. The SP7 release notes describe it as fully maintained to 31 July 2034 (summarised), which matches the SP7 LTSS date; read the lifecycle page for the support phase you are buying.

## SLES 15 SP7 (June 2025)

Kernel 6.4; Python 3.6 remains the system interpreter (supported to July 2034) with 3.13 in the Python 3 module; RMT replaces SMT; Redis dropped for Valkey; Kea DHCP replaces ISC `dhcpd`; XFS v4 deprecated; `pam_unix2` deprecated; `zypper search-packages` added; the YaST partitioner fully supports LUKS2 (summarised from the SP7 notes).

## SLES 15 SP6 and earlier

The release notes for SP4 to SP6 were not read for this skill; use SUSE's release notes for your service pack for kernel, library and default changes.

## SLES 16.0 (November 2025)

From the 16.0 release notes and SUSE's comparison guide (partly summarised): Linux 6.12; Agama installer; YaST removed; wicked removed and NetworkManager the only network stack; AppArmor replaced by SELinux (enforcing by default, reported permissive on SLES for SAP); modules removed; SysV init scripts, NIS and `nscd` removed; ISC DHCP replaced by Kea; GRUB 2.12 (BLS and systemd-boot are not used in 16.0); TPM full-disk encryption on AMD64/Intel 64 with TPM v2.1 or later; microarchitecture x86-64-v2 or higher (POWER10 for ppc64le, z14 for IBM Z, per SUSE's comparison table; the IBM Z level is summarised, so confirm on SUSE's hardware page); 32-bit execution disabled by default; `/tmp` is a tmpfs; `crun` removed (use `runc`); first installer user in `wheel`; root password SSH login disabled by default; transactional updates not supported (use SLE Micro); userspace live patching (libpulp) for glibc and openssl on x86-64 and ppc64le. The registration tooling for 16 is not described in the pages read; follow SUSE's current guide.

## Upgrade path to 16

Distribution migration system: `suse-migration-sle16-activation` and `run_migration`, from a registered, patched SLES 15 SP7 host (the upgrade guide); the release notes also mention SP6. Skipping service packs on 15 needs an LTSS contract (SP7 notes, summarised).

## Using this file

Quote a row with its date. For "is SLES N supported", state the phase (general or LTSS), its end date, and whether the host is registered and entitled.
