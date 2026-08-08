# Okta operations

## Authentication policy design

### Policy evaluation flow

```
User requests access to app
  -> Global Session Policy (session-level MFA, session lifetime)
  -> App-level Authentication Policy (app-specific requirements)
  -> Authenticator enrolment policy (which factors the user may use)
  -> Access granted or denied
```

**Global Session Policy** is evaluated first and determines whether a session-level MFA challenge is required and the session lifetime. **Per-app Authentication Policies** are evaluated next and enforce application-specific requirements such as device trust, specific authenticators, or network zone membership. Rules in each policy are evaluated top-to-bottom; the first matching rule applies.

### Policy rule checklist

- Replace the default catch-all rule (which often allows password-only access) with an explicit MFA requirement.
- Define a network zone for trusted corporate IPs; use zone-aware rules to require MFA outside trusted zones.
- Separate Assurance Levels: phishing-resistant authenticators (Okta FastPass, FIDO2) for high-sensitivity apps; Okta Verify with number challenge as a fallback.
- Set explicit session lifetimes; do not rely on defaults. Reason all expiry windows in UTC per `utc-timestamps`.

---

## MFA authenticator strategy

| Authenticator | Type | Phishing resistant | Recommendation |
|---|---|---|---|
| Okta FastPass | Possession + Device | Yes | Preferred; passwordless |
| FIDO2/WebAuthn | Possession + Inherence | Yes | Hardware keys and platform authenticators |
| Okta Verify (push + number challenge) | Possession | No (with number challenge: reduced risk) | Fallback for FastPass |
| Okta Verify (TOTP) | Possession | No | Offline fallback |
| Google Authenticator | Possession | No | Standard TOTP; phishing-risk |
| SMS/Voice | Possession | No | Last resort; SIM-swap vulnerable |
| Security Question | Knowledge | No | Weak; being deprecated; avoid |
| Email | Possession | No | Account-compromise risk; avoid as sole factor |

**Recommended baseline**: deploy Okta FastPass for managed devices; FIDO2/WebAuthn for unmanaged or high-assurance scenarios; Okta Verify with number challenge as fallback. Disable SMS/Voice unless no alternative exists. Disable Security Question entirely.

---

## Lifecycle Management patterns

### HR-driven provisioning flow

```
HR System (Workday, BambooHR, SAP SuccessFactors)
  -> Okta Universal Directory (create / update / deactivate user)
  -> Downstream apps via SCIM (provision / deprovision)
  -> AD/LDAP via Okta AD Agent (if hybrid)
```

**Joiner**: HR system creates the employee record; Okta aggregates the identity and provisions downstream apps automatically based on group membership and app assignments.

**Mover**: HR system updates department, title, or location; Okta detects the attribute change, re-evaluates group membership via dynamic rules, and adjusts app access accordingly.

**Leaver**: HR system sets the termination date or deactivates the record; Okta deactivates the Okta account and deprovisions connected apps. Target disablement within one hour of termination.

### SCIM provisioning checklist

1. Enable provisioning on the app integration (Okta Admin Console: Applications -> app -> Provisioning tab).
2. Configure the provisioning endpoint URL and bearer token (store the token via `secrets-hygiene`).
3. Map Okta user profile attributes to SCIM attributes in the attribute mappings section.
4. Configure provisioning actions: Create Users, Update User Attributes, Deactivate Users, Sync Password (where supported).
5. Enable Push Groups if the application needs group membership information.
6. Test with a single test user before enabling for all users.

---

## Workflows patterns

**Onboarding automation:**
- Trigger: user lifecycle create event.
- Actions: assign groups, send welcome email (connector: SendGrid/SMTP), create Jira onboarding ticket, provision Slack account, send manager notification.

**Offboarding automation:**
- Trigger: user lifecycle deactivate event.
- Actions: revoke all active sessions, remove from all Okta groups, transfer Google Drive file ownership, archive mailbox, create ServiceNow offboarding ticket.

**Access request:**
- Trigger: Slack slash command or form submission.
- Flow: user requests access -> manager receives Slack DM for approval -> on approval, Workflow assigns the user to the appropriate Okta group.

**Scheduled compliance report:**
- Trigger: scheduled (weekly).
- Actions: query all users without MFA enrolled (Okta API), format report, email to security team.

**Threat response:**
- Trigger: user.risk.change event (Identity Threat Protection signal).
- Actions: suspend user, notify SOC via PagerDuty, create incident ticket in ServiceNow.

---

## API Access Management

### Custom authorisation server setup

1. Create a custom authorisation server in the Okta Admin Console: Security -> API -> Authorisation Servers.
2. Define scopes (e.g., `read:reports`, `write:config`).
3. Define custom claims (static, expression, or token inline hook).
4. Create access policies: which clients can request which scopes.
5. Set token lifetimes (access token, refresh token).
6. Enable token introspection and revocation endpoints.

**Example access token payload:**

```json
{
  "iss": "https://company.okta.com/oauth2/default",
  "sub": "user@example.com",
  "aud": "api://my-api",
  "iat": 1712345678,
  "exp": 1712349278,
  "scp": ["read:data", "write:data"],
  "groups": ["Engineering", "API-Users"],
  "custom_claim": "custom_value"
}
```

Use `utc-timestamps` when reasoning about `iat` and `exp` values.

### API token vs. OAuth 2.0 service app

| Credential type | Scope | Lifecycle | Recommendation |
|---|---|---|---|
| Okta API token | Inherits creating admin's permissions | Never expires until revoked | Avoid for new integrations |
| OAuth 2.0 service app (client credentials) | Scoped to specific API endpoints | Token expiry; rotate client secret | Preferred for all new automations |

---

## System Log monitoring

### Critical events

| Event type | Meaning | Alert priority |
|---|---|---|
| `system.api_token.create` | API token created | High |
| `zone.update` | Network zone modified | High |
| `user.account.lock` | Account locked out | Medium |
| `user.lifecycle.deactivate` | User deactivated | Medium |
| `user.session.start` | User sign-in | Low (baseline) |
| `user.authentication.auth_via_mfa` | MFA challenge completed | Low (baseline) |
| `policy.evaluate_sign_on` | Authentication policy evaluated | Low (baseline) |
| `application.user_membership.add` | User assigned to app | Medium |
| `user.lifecycle.create` | User created | Medium |

### System Log API queries

```bash
# Query sign-in events since a specific time
GET /api/v1/logs?filter=eventType eq "user.session.start"&since=2024-01-01T00:00:00Z

# Query for a specific user
GET /api/v1/logs?filter=actor.id eq "user-id"&since=2024-01-01T00:00:00Z

# Query account lockouts
GET /api/v1/logs?filter=eventType eq "user.account.lock"
```

Derive time values from the live clock; see `utc-timestamps`. Always set a `since` parameter to avoid full-table scans that consume System Log rate-limit quota (120 requests/minute).

### Log streaming

Stream System Log to a SIEM via:
- Native log streaming integrations: Splunk, Sumo Logic, Elastic, Azure Event Hub, AWS EventBridge.
- Webhook log streaming for custom endpoints.
- Event Hooks on specific event types for targeted alerting.

---

## ThreatInsight and Identity Threat Protection

### ThreatInsight

Evaluates sign-in attempts against Okta's threat intelligence database before authentication policy evaluation:
- Actions: none (log only, default), audit (log), block (deny and log).
- Exempt trusted proxy IPs (CDN, WAF egress) from ThreatInsight evaluation to avoid false positives.
- Protects against credential stuffing, brute force, and distributed attacks.

### Identity Threat Protection with Okta AI

Continuous risk evaluation throughout active sessions via CAEP:
- Evaluates risk signals after login (device posture change, impossible travel, anomalous activity).
- Integrates with third-party security signals (EDR, SIEM via Shared Signals Framework).
- Response actions: step-up MFA challenge, session termination, user suspension, SOC alert.
- Requires Identity Threat Protection SKU.

---

## Identity Governance (OIG) campaigns

### Campaign types

| Type | Reviewer | Frequency | Use case |
|---|---|---|---|
| Manager | People manager | Quarterly | Standard access review for all direct reports |
| Entitlement Owner | Named entitlement owner | As needed | Sensitive entitlement review |
| Source/App Owner | Application owner | Quarterly or on-demand | App-specific certification |
| Search-based | Configurable | As needed | Targeted review (e.g., SOD violations) |

### Campaign configuration checklist

1. Define campaign scope (all apps, specific apps, privileged entitlements only).
2. Set duration (2 to 4 weeks) and send automated reminders.
3. Enable auto-revocation: remove access for items not actioned by the deadline.
4. Enable reassignment: allow reviewers to delegate to a more knowledgeable reviewer.
5. Exclude recently certified access to reduce reviewer fatigue.
6. Confirm remediation completion: verify deprovisioning occurred after revocations.
