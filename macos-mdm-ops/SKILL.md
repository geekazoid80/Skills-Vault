---
name: macos-mdm-ops
description: "Use for managing Macs with MDM and Apple's device management: enrolment (Automated Device Enrollment, Device Enrollment, Account-Driven User Enrollment), Apple Business Manager and Apple School Manager, supervision, configuration profiles and payloads, restrictions, declarative device management (declarations, activations, status, software updates, app and package deployment), the bootstrap token, FileVault escrow, Recovery Lock, moving Macs between management services, and Platform SSO configuration on the device. Triggers include \"MDM\", \"ADE\", \"DEP\", \"Apple Business Manager\", \"ABM\", \"supervised\", \"mobileconfig\", \"configuration profile\", \"DDM\", \"declarative device management\", \"bootstrap token\", \"Recovery Lock\", \"MDM migration\", \"profiles status\", \"Platform SSO\", \"PSSO\", \"extensiblesso\", \"Jamf\", \"Intune macOS\", \"Kandji\", \"APNs certificate expired\". NOT for general macOS administration (macos-ops), NOT for identity provider tenant configuration (entra-id, okta, identity-access-management), NOT for Intune on Windows (windows-client-ops), NOT for any single MDM vendor's console steps."
license: MIT
metadata:
  version: 1.0.0
---

# macOS MDM operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: macos-mdm-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A Mac is managed when it has an MDM enrolment (a management service reached over APNs and HTTPS) and, increasingly, declarative device management (DDM), in which the device applies declared configuration and reports status on its own. Capability depends on the **enrolment type**, whether the Mac is **supervised**, the **macOS version**, and what the **management service** supports. Pin all four before advising.

**Core principle:** prefer the least disruptive fix (profile or declaration change, then re-enrolment, then erase), and verify the enrolment and the bootstrap token before relying on any control that depends on them. Apple moves capabilities from MDM commands and profiles to declarations every release: legacy software update management no longer functions in macOS 27.

> **Caveat on provenance.** Keys, versions and behaviour were reshaped from a community upstream that was largely wrong about Platform SSO and several payloads, then corrected against Apple Support pages, Apple's device-management schemas (github.com/apple/device-management, release branch, commit of 2026-09-17), the "What's new for enterprise" pages and the local man pages on 2026-10-19. The scripts are checked with `shellcheck` and stub commands only.

## Step 0: establish what you are managing

```sh
sw_vers -productVersion
profiles status -type enrollment        # local; "MDM enrollment" and "Enrolled via DEP" lines, "(User Approved)" when approved
sudo profiles status -type bootstraptoken   # supported on server? escrowed to server?
sudo profiles list -type configuration  # device-level profiles (as root); without root it lists the user's
```

`profiles show -type enrollment` asks the enrolment server and is rate limited (the man page says 10 times every 23 hours before it falls back to cache); `profiles status` is local and cheap. Since macOS 11 the `profiles` tool cannot install configuration profiles; installation is by management or System Settings. Apple's terms changed: DEP is Automated Device Enrollment (ADE); Apple Business Manager appears as "Apple Business" in current Apple pages; Managed Apple IDs are Managed Apple Accounts.

## Which commands change state

| Safe to run (read only) | Changes state, confirm first | Disruptive or destructive, get explicit approval |
|---|---|---|
| `profiles status`, `profiles list`, `profiles show -type configuration`, `profiles show -type enrollment -cached`, `fdesetup status`, `log show`, `security find-certificate`, `app-sso platform -s` | `profiles install -type bootstraptoken` (generates and escrows a token; needs secure-token admin credentials; the man page says it needs a supervised client), `profiles renew`, `profiles validate -type enrollment` (updates local enrolment information and contacts the server), `defaults write` on managed domains | `profiles remove -all` or `-forced`, un-enrolling, erasing (`EraseDevice` from the service, Erase All Content and Settings), `SetRecoveryLock` (an empty `NewPassword` clears the lock), `fdesetup changerecovery` (prints the new personal recovery key on standard output and invalidates the old one, so never run it where output is logged), reassigning devices in Apple Business Manager, a management service migration, `sudo profiles remove -type bootstraptoken` |

`mdmclient` arguments are private; do not script against them (Apple's man page says so).

## Enrolment types and supervision

| Type | How | What you get |
|---|---|---|
| Automated Device Enrollment (ADE) | Mac bought through Apple or an authorised reseller (or added with Apple Configurator) is assigned to a management service in Apple Business Manager; at setup it fetches an enrolment profile | Supervised; the richest control surface; the enrolment profile can be made mandatory; bootstrap token created at enrolment on macOS 26 and later |
| Device Enrollment (user approved) | User installs an enrolment profile and approves it | Most MDM features except those that need supervision |
| Account-driven User Enrollment | User signs in with a Managed Apple Account | Personal-device pattern with limited control; macOS 15 removed profile-based User Enrollment |

Supervision unlocks the controls Apple restricts to organisation-owned devices; each payload and command in Apple's schema says whether it needs supervision, ADE or user-approved MDM. Check the schema row before promising a control. Apple's enterprise network requirements page lists the hosts and ports. The Mac itself needs `albert.apple.com` (activation), `iprofiles.apple.com` (enrolment profiles), `deviceenrollment.apple.com` (provisional enrolment) and `*.push.apple.com` on 443, 80, 5223 and 2197 (APNs). The management service reaches `mdmenrollment.apple.com` (uploads enrolment profiles), `gdmf.apple.com` (software update catalogue), `vpp.itunes.apple.com` (app licences), and its owner uses `identity.apple.com` to request the APNs certificate; a Mac need not reach those.

## Declarative device management

DDM is declarative: the service sends declarations; the device applies them, evaluates activations, and reports status through the status channel. Declaration kinds are configurations, activations (which bind configurations to predicates), assets (data a configuration references) and management declarations. The `DeclarativeManagement` MDM command (macOS 13 and later) starts it. Legacy MDM remains for commands, wipe, lock and anything without a declaration.

| Need | Mechanism | Introduced (macOS) | Allowed enrolments (schema) |
|---|---|---|---|
| Enforce an OS version by a deadline | `com.apple.configuration.softwareupdate.enforcement.specific` (`TargetOSVersion`, `TargetBuildVersion`, `TargetLocalDateTime`, `DetailsURL`) | 14 | supervised |
| Update settings, deferrals, automatic actions, beta enrolment | `com.apple.configuration.softwareupdate.settings` | 15 (beta program keys 15.4) | supervised |
| Block or make read-only external and network storage | `com.apple.configuration.diskmanagement.settings` | 15 | supervised, local |
| Deploy App Store apps and custom apps | `com.apple.configuration.app.managed` | 26 | supervised, user |
| Deploy packages (and remove them on withdrawal, with `UninstallBehavior`) | `com.apple.configuration.package` | 26 (removal behaviour 27) | supervised |
| Deliver an old profile as a declaration | `com.apple.configuration.legacy` (`ProfileURL`, or an asset in 27) | 13 (asset 27) | supervised, user, local |
| Extensible SSO as a declaration | `com.apple.configuration.extensible-sso` | 27 | supervised, user |
| Managed Migration Assistant | `com.apple.configuration.migration-assistant.settings` | 26.4 | supervised |

The update declarations are **supervised only**, so an unsupervised Mac (for example a user-approved Device Enrollment) gets no declarative update enforcement, and once it is on macOS 27 the legacy update path no longer works either; plan for that population. `TargetLocalDateTime` is device local time, not UTC, so a fleet across time zones reaches the deadline at different moments. **Legacy software update management** (the `com.apple.SoftwareUpdate` payload, `ScheduleOSUpdate`, `AvailableOSUpdates`, recommended cadence settings, deferral restrictions) was deprecated in macOS 26 and no longer functions in macOS 27. Remove legacy update profiles and move to declarations before the fleet reaches 27.

## Configuration profiles and restrictions

Profiles are signed property lists carrying payloads; MDM-installed profiles are removed by the service. Payload types seen on macOS in Apple's schema include `com.apple.wifi.managed`, `com.apple.vpn.managed`, `com.apple.security.pkcs1`, `.pkcs12`, `.scep`, `.acme`, `.root`, `com.apple.applicationaccess` (restrictions), `com.apple.mobiledevice.passwordpolicy` (deprecated in 27), `com.apple.extensiblesso`, `com.apple.security.FDERecoveryKeyEscrow` and `com.apple.MCX.FileVault2` (FileVault), `com.apple.dnsSettings.managed` (deprecated in 27), `com.apple.security.firewall`, `com.apple.loginwindow`, `com.apple.security.smartcard`, `com.apple.system-extension-policy`, `com.apple.TCC.configuration-profile-policy`, `com.apple.servicemanagement` (login items), `com.apple.SetupAssistant.managed`. There is no `com.apple.FDE` payload. Check a key in the schema before using it; several keys that blogs list for restrictions do not apply to macOS (`allowAppInstallation`, `forceEncryptedBackup`, `allowManagedAppsCloudSync` are not macOS keys). Verified macOS restriction keys include `allowCamera`, `allowAirDrop`, `allowScreenShot` (10.14.4), `allowBluetoothModification` (13), `allowEraseContentAndSettings` (12), `allowPasswordAutoFill`, `allowPasswordSharing`, `allowiPhoneMirroring` (15) and `allowRosettaUsageAwareness` (26.4). The Apple Intelligence restriction keys in `com.apple.applicationaccess` were deprecated in 26.4 in favour of declarative configurations; `com.apple.applicationaccess.new` is deprecated in 27, and the software update deferral and enforcement keys inside `com.apple.applicationaccess` (`enforcedSoftwareUpdate*`, `forceDelayedSoftwareUpdates`) are removed in 27.

## Bootstrap token, FileVault and Recovery Lock

- **Bootstrap token:** lets macOS grant a secure token to accounts, including accounts created on demand by Platform SSO and mobile accounts, without an existing secure-token administrator. On Apple silicon it also authorises software update installs, silently authorises Erase All Content and Settings (macOS 12.0.1 and later) and the creation of users at first Platform SSO login (macOS 13 and later). On macOS 26 and later it is created during enrolment when the service supports it; before that macOS generates it when a secure-token user logs in. Check with `sudo profiles status -type bootstraptoken` (supported on server, escrowed to server). A service that supports it but holds none leaves FileVault key rotation and on-demand accounts broken.
- **FileVault escrow:** deliver a FileVault recovery key escrow configuration; if a key already exists, macOS 26 rotates it before escrow when a bootstrap token is present. Rotating a personal recovery key is `fdesetup changerecovery -personal` or a service command (`RotateFileVaultKey`).
- **Recovery Lock** (`SetRecoveryLock`, `VerifyRecoveryLock`, macOS 11.5 and later on Apple silicon): the password is required to enter Recovery; only the service can set or clear it, un-enrolling removes it (per the schema note), and changing it needs the current value. Apple's pages read for this skill do not say what an erase does to it, so confirm on a test Mac before relying on an erase to clear it. Store the value in the service's device record and plan for the case where it is lost.

## Moving Macs between management services (macOS 26 and later)

Apple Business Manager or Apple School Manager reassigns eligible devices (macOS 26, ADE-enrolled; a Mac can also move from ADE to profile-based enrolment) to the new service with an enforcement deadline; on a Mac every user gets a prompt, and at the deadline a non-dismissible full-screen prompt. Prepare the new service to apply equivalent configuration, keep managed apps (declarative managed apps are kept; the old service must not send app removal on unenrolment), move volume-purchased app tokens, and have the new service install a FileVault escrow configuration so the key rotates with the bootstrap token. Apple's migration guide says existing Activation Lock is removed during migration and its bypass codes are invalidated (check the page for which device types, and for re-applying it afterwards). Test on a pilot first. The admin APIs can assign devices and set or cancel deadlines in bulk. Apple's pages differ in detail by version; read the current "Migrate managed devices" guide before a run.

## Platform SSO on the device

Platform SSO (PSSO, macOS 13 and later) uses an Extensible SSO payload and an app extension from the identity provider. Facts from Apple's schema:

- `com.apple.extensiblesso` requires `ExtensionIdentifier`, `Type` (`Credential` or `Redirect`) and, on macOS, `TeamIdentifier`; the `PlatformSSO` dictionary (macOS 14 and later) requires `Type` to be `Redirect`. The top-level `AuthenticationMethod` was deprecated in 14 in favour of `PlatformSSO.AuthenticationMethod` (`Password`, `UserSecureEnclaveKey`, `SmartCard`; `OpenID` in 27). Take the extension and team identifiers from the identity provider's documentation, not from a blog.
- Authentication policies (introduced in macOS 15): `FileVaultPolicy`, `LoginPolicy` and `UnlockPolicy` are **arrays** of strings from `AttemptAuthentication`, `RequireAuthentication`, `AllowOfflineGracePeriod`, `AllowAuthenticationGracePeriod`, `RequireTouchID`, `RequireTouchIDOrWatch`, `AllowOpenIDForTouchIDFallback` (and `AllowTouchIDOrWatchForUnlock` for unlock). The schema gives no version per value; Apple lists options to require Touch ID or Apple Watch at login or unlock as new in macOS 27, so treat the Touch ID, Apple Watch and OpenID values as 27 until you have checked. `AttemptAuthentication`, `RequireAuthentication` and `AllowAuthenticationGracePeriod` are for `AuthenticationMethod` `Password` only, and `AllowOfflineGracePeriod` is for `Password` with `RequireAuthentication`, or `OpenID`. `OfflineGracePeriod` and `AuthenticationGracePeriod` are in seconds and are required with the matching Allow option. `NonPlatformSSOAccounts` exempts named local accounts. A `Redirect` payload also needs `URLs`.
- Registration can be silent with `RegistrationToken` (macOS 13). Setup Assistant registration: `EnableRegistrationDuringSetup` and `EnableCreateFirstUserDuringSetup` (macOS 26). Authenticated Guest mode: `NewUserAuthorizationMode` `Temporary` and `TemporarySessionQuickLogin` (macOS 26). New accounts: `NewUserAuthenticationMethods` (`Password`, `SmartCard`, `AccessKey`, `OpenID`).
- `UseSharedDeviceKeys`, `EnableCreateUserAtLogin` and `EnableAuthorization` control on-demand accounts and IdP use at authorisation prompts; group mapping uses `AdministratorGroups`, `AdditionalGroups` and `AuthorizationGroups`.
- The declarative form (`com.apple.configuration.extensible-sso`, 27) restructures the keys: `ExtensionComposedIdentifier` ("Bundle-ID (Team-ID)"), `UserCreation`, `Authorization`, `Policies` (with `FileVault`, `Login` and `Unlock`) and `WebAuthentication`. Read its schema row; do not paste profile key names into it.
- State: `app-sso platform -s` prints the Platform SSO state for the current user (its output is not a documented format); `app-sso platform -m` shows sample messages. The `-l`, `--register` and `-t` options the community lists are Kerberos-mode or do not exist; read `man app-sso`. Logs: the `com.apple.AppSSO` subsystem is the usual place to look.

## Pitfalls

1. APNs push certificate expired (devices stop receiving commands).
2. Deploying a restriction or payload that needs supervision to a user-approved Mac and assuming it applied.
3. Bootstrap token not escrowed, found only when FileVault rotation or a new user fails.
4. Legacy software update profiles left in place for macOS 27 (silently non-functional).
5. Keys copied from blogs without checking Apple's schema (invented payloads such as `com.apple.FDE`).
6. Treating Platform SSO policies as strings or booleans instead of arrays of policy names.
7. `profiles show -type enrollment` in a loop (rate limited).
8. Migrating a fleet before the new service applies equivalent configuration.
9. Assuming a vendor supports a new declaration the day Apple ships it (check the vendor).
10. Losing the Recovery Lock password with no service record.

## Red flags

- A payload key, command or version claim with no Apple schema row or Apple page behind it.
- `mdmclient` or `app-sso` output parsed to make a decision.
- A state-changing `profiles` or service action presented as a check.
- Recovery Lock passwords, bootstrap tokens, SCEP challenges or APNs keys written into a command or script.

## References and scripts

- `references/architecture.md`: the MDM protocol and APNs, DDM building blocks, ADE and Apple Business Manager, supervision, certificates and identity.
- `references/best-practices.md`: a deployment sequence, profile and declaration hygiene, update management, migration checklist, Platform SSO rollout.
- `references/diagnostics.md`: enrolment, profile, declaration and Platform SSO workflows, log subsystems, and the `profiles` tool.
- `scripts/mdm-enrollment.sh`, `profile-inventory.sh`, `certificate-expiry.sh`, `psso-state.sh`: read-only checks. Exit codes: 0 no findings, 1 warnings (this includes any check that could not run, and a command that fails or returns nothing), 2 critical findings. A check that could not run is therefore never a clean pass; an explicit "no configuration profiles installed" answer is reported as information. Exit 2 also means the script aborted on an invalid setting (the message is on standard error), so read the output before reading the code. `psso-state.sh` prints the Platform SSO state and does not judge registration, because Apple documents that output as diagnostic only.

The scripts are POSIX `sh`, read state only, and need root for the device-level views (they warn when not root; `psso-state.sh` under `sudo` reads the state of `$SUDO_USER`). `mdm-enrollment.sh` tests the device-side Apple hosts (TCP only) only when `CHECK_NETWORK=1`. They pass `shellcheck -s sh` and were run against stub commands (empty-result, throwing, healthy and unhealthy worlds; the certificate script against real generated certificates), not on an enrolled Mac, and the output formats they parse come from Apple's documentation and man pages.

## Boundaries

- Everything about the Mac itself: `macos-ops`.
- Tenant-side identity provider work (Entra ID, Okta, Ping): `entra-id`, `okta`, `ping-identity`, `identity-access-management`.
- Intune policy design for Windows: `windows-client-ops`; EDR on the Mac: `defender-for-endpoint`.
- Vendor consoles (Jamf, Kandji, Mosyle, Intune): follow the vendor's documentation; this skill covers what Apple defines.
- Credentials and tokens: `secrets-hygiene`.

## Bottom line

Know the enrolment type, supervision state, macOS version and what the service supports; read Apple's schema row before using a key; verify the bootstrap token; move software updates to declarations before macOS 27; and treat Platform SSO configuration as arrays and dictionaries from Apple's schema, not from memory.
