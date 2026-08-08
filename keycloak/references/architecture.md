# Keycloak architecture

## Realm topology and design

A realm is a fully isolated namespace in Keycloak containing users, clients, groups, roles, and identity providers.

```
Master Realm (admin-only)
  |-- Realm: company-internal   (workforce: employees, contractors)
  |     |-- Clients, Groups, Roles, Identity Providers, Flows
  |-- Realm: company-customers  (CIAM: external users)
  |-- Realm: partner-portal     (B2B: partner organisations)
```

**Design rules:**
- Master realm: Keycloak administration only. Zero application clients.
- Separate realms by trust domain; do not share a realm across trust boundaries.
- Do not create a realm per B2B customer at scale; use Organizations instead (see below).
- Realm count in the hundreds degrades Keycloak's JPA cache and startup performance.

---

## Clients

### Client types

| Type | Protocol | OIDC flow | Example use case |
|---|---|---|---|
| Public | OIDC | Authorization Code + PKCE | SPA (React, Angular, Vue), mobile app |
| Confidential | OIDC | Authorization Code, Client Credentials | Backend web app, microservice-to-microservice |
| Bearer-only | OIDC | Token validation (introspection/JWKS) | REST API resource server |
| SAML | SAML 2.0 | SP-initiated or IdP-initiated | Enterprise legacy application |

**PKCE** (Proof Key for Code Exchange) is mandatory for public clients; it prevents authorisation-code interception attacks.

### Client scopes

Client scopes group protocol mappers and role scope mappings. Scopes are reusable across clients.

**Scope categories:**

| Category | Behaviour |
|---|---|
| Default | Automatically included in every token for this client |
| Optional | Included only when the client requests it via `scope=` parameter |

**Built-in scopes**: `openid`, `profile`, `email`, `address`, `phone`, `offline_access`, `roles`, `web-origins`, `microprofile-jwt`.

---

## Protocol mappers

Protocol mappers transform user attributes and role assignments into token claims. Each mapper targets one or more token types (ID token, access token, userinfo endpoint).

| Mapper type | Source | Token claim path |
|---|---|---|
| User Attribute | User profile attribute (e.g., `department`) | Custom claim (configurable path) |
| User Realm Role | Realm role assignments | `realm_access.roles` |
| User Client Role | Client role assignments | `resource_access.{client_id}.roles` |
| Group Membership | Group names | `groups` claim |
| Audience | Client configuration | `aud` claim |
| Hardcoded Claim | Static value | Fixed claim value |
| Script Mapper | JavaScript expression (JSR-223) | Dynamic claim value |

**Common pitfall**: roles are included in tokens only when the corresponding role-mapper scope is assigned to the client. If `realm_access.roles` is missing from tokens, check that the `roles` scope is set as a default scope on the client.

---

## Authentication flows

### Built-in flows

| Flow | When it runs |
|---|---|
| Browser | Interactive user login via browser |
| Direct Grant | Resource owner password credentials (API login; avoid for production user-facing apps) |
| Registration | Self-service user sign-up |
| Reset Credentials | Password recovery |
| First Broker Login | Behaviour on first login via an external IdP (brokered identity) |
| Client Authentication | How confidential clients authenticate to Keycloak (client secret, JWT, X.509) |

### Flow execution structure

```
Browser Flow (example)
  |-- Cookie (check existing session) [Alternative]
  |-- Identity Provider Redirector (social login buttons) [Alternative]
  |-- Username/Password Form [Required]
  |-- Conditional OTP [Conditional]
       |-- Condition: User Configured
       |-- OTP Form [Required]
```

**Execution types:**
- Required: must succeed for the flow to continue.
- Alternative: one of these must succeed; if one fails, the next alternative is tried.
- Conditional: the execution and its children run only if the condition evaluates to true.
- Disabled: excluded from evaluation.

### Custom authenticator SPI

Custom authentication logic is implemented via the `org.keycloak.authentication.Authenticator` SPI:
1. Implement `Authenticator` and `AuthenticatorFactory`.
2. Package as a JAR and deploy to Keycloak's `providers/` directory.
3. Run `kc.sh build` to register the custom provider.
4. Add the custom authenticator as an execution step in the desired flow.

---

## Identity brokering

### Brokering flow

```
User selects "Sign in with [External IdP]"
  -> Keycloak redirects to external IdP
  -> External IdP authenticates the user
  -> External IdP returns an assertion/token to Keycloak
  -> Keycloak runs the "First Broker Login" flow:
       |-- Lookup existing Keycloak account by email/username
       |-- If found: link the external identity to the existing account
       |-- If not found: create a new account (or prompt for profile review)
  -> Keycloak issues its own ID token and access token to the application
```

### Supported external IdP protocols

- **OIDC**: connect to any OIDC-compliant IdP (Okta, Entra ID, Google, Auth0, another Keycloak realm).
- **SAML 2.0**: connect to any SAML IdP (AD FS, PingFederate, Shibboleth).
- **Social**: pre-built social connectors (Google, Facebook, GitHub, Twitter/X, Microsoft, Apple, LinkedIn).

### First broker login flow configuration

Configurable per external IdP:

| Option | Behaviour |
|---|---|
| Automatically create user | Create a new Keycloak account for every brokered identity |
| Review profile before creation | Show a profile form to the user before creating the account |
| Link to existing account by email | If a Keycloak account with the same email exists, link the external identity to it |
| Require email verification | Send a verification email before completing login for new brokered users |

---

## User federation (LDAP / AD)

**LDAP federation configuration:**

```
Connection URL:          ldaps://dc01.example.com:636
Bind DN:                 CN=keycloak-svc,OU=Service Accounts,DC=example,DC=com
Bind Credential:         (store via secrets-hygiene)
Users DN:                OU=Users,DC=example,DC=com
User Object Classes:     inetOrgPerson, organizationalPerson
Username LDAP Attribute: sAMAccountName
UUID LDAP Attribute:     objectGUID
Edit Mode:               READ_ONLY (or WRITABLE)
```

**Sync modes:**

| Mode | Behaviour | When to use |
|---|---|---|
| Import (periodic sync) | Users are imported into Keycloak's local DB on schedule | Reduces LDAP load; allows Keycloak to function if LDAP is unavailable |
| Query on every request | Keycloak queries LDAP on each authentication | Always up-to-date; requires LDAP availability at login time |

**Sync configuration:**
- Full sync period: how often to reimport all LDAP users (seconds). Example: 3600 (1 hour).
- Changed users sync period: how often to sync only changed users. Example: 60 (1 minute).

**Writable federation**: set Edit Mode to WRITABLE to allow Keycloak to write password changes and profile updates back to LDAP. Requires the bind service account to have write permission on the relevant LDAP attributes.

**Group mapper**: map LDAP groups to Keycloak groups; configure the Group DN and Group Object Classes.

---

## Fine-grained authorisation services

Keycloak's authorisation framework sits on top of OAuth 2.0/UMA.

**Components:**

| Component | Description |
|---|---|
| Resource | What is being protected (e.g., `/api/documents`, a specific record) |
| Scope | Actions on the resource (e.g., `read`, `write`, `delete`) |
| Policy | A rule that evaluates to Permit or Deny (role policy, user policy, group policy, time policy, JavaScript policy, aggregated policy) |
| Permission | Associates one or more policies with a resource and/or scope |

**Policy evaluation decision strategies:**

- Unanimous: all policies must permit (default for deny-by-default).
- Affirmative: at least one policy must permit.
- Consensus: majority must permit.

**UMA (User-Managed Access)**:
- Extension to OAuth 2.0 for user-driven access sharing.
- Resource owner registers resources with Keycloak; grants permissions to other users or clients.
- Used for document sharing, collaborative access, and delegated access scenarios.

---

## Organizations (B2B multi-tenancy, GA in 26.0)

**Why Organizations over multiple realms:**

| Dimension | Organizations | Per-customer realms |
|---|---|---|
| Scalability | Hundreds of organisations in one realm | Hundreds of realms degrades performance |
| Shared configuration | Themes, flows, client scopes shared | Duplicated per realm |
| User membership | Users can belong to multiple organisations | Users isolated per realm |
| Management | Centralised | Distributed |

**Organization configuration:**
- Each Organization has a name, a set of member users, and optionally its own identity providers (enterprise SAML/OIDC per customer).
- Attribute-based membership: map incoming IdP attributes to Organisation membership.
- Organisation-specific authentication flow overrides: require MFA for all members of a specific Organisation.

---

## Admin REST API

Full programmatic management of all Keycloak resources.

```bash
# Obtain an admin token
TOKEN=$(curl -s -X POST \
  "https://auth.company.com/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" | jq -r '.access_token')

# Create a user
curl -X POST \
  "https://auth.company.com/admin/realms/my-realm/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"jdoe","email":"jdoe@example.com","enabled":true}'

# Create a client
curl -X POST \
  "https://auth.company.com/admin/realms/my-realm/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"clientId":"my-app","protocol":"openid-connect","publicClient":true}'

# List realm roles
curl "https://auth.company.com/admin/realms/my-realm/roles" \
  -H "Authorization: Bearer $TOKEN"
```

The admin-cli client uses the direct grant (resource owner password) flow, which is deprecated for user-facing apps but acceptable for admin automation. For production automation, create a dedicated confidential client with the minimum required service-account roles; store the client secret via `secrets-hygiene`. Token `exp` must be tracked via `utc-timestamps`.
