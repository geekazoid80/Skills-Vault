---
name: ping-identity
description: "Use for Ping Identity platform implementation, configuration, and troubleshooting. Covers PingOne cloud platform (SSO, MFA, Directory, Authorize, Credentials), PingFederate on-premises federation server (SAML 2.0, OIDC, OAuth 2.0, WS-Federation, WS-Trust, SP/IdP connections, adapter model, clustering), PingAccess API and application gateway (reverse proxy, token mediation, policy enforcement), PingDirectory high-performance LDAP (replication, SCIM, consent management), DaVinci no-code orchestration (flow builder, 200+ connectors, progressive profiling, step-up auth), PingOne Protect risk assessment (device intelligence, behavioural analytics, IP intelligence, bot detection), and PingOne Neo decentralised identity (verifiable credentials, digital wallets, W3C VCs, DIDs). References: architecture.md. Triggers include \"Ping Identity\", \"PingFederate\", \"PingOne\", \"PingAccess\", \"PingDirectory\", \"DaVinci\", \"PingOne Protect\", \"PingOne Neo\", \"Ping SSO\", \"Ping federation\", \"PingOne MFA\", \"PingOne Authorize\", \"DaVinci flow\", \"PingFederate adapter\", \"PingFederate SP connection\", \"PingFederate IdP connection\", \"PingAccess token mediation\", \"PingDirectory LDAP\", \"PingOne Credentials\", \"verifiable credentials Ping\", \"Ping WS-Federation\", \"Ping RADIUS\", \"PingFederate cluster\". For IAM architecture, federation protocol design, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Ping Identity

> **Skill marker**: When applying this skill, begin your reply with `[skill: ping-identity]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Ping Identity platform implementation across its full product suite: PingOne cloud identity, PingFederate federation server, PingAccess API gateway, PingDirectory LDAP, DaVinci orchestration, PingOne Protect risk assessment, and PingOne Neo decentralised identity. The conceptual layer (federation protocol choice, IdP selection, access-control models, zero trust) lives in `identity-access-management`.

## When to use

- Configuring PingOne cloud platform: environments, populations, applications (SAML/OIDC), sign-on and MFA policies, PingOne APIs.
- Setting up PingFederate: SP connections, IdP connections, OAuth clients, authentication policies, adapter chains, token exchange, clustering.
- Configuring PingAccess: reverse-proxy policies, OAuth token validation, identity-header injection, web session management.
- Deploying PingDirectory: LDAP configuration, replication, SCIM endpoints, consent management, JVM sizing.
- Building DaVinci flows: no-code identity orchestration, progressive profiling, step-up authentication, B2B onboarding.
- Configuring PingOne Protect: device intelligence, behavioural analytics, risk-score-based authentication policies.
- Implementing PingOne Neo: verifiable credential issuance, digital wallet integration, W3C VC and DID workflows.
- Troubleshooting hybrid deployments: PingOne cloud + PingFederate + PingAccess + PingDirectory combinations.

## When not to use

- **IAM architecture, federation protocol design, or IdP selection**: use `identity-access-management`.
- **Credential and secret storage** (PingFederate keystore passwords, PingDirectory bind credentials, PingOne client secrets): use `secrets-hygiene`.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Deployment models

Ping Identity supports three deployment models:

| Model | Components | When to use |
|---|---|---|
| PingOne Cloud | PingOne SSO, MFA, Directory, Protect, Neo | Cloud-first; no on-premises footprint |
| Self-managed | PingFederate, PingAccess, PingDirectory | On-premises or customer-managed cloud; full control |
| Hybrid | PingOne cloud + self-managed components connected | Large enterprise with existing on-prem federation investment |

Define clearly which component handles authentication, authorisation, and session management before integrating components; unclear boundaries are the most common source of complexity in hybrid Ping deployments.

### PingOne platform

PingOne is the cloud-native identity platform structured around Environments:

```
PingOne Organisation
  |-- Environment: Production  (PRODUCTION type)
  |     |-- Populations (user groups)
  |     |-- Applications (SAML, OIDC clients)
  |     |-- Policies (sign-on, MFA, password)
  |-- Environment: Staging  (SANDBOX type)
  |-- Environment: Development  (SANDBOX type)
```

Core services: PingOne SSO (SAML/OIDC), PingOne MFA (push, TOTP, FIDO2, email, SMS), PingOne Directory (cloud directory replacing on-premises LDAP in cloud-first scenarios), PingOne Authorize (dynamic, policy-based authorisation), PingOne Credentials (verifiable credential issuance).

### PingFederate

Enterprise-grade federation server for on-premises and hybrid deployments. Supports SAML 2.0, OIDC, OAuth 2.0, WS-Federation, and WS-Trust. Cluster-capable for high availability (active-active).

**Connection types:**
- **SP Connection**: PingFederate acts as the IdP; issues tokens to a Service Provider.
- **IdP Connection**: PingFederate acts as the SP; receives tokens from an external IdP (e.g., partner federation).
- **OAuth Client**: application registered for OAuth 2.0/OIDC flows.
- **Token Exchange**: exchange one token type for another (RFC 8693).

**Adapter model**: authentication policy chains multiple adapters with decision logic.
- **IdP Adapters**: authenticate users (HTML Form, Kerberos, Certificate, RADIUS, custom).
- **SP Adapters**: deliver identity to the application (OpenToken, OIDC, custom).
- **Authentication Policy**: if Kerberos fails, fall back to form login; if form login succeeds, require MFA.

Certificate management is the most common operational pain point in PingFederate: SSL server certs, signing certs, and partner certs live in separate keystores. Track all expiration dates.

### PingAccess

Identity-aware reverse proxy and API gateway:

```
Client -> PingAccess (reverse proxy)
  |-- Validates OAuth access token (from PingFederate or PingOne)
  |-- Evaluates access policy (user role, request path, HTTP method)
  |-- Injects identity headers (X-User-ID, X-Roles) into forwarded request
  |-- Forwards request to backend application
```

Two deployment models: reverse proxy (PingAccess in the network path) or agent-based (Apache/IIS modules). PingAccess manages web sessions separately from OAuth tokens; understand which model the application expects before configuring.

### PingDirectory

High-performance LDAP directory. Suitable for high-volume, application-facing directory needs where AD DS is not appropriate (SCIM-native, consent management, no Windows dependency).

Key capabilities: millions of entries, thousands of operations per second, multi-master replication across data centres, built-in GDPR consent tracking per attribute, native SCIM 2.0 endpoint, field-level encryption, access logging, data masking.

JVM heap must accommodate the entry cache. Under-provisioned heap causes severe performance degradation; size appropriately before go-live.

### DaVinci

No-code identity orchestration: a visual flow builder where authentication journeys are composed from drag-and-drop connectors (200+).

Common flow patterns:
- **Progressive profiling**: collect user information across multiple sessions without blocking first login.
- **Step-up authentication**: prompt MFA only when the user accesses a sensitive resource.
- **Self-service registration**: sign-up with email verification, identity proofing, and MFA enrolment.
- **Account recovery**: knowledge-based, email, or phone-based recovery with risk checks.
- **B2B onboarding**: organisation creation, admin invitation, and IdP configuration wizard.

DaVinci vs. PingFederate authentication policies: DaVinci is visual, no-code, cloud-only, faster iteration; PingFederate is config-file-based, more complex, and supports on-premises.

### PingOne Protect

Risk assessment and fraud prevention:

**Risk signals collected:**
- Device intelligence: fingerprinting, device reputation, jailbreak/root detection.
- Behavioural analytics: typing patterns, mouse movement, navigation patterns.
- IP intelligence: IP reputation, geolocation, VPN/proxy detection, impossible travel.
- Bot detection: automated request patterns.

**Integration pattern:**
1. Client-side SDK collects signals during user interaction.
2. Signals sent to PingOne Protect API for evaluation.
3. Risk score returned: LOW, MEDIUM, or HIGH.
4. DaVinci flow or PingOne sign-on policy adjusts authentication requirements accordingly.

Risk-based policies: low risk allows passwordless or skips MFA; medium risk requires MFA; high risk blocks access or requires identity verification.

### PingOne Neo

Decentralised identity using W3C Verifiable Credentials (VCs) and Decentralised Identifiers (DIDs):
- **Digital wallet**: mobile app for storing VCs (employee badge, certification, access pass).
- **Credential issuance**: issue W3C VCs to users via PingOne Credentials.
- **Credential verification**: verify credentials presented by users during authentication.
- **Standards**: W3C Verifiable Credentials Data Model, DID Core.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | PingOne environment model and APIs, PingFederate architecture diagram and connection types, adapter model and authentication policy chaining, PingAccess deployment patterns, PingDirectory sizing and replication, DaVinci connector library and flow examples, PingOne Protect integration pattern, PingOne Neo standards and use cases | `references/architecture.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts (SAML, OIDC, WS-Federation, WS-Trust), IdP selection rationale, access-control model design, hybrid identity architecture.
- `sailpoint`: SailPoint IGA is frequently deployed alongside Ping Identity; SailPoint owns certifications, SOD, role mining, and the JML lifecycle while PingFederate or PingOne owns authentication.
- `secrets-hygiene`: PingFederate keystore passwords, PingDirectory bind credentials, PingOne client secrets, and DaVinci connector credentials are credentials; handle per `secrets-hygiene` discipline.
- `utc-timestamps`: PingFederate certificate expiration tracking, token `exp`/`iat`, session lifetimes, and PingOne Protect impossible-travel windows must be reasoned in UTC.
- `oncall-runbooks`: PingFederate certificate expiry, PingOne outage, DaVinci flow failure, and PingDirectory replication-lag runbooks.

## Red flags

- **PingFederate certificate expiry not tracked across all keystores**: PingFederate uses multiple keystores (SSL server cert, signing certs, partner certs). Certificate expiry in any keystore can cause authentication outages. Track all expiration dates and set alerts at 90, 30, and 7 days.
- **PingFederate connection configuration drift at scale**: PingFederate deployments with hundreds of SP/IdP connections are hard to manage manually. Use the Admin API and configuration management tools (version control, automated deployment) to prevent drift.
- **PingAccess session vs. token model not clarified**: PingAccess can use both session cookies and OAuth tokens; applications may expect one model or the other. Clarify the expected session model before configuring PingAccess for a new application.
- **DaVinci flow complexity without incremental testing**: complex DaVinci flows with many branching paths are difficult to debug after the fact. Build and test incrementally; use the built-in flow debugger at each step.
- **PingDirectory JVM heap under-provisioned**: under-provisioned heap causes severe performance degradation under load. Benchmark with production-representative data volumes before go-live.
- **Mixed cloud and self-managed without clear boundaries**: when PingOne cloud and PingFederate self-managed components are both present, undefined boundaries (who handles the session? who issues the final token?) cause duplicate authentication prompts and hard-to-trace failures.

## Bottom line

Classify the deployment model (PingOne cloud, self-managed, or hybrid) before starting any configuration. For federation at scale, PingFederate is the centre of gravity; keep connections under version control and automate via the Admin API. For complex authentication journeys, prefer DaVinci over PingFederate policy chaining. Load `references/architecture.md` for detailed component configuration. Track PingFederate certificate expiry across all keystores; it is the top cause of unplanned Ping identity outages.
