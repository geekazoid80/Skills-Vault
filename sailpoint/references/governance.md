# SailPoint governance

## Access certifications

Access certifications are periodic, structured reviews of who has access to what. Reviewers confirm that access is still appropriate or revoke it; SailPoint deprovisions revoked access automatically.

### Campaign types

| Type | Reviewer | Scope | Best for |
|---|---|---|---|
| Manager | People manager | All access for their direct reports | Quarterly standard access review |
| Source Owner | Application/source owner | All access on a specific source | App-specific or source-specific certification |
| Entitlement Owner | Named entitlement owner | Specific entitlements across all users | Sensitive or privileged entitlement review |
| Role Composition | Role owner | Access within a role | Role accuracy validation |
| Search-based | Configurable | Custom identity search results | Targeted reviews (e.g., users with SOD violations) |

### Campaign configuration checklist

1. **Scope**: define which identities and which access are in scope. Narrower scope = more meaningful review.
2. **Frequency**: quarterly for standard access; monthly for privileged access. Avoid over-certifying.
3. **Duration**: 2 to 4 weeks with automated email reminders at 1 week and 3 days remaining.
4. **Auto-revocation**: enable for items not actioned by the deadline. Without auto-revocation, unsigned items remain and the campaign's purpose is defeated.
5. **Reassignment**: allow reviewers to reassign items to a more knowledgeable reviewer (e.g., app owner instead of manager for technical entitlements).
6. **Exclusions**: exclude access that was certified in the last N days to reduce reviewer fatigue.

### Remediation

When a reviewer revokes access:
1. SailPoint triggers deprovisioning for the identity on the target source.
2. Track remediation completion: confirm the deprovisioning was executed (not just approved).
3. Escalate unexecuted remediations; provisioning errors block the governance outcome.

---

## Role management

### Role design principles

**Role explosion** occurs when too many fine-grained roles are created. Signs: more than 50 business roles in an organisation under 500 people; roles that differ by only one entitlement; roles named after specific individuals or temporary projects.

Remediation: consolidate roles; use Access Profiles for technical granularity below the business-role level; retire roles with fewer than a threshold of assignments.

Target: 80% of access covered by roles, 20% exception-based (individual entitlement assignments for non-standard needs).

### Role mining

SailPoint's role mining engine analyses existing entitlement assignments across the user population to identify common access patterns:

1. Run a role mining analysis: choose peer group (by department, title, location) and a similarity threshold.
2. Review suggested role candidates: SailPoint shows which entitlements appear together frequently.
3. Evaluate each candidate: does it represent a real job function? Does it have a clear owner?
4. Refine: merge overlapping candidates, split over-broad candidates.
5. Publish approved roles; assign to identities.

### Role governance

- Each role must have an owner (person accountable for role composition accuracy).
- Role owners receive periodic certification campaigns for role membership.
- Role changes (add/remove entitlements) require review and approval from the role owner.
- Review role assignments annually; archive roles with zero assignments.

---

## Separation of duties (SOD)

### Policy structure

SOD policies define toxic access combinations: pairs of entitlements (or roles) that no single identity should hold simultaneously.

```
Policy: "No payment creation and payment approval by the same person"
  Left side: entitlement or role representing "Create Payment"
  Right side: entitlement or role representing "Approve Payment"
  Action on violation:
    - Block: prevent the conflicting assignment from being provisioned
    - Flag: allow but record the violation and trigger a review
```

### SOD implementation workflow

1. **Inventory**: identify business-critical access pairs that must be separated (financial controls, IT admin + auditor, dev + prod deployment).
2. **Draft policies**: define each policy with clear left-side / right-side entitlement/role membership.
3. **Test in report-only mode**: run the SOD policy as report-only first; review the violation list. High violation counts often indicate data-quality issues or poorly scoped policies.
4. **Define exception workflow**: configure the approval chain for exceptions (manager approval + risk acceptance sign-off); set expiration dates on exceptions (no open-ended exceptions).
5. **Enable enforcement**: switch from report-only to blocking mode after the exception backlog is addressed.
6. **Monitor**: SOD checks run during access requests, certifications, and provisioning. Review violation reports regularly.

### SOD checks in the access request flow

When a user requests access that would create an SOD violation:
1. SailPoint detects the conflict during the access-request evaluation.
2. Depending on policy configuration: block the request (user must choose one side) or route to SOD exception approval.
3. Exception approver receives the violation details and accepts the risk (with expiration date) or denies.
4. All SOD exceptions are logged and appear in governance reports.

---

## IdentityAI risk scoring and outlier detection

### Risk score components

SailPoint IdentityAI assigns a risk score to each identity based on:

| Component | High-risk indicator |
|---|---|
| Entitlement count | More entitlements than peer average |
| Privileged access | Holds admin-level or sensitive entitlements |
| SOD violations | Active SOD policy violations |
| Outlier score | Access pattern significantly different from peers |
| Orphaned accounts | Accounts not correlated to an active identity |
| Certification failure history | Access repeatedly flagged in past certifications |

### Outlier detection

IdentityAI compares each identity's access pattern against their peer group (identities with similar department, title, and location). Identities whose access pattern diverges significantly are flagged as outliers.

**Reviewer aid**: during access certifications, IdentityAI provides recommendation labels (approve / revoke) based on peer analysis. Reviewers still make the final decision, but AI recommendations reduce cognitive load and surface anomalous access.

**Role insights**: IdentityAI identifies entitlements that frequently appear together across identities but are not yet captured in a role; these are role mining suggestions surfaced automatically.

### Acting on IdentityAI outputs

- Review the outlier report weekly (or before each certification campaign launch).
- Prioritise identities with high risk scores and active SOD violations for manual review.
- Launch a search-based certification campaign scoped to outlier identities.
- Investigate access that IdentityAI consistently recommends for revocation across multiple campaigns; if consistently appropriate, revoke it; if consistently appropriate to keep, adjust the peer-group model.

---

## Access request catalog

### Catalog design

The access request catalog is the self-service interface where users browse and request access. Design principles:
- Expose Access Profiles and Roles, not raw entitlements; entitlements are too granular for end users to evaluate.
- Write clear, plain-language descriptions of what each item grants.
- Categorise by department, application, or job function.
- Mark high-risk or privileged items prominently; route them through extended approval chains.

### Approval workflow patterns

| Pattern | When to use |
|---|---|
| Manager approval only | Low-risk access; standard departmental tools |
| Manager + application owner | Medium-risk; app-specific access |
| Manager + application owner + SOD check | High-risk; financial, HR, or privileged systems |
| Auto-approval | Very low risk; access with no entitlement sensitivity (read-only public catalog) |
| Time-limited approval | Temporary access for projects or contractors; access expires automatically |

### Access request API

```bash
# Submit an access request
POST /v3/access-requests
{
  "requestedFor": ["identity-id"],
  "requestedItems": [
    { "type": "ACCESS_PROFILE", "id": "access-profile-id" },
    { "type": "ROLE", "id": "role-id" }
  ],
  "requestedComment": "Need access for Project Alpha - Q2 deliverable"
}

# Get pending approvals for a reviewer
GET /v3/access-request-approvals/pending?reviewer-identity=reviewer-id

# Approve an access request item
POST /v3/access-request-approvals/approve
{
  "approvalId": "approval-id",
  "comment": "Approved; verified with manager"
}
```
