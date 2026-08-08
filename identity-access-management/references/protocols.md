# IAM federation and directory protocols

Deep technical reference for the authentication, federation, provisioning, and directory protocols that apply across all IAM platforms. For access control models, tokens, and sessions see `access-control-and-tokens.md`; for the joiner-mover-leaver lifecycle and governance see `governance-and-zero-trust.md`.

---

## OpenID Connect (OIDC)

OIDC is an identity layer on top of OAuth 2.0. It answers "who is this user?" while OAuth 2.0 answers "what can this client do?". It is the default choice for new applications, SPAs, APIs, and mobile.

### Authorization-code flow with PKCE

The recommended flow for all client types (web apps, SPAs, native apps):

```
1. Client generates code_verifier (random string, 43-128 chars)
2. Client computes code_challenge = BASE64URL(SHA256(code_verifier))
3. Client redirects user to /authorize with:
   - response_type=code
   - client_id
   - redirect_uri
   - scope=openid profile email
   - code_challenge
   - code_challenge_method=S256
   - state (CSRF protection)
   - nonce (replay protection)
4. User authenticates at the IdP
5. IdP redirects to redirect_uri with an authorization code
6. Client exchanges code + code_verifier at the /token endpoint
7. IdP validates code_challenge against code_verifier
8. IdP returns: access_token, id_token, refresh_token
```

PKCE (Proof Key for Code Exchange) protects against authorization-code interception. It is now recommended for confidential clients too, not just public ones.

### ID token structure (JWT)

```json
{
  "iss": "https://idp.example.com",      // Issuer
  "sub": "user123",                       // Subject (unique user ID)
  "aud": "client_app_id",                 // Audience (client ID)
  "exp": 1712345678,                      // Expiration
  "iat": 1712342078,                      // Issued at
  "nonce": "abc123",                      // Replay protection
  "auth_time": 1712342000,                // When the user authenticated
  "acr": "urn:mace:incommon:iap:silver",  // Authentication context class
  "amr": ["pwd", "mfa"],                  // Authentication methods
  "azp": "client_app_id",                 // Authorized party
  "at_hash": "..."                        // Access token hash
}
```

ID token validation checklist:
1. Verify the JWT signature against the IdP's JWKS (`/.well-known/jwks.json`).
2. Check `iss` matches the expected IdP.
3. Check `aud` contains your `client_id`.
4. Check `exp` is greater than the current time.
5. Check `nonce` matches what you sent.
6. Check `iat` is within an acceptable window.

### Client-credentials flow

Machine-to-machine, with no user involved:

```
POST /token
  grant_type=client_credentials
  client_id=...
  client_secret=...   (or a client-assertion JWT for private_key_jwt)
  scope=api://resource/.default
```

Returns an access token only. No ID token (there is no user) and no refresh token. Prefer `private_key_jwt` (signed client assertion) over a shared secret where the IdP supports it.

### Discovery and JWKS

Every OIDC provider exposes `/.well-known/openid-configuration`:
- `authorization_endpoint`: where to send users to authenticate.
- `token_endpoint`: where to exchange codes for tokens.
- `jwks_uri`: public keys for verifying token signatures.
- `userinfo_endpoint`: get additional user claims.
- `scopes_supported`, `response_types_supported`, `claims_supported`: capability advertisement.

---

## SAML 2.0

Security Assertion Markup Language is an XML-based federation protocol for enterprise SSO and B2B federation. Mature and widely supported, at the cost of XML complexity and large browser-borne payloads.

### SP-initiated flow

```
1. User visits the Service Provider (SP)
2. SP generates an AuthnRequest (XML, optionally signed)
3. SP redirects the user to the IdP SSO URL (HTTP-Redirect or HTTP-POST binding)
4. User authenticates at the IdP
5. IdP generates a SAML Response containing one or more Assertions
6. IdP POST-redirects the user to the SP's Assertion Consumer Service (ACS) URL
7. SP validates Response signature, Assertion signature, and conditions
8. SP creates a local session
```

Prefer SP-initiated over IdP-initiated flows: IdP-initiated flows have no `InResponseTo` to validate, which weakens replay protection.

### SAML assertion structure

```xml
<saml:Assertion>
  <saml:Issuer>https://idp.example.com</saml:Issuer>
  <ds:Signature>...</ds:Signature>
  <saml:Subject>
    <saml:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent">user@example.com</saml:NameID>
    <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
      <saml:SubjectConfirmationData
        NotOnOrAfter="2024-04-01T12:05:00Z"
        Recipient="https://sp.example.com/saml/acs"
        InResponseTo="_request123"/>
    </saml:SubjectConfirmation>
  </saml:Subject>
  <saml:Conditions NotBefore="..." NotOnOrAfter="...">
    <saml:AudienceRestriction>
      <saml:Audience>https://sp.example.com</saml:Audience>
    </saml:AudienceRestriction>
  </saml:Conditions>
  <saml:AuthnStatement AuthnInstant="..." SessionIndex="...">
    <saml:AuthnContext>
      <saml:AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</saml:AuthnContextClassRef>
    </saml:AuthnContext>
  </saml:AuthnStatement>
  <saml:AttributeStatement>
    <saml:Attribute Name="email"><saml:AttributeValue>user@example.com</saml:AttributeValue></saml:Attribute>
    <saml:Attribute Name="groups"><saml:AttributeValue>Admins</saml:AttributeValue></saml:Attribute>
  </saml:AttributeStatement>
</saml:Assertion>
```

### SAML validation checklist

1. Verify the XML signature on the Response and/or Assertion using the IdP's X.509 certificate.
2. Check `Issuer` matches the expected IdP.
3. Check `Audience` matches your SP entity ID.
4. Check `NotBefore` and `NotOnOrAfter` timestamps (clock-skew tolerance: 2-5 minutes).
5. Check `Recipient` matches your ACS URL.
6. Check `InResponseTo` matches your original AuthnRequest ID (prevents replay).
7. Canonicalise before signature verification to defeat XML wrapping attacks.

### Common SAML attacks

- **XML Signature Wrapping (XSW)**: the attacker moves the signed assertion and injects a malicious one. Mitigation: strict signature-reference validation.
- **Assertion replay**: resubmit a captured assertion. Mitigation: track consumed AssertionIDs and enforce `NotOnOrAfter`.
- **IdP-initiated flow abuse**: no `InResponseTo` to validate. Mitigation: prefer SP-initiated flow.

---

## Protocol selection

| Protocol | Use when | Strengths | Limitations |
|---|---|---|---|
| OIDC | New apps, SPAs, APIs, mobile | Modern, JSON-based, good libraries, token-based | Requires HTTPS; stateless tokens need a revocation strategy |
| SAML 2.0 | Enterprise SSO, legacy apps, B2B federation | Mature, widely supported, signed assertions | XML complexity, large payloads, browser-based only |
| WS-Federation | Microsoft-centric, AD FS | Native to Windows Identity Foundation | Legacy, being replaced by OIDC |
| LDAP(S) | Directory lookups, legacy app auth | Universal directory protocol | Not a federation protocol; credential-exposure risk |
| SCIM 2.0 | User/group provisioning (not auth) | Standardised REST API for identity lifecycle | Inconsistent vendor implementations |

Federation trust topologies:
- **Hub-and-spoke**: a central IdP authenticates for all SPs. Simplest model; a single point of failure.
- **Mesh**: direct trusts between IdPs. Complex at scale; use for B2B federation between large enterprises.
- **Broker**: an intermediary translates between protocols and IdPs. Use when connecting SAML-only apps to an OIDC IdP or vice versa.

---

## SCIM 2.0 (System for Cross-domain Identity Management)

A REST API standard for automating user and group provisioning. SCIM moves identity data; it does not authenticate users.

### Core endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | /Users | Create user |
| GET | /Users/{id} | Read user |
| GET | /Users?filter=... | Search users |
| PUT | /Users/{id} | Full replace |
| PATCH | /Users/{id} | Partial update |
| DELETE | /Users/{id} | Delete or deactivate user |
| POST | /Groups | Create group |
| PATCH | /Groups/{id} | Update group membership |

### SCIM user schema

```json
{
  "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
  "userName": "jdoe@example.com",
  "name": { "givenName": "John", "familyName": "Doe" },
  "emails": [{ "value": "jdoe@example.com", "type": "work", "primary": true }],
  "active": true,
  "groups": [{ "value": "group-id", "display": "Engineering" }],
  "externalId": "HR-12345"
}
```

### SCIM operational patterns

- **Full sync**: periodic `GET /Users` with pagination, compared against the IdP and reconciled. Use for initial load and drift detection.
- **Incremental push**: the IdP pushes changes as they happen via POST/PATCH/DELETE. Real-time but needs reliable event delivery.
- **Filter-based pull**: the SP pulls changes using `filter=meta.lastModified gt "2024-01-01T00:00:00Z"`. Polling-based.

Common issues: vendors implement SCIM inconsistently (attribute naming, error codes, filter support); PATCH group-membership updates are expensive for large groups; soft delete (`active=false`) versus hard delete (HTTP DELETE) semantics vary by vendor.

---

## Kerberos protocol

Ticket-based authentication used by Active Directory. All operations use symmetric-key cryptography.

### Authentication flow

```
Client                     KDC (DC)                    Service
  |                          |                            |
  |--- AS-REQ (username) --->|                            |
  |    (encrypted with       |                            |
  |     user's password hash)|                            |
  |                          |                            |
  |<-- AS-REP (TGT) ---------|                            |
  |    (TGT encrypted with   |                            |
  |     KRBTGT hash)         |                            |
  |                          |                            |
  |--- TGS-REQ (TGT+SPN) --->|                            |
  |                          |                            |
  |<-- TGS-REP (ST) ---------|                            |
  |    (ST encrypted with    |                            |
  |     service account hash)|                            |
  |                          |                            |
  |--- AP-REQ (ST) -------------------------------------->|
  |                          |                            |
  |<-- AP-REP (optional mutual auth) --------------------|
```

### Key Kerberos concepts

- **TGT (Ticket Granting Ticket)**: proves user identity to the KDC. Default lifetime 10 hours, renewable for 7 days.
- **Service Ticket (ST)**: proves user identity to a specific service. Contains the PAC with group memberships.
- **SPN (Service Principal Name)**: identifies a service, for example `HTTP/web.example.com` or `MSSQLSvc/sql01.example.com:1433`.
- **KRBTGT account**: the KDC's own account. Its password hash encrypts all TGTs; compromise enables a Golden Ticket.
- **PAC (Privilege Attribute Certificate)**: embedded in tickets, carries the user SID and group SIDs, used for authorization.

### Kerberos attacks

| Attack | Mechanism | Detection | Mitigation |
|---|---|---|---|
| Kerberoasting | Request an ST for a service with an SPN, crack offline | Event 4769 with RC4 encryption | Use AES, long service-account passwords, gMSA |
| AS-REP Roasting | Request a TGT for accounts without pre-auth, crack offline | Event 4768 with RC4 | Require pre-auth for all accounts |
| Golden Ticket | Forge a TGT with a compromised KRBTGT hash | Hard to detect without PAC validation | Rotate KRBTGT twice, deploy Defender for Identity |
| Silver Ticket | Forge an ST with a compromised service-account hash | Service-side PAC validation (rare) | Use gMSA, enable PAC validation |
| Pass-the-Ticket | Steal and reuse tickets from memory | Anomalous ticket-use patterns | Credential Guard, Protected Users group |
| Delegation abuse | Abuse unconstrained or constrained delegation | Event 4624 with delegation flags | Use resource-based constrained delegation; avoid unconstrained |

For AD CS certificate-template abuse (ESC1-ESC8) see the `ad-cs` vendor skill; for domain-controller hardening see `ad-ds`.

---

## LDAP and directory concepts

LDAP (Lightweight Directory Access Protocol) is a hierarchical directory protocol. The tree is built from Distinguished Names (DNs):

```
dc=example,dc=com
  |-- ou=Users
  |     |-- cn=John Doe
  |     |-- cn=Jane Smith
  |-- ou=Groups
  |     |-- cn=Engineering
  |     |-- cn=Admins
  |-- ou=Service Accounts
        |-- cn=svc-app1
```

LDAP operations: Bind (authenticate), Search (find entries), Add, Delete, Modify, Compare.

Search filters use prefix notation: `(&(objectClass=user)(department=Engineering)(!(disabled=TRUE)))`.

Security concerns:
- Use LDAPS (LDAP over TLS, port 636) or StartTLS. Never use plain LDAP (port 389) for authentication.
- A simple bind sends credentials in cleartext without TLS.
- Disable anonymous bind.
- Modern AD security requires LDAP channel binding and signing.

Schema fundamentals:
- **objectClass** defines the required and optional attributes (for example `user`, `group`, `organizationalUnit`).
- **Attribute syntax** is the data type of each attribute (string, integer, DN, octet string).
- **Auxiliary classes** extend objects with extra attributes without changing the structural class.
