---
name: identity-access-management
description: "Use for Identity and Access Management architecture, design, comparison, and cross-platform operations: authentication vs authorization, identity federation (OIDC, SAML 2.0, WS-Federation), provisioning and the joiner-mover-leaver lifecycle (SCIM, JIT, HR-driven), MFA and phishing-resistant factors (FIDO2/passkeys), access control models (RBAC/ABAC/ReBAC/PBAC), JIT/JEA privileged access, identity governance (access reviews, certifications, SOD, entitlement management), token and session security, Kerberos and LDAP directory concepts, and zero trust identity. References: protocols.md, access-control-and-tokens.md, governance-and-zero-trust.md, platform-selection.md. Triggers include \"IAM\", \"identity management\", \"access management\", \"SSO\", \"single sign-on\", \"MFA\", \"passkeys\", \"FIDO2\", \"federation\", \"OIDC\", \"OAuth\", \"SAML\", \"SCIM provisioning\", \"JML lifecycle\", \"RBAC\", \"ABAC\", \"least privilege\", \"access review\", \"access certification\", \"separation of duties\", \"SOD\", \"entitlement management\", \"PIM\", \"PAM\", \"JIT access\", \"Kerberos\", \"LDAP\", \"zero trust identity\", \"which IdP\", \"IdP selection\", \"identity federation design\", \"deprovisioning\". For platform-specific implementation route to the vendor skills in this family: entra-id, okta, auth0, keycloak, ping-identity, sailpoint, aws-iam, gcp-iam, ad-ds, ad-fs, ad-cs. For Entra ID app-registration lifecycle (OAuth flow choice, MSAL, service principals, API permissions) use entra-app-lifecycle; for credential and signing-key storage use secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Identity and access management

> **Skill marker**: When applying this skill, begin your reply with `[skill: identity-access-management]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the routing and architecture entry point for all IAM work. It owns the cross-platform, comparative, and conceptual layer: how authentication and federation work, how to choose between identity providers, how to design provisioning and governance, and how identity becomes the control plane in zero trust. Platform-specific implementation (Conditional Access policies, Okta Workflows, Keycloak realms, AWS IAM policy language, AD replication) belongs in the vendor skills listed below.

Identity is the new perimeter. Get this wrong and nothing else in the security architecture matters: a compromised identity walks through every other control.

## When to use

- Selecting an identity provider or governance platform before a deployment or migration (Entra ID vs Okta vs Auth0 vs Keycloak vs Ping, SailPoint vs Entra ID Governance).
- Designing an SSO or federation architecture: hub-and-spoke, mesh, or broker; protocol choice across OIDC, SAML, and WS-Federation.
- Planning a provisioning and joiner-mover-leaver lifecycle: SCIM push, JIT provisioning, HR-driven flows, directory sync.
- Choosing an MFA strategy and prioritising phishing-resistant factors (FIDO2/passkeys over push over TOTP over SMS).
- Choosing an access control model (RBAC, ABAC, ReBAC, PBAC) and designing JIT/JEA privileged access.
- Designing an identity governance programme: access reviews, certifications, separation of duties, entitlement management, role mining.
- Explaining or troubleshooting authentication flows end-to-end (OIDC code-with-PKCE, SAML assertion validation, Kerberos ticketing).
- Designing token and session security: lifetimes, revocation strategy, secure storage, continuous evaluation.

## When not to use

- **Platform-specific configuration or troubleshooting**: route to the vendor skill (see "Vendor skills" below).
- **Entra ID app-registration lifecycle** (OAuth flow choice per app type, MSAL integration, service principal creation, API permission grants, client credential discipline): use `entra-app-lifecycle`. That skill owns the developer-facing app-registration surface; the `entra-id` vendor skill owns the platform/admin surface (Conditional Access, PIM, Identity Protection, Entra Connect, governance).
- **Credential, token, and signing-key storage and rotation**: use `secrets-hygiene`. This skill covers how tokens and keys are used; that skill covers where they live.
- **Cloud resource-permission audit beyond the IAM model itself**: route to the relevant cloud skill (`aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`, `aws-networking-audit`).

## Authentication vs authorization (the first classification)

Every IAM question resolves to one of two concerns. Classify first; conflating them is the root cause of most IAM architecture failures.

| Concern | Question answered | Protocols | Examples |
|---|---|---|---|
| Authentication (AuthN) | Who are you? | OIDC, SAML, Kerberos, FIDO2 | Login page, MFA challenge, certificate auth |
| Authorization (AuthZ) | What can you do? | OAuth 2.0, XACML, OPA/Rego | API scopes, role checks, policy decisions |

AuthN establishes identity; AuthZ decides what that identity may do. They are distinct concerns with distinct protocols and distinct failure modes. A system that authenticates correctly but authorises sloppily is just as breached as one that fails to authenticate at all.

## Platform selection

| Technology | Type | Best for | Deployment | Key differentiator | Vendor skill |
|---|---|---|---|---|---|
| Entra ID | Cloud IdP | Microsoft/Azure estates, hybrid with AD | Cloud (SaaS) | Deepest Microsoft integration, Conditional Access, PIM | `entra-id` |
| Okta | Cloud IdP | Multi-cloud, vendor-neutral shops | Cloud (SaaS) | 7,000+ OIN integrations, Workflows | `okta` |
| Auth0 | CIAM | Customer-facing, developer-led identity | Cloud (SaaS) | Actions extensibility, Organizations for B2B | `auth0` |
| Keycloak | IdP | Self-hosted, open-source, full control | Self-hosted | No licensing cost, extensible, identity brokering | `keycloak` |
| Ping Identity | Enterprise IdP | Large enterprise, complex federation | Hybrid/Cloud | DaVinci orchestration, decentralized identity | `ping-identity` |
| SailPoint | IGA | Enterprise governance, certifications, SOD | Cloud (SaaS) | Deep IGA, role mining, IdentityAI | `sailpoint` |
| AWS IAM | Cloud IAM | AWS resource access control | Cloud (AWS) | Fine-grained policy language, Identity Center | `aws-iam` |
| GCP IAM | Cloud IAM | Google Cloud resource access control | Cloud (GCP) | Workload Identity Federation, IAM Recommender | `gcp-iam` |
| AD DS | Directory | Windows-centric on-prem, GPO, Kerberos | On-premises | Group Policy, Kerberos, Windows device management | `ad-ds` |
| AD FS | Federation | On-prem SAML/OIDC federation | On-premises | Claims-based auth (being replaced by Entra ID) | `ad-fs` |
| AD CS | PKI | Enterprise PKI, certificate-based auth | On-premises | Native Windows PKI, auto-enrolment | `ad-cs` |

Quick decision guide:
- Microsoft-centric, migrating to cloud: Entra ID (with Entra Connect bridging on-prem AD DS).
- Multi-cloud, want a vendor-neutral IdP: Okta.
- Customer-facing (CIAM) identity for a SaaS product: Auth0.
- Self-hosted, open-source, full control with no per-seat licensing: Keycloak.
- Large enterprise with complex federation and orchestration needs: Ping Identity.
- Enterprise governance (certifications, SOD, role mining) on top of any IdP: SailPoint.
- Cloud resource access: AWS IAM (AWS), GCP IAM (Google Cloud).
- On-prem Windows directory, federation, or PKI: AD DS, AD FS, AD CS respectively.

Workforce IAM and customer IAM (CIAM) have different requirements. Do not force employees through a CIAM solution or customers through an enterprise workforce IdP.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Federation protocols | OIDC (authorization-code-with-PKCE flow, ID token structure and validation, client credentials, discovery and JWKS), SAML 2.0 (SP-initiated flow, assertion structure, validation checklist, common attacks), SCIM 2.0 provisioning, Kerberos protocol and attacks, LDAP and directory concepts | `references/protocols.md` |
| Access control and tokens | RBAC/ABAC/ReBAC/PBAC models and when to use each, XACML PEP/PDP/PAP/PIP architecture, JIT/JEA privileged access, JWT signing and claims best practice, token revocation strategies, session lifecycle and security controls | `references/access-control-and-tokens.md` |
| Governance and zero trust | Joiner-mover-leaver lifecycle, provisioning patterns (SCIM/JIT/HR-driven/directory-sync), MFA factor strategy and phishing resistance, IGA capabilities (access reviews, certifications, SOD, entitlement management, role mining, PAM), zero trust identity principles and access-decision signals | `references/governance-and-zero-trust.md` |
| Platform selection and patterns | Cross-platform technology comparison, IAM architecture patterns (cloud-first with Entra ID, multi-cloud with Okta, hybrid on-prem + cloud, developer-first CIAM), and the IAM anti-patterns to design against | `references/platform-selection.md` |

## Vendor skills

For platform-specific implementation, configuration, and troubleshooting, route to the vendor skill. These ship across the IAM family PRs.

| Request pattern | Route to |
|---|---|
| Entra ID, Azure AD, Conditional Access, PIM, Identity Protection, Entra Connect, B2B/B2C, governance | `entra-id` |
| Okta, Universal Directory, OIN integrations, Workflows, ThreatInsight | `okta` |
| Auth0, Universal Login, Actions, Organizations, CIAM attack protection | `auth0` |
| Keycloak, realms, identity brokering, Quarkus distribution | `keycloak` |
| Ping Identity, PingFederate, PingOne, DaVinci orchestration | `ping-identity` |
| SailPoint, IdentityNow, access certifications, SOD, role mining | `sailpoint` |
| AWS IAM, IAM Identity Center, SCPs, permission sets, policy language | `aws-iam` |
| Google Cloud IAM, Cloud Identity, Workload Identity Federation | `gcp-iam` |
| Active Directory, domain controllers, GPO, Kerberos, LDAP, replication | `ad-ds` |
| AD FS, claims-based auth, SAML federation with AD FS, WAP | `ad-fs` |
| AD CS, enterprise PKI, certificate templates, ESC vulnerabilities | `ad-cs` |

## Cross-references

- `entra-app-lifecycle`: Entra ID app-registration lifecycle (app type to OAuth flow, MSAL, service principals, API permission grants, federated identity credentials). Owns the developer-facing app-integration surface; the `entra-id` vendor skill owns the platform/admin surface. Use this skill for the lifecycle, `entra-id` for Conditional Access / PIM / hybrid identity.
- `secrets-hygiene`: storage and rotation of client secrets, certificate credentials, signing keys, SCIM bearer tokens, service-account credentials, and Kerberos keytabs. Never inline these in code or commit them; this skill covers their use, that skill covers their custody.
- `utc-timestamps`: token `exp`/`iat`/`nbf`, session absolute and idle timeouts, Kerberos ticket lifetimes (TGT 10h / renew 7d), certificate validity windows, and access-review cycles must be reasoned about in UTC.
- `aws-cloud-ops`, `aws-networking-audit`: AWS IAM ties into the broader AWS account, organisation, and network posture; route resource-permission audit and cross-account design there.
- `azure-cloud-ops`: Entra ID and Azure RBAC for resource access; route Azure resource-permission and subscription governance there.
- `gcp-cloud-ops`: GCP IAM, Workload Identity Federation, and organisation policy for Google Cloud resource access.
- `oncall-runbooks`: identity incident runbooks (IdP outage, mass account lockout, golden-ticket response, compromised admin credential, federation trust break).

## Red flags

- **"One IdP for everything."** Workforce IAM and CIAM have different requirements; forcing one tool across both produces a poor fit on both sides.
- **"MFA is enough."** MFA is critical but insufficient. Token theft, session hijacking, and MFA-fatigue attacks bypass it. Layer device trust, conditional access, and continuous evaluation, and prefer phishing-resistant factors (FIDO2/passkeys).
- **"Sync all attributes everywhere."** Minimise attribute propagation. Each downstream system gets only the attributes it needs; over-syncing creates privacy exposure and expands blast radius.
- **"Flat RBAC with hundreds of roles."** Role explosion means the access model is wrong. Consider ABAC or group nesting. More than ~50 roles in a small organisation is a warning sign.
- **"No service-account governance."** Service accounts, API keys, and managed identities are identities too. They need lifecycle management, rotation, and least privilege like human identities.
- **"Delaying deprovisioning."** Orphaned accounts are a top attack vector. Automate deprovisioning from HR-leaver events; target disablement within one hour of termination.
- **"Skipping access reviews."** Access accrues over time. Without periodic certification, users accumulate permissions far beyond need. Quarterly reviews are the minimum for privileged access.

## Bottom line

Classify the request as authentication or authorization first, then as conceptual or platform-specific. For conceptual, federation, governance, and selection work, load the matching reference. For implementation, route to the vendor skill. Treat identity as the control plane: least privilege, phishing-resistant MFA, automated joiner-mover-leaver, and continuous verification are the load-bearing decisions, and everything downstream depends on getting them right.
