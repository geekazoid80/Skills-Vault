# macOS device management architecture reference

Sources: Apple Platform Deployment guide, Apple's device-management schemas (github.com/apple/device-management, release branch, 2026-09-17), Apple's enterprise network requirements page, the local `profiles` man page. Versions are macOS versions unless stated.

## MDM protocol

An MDM server (the management service) and a device communicate over HTTPS. The server cannot connect to the device: it sends an empty push through the Apple Push Notification service (APNs) to the device's push topic, and the device then connects to the server's command URL, receives the next command, executes it and reports the result. Authentication is by the device's MDM identity (a certificate issued at enrolment) and the server's TLS certificate. A separate check-in URL carries `Authenticate`, `TokenUpdate`, `CheckOut` and related messages (for example `GetBootstrapToken`, `SetBootstrapToken`). The MDM payload (`com.apple.mdm`) in the enrolment profile carries the server URL, the check-in URL, the topic and the identity.

APNs needs the device to reach `*.push.apple.com` on TCP 443, 80, 5223 and 2197 (Apple's enterprise network page); the service owner needs a valid APNs certificate (requested at `identity.apple.com`), which must be renewed before it expires or devices stop receiving commands. Treat the expiry date as an operational alarm.

Commands are named in Apple's schema (for example `DeclarativeManagement` since macOS 13, `EraseDevice`, `RotateFileVaultKey`, `SetRecoveryLock`, `VerifyRecoveryLock`, `SecurityInfo`, `InstallProfile`, `RemoveProfile`). Each schema entry states the macOS version it was introduced, whether it is deprecated or removed, and the access rights the service needs. Commands and payloads carry `supervised`, `requiresdep` and `userapprovedmdm` flags; declarations list `allowed-enrollments` (for example `supervised`, `user`, `local`). The software update commands (`ScheduleOSUpdate`, `AvailableOSUpdates`) were deprecated in 26 and removed in 27.

## Declarative device management

DDM adds a second channel to the same enrolment. The service describes desired state in declarations; the device downloads a manifest, then each declaration by token, applies the ones whose activations are satisfied, and reports status.

- **Configurations** describe settings (software update enforcement, apps, packages, Wi-Fi, VPN, restrictions, Platform SSO, and so on).
- **Activations** bind configurations to a predicate, such as a status value or a simple condition, so a configuration applies only when it should.
- **Assets** carry data a configuration references, such as a certificate or a legacy profile (macOS 27 lets the legacy declaration reference an asset).
- **Management declarations** carry organisation metadata and status subscriptions.
- **Status** items and reports flow from the device without polling: install states, software update state, FileVault state (`diskmanagement.filevault.enabled`), and in macOS 27 the enrolment type, Lockdown Mode state and whether the device is waiting in Setup Assistant for the service.

The `DeclarativeManagement` command bootstraps the exchange. The `com.apple.configuration.legacy` declaration (macOS 13) carries an existing profile through DDM so a service can migrate payloads that lack a declaration. DDM does not replace commands for erase, lock or app licensing; services use both.

## Enrolment and supervision

- **Automated Device Enrollment (ADE)**: serial numbers purchased from Apple or an authorised reseller (or added through Apple Configurator) appear in Apple Business Manager. An administrator assigns them to a management service. At activation the Mac contacts `albert.apple.com`, then retrieves the enrolment profile from `iprofiles.apple.com`; the service uploads enrolment profile definitions through `mdmenrollment.apple.com`. ADE devices are supervised, and the profile can be mandatory. Setup Assistant panes can be skipped by the service.
- **Device Enrollment (user approved)**: the user installs the enrolment profile and approves it; many features work, supervision-only features do not.
- **Account-driven User Enrollment**: the user signs in with a Managed Apple Account in System Settings; profile-based User Enrollment was removed in macOS 15.
- **Supervision** marks an organisation-owned device. Apple's schema marks each payload and command with `supervised`, `requiresdep` and `userapprovedmdm` flags for macOS, and each declaration with `allowed-enrollments`; read them rather than inferring. The software update, package and Migration Assistant declarations list `supervised` only.

## Apple Business Manager and Apple School Manager

The portal assigns devices to services, buys and distributes apps and books (device-assigned licences need no Apple Account on the device), federates the organisation's identity provider so users get Managed Apple Accounts (provisioned from the identity provider by SCIM), sets enrolment deadlines for service migration, and exposes admin APIs. Apple's current documentation names the product "Apple Business" alongside Apple School Manager. Platform SSO and Managed Apple Accounts are separate mechanisms: a user can have either without the other.

## Device identity, certificates and tokens

The MDM identity certificate is issued at enrolment (often by SCEP or ACME); on Apple silicon the private key can be held in the Secure Enclave. SCEP, ACME, PKCS #1 and PKCS #12 payloads deliver other certificates; ACME and SCEP credential declarations gained "available only after first unlock" controls in macOS 27. Managed Device Attestation lets a service verify that a device and its key are genuine.

The **bootstrap token** is escrowed to the service and lets macOS grant secure tokens to accounts without an administrator's credentials; on macOS 26 and later it is created at enrolment when the service supports it. See the skill for what depends on it.

## Platform SSO architecture

The Extensible SSO payload names an app extension supplied by the identity provider. In Platform SSO the extension registers the device and the user with the identity provider, receives tokens that unlock the local account (password, a Secure Enclave key, a smart card, and in macOS 27 OpenID web login), and brokers tokens to apps and the browser. The login window, FileVault pre-boot screen and Lock Screen can use the identity credential under the policies configured. The payload keys and the version each arrived in are in the skill and in Apple's `com.apple.extensiblesso` schema.
