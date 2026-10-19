# Windows 10 and 11 version and lifecycle notes

Written 2026-10-19 from the Microsoft Lifecycle pages and Microsoft Learn pages fetched that day. Dates move and differ by edition; recheck the Lifecycle page for your edition before advising, and cite the source and date. The community upstream carried several wrong dates (for example, Windows 10 Enterprise 22H2 shown as supported to October 2027, and Windows 11 24H2 dates that did not match Microsoft's table); they are corrected here.

---

## Windows 10

Version 22H2 is the final Windows 10 feature update. Microsoft's Lifecycle page for Windows 10 Enterprise and Education lists 22H2 ending on 14 October 2025, and states that Windows 10 reached end of support on that date, with existing LTSC releases continuing on their own lifecycles. Beginning that date Microsoft no longer provides technical support, feature updates or quality (security and reliability) updates for the affected versions.

**Extended Security Updates (Microsoft Learn ESU page, 2026-10-19):** a paid program for devices on Windows 10 version 22H2. Organisations buy by year (no partial periods; Year Two requires Year One) for a maximum of three years; the page quoted a per-device Year One price that doubles each year; there is no technical support included beyond the ESU itself; ESU is included at no extra cost for Windows 10 virtual machines in Windows 365, Azure Virtual Desktop and Azure services listed on the page. Consumers use a separate program. Check the page for current prices and enrolment steps.

LTSC: Windows 10 Enterprise LTSC 2019 and 2021 and the IoT Enterprise LTSC editions have separate Lifecycle pages; read those, do not infer from the table above.

## Windows 11 (Microsoft Lifecycle, Modern Lifecycle Policy)

Home and Pro:

| Version | Start | End |
|---|---|---|
| 26H2 | 29 September 2026 | October 2028 (Microsoft's day-level data for 26H2 is inconsistent; check the page) |
| 26H1 | 10 February 2026 | 14 March 2028 |
| 25H2 | 30 September 2025 | 12 October 2027 |
| 24H2 | 1 October 2024 | 13 October 2026 (has ended) |
| 23H2 | 31 October 2023 | 11 November 2025 (ended) |

Enterprise and Education:

| Version | Start | End |
|---|---|---|
| 26H2 | 29 September 2026 | October 2029 (day-level data inconsistent; check the page) |
| 26H1 | 10 February 2026 | 13 March 2029 |
| 25H2 | 30 September 2025 | 10 October 2028 |
| 24H2 | 1 October 2024 | 12 October 2027 |
| 23H2 | 31 October 2023 | 10 November 2026 |

Microsoft's pages also note that Windows 11 version 26H2 is the last version that supports devices with Snapdragon 850 processors, and that 24H2 was the last supported version of Windows 11 SE. Microsoft's Learn lifecycle tables print end dates as instants that sit a day later than the calendar date in Pacific time (for example 6:59:59 AM on the next day); the dates above are the Pacific calendar dates, which match Microsoft's release-health pages. The Windows 10 end date of 14 October 2025 follows the same rule.

**Planning consequences (as of 2026-10-19):** Home and Pro devices on 24H2 are now out of support and need to move to 25H2 or later; Enterprise and Education 23H2 ends in November 2026.

## What changes between Windows 10 and 11 that matters operationally

- Hardware floor: TPM 2.0, UEFI Secure Boot and a compatible processor are enforced for the supported install path (see `editions-and-licensing.md`); there is a technical reason in that VBS features depend on them.
- Management: both versions support Intune, Group Policy and Windows Update for Business; Autopilot and Autopatch features are documented per Windows 11 version. Hotpatch for Windows 11 Enterprise (version 24H2 and later) is managed through Windows Autopatch and Intune and only for eligible devices (see the Windows Autopatch hotpatch updates page).
- Removed or changed features (Internet Explorer, Cortana, legacy components) are listed in Microsoft's Windows 11 deprecation and removal documentation; check it for the version in play.
- Developer and productivity features (Dev Drive, Snap Layouts, Copilot+ PC capabilities) depend on version and hardware; verify per version on the Microsoft what's-new page before promising them.

## Moving from Windows 10 to 11 (checklist)

1. Run `scripts/windows11-readiness.ps1` and confirm the processor on Microsoft's list.
2. Escrow BitLocker recovery keys before any firmware or TPM change.
3. Check drivers and applications (HVCI exposes unsigned drivers) in a pilot ring.
4. Decide ESU for devices that cannot move.
5. Move in rings through Windows Update for Business or Autopatch; keep a rollback window.
