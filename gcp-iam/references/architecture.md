# GCP IAM architecture

## Resource hierarchy and IAM inheritance

### Hierarchy model

```
Organisation node (org ID, e.g. 123456789)
  |
  +-- Folder (logical grouping: teams, environments, business units)
  |     |
  |     +-- Project (billing unit, API enablement scope, resource container)
  |           |
  |           +-- Resources (GCS buckets, GCE instances, GKE clusters, ...)
```

Every resource belongs to exactly one project. Projects belong to a folder or directly to the organisation. Folders nest arbitrarily deep (maximum 10 levels recommended).

### Inheritance semantics

IAM bindings cascade down: a binding at the organisation node applies to all folders, projects, and resources beneath it. Bindings accumulate; they are never removed by a lower-level binding. To restrict access at a lower level, remove the higher-level binding or use organisation policies and VPC Service Controls (which operate independently of IAM).

**Policy at effective resource = union of all bindings from organisation to resource.**

This means granting `roles/owner` at the organisation level grants owner permissions on every resource in every project under the organisation. Minimise high-level bindings; prefer project-level and below.

### IAM Deny policies

IAM Deny policies (GA as of 2024) add explicit-deny capability on top of the allow-list IAM model. Deny policies are evaluated before allow policies; a matching deny rule overrides any allow binding. They attach at organisation, folder, or project scope. Use deny policies to enforce guardrails that cannot be expressed as organisation policies (e.g., deny a specific permission to all service accounts globally).

---

## IAM policy binding structure

### Policy object

```json
{
  "bindings": [
    {
      "role": "roles/storage.objectAdmin",
      "members": [
        "group:data-team@example.com"
      ],
      "condition": {
        "title": "prod-buckets-only",
        "expression": "resource.name.startsWith('projects/_/buckets/prod-')"
      }
    }
  ],
  "etag": "BwX...",
  "version": 3
}
```

Policy version 3 is required when conditions are present. The `etag` is used for optimistic concurrency; include it in `setIamPolicy` calls to prevent overwriting concurrent changes.

### Concurrent modification pattern

```bash
# Read-modify-write to avoid races
POLICY=$(gcloud projects get-iam-policy my-project --format=json)
# Modify POLICY in a script, preserving etag
echo "$POLICY" | jq '.bindings += [{"role":"roles/viewer","members":["user:bob@example.com"]}]' \
  | gcloud projects set-iam-policy my-project /dev/stdin
```

For production automation, prefer `add-iam-policy-binding` and `remove-iam-policy-binding` which handle etag management automatically.

---

## Service account design model

### Service account types

| Type | Created by | Lifecycle | Notes |
|---|---|---|---|
| User-managed | Customer | Explicit creation and deletion | Recommended; one per workload |
| Default (Compute Engine) | GCP on project creation | Tied to project | Granted `roles/editor` by default; disable or replace |
| Default (App Engine) | GCP on first App Engine use | Tied to project | `project-id@appspot.gserviceaccount.com` |
| Google-managed | GCP | Managed by GCP services | Do not modify; used by service agents |

### Service account impersonation

Service account impersonation allows a principal to obtain short-lived tokens scoped to a service account without exporting long-lived keys. Requires `roles/iam.serviceAccountTokenCreator` on the target service account.

```bash
# Generate an access token impersonating a service account
gcloud auth print-access-token \
  --impersonate-service-account=target-sa@project.iam.gserviceaccount.com
```

Use impersonation in automation pipelines instead of key export: the calling identity must be authorised, the token expires (1 hour default), and there is no key file to leak.

---

## Workload Identity Federation model

### Pool and provider model

```
Workload Identity Pool (container for external identity providers)
  |
  +-- Provider (one per external IdP: GitHub, AWS, Azure, OIDC IdP, SAML IdP)
        |-- Issuer URI (OIDC) or Entity ID (SAML)
        |-- Attribute mapping (external claim -> google.subject, attribute.*)
        |-- Attribute condition (CEL filter to restrict which external identities can authenticate)
```

The `google.subject` mapped attribute becomes the principal identifier in GCP IAM. Use it to grant the federated identity access to impersonate a service account:

```
member = "principal://iam.googleapis.com/projects/PROJECT_NUM/locations/global/workloadIdentityPools/POOL_ID/subject/SUBJECT"
```

Or to grant access to all identities in a pool with a matching attribute:

```
member = "principalSet://iam.googleapis.com/projects/PROJECT_NUM/locations/global/workloadIdentityPools/POOL_ID/attribute.repository/my-org/my-repo"
```

### Direct resource access vs. service-account impersonation

**Service-account impersonation (recommended for most cases)**: the federated identity is granted `roles/iam.workloadIdentityUser` on a service account, then exchanges its pool token for a service-account access token. IAM bindings on GCP resources reference the service account.

**Direct resource access**: the `principalSet` or `principal` is bound directly to GCP resource roles. Simpler setup but requires updating IAM bindings on every resource when the mapping changes. Use when no service account is needed as an intermediary.

---

## Organisation policy model

### Constraint types

| Type | How it works | Example |
|---|---|---|
| List constraint | Allow or deny a list of values | `constraints/gcp.resourceLocations`: allowedValues = `["in:us-locations"]` |
| Boolean constraint | Enforced or not enforced | `constraints/iam.disableServiceAccountKeyCreation`: enforced = true |

Organisation policies can be set as:
- **Inherited**: child inherits from parent (default behaviour if no policy set at this level).
- **Overriding**: child explicitly sets a value, overriding the parent. Boolean constraints cannot be relaxed at a lower level; list constraints can be further restricted.

### Policy evaluation order

Organisation policies are evaluated before IAM bindings. If an org policy prohibits an action (e.g., creating a public GCS bucket), the action is denied even if the principal has IAM permissions to perform it.

---

## VPC Service Controls architecture

### Perimeter model

```
Access Context Manager
  |-- Access levels (conditions: IP ranges, device trust, identity)

VPC Service Controls
  |-- Service perimeter (set of projects + set of protected services)
        |-- Ingress rules (allow specific principals or access levels into the perimeter)
        |-- Egress rules (allow specific principals or resources to exit the perimeter)
```

Resources inside the perimeter can communicate with each other and with approved external principals/projects per ingress/egress rules. Resources outside the perimeter cannot access protected APIs for services inside without an explicit ingress rule.

### Protected services

Over 100 GCP services support VPC Service Controls; key ones: BigQuery, Cloud Storage, Cloud KMS, Container Registry, Artifact Registry, Secret Manager, Pub/Sub, GKE. Full list at `accesscontextmanager.googleapis.com`.

### Dry-run mode

In dry-run mode, the perimeter logs violations without enforcing them. Violations appear in Cloud Audit Logs with the `dry_run` flag set. Deploy in dry-run for at least a week before switching to enforcement; analyse violations to identify legitimate access that needs ingress/egress rules.

---

## IAM Recommender

### Algorithm

IAM Recommender analyses Cloud Audit Logs over a rolling 90-day window to determine which permissions a principal actually exercised. It generates recommendations to:
- Replace broad roles with narrower predefined roles.
- Remove roles not used at all.
- Replace organisation/folder-level bindings with project-level bindings (right-sizing scope).

### Recommendation states

| State | Meaning |
|---|---|
| ACTIVE | New recommendation, not yet reviewed |
| CLAIMED | Marked in-progress (optimistic lock) |
| SUCCEEDED | Applied successfully |
| FAILED | Application attempted but failed |
| DISMISSED | Explicitly dismissed by reviewer |

Recommendations that are dismissed do not regenerate for 90 days. Recommendations that are not acted on recalculate monthly.

---

## BeyondCorp Enterprise architecture

### Identity-Aware Proxy (IAP)

IAP sits in front of web applications and VMs. Every request is authenticated and authorised by IAP before reaching the application:

```
User -> Google Front End -> IAP
                            |-- Verify identity (Google/IdP)
                            |-- Evaluate access policy (group membership, access level)
                            |-- Forward with IAP-signed headers (X-Goog-Authenticated-User-*)
                            v
                         Application (GCE, Cloud Run, GKE, App Engine)
```

IAP adds `X-Goog-Authenticated-User-Email` and `X-Goog-Authenticated-User-ID` headers to forwarded requests. Applications must validate these headers are present and signed; do not rely on them without verification (use the IAP JWT validation library).

### Access levels

Access levels are conditions evaluated at the time of the request:

- IP subnet ranges (corporate network, VPN egress).
- Device policy: screen lock required, OS type, Chrome OS verified, Endpoint Verification enrolled.
- Identity: specific user or group.

Access levels are referenced in IAP access policies and VPC Service Controls ingress rules.
