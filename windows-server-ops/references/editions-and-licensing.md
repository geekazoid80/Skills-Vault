# Windows Server editions and licensing

Edition rosters, feature gates and licensing change. This file records what is stable and says where to check the rest. Syntax has not been run on live systems. Licensing and pricing are commercial facts: confirm them with Microsoft licensing documents or an authorised partner.

---

## Editions

| Edition | Notes |
|---|---|
| Essentials | OEM-licensed on recent releases; small-business limits on users and devices |
| Standard | Core server features; limited virtualisation rights |
| Datacenter | Unlimited virtualisation rights; the edition that carries Storage Spaces Direct and other software-defined features |
| Datacenter: Azure Edition | Azure and Azure Local only (not for on-premises bare metal); the first to carry Hotpatch on 2022 |
| Hyper-V Server (free) | 2016 and 2019 only; not offered on 2022 or 2025 |

Check the current feature comparison for your release before promising a feature on Standard. Items that commonly gate on Datacenter: Storage Spaces Direct, Host Guardian (shielded VM) hosting, Network Controller and unlimited Storage Replica. SMB over QUIC moved from Azure Edition only (2022) to Standard and Datacenter (2025, per Microsoft's what's-new page). Hotpatch on 2025 Standard and Datacenter uses Azure Arc; see `SKILL.md`.

## Hardware floor (Microsoft hardware requirements page, 2026-10-19)

1.4 GHz 64-bit CPU with NX/DEP, CMPXCHG16b, LAHF/SAHF, PrefetchW and SLAT (EPT or NPT); 2025 additionally needs SSE4.2 and POPCNT. RAM minimum 2 GB on 2025 and 1 GB for Server Core on earlier releases (virtual machines at the bare minimum can fail to install; allocate more during setup). Disk: 32 GB absolute minimum, Server Core about 4 GB smaller than Desktop Experience. A 1 Gbit PCIe Ethernet adapter. A TPM, if present and used for BitLocker, must be 2.0 with SHA-256 PCR banks.

## Licensing model (verify with Microsoft)

- Standard and Datacenter are licensed per physical core; Microsoft's published minimums have been 8 core licences per processor and 16 per server, sold in packs.
- Standard gives rights to run two operating system environments per fully licensed host; more require more licences. Datacenter gives unlimited. Work out the break-even from current prices, not from a rule of thumb.
- Client access licences (CALs) are required for users or devices accessing a Standard or Datacenter server; Remote Desktop Services needs RDS CALs on top. Azure Edition is billed through Azure.
- Pay-as-you-go licensing through Azure Arc exists for Windows Server 2025; check the current terms.

## Upgrade paths

| Topic | Fact to check |
|---|---|
| In-place upgrade | Microsoft supports upgrading several releases at a time to 2025 (check the supported source versions in the upgrade documentation) |
| Cluster OS Rolling Upgrade | One release at a time |
| Edition conversion | Standard to Datacenter is supported with `DISM /online /Set-Edition`; the reverse needs a clean install |
| Evaluation to retail | `DISM /Set-Edition` with a product key |

```powershell
DISM /online /Get-CurrentEdition
DISM /online /Get-TargetEditions
DISM /online /Set-Edition:ServerDatacenter /ProductKey:<key> /AcceptEula   # state-changing, one way, needs a restart
```

Never paste a product key into a shared script; read it from your licensing system at run time.

## Edition detection

```powershell
(Get-CimInstance Win32_OperatingSystem).Caption
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
dism /online /Get-CurrentEdition
```

## Decision framework

| Scenario | Lean towards | Reason |
|---|---|---|
| Physical server, few or no virtual machines | Standard | Rights suffice |
| Dense virtualisation | Datacenter | Unlimited rights; compute the break-even with current prices |
| Storage Spaces Direct, shielded VMs, SDN controller | Datacenter | Edition-gated |
| Workloads on Azure needing Hotpatch | Datacenter: Azure Edition | Built in on Azure |
| Small workload, no gated features | Standard | Lower cost |
