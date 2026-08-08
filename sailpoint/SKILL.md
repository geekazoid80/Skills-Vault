---
name: sailpoint
description: "Use for SailPoint IdentityNow and Atlas platform implementation, configuration, and troubleshooting. Covers identity governance and administration (IGA), access certifications and campaign design, lifecycle management (Joiner-Mover-Leaver automation), role management and role mining, separation of duties (SOD) policy definition and enforcement, provisioning connectors and transforms, IdentityAI risk scoring and outlier detection, access request workflows with approval chains, identity cube and source correlation, SailPoint APIs, and the relationship between IdentityNow (SaaS) and IdentityIQ (legacy on-premises). References: architecture.md, governance.md. Triggers include \"SailPoint\", \"IdentityNow\", \"IGA\", \"access certification\", \"role mining\", \"separation of duties\", \"SOD\", \"entitlement management\", \"SailPoint Atlas\", \"IdentityAI\", \"access request\", \"JML lifecycle\", \"Joiner Mover Leaver\", \"identity cube\", \"SailPoint connector\", \"SailPoint transform\", \"SailPoint provisioning\", \"SailPoint campaign\", \"SailPoint workflow\", \"SailPoint API\", \"IdentityIQ\", \"certification campaign\", \"outlier detection SailPoint\", \"role explosion\". For IAM architecture, federation protocols, MFA strategy, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# SailPoint

> **Skill marker**: When applying this skill, begin your reply with `[skill: sailpoint]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers SailPoint IdentityNow and the Atlas platform: identity governance and administration (IGA), access certifications, lifecycle management, role management, separation of duties, provisioning, IdentityAI, and access requests. SailPoint is an IGA platform, not an IdP; it governs access and automates the joiner-mover-leaver lifecycle on top of any IdP. The conceptual layer (federation protocol choice, IdP selection, access-control models) lives in `identity-access-management`.

## When to use

- Designing or configuring access certification campaigns (manager, source owner, entitlement owner, search-based).
- Implementing joiner-mover-leaver (JML) lifecycle automation: identity profiles, provisioning policies, attribute-change detection.
- Setting up role management: IT roles, business roles, role mining, role governance, and controlling role explosion.
- Defining and enforcing SOD policies: toxic-access-combination detection, violation handling, exception workflows.
- Configuring provisioning connectors: Active Directory, Azure AD, Salesforce, ServiceNow, Workday, custom web services.
- Writing transforms for attribute mapping (concat, lower, substringBefore, conditional, etc.).
- Configuring access request workflows: catalog design, approval chains, SOD checks, auto-approval rules.
- Reviewing IdentityAI outputs: risk scores, outlier detection, peer-group analysis, AI-assisted certification.
- Troubleshooting source correlation failures, orphaned accounts, or provisioning errors.
- Migrating from IdentityIQ (on-premises) to IdentityNow (SaaS).

## When not to use

- **IAM architecture, federation protocol design, or IdP selection**: SailPoint is an IGA platform, not an IdP; use `identity-access-management` for IdP selection and federation design.
- **Authentication, MFA, or SSO configuration**: SailPoint does not perform authentication; route to the relevant IdP skill (`okta`, `ping-identity`, `entra-id`, `keycloak`).
- **Credential, connector-secret, and API-token storage or rotation**: use `secrets-hygiene`.
- **Token expiry reasoning or certification-deadline maths**: use `utc-timestamps` alongside this skill.

## Core model

### IdentityNow architecture

SailPoint IdentityNow organises identity governance around these components:

| Component | Purpose |
|---|---|
| Sources | Connections to authoritative (HR) and target systems (AD, SaaS apps, databases) |
| Identity Profiles | Define how identities are created and attributes mapped from source data |
| Access Profiles | Bundles of entitlements representing a level of access |
| Roles | Business-meaningful groupings of Access Profiles |
| Campaigns | Access certification campaigns for periodic review |
| Provisioning Policies | Rules for creating accounts in target systems |
| Workflows | Custom automation triggered by identity events |
| Transforms | Data-transformation rules for attribute mapping |

**Architecture flow:**
```
HR Source (Workday, SAP)
  -> Aggregated into IdentityNow
  -> Identity Profile maps attributes via transforms
  -> Identity Cube (unified view of the identity)
  -> Access Profiles + Roles assigned
  -> Provisioning to target systems (AD, Azure AD, SaaS apps)
```

### Identity Cube

The identity cube is SailPoint's unified identity model. It aggregates accounts from all connected sources (AD, HR, SaaS) into a single identity view, correlating accounts by matching attributes (email, employee ID, UPN). The cube contains: consolidated profile attributes, all access entitlements across all target systems, and optional activity data for access intelligence.

### JML lifecycle

**Joiner:**
HR system creates a new hire record -> SailPoint aggregates the identity -> Identity Profile triggers account creation -> provisioning policies create accounts in AD, email, and base-access roles -> notifications sent -> MFA enrolment initiated.

**Mover:**
HR system updates department/title/location -> SailPoint detects attribute change -> role re-evaluation triggered -> old department role removed, new department role added -> access certification triggered for removed access.

**Leaver:**
HR system sets termination date or deactivates record -> SailPoint detects termination -> pre-termination: disable accounts, revoke VPN -> on termination date: deprovision all accounts -> post-termination: archive data, reclaim licences -> manager notified.

Target disablement within one hour of termination; see `utc-timestamps` for scheduling maths.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | IdentityNow component model, identity cube and correlation, JML lifecycle flows, connector types and SCIM/REST/LDAP/JDBC protocols, transform syntax and examples, Access Profile and Role hierarchy, SailPoint API examples | `references/architecture.md` |
| Governance | Access certification campaign types and configuration, role management and role mining, SOD policy structure and exception workflows, IdentityAI risk scoring and outlier detection, access request catalog design and approval chains | `references/governance.md` |

## Cross-references

- `identity-access-management`: IAM architecture, JML lifecycle design concepts, access-control model selection (RBAC vs. ABAC vs. ReBAC), certification and governance programme design.
- `okta`: SailPoint IGA is frequently deployed on top of Okta as the IdP; Okta handles authentication and provisioning, SailPoint handles certifications, SOD, and role governance. The two complement each other.
- `ping-identity`: SailPoint IGA similarly pairs with PingFederate or PingOne; Ping owns authentication, SailPoint owns governance.
- `secrets-hygiene`: SailPoint connector credentials, API client secrets, and provisioning service account passwords are credentials; handle per `secrets-hygiene` discipline.
- `utc-timestamps`: certification campaign deadlines, access request SLA windows, leaver-disablement timing, and SOD exception expiration must be reasoned in UTC.
- `oncall-runbooks`: provisioning failure, source aggregation outage, certification campaign not closing, and SOD-policy false-positive runbooks.

## Red flags

- **Certification fatigue from over-broad campaigns**: too many items reviewed too frequently causes reviewers to rubber-stamp approvals without meaningful review. Target risk-based, narrowly scoped campaigns; quarterly for standard access, monthly for privileged access.
- **Role explosion**: creating too many fine-grained IT roles defeats the purpose; access model complexity grows, and users end up with roles that are hard to interpret. Target 20 to 50 business roles for most organisations; use Access Profiles for technical granularity.
- **Source correlation failures producing orphaned accounts**: if accounts cannot be correlated to identities (no matching attribute), they appear as orphaned accounts and are invisible to governance. Clean up source-system data quality (consistent email, employee ID) before onboarding sources.
- **SOD policies without an exceptions process**: some users legitimately need conflicting access (a developer who must both create and approve test transactions). Define exception workflows with time-limited approvals and an expiration date before enforcing SOD policies.
- **Provisioning without sandbox testing**: provisioning errors (account created in the wrong OU, wrong attribute values, wrong group membership) are difficult to reverse at scale. Test provisioning policies against a sandbox source before enabling production provisioning.
- **No authoritative HR source**: without a trusted HR system as the authoritative identity source, JML processes cannot be reliably automated. Ambiguity about who is an active employee produces over-provisioning and deprovisioning delays.
- **Ignoring IdentityAI outlier recommendations**: IdentityAI outlier detection surfaces users with access significantly different from their peers. Ignoring outlier reports means access accretes beyond what role-based assignments would allow.

## Bottom line

SailPoint is a governance and lifecycle platform; it always works alongside an IdP (Okta, Ping, Entra ID, Keycloak) rather than replacing one. Establish a trusted authoritative HR source before configuring JML automation. Design access certification campaigns to be narrow and risk-focused rather than broad and fatiguing. Control role explosion: more than 50 business roles in a small organisation signals the access model needs redesign. Load `references/architecture.md` for connector, transform, and component configuration; load `references/governance.md` for certification design, SOD policies, role mining, and IdentityAI.
