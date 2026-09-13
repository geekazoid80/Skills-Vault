---
name: powershell-module-compat
description: Use before installing, importing, or running any PowerShell module for an M365 / Entra / Exchange Online / Microsoft Graph / Power Platform / Azure operation, especially on pwsh 7 (PowerShell Core) on macOS or Linux (the NUC). Fires on symptoms - "The term '<cmdlet>' is not recognized" after a successful Import-Module; a module that imports with an "unapproved verbs" warning but whose cmdlets are then missing; Add-PowerAppsAccount / Test-PowerAppsAccount / New-PowerAppManagementApp not found; an M365 module that "installs fine but does nothing"; Desktop-vs-Core or Windows-PowerShell-5.1-vs-pwsh-7 edition mismatch. NOT for guaranteed Windows PowerShell 5.1 environments, NOT for non-PowerShell tooling. Covers the pre-flight check (PSVersion + $IsWindows + CompatiblePSEditions + Get-Command the SPECIFIC cmdlet after import) and the three escape hatches (Windows PowerShell 5.1, the REST API with an az-cli / MSAL / cert-JWT token, or a cross-platform module), plus the known M365 traps (Power Platform admin modules, EXO cert-file-vs-thumbprint, Graph X509Certificate2). ALSO covers the adjacent bash-vs-pwsh shell-syntax trap - pasting unix command syntax into a PowerShell prompt - symptoms "Missing property name after reference operator", "The term '-H' is not recognized", "could not be loaded ... Import-Module 'TOKEN=...'", a multi-line curl / scp / ssh failing on the second line, a bash $(...) / VAR= assignment / backslash line-continuation / export / heredoc rejected at a PS> prompt; fix by running unix commands in zsh/bash or translating REST calls to Invoke-RestMethod -Headers @{}. ALSO covers the SharePoint-admin-from-Linux escape - the Windows-only SharePoint Online Management Shell (Set-SPOUser -IsSiteCollectionAdmin) does not run on pwsh 7, and PnP.PowerShell admin cmdlets (Set-PnPTenantSite -Owners, Add-PnPSiteCollectionAdmin) return 'unauthorized' on Linux even with a correct SharePoint-audience token and full admin roles (pnp/powershell #889, systemic since 2024-05-09), so both route to CLI for Microsoft 365 (@pnp/cli-microsoft365, a Node.js tool, m365 spo site admin add/remove --asAdmin). ALSO covers the single-item-collection-return trap - a function that builds a List/array and returns it with a bare `return $list` unwraps to a bare scalar at the caller when the collection holds exactly one element (0 or 2+ elements return the real collection type), so `$result.Count` still reads 1 but a later range-index slice (`$result[0..0]`) on the collapsed scalar silently returns empty with no error; fix with the unary comma operator, `return ,$list`.
---

# PowerShell module compatibility pre-flight

> **Skill marker**: begin your reply with `[skill: powershell-module-compat]` on its own line.

## Overview

M365 / Azure / Power Platform PowerShell modules are frequently built for **Windows
PowerShell 5.1 (Desktop edition)** and carry Windows-only assumptions. On **pwsh 7
(Core) on macOS or Linux** they often `Import-Module` cleanly, then their cmdlets are
silently absent or their auth layer never loads. `Install-Module` succeeding proves
nothing. **Check compatibility before you rely on a cmdlet, do not install-and-try.**

Core principle: module *presence* is not cmdlet *availability*. Verify the exact cmdlet
exists on the exact host before building on it.

## The pre-flight (run BEFORE the real command)

```powershell
$PSVersionTable.PSVersion          # 7.x = Core; 5.1 = Windows PowerShell (Desktop)
$IsWindows                         # $false on the Mac / NUC
Get-Module <module> -ListAvailable | Select-Object Name, Version, CompatiblePSEditions
Import-Module <module>
Get-Command <the-exact-cmdlet-you-need>   # THE test: does it actually exist here?
```

- `CompatiblePSEditions` listing only `Desktop` (no `Core`) => it will not work on pwsh 7. Stop.
- The "unapproved verbs" warning on import is NOT success; it just means something loaded.
  Always follow it with `Get-Command <cmdlet>`. Empty output = the cmdlet is not there.
- Test the SPECIFIC cmdlet, not the module. A module can export command A while its internal
  helper B (in a Windows-only auth assembly) is missing, so A fails at runtime.

## The three escape hatches (when pre-flight fails on pwsh 7 / non-Windows)

1. **Windows PowerShell 5.1** on a Windows box. Fastest when a Windows host is available.
2. **Go straight to the REST API.** Most admin cmdlets are thin wrappers over a documented
   endpoint. Get a token (az-cli `az account get-access-token --resource <aud>`, MSAL, or a
   cert-JWT client assertion) and call the endpoint directly. Fully cross-platform, no module.
3. **Use the cross-platform-supported module variant** where one exists (e.g. the Graph SDK and
   `ExchangeOnlineManagement` support Core; the legacy PowerApps admin modules do not).

## Known M365 traps (verified)

| Module / task | Trap on pwsh 7 / Linux | Cross-platform route |
|---|---|---|
| `Microsoft.PowerApps.Administration.PowerShell` + `.PowerShell` (register mgmt app, `New-PowerAppManagementApp`) | Imports with warning, but `Add-`/`Test-PowerAppsAccount` never load, so the cmdlet can't find its helper | REST: `PUT https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/adminApplications/{appId}?api-version=2020-06-01` with an `https://service.powerapps.com/` token |
| Exchange Online app-only on Linux | `-CertificateThumbprint` needs the Windows cert store (absent) | `Connect-ExchangeOnline -CertificateFilePath <pfx> -CertificatePassword <secure>` |
| Microsoft Graph app-only | thumbprint-from-store assumptions | Pass the loaded object: `Connect-MgGraph -Certificate $x509` |
| Signing a cert-JWT client assertion by hand (app-only token minting, any M365/Power Platform REST) | `$cert.GetRSAPrivateKey()` throws "does not contain a method named 'GetRSAPrivateKey'": it is an **extension method** (`RSACertificateExtensions`), which pwsh will not dispatch as an instance call. Silent-failure risk: if the signing sits inside a `try/catch`, the token mint fails and the whole surface returns empty with no error | Call the **static** form: `[System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)`, then `.SignData(bytes, [HashAlgorithmName]::SHA256, [RSASignaturePadding]::Pkcs1)`. (`$cert.GetCertHash()` IS a real instance method and works.) |
| `MicrosoftTeams` module, `Connect-MicrosoftTeams` on macOS / Linux (pwsh 7) | Module installs and imports fine (Core build, e.g. 7.9.0), then `Connect-MicrosoftTeams` throws `Unable to load shared library 'kernel32.dll' or one of its dependencies` at connect time: the connect path P/Invokes a Windows-only system library for its token cache / auth broker, so `Install-Module` succeeding proves nothing and the whole `Get-Cs*` federation / external-access / policy surface is unreachable. Seen on 7.9.0; a version regression, not a one-off | For a one-off read, skip PowerShell: the **Teams admin centre GUI** holds the same values (External collaboration -> External access -> **Organization settings** tab = the tenant `Get-CsTenantFederationConfiguration` values like `AllowTeamsConsumer`; the **Policies** tab = the per-user `Get-CsExternalAccessPolicy` set). For scripting: try `Connect-MicrosoftTeams -UseDeviceAuthentication` (device-code flow can avoid the broker); else run from Windows PowerShell 5.1; else pin a known cross-platform module version |
| SharePoint Online site administration on Linux (add / list / remove a site-collection admin, set a site LockState) | The SharePoint Online Management Shell (`Set-SPOUser -IsSiteCollectionAdmin`) is **Windows-only** and will not run on pwsh 7, and PnP.PowerShell's admin cmdlets (`Set-PnPTenantSite -Owners`, `Add-PnPSiteCollectionAdmin`) return `unauthorized` on Linux **even with a correct SharePoint-audience token and every admin role present**: a confirmed PnP bug (pnp/powershell #889 / discussion #3897, systemic since 2024-05-09), not a permission gap on your side. Reinstalling or re-consenting does not help | **CLI for Microsoft 365** (`@pnp/cli-microsoft365`), a **Node.js** tool (not a PowerShell module), which is unaffected and cross-platform: `npm i -g @pnp/cli-microsoft365`, `m365 login --authType deviceCode`, then `m365 spo site admin add --siteUrl <url> --userName <upn> --asAdmin` (and `list` / `remove`). `--asAdmin` uses the admin-centre path, which breaks the need-access-to-grant-access loop. Runs at a bash/zsh prompt, not `PS>` |

## Shell syntax: you are in pwsh, not bash

A separate but adjacent trap in the same context: pasting **bash / zsh command syntax into a pwsh prompt**.
pwsh is not bash; they disagree on line-continuation, variable assignment, and how external-command flags
parse. Symptoms: `Missing property name after reference operator` (pwsh read `.17` in an IP/URL as a member
access); `The term '-H' is not recognized`; `could not be loaded ... Import-Module 'TOKEN=$(...'`; a
multi-line `curl` / `scp` / `ssh` that errors on the second line (the `\` was not a continuation).

| bash / zsh | pwsh |
|---|---|
| `VAR=$(cmd ...)` | `$VAR = cmd ...` (or `$VAR = (cmd ...)`) |
| line-continuation `\` at end of line | backtick `` ` `` at end of line, or put it on ONE line |
| `curl -H "A: b" -H "C: d" URL` | keep on one line, or better `Invoke-RestMethod -Uri URL -Headers @{ A='b'; C='d' }` |
| `export X=y` | `$env:X = "y"` |
| heredoc `<<EOF ... EOF` | here-string `@" ... "@`, or just avoid |

Rules of thumb:
- For `scp` / `curl` / `ssh` / `$(...)` / heredocs, run them in a plain **Terminal (zsh)**, not the pwsh
  prompt. Reserve pwsh for actual PowerShell cmdlets (`Invoke-RestMethod`, `Connect-MgGraph`, `Set-Mailbox`).
- If you must stay in pwsh, collapse multi-line unix commands to ONE line (no `\`) and translate REST calls
  to `Invoke-RestMethod` with a `-Headers @{}` hashtable instead of `curl -H`.
- When handing commands to a user, read their prompt first: `PS ...>` is pwsh, `user@host:~$` is bash/zsh.
  Match the command syntax to the prompt they are actually at.

## Single-item collection return silently unwraps to a scalar

A separate, general PowerShell trap, not specific to M365/module compatibility, but caught by the
same pre-flight discipline of testing the exact case rather than trusting the happy path: a function
that builds a `[System.Collections.Generic.List[object]]` (or any array) and returns it with a bare
`return $list` gets **unwrapped to a bare scalar at the caller when the collection holds exactly one
element** (0 or 2+ elements return the real collection type unchanged).

- **Why it's dangerous rather than merely surprising:** the caller's `$result.Count` still reads `1`
  (PowerShell gives every object a synthetic `.Count` member), so nothing looks wrong. The defect
  only shows up if the caller then does something that depends on the object actually being a
  collection: a range-index slice (`$result[0..0]`) on the collapsed scalar silently returns EMPTY
  rather than the one item, with no error and no exception.
- **Fix:** `return ,$list` (the unary comma operator) forces the object through as the collection it
  is, regardless of element count.
- **Who is safe:** a caller that only ever does a plain `foreach ($x in $result)` is unaffected
  either way (it iterates a scalar once, functionally identical to a 1-element array). The risk is
  index access, range slicing, `.Count`-gated branching, or piping into something that behaves
  differently for a scalar vs. an array.
- **Test the 1-item case explicitly.** A happy-path test using 0 or 2+ items will never catch this;
  only an exactly-one-item input exercises the collapse.

## Red flags

- Pasting a bash `$(...)`, `\` line-continuation, `export`, heredoc, or `curl -H` command into a `PS>` prompt
  (run it in zsh/bash, or translate to pwsh).
- Handing a user a multi-line unix command without checking whether their prompt is `PS>` or `$`.
- About to `Install-Module` a Power Platform / M365 admin module on the Mac or NUC without
  checking `CompatiblePSEditions` first.
- Treating an "unapproved verbs" import warning as success.
- Retrying `Install-Module` / `Import-Module` after a "term is not recognized" error, instead
  of concluding the edition/platform is wrong.
- An `Unable to load shared library 'kernel32.dll'` (or any Windows DLL) error from an M365 module
  cmdlet on macOS/Linux: that code path P/Invokes a Windows-only library. Do not retry or reinstall;
  switch to the GUI / REST / Windows route. (Seen on `Connect-MicrosoftTeams` 7.9.0.)
- Assuming a cmdlet exists because the module "installed fine".
- Reaching for `-CertificateThumbprint` on a Linux/macOS host.
- A function returning a built-up List/array with a bare `return $list`, where the caller does
  anything more than a plain `foreach` over the result: check the 1-item case explicitly, since
  0- and 2+-item returns hide the collapse.

## Bottom line

Before running a PowerShell M365/Azure/Power Platform op on pwsh 7 or non-Windows: check
PSVersion, `$IsWindows`, `CompatiblePSEditions`, and `Get-Command <the-cmdlet>`. If it's
Desktop-only, don't fight the module, drop to Windows PS 5.1 or the REST API. Module installed
is not cmdlet available.
