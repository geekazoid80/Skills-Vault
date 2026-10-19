# macOS device management diagnostics reference

Read-only unless marked (rows marked as a change update local or server state). Options were checked against the `profiles`, `fdesetup` and `app-sso` man pages on macOS 26.7.1.

## The profiles tool

| Command | Use | Notes |
|---|---|---|
| `profiles status -type enrollment` | Local enrolment state; shows "(User Approved)" for user-approved MDM | Cheap; safe to repeat |
| `profiles show -type enrollment [-cached]` | Server-side enrolment (ADE) information | Rate limited to 10 per 23 hours; `-cached` reads the local cache |
| `profiles status -type bootstraptoken` | Is the token supported on the server, and escrowed | Run as root |
| `profiles list [-type configuration] [-user name] [-output path]` | Profile list for the user; as root, the device | `-output` takes a file path |
| `profiles show -type configuration` | Expanded profile and payload detail | Large; contains settings |
| `profiles validate -type enrollment` | Re-validate the installed ADE server information | A change: updates local information and contacts the server; rate limited |
| `profiles renew -type enrollment` | Retry fetching the enrolment configuration | A change; rate limited |
| `profiles sync -type configuration` | Remove profiles belonging to users that no longer exist | A change |
| `profiles install -type bootstraptoken` | Generate and escrow a token | A change; needs secure-token admin credentials |

`profiles` cannot install configuration profiles since macOS 11; `profiles validate -path` validates **provisioning** profiles, not configuration profiles. For the other `-type` values the man page lists `configuration`, `provisioning`, `bootstraptoken` and `enrollment`.

## Logs

Subsystems seen in practice (confirm with `log stream` on your build): `com.apple.ManagedClient` (MDM client and profiles), `com.apple.AppSSO` and `com.apple.AuthenticationServices` (Platform SSO and the token broker), `com.apple.loginwindow` (login window), `com.apple.SoftwareUpdate`.

```sh
log show --last 1h --predicate 'subsystem == "com.apple.ManagedClient"'
log stream --predicate 'subsystem == "com.apple.ManagedClient" AND eventMessage CONTAINS[c] "declaration"'
log show --last 2h --predicate 'subsystem == "com.apple.AppSSO"'
```

Use `--info` and `--debug` when you need those levels. Logs can contain account names and URLs; review before sharing.

## Enrolment workflows

### ADE does not start at Setup Assistant

1. In Apple Business Manager, is the serial number present, assigned to the right service and current? Was it assigned before the Mac was activated, or does it need an erase to re-run activation?
2. Network: can the Mac reach `albert.apple.com`, `iprofiles.apple.com` and `deviceenrollment.apple.com` on 443, and `*.push.apple.com`? (Apple's enterprise network page; `CHECK_NETWORK=1 sh scripts/mdm-enrollment.sh` makes a TCP connection to the three named hosts only, so it cannot see a proxy or TLS inspection that breaks the handshake.) A proxy or TLS inspection that breaks these is a common cause. `mdmenrollment.apple.com`, `gdmf.apple.com` and `identity.apple.com` are the management service owner's to reach, not the Mac's.
3. Time: a badly wrong clock breaks certificate validation. `date` against a trusted source; `sntp <server>` reports the offset (its man page describes `-S` and `-s` as the options that set or slew the clock, so never add them on a managed Mac).
4. The service: the enrolment profile defined and assigned in the service; the ADE token (server token) not expired.

### The Mac enrolled but gets no commands

1. APNs: the service's push certificate expired or the topic does not match. Check the expiry in the service console first.
2. `profiles status -type enrollment` shows the right server? `log show --last 1h --predicate 'subsystem == "com.apple.ManagedClient"'` for rejected or failed commands.
3. Identity: SCEP or ACME issuance failed, so the MDM identity is missing or expired. `scripts/certificate-expiry.sh` lists expiring system keychain certificates and `CERT_FILTER` narrows by subject, but it cannot tell which certificate is the MDM identity; find that subject in the service first.
4. Network path to the service's command URL.

### Profile or payload not applied

1. Enrolment type and supervision against the schema row for each key.
2. macOS version against `introduced`, `deprecated` and `removed` in the schema.
3. Order and dependencies (certificate before Wi-Fi, root before identity).
4. Duplicate `PayloadUUID`, bad plist, or a payload that is user-channel only sent to the device channel.
5. `sudo profiles show -type configuration` to see what actually landed; `/Library/Managed Preferences` shows the resulting managed domains.

### Declaration not activating

1. The service supports that declaration type and sent the `DeclarativeManagement` command at enrolment.
2. The macOS version supports the declaration (schema `introduced`).
3. The activation predicate matches current device state; check the status channel in the service for errors.
4. Logs from `com.apple.ManagedClient` mentioning the declaration identifier.

### Bootstrap token not escrowed

1. `sudo profiles status -type bootstraptoken`: "supported on server: NO" means the service does not support it; "YES" with "escrowed: NO" means this Mac has not escrowed it.
2. On a Mac enrolled by profile, `sudo profiles install -type bootstraptoken` with secure-token administrator credentials (a change; never put the password on a command line in a script).
3. On macOS 26 and later enrolment normally creates it; if it does not, check the service version and whether the enrolment was ADE.

## Platform SSO workflows

1. State: `app-sso platform -s` as the logged-in user. Apple documents it as diagnostic only, so read it by eye (registration, the realm, token times) and do not parse it in automation; `scripts/psso-state.sh` prints it and does not judge it.
2. Profile: is a `com.apple.extensiblesso` payload present (`sudo profiles show -type configuration | grep extensiblesso`), and on macOS 27 an `extensible-sso` declaration? Is the identity provider's app installed and its extension identifier and team identifier correct?
3. Policies: `FileVaultPolicy`, `LoginPolicy` and `UnlockPolicy` must be arrays of policy names; a string or dictionary is ignored or rejected. Grace periods set and in seconds.
4. Registration stuck or repeated: check the identity provider's device and user records, the extension's logs, and macOS 26.6 (fixed unexpected re-registration) or 27.0.1 (fixed Lock Screen fields after sleep) for known fixes.
5. Network at the login window: the identity provider's hosts must resolve and connect before login; macOS 27 adds network and captive network controls for login and unlock.
6. Lockout recovery: a local administrator exempt through `NonPlatformSSOAccounts`, or the FileVault recovery key escrowed in the service.

## FileVault checks

`fdesetup status`, `fdesetup list`, `fdesetup haspersonalrecoverykey`, `fdesetup hasinstitutionalrecoverykey`, and in the service the escrowed key's date. `fdesetup validaterecovery` prompts for a key and tests it (an interactive check; do it in a maintenance window).

## Recovery Lock

There is no local command that shows the Recovery Lock password. `VerifyRecoveryLock` from the service checks that a given value is set. If the password is lost and the service record is gone, the Mac needs an Apple-supported recovery route; this is the reason to store it in the service record and test retrieval.
