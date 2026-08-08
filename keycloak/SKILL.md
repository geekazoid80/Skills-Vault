---
name: keycloak
description: "Use for Keycloak open-source identity and access management platform implementation, configuration, and troubleshooting. Covers realm design and multi-tenancy strategy, client types (public, confidential, bearer-only, SAML), client scopes and protocol mappers, authentication flow customisation (browser flow, direct grant, registration, reset credentials, first broker login), identity brokering (OIDC/SAML external IdP integration, first-login flow), user federation (LDAP/AD sync, delegated authentication, writeback), fine-grained authorization services (resources, scopes, policies, UMA), Organizations for B2B multi-tenancy (GA in 26.0), Quarkus-based deployment (kc.sh start/build commands, production checklist), high availability and clustering (Infinispan, JGroups, DNS_PING, JDBC_PING, cross-DC deployment), admin REST API, themes and SPI customisation, and version migration (WildFly to Quarkus). References: architecture.md, operations.md. Triggers include \"Keycloak\", \"realm\", \"identity brokering\", \"Keycloak client\", \"Keycloak federation\", \"Keycloak themes\", \"Keycloak authorization\", \"Keycloak Quarkus\", \"Keycloak Organizations\", \"kc.sh\", \"protocol mapper\", \"client scope\", \"authentication flow\", \"Keycloak LDAP\", \"Keycloak SPI\", \"Keycloak admin API\", \"Infinispan Keycloak\", \"Keycloak cluster\", \"Keycloak WildFly migration\", \"UMA Keycloak\", \"Keycloak upgrade\", \"KC_DB\", \"KC_HOSTNAME\". For IAM architecture, federation protocol design, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Keycloak

> **Skill marker**: When applying this skill, begin your reply with `[skill: keycloak]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Keycloak-specific implementation: realm design, client configuration, authentication flow customisation, identity brokering, user federation, fine-grained authorisation, Organizations, Quarkus deployment, clustering, and the admin REST API. Keycloak is an open-source, self-hosted IAM platform (CNCF project). The conceptual layer (federation protocol choice, IdP selection, access-control models, zero trust) lives in `identity-access-management`.

## When to use

- Designing realm topology: trust boundaries, separation of internal/customer/partner identity domains.
- Configuring clients (public OIDC, confidential OIDC, bearer-only, SAML) and client scopes.
- Writing or reviewing protocol mappers (user attribute, realm role, client role, group membership, audience, script mapper).
- Customising authentication flows: building a browser flow with conditional OTP, WebAuthn, or a custom SPI authenticator.
- Configuring identity brokering: connecting Keycloak to an external OIDC or SAML IdP, configuring the first-login flow.
- Setting up LDAP or Active Directory user federation: sync modes, attribute mapping, delegated authentication, writeback.
- Implementing fine-grained authorisation services: defining resources, scopes, policies, permissions, and UMA.
- Configuring Organizations for B2B multi-tenancy within a single realm (Keycloak 26.0+).
- Deploying or upgrading Keycloak: Quarkus `kc.sh start/build`, external database setup, TLS, hostname configuration, production checklist.
- Setting up clustering: Infinispan session replication, JGroups discovery (DNS_PING for Kubernetes, JDBC_PING for database), cross-DC deployment.
- Managing Keycloak programmatically via the admin REST API.
- Migrating from WildFly-based Keycloak (pre-17.0) to the Quarkus distribution.

## When not to use

- **IAM architecture, federation protocol design, IdP selection, or multi-tenancy model choice (realms vs. Organizations)**: use `identity-access-management` for the conceptual layer.
- **Managed/SaaS identity providers** (Okta, Auth0, Entra ID, PingOne): Keycloak is self-hosted; for managed IdPs use the relevant vendor skill.
- **Credential, client-secret, and service-account-credential storage or rotation**: use `secrets-hygiene`.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Realm topology

A realm is a tenant/namespace in Keycloak: isolated users, clients, groups, roles, and identity providers.

```
Master Realm (admin-only; never for applications)
  |-- Realm: company-internal  (workforce identity)
  |-- Realm: company-customers  (CIAM)
  |-- Realm: partner-portal  (B2B federation)
```

**Realm design principles:**
- Use the master realm only for managing Keycloak itself. Never register application clients in master.
- Separate realms by trust boundary (internal employees vs. external customers vs. B2B partners).
- Do not create a realm per B2B customer: use Organizations within a single realm instead. Hundreds of realms degrade performance.

### Clients

| Client type | Protocol | OIDC flow | Example |
|---|---|---|---|
| Public | OIDC | Authorization Code + PKCE | SPA, mobile app |
| Confidential | OIDC | Authorization Code, Client Credentials | Backend web app, API service |
| Bearer-only | OIDC | Token validation only | REST API (resource server) |
| SAML | SAML 2.0 | SP-initiated or IdP-initiated | Enterprise legacy apps |

**Client scopes** group protocol mappers and role scope mappings:
- Default scopes are automatically included in every token.
- Optional scopes are included only when explicitly requested via the `scope=` parameter.
- Built-in scopes: `openid`, `profile`, `email`, `address`, `phone`, `offline_access`.

### Protocol mappers

Transform user attributes and role assignments into token claims. See `references/architecture.md` for the full mapper reference and claim path examples.

### Authentication flows

Keycloak's authentication is built from configurable execution steps:
- Cookie (check existing session), Identity Provider Redirector (social login buttons), Username/Password Form, OTP Form, WebAuthn Authenticator, Conditional OTP (require OTP based on condition), custom SPI authenticator.
- Separate flows exist for: browser login, direct grant (resource owner password), registration, reset credentials, first broker login (brokered IdP first login), and client authentication.

### Identity brokering

```
User clicks "Sign in with Google" (or any external IdP) on Keycloak login page
  -> Keycloak redirects to external IdP
  -> External IdP authenticates user, returns to Keycloak
  -> Keycloak runs the "first broker login" flow (create/link/review user)
  -> Keycloak issues its own tokens to the application
```

Configurable first-login behaviour: auto-create user, require profile review, link to existing account by email, or require email verification.

### User federation (LDAP/AD)

Integrate external user stores for delegated authentication or attribute sync. Key options: import vs. query mode, READ_ONLY vs. WRITABLE edit mode, full-sync and incremental-sync periods, LDAP attribute mapping to Keycloak user profile.

### Organizations (GA in 26.0)

Multi-tenancy within a single realm:
- Each Organization represents a B2B customer.
- Users are members of Organizations; users can belong to multiple Organizations.
- Each Organization can have its own identity providers (enterprise SAML/OIDC IdP per customer).
- Organization-specific authentication flows and attribute-based membership.
- Better scalability than realms: shared configuration (themes, flows, client scopes), simpler management and monitoring.

Do not use realms for per-customer multi-tenancy at scale; use Organizations instead.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Realm topology; client types and scopes; protocol mapper reference; authentication flow structure and customisation; identity brokering flow and first-login configuration; LDAP/AD federation configuration; fine-grained authorisation services (resources, scopes, policies, UMA); Organizations model; admin REST API examples | `references/architecture.md` |
| Operations | Quarkus deployment commands and production checklist; external database configuration; TLS and hostname setup; clustering (Infinispan, JGroups, DNS_PING, JDBC_PING, cross-DC); metrics and health endpoints; upgrade path (WildFly to Quarkus); common pitfalls and version-specific notes (17.0, 22.0, 25.0, 26.0) | `references/operations.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts (OIDC, SAML 2.0, OAuth 2.0), IdP selection rationale, access-control models, zero trust identity.
- `sailpoint`: SailPoint IGA can be layered on top of Keycloak as the IdP for enterprise governance (certifications, SOD, role mining); Keycloak handles authentication, SailPoint handles governance.
- `secrets-hygiene`: Keycloak client secrets, LDAP bind credentials, admin API service-account credentials, and theme-injection tokens are credentials; handle per `secrets-hygiene` discipline.
- `utc-timestamps`: token `exp`/`iat`/`nbf`, session idle and absolute timeouts, LDAP sync schedules, and access-review cycles must be reasoned in UTC.
- `oncall-runbooks`: Keycloak cluster split-brain, LDAP federation outage, authentication flow failure, and Quarkus startup failure runbooks.

## Red flags

- **Registering application clients in master realm**: the master realm is for Keycloak administration only. Clients in master inherit elevated risk; a compromised client credential could expose the admin API. Always use a separate realm for applications.
- **Realms per B2B customer at scale**: creating hundreds of realms for B2B customers degrades Keycloak performance significantly. Use Organizations (Keycloak 26.0+) for per-customer multi-tenancy within a single realm.
- **WildFly-based Keycloak still in use**: the WildFly distribution reached end-of-life at Keycloak 17. Deployments still on WildFly miss security patches and the Quarkus performance improvements. Migrate to Quarkus immediately.
- **H2 database in production**: the embedded H2 database is for development only. Production deployments require an external database (PostgreSQL recommended; MySQL/MariaDB supported). H2 is not suitable for clustering or data durability.
- **Skipping `kc.sh build`**: the Quarkus distribution benefits from a pre-compilation step (`kc.sh build`) that bakes configuration into the binary for faster startup. Skipping it means Keycloak reconfigures at every start, increasing startup time.
- **Custom themes that override base templates**: theme customisations that override Keycloak's base FreeMarker templates break on upgrade when Keycloak changes the template structure. Pin to specific Keycloak versions and test all themes before upgrading.
- **Tokens missing needed claims**: default token content may not include all claims the application requires. Verify protocol mapper configuration and client scope assignments produce the expected claims in the issued token.

## Bottom line

Design realm topology around trust boundaries, not organisational hierarchy. Use Organizations for per-customer B2B multi-tenancy rather than per-customer realms. Deploy on the Quarkus distribution with an external database (PostgreSQL). Run `kc.sh build` before production starts. Test custom themes after every Keycloak upgrade. Load `references/architecture.md` for configuration and integration patterns; load `references/operations.md` for deployment, clustering, and upgrade guidance.
