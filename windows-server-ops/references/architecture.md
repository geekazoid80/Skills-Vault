# Windows Server architecture reference

How the platform is put together. Operating rules and the command safety table are in `SKILL.md`. Syntax here has not been run on live systems.

---

## NT kernel

- **Privilege separation:** kernel mode (ring 0: HAL, `ntoskrnl.exe` kernel and executive, drivers) and user mode (processes, subsystems, services). With VBS, a further isolation level (Virtual Secure Mode) holds security-critical processes beyond the reach of the normal kernel.
- **HAL** hides platform hardware differences. **Executive** subsystems include the I/O manager, memory manager, object manager, process and thread manager, security reference monitor, Plug and Play and power manager, configuration manager (registry) and cache manager.
- **Key processes:** `smss.exe` (session manager), `csrss.exe`, `wininit.exe`, `services.exe` (service control manager), `lsass.exe` (local security authority and authentication packages), `svchost.exe` (shared service host), `winlogon.exe`.

## Boot

1. UEFI firmware initialises hardware and, with Secure Boot, verifies the boot manager signature.
2. The Windows boot manager reads the Boot Configuration Data (BCD) store (`bcdedit /enum` reads it) and loads `winload.efi`.
3. The kernel and early-boot drivers load; ELAM drivers start first; the system hive is mapped.
4. Session manager starts, then `wininit`, the service control manager and `lsass`; services start in phases (boot, system, automatic, delayed automatic, manual).
5. Measured Boot records boot components into TPM PCRs for attestation; Secure Boot and Measured Boot are inputs to secured-core and VBS.

## Registry

Hives are files: `SYSTEM`, `SOFTWARE`, `SECURITY`, `SAM` and `COMPONENTS` under `%SystemRoot%\System32\config`, per-user `NTUSER.DAT`, and BCD. Paths that matter operationally:

| Path | Holds |
|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Services` | Service and driver definitions |
| `HKLM\SYSTEM\CurrentControlSet\Control\Lsa` | Authentication settings (for example `LmCompatibilityLevel`) |
| `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL` | TLS protocol and cipher switches |
| `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server` | RDP settings |
| `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` | Edition, build, revision (`UBR`) |
| `HKLM\SOFTWARE\Policies` | Group Policy-delivered settings |

## Services and memory

Service types: Win32 own-process and shared-process, drivers, user services. Service accounts: LocalSystem (unrestricted on the machine), LocalService, NetworkService, virtual accounts, gMSA or dMSA. Modern `svchost` splits many services into separate processes.

x64 virtual address space is split between user and kernel ranges. Pool memory is paged or nonpaged; a steadily growing nonpaged pool points to a driver leak.

## Storage stack

Application, file system (NTFS, ReFS), volume manager (Storage Spaces, dynamic volumes), partition manager, class driver (disk), port and miniport drivers (StorNVMe, storport), then hardware. **VSS** coordinates application-consistent shadow copies through writers, providers and requesters.

| Facts | NTFS | ReFS |
|---|---|---|
| Boot volume | Yes | No |
| Integrity checksums | No | Yes |
| Repair | `chkdsk` (offline for deep repair) | Online, using redundant copies on resilient Storage Spaces |
| Preferred for | Boot, general application volumes, features such as EFS and disk quotas | Hyper-V and Storage Spaces Direct volumes, integrity workloads |

**Storage Spaces** pools disks into virtual disks with simple, mirror or parity resiliency. **Storage Spaces Direct** extends that across cluster nodes with local drives (Datacenter edition; clustering is in `windows-failover-clustering-ops`). Windows Server 2025 optimises the NVMe path (Microsoft reports higher IOPS and lower CPU use; measure on your hardware).

## Networking stack

NDIS and miniport drivers, TCP/IP stack, Windows Filtering Platform (firewall), then Winsock and applications. **SMB 3.x** features: Multichannel, SMB Direct (RDMA), encryption, signing, SMB over QUIC (UDP 443, TLS 1.3), compression (2022 onwards). **Teaming:** LBFO versus Switch Embedded Teaming; SET lives in the Hyper-V virtual switch and keeps RDMA available.

## Security architecture

- **Authentication:** Kerberos (default in a domain, ticket-granting ticket plus service tickets) with NTLM as fallback. `lsass.exe` hosts the authentication packages; run it as a protected process light where supported.
- **Authorisation:** every process carries an access token (user and group SIDs, privileges, integrity level) which the security reference monitor checks against object DACLs.
- **VBS, Credential Guard, HVCI:** the hypervisor isolates secrets (Credential Guard, `LSAIso`) and validates kernel-mode code integrity. Requirements: UEFI Secure Boot, a 64-bit CPU with SLAT and virtualisation extensions, and a TPM (recommended for VBS; required for secured-core and for some features).
- **Secured-core server (2022 onwards):** adds DMA remapping, Kernel DMA Protection and DRTM on certified hardware, on top of TPM 2.0, Secure Boot and VBS.

## WMI and CIM

Management data is exposed through WMI providers. CIM cmdlets (`Get-CimInstance`) use WS-Man by default with DCOM fallback and are the supported direction; `Get-WmiObject` is legacy and absent from PowerShell 7. Namespaces used here include `root\cimv2` and `root\Microsoft\Windows\DeviceGuard`.
