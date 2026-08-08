# Identity lifecycle, governance, MFA, and zero trust

Deep technical reference for the joiner-mover-leaver lifecycle, provisioning patterns, MFA strategy, identity governance and administration (IGA), and zero trust identity. For protocols see `protocols.md`; for access control models and tokens see `access-control-and-tokens.md`.

---

## Multi-factor authentication (MFA)

MFA factors by category, ordered by strength:

| Factor | Category | Phishing resistant? | Examples |
|---|---|---|---|
| Password | Knowledge | No | Static password, PIN |
| TOTP | Possession | No (phishable) | Authenticator app codes |
| Push notification | Possession | Partially (MFA-fatigue risk) | Okta Verify, Microsoft Authenticator push |
| Number-matching push | Possession | Better (resists fatigue) | Okta Verify number challenge, MS Authenticator number match |
| SMS OTP | Possession | No (SIM swap, SS7) | Text-message codes |
| FIDO2 / passkeys | Possession + Inherence | Yes (origin-bound) | YubiKey, platform passkeys |
| Certificate | Possession | Yes (mutual TLS) | Smart card, virtual smart card |
| Biometric | Inherence | Depends on implementation | Windows Hello, Face ID (local biometric) |

MFA strategy priority: FIDO2/passkeys > certificate-based > number-matching push > TOTP > SMS (last resort).

The crucial distinction is phishing resistance. TOTP and push can be relayed through an adversary-in-the-middle proxy; FIDO2 and certificate auth are bound to the origin or rely on a private key the user cannot disclose, which defeats real-time phishing. Move privileged users to phishing-resistant factors first.

---

## Provisioning and the joiner-mover-leaver lifecycle

The joiner-mover-leaver (JML) lifecycle:

| Phase | Actions | Automation |
|---|---|---|
| Joiner | Create identity, assign baseline access, enrol MFA, provision to downstream apps | HR-driven provisioning via SCIM, attribute mapping |
| Mover | Adjust group memberships, recertify access, update attributes | Role-based auto-adjustment, access-review triggers |
| Leaver | Disable account, revoke tokens, deprovision from apps, archive data | Automated deprovisioning, token revocation, licence reclaim |

Provisioning patterns:
- **SCIM push**: the IdP pushes changes to SPs via REST API. The standard approach.
- **JIT provisioning**: the account is created on first SAML/OIDC login. Simple, but there is no pre-provisioning for offline access.
- **HR-driven**: the HR system (Workday, BambooHR, SAP SuccessFactors) is the source of truth. Changes flow HR -> IdP -> apps.
- **Directory sync**: Entra Connect or LDAP sync, for hybrid environments bridging on-prem to cloud.

The mover phase is the most neglected and the most dangerous. Without recertification on role change, users accumulate access from every position they have held: privilege creep that no single grant looks wrong but that, summed, breaks least privilege.

---

## Identity governance and administration (IGA)

| Capability | Description | Representative vendors |
|---|---|---|
| Access certifications | Periodic review of who has access to what | SailPoint, Saviynt, Okta, Entra ID Governance |
| Entitlement management | Self-service access request with approval workflows | Entra ID, SailPoint, Okta |
| Separation of duties (SOD) | Prevent toxic combinations of access | SailPoint, Saviynt, Oracle |
| Role mining | Discover roles from existing access patterns | SailPoint, Saviynt |
| Lifecycle workflows | Automate JML processes | Entra ID Lifecycle Workflows, SailPoint, Okta |
| Privileged Access Management (PAM) | Control and audit privileged access | CyberArk, Entra PIM, BeyondTrust, Delinea |

Governance is the feedback loop that keeps the access model honest over time. Provisioning grants access; governance proves, periodically, that the access still maps to need, and removes what does not. Without it, the model is correct only at the moment of grant and drifts from then on.

For the deep SailPoint implementation (certification campaigns, SOD policy, role mining) route to the `sailpoint` vendor skill; for Entra ID Governance and PIM route to `entra-id`.

---

## Zero trust identity

Identity is the control plane in zero trust architecture. The principles:

1. **Continuous verification**: every access request is authenticated and authorized, regardless of network location.
2. **Device trust**: device health (patched, compliant, managed) is a signal in the access decision.
3. **Least privilege**: grant the minimum, and use JIT elevation for privileged operations.
4. **Assume breach**: segment access so a compromised identity has minimal blast radius.
5. **Continuous evaluation**: re-evaluate access during a session, not only at login, via the Continuous Access Evaluation Protocol (CAEP).

Signals that feed an access decision:
- User identity (who).
- Device health (what).
- Location (where).
- Application sensitivity (to what).
- Risk score (how risky).
- Time and behaviour (when and how).

A zero trust identity design combines these: the same user, on a managed and compliant device, from a known location, gets a frictionless session; the same user on an unmanaged device from an anomalous location gets step-up MFA or denial. The policy engine (Conditional Access in Entra ID, adaptive policies in Okta) is where these signals become decisions.
