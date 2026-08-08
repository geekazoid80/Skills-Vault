# SailPoint architecture

## IdentityNow component model

### Sources

Sources are connectors to external systems. Two types:

**Authoritative sources** (define who exists): HR systems (Workday, SAP SuccessFactors, BambooHR, UKG). The identity's attributes are mastered here. When the authoritative source deactivates a record, SailPoint triggers the leaver process.

**Target sources** (where access is provisioned): Active Directory, Azure AD/Entra ID, Salesforce, ServiceNow, Google Workspace, Slack, databases (JDBC), Unix/Linux (SSH), and custom sources (SCIM, REST, flat file).

### Identity Profiles

Identity Profiles control how a source's records become IdentityNow identities. Each profile defines:
- **Correlation rule**: how to match source accounts to existing identities (by email, employee ID, UPN).
- **Attribute transformation**: map source attributes to the IdentityNow identity attributes via transforms.
- **Identity creation**: trigger account creation in target systems when a new identity is detected.

### Access Profiles and Roles

**Access Profile**: a bundle of entitlements on a single source (e.g., "AD Group: SalesTeam + AD Group: CRMAccess"). Access Profiles represent a coherent level of access on one system.

**Role**: a business-meaningful grouping of Access Profiles across systems (e.g., "Sales Representative Role" = AD Access Profile + Salesforce Access Profile + Slack Access Profile). Roles correspond to job functions.

**Role types:**

| Type | Composition | Use case |
|---|---|---|
| IT Role | Access Profiles (technical entitlements) | Technical access groupings below business-role level |
| Business Role | IT Roles + Access Profiles | Job-function bundles; what a user in a given job needs |

---

## Connector types

| Category | Connectors | Protocol |
|---|---|---|
| Directory | Active Directory, Azure AD/Entra ID, LDAP | LDAP, Microsoft Graph API |
| Cloud apps | Salesforce, ServiceNow, Workday, SAP, Slack, Google Workspace | SCIM, REST API, proprietary |
| Infrastructure | Unix/Linux (SSH), databases (JDBC) | SSH, JDBC |
| Custom | Web services, flat files | REST, CSV, JDBC |
| Cloud infrastructure | AWS IAM, Azure, GCP | Cloud provider APIs |

---

## Transforms (attribute mapping)

Transforms are JSON-defined data-transformation rules applied during attribute mapping.

**Concat transform (generate username):**

```json
{
  "name": "Generate Username",
  "type": "static",
  "attributes": {
    "value": {
      "type": "concat",
      "attributes": {
        "values": [
          {
            "type": "lower",
            "attributes": {
              "input": {
                "type": "identityAttribute",
                "attributes": { "name": "firstname" }
              }
            }
          },
          ".",
          {
            "type": "lower",
            "attributes": {
              "input": {
                "type": "identityAttribute",
                "attributes": { "name": "lastname" }
              }
            }
          }
        ]
      }
    }
  }
}
```

**Common transform types:**

| Type | Description |
|---|---|
| `concat` | Concatenate multiple values |
| `lower` / `upper` | Change string case |
| `trim` | Remove leading/trailing whitespace |
| `substring` | Extract a substring by position |
| `replace` | Replace a substring |
| `conditional` | Return different values based on a condition |
| `identityAttribute` | Reference another identity attribute as input |
| `accountAttribute` | Reference an attribute from a connected source account |
| `static` | Return a literal value |
| `reference` | Reference another named transform |

---

## JML lifecycle flows

### Joiner

```
HR source aggregates new hire record
  -> Identity Profile correlation: new identity created
  -> Provisioning policies triggered:
       - AD account created (naming convention from username transform)
       - M365/Exchange mailbox provisioned
       - Base-access Role assigned (department-based)
  -> Notifications sent to manager and IT team
  -> MFA enrolment workflow triggered
```

### Mover

```
HR source updates department, title, or manager
  -> SailPoint detects attribute change on next aggregation
  -> Role re-evaluation: old department Role removed, new department Role added
  -> Changed Access Profiles trigger provisioning updates
  -> Certification triggered for access removed during the move
  -> Manager notified of role changes
```

### Leaver

```
HR source sets termination date or deactivates record
  -> Pre-termination actions (configurable lead time):
       - Disable AD account, revoke VPN access
       - Notify manager to reassign tasks
  -> On termination date:
       - Deprovision all accounts (SCIM disable, AD deactivate)
       - Revoke all role and access-profile assignments
  -> Post-termination:
       - Archive data (Google Drive ownership transfer, mailbox archive)
       - Licence reclaim (M365, Salesforce)
       - Manager notified, open access requests cancelled
```

Target disablement within one hour of termination. Use `utc-timestamps` to reason about scheduling and lead-time windows.

---

## SailPoint APIs

```bash
# Search identities by department
POST /v3/search/identities
{
  "query": { "query": "department:Engineering" },
  "sort": ["displayName"]
}

# Create a certification campaign
POST /v3/campaigns
{
  "name": "Q1 Manager Certification",
  "type": "MANAGER",
  "deadline": "2024-03-31T00:00:00Z",
  "sunlightPeriod": {
    "timezoneId": "US/Eastern",
    "end": "2024-03-17T00:00:00Z"
  }
}

# Submit an access request
POST /v3/access-requests
{
  "requestedFor": ["identity-id"],
  "requestedItems": [
    { "type": "ACCESS_PROFILE", "id": "access-profile-id" }
  ],
  "requestedComment": "Need access for Q1 project"
}

# Get SOD violations for an identity
GET /v3/sod-violations?identityId=identity-id
```

Derive all deadline values from the live clock; see `utc-timestamps`.
