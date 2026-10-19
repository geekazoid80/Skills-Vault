# RHEL family architecture reference

Sources: Red Hat product life-cycle data and documentation (RHEL 10 considerations in adopting, 10.0 release notes, DNF, SELinux, firewall and networking guides, the 8-to-9 and 9-to-10 upgrade guides), AlmaLinux and Rocky Linux pages and release notes, and the DNF manual page, read on 2026-10-19. Statements from experience rather than a page are marked.

## Lineage and distributions

- **Fedora** is the upstream community distribution; **CentOS Stream** is the rolling preview of the next RHEL minor; **RHEL** is the commercial release. Major releases are about three years apart (8: May 2019, 9: May 2022, 10: May 2025) and minors about every six months.
- **Rocky Linux** and **AlmaLinux** are free rebuilds or compatible builds. AlmaLinux 10.2 documents deliberate deviations from RHEL: an x86-64-v2 build for older CPUs alongside v3, i686 userspace packages, Btrfs support including boot, the CRB repository enabled by default, frame pointers, SPICE and KVM on POWER. Rocky ships dual-signed Secure Boot shims and an opt-in `security` repository. Neither project is a Red Hat product.

## Repositories and content

- **BaseOS** holds the core operating system; **AppStream** holds applications and runtimes, with life cycles that can be shorter than the release's (Red Hat publishes an Application Streams life-cycle page). **CRB** (CodeReady Builder) carries development packages. **EPEL** is a Fedora community repository, not supported by Red Hat.
- RHEL 8 and 9 use **modules** for some applications (`dnf module list`, `dnf module enable <name>:<stream>`, `dnf module install <name>:<stream>/<profile>`, `dnf module reset`). RHEL 10 provides initial Application Stream versions as plain RPMs and does not use modularity.
- RHEL repositories are served from the Red Hat CDN to registered systems, from Satellite, or from RHUI in public clouds. A system that is registered but has the wrong release lock sees the wrong content; check `subscription-manager release --show` on RHEL 8 and 9.

## dnf and rpm

`dnf` is the package manager on 8, 9 and 10 (RHEL 10 documentation still uses `dnf` throughout; RPM is 4.19). Transaction history is in `dnf history`; `dnf history undo` reverts a transaction but downgrading RHEL system packages that way is unsupported. Plugins: `dnf-plugins-core` (4.7.0 in RHEL 10), `versionlock`. `rpm -qa`, `rpm -qf`, `rpm -V` verify and query. The RPM database is SQLite from RHEL 9 (BerkeleyDB in 8) per common documentation; check `rpm --version` and `rpm -E %_db_backend` on your host.

## SELinux

SELinux labels every process and file; the targeted policy confines services. Policy and mode: `/etc/selinux/config`, `sestatus`, `getenforce`. Troubleshooting: audit log (`/var/log/audit/audit.log`) via `ausearch`, `sealert` from `setroubleshoot-server`, `semanage` and `restorecon` from `policycoreutils-python-utils`. In RHEL 10.1 some policy modules for EPEL moved to `-extra` subpackages in CRB. SELinux userspace 3.8 (RHEL 10) adds a CIL output mode for `audit2allow`.

## Crypto policies, FIPS and auditing

System-wide crypto policies set defaults for TLS, SSH and other toolkits through `update-crypto-policies`. The four predefined policies are DEFAULT, LEGACY, FUTURE and FIPS; sub-policies refine them. RHEL 10 provides post-quantum algorithm support as a Technology Preview and OpenSSH 9.9. FIPS mode is turned on with `fips=1` at installation. `auditd` and `ausearch` hold the audit trail; `aide` (file integrity) and `keylime` (remote attestation) ship with the distribution.

## Networking and firewall

NetworkManager manages connections as keyfiles (`/etc/NetworkManager/system-connections/*.nmconnection`); `nmcli` is the scripting tool and `nmcli connection reload` re-reads files. `firewalld` provides zones (default `public`), services, rich rules and policies on the nftables backend; direct rules use iptables and are unmaintained. RHEL 10 removes ifcfg support, `teamd`, `dhclient` and firewalld lockdown. `chronyd` provides time.

## Storage

XFS is the default file system (grow only). LVM manages volumes; Stratis provides pool-based storage. The Btrfs file system is not supported in RHEL; AlmaLinux 10.2 adds it as a deviation. `VDO` is part of LVM in recent releases (common documentation; confirm for your release).

## Containers and image mode

Podman, Buildah and Skopeo are the container tools (see `podman-ops`). RHEL 10 removes `runc` and the CNI network stack. Image mode (bootc) builds the operating system from a container image; most file systems are read-only in image mode.

## Upgrade and conversion tooling

`leapp` is Red Hat's in-place upgrade utility (consecutive major releases only). AlmaLinux ELevate is a Leapp-based project with its own data (`leapp-data`). `migrate2rocky` converts supported systems to Rocky. `convert2rhel` is Red Hat's tool for converting other EL distributions to RHEL (named here from general knowledge; read Red Hat's documentation before using it).
