# Windows Server version and lifecycle notes

Written 2026-10-19. Lifecycle dates come from the Microsoft Lifecycle pages for each release and the feature statements from Microsoft Learn pages fetched the same day. Dates and terms move, so re-check the Lifecycle page before planning, and write down the source and date next to any figure you give. The community upstream these notes replace carried several wrong dates and defaults; they are corrected here, not repeated.

---

## Support dates (Microsoft Lifecycle, Fixed Lifecycle Policy)

| Release | Build | Start | Mainstream support ended or ends | Extended support ends |
|---|---|---|---|---|
| Windows Server 2016 | 14393 | October 2016 | January 2022 (ended) | January 2027 |
| Windows Server 2019 | 17763 | November 2018 | January 2024 (ended) | January 2029 |
| Windows Server 2022 | 20348 | August 2021 | October 2026 (the listed date has now passed, so the release is in extended support) | October 2031 |
| Windows Server 2025 | 26100 | November 2024 | November 2029 | November 2034 |

Containers released with a Windows Server release follow the same dates. Hotpatch on Datacenter: Azure Edition 2022 Core is supported through the end of mainstream support, per the 2022 Lifecycle page, so that support period has now ended. Microsoft's Learn lifecycle tables print end dates as instants a day later than the Pacific calendar date; the months above are unaffected.

**Planning consequences:** 2016 leaves extended support in January 2027, so plan its replacement now. 2019 has about two years of extended support left. 2022 no longer gets non-security fixes as mainstream support has ended.

---

## Windows Server 2016

First native Windows containers (Windows Server containers and Hyper-V containers); Nano Server as a deployment option (Nano Server became a container base image only from 2019, so it cannot be a host OS on later releases); Shielded VMs and the Host Guardian Service; Storage Spaces Direct and Storage Replica (Datacenter); Credential Guard and Device Guard; Just Enough Administration; software-defined networking with Network Controller (Datacenter).

## Windows Server 2019

Windows Admin Center as a browser-based management gateway; System Insights (local predictive analytics for capacity); Storage Migration Service for file server migrations; OpenSSH client and server as optional features; Windows nodes for Kubernetes; Storage Replica on Standard edition with limits; Storage Spaces Direct improvements.

## Windows Server 2022

Secured-core server (TPM 2.0, DRTM, Kernel DMA Protection, VBS and HVCI on certified hardware); TLS 1.3 enabled by default; SMB compression and AES-256 encryption options; SMB over QUIC and Hotpatch on Azure Edition; nested virtualisation on AMD processors; Azure Arc integration. Microsoft's Schannel documentation notes TLS 1.0 and 1.1 deprecation beginning with Windows 11 Insider builds; do not assume the 2022 default disables them, read the registry and Schannel logs.

## Windows Server 2025 (per Microsoft's what's-new page, 2026-10-19)

| Area | What the page states |
|---|---|
| Hotpatch | Available for Windows Server 2025 machines connected to Azure Arc once enabled in the Azure Arc portal. The what's-new page still labelled Arc-enabled Hotpatch as preview, while the Hotpatch page says it is available at no extra cost; read the Hotpatch page for current terms |
| SMB over QUIC | Server feature now in Standard and Datacenter, no longer Azure Edition only |
| SMB | Authentication rate limiter on by default; the SMB client can block NTLM for remote outbound connections (an option, not a blanket default) |
| Credential Guard | Enabled by default on devices that meet the requirements; Microsoft's Credential Guard documentation scopes default enablement to domain-joined, non-domain-controller systems that meet the licence, hardware and software requirements and are not explicitly disabled |
| Active Directory | 32k database page size as an optional feature that needs the new functional level (DomainLevel and ForestLevel 10); delegated managed service accounts (dMSA); LDAP signing (sealing) required by default for new deployments after a SASL bind; LDAP channel binding audit events; TLS 1.3 for LDAP over TLS |
| Windows LAPS | New automatic managed local account feature among other improvements |
| Storage | NVMe performance optimised (IOPS up, CPU use down; no figure given on the page); Storage Replica compression; Dev Drive |
| Virtualisation | GPU partitioning (GPU-P) with high availability |
| Tools | `dtrace` as a native tool; OpenSSH server installed by default; WinGet installed by default; Windows Terminal; Bluetooth; Wireless LAN Service feature installed by default (service set to manual) |

Items the upstream stated that could not be confirmed on these pages and are therefore not repeated: a fixed 80 per cent IOPS gain, "NTLMv1 blocked by default", "SMB signing required for all connections", containerd replacing Docker as the default runtime, a per-core Hotpatch fee, and 40 per cent AD replication savings. Check the release notes and the specific feature pages before stating any of them.

---

## Upgrading to 2025 (checklist, verify per environment)

1. Audit NTLM use and LDAP binds before the upgrade (NTLM operational log, LDAP signing and channel binding events).
2. Test applications against Credential Guard on capable hardware.
3. Update NVMe firmware; a faster stack can expose old firmware faults.
4. Decide on Hotpatch and Azure Arc enrolment.
5. Treat raising domain and forest functional levels as one-way; do it only after every domain controller runs the new release.
6. Re-test container workflows and base-image compatibility against the new host.
7. Keep a rollback (snapshot or backup) and a pilot ring.
