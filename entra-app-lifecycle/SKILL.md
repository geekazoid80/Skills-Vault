---
name: entra-app-lifecycle
description: "Use for any Microsoft Entra ID (formerly Azure AD) app-registration lifecycle work, OAuth 2.0 flow choice and integration, MSAL setup, service principal creation, API permission grants, or token validation. Triggers include \"register an Azure AD app\", \"create app registration\", \"Entra ID app\", \"service principal\", \"configure OAuth\", \"MSAL setup\", \"Microsoft Graph permissions\", \"client secret\", \"client certificate\", \"federated identity credential\", \"managed identity vs app registration\", \"redirect URI\", \"consent screen\", \"admin consent\", \"token audience\", \"AADSTS error\", \"Bicep app registration\", \"az ad app create\", \"OBO flow\", \"device code flow\", \"PKCE flow\", \"client credentials flow\". Covers: app type selection (web / SPA / native / daemon / mobile) maps onto an OAuth flow; portal / CLI / Bicep registration paths (Bicep preferred for any non-throwaway tenant); credential discipline (federated identity > certificate > secret > nothing) hooked into `secrets-hygiene`; least-privilege permission grants; sign-in monitoring. Customised from microsoft/azure-skills/entra-app-registration (MIT)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Entra ID app lifecycle

Microsoft Entra ID (formerly Azure Active Directory) is Microsoft's identity and access management cloud. An **app registration** is the configuration object that lets a workload (web app, daemon, CLI, agent) authenticate to the Microsoft identity platform and ask for tokens against Microsoft Graph or your own resource APIs. The app registration plus the **service principal** (the per-tenant identity it spawns) plus the **credential** (secret / certificate / federated identity credential) are the three things that actually exist after you "register an app".

This skill covers the full lifecycle: pick the app type, register it the right way, grant the smallest viable set of permissions, attach the right credential, integrate with MSAL, and verify before claiming done.

> **Skill marker**: When applying this skill, begin your reply with `[skill: entra-app-lifecycle]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Entra ID tenant (admin posture, app-registration governance, conditional-access surface, audit requirements) before commanding the directory. Only ask the user for information not already covered or specific to this app.

Before commanding the directory, understand:

1. **Tenant and authority**
   - Single-tenant or multi-tenant app target?
   - Admin role available (Application Admin, Cloud App Admin, Global Admin)?
   - Tenant-wide conditional-access policies that affect grant flow?

2. **App type and flow**
   - Web app, SPA, mobile / native, daemon / service, or hybrid?
   - OAuth flow per surface (auth-code + PKCE, client credentials, device code)?
   - Delegated, app, or hybrid permissions?

3. **Lifecycle context**
   - Net-new registration, change to an existing app, or secrets / cert rotation?
   - Downstream consumers that need notice of any breaking change?
   - Audit / compliance scope (consent governance, PIM, access reviews)?

---

## Concept primer (one table, scan once, return when stuck)

| Concept | What it actually is |
|---|---|
| App registration | The application object in your tenant. Holds redirect URIs, requested permissions, optional credentials, branding. |
| Application (client) ID | The GUID identifying the app registration. Goes in code. Public; not a secret. |
| Tenant ID | The GUID identifying your directory. Public; not a secret. |
| Service principal | The per-tenant identity that the app registration spawns when first consented. Role assignments target this, not the app registration. |
| Client secret | A password attached to the app registration. Time-limited (max 24 months as of writing). Last-resort credential type. |
| Certificate credential | A public key attached to the app registration; the workload signs an assertion with the matching private key. Better than a secret. |
| Federated identity credential (FIC) | A trust between the app registration and an external token issuer (GitHub Actions, AKS, EKS, GCP, another Entra workload). The workload presents an issuer-signed token; Entra returns a Microsoft token. **No long-lived credential to rotate.** First choice when available. |
| Managed identity | Different beast: an identity Azure manages for you, attached to an Azure resource (VM, Function, AKS pod). For Azure-hosted workloads, prefer this over an app registration entirely. |
| Redirect URI | The URL Entra returns the auth code / token to. Must match exactly; HTTPS only (localhost exception). |
| API permission | A scope or app role the app requests. Delegated (acts as user) or Application (acts as itself). |
| Admin consent | Required for any Application permission and for high-privilege Delegated permissions. Only a tenant admin can grant it. |

## App type maps to OAuth flow

Pick the app type first. The OAuth flow follows from it.

| App type | Recommended flow | Key constraint |
|---|---|---|
| Server-rendered web app | Authorization Code with PKCE | Has a backend; can hold a client secret or certificate. |
| Single-page app (React, Angular, Vue) | Authorization Code with PKCE | No backend secret; PKCE is mandatory; refresh tokens delivered via SPA flow only. |
| Native / mobile / desktop | Authorization Code with PKCE | Public client; PKCE mandatory; redirect URI is custom scheme or `http://localhost`. |
| Daemon / cron / service-to-service | Client Credentials | No user. Uses Application permissions (admin consent required). FIC > certificate > secret. |
| CLI / dev tool | Device Code | No browser available locally; user completes the auth on another device. |
| Web API calling another API on behalf of the user | On-Behalf-Of (OBO) | Receives a user token, exchanges for a token to the downstream API. |
| GitHub Actions, AKS pod, GCP workload calling Microsoft Graph | Federated Identity Credential + Client Credentials | Workload identity federation; **no secret stored anywhere**. |

If two flows could fit, the rule of thumb is: **pick the one where no long-lived secret has to exist on disk anywhere**. That usually means FIC (when the caller is itself a federated workload), or managed identity (when the caller is an Azure resource), or PKCE (when there is no backend at all).

## Lifecycle: the six steps

### 1. Decide the app type

The first decision drives every subsequent one. Get it wrong and you end up with a daemon that uses Authorization Code, or an SPA that ships a client secret in JavaScript. If unsure between two app types, use AskUserQuestion and surface the two flows side by side.

### 2. Register the app

Three paths, in order of preference for any non-throwaway tenant.

**Bicep (IaC).** First choice. Audit history, repeatable, scales to many tenants and many environments. Snippet shape (the Microsoft upstream ships a complete `BICEP-EXAMPLE.bicep`):

```bicep
extension microsoftGraphV1
resource entraApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'my-app-uniquename'
  displayName: 'My app'
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: ['https://my-app.example.com/auth/callback']
    implicitGrantSettings: { enableIdTokenIssuance: false, enableAccessTokenIssuance: false }
  }
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000'  // Microsoft Graph
      resourceAccess: [
        { id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d', type: 'Scope' }  // User.Read
      ]
    }
  ]
}
```

**Azure CLI.** Acceptable for one-off creation, exploratory work, and tooling glue.

```bash
az ad app create --display-name "My app" --sign-in-audience AzureADMyOrg
az ad sp create --id <app-id>
az ad app permission add --id <app-id> --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
az ad app permission grant --id <app-id> --scope User.Read --api 00000003-0000-0000-c000-000000000000
```

**Portal.** Last resort. No audit trail, no reproducibility. Acceptable only for first-time learning or for a single throwaway tenant.

### 3. Configure authentication

Set the redirect URIs and platform configuration that match the app type.

| App type | Redirect URI shape | Notes |
|---|---|---|
| Web | `https://your-app.example.com/auth/callback` | HTTPS only. Multiple URIs allowed (one per env), but list every one explicitly. |
| SPA | `https://your-app.example.com/` | Configured under "Single-page application" platform, **not** "Web". Different platform = different token delivery. |
| Native / desktop / mobile | `http://localhost`, `myapp://callback`, or `https://login.microsoftonline.com/common/oauth2/nativeclient` | Custom scheme requires deep-link registration in OS; `http://localhost` works for the loopback flow. |
| Daemon | None required | Client credentials flow does not redirect. |

Disable implicit grant unless you have a documented reason. The default Bicep / portal ask you about this; the safe answer is **no**.

### 4. Grant the smallest set of API permissions

Two kinds of permission. They are not interchangeable.

- **Delegated.** App acts on behalf of a signed-in user. The effective permission is the intersection of (user's actual rights) and (app's requested scope). Use for any user-facing app.
- **Application.** App acts as itself, no user. The effective permission is exactly what was granted, applied tenant-wide. **Always requires admin consent.** Use for daemons.

Practical discipline:

1. Start from the app's actual API calls. Map each endpoint to the smallest scope that lets it work. Microsoft Graph permission reference is the source of truth.
2. Never grant `Directory.ReadWrite.All` because the app "might need it later". Add it when an actual call needs it; remove it when the call is removed.
3. Application permissions need admin consent. Plan the admin-consent step into the deployment flow; do not assume the developer doing the registration has tenant-admin rights.
4. For multi-tenant apps, the publisher tenant grants nothing for the consumer tenant. Each consumer's admin grants consent on first install. Build the admin-consent URL into your installer.

### 5. Attach the right credential

Hard preference order. Climb the ladder as far as your environment allows.

1. **Managed identity.** If the workload runs on an Azure resource (VM, Function, App Service, AKS pod), use the resource's managed identity directly. Skip the app registration entirely; no credential to manage.
2. **Federated identity credential (FIC).** If the workload runs on GitHub Actions, AKS / EKS / GKE with workload identity, another Entra tenant, or anywhere with an OIDC-issuing trust, configure FIC on the app registration. Workload presents its OIDC token; Entra returns a Microsoft token. **No long-lived credential exists.**
3. **Certificate.** Generate a key pair; upload the public key to the app registration; store the private key in Key Vault (or HSM, or platform keystore). The workload signs a JWT assertion with the private key.
4. **Client secret.** Last resort. Generate via portal or `az ad app credential reset`. The value is shown **once**; copy it immediately into Key Vault. Set the shortest expiration the workload tolerates; treat the rotation date as a hard deadline (see `secrets-hygiene` for the rotate-in-place pattern).

When a credential is created, three follow-ups happen the same day:

- The value goes into Key Vault (or the equivalent secret store) and the workload reads it from there at runtime, not from a `.env` baked into an image.
- The expiration date goes into a calendar reminder or alerting system, set to fire at least 30 days before expiry. A surprise-expired credential is a self-inflicted incident.
- The PR that ships the credential reference does **not** contain the value (see `secrets-hygiene` red flags).

### 6. Integrate with MSAL

The Microsoft Authentication Library is the supported integration path. Hand-rolling the OAuth flow is a recipe for token-validation bugs; do not.

| Language | Library |
|---|---|
| .NET / C# | `Microsoft.Identity.Client` |
| Python | `msal` |
| Node.js / TypeScript (server) | `@azure/msal-node` |
| Browser / SPA | `@azure/msal-browser` |
| Java | `msal4j` |

Three things MSAL does that you should not reimplement: token caching (in-memory plus optional persistent), refresh-token rotation, and token validation (issuer, audience, expiration, signature). If you find yourself parsing a JWT manually to "just check the audience", use `AcquireTokenSilent` or the framework-supplied middleware instead.

For Azure-hosted workloads, prefer `Azure.Identity` (or `azure-identity`) which wraps MSAL plus the managed-identity providers behind a single `DefaultAzureCredential` chain. The chain tries managed identity first, falls back to environment variables, then to interactive auth. This is what makes the same code work locally (developer credential) and in production (managed identity) without conditional logic.

## OAuth flow quick reference (the two you will use most)

### Authorization Code with PKCE (web, SPA, native)

```
1. App: generate code_verifier (random 43-128 chars) and code_challenge = base64url(sha256(code_verifier))
2. App -> Entra: redirect user to /authorize with client_id, redirect_uri, scope, state, code_challenge, code_challenge_method=S256
3. User: authenticates and consents at login.microsoftonline.com
4. Entra -> App: redirect to redirect_uri with ?code=...&state=...
5. App: validates state matches what was sent (CSRF check)
6. App -> Entra: POST /token with code, code_verifier, redirect_uri, client_id, (client_secret if confidential)
7. Entra -> App: { access_token, refresh_token, id_token, expires_in }
8. App: stores tokens in MSAL cache; calls API with Bearer access_token
```

State validation is mandatory. Skipping it is a CSRF hole.

### Client Credentials (daemon, service-to-service)

```
1. App -> Entra: POST /token with client_id, client_secret OR client_assertion (cert/FIC), grant_type=client_credentials, scope=https://graph.microsoft.com/.default
2. Entra -> App: { access_token, expires_in }
3. App: caches token until expiry; calls API with Bearer access_token; refreshes when expired
```

Note the `.default` scope. Client Credentials always requests the **statically consented** Application permissions, not delegated scopes. There is no user, so there is no consent screen at runtime; consent must already be granted by an admin.

## Common AADSTS errors (the ones you will hit)

| Code | Meaning | Fix |
|---|---|---|
| AADSTS50011 | Redirect URI mismatch | The redirect URI in the request does not match exactly what is registered. Check trailing slashes, http vs https, port number. |
| AADSTS65001 | The user or admin has not consented | Run admin consent (portal "Grant admin consent" or `az ad app permission admin-consent`), or add `prompt=consent` to the auth URL once. |
| AADSTS70011 | Invalid scope | The scope requested is not granted to the app, or the scope value is malformed. Check for typos and the `https://graph.microsoft.com/` prefix on `.default`. |
| AADSTS7000215 | Invalid client secret | Secret is wrong or expired. Rotate via Key Vault, not by emailing a new value around. |
| AADSTS9002313 | Invalid request payload | Usually a missing or wrong-cased parameter in the token request. Common with hand-rolled flows; another argument for MSAL. |
| AADSTS50058 | Silent sign-in failed (no session) | Expected when the user has no active session; fall through to interactive auth. Not a real error. |

## Multi-tenant vs single-tenant

The `signInAudience` field on the app registration decides. Four values:

- `AzureADMyOrg`: only your tenant. Default. Pick this unless there is a specific reason not to.
- `AzureADMultipleOrgs`: any work / school account in any tenant. Each consumer tenant's admin grants consent on first sign-in.
- `AzureADandPersonalMicrosoftAccount`: above plus personal Microsoft accounts.
- `PersonalMicrosoftAccount`: personal accounts only.

Do not switch from single to multi-tenant without thinking through admin-consent flow, the `tid` claim handling in your token-validation code, and the tenant-allowlist policy if you have one.

## Verification before claiming done

Per `completion-gate`, "registered the app" is not a finish line. Before the chunk closes:

- [ ] App registration is visible in the target tenant; service principal exists.
- [ ] Required API permissions are granted **and** admin-consented (Application perms only show as "granted" when consent has happened).
- [ ] Redirect URIs match what the workload actually uses (test the round-trip end-to-end with a real sign-in or a real `client_credentials` call returning a token).
- [ ] The credential (FIC, certificate, or secret) is referenced from secret store, not literal in code or config.
- [ ] If a secret was used, the expiration date is calendared with a 30-day-prior reminder.
- [ ] The Bicep / CLI script that created the app is checked in. The portal-only path is not the source of truth.

## Cross-references

- `secrets-hygiene`: every credential discussion in this skill defers to the rotate-in-place, store-in-Key-Vault, never-in-tracked-files patterns there. The credential-ladder ordering (FIC > certificate > secret) is the operational form of the same principle.
- `plan-time-tooling`: any chunk that introduces a new app registration in a production tenant is a `engineering:deploy-checklist` trigger. Surface the registration plan, the admin-consent step, the credential type choice, and the rotation cadence in the chunk's Tooling block.
- `completion-gate`: the verification checklist above is the layer-3 gate for any Entra-touching chunk. "I registered the app" without a token-issuing round trip does not count.
- `forward-compatible-schemas`: app registration is itself a schema. Adding a permission is additive (safe). Removing a permission breaks consumers; sequence as add-new, migrate callers, then drop.
- `humanise-comms`: when surfacing the admin-consent step to a tenant admin who is not technical, write the request in plain language; name what the app will do, what permissions it asks for, and the contact for revocation.
- `azure-cloud-ops`: broader Azure operations context (compute, storage, database, networking, cost, governance). This skill owns the app-registration and OAuth/OIDC depth; `azure-cloud-ops` owns the rest of the Azure surface and cross-refers here for Entra depth.
- `entra-id`: the Entra ID platform and tenant-administration surface (Conditional Access, Privileged Identity Management, Identity Protection, Entra Connect and hybrid identity, B2B/B2C, Entra ID Governance). Boundary: this skill owns the app-REGISTRATION lifecycle (app type to OAuth flow, MSAL, service principals, API permission grants, credential ladder); `entra-id` owns the tenant/admin/policy surface around it. They cross-reference and do not duplicate: a Conditional Access policy affecting an app's sign-in is an `entra-id` concern, the app registration itself is this skill's concern.
- `identity-access-management`: the cross-platform IAM umbrella (AuthN vs AuthZ, federation protocol choice, MFA strategy, access-control models, IdP selection, zero trust identity). Use it for the conceptual and comparative layer; this skill is the Entra-specific app-registration implementation.

## Red flags

- About to ship a client secret value in a PR diff, env file commit, image layer, or chat message.
- About to grant `Directory.ReadWrite.All` (or any `*.ReadWrite.All`) on a hunch rather than from an actual API call requirement.
- About to wire up an Azure-hosted workload with an app-registration secret when managed identity would work.
- About to use Authorization Code without PKCE for a public client (SPA, native, mobile).
- About to skip `state` validation in the auth callback.
- About to disable token signature validation "to test something".
- About to issue a long-lived secret (12+ months) without a rotation reminder calendared.
- About to reuse one app registration across dev, staging, and production. Each environment is its own app registration; conflating them means a leaked dev secret leaks production.
- About to commit the Bicep parameter file with a real client secret literal instead of a Key Vault reference.

## Bottom line

Pick the app type first; the OAuth flow falls out. Register via Bicep wherever a tenant is more than throwaway. Climb the credential ladder as high as the workload allows, FIC over certificate over secret, managed identity over app registration entirely when the workload lives on Azure. Grant the smallest set of permissions that maps to actual API calls. Use MSAL. Verify with an end-to-end token round trip before claiming done.

## External resources

- Microsoft identity platform documentation: https://learn.microsoft.com/entra/identity-platform/
- OAuth 2.0 and OpenID Connect protocols: https://learn.microsoft.com/entra/identity-platform/v2-protocols
- MSAL: https://learn.microsoft.com/entra/msal/
- Microsoft Graph API: https://learn.microsoft.com/graph/
- Workload identity federation (FIC) reference: https://learn.microsoft.com/entra/workload-id/workload-identity-federation
