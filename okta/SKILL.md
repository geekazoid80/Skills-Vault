---
name: okta
description: "Use for Okta identity platform implementation, configuration, and troubleshooting. Covers Universal Directory, profile mastering and Okta Expression Language, authentication policies and adaptive MFA, Lifecycle Management via SCIM and HR-driven provisioning, Workflows no-code automation, API Access Management (OAuth 2.0 authorisation servers), OIN integrations (SAML 2.0, OIDC), ThreatInsight, Identity Threat Protection with CAEP, Identity Governance (OIG) certifications and SOD, System Log, rate limits, agent architecture (AD Agent, LDAP Agent, RADIUS Agent, IWA Agent), and inline hooks and event hooks. References: architecture.md, operations.md. Triggers include \"Okta\", \"Universal Directory\", \"OIN\", \"Okta Workflows\", \"Okta MFA\", \"Okta FastPass\", \"Okta SSO\", \"ThreatInsight\", \"Okta Lifecycle\", \"Okta SCIM\", \"Okta API Access Management\", \"Okta Expression Language\", \"OEL\", \"profile mastering\", \"Okta authentication policy\", \"Okta sign-on policy\", \"Okta inline hook\", \"Okta event hook\", \"Okta rate limit\", \"Okta AD Agent\", \"Okta groups\", \"Okta Verify\", \"number challenge\", \"CAEP\", \"Identity Threat Protection\", \"OIG\", \"Okta Identity Governance\". For IAM architecture, federation protocol choice, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Okta

> **Skill marker**: When applying this skill, begin your reply with `[skill: okta]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Okta-specific implementation: configuring Universal Directory, authentication policies, adaptive MFA, Lifecycle Management, Workflows, API Access Management, OIN integrations, ThreatInsight, Identity Governance, and the System Log. The conceptual layer (federation protocol choice, IdP selection, access-control models, zero trust) lives in `identity-access-management`.

## When to use

- Configuring Universal Directory: user profile attributes, profile mastering, profile mappings, group rules with OEL expressions.
- Setting up authentication policies (global session policy and per-app policies), adaptive MFA, or phishing-resistant authenticators (Okta FastPass, FIDO2/WebAuthn).
- Implementing Lifecycle Management: SCIM provisioning, HR-driven flows (Workday, BambooHR, SAP SuccessFactors), deprovisioning automation.
- Building Workflows: onboarding/offboarding automation, access-request flows, threat-response automation.
- Configuring API Access Management: custom authorisation servers, scopes, claims, token policies, inline hooks.
- Integrating applications via OIN: SAML 2.0, OIDC, SCIM provisioning to OIN apps.
- Deploying agents: AD Agent, LDAP Agent, RADIUS Agent, IWA Agent for hybrid connectivity.
- Monitoring and alerting: System Log API queries, SIEM export, rate-limit management.
- Reviewing Identity Governance (OIG): access certifications, entitlement management, SOD policies.

## When not to use

- **IAM architecture, federation protocol design, IdP selection, or access-control model choice**: use `identity-access-management`.
- **Auth0 (CIAM, Universal Login, Organizations, Actions)**: Auth0 and Okta are sibling products under the same company with distinct platforms; use `auth0` for customer-facing identity work.
- **Credential, client-secret, and API-token storage or rotation**: use `secrets-hygiene`. Okta API tokens and OAuth client secrets are credentials; their custody belongs there.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Universal Directory

Universal Directory is Okta's cloud directory: the hub for all identities in an Okta org.

Key concepts:
- **Profile master**: defines which source controls each attribute (Okta, AD, LDAP, HR system). When multiple sources provide the same attribute, the profile master priority determines which source wins.
- **Custom attributes**: extend the base Okta user profile (string, number, boolean, array of strings, integer). Usable in group rules, profile mappings, and Workflows.
- **Profile mappings**: map attributes between the Okta profile and per-app profiles for provisioning.
- **Group types**: Okta groups (manually managed), dynamic groups (OEL expression rules), AD groups (synced), LDAP groups (synced), App groups (pushed from application).

Okta Expression Language (OEL) powers dynamic group rules and attribute mappings. See `references/architecture.md` for the OEL reference.

### Authentication policies

Two layers govern how users authenticate:

1. **Global Session Policy**: evaluated first; controls session-level MFA requirements and session lifetime.
2. **Per-app Authentication Policies**: control access to specific applications; can require specific authenticators, device trust, or network zones. Rules are evaluated top-to-bottom; first match wins.

Policy evaluation order: Global Session Policy -> App Authentication Policy -> Authenticator enrolment policy -> access granted or denied.

### Adaptive MFA

Okta evaluates risk signals to determine whether MFA is required and which authenticators to prompt.

| Authenticator | Phishing resistant | Notes |
|---|---|---|
| Okta FastPass | Yes (device-bound) | Passwordless; preferred |
| FIDO2/WebAuthn | Yes | Hardware keys, platform authenticators |
| Okta Verify (push) | No (fatigue risk) | Enable number challenge to reduce fatigue |
| Okta Verify (TOTP) | No | Standard TOTP |
| SMS/Voice | No | SIM-swap vulnerable; last resort only |

Risk signals evaluated: device context (managed/unmanaged), network zone (trusted/untrusted), location (impossible travel), behaviour patterns, and ThreatInsight IP reputation.

### Lifecycle Management

Automated provisioning and deprovisioning:
- **SCIM 2.0**: standard REST provisioning to SCIM-capable applications.
- **SAML JIT**: Just-in-Time provisioning on first SAML login (limited attributes).
- **HR-driven**: Workday, BambooHR, SAP SuccessFactors as the authoritative identity source.
- Provisioning actions: create users, update profiles, deactivate users, push groups, sync passwords.

Applications not connected to Lifecycle Management require manual deprovisioning; audit for coverage regularly.

### Workflows

No-code identity automation platform built from flows, connectors, tables, and functions. Common patterns: onboarding automation, offboarding automation (revoke sessions, transfer ownership, archive mailbox), access-request flows with manager approval via Slack, scheduled compliance reports, threat-response automation.

### API Access Management

Okta as an OAuth 2.0 authorisation server for API security:
- Custom authorisation servers define scopes, claims, and access policies per API.
- Access tokens are JWTs; custom claims can be added via token inline hooks.
- Access policies restrict which clients can request which scopes.

### ThreatInsight and Identity Threat Protection

**ThreatInsight**: IP-based threat intelligence evaluated at the org level before authentication policy. Actions: none, audit (log only), or block. Exempt trusted proxy IPs (CDN, WAF) from evaluation.

**Identity Threat Protection with Okta AI**: continuous risk evaluation throughout active sessions (not just at login). Integrates CAEP (Continuous Access Evaluation Protocol); can trigger step-up authentication, session termination, or alerts mid-session.

### Identity Governance (OIG)

- **Access certifications**: periodic reviews of user access to applications and resources.
- **Entitlement management**: self-service access request, approval, and audit.
- **SOD policies**: define and enforce separation of duties rules.
- **Governance reports**: visibility into who has access to what.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Platform internals | Cell/org architecture, agent types (AD, LDAP, RADIUS, IWA), Universal Directory data model, profile mastering, group types, OIN integration patterns (SAML/OIDC/SCIM), event hooks, inline hook types, rate limits, OEL reference, network zones, session security, data residency | `references/architecture.md` |
| Operations | Authentication policy design, MFA authenticator selection, Lifecycle Management patterns, Workflow patterns, API Access Management setup, System Log queries and critical events, rate-limit management, ThreatInsight and Identity Threat Protection configuration, OIG campaigns | `references/operations.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts, IdP selection rationale, JML lifecycle design, access-control models, governance programme design.
- `auth0`: Auth0 is Okta's sibling CIAM product (same company, distinct platform); use `auth0` for customer-facing identity. Okta and Auth0 are not interchangeable; workforce vs. customer-facing is the primary split.
- `sailpoint`: SailPoint IGA works alongside Okta as the IdP; SailPoint owns certifications, SOD, and role mining while Okta owns authentication and provisioning.
- `secrets-hygiene`: Okta API tokens, OAuth client secrets, SCIM bearer tokens, and Workflow connector credentials are credentials; never inline them in code or commit to version control.
- `utc-timestamps`: token `exp`/`iat`, session idle and absolute lifetimes, ThreatInsight exemption windows, and access-certification deadlines must be reasoned in UTC.
- `oncall-runbooks`: Okta outage, MFA fatigue attack, admin account compromise, and mass-deprovisioning runbooks.

## Red flags

- **Default authentication policy left at password-only**: the default catch-all rule frequently allows password-only access. Configure MFA requirements for every application; do not rely on the default rule.
- **Okta Verify push without number challenge**: simple push notifications are vulnerable to MFA fatigue attacks. Enable number matching in the authenticator settings.
- **Over-scoped Okta API tokens**: API tokens inherit the permissions of the creating admin. Replace long-lived API tokens with scoped OAuth 2.0 service-app tokens wherever possible.
- **Profile mapping conflicts with multiple masters**: when multiple sources map to the same attribute, unexpected values appear at login. Define profile mastering explicitly; do not leave mastering ambiguous.
- **System Log not exported to a SIEM**: Okta System Log is the primary security telemetry source. Without SIEM integration, critical events (API token creation, admin privilege escalation, zone changes) go undetected.
- **Deprovisioning gaps for non-SCIM apps**: applications without a Lifecycle Management connection require manual deprovisioning. Audit coverage; orphaned accounts are a top attack vector.
- **Inline hooks with slow external calls**: inline hooks have a 3-second timeout. Heavy processing in a hook causes authentication failures for users. Respond quickly or use event hooks (async) for non-blocking work.

## Bottom line

Configure Universal Directory with explicit profile mastering before connecting any application. Enforce phishing-resistant MFA (Okta FastPass + FIDO2) with number challenge on Okta Verify as a fallback. Automate deprovisioning via Lifecycle Management for every connected application. Export System Log to a SIEM and alert on high-value events. Load `references/architecture.md` for platform internals and `references/operations.md` for configuration patterns and operational guidance.
