---
name: auth0
description: "Use for Auth0 customer identity (CIAM) platform implementation, configuration, and troubleshooting. Covers tenant architecture and environment strategy, Universal Login (New and Classic), database/social/enterprise/passwordless Connections, Actions (Post Login, M2M, Pre/Post Registration), Organizations for B2B multi-tenancy, RBAC (Roles, Permissions, Resource Servers), Attack Protection (bot detection, brute-force protection, breached password detection, suspicious IP throttling, adaptive MFA), machine-to-machine (M2M) client credentials flow, Fine-Grained Authorization (Okta FGA/OpenFGA), tenant configuration as code (Deploy CLI, Terraform auth0 provider), log streaming, Management API, and lazy user migration via custom database connections. References: architecture.md, operations.md. Triggers include \"Auth0\", \"Universal Login\", \"Auth0 Actions\", \"Auth0 Organizations\", \"CIAM\", \"Auth0 connections\", \"Auth0 Rules\", \"Auth0 Hooks\", \"Auth0 tenant\", \"Auth0 attack protection\", \"Auth0 FGA\", \"Okta FGA\", \"OpenFGA\", \"Auth0 Management API\", \"Auth0 Deploy CLI\", \"a0deploy\", \"auth0 terraform\", \"custom database connection\", \"Auth0 RBAC\", \"Auth0 M2M\", \"Auth0 log streaming\", \"Auth0 branding\", \"Universal Login customisation\", \"Auth0 Actions pipeline\". For IAM architecture, federation protocol choice, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Auth0

> **Skill marker**: When applying this skill, begin your reply with `[skill: auth0]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Auth0-specific implementation: tenant architecture, Universal Login, Connections, Actions, Organizations, RBAC, Attack Protection, machine-to-machine authentication, configuration as code, and operational monitoring. Auth0 is a customer identity (CIAM) platform; it is an Okta company but a distinct product targeting developer-led, customer-facing identity scenarios. The conceptual layer (federation protocol choice, IdP selection, access-control models, zero trust) lives in `identity-access-management`.

## When to use

- Designing or configuring Auth0 tenant architecture (dev/staging/prod environment strategy, custom domains).
- Implementing or customising Universal Login (branding, New vs. Classic, redirect-based flows).
- Configuring Connections: database (Auth0-managed or custom), social (Google, Apple, GitHub), enterprise (SAML, OIDC, Azure AD), or passwordless (email magic link, SMS OTP).
- Writing or reviewing Actions (Post Login, M2M, Pre/Post Registration, Post Change Password, Send Phone Message).
- Implementing Organizations for B2B SaaS multi-tenancy.
- Configuring RBAC: Roles, Permissions, Resource Servers (APIs), `permissions` claim in tokens.
- Configuring Attack Protection features or reviewing adaptive MFA settings.
- Setting up client credentials flows for AI agents or service-to-service authentication.
- Managing tenant configuration as code via Auth0 Deploy CLI or Terraform.
- Troubleshooting Auth0 log events, configuring log streaming, or monitoring Management API rate limits.

## When not to use

- **Okta workforce identity (Universal Directory, Lifecycle Management, OIN, Workflows, ThreatInsight)**: Auth0 and Okta are sibling products under one company but serve distinct use cases. Auth0 is for customer-facing (CIAM) identity; Okta is for workforce identity. Use `okta`.
- **IAM architecture, federation protocol design, IdP selection, or CIAM vs. workforce split decision**: use `identity-access-management`.
- **Credential, client-secret, and API-token storage or rotation**: use `secrets-hygiene`. Auth0 client secrets, Management API tokens, and Action secrets are credentials; their custody belongs there.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Tenant architecture

Auth0 uses a separate-tenant-per-environment model. Each tenant is an isolated namespace:

```
dev.company.auth0.com      -> Development (free to experiment)
staging.company.auth0.com  -> Staging (mirrors production configuration)
company.auth0.com          -> Production (custom domain: auth.company.com)
```

Production tenants must use a custom domain (`auth.company.com`) to avoid third-party cookie restrictions, maintain brand consistency, and support proper same-site session management.

### Universal Login

Auth0's hosted login page. Auth0 recommends redirect-based Universal Login over embedded SDKs (Lock.js in SPA) because credentials never touch application servers, SSO sessions are managed centrally, and Attack Protection features work automatically.

**New Universal Login** (recommended): rendered by Auth0; customisable via branding settings (logo, colours, fonts); automatic feature upgrades; supports passkeys.

**Classic Universal Login** (legacy): fully customisable HTML/JS/CSS; no automatic feature upgrades; requires manual maintenance.

### Connections

Identity sources that authenticate users:

| Type | Examples | Use case |
|---|---|---|
| Database | Auth0-managed or custom script | Username/password; own user store |
| Social | Google, Apple, Facebook, GitHub, LinkedIn | Consumer sign-up/sign-in |
| Enterprise | SAML, OIDC, Azure AD, Google Workspace, AD FS | Employee/partner SSO |
| Passwordless | Email magic link/OTP, SMS OTP | Passwordless sign-in |
| Custom database | Custom login/create/verify scripts | Lazy migration from legacy system |

**Custom database connections** enable gradual user migration: on first login, Auth0 calls the custom login script against the legacy system; if valid, Auth0 creates the user in its database; subsequent logins use Auth0 directly. See `references/architecture.md` for a migration script example.

### Actions

Serverless Node.js functions that hook into Auth0's authentication and authorisation pipeline. Actions replace the deprecated Rules and Hooks (migrate all existing Rules/Hooks to Actions).

| Trigger | When it runs | Common use case |
|---|---|---|
| Login / Post Login | After authentication, before tokens issued | Add custom claims, enrich profile, enforce access policies |
| Machine to Machine | During client credentials flow | Add custom claims to M2M tokens |
| Pre User Registration | Before user is created | Validate email domain, check deny lists |
| Post User Registration | After user is created | Send welcome email, create downstream accounts |
| Post Change Password | After password change | Notify user, sync to legacy system |
| Send Phone Message | When SMS/Voice OTP is sent | Custom SMS provider (Twilio, MessageBird) |

**Action secrets**: store API keys and credentials in `event.secrets`; never hardcode them in Action code. See `secrets-hygiene`.

### Organizations

Multi-tenancy support for B2B SaaS:
- Each **Organization** represents a customer company in the B2B SaaS product.
- Organizations have their own connections, branding, MFA policies, and member lists.
- Users can belong to multiple organizations.
- Organization-specific login: `/authorize?organization=org_xxx`.
- Members can hold organization-scoped roles distinct from their global roles.

### RBAC

Auth0 RBAC components:
- **Roles**: named permission sets (e.g., `admin`, `editor`, `viewer`).
- **Permissions**: granular access rights tied to a Resource Server (e.g., `read:articles`).
- **Resource Servers (APIs)**: define the audience (`aud`) and the available scopes/permissions.
- Permissions are included in access tokens as the `permissions` claim when RBAC is enabled.

### Attack Protection

| Feature | Protection | Configuration |
|---|---|---|
| Bot Detection | Blocks automated credential stuffing | CAPTCHA challenge on suspicious requests |
| Brute-Force Protection | Rate-limits login attempts per user/IP | Block after N failed attempts from same IP or for same account |
| Breached Password Detection | Checks passwords against breach databases | Block or warn on compromised passwords |
| Suspicious IP Throttling | Rate-limits IPs with high failure rates | Throttle after anomalous failure rate |
| Adaptive MFA | Risk-based MFA challenges | Challenge on impossible travel, new device, new IP |

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Tenant model, Universal Login (New vs. Classic), Connection types and custom DB migration scripts, Actions pipeline and example code, Organizations B2B model and Management API examples, RBAC token structure, Attack Protection configuration, M2M client credentials flow, Fine-Grained Authorization (Okta FGA/OpenFGA) | `references/architecture.md` |
| Operations | Environment strategy (dev/staging/prod), tenant configuration as code (Deploy CLI + Terraform), log streaming and critical log events, Management API rate limits, Actions testing and deployment, custom domain setup, monitoring and alerting patterns | `references/operations.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts, CIAM vs. workforce IdP selection, access-control model design, zero trust.
- `okta`: Okta is Auth0's sibling workforce identity product (same company, distinct platform); use `okta` for employee/workforce identity. Do not substitute one for the other.
- `sailpoint`: SailPoint IGA can be layered on top of Auth0 for enterprise governance requirements on customer identities (certifications, SOD); uncommon but valid for regulated industries.
- `secrets-hygiene`: Auth0 client secrets, Management API tokens, Action secrets (`event.secrets`), and Connection credentials are all credentials; never hardcode in code or commit to repositories.
- `utc-timestamps`: token `exp`/`iat`, session lifetimes, token rotation windows, and log event analysis must be reasoned in UTC.
- `oncall-runbooks`: Auth0 tenant outage, Attack Protection false-positive blocking, Actions pipeline failure, and Management API rate-limit exhaustion runbooks.

## Red flags

- **Rules or Hooks still in use**: Rules and Hooks are deprecated. All new extensibility must use Actions; migrate existing Rules/Hooks before Auth0 removes the feature.
- **Embedded login (Lock.js in SPA) instead of Universal Login redirect**: embedded login means credentials pass through the application server, bypassing Auth0's Attack Protection and SSO session management. Always use redirect-based Universal Login.
- **Action secrets hardcoded in Action code**: API keys and credentials hardcoded in Action code are exposed in Auth0 logs and version history. Use `event.secrets` for all credentials.
- **No custom domain in production**: third-party cookie restrictions break cross-domain session management without a custom domain. Production tenants must use a custom domain.
- **Access tokens stored in localStorage**: tokens in localStorage are vulnerable to XSS attacks. Use in-memory storage or secure, HttpOnly cookies.
- **Single tenant for all environments**: testing in production corrupts audit logs and risks production data exposure. Use separate tenants per environment.
- **Ignoring Management API rate limits**: the Management API enforces rate limits (50 requests/second per tenant on most plans). Plan bulk operations (user migration, bulk role assignment) with rate limiting in mind.

## Bottom line

Classify the work as workforce (use `okta`) or customer-facing/CIAM (use this skill) before starting. Always use redirect-based Universal Login with a custom domain in production. Migrate all Rules/Hooks to Actions. Manage tenant configuration as code via the Auth0 Deploy CLI or Terraform. Store all secrets in `event.secrets`, never hardcoded. Load `references/architecture.md` for platform internals and integration patterns; load `references/operations.md` for environment strategy, IaC tooling, and operational guidance.
