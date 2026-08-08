# Ping Identity architecture

## PingOne platform

### Environment model

```
PingOne Organisation
  |-- Environment: Production  (PRODUCTION type)
  |     |-- Populations (user groups / segments)
  |     |-- Applications (SAML SP, OIDC client)
  |     |-- Policies (sign-on, MFA, password, device)
  |-- Environment: Staging  (SANDBOX type)
  |-- Environment: Development  (SANDBOX type)
```

Environments are isolated namespaces within an Organisation. PRODUCTION environments have additional controls (higher rate limits, audit logging); SANDBOX environments are for testing and development.

### PingOne APIs

```bash
# Obtain a management token via client credentials
TOKEN=$(curl -s -X POST "https://auth.pingone.com/$ENV_ID/as/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" | jq -r '.access_token')

# Create a user
curl -X POST "https://api.pingone.com/v1/environments/$ENV_ID/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"jdoe@example.com","name":{"given":"John","family":"Doe"},"username":"jdoe"}'

# Create an OIDC application
curl -X POST "https://api.pingone.com/v1/environments/$ENV_ID/applications" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"My App","type":"WEB_APP","protocol":"OPENID_CONNECT"}'
```

Store all client credentials via `secrets-hygiene`. Use `utc-timestamps` for token `exp` handling.

---

## PingFederate architecture

### Network topology

```
External Partners           |  DMZ              |  Internal Network
                            |                   |
Partner IdP/SP --SAML-----> | PingFederate      | ---> PingDirectory (LDAP)
                            | Port 9031 (HTTPS) | ---> Database (JDBC)
Internal Apps <--OIDC------ | PingFederate      | ---> Active Directory
                            | Port 9031 (HTTPS) | ---> HR System
Admin Console               | Port 9999 (HTTPS) |
```

PingFederate communicates with internal systems over LDAP, JDBC, or HTTP. External partners connect via SAML/OIDC over HTTPS (port 9031). The Admin Console runs on port 9999 and must be restricted to management networks.

### Connection types

| Connection type | PingFederate role | Use case |
|---|---|---|
| SP Connection | IdP (issues assertions) | PingFederate authenticates users and issues SAML/OIDC tokens to a partner or internal SP |
| IdP Connection | SP (receives assertions) | PingFederate receives assertions from an external IdP (partner federation, inbound SSO) |
| OAuth Client | Authorisation server | Application registers for OAuth 2.0 / OIDC flows |
| Token Exchange | Intermediary | Exchange one token type for another (RFC 8693): user token to service token, JWT to SAML |

### Adapter model

PingFederate's authentication policy is composed from adapters:

**IdP Adapters** (authenticate the user):
- HTML Form Adapter: username/password form
- Kerberos Adapter: Windows Integrated Authentication (desktop SSO)
- Certificate Adapter: client certificate authentication
- RADIUS Adapter: RADIUS-based authentication (for legacy MFA systems)
- Custom Adapter (Java SPI): arbitrary authentication logic

**SP Adapters** (deliver identity to the application):
- OpenToken Adapter: proprietary token for PingAccess integration
- OIDC Adapter: deliver identity via OIDC tokens
- Custom Adapter (Java SPI): arbitrary delivery logic

**Authentication Policy chain example:**
```
Kerberos Adapter
  -> Success: proceed to token issuance
  -> Failure: fall back to HTML Form Adapter
       HTML Form Adapter
         -> Success: require TOTP MFA (second adapter)
         -> Failure: deny access
```

### Clustering

PingFederate supports active-active clustering:
- Cluster nodes share configuration via a console-managed replication mechanism.
- User sessions are replicated across nodes.
- A load balancer distributes traffic; sticky sessions are recommended but not required.
- Each node must have its own SSL certificate bound to its node hostname; the cluster shares a signing certificate.

Cluster administration: changes made on the Admin Console node are replicated to all runtime nodes.

---

## PingAccess architecture

### Deployment models

**Reverse proxy:** PingAccess sits in the network path between the client and the backend application. All traffic passes through PingAccess; it validates tokens, enforces policies, and injects identity headers.

**Agent-based:** PingAccess agents (Apache module, IIS module) intercept requests at the web server layer and call back to the PingAccess Policy Server for access decisions.

### Request flow (reverse proxy model)

```
Client request
  -> PingAccess (reverse proxy)
       |-- Is there a valid web session cookie?
       |     Yes -> evaluate access policy
       |     No  -> redirect to PingFederate / PingOne for authentication
       |
       |-- Evaluate URL-based access policy
       |     (path match, HTTP method, user role/attribute conditions)
       |
       |-- Validate OAuth access token (introspection or JWKS local validation)
       |
       |-- Inject identity headers (X-User-ID, X-Roles, X-Org-ID)
       |
       |-- Forward request to backend
```

### Session vs. token model

| Model | How PingAccess maintains state | Application impact |
|---|---|---|
| Web session | PingAccess creates a session cookie after authentication | Application is stateless; session managed by PingAccess |
| Token-based | Application presents an OAuth token per request | Application manages token acquisition and refresh |

Clarify which model the application expects before configuring PingAccess. Mixing models produces double-authentication prompts or session-not-found errors.

---

## PingDirectory architecture

### Key characteristics

- **Java-based LDAP directory**: tunable JVM configuration; heap must accommodate the entry cache.
- **High-performance**: millions of entries, thousands of operations per second.
- **Multi-master replication**: synchronise across data centres; supports active-active replication topologies.
- **Consent management**: built-in per-attribute GDPR consent tracking; applications can record and query consent grants.
- **SCIM 2.0 native**: exposes a SCIM endpoint natively for modern provisioning pipelines.
- **Field-level encryption**: encrypt individual LDAP attributes at rest.
- **Data masking**: return masked values for sensitive attributes based on access permissions.

### LDAP connection configuration

```
Connection URL:    ldaps://pingdir.example.com:636
Base DN:           dc=example,dc=com
Bind DN:           cn=admin,dc=example,dc=com
Bind credential:   (store via secrets-hygiene)
User DN:           ou=People,dc=example,dc=com
```

### When to use PingDirectory vs. AD DS

| PingDirectory | AD DS |
|---|---|
| Application-facing LDAP; high-performance reads | Windows authentication, Group Policy, Kerberos, device management |
| Cloud-native or cross-platform | Windows-centric on-premises |
| SCIM-native provisioning | Manual or LDAP-based provisioning |
| Built-in GDPR consent management | No native consent management |
| No Windows dependency | Windows Server required |

---

## DaVinci orchestration

### Core concept

DaVinci is a visual, no-code orchestration platform. Authentication and identity journeys are composed by connecting drag-and-drop connector nodes in a canvas. Each flow is a directed graph of connectors; execution follows the graph edges based on connector output values.

### Connector categories (200+ available)

| Category | Examples |
|---|---|
| PingOne services | PingOne SSO, PingOne MFA, PingOne Protect, PingOne Directory |
| External IdPs | Okta, Entra ID (Azure AD), Google, GitHub, social providers |
| Communication | Email (SendGrid, SMTP), SMS (Twilio, MessageBird), push notification |
| Data stores | HTTP connector (generic REST), LDAP, PostgreSQL, MySQL |
| Logic | Branch, loop, variable, error handler, annotation |
| Custom | Webhook (generic HTTP POST/GET), custom connector (OpenAPI spec) |

### Flow patterns

**Progressive profiling:**
1. User authenticates (minimal claims).
2. On subsequent sessions, DaVinci checks profile completeness.
3. If profile is incomplete, present a profile-update form before redirecting to the application.
4. Continue until profile is complete; then skip the form.

**Step-up authentication:**
1. User is authenticated with a low-assurance flow (e.g., username/password).
2. On access to a sensitive resource, the application calls DaVinci with the existing session token.
3. DaVinci evaluates the assurance level required; if insufficient, triggers an MFA challenge.
4. On successful MFA, DaVinci issues a high-assurance token.

**Self-service registration with identity proofing:**
1. User submits registration form.
2. DaVinci calls an email-verification connector.
3. After email verification, DaVinci optionally calls an identity-proofing connector (document scan, liveness check).
4. On success, DaVinci creates the user in PingOne Directory and optionally provisions downstream applications.
5. DaVinci triggers MFA enrolment before redirecting to the application.

### DaVinci vs. PingFederate authentication policies

| Dimension | DaVinci | PingFederate |
|---|---|---|
| Interface | Visual, no-code canvas | XML/JSON configuration files |
| Deployment | Cloud only (PingOne) | On-premises or cloud |
| Iteration speed | Fast; drag-and-drop | Slower; config changes require deployment |
| Debugging | Built-in flow debugger | Log file analysis |
| Complexity ceiling | Medium | High |
| Migration path | Recommended for new cloud deployments | Existing on-prem federation investment |

---

## PingOne Protect integration

### Client-side signal collection

```javascript
// Initialise the PingOne Protect SDK in the browser
import { BehavioralData } from '@pingidentity/p14c-js-sdk-protect';

const behavioralData = new BehavioralData();
behavioralData.setFlowContext('login');
behavioralData.startCollection();

// On form submit, collect and send signals
const signals = await behavioralData.getData();
// Signals are sent to PingOne Protect API; the risk score is returned
```

### Risk evaluation and policy response

| Risk score | Example policy response |
|---|---|
| LOW | Allow passwordless or skip MFA step |
| MEDIUM | Require MFA (TOTP, push, FIDO2) |
| HIGH | Block access; require identity verification or human review |

---

## PingOne Neo and verifiable credentials

### Standards

| Standard | Role |
|---|---|
| W3C Verifiable Credentials Data Model | Schema for the credential payload |
| Decentralised Identifiers (DID) | Identifier for issuers, holders, and verifiers |
| OpenID for Verifiable Credentials (OID4VC) | Protocol for issuance and presentation |

### Lifecycle

1. **Issuance**: organisation (issuer) issues a W3C VC to a user's digital wallet (PingOne Neo app or compatible wallet).
2. **Storage**: user stores the VC in their digital wallet on their device.
3. **Presentation**: verifier (e.g., another application or organisation) requests proof of a claim; user presents the VC from their wallet.
4. **Verification**: verifier checks the VC's cryptographic proof against the issuer's DID document.

**Use cases:** employee digital badge, professional certification, government identity proofing for high-assurance enrolment, age verification, access pass for physical or digital resources.
