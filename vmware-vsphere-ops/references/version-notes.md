# vSphere version and licensing notes

Read this before advising on versions, upgrades, editions or support dates. Everything here is a point-in-time note written on 2026-10-16 from search results, several of which are reseller or community sources rather than Broadcom documents. Treat each line as a pointer to check, not a fact to quote. The authoritative sources are Broadcom's Product Lifecycle matrix, the release notes and the interoperability matrix for the exact versions in play.

---

## What was found, and how solid it is

| Topic | Note | Source tier |
|---|---|---|
| vSphere 8.0 | General availability 11 October 2022. End of general support is widely cited as 11 October 2027 and technical guidance as 11 October 2029, but these are not confirmed against Broadcom's matrix, and Broadcom has moved a lifecycle date before (the vSphere 7 end of general support moved from April to October 2025). | Mixed; verify |
| vSphere 9.0 | Released in June 2025 as part of VMware Cloud Foundation 9 and vSphere Foundation 9. The hypervisor was renamed from ESXi to ESX and versioning moved to a four-part scheme. Early coverage said there was no standalone vSphere 9 product. | Community and press; verify |
| Licensing model | Subscription only. Per-core licensing with a 16-core minimum per CPU. A 72-core minimum per product per order, reported from April 2025. vSphere Essentials Plus reported as discontinued, with Enterprise Plus as the nearest replacement. Existing perpetual licences remain valid for their term but cannot be extended. | Reseller and press; verify with Broadcom or an authorised partner |
| vSAN ESA | ESA compression is part of the architecture; Broadcom's API reference reports it enabled by default from 9.1 with disabling unsupported, while older material describes per-policy control, so check your release. ESA global deduplication was described as a 9.0-era feature, limited availability, with prerequisites (reported: version 9.0.1, 25 GbE or faster, telemetry on) and not supported with stretched clusters in its first release. This corrects older text that said ESA deduplication was always on in vSAN 8. | VMware blogs and community; verify |
| PowerCLI | Broadcom renamed VMware PowerCLI to VCF PowerCLI, described on its developer page as a continuation of the VMware.PowerCLI module; that page lists 9.1.1 as the latest release, with 9.1 and 9.0 also available. PowerCLI 13.3 (July 2024) targeted vSphere 8.0 Update 3. A community post says 9.1 supports vSphere 8.0, 9.0 and 9.1, which is not the interoperability matrix, so check the compatibility matrix and the module name your environment installs (`VCF.PowerCLI` or `VMware.PowerCLI`) before scripting against 9.0. | Broadcom developer page, community post; verify |

## What was removed from the upstream notes, and why

The community upstream these notes replaced listed a REST API v9 with a GraphQL endpoint, a PowerCLI minimum for vSphere 9, a table of build numbers, confidential-computing and GPU feature lists, and "mainstream support through 2030". None of those could be confirmed from a Broadcom source, so they are not repeated. Add them back only after checking the vSphere 9 release notes.

## How to use this file

1. Ask which exact vCenter and ESXi builds are in play (`Get-VMHost | Select-Object Name, Version, Build`).
2. Open the release notes and interoperability matrix for those builds on Broadcom's documentation site.
3. Check the lifecycle matrix for support dates, and the licensing documents or an authorised partner for editions and minimums.
4. Write down the source and the date next to every figure you give.

## Upgrade sequence (general, verify per release)

Check hardware, firmware and driver compatibility; check third-party VIBs and backup-product support; upgrade vCenter first (it must be the same version as or newer than the hosts); upgrade hosts through lifecycle management with rolling remediation, or interactively; upgrade VMware Tools, then VM hardware versions in maintenance windows; update PowerCLI, Terraform providers and other automation against the new API; then retest backups. Keep a rollback plan for each step and do not raise VM hardware versions until every host in the cluster is upgraded.
