# RHEL family version notes

Dated 2026-10-19. Sources: Red Hat product life-cycle data (Customer Portal API), the RHEL 10 considerations in adopting, the 10.0 release notes, the upgrade guides, the Errata and Support Policy page, AlmaLinux release notes (10.2) and release-notes index, Rocky Linux news, and endoflife.date for minor release dates (a community source used only for dates of minors). Re-check Red Hat's life-cycle page before quoting a date; Red Hat calls future phase dates approximate.

## Lifecycle snapshot

| Release | GA | End of full support | End of maintenance | Extended life cycle support (add-on) ends | Latest minor seen |
|---|---|---|---|---|---|
| RHEL 10 | 20 May 2025 | 31 May 2030 | 31 May 2035 | 31 May 2039 | 10.2 (19 May 2026) |
| RHEL 9 | 18 May 2022 | 31 May 2027 | 31 May 2032 | 31 May 2036 | 9.8 (19 May 2026) |
| RHEL 8 | 7 May 2019 | 31 May 2024 | 31 May 2029 | 31 May 2033 | 8.10 (22 May 2024) |

- Standard subscriptions cover a minor release for six months, Premium for two years, ELCP for six years (nine for the terminal .10) on eligible even-numbered minors. ELCP replaces EUS, Enhanced EUS and ELS (for RHEL 8, ELS from 8.10 on 1 June 2029); E4S continues for RHEL 8 and 9 and ELCP replaces it for SAP from 10.6.
- Minor release dates come from Red Hat's release-dates page (10.2 and 9.8 on 19 May 2026, 10.1 on 11 November 2025, 8.10 on 22 May 2024); that page gives 17 May 2022 for 9.0 where the life-cycle data says 18 May 2022. Kernels: 4.18 (8.10), 5.14 (9) and 6.12 (10).
- AlmaLinux: 10.2 released 26 May 2026 ("Lavender Lion", kernel 6.12.0-211.7.3); 9.8 released 26 May 2026; 8.10 is the last 8; active support for 10 until 31 May 2030 and security support until 31 May 2035; for 9, 31 May 2027 and 31 May 2032. Each minor reaches end of life when the next is released. 10.3 and 9.9 betas appeared in September 2026.
- Rocky Linux: 10.2 released 28 May 2026; 9.8 released 27 May 2026; 8.10 is the last 8 minor.

## RHEL 8

Kernel 4.18; Python 3.6 is the system Python; modules deliver some application versions; `network-scripts` and ifcfg profiles are still used in RHEL 8. Last minor 8.10 (May 2024). In maintenance support: errata only, no minor releases.

## RHEL 9

Kernel 5.14; Python 3.9, OpenSSH 8.7. `network-scripts` was removed. Modules remain (`dnf module`). Full support until 31 May 2027. In-place upgrade source for RHEL 10 is 9.6 (EUS) or 9.8.

## RHEL 10

From Red Hat's considerations and release notes:

- Kernel 6.12.0 with the EEVDF scheduler (CFS replaced); minimum x86-64-v3 for AMD and Intel (also ARMv8.0-A, POWER9, z14 or later); GCC 14 defaults to x86-64-v3.
- No modularity: MariaDB, MySQL and PostgreSQL are RPMs; Python 3.12, Node.js 22, PHP 8.3; OpenSSH 9.9; RPM 4.19; SELinux userspace 3.8.
- Removed or unsupported: ifcfg network profiles, `teamd`/`libteam`, `dhclient`, `runc`, CNI (use netavark), cgroups v1 boot support, firewalld lockdown, `compat-openssl11`, `fips-mode-setup`. Kernel modules for iptables moved to `kernel-modules-extra`. 32-bit ARM and MIPS backends are removed from llvm in 10.1.
- Crypto: LEGACY no longer allows SHA-1 signatures in TLS; DEFAULT rejects TLS ciphers using RSA key exchange; the FIPS policy rejects AES HMAC-SHA1 Kerberos key derivation; post-quantum algorithms are a Technology Preview.
- 10.2: SELinux policy treats `/var/opt` like `/opt`; `mlkem768x25519-sha256` is on by default for libssh; the installer uses Wayland instead of Xorg.
- AlmaLinux 10.2 ships Python 3.14, PostgreSQL 18, MariaDB 11.8, PHP 8.4, GNOME 49, Podman 5.8, NetworkManager 1.56 and chrony 4.8 as additions and updates.

## Rocky and Alma operational notes

- Rocky Linux security repository (May 2026): opt-in, disabled by default, for urgent fixes ahead of upstream; no errata records.
- Secure Boot (June 2026): Microsoft's 2011 UEFI CA expires in 2026; firmware that enrols the 2023 CAs and KEK is rolling out; Rocky ships dual-signed shims; AlmaLinux's shim 16.1 for x86_64 is dual-signed with the 2011 and 2023 certificates.
- ELevate no longer migrates from Rocky (since 3 November 2025, per AlmaLinux). `migrate2rocky` supports 8 and 9 sources.

## Using this file

Quote a row with its date. For "is RHEL N supported", give the phase and its end date from Red Hat, and for a rebuild say which project supports it and for how long.
