# IAM platform selection, architecture patterns, and anti-patterns

Deep reference for choosing IAM technologies and assembling them into architectures. For protocols see `protocols.md`; for governance see `governance-and-zero-trust.md`. The umbrella `SKILL.md` carries the quick-decision summary; this reference carries the full comparison and the worked patterns.

---

## Technology comparison

| Technology | Type | Best for | Deployment | Key differentiator |
|---|---|---|---|---|
| Entra ID | Cloud IdP | Microsoft/Azure shops, hybrid with AD | Cloud (SaaS) | Deepest Microsoft integration, Conditional Access, PIM |
| Okta | Cloud IdP | Multi-cloud, IdP-agnostic shops | Cloud (SaaS) | 7,000+ OIN integrations, Workflows, vendor-neutral |
| Auth0 | CIAM | Customer-facing identity, developer-focused | Cloud (SaaS) | Actions extensibility, Organizations for B2B |
| Keycloak | IdP | Self-hosted, open-source, customisable | Self-hosted | Full control, no licensing cost, extensible |
| Ping Identity | Enterprise IdP | Large enterprise, complex federation | Hybrid/Cloud | DaVinci orchestration, decentralized identity |
| AD DS | Directory | Windows-centric on-prem, GPO, Kerberos | On-premises | Group Policy, Windows device management, Kerberos |
| AD FS | Federation | On-prem SAML/OIDC federation | On-premises | Claims-based auth, being replaced by Entra ID |
| AD CS | PKI | Enterprise PKI, certificate-based auth | On-premises | Native Windows PKI, auto-enrolment |
| AWS IAM | Cloud IAM | AWS resource access control | Cloud (AWS) | Fine-grained AWS policy language, Identity Center |
| GCP IAM | Cloud IAM | Google Cloud resource access control | Cloud (GCP) | Workload Identity Federation, IAM Recommender |
| SailPoint | IGA | Enterprise governance, certifications, SOD | Cloud (SaaS) | Deep IGA, IdentityAI, role mining |

The first split is workforce versus customer (CIAM) versus cloud-resource IAM. Entra ID, Okta, Ping, AD, and SailPoint serve the workforce; Auth0 (and Okta CIC) serves customers; AWS IAM and GCP IAM control access to cloud resources, not people-to-app SSO. A complete estate usually runs more than one: a workforce IdP, a CIAM platform if there is a customer-facing product, cloud-native IAM per cloud, and often an IGA layer on top.

---

## IAM architecture patterns

### Pattern 1: cloud-first with Entra ID

```
Entra ID (primary IdP)
  |-- Conditional Access (policy engine)
  |-- PIM (privileged access)
  |-- Entra Connect (hybrid sync from AD DS)
  |-- SCIM provisioning to SaaS apps
  |-- B2B/B2C for external identities
```

Best for Microsoft-centric organisations migrating to cloud. AD DS remains the on-prem source of truth, Entra Connect syncs to the cloud, and Conditional Access becomes the zero trust policy engine.

### Pattern 2: multi-cloud with Okta

```
Okta (central IdP)
  |-- Adaptive MFA (risk-based)
  |-- Lifecycle Management (HR-driven provisioning)
  |-- OIN integrations (SAML/OIDC to SaaS apps)
  |-- API Access Management (OAuth 2.0 for APIs)
  |-- Identity Governance (certifications)
```

Best for multi-cloud organisations wanting vendor-neutral identity that is not tied to any single cloud provider's ecosystem.

### Pattern 3: hybrid on-prem and cloud

```
AD DS (on-prem directory, source of truth for Windows)
  |-- AD FS or Entra Connect (federation/sync to cloud)
  |-- Entra ID or Okta (cloud IdP for SaaS apps)
  |-- AD CS (PKI for certificate-based auth)
  |-- PAM solution (CyberArk, Delinea) for privileged access
```

Best for organisations with significant on-prem Windows infrastructure. The trend is to retire AD FS in favour of Entra Connect plus Conditional Access, but many estates still run both during migration.

### Pattern 4: developer-first CIAM

```
Auth0 (customer-facing identity)
  |-- Universal Login (customisable, hosted login)
  |-- Social connections (Google, Apple, Facebook)
  |-- Organizations (B2B multi-tenancy)
  |-- Actions (extensibility hooks)
  |-- Attack Protection (brute force, bot, breached password)
```

Best for SaaS applications and developer-led identity for customer-facing apps. Keep this separate from the workforce IdP: customers and employees have different scale, privacy, and self-service requirements.

---

## Anti-patterns to design against

1. **"One IdP for everything."** Workforce IAM and CIAM have different requirements. Do not force employees through a CIAM solution or customers through an enterprise workforce IdP.

2. **"MFA is enough."** MFA is critical but insufficient. Token theft, session hijacking, and MFA-fatigue attacks bypass it. Layer device trust, conditional access, and continuous evaluation, and prefer phishing-resistant factors.

3. **"Sync all attributes everywhere."** Minimise attribute propagation. Each downstream system should receive only the attributes it needs. Over-syncing creates privacy exposure and expands blast radius.

4. **"Flat RBAC with hundreds of roles."** Role explosion indicates the access model is wrong. Consider ABAC or group nesting. More than ~50 roles in a small organisation is a warning sign.

5. **"No service-account governance."** Service accounts, API keys, and managed identities are identities too. They need lifecycle management, rotation, and least privilege just like human identities.

6. **"Delaying deprovisioning."** Orphaned accounts are a top attack vector. Automate deprovisioning from HR events; target accounts disabled within one hour of termination.

7. **"Skipping access reviews."** Access accrues over time. Without periodic certification, users accumulate permissions far beyond need. Quarterly reviews are the minimum for privileged access.
