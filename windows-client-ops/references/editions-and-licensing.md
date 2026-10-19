# Windows client editions and licensing

Edition feature matrices change between releases. This file keeps what is stable and points to Microsoft's edition comparison for the rest. Syntax has not been run on live systems.

---

## Edition roster

| Edition | Target |
|---|---|
| Home | Consumers; no domain join or Group Policy; setup needs an internet connection and a Microsoft account |
| Pro | Small business and power users; domain join, Group Policy, Windows Update for Business, BitLocker management, Hyper-V, RDP host |
| Pro for Workstations | High-end workstations (more RAM and sockets, ReFS and SMB Direct features) |
| Enterprise | Large organisations; full policy and security feature set, LTSC available |
| Education | Enterprise-equivalent for education customers |
| Enterprise LTSC | Fixed-function devices; fixed feature set, longer servicing, separate licensing |
| IoT Enterprise (including LTSC) | Embedded devices, longer lifecycles |

Home to Pro upgrades are done by key; Pro to Enterprise by volume licensing or subscription entitlement; moving to LTSC is a clean install of the LTSC media.

## Editions and hardware limits to verify

Commonly published limits are RAM of 128 GB (Home), 2 TB (Pro) and 6 TB (Pro for Workstations and Enterprise), and CPU sockets of 1 (Home), 2 (Pro and Enterprise) and 4 (Pro for Workstations). Check Microsoft's Windows 11 specifications and edition comparison before relying on them. Credential Guard, Personal Data Encryption and full AppLocker authoring are edition-gated (typically Enterprise and Education); confirm in Microsoft's feature-by-edition documentation.

## Windows 11 hardware requirements (Microsoft, 2026-10-19)

| Component | Requirement |
|---|---|
| Processor | 1 GHz or faster, two or more cores, compatible 64-bit processor or SoC |
| Memory | 4 GB or more |
| Storage | 64 GB or more available |
| Graphics | DirectX 12 or later with a WDDM 2.0 driver |
| Firmware | UEFI, Secure Boot capable |
| TPM | 2.0 |
| Display | 720p, 9 inches or larger, 8 bits per colour channel |
| Network | Internet connection for updates; Home needs it and a Microsoft account at setup |

Processor generation limits are published as a separate list; do not paraphrase them from memory. Virtual machines need generation 2, a virtual TPM and Secure Boot.

## Upgrade paths

- Windows 10 to 11: free on eligible hardware through Windows Update or media, with the OS prerequisites above; edition maps like for like.
- Windows 10 LTSC to a newer LTSC: clean install or in-place with the newer LTSC media; LTSC does not move through the Windows Update feature channel.
- Windows 10 end of support was 14 October 2025; see `version-notes.md` and the ESU page.

## LTSC considerations

LTSC is for fixed-function devices (medical, industrial, kiosk, point-of-sale, air-gapped systems), not for general knowledge workers: it has no annual feature updates and a reduced inbox app set. LTSC licences are bought separately from the general availability channel. Support periods for each LTSC release and its IoT variant are on their own Lifecycle pages.

## Edition detection

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
Get-ComputerInfo | Select-Object WindowsProductName, WindowsEditionId, OsBuildNumber
```

EditionID examples: `Core` Home, `Professional` Pro, `ProfessionalWorkstation` Pro for Workstations, `Enterprise`, `Education`, `EnterpriseS` Enterprise LTSC.
