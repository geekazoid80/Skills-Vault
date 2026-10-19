# macOS version notes

Dated 2026-10-19. Sources: Apple Support security releases page, Apple's "What's new for enterprise" pages for each release, Apple's Rosetta support page, Apple's device-management schemas (github.com/apple/device-management, release branch), and the man pages of a macOS 26.7.1 machine. Apple publishes no end-of-support dates; lifecycle statements below are inferences from the security releases page and are labelled.

## Lifecycle snapshot

| Release | Codename | Released | Latest seen | Status (inference) |
|---|---|---|---|---|
| macOS 27 | Golden Gate | 14 Sep 2026 | 27.0.1, 28 Sep 2026 | Current |
| macOS 26 | Tahoe | 15 Sep 2025 | 26.7.1, 28 Sep 2026 | Receiving security updates |
| macOS 15 | Sequoia | 16 Sep 2024 | 15.8.1, 28 Sep 2026 | Receiving security updates |
| macOS 14 | Sonoma | Sep 2023 | 14.8.9, 6 Aug 2026 | No fixes in the 14 or 28 Sep 2026 rounds; treat as unsupported |

Re-check the security releases page (support.apple.com/en-us/100100) before quoting any row; it lists what Apple shipped, not what it promises.

## Hardware support

- **macOS 27** runs on Apple silicon only: MacBook Neo (2026), MacBook Air and MacBook Pro with Apple silicon (2020 and later), iMac with Apple silicon (2021 and later), Mac mini with Apple silicon (2020 and later), Mac Studio (2022 and later), Mac Pro with Apple silicon (2023).
- **macOS 26** lists Mac Studio (2022 and later), iMac (2020 and later), Mac Pro (2019 and later), Mac mini (2020 and later), MacBook Air with Apple silicon (2020 and later), MacBook Pro 16-inch (2019), MacBook Pro 13-inch (2020, four Thunderbolt 3 ports) and MacBook Pro with Apple silicon (2020 and later). The four Intel models are the last Intel Macs to receive a new macOS release.
- **macOS 15** lists Mac Studio (2022 and later), iMac (2019 and later), Mac Pro (2019 and later), Mac mini (2018 and later), MacBook Air (2020 and later), MacBook Pro (2018 and later) and iMac Pro (2017 and later).
- Apple Intelligence features need Apple silicon; they never ran on Intel Macs.
- Rosetta: available on Apple silicon through macOS 27; macOS 26.4 added a notification when a user opens a Rosetta app, controlled by the `allowRosettaUsageAwareness` restriction; macOS 27 does not automatically restore Rosetta on upgrade if it was installed before; from macOS 28 Rosetta covers only certain older games.
- Intel security updates after Tahoe: reported as three years in forum posts quoting Apple; not confirmed on a page read for this skill. Plan an Intel refresh against a date you have confirmed.

## Changes administrators will meet

### macOS 14 Sonoma

- Declarative device management software update enforcement (`com.apple.configuration.softwareupdate.enforcement.specific`, macOS 14).
- Platform SSO gained the `PlatformSSO` dictionary in the Extensible SSO payload (macOS 14).

### macOS 15 Sequoia

- Software updates can be managed entirely with declarative device management; `com.apple.configuration.softwareupdate.settings` (macOS 15).
- Platform SSO authentication policies: `FileVaultPolicy`, `LoginPolicy`, `UnlockPolicy` (macOS 15).
- Disk management configuration for external and network storage (macOS 15).
- Profile-based User Enrollment removed (use Managed Apple Account sign-in); third-party DirectoryService plug-ins removed (use Platform SSO); the Profiles pane became Device Management in General; local network privacy prompts for third-party apps and launch agents.
- Application firewall settings left `com.apple.alf.plist` (use `socketfilterfw`); `spctl` can no longer disable Gatekeeper; `sudo` logging is off by default.
- 15.5 deprecated the AFP client.

### macOS 26 Tahoe

- Management service migration: Apple Business Manager and Apple School Manager can move a macOS 26 device to a new service with a deadline (devices enrolled through ADE; macOS can also move from ADE to profile-based enrollment).
- Declarative app and package deployment (`com.apple.configuration.app.managed`, `com.apple.configuration.package`, macOS 26).
- Platform SSO at Setup Assistant (`EnableRegistrationDuringSetup`), Authenticated Guest mode with a Tap to Login option using compatible NFC accessories (`TemporarySessionQuickLogin`), and new-user authentication methods including `AccessKey` (access keys in Apple Wallet, per Apple's Platform SSO page).
- FileVault can be unlocked over SSH after a restart when Remote Login is on.
- Legacy software update management (the `com.apple.SoftwareUpdate` payload, `ScheduleOSUpdate`, `AvailableOSUpdates`) deprecated, with removal in 27.
- 26.4: managed Migration Assistant declaration (`com.apple.configuration.migration-assistant.settings`); declarative configurations for Apple Intelligence, External Intelligence, Siri and Keyboard replace the matching `com.apple.applicationaccess` restrictions, now deprecated; Rosetta usage notification.
- IKEv2 VPN dropped DES, 3DES, SHA1-96, SHA1-160 and Diffie-Hellman groups below 14. Apple Sparse Image Format (ASIF) support.

### macOS 27 Golden Gate

- Apple silicon only.
- **Legacy MDM software update management no longer functions**: software update commands and queries, recommended cadence settings and restrictions such as deferrals and Background Security Improvements. Use declarative software update management.
- Device management can allow or deny apps and binaries; consolidated privacy consent declaration; Platform SSO with OpenID at FileVault unlock, Lock Screen and login window, network and captive network controls at login, Touch ID or Apple Watch requirements, and FileVault support for Authenticated Guest mode; declarative Extensible SSO (`com.apple.configuration.extensible-sso`); new declarative VPN, DNS and relay configurations; content caching reporting; the ManagedApp framework on macOS; restrictions for Siri AI, Visual Intelligence and Natural Language Calendar Event Editing; package removal behaviour (`UninstallBehavior`); ACME and SCEP credential controls for availability after first unlock; new status items (enrollment type, Lockdown Mode, waiting in Setup Assistant); legacy profiles can be delivered as declarative assets; the Liquid Glass setup pane can be skipped.
- `tccutil list`, App Attest, and apps can no longer read the local TCC database.
- 27.0.1 fixed Platform SSO not showing username and password fields on the Lock Screen after waking from sleep.

## Using this file

Quote a row with its date. When a user asks "is macOS N still supported", answer with the latest security release you can see for that release and its date, say that Apple publishes no support promise, and recommend a decision on that evidence rather than a calendar rule.
