# macOS device management best practices

Statements here come from Apple's schema and pages unless a line says it is a rule of thumb.

## A deployment sequence for new Macs

1. Buy through Apple or an authorised reseller with the organisation's customer number, or add existing Macs with Apple Configurator (check the current Apple Configurator workflow for adding without a wipe).
2. In Apple Business Manager, assign the serial numbers to the management service; set the enrolment profile (supervised, mandatory, Setup Assistant panes to skip, the first account behaviour).
3. In the service, apply configuration in this order: certificates (root and identity), network (Wi-Fi, VPN, DNS), security (FileVault with escrow, firewall, privacy and system extension approvals, login items), software update declarations, apps and packages, then user experience.
4. Test on a clean Mac of the oldest and newest supported macOS before the fleet. Include an Apple silicon and (while any remain) an Intel Mac.
5. Verify on a pilot Mac: `profiles status -type enrollment`, `sudo profiles status -type bootstraptoken` (supported and escrowed), FileVault state and key escrow, installed profiles, and the first software update declaration.

## Profiles and declarations

- One purpose per profile (Wi-Fi, VPN, certificates, restrictions, Platform SSO), with descriptive display names, so a change touches one thing.
- Unique `PayloadUUID` and stable `PayloadIdentifier`; a repeated UUID fails installation.
- Deliver certificates before the payloads that need them.
- Prefer declarations where Apple provides one: software updates (14 and 15), disk management (15), apps and packages (26), Siri and Apple Intelligence settings (26.4), and VPN, DNS, relay, web content filter and Extensible SSO (27 only); use the `com.apple.configuration.legacy` declaration to carry a profile you cannot yet express natively.
- Read the schema entry for every key you use: macOS version, supervision, whether it is deprecated or removed. Several widely copied keys are not macOS keys or do not exist.
- Keep payloads for the oldest macOS in the fleet and for 27 distinct until the old one is gone; a payload removed in 27 (`com.apple.SoftwareUpdate`) is simply ignored there.

## Software updates

- Use `com.apple.configuration.softwareupdate.enforcement.specific` for a version and deadline and `com.apple.configuration.softwareupdate.settings` for deferrals, automatic actions and beta enrolment. Set deadlines in device local time deliberately and communicate them.
- Remove legacy update profiles and stop sending `ScheduleOSUpdate` before macOS 27 devices arrive (legacy update management no longer functions there).
- Major upgrades: hardware first (27 needs Apple silicon), then app and extension compatibility, a pilot ring, then waves. Apple silicon Macs use the bootstrap token to authorise some installs, so confirm escrow before waves.
- Check the vendor supports each declaration you plan to use; vendors lag Apple by weeks to months.

## FileVault, bootstrap token and Recovery Lock

- Enforce FileVault with the escrow payload; rotate the personal recovery key after any suspected exposure or technician use. `RotateFileVaultKey` needs a `KeyType` and the current `FileVaultUnlock` password, so it is not unattended by itself; Apple describes escrow-triggered rotation on macOS 26 and later when a bootstrap token is present.
- Confirm `sudo profiles status -type bootstraptoken` reports both "supported on server" and "escrowed to server" on every Mac as part of onboarding. An unescrowed token may need `sudo profiles install -type bootstraptoken` with secure-token administrator credentials (a change); the `profiles` man page says it needs a supervised client, so check supervision first.
- Set Recovery Lock on Apple silicon Macs through the service, store the value in the device record, and rotate it on a schedule you can actually run. Remember that un-enrolling removes it.

## Restrictions

Use restrictions for what you must stop, not what you would prefer. Keep a record of each restriction key with its supervision requirement and macOS version from the schema. From macOS 26.4 prefer the declarative Apple Intelligence, Siri and Keyboard configurations to the deprecated `com.apple.applicationaccess` keys. Treat `allowRosettaUsageAwareness` (26.4) as a notice control, not an application block.

## Service migration checklist (macOS 26 and later)

- [ ] Inventory the old service: profiles, declarations, scripts, apps and licence tokens, compliance rules, reports.
- [ ] Build and test the equivalent in the new service, linked to Apple Business Manager.
- [ ] Configure the new service to hold managed apps (the old service must not send app removal on unenrolment) and to install a FileVault escrow configuration.
- [ ] Move volume-purchased app licences (remove the token from the old service, add to the new).
- [ ] Pilot with a few Macs; set a deadline; watch the enforced prompt.
- [ ] After: `profiles status -type enrollment` shows the new server, bootstrap token escrowed to the new service, FileVault key rotated and escrowed, Platform SSO registration intact, declarations from the old service gone.
- [ ] A rollback plan that does not depend on the old service remaining available.

## Platform SSO rollout

1. Deploy the identity provider's app and extension before or with the profile; take `ExtensionIdentifier`, `TeamIdentifier` and the realm and host settings from the provider's documentation.
2. Choose the authentication method per population (`UserSecureEnclaveKey` for existing local accounts without a password prompt, `Password` for password sync, `SmartCard`, `OpenID` on macOS 27). The `AttemptAuthentication`, `RequireAuthentication` and `AllowAuthenticationGracePeriod` policy values apply to `Password` only, so staging step 3 below is a `Password` rollout; with another method, check the schema for the policy values it accepts.
3. For `Password`, add policies in stages: observe with `AttemptAuthentication`, then `RequireAuthentication` once registration is complete, and always set grace periods (`OfflineGracePeriod`, `AuthenticationGracePeriod`) so an outage at the identity provider cannot lock users out. Pick the values from your outage history; Apple does not publish a recommended number.
4. Exempt break-glass local accounts with `NonPlatformSSOAccounts`.
5. For new Macs, use Setup Assistant registration (`EnableRegistrationDuringSetup`, macOS 26).
6. Monitor registration state with `app-sso platform -s` on pilot Macs and the identity provider's logs; macOS 27.0.1 fixed a Lock Screen issue after sleep, so keep pilot Macs current.

## Offboarding and loss

Wipe through the service (an `EraseDevice` command, or Erase All Content and Settings with a bootstrap token on Apple silicon), release the device in Apple Business Manager, remove the Managed Apple Account, rotate any shared credentials, and record Activation Lock status.
