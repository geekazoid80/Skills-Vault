# Access control models, tokens, and sessions

Deep technical reference for authorization models, token security, and session management. For the wire protocols (OIDC, SAML, SCIM, Kerberos, LDAP) see `protocols.md`; for governance and zero trust see `governance-and-zero-trust.md`.

---

## Access control models

| Model | Description | Best for | Limitations |
|---|---|---|---|
| RBAC | Permissions attach to roles; users are assigned to roles | Structured organisations, compliance | Role explosion, static, ignores context |
| ABAC | Policies evaluate attributes (user, resource, environment, action) | Dynamic, fine-grained decisions | Complex authoring, harder to audit |
| ReBAC | Permissions derive from relationships between entities | Document sharing, hierarchical orgs | Newer model, fewer implementations |
| PBAC | A central policy engine makes decisions | Consistent cross-app authorization | Evaluation latency, central dependency |

### RBAC (Role-Based Access Control)

Users are assigned to roles; roles hold permissions; users inherit permissions through role membership.

```
User --> Role --> Permission
         |
         +--> Permission
         |
         +--> Permission
```

Best practice:
- Keep roles coarse-grained (10-30 roles for most organisations).
- Use a role hierarchy (Manager inherits from Employee).
- Avoid user-specific permission overrides; they defeat the purpose of RBAC.
- Enforce separation of duties through mutually exclusive roles.
- Certify role assignments quarterly.

### ABAC (Attribute-Based Access Control)

Policies evaluate attributes at decision time:

```
Subject attributes: department=Engineering, clearance=Secret, location=US
Resource attributes: classification=Secret, owner=Engineering
Environment attributes: time=business_hours, network=corporate
Action: read

Policy: PERMIT if subject.clearance >= resource.classification
            AND subject.department = resource.owner
            AND environment.network = corporate
```

ABAC components (the XACML architecture):
- **PEP (Policy Enforcement Point)**: intercepts requests and asks the PDP.
- **PDP (Policy Decision Point)**: evaluates policies and returns permit or deny.
- **PAP (Policy Administration Point)**: where policies are authored.
- **PIP (Policy Information Point)**: retrieves attributes from external sources.

This is the same pattern modern policy engines such as Open Policy Agent (OPA/Rego) implement: externalise the decision from the application.

### Choosing a model

Start with RBAC for structure and compliance. Reach for ABAC when access decisions depend on context (time, location, device, resource sensitivity) that roles cannot capture. ReBAC fits relationship-heavy domains (who-shared-what, org-chart hierarchies). PBAC is the operating model when you centralise decisions across many applications behind one policy engine. Most mature estates run a hybrid: RBAC for coarse grants, ABAC/PBAC for the fine-grained and contextual decisions.

---

## JIT and JEA (privileged access)

**JIT (Just-In-Time) access**: elevated privileges are granted temporarily and auto-revoked.
- Request a privileged role -> approval workflow -> time-limited activation (1-8 hours) -> automatic revocation.
- Implementations: Entra PIM, CyberArk, BeyondTrust, Delinea.

**JEA (Just Enough Administration)**: constrained PowerShell endpoints that limit which commands an admin can run.
- Define role capabilities (allowed cmdlets, parameters, visible functions).
- The user connects via PowerShell remoting to the JEA endpoint.
- The session runs under a virtual account or gMSA with only the permitted commands.

The principle behind both: standing privilege is a liability. Grant the minimum, for the shortest time, with the narrowest command surface, and revoke automatically.

---

## Token security

### JWT (JSON Web Token) best practice

Signing:
- Use RS256 or ES256 for asymmetric signing so verifiers can use the public key.
- Never accept `alg: none`, and never allow algorithm switching (the classic JWT confusion attack).
- Rotate signing keys periodically (90 days is a reasonable default).

Claims:
- Set a short `exp`: 5-15 minutes for access tokens.
- Include `iss`, `aud`, `iat`, `exp` at minimum.
- Use `jti` (JWT ID) to support token-revocation tracking.
- Never put secrets or PII in tokens. A JWT is base64-encoded, not encrypted; anyone holding it can read the payload.

Client-side storage:
- Web apps: HTTP-only, Secure, SameSite=Lax cookies (not localStorage).
- SPAs: in-memory only (not localStorage or sessionStorage).
- Mobile: OS-level secure storage (Keychain on iOS, Keystore on Android).

### Token revocation strategies

| Strategy | Latency | Complexity | Use case |
|---|---|---|---|
| Short-lived tokens | Token lifetime | Low | Default approach; 5-15 min access tokens |
| Token introspection | Real-time | Medium | OAuth 2.0 introspection endpoint, per-request check |
| Blocklist | Near real-time | Medium | Track revoked `jti` values in a fast store (Redis) |
| Refresh-token rotation | Next refresh | Low | Detect stolen refresh tokens via reuse detection |

Short-lived access tokens plus rotating refresh tokens (with reuse detection) is the pragmatic default: it bounds the window of a stolen access token without a per-request introspection round-trip, and reuse detection catches a stolen refresh token on its next use.

---

## Session management

### Session lifecycle

1. **Creation**: after successful authentication, create a server-side session or issue tokens.
2. **Validation**: on each request, validate the session (expiration, binding, revocation).
3. **Renewal**: extend on activity (sliding expiration) or require re-authentication (absolute expiration).
4. **Termination**: explicit logout, timeout, or revocation.

### Session security controls

- **Absolute timeout**: a maximum session lifetime regardless of activity (8-12 hours is typical).
- **Idle timeout**: the session expires after inactivity (15-30 minutes for sensitive apps).
- **Session binding**: bind the session to the client IP, user agent, or device fingerprint.
- **Secure cookie attributes**: HttpOnly, Secure, SameSite=Lax, and an appropriate Domain/Path.
- **Session-fixation prevention**: regenerate the session ID after authentication.
- **Concurrent-session limits**: cap the number of active sessions per user.

Sessions and tokens are where authentication decays into standing access. The controls above bound how long a single authentication event remains trusted; continuous evaluation (see `governance-and-zero-trust.md`) shortens that further by re-checking risk during the session, not only at login.
