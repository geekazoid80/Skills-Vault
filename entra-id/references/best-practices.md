# Entra ID best practices and hardening

## Conditional Access policy framework

### Baseline policies (apply to all users)

| Policy | Conditions | Controls | Purpose |
|---|---|---|---|
| Block legacy authentication | All users, all apps; client apps = Exchange ActiveSync + Other clients | Block | Eliminate protocols that cannot do MFA |
| Require MFA for all users | All users (exclude break-glass), all apps | Grant: MFA | Foundation security policy |
| Block high-risk sign-ins | All users, sign-in risk = High | Block | Automated threat response |
| Require password change for high-risk users | All users, user risk = High | Grant: password change + MFA | Automated compromise response |
| Require compliant device for Microsoft 365 | All users, Microsoft 365 apps | Grant: compliant device OR MFA | Device trust for productivity apps |

### Targeted policies (specific scenarios)

| Policy | Conditions | Controls | Purpose |
|---|---|---|---|
| Require phishing-resistant MFA for admins | Directory roles (Global Admin, etc.), all apps | Grant: authentication strength (phishing-resistant) | Protect privileged access |
| Block access from untrusted countries | All users; locations = all except named trusted locations | Block | Reduce attack surface |
| Require compliant device for sensitive apps | All users, specific sensitive apps | Grant: compliant device (required only, not OR) | Strict device trust for sensitive data |
| Session controls for unmanaged devices | All users, device state: not compliant | Session: sign-in frequency = 1 hour, no persistent browser | Limit session lifetime on personal devices |
| Require terms of use for guests | Guest users, all apps | Grant: terms of use | Legal compliance for B2B access |

### CA policy design principles

1. **Name descriptively**: `CA001-BaseProtection-AllUsers-AllApps-RequireMFA` conveys scope and control at a glance.
2. **Report-Only first**: test in Report-Only mode for 2-4 weeks; use the What If tool to simulate impact before enabling.
3. **Check What If before every change**: simulate the policy against representative users before enabling.
4. **Never target all users without exclusions**: always exclude break-glass accounts. Every policy targeting "All users" or "All apps" must have explicit break-glass exclusions.
5. **Prefer Require over Block**: requiring MFA gives compliant users a path; blocking does not. Use Block only for clearly prohibited access patterns (legacy auth, high-risk sign-ins, blocked countries).
6. **Use authentication strength**: specify which MFA methods qualify (phishing-resistant, passwordless, or custom strength) rather than generic MFA requirement.
7. **Document exclusions**: every exclusion is a potential security gap. Record the business justification and set a review date.

---

## Emergency access (break-glass) accounts

### Configuration requirements

- **At least 2 accounts**: survive if one is compromised or accidentally locked out.
- **Cloud-only**: not synced from on-premises AD; survive an AD outage or Entra Connect failure.
- **Excluded from all Conditional Access policies**: including MFA requirements, device compliance, and location restrictions.
- **Strong, unique passwords**: 24+ characters; stored in a physical safe, not a digital password manager or shared vault.
- **Permanent Global Administrator role**: not eligible via PIM; these accounts must be usable when PIM itself is unavailable.
- **No phone number or SSPR methods registered**: prevents social-engineering attacks on the account.
- **FIDO2 hardware security key for MFA**: store the key in the same physical safe as the password.
- **Use `@tenant.onmicrosoft.com` UPN**: not a custom domain; resilient to DNS failures and domain expiry.

### Break-glass monitoring

```kusto
// Alert on ANY sign-in by break-glass accounts
// KQL for Azure Monitor / Microsoft Sentinel
SignInLogs
| where UserPrincipalName in (
    "breakglass1@tenant.onmicrosoft.com",
    "breakglass2@tenant.onmicrosoft.com"
  )
| project TimeGenerated, UserPrincipalName, IPAddress, Location, ResultType, AppDisplayName
```

Every break-glass sign-in triggers a Critical-priority alert to Security Operations. Break-glass accounts should never be used during normal operations; any sign-in is an anomaly requiring immediate investigation.

---

## PIM configuration

### Role settings (recommended values)

| Setting | Recommended value | Rationale |
|---|---|---|
| Maximum activation duration | 4 hours (8 for complex tasks) | Minimise window of elevated access |
| Require MFA on activation | Yes | Verify identity before granting privileges |
| Require justification | Yes | Audit trail for every activation |
| Require approval (Global Admin, Privileged Role Admin) | Yes | Human verification for highest-impact roles |
| Require ticket number | Yes | Link to change management record |
| Eligible assignment duration | 6 months (with access review) | Prevent stale eligible assignments |
| Active assignment duration | Never permanent (except break-glass) | All active assignments should be time-bound |
| Notification on activation | Security Operations team | Alert SOC to every privileged role activation |

### Access reviews for PIM

- Review eligible assignments every quarter.
- Reviewer: manager plus security team representative.
- Auto-apply results: remove the eligible assignment if not approved.
- Send reminders 3 days before the review period ends.
- Scope reviews to the highest-impact roles first: Global Administrator, Privileged Role Administrator, Security Administrator.

---

## B2B governance

### Cross-tenant access settings

Configure per-organisation inbound and outbound policies in Entra External Identities:
- **Inbound trust settings**: whether to trust MFA claims and device compliance state from the external tenant. Trusting a verified partner's MFA avoids redundant MFA challenges.
- **Inbound access policy**: which external users from a specific tenant can access your applications, and under what conditions.
- **Outbound access policy**: which of your users can access a specific external tenant.

### Guest lifecycle management

1. **Quarterly access reviews for all guest users**: reviewer is the sponsoring employee or manager.
2. **Restrict invitations**: configure External Collaboration Settings to allow only admins (or a specific group) to invite guests; not all users.
3. **Access expiration**: set expiration on B2B invitations and entitlement management access packages for guests.
4. **Audit guest access**: regularly review which applications and groups guests have access to. Use Entra ID Governance access reviews scoped to "Guest users" membership.
5. **Auto-remediate reviews**: configure access reviews to automatically remove access when reviewers do not respond within the review period.
6. **Block specific external domains**: use External Collaboration Settings to deny-list domains from which you do not want to accept guest invitations.

---

## Monitoring and alerting

### Critical sign-in events

| Event | Alert priority | Action |
|---|---|---|
| Break-glass account sign-in | Critical (P1) | Immediate investigation; assume compromise until proven otherwise |
| Global Administrator role activation (PIM) | High (P2) | Verify with the activating user via out-of-band channel |
| Admin sign-in from new country | High | Verify legitimacy with the user |
| Multiple failed sign-ins across accounts (password spray) | High | Check Identity Protection; block originating IP |
| Consent grant for high-privilege application | High | Review the app and revoke if unexpected |
| Conditional Access policy modification | Medium | Verify the change was authorised |
| New MFA method registered by an admin | Medium | Confirm the admin initiated it |
| Bulk user creation or licence assignment | Medium | Confirm expected provisioning wave |
| Service principal sign-in failure spike | Medium | Investigate expired credential or credential-stuffing attempt |

### Key logs and retention

| Log | Location | Default retention |
|---|---|---|
| Sign-in logs | Entra ID > Monitoring > Sign-in logs | 30 days (all tiers); extend via Diagnostic Settings |
| Audit logs | Entra ID > Monitoring > Audit logs | 30 days; extend via export |
| Provisioning logs | Entra ID > Monitoring > Provisioning logs | 30 days |
| Identity Protection risk detections | Entra ID > Security > Risk detections | 90 days |

**SIEM export**: configure Diagnostic Settings to stream Sign-in logs and Audit logs to a Log Analytics workspace, Event Hub (for third-party SIEM), or Storage Account (for long-term archival). Integrate with Microsoft Sentinel or a third-party SIEM for extended retention, correlation, and automated alerting.

---

## Entra Connect server hardening

The Entra Connect server holds privileged sync credentials for both on-premises AD and Entra ID. A compromise is equivalent to a full domain + tenant compromise. Treat it as a Tier 0 asset.

| Hardening measure | Rationale |
|---|---|
| Dedicated server (no other roles) | Reduces attack surface; limits blast radius |
| No internet browsing | Only outbound HTTPS to Entra ID endpoints; block all other outbound |
| Credential Guard enabled | Protects sync account credentials from extraction |
| Limit admin access to named Entra Connect admins | Separate admin accounts; not domain admin accounts |
| Monitor all sign-ins and configuration changes | Unauthorised access or rule changes indicate compromise |
| Apply updates promptly | Entra Connect is updated frequently for security fixes |
| Run on-premises (not in a shared VM pool) | Shared hypervisor environments expand the trust boundary |

### Entra Connect sync accounts

| Account | Purpose | Security requirement |
|---|---|---|
| AD Connector account | Reads from and writes back to AD | Least privilege: only required AD permissions; never Domain Admin |
| Entra ID Connector account | Syncs objects to Entra ID | Auto-created during setup; Hybrid Identity Admin or Global Admin at setup only |
| ADSync service account | Runs the sync engine | Local service account or gMSA; not an interactive user |

The AD Connector account requires: Read access to directory objects, "Replicate Directory Changes" and "Replicate Directory Changes All" for Password Hash Sync, and targeted writeback permissions for the features enabled (group writeback, device writeback, password writeback). Never assign Domain Admin to this account.
