# Auth0 architecture

## Tenant model

Auth0 uses a tenant-per-environment model. A tenant is an isolated namespace containing all Auth0 configuration for one environment.

```
dev.company.auth0.com      -> Development
staging.company.auth0.com  -> Staging
company.auth0.com          -> Production (custom domain: auth.company.com)
```

**Custom domains** in production:
- Required to avoid third-party cookie restrictions that break session management in modern browsers.
- Required for brand consistency: `auth0.com` must not appear in production login URLs.
- Enables same-site cookie behaviour for Universal Login sessions.
- Configure via Dashboard: Branding -> Custom Domains.

---

## Universal Login

### New Universal Login (recommended)

- Rendered by Auth0 servers; never served from application code.
- Customisable via Branding -> Universal Login settings: logo, primary colour, background colour, font.
- Advanced customisation via the Universal Login editor (HTML/CSS) or Page Templates.
- Supports automatic feature upgrades: new MFA methods, passkeys, and Attack Protection features are available without code changes.
- Redirect-based: the application redirects to Auth0 for authentication, then Auth0 redirects back with a code.

### Classic Universal Login (legacy)

- Fully customisable HTML/JS/CSS hosted on Auth0.
- Full control but requires manual maintenance and testing on each Auth0 update.
- No automatic feature upgrades for new MFA methods or Attack Protection.
- Migration to New Universal Login is recommended.

### Why hosted login over embedded

| Concern | Hosted (Universal Login) | Embedded (Lock.js in SPA) |
|---|---|---|
| Credentials exposure | Never touch application servers | Pass through application |
| SSO session | Managed by Auth0; shared across apps | Per-app session only |
| Attack Protection | Works automatically | Limited |
| Security standards | Recommended by Auth0 and OIDC specs | Discouraged |

---

## Connections

### Database connections

**Auth0-managed database**: Auth0 stores and manages user credentials. Supports email/password, username/password, and passwordless flows.

**Custom database connection (lazy migration):**

On first login, Auth0 calls the custom login script against the legacy system. If valid, Auth0 imports the user into its database. Subsequent logins use Auth0 directly.

```javascript
// Custom database login script (lazy migration)
async function login(email, password, callback) {
  const bcrypt = require('bcrypt');
  const { Client } = require('pg');

  const client = new Client({ connectionString: configuration.PG_URL });
  await client.connect();

  const result = await client.query(
    'SELECT id, email, password_hash FROM users WHERE email = $1', [email]
  );

  if (result.rows.length === 0) {
    return callback(new WrongUsernameOrPasswordError(email));
  }

  const match = await bcrypt.compare(password, result.rows[0].password_hash);
  if (!match) {
    return callback(new WrongUsernameOrPasswordError(email));
  }

  return callback(null, {
    user_id: result.rows[0].id.toString(),
    email: result.rows[0].email
  });
}
```

Store the database connection string in `configuration` (Auth0's Connection secrets), not hardcoded. See `secrets-hygiene`.

### Social connections

Connect to social identity providers (Google, Apple, Facebook, GitHub, LinkedIn, Twitter/X, etc.). Each social connection requires OAuth credentials (client ID and secret) from the provider's developer console. Store client secrets via `secrets-hygiene`.

### Enterprise connections

| Type | Use case |
|---|---|
| SAML 2.0 | SP-initiated SSO from enterprise IdPs (AD FS, PingFederate, any SAML IdP) |
| OIDC | Connect to any OIDC-compliant IdP (Okta, Keycloak, custom) |
| Azure AD | Microsoft Entra ID (formerly Azure AD); uses Microsoft identity platform |
| Google Workspace | G Suite / Google Workspace domain accounts |
| AD FS | Legacy on-premises AD FS federation |

Enterprise connections can be scoped to a specific Organization, enabling each B2B customer to authenticate via their own IdP.

### Passwordless connections

- **Email**: magic link or OTP via email.
- **SMS**: OTP via SMS (uses Twilio or a custom Telephony Action).
- Passwordless flows require Universal Login (redirect-based); embedded passwordless is not supported in New Universal Login.

---

## Actions pipeline

### Actions execution model

Actions are stateless serverless Node.js functions. Multiple Actions can be chained on a single trigger; they execute in order. Each Action receives an `event` (read-only context) and an `api` object (writable surface for modifying Auth0 behaviour).

### Post Login Action example

```javascript
exports.onExecutePostLogin = async (event, api) => {
  const namespace = 'https://myapp.com/claims';

  // Add roles from app_metadata to tokens
  if (event.user.app_metadata?.roles) {
    api.idToken.setCustomClaim(`${namespace}/roles`, event.user.app_metadata.roles);
    api.accessToken.setCustomClaim(`${namespace}/roles`, event.user.app_metadata.roles);
  }

  // Enrich with external data (call external API)
  const response = await fetch(
    `https://api.company.com/users/${event.user.user_id}/permissions`,
    { headers: { Authorization: `Bearer ${event.secrets.INTERNAL_API_KEY}` } }
  );
  const permissions = await response.json();
  api.accessToken.setCustomClaim(`${namespace}/permissions`, permissions);

  // Deny access on a condition
  if (event.user.email_verified === false) {
    api.access.deny('Please verify your email before logging in.');
  }
};
```

**Key rules for Actions:**
- Use `event.secrets` for all API keys and credentials; never hardcode.
- Actions must respond within the configured timeout; keep external calls fast.
- Use the `api` object exclusively to modify token claims or deny access; do not write directly to the `event` object.

### Actions vs. Rules vs. Hooks

| Mechanism | Status | Recommendation |
|---|---|---|
| Actions | Current | Use for all new extensibility |
| Rules | Deprecated | Migrate to Actions |
| Hooks | Deprecated (most triggers) | Migrate to Actions |

---

## Organizations (B2B multi-tenancy)

Organizations represent customer companies in a B2B SaaS product.

**Key properties per Organization:**
- Own connections: the enterprise IdP (SAML, OIDC, Azure AD) the customer's users authenticate through.
- Branding: logo and colour scheme overrides for the Universal Login page.
- MFA policy: require MFA for all organization members.
- Members and roles: users are members of the organization and can hold organization-scoped roles.

**Organization login flow:**

```
User navigates to: https://app.company.com/login?org=acme
  -> App calls /authorize?organization=org_xxx
  -> Auth0 presents the organization's configured IdP
  -> User authenticates via the organization's IdP (or Auth0 database)
  -> Auth0 issues tokens with org_id claim
  -> App reads org_id to scope the user's session to the correct tenant
```

**Management API examples:**

```javascript
const ManagementClient = require('auth0').ManagementClient;
const management = new ManagementClient({ domain, clientId, clientSecret });

// Add a member to an organization
await management.organizations.addMembers(
  { id: 'org_abc123' },
  { members: ['auth0|user_id_123'] }
);

// Assign an organization-scoped role
await management.organizations.addMemberRoles(
  { id: 'org_abc123', user_id: 'auth0|user_id_123' },
  { roles: ['rol_admin'] }
);
```

---

## RBAC and token claims

**Token with RBAC enabled:**

```json
{
  "iss": "https://company.auth0.com/",
  "sub": "auth0|user123",
  "aud": "https://api.company.com",
  "permissions": ["read:articles", "write:articles"],
  "org_id": "org_abc123"
}
```

RBAC must be enabled on the API (Resource Server) in the Auth0 Dashboard: Applications -> APIs -> [API name] -> Settings -> Enable RBAC. Permissions are only included in the access token when RBAC is enabled and the user has been assigned roles containing those permissions.

---

## Machine-to-machine (M2M) authentication

Use the client credentials flow for service-to-service authentication without user context:

```
Service A requests an access token:
POST /oauth/token
{
  "client_id": "...",
  "client_secret": "...",
  "audience": "https://api.company.com",
  "grant_type": "client_credentials"
}
```

Store the client secret via `secrets-hygiene`. For AI agents, use the client credentials flow per audience/API; scope tokens minimally.

**Fine-Grained Authorization (Auth0 FGA / Okta FGA)**: based on OpenFGA (Google Zanzibar model); use for relationship-based access control (ReBAC) beyond RBAC. Define a model of objects, relations, and tuples; FGA evaluates permission questions ("can user X read document Y?") against the tuple store.

---

## Attack Protection reference

| Feature | Triggers | Default action |
|---|---|---|
| Bot Detection | Automated request patterns | CAPTCHA challenge |
| Brute-Force Protection (per account) | N failed logins for one account | Block account temporarily |
| Brute-Force Protection (per IP) | N failed logins from one IP | Block IP temporarily |
| Breached Password Detection | Password found in breach databases | Block (configurable: block or warn) |
| Suspicious IP Throttling | Anomalous failure rate from IP | Throttle |
| Adaptive MFA | Impossible travel, new device, new IP | MFA challenge |

All features are configurable in the Auth0 Dashboard: Security -> Attack Protection.
