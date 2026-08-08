---
name: gcp-iam
description: "Use for Google Cloud IAM and Cloud Identity implementation, configuration, and troubleshooting. Covers the resource hierarchy (organisation, folder, project, resource), IAM policy bindings and additive inheritance, role types (basic, predefined, custom), member types (user, group, service account, domain, allUsers), service accounts and the key-export anti-pattern, Workload Identity Federation (pools, OIDC/SAML providers, attribute mapping, attribute conditions), organisation policies and constraint types (list, boolean), VPC Service Controls (service perimeters, ingress/egress rules, access levels, dry-run mode), IAM Conditions (CEL expressions for resource name, resource type, request time, and combined conditions), IAM Recommender (90-day usage analysis, recommendation workflow), BeyondCorp Enterprise and Identity-Aware Proxy, Policy Analyzer, and Cloud Identity directory management. References: architecture.md, operations.md. Triggers include \"GCP IAM\", \"Google Cloud IAM\", \"Cloud Identity\", \"Workload Identity Federation\", \"Workload Identity Pool\", \"Organization policy\", \"org policy\", \"VPC Service Controls\", \"service perimeter\", \"IAM Recommender\", \"IAM Conditions\", \"CEL expression\", \"BeyondCorp\", \"Identity-Aware Proxy\", \"IAP\", \"GCP roles\", \"Google Cloud roles\", \"service account\", \"service account key\", \"gcloud iam\", \"allUsers\", \"allAuthenticatedUsers\", \"roles/owner\", \"roles/editor\", \"roles/viewer\", \"predefined role\", \"custom role\", \"constraints/iam\", \"Endpoint Verification\", \"google.iam.policy.Recommender\", \"principalSet\", \"workloadIdentityPools\". For IAM architecture, federation protocols, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# GCP IAM

> **Skill marker**: When applying this skill, begin your reply with `[skill: gcp-iam]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Google Cloud IAM implementation: resource hierarchy, policy bindings and inheritance, role types, service accounts, Workload Identity Federation, organisation policies, VPC Service Controls, IAM Conditions, and IAM Recommender. The conceptual layer (access-control model choice, IdP selection, zero trust architecture) lives in `identity-access-management`.

## When to use

- Writing or reviewing IAM policy bindings: adding roles to users, groups, service accounts, or federated identities at any hierarchy level (organisation, folder, project, resource).
- Configuring Workload Identity Federation: creating pools and providers, mapping external identity attributes, eliminating service-account key exports.
- Authoring or auditing organisation policies: resource location constraints, service-account key creation denial, public IP restrictions, domain-restricted sharing.
- Designing VPC Service Controls: defining service perimeters, authoring ingress/egress rules, testing with dry-run mode.
- Writing IAM Conditions (CEL expressions) for time-based, resource-name-based, or resource-type-based conditional bindings.
- Reviewing IAM Recommender findings and applying permission right-sizing recommendations.
- Configuring BeyondCorp Enterprise: Identity-Aware Proxy for web applications and VMs, access levels, and Endpoint Verification.
- Troubleshooting IAM access issues: using Policy Analyzer, `gcloud projects get-iam-policy`, and audit logs.

## When not to use

- **IAM architecture, access-control model choice, or IdP selection**: use `identity-access-management`.
- **GCP resource configuration, billing, and project management beyond IAM**: use `gcp-cloud-ops`.
- **Credential, secret, and service-account key storage or rotation procedures**: use `secrets-hygiene`. Service-account keys are credentials; their custody belongs there.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Resource hierarchy and policy inheritance

GCP organises resources in a tree: Organisation -> Folder(s) -> Project(s) -> Resources. IAM policies bind roles to members at any node; bindings are inherited down the hierarchy.

```
Organisation (example.com)
  |-- Folder: Production
  |     |-- Project: prod-app-1
  |           |-- Resources (GCE, GCS, GKE, etc.)
  |-- Folder: Staging
        |-- Project: staging-app-1
```

Inheritance is additive: a role granted at the organisation level applies to every folder, project, and resource below it. There is no deny-at-a-lower-level in standard IAM bindings. To restrict access, remove the binding or use organisation policies and VPC Service Controls. (IAM Deny policies exist but are a separate, newer feature; they add explicit deny capability at organisation, folder, and project scope.)

### IAM policy bindings

GCP IAM uses an allow-list model: a principal must have an explicit role binding to act. The absence of a binding is an implicit deny.

```yaml
bindings:
- role: roles/storage.objectViewer
  members:
  - user:alice@example.com
  - group:data-analysts@example.com
  - serviceAccount:app-sa@project-id.iam.gserviceaccount.com
  condition:
    title: "Only production bucket"
    expression: "resource.name.startsWith('projects/_/buckets/prod-')"
```

**Member types:**

| Member | Format | Notes |
|---|---|---|
| User | `user:email@example.com` | Individual Google account |
| Group | `group:name@example.com` | Google Group; preferred for access management |
| Service account | `serviceAccount:sa@project.iam.gserviceaccount.com` | Machine identity |
| Domain | `domain:example.com` | All users in the Google Workspace domain |
| allUsers | `allUsers` | Anyone on the internet; use only for intentionally public resources |
| allAuthenticatedUsers | `allAuthenticatedUsers` | Any Google account; do not use for access control |

### Role types

| Type | Example | Characteristics |
|---|---|---|
| Basic | `roles/owner`, `roles/editor`, `roles/viewer` | Thousands of permissions across all services; avoid in production |
| Predefined | `roles/storage.objectViewer`, `roles/compute.admin` | Google-managed, service-specific, right-sized |
| Custom | `projects/my-project/roles/customRole` | Customer-defined set of specific permissions |

Create custom roles when predefined roles are too broad. Prefer predefined roles wherever one fits; they are updated when new service features add new permissions.

### Service accounts

Machine identities for GCP workloads:

- **Default service accounts**: auto-created per project (Compute Engine default SA, App Engine default SA). Granted the Editor role by default; over-privileged and not recommended for production use.
- **User-managed**: created explicitly with specific minimum roles. One service account per workload; never share service accounts across workloads.
- **Google-managed**: used by Google services internally (Cloud Build service agent, etc.); do not modify.

Never export service-account keys. Keys are long-lived, exportable credentials that can be leaked. Use Workload Identity Federation for external workloads and attached service accounts for GCP workloads running on Compute Engine, GKE, Cloud Run, or Cloud Functions.

### Workload Identity Federation

Authenticate external workloads to GCP APIs without service-account keys:

Supported external identity providers: AWS (EC2 instance roles, ECS tasks), Azure (managed identities), GitHub Actions, Kubernetes (non-GKE OIDC), and any OIDC 1.0 or SAML 2.0 provider.

```bash
# Create a workload identity pool
gcloud iam workload-identity-pools create github-pool \
  --location=global \
  --display-name="GitHub Actions Pool"

# Create a provider for GitHub Actions (OIDC)
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == 'my-org/my-repo'"

# Grant the federated identity permission to impersonate a service account
gcloud iam service-accounts add-iam-policy-binding \
  app-deploy@my-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/attribute.repository/my-org/my-repo"
```

### Organisation policies

Centralised constraints enforced across the resource hierarchy; evaluated before IAM bindings. Common constraints:

| Constraint | Effect |
|---|---|
| `constraints/iam.disableServiceAccountKeyCreation` | Prevents export of service-account keys |
| `constraints/compute.vmExternalIpAccess` | Restricts public IPs on Compute Engine VMs |
| `constraints/gcp.resourceLocations` | Restricts deployment regions |
| `constraints/iam.allowedPolicyMemberDomains` | Restricts IAM bindings to specific domains |
| `constraints/compute.requireShieldedVm` | Requires Shielded VM configuration |
| `constraints/storage.uniformBucketLevelAccess` | Enforces uniform bucket-level access (disables ACLs) |

Organisation policies use list constraints (allowed values, denied values) or boolean constraints (enforced or not). Set at organisation, folder, or project; lower levels can be more restrictive but not less restrictive than the parent.

### IAM Conditions

Conditional IAM bindings use CEL (Common Expression Language) expressions:

```
# Time-based access
request.time < timestamp('2024-12-31T00:00:00Z')

# Resource name filter
resource.name.startsWith('projects/_/buckets/prod-')

# Resource type filter
resource.type == 'storage.googleapis.com/Bucket'

# Combined
resource.name.startsWith('projects/_/buckets/prod-') &&
request.time.getHours('America/New_York') >= 9 &&
request.time.getHours('America/New_York') <= 17
```

IAM Conditions are evaluated at every API request; conditions on bindings at higher levels are inherited with the binding.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Resource hierarchy and inheritance model, IAM policy binding structure, member types, role types and selection, service account types and design, Workload Identity Federation pool and provider model, organisation policy types and constraint catalogue, VPC Service Controls perimeter model and ingress/egress rules, IAM Recommender algorithm, BeyondCorp and IAP architecture | `references/architecture.md` |
| Operations | Policy binding commands, Workload Identity Federation setup patterns, organisation policy authoring, VPC Service Controls dry-run workflow, IAM Recommender review and apply workflow, IAM Conditions authoring, access troubleshooting with Policy Analyzer and audit logs, gcloud CLI reference | `references/operations.md` |

## Cross-references

- `identity-access-management`: access-control model selection (RBAC vs ABAC), zero trust architecture, IdP comparison, JML lifecycle design, multi-cloud IAM patterns.
- `gcp-cloud-ops`: GCP project management, VPC networking, billing, and resource configuration; routes back here for IAM binding and policy questions.
- `secrets-hygiene`: service-account keys and OAuth tokens; never export or inline service-account keys; use Workload Identity Federation instead.
- `utc-timestamps`: IAM Condition time-based expressions (`request.time < timestamp(...)`) and token expiry must be reasoned in UTC.
- `terraform-iac-ops`: GCP IAM resources managed via Terraform (`google_project_iam_binding`, `google_service_account`, `google_iam_workload_identity_pool`).

## Red flags

- **Using basic roles (Owner, Editor, Viewer)**: these grant thousands of permissions across all GCP services. Replace with predefined or custom roles in production environments.
- **Exporting service-account keys**: keys are long-lived credentials that can be leaked via source control, container images, or log output. Use Workload Identity Federation for external workloads and attached service accounts for GCP-native workloads.
- **`allUsers` or `allAuthenticatedUsers` on sensitive resources**: these open resources to anyone on the internet or any Google account. Use only for intentionally public content; alert on any new binding to these members.
- **Not using Google Groups for access management**: binding roles to individual users is unmanageable at scale and creates orphaned bindings when users leave. Use Google Groups; manage group membership in Cloud Identity or Google Workspace.
- **Ignoring IAM Recommender findings**: Recommender analyses 90 days of actual usage and identifies over-provisioned roles. Unreviewed recommendations compound; check monthly.
- **No organisation policies**: without org policies, any project can export service-account keys, create public-IP VMs, deploy resources in any region, or grant access to external domains.
- **VPC Service Controls deployed without dry-run testing**: enabling perimeters without dry-run mode first can break legitimate access patterns for BigQuery, GCS, and other protected services. Always test in dry-run mode for at least a week before enforcing.

## Bottom line

Bind roles at the lowest appropriate hierarchy level; prefer groups over individuals; use predefined roles over basic roles; and never export service-account keys. Enforce organisation policies to create guardrails across all projects. Use Workload Identity Federation to grant external workloads access without credentials. Run IAM Recommender monthly and apply least-privilege recommendations. Load `references/architecture.md` for the data model and `references/operations.md` for command patterns and troubleshooting procedures.
