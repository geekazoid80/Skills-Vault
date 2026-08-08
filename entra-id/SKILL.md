---
name: entra-id
description: "Use for Microsoft Entra ID (formerly Azure AD) tenant administration, platform configuration, and security hardening. Covers tenant architecture (tenant ID, custom domains, Administrative Units, flat directory structure), Conditional Access as the zero trust policy engine (signals, grant controls, session controls, named locations, report-only mode, What If tool), Privileged Identity Management (PIM) for JIT privileged access (eligible vs active assignments, activation workflow, access reviews for roles), Identity Protection (risk detections: atypical travel, anonymous IP, leaked credentials, password spray; risk-based CA policies), hybrid identity (Entra Connect vs Cloud Sync, Password Hash Sync vs Pass-Through Auth vs federation, Seamless SSO, source anchor, sync filtering), B2B external identities (cross-tenant access settings, guest lifecycle management, access reviews for guests), B2C and Entra External ID for consumer-facing applications, Entra ID Governance (access reviews, entitlement management and access packages, lifecycle workflows for JML automation), Continuous Access Evaluation (CAE), Primary Refresh Token (PRT) architecture, token types and lifetimes, Graph API patterns for IAM operations, licensing tiers (Free, P1, P2, Governance), and Entra Permissions Management (CIEM). References: architecture.md, best-practices.md. Triggers include \"Entra ID\", \"Azure AD\", \"Conditional Access\", \"PIM\", \"Privileged Identity Management\", \"Identity Protection\", \"Entra Connect\", \"Cloud Sync\", \"Password Hash Sync\", \"PHS\", \"Pass-Through Auth\", \"PTA\", \"B2B\", \"B2C\", \"Entra External ID\", \"entitlement management\", \"access package\", \"lifecycle workflow\", \"JML Entra\", \"CAE\", \"Continuous Access Evaluation\", \"PRT\", \"Primary Refresh Token\", \"Entra Governance\", \"access review Entra\", \"named location\", \"authentication strength\", \"FIDO2 Entra\", \"passkeys Entra\", \"Windows Hello for Business\", \"break-glass account\", \"Administrative Units\", \"Entra Permissions Management\", \"CIEM Entra\", \"risky users\", \"risky sign-ins\", \"MFA fatigue Entra\", \"security defaults\", \"ms-DS-ConsistencyGuid\". For IAM architecture, federation protocol choice, MFA strategy, and IdP selection see identity-access-management; for Entra ID app-registration lifecycle (OAuth flow choice, MSAL, service principal creation, API permission grants) see entra-app-lifecycle; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Entra ID

> **Skill marker**: When applying this skill, begin your reply with `[skill: entra-id]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers the Microsoft Entra ID platform from the tenant-admin perspective: Conditional Access, Privileged Identity Management, Identity Protection, hybrid identity, external identities, Entra ID Governance, and the underlying token and authentication architecture. The app-registration and OAuth integration surface (app types, MSAL, service principal creation, API permission grants) belongs to `entra-app-lifecycle`; the conceptual IAM layer (protocol design, IdP selection) belongs to `identity-access-management`.

## When to use

- Designing or reviewing Conditional Access policies: signal-based conditions (user/group, application, device compliance, location, sign-in risk, user risk), grant controls (MFA, compliant device, authentication strength), and session controls.
- Configuring Privileged Identity Management: eligible vs active assignments, activation workflow, approval and justification requirements, and access reviews for directory roles.
- Investigating or responding to Identity Protection detections: risky users, risky sign-ins, risk-based CA policy design, and remediation flows.
- Planning hybrid identity: Entra Connect vs Cloud Sync selection, authentication method choice (PHS vs PTA vs federation), source anchor management, sync filtering.
- Managing external identities: B2B cross-tenant access settings, guest invitation restrictions, guest access reviews, Entra External ID for consumer scenarios.
- Implementing Entra ID Governance: access reviews for groups and apps, entitlement management (access packages, catalogs, approval policies), and lifecycle workflows for joiner-mover-leaver automation.
- Troubleshooting authentication failures using Sign-in logs, Audit logs, and the What If tool.
- Reviewing tenant-level security posture: break-glass accounts, CA policy coverage gaps, Entra Connect server hardening, licensing tier alignment with feature requirements.

## When not to use

- **App-registration lifecycle** (OAuth flow choice per app type, MSAL SDK integration, service principal creation, API permission grants, managed identity configuration, client credential discipline): use `entra-app-lifecycle`. This skill owns the platform/admin surface; `entra-app-lifecycle` owns the developer-facing integration surface. Where this skill mentions app registrations or managed identities, it does so briefly and routes depth to `entra-app-lifecycle`.
- **IAM architecture, federation protocol design, MFA strategy, or IdP selection**: use `identity-access-management`.
- **Azure resource configuration (RBAC, subscriptions, resource groups)**: use `azure-cloud-ops`; Entra ID provides identity; Azure RBAC provides resource-level access control.
- **Credential and client-secret storage or rotation**: use `secrets-hygiene`. Entra ID app client secrets and certificate credentials are credentials; their custody belongs there.
- **Token expiry reasoning or session-timeout calculations**: use `utc-timestamps` alongside this skill.

## Core model

### Tenant architecture

An Entra ID tenant is an isolated directory instance:
- **Tenant ID**: immutable GUID assigned at creation.
- **Primary domain**: `<tenantname>.onmicrosoft.com`; cannot be changed.
- **Custom domains**: verified DNS domains; used as UPN suffixes.
- **Flat structure**: no Organisational Units. Use Administrative Units (AUs) to scope role assignments to a subset of users, groups, or devices. AUs support dynamic membership rules (P1 licence required).
- **Object types**: users, groups, devices, applications (registrations), service principals (enterprise applications), conditional access policies.

**Licensing tiers**: Conditional Access and dynamic groups require P1; PIM, Identity Protection, access reviews, and entitlement management require P2; lifecycle workflows require Governance licence. Design policy before purchasing; features vary dramatically by tier.

### Conditional Access

Conditional Access is the zero trust policy engine for Entra ID. Every sign-in evaluates all applicable policies:

**Signals (conditions):**
- User or group membership; directory role.
- Application being accessed.
- Device platform and compliance state (Intune-compliant, Entra joined).
- Location (named locations by IP range; country/region).
- Sign-in risk level and user risk level (from Identity Protection).
- Client application type (browser, modern auth client, legacy auth clients).

**Controls (grant and session):**
- Grant: block, require MFA, require compliant device, require Entra joined device, require approved app, require authentication strength (specify which MFA methods qualify).
- Session: sign-in frequency, persistent browser session control, Microsoft Defender for Cloud Apps integration, disable resilience defaults.

Policy evaluation: all applicable policies are evaluated; the most restrictive effective control applies. Policies are independent; a user can match multiple policies simultaneously.

**Deployment discipline:**
1. Deploy every new policy in Report-Only mode.
2. Use the What If tool to simulate policy impact before enabling.
3. Never target "All users" without excluding break-glass accounts.
4. Test for 2-4 weeks in report-only before switching to Enabled.

### Privileged Identity Management

PIM provides JIT (just-in-time) privileged access:

- **Eligible assignment**: the user can activate the role on demand; it is not active until requested.
- **Active assignment**: the user holds the role (permanently or for a time-bound period).
- **Activation**: the user requests the role, provides justification, optionally triggers an approval workflow, and MFA is required on activation.
- **Activation duration**: configurable (maximum 4-8 hours is recommended; default 8 hours).

Key roles to protect with PIM: Global Administrator, Privileged Role Administrator, Conditional Access Administrator, Exchange Administrator, SharePoint Administrator, Security Administrator.

### Identity Protection

Automated risk detection and CA integration:

| Detection | Risk type | Description |
|---|---|---|
| Anonymous IP address | Sign-in | Sign-in from known anonymous proxy |
| Atypical travel | Sign-in | Impossible travel between locations |
| Password spray | Sign-in | Multiple accounts targeted with common passwords |
| Unfamiliar sign-in properties | Sign-in | Unusual properties for this user |
| Leaked credentials | User | Credentials found in breach databases |
| Token anomaly | Sign-in | Unusual token characteristics |

Risk-based CA policies: sign-in risk Medium+ requires MFA; sign-in risk High blocks access; user risk High requires password change plus MFA.

### Hybrid identity

**Synchronisation options:**

| Method | Architecture | Best for |
|---|---|---|
| Entra Connect | On-premises server with ADSync engine | Full-featured: device writeback, Exchange hybrid, custom sync rules |
| Cloud Sync | Lightweight cloud-managed agent | Simple or multi-forest: no on-premises server; active-active agent HA |

**Authentication methods:**

| Method | Password location | On-premises dependency |
|---|---|---|
| Password Hash Sync (PHS) | Cloud (hash of hash) | None after initial sync; recommended default |
| Pass-Through Auth (PTA) | On-premises AD only | PTA agents must be available per authentication |
| Federation (AD FS) | On-premises AD | AD FS farm and WAP must be available |

PHS + Seamless SSO is the recommended approach: cloud resilience (authenticates if on-premises is down), enables Identity Protection risk detections, and reduces operational complexity. Enable PHS as a backup even when using PTA or federation.

### External identities

**B2B (Business-to-Business)**: guest users from external organisations. Home tenant authenticates; your tenant authorises via CA policies. Configure cross-tenant access settings (inbound/outbound) per partner organisation. Run quarterly access reviews for all guest accounts.

**Entra External ID / B2C (Business-to-Consumer)**: customer-facing identity for consumer applications. Separate from workforce identity; uses user flows (sign-up/sign-in, password reset) and custom policies (Identity Experience Framework). For depth on app integration in External ID, use `entra-app-lifecycle`.

### Entra ID Governance

**Access reviews**: periodic reviews of group memberships, app assignments, and directory role assignments. Reviewers: managers, self-review, or designated reviewers. Configure auto-remediation to remove access if not approved.

**Entitlement management**: organise resources into access packages (a bundle of groups, apps, and SharePoint sites). Users request access via a self-service portal; policies govern approval, expiration, and access review requirements.

**Lifecycle workflows**: automate joiner-mover-leaver (JML) processes with trigger-based workflows. Triggers: employee hire date, department change, termination date. Tasks: generate Temporary Access Pass, send onboarding email, add to groups, remove access and disable account. Requires Governance licence.

### Passwordless authentication

Strongest to weakest:
1. FIDO2 security keys (phishing-resistant, cross-platform).
2. Passkeys in Microsoft Authenticator (device-bound, phishing-resistant).
3. Windows Hello for Business (biometric or PIN, device-bound, phishing-resistant).
4. Certificate-based authentication (smart cards, phishing-resistant).
5. Microsoft Authenticator push with number matching (resists MFA fatigue).
6. TOTP authenticator codes (phishable).
7. SMS/Voice (last resort; SIM-swap vulnerable).

Use authentication strength policies in Conditional Access to specify which methods are acceptable for a given policy rather than requiring generic MFA.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Tenant model, object types, AUs, authentication flows (cloud-only, PHS, PTA, Seamless SSO), token types and lifetimes (ID/access/refresh/PRT), Continuous Access Evaluation (CAE), directory synchronisation (Entra Connect ADSync cycle, source anchor, filtering, Cloud Sync comparison), Graph API IAM endpoints and permissions model, licensing tier feature matrix | `references/architecture.md` |
| Best practices | Conditional Access policy framework (baseline and targeted policies), CA design principles, break-glass account configuration and monitoring, PIM role settings, access reviews for PIM, B2B governance and cross-tenant settings, monitoring and alerting (critical sign-in events, key logs, SIEM export), Entra Connect server hardening | `references/best-practices.md` |

## Cross-references

- `entra-app-lifecycle`: app-registration lifecycle (app type to OAuth flow, MSAL, service principal creation, API permission grants, managed identity, federated identity credentials, client credential discipline). This skill routes there for any depth on app registrations and managed identities; duplication is deliberately avoided.
- `identity-access-management`: federation protocol concepts, IdP selection, access-control model design, JML lifecycle planning, zero trust architecture principles.
- `azure-cloud-ops`: Azure RBAC for resource access, subscription governance, and resource configuration; Entra ID provides identity, Azure RBAC provides resource-level permissions.
- `secrets-hygiene`: app client secrets, certificate credentials, Entra Connect sync account passwords, and PTA agent credentials are credentials; never inline in code or commit to version control.
- `utc-timestamps`: token `exp`/`iat`/`nbf`, PRT renewal (every 4 hours), access review deadlines, PIM activation durations, and CA sign-in frequency settings must be reasoned in UTC.
- `sailpoint`: SailPoint IGA alongside Entra ID for enterprise-grade certifications, SOD, and role mining at scale beyond what Entra ID Governance provides.
- `oncall-runbooks`: Entra ID outage, MFA fatigue attack, global admin compromise, mass account lockout, and federation trust break runbooks.

## Red flags

- **No break-glass accounts**: if every account is subject to CA policies, a misconfigured Conditional Access policy can lock out all administrators. Maintain at least two cloud-only break-glass accounts excluded from all CA policies; monitor their sign-ins with a critical-priority alert.
- **CA policy gaps**: a user or application not covered by any CA policy receives unrestricted access. Always maintain a catch-all policy requiring MFA for all users to all applications.
- **New CA policies deployed in Enabled mode**: deploying directly to Enabled without first running in Report-Only mode causes user lockouts. Treat Report-Only as mandatory; simulate with What If before enabling.
- **PIM notifications ignored**: every Global Administrator activation should trigger an alert to Security Operations. Investigate every activation; unrecognised activations indicate account compromise.
- **PHS not enabled as a backup**: organisations running PTA or federation without PHS as a backup cannot authenticate if on-premises infrastructure is unavailable. Enable PHS for resilience even if the primary method differs.
- **Stale B2B guest accounts**: guests accumulate and are rarely reviewed. Orphaned guest accounts are an access risk. Run quarterly access reviews for all guest users and configure access expiration on B2B invitations.
- **Entra Connect server not treated as Tier 0**: the Entra Connect server has privileged sync access to both on-premises AD and Entra ID. A compromise is equivalent to domain compromise. Treat it as a Tier 0 asset: dedicated server, no internet browsing, Credential Guard enabled, limited admin access.

## Bottom line

Conditional Access is the control plane for all access decisions; get it complete (no gaps), tested (report-only first), and monitored (sign-in logs to SIEM). Protect all privileged roles with PIM; make every role eligible, never permanently active. Enable PHS for hybrid resilience. Automate JML with Lifecycle Workflows. For the app-registration and OAuth integration layer, load `entra-app-lifecycle`. Load `references/architecture.md` for token and sync internals; load `references/best-practices.md` for CA policy framework, PIM configuration, and monitoring setup.
