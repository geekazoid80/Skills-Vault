# Windows client architecture reference

Desktop-specific internals. The NT kernel, registry, boot, services, storage and security architecture are shared with the server release; see `windows-server-ops` `references/architecture.md` for those. Syntax here has not been run on live systems.

---

## Application models

| Model | Notes |
|---|---|
| Win32 | Classic desktop applications, no sandbox, installed by MSI or EXE; still the dominant line-of-business model |
| UWP | Sandboxed AppContainer model with declared capabilities; lifecycle managed by the process lifetime manager; delivered through the Store or sideloading |
| MSIX | Container-based package format; clean install and uninstall; Win32 applications can be packaged through the Desktop Bridge |
| winget | Command-line package manager; supports MSI, MSIX, EXE and portable installers; private sources possible; `winget configure` for DSC-style machine setup |
| WinUI 3 / Windows App SDK | Current UI framework, decoupled from the OS cadence |

## Display and graphics

The Desktop Window Manager (DWM) composes all windows; the Windows Display Driver Model (WDDM) governs display drivers and GPU scheduling. A display driver that stops responding is reset by timeout detection and recovery (TDR), logged as System event 4101. Windows 11 requires DirectX 12 with a WDDM 2.0 driver.

## Power

Modern Standby (connected standby) lets devices wake for background work while "asleep"; `powercfg /sleepstudy` shows drain. S3 sleep is the older model.

## Management planes

| Plane | Delivery | Typical scope |
|---|---|---|
| Group Policy | ADMX policies from SYSVOL, domain-joined devices | On-premises estates |
| MDM (Intune and others) | CSP-backed settings over HTTPS | Entra ID-joined or hybrid devices |
| Co-management | Workloads split between Configuration Manager and Intune | Migration paths |

Group Policy applies offline from cache; MDM needs connectivity to change. Conflicts are resolved by policy precedence rules in each plane, so avoid setting the same thing in both.

## Update plumbing

Windows Update service (`wuauserv`), Update Orchestrator (`UsoSvc`), BITS, Delivery Optimisation for peer download, Windows Update for Business policies in the `Policies\Microsoft\Windows\WindowsUpdate` registry key, and optional WSUS. Feature updates arrive annually; quality updates monthly.

## Security features that are hardware-dependent

TPM 2.0, UEFI Secure Boot, VBS with HVCI and Credential Guard (edition and hardware dependent), BitLocker and Device Encryption, Windows Hello and Hello for Business, Smart App Control, Microsoft Defender Antivirus and attack surface reduction rules, App Control for Business (WDAC) and AppLocker. See `best-practices.md` and `editions-and-licensing.md`.
