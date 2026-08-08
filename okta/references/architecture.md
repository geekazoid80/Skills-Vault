# Okta architecture

## Platform architecture

### Multi-tenant cloud service

Okta operates as a multi-tenant SaaS platform:
- **Cell architecture**: each Okta org is assigned to a cell (isolated infrastructure cluster).
- **Org URL**: `https://<subdomain>.okta.com` or a custom domain such as `https://id.company.com`.
- **Data isolation**: each org's data is logically isolated within the cell.
- **High availability**: active-active across multiple data centres within a cell.
- **Preview/Production cells**: preview cells (`*.oktapreview.com`) receive features before production cells; use them for testing before production rollout.
- **Data residency**: US, EU, Australia, Japan cell options.
- **Certifications**: SOC 2 Type 2, ISO 27001, FedRAMP High.

### Agent architecture

Okta agents enable hybrid connectivity between the Okta cloud and on-premises infrastructure. All agents communicate via outbound HTTPS only; no inbound firewall rules are required.

| Agent | Purpose | Protocol | Deployment |
|---|---|---|---|
| AD Agent | Sync AD users/groups to Okta; delegated authentication | Outbound HTTPS (443) | On-premises; 2+ for HA |
| LDAP Agent | Sync LDAP directories to Okta | Outbound HTTPS (443) | On-premises; 2+ for HA |
| RADIUS Agent | RADIUS authentication (VPN, Wi-Fi, network access) | Inbound UDP 1812/1813 + Outbound HTTPS | On-premises or DMZ |
| IWA Agent | Integrated Windows Authentication (desktop SSO) | Inbound HTTP + Outbound HTTPS | On-premises, domain-joined |
| On-Prem MFA Agent | MFA for on-premises apps via RADIUS/IWA | Outbound HTTPS | On-premises |

**AD Agent details:**
- Supports multiple AD forests/domains per Okta org.
- Service account needs read access only (plus password reset if using password sync).
- Install 2+ agents per domain for high availability (active-passive failover).
- Polls Okta for authentication requests in delegated auth mode; imports users in sync mode.

---

## Universal Directory data model

### User profile

The Okta user profile has two layers:
- **Okta user profile**: base profile with standard and custom attributes.
- **Application user profiles**: per-app profiles with app-specific attributes, populated via profile mappings.

**Standard attributes:**

| Attribute | Type | Notes |
|---|---|---|
| `login` | string | Unique; typically email |
| `email` | string | Primary email address |
| `firstName`, `lastName`, `displayName` | string | Display identity |
| `mobilePhone`, `primaryPhone` | string | Contact |
| `department`, `title`, `manager`, `organization` | string | HR attributes |
| `status` | enum | STAGED, PROVISIONED, ACTIVE, PASSWORD_EXPIRED, LOCKED_OUT, RECOVERY, SUSPENDED, DEPROVISIONED |

**Custom attributes**: added via Admin Console or API; types: string, number, boolean, array of strings, integer. Usable in group rules, profile mappings, and Workflows.

### Profile mastering

Profile mastering defines the authoritative source for each attribute.

```
Attribute: department
  Master: Workday (HR system)

Attribute: phoneNumber
  Master: Okta (user self-service update)

Attribute: samAccountName
  Master: Active Directory
```

**Master priority** (when multiple sources provide the same attribute):
1. Application masters (HR, AD, LDAP) take priority over Okta.
2. Among application masters, priority is configurable in the Admin Console.
3. Okta-mastered attributes can be edited by users (self-service) or admins.

### Group types

| Group type | Source | Use case |
|---|---|---|
| Okta group | Manually managed in Okta | Static group assignments |
| Dynamic (Okta rule) | OEL expression rule | Auto-membership based on profile attributes |
| AD group | Synced from Active Directory | Mirror AD group structure |
| LDAP group | Synced from LDAP directory | Mirror LDAP groups |
| App group | Pushed from application | Application-defined groups |

---

## OIN integration patterns

### SAML 2.0 integration (SP-initiated)

```
User clicks app in Okta dashboard or navigates to app URL
  -> SP redirects to Okta SAML endpoint
  -> Okta authenticates user (if no active session)
  -> Okta generates SAML Assertion with configured attributes
  -> User is POST-redirected to SP's ACS URL
  -> SP validates assertion, creates local session
```

**Key SAML configuration:**
- **Entity ID**: unique identifier for the SP (typically a URL).
- **ACS URL**: where Okta sends the SAML response.
- **Name ID**: user identifier in the assertion (email, Okta username, or custom).
- **Attribute statements**: additional claims (groups, department, custom attributes).
- **Signing**: assertions signed with Okta's app-specific certificate.

### OIDC integration

Configuration values:
- **Client ID / Client Secret**: application credentials (store via `secrets-hygiene`).
- **Redirect URIs**: allowed callback URLs.
- **Grant types**: Authorization Code with PKCE (preferred), client credentials, device code; implicit is deprecated.
- **Scopes**: `openid`, `profile`, `email`, `address`, `phone`, `offline_access`, custom scopes.
- **Token configuration**: access token lifetime, refresh token rotation policy.

### SCIM 2.0 provisioning

| Okta action | SCIM request |
|---|---|
| User assigned to app | POST /Users |
| Profile attribute change | PATCH /Users/{id} |
| User unassigned from app | PATCH /Users/{id} (active: false) |
| Group pushed | POST /Groups |
| Group membership change | PATCH /Groups/{id} |
| Import users from app | GET /Users (paginated) |

---

## Event hooks and inline hooks

### Event hooks

Asynchronous webhooks triggered by Okta events. Fire-and-forget: Okta does not wait for the response. Use for notifications, external system updates, and logging. Delivery guarantee: at-least-once; implement idempotent handling.

### Inline hooks

Synchronous hooks that modify Okta behaviour in real-time. Timeout: 3 seconds. Fallback behaviour is configurable (proceed without hook, or fail closed).

| Hook type | Trigger | Common use case |
|---|---|---|
| Token Inline Hook | Token issuance | Add custom claims from an external data source |
| SAML Assertion Inline Hook | SAML assertion generation | Modify SAML attributes from external source |
| Import Inline Hook | User import from app/directory | Filter or transform imported users |
| Registration Inline Hook | Self-service registration | Custom validation during sign-up |
| Password Import Inline Hook | First login after migration | Validate password against legacy system |
| Telephony Inline Hook | SMS/Voice MFA delivery | Custom SMS/voice provider |

Do not use inline hooks for heavy processing. Respond within the 3-second timeout or Okta will cancel the hook and apply the configured fallback.

---

## Rate limits reference

| Category | Rate limit | Key endpoints |
|---|---|---|
| Authentication | 600/minute | `/api/v1/authn`, `/api/v1/sessions` |
| User management | 600/minute | `/api/v1/users` |
| App management | 600/minute | `/api/v1/apps` |
| Group management | 600/minute | `/api/v1/groups` |
| Token issuance | 2400/minute | `/oauth2/*/v1/token` |
| System Log | 120/minute | `/api/v1/logs` |

**Rate limit headers:**

```
X-Rate-Limit-Limit: 600          # Maximum requests per window
X-Rate-Limit-Remaining: 450      # Remaining in current window
X-Rate-Limit-Reset: 1712345678   # Unix timestamp when window resets
```

**Best practices:**
- Implement exponential backoff with jitter on 429 responses.
- Cache frequently accessed data (user profiles, group memberships).
- Use delta APIs (`/api/v1/logs?since=...`) rather than full scans.
- Batch operations where possible (bulk user import).
- Monitor rate-limit consumption in System Log.

---

## Okta Expression Language (OEL) reference

OEL is used in dynamic group rules and attribute mappings.

```javascript
// String operations
String.len(source.login)
String.substringBefore(source.email, "@")
String.substringAfter(source.email, "@")
String.toUpperCase(source.department)
String.replace(source.login, " ", ".")

// Conditional logic
source.department == "Engineering" ? "eng-access" : "default-access"
source.userType == "Employee" ? true : false

// Array/group operations
Arrays.contains(source.groups, "Admins")
Arrays.toCsvString(source.groups)
Arrays.size(source.groups)

// Date operations
Time.now()
Time.fromWindowsToUnix(source.lastPasswordChange)

// Null handling
source.department != null ? source.department : "Unassigned"
```

**Group rule expressions:**

```javascript
// All users in Engineering department
user.department == "Engineering"

// Users in a specific AD group
isMemberOfGroupName("Domain Users")

// Combined conditions
user.department == "Engineering" AND user.office == "NYC"

// Substring match
String.stringContains(user.email, "@company.com")
```

---

## Security and session architecture

**Data protection:**
- Encryption at rest: AES-256 for all stored data.
- Encryption in transit: TLS 1.2+ for all communications.
- Key management: Okta-managed HSM for signing keys.

**Session security:**
- Session cookie attributes: HTTPOnly, Secure, SameSite.
- Optional session binding to client IP.
- Admin-initiated revocation of all sessions for a user.
- Idle timeout and max session lifetime configurable per global session policy.

**Network zones:**
- **IP zones**: specific IP ranges (corporate network, VPN egress).
- **Dynamic zones**: based on ASN, geolocation, or IP type (proxy, Tor).
- **Block list zones**: known malicious IPs.
- Use in authentication policies: trusted zones may have relaxed MFA requirements. See `utc-timestamps` for session timeout reasoning.
