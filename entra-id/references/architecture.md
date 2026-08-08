# Entra ID architecture

## Tenant model

### Tenant fundamentals

An Entra ID tenant is an isolated directory instance:
- **Isolation boundary**: each tenant is fully isolated; no data leaks between tenants.
- **Tenant ID**: immutable GUID assigned at creation.
- **Initial domain**: `<tenantname>.onmicrosoft.com`; cannot be changed after creation.
- **Custom domains**: verified via DNS TXT record; used as UPN suffixes.
- **Object limit**: 50,000 by default; extends to 300,000+ with custom domain verification, or effectively unlimited with P1/P2 licensing.
- **Multi-geo**: data residency options for EU, US, and other regions selected at tenant creation.

### Object types

| Object | Description | Key properties |
|---|---|---|
| User | Human or service identity | UPN, mail, displayName, department, manager |
| Group | Security group or Microsoft 365 group | Membership type: assigned or dynamic; mail-enabled flag |
| Device | Registered, joined, or hybrid-joined device | OS, compliance state, last sign-in |
| Application registration | App definition in the tenant | Client ID, redirect URIs, API permissions, certificates/secrets |
| Service Principal | App instance in the tenant | Assigned users/groups, CA policy target |
| Administrative Unit | Delegation boundary for scoped role assignments | Dynamic membership rules (P1), restricted management AUs |
| Conditional Access Policy | Access policy with conditions and controls | Conditions, grant controls, session controls |

### Administrative Units

Administrative Units (AUs) scope directory role assignments without creating OUs:
- Assign roles such as User Administrator or Helpdesk Administrator scoped to users and groups in an AU.
- AUs support dynamic membership rules based on user attributes (P1 licence required).
- Restricted management AUs prevent tenant-level admins from modifying AU members directly.

---

## Authentication flows

### Cloud-only authentication

```
Client -> Entra ID /authorize
  |-- Evaluate Conditional Access policies
  |-- Check Identity Protection risk level
  |-- MFA challenge if required by CA
  |-- Issue tokens (ID token, access token, refresh token)
  |-- Client accesses resource with access token
```

### Hybrid: Password Hash Sync

```
Client -> Entra ID /authorize
  |-- Entra ID looks up user in directory
  |-- Validates password against synced hash (SHA-256 of MD4 hash)
  |-- Conditional Access evaluation
  |-- MFA challenge if required
  |-- Tokens issued
```

Entra Connect syncs a hash of the MD4 hash every 2 minutes. The original password never leaves on-premises. PHS enables Identity Protection risk detections because sign-in events are fully processed in the cloud.

### Hybrid: Pass-Through Auth

```
Client -> Entra ID /authorize
  |-- Entra ID encrypts credentials with PTA agent public key
  |-- Entra ID queues encrypted credentials
  |-- PTA agent (on-premises) picks up request via persistent outbound connection
  |-- PTA agent decrypts and validates against AD
  |-- PTA agent returns success/failure to Entra ID
  |-- Tokens issued if successful
```

PTA agents maintain persistent outbound HTTPS connections to Entra ID; no inbound firewall rules are required. Deploy 3+ agents for high availability. Authentication fails if all PTA agents are unavailable.

### Seamless SSO (desktop SSO)

For domain-joined devices using PHS or PTA:
1. Entra ID returns a 302 redirect to `https://autologon.microsoftazuread-sso.com`.
2. The client's browser sends a Kerberos ticket obtained from AD via the `AZUREADSSOACC$` computer account.
3. Entra ID validates the Kerberos ticket.
4. User is silently authenticated; no password prompt.

Seamless SSO requires the `AZUREADSSOACC$` account to exist in all synced domains. Roll over its Kerberos decryption key every 30 days.

---

## Token architecture

### Token types and lifetimes

| Token | Format | Default lifetime | Storage |
|---|---|---|---|
| ID Token | JWT | 1 hour (not configurable) | In-memory (SPA) or session cookie (web app) |
| Access Token | JWT (v1 or v2) | 60-90 minutes (configurable via token lifetime policy) | In-memory or MSAL cache |
| Refresh Token | Opaque | 90 days sliding window; revoked on password change | Secure storage (MSAL persistent cache) |
| Primary Refresh Token (PRT) | Opaque | 14 days | Device-bound; TPM-protected where available |

### Primary Refresh Token

The PRT is the SSO credential for Entra ID on Windows, macOS (with the Microsoft Enterprise SSO plug-in), and iOS/Android (with the Authenticator app):
- Obtained during device join/registration or first user sign-in on a joined device.
- Contains device claims (`deviceId`, `deviceCompliance`).
- Enables SSO to all applications without re-authentication.
- Protected by TPM when available (device-bound; cannot be extracted without device access).
- Refreshed every 4 hours during an active session; contains the user's most recent MFA claim.
- Used by the CloudAP and WAM broker on Windows to silently obtain access tokens for applications.

### Continuous Access Evaluation

CAE enables near-real-time token revocation beyond the standard access token lifetime:
- Resource providers (Exchange Online, SharePoint, Microsoft Teams, Microsoft Graph) subscribe to critical events from Entra ID.
- Critical events: user account disabled, password changed, MFA requirement added, admin revoke all sessions.
- On a critical event, the resource provider rejects the current access token even if it has not expired.
- CAE-capable access tokens are issued with a 24-hour lifetime (instead of 60-90 minutes) because they can be revoked instantly via the event subscription.

---

## Directory synchronisation

### Entra Connect ADSync architecture

```
On-Premises AD -> Entra Connect Server -> Entra ID
                    |
                    |-- Sync Engine (ADSync service)
                    |-- SQL LocalDB or full SQL Server
                    |-- AD Connector (reads/writes AD)
                    |-- Entra ID Connector (reads/writes Entra ID)
                    |-- Sync Rules Engine (attribute flow rules)
```

**Sync cycle**: every 30 minutes by default. Delta sync processes only changes since the last cycle. Full import and sync process all objects (triggered manually or after rule changes).

### Sync filtering and scoping

| Filter type | Method | Example |
|---|---|---|
| Domain-based | Select specific AD domains | Sync `corp.example.com`, exclude `test.example.com` |
| OU-based | Select specific OUs | Sync only `OU=Users,DC=corp,DC=example,DC=com` |
| Attribute-based | Sync rules with attribute conditions | Sync only where `extensionAttribute1` equals `Sync` |
| Group-based | Pilot sync scoped to a group | Members of `EntraID-Sync-Pilot` only |

### Source anchor

The source anchor is the immutable identifier linking on-premises AD objects to Entra ID objects:
- **Default**: `ms-DS-ConsistencyGuid` (populated from `objectGUID` on first sync by Entra Connect).
- **Legacy**: `objectGUID` used directly in older deployments.
- Cannot be changed after initial sync without recreating the Entra ID object (resulting in a new object losing history).

### Cloud Sync vs. Entra Connect

| Capability | Entra Connect | Cloud Sync |
|---|---|---|
| Architecture | On-premises server | Cloud-managed lightweight agent |
| Multi-forest | Supported (complex join rules) | Supported (simplified) |
| Filtering | OU, domain, attribute, group | OU, attribute |
| Device writeback | Supported | Not supported |
| Exchange hybrid | Full support | Limited |
| Custom sync rules | Full rule editor | Scoping filters and attribute mapping |
| HA model | Staging server (active-passive) | Multiple agents (active-active) |
| Password writeback | Supported | Supported |

---

## Graph API patterns for IAM operations

### Key endpoints

```
# Users
GET  /users/{id}
POST /users                                            # create
PATCH /users/{id}                                      # update

# Groups
GET  /groups/{id}/members
POST /groups/{id}/members/$ref                         # add member

# Conditional Access
GET  /identity/conditionalAccess/policies
POST /identity/conditionalAccess/policies

# PIM role assignments
POST /roleManagement/directory/roleAssignmentScheduleRequests   # activate role
GET  /roleManagement/directory/roleEligibilityScheduleInstances  # list eligible

# Sign-in and audit logs
GET  /auditLogs/signIns
GET  /auditLogs/directoryAudits

# Identity Protection
GET  /identityProtection/riskyUsers
GET  /identityProtection/riskDetections
```

### Permissions model

| Permission | Type | Use case |
|---|---|---|
| `User.Read.All` | Application | Read all user profiles |
| `Directory.Read.All` | Application | Read directory objects |
| `Policy.Read.All` | Application | Read CA policies |
| `RoleManagement.ReadWrite.Directory` | Application | Manage PIM role assignments |
| `IdentityRiskyUser.Read.All` | Application | Read risky user data |
| `AuditLog.Read.All` | Application | Read sign-in and audit logs |

**Delegated vs application permissions**: delegated permissions act in the context of the signed-in user (bounded by user's permissions); application permissions act as the application itself and require admin consent. For automation pipelines reading sign-in logs, use application permissions with a managed identity where possible; use `entra-app-lifecycle` for the service principal and permission grant procedures.

---

## Licensing tier feature matrix

| Feature | Free | P1 | P2 | Governance |
|---|---|---|---|---|
| SSO (unlimited apps) | Yes | Yes | Yes | Yes |
| MFA (security defaults) | Yes | Yes | Yes | Yes |
| Conditional Access | No | Yes | Yes | Yes |
| Dynamic groups | No | Yes | Yes | Yes |
| Application Proxy | No | Yes | Yes | Yes |
| Entra Connect Health | No | Yes | Yes | Yes |
| Self-service password reset | Limited | Yes | Yes | Yes |
| Password writeback | No | Yes | Yes | Yes |
| PIM | No | No | Yes | Yes |
| Identity Protection | No | No | Yes | Yes |
| Access Reviews | No | No | Yes | Yes |
| Entitlement Management | No | No | Yes | Yes |
| Lifecycle Workflows | No | No | No | Yes |
