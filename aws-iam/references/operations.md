# AWS IAM operations

## Policy authoring checklist

Before attaching or deploying any IAM policy:

1. **Run `accessanalyzer validate-policy`** to catch syntax errors, incorrect condition keys, and best-practice violations.
2. **Use the IAM Policy Simulator** (`aws iam simulate-principal-policy`) to verify the effective permissions for a specific principal and action set before changes reach production.
3. **Check for wildcard actions and resources**: any `"Action": "*"` or `"Resource": "*"` on a write action warrants explicit justification.
4. **Confirm condition keys are correct**: condition key names are case-insensitive in evaluation but must exist for the given service and action. Unknown keys silently fail to match.
5. **Test the least-privilege boundary**: can the principal do what they need? Can they do anything they should not?
6. **Version the policy** before modifying: Customer managed policies retain up to five versions; set the old version as default before saving the new one so rollback is immediate.

---

## Cross-account access patterns

### Pattern 1: identity-based + resource-based (resource in target account)

Target account: add a resource-based policy (S3 bucket policy, KMS key policy) granting the source account's principal.
Source account: add an identity-based policy allowing the same action on the resource ARN.
Both are required unless the resource-based policy names the exact principal ARN (not `:root`).

### Pattern 2: cross-account role assumption (hub-and-spoke)

Target account: create a role with a trust policy allowing assumption from the source account's principals.
Source account: grant `sts:AssumeRole` to the relevant users/roles pointing at the target role ARN.
Useful when the target account has many resources and the source has many users; the role becomes the access point.

### Pattern 3: organisation-wide role (all accounts, one management point)

Create a role in each member account with a trust policy allowing the management account's admin role. Provision via AWS CloudFormation StackSets so every existing and new account gets the role automatically. Used for audit and security tool cross-account access.

---

## Permission-set design for IAM Identity Center

**Design principles:**
- One permission set per job function (not per person). Examples: `PlatformEngineer`, `SecurityAuditor`, `DatabaseAdmin`, `ReadOnly`.
- Session duration: 4-8 hours for human access; 1 hour for automation. Never set longer than the working day.
- Use AWS managed policies where they fit; add customer managed policies for organisation-specific restrictions.
- Attach a permission boundary if engineers need to create IAM roles within their accounts; prevents privilege escalation via role creation.

**Account assignment strategy:**
- Group accounts by environment (prod, staging, dev) and by team (platform, data, security).
- Assign via IAM Identity Center groups (synced from IdP) rather than individual users; group membership changes propagate automatically.
- Automate assignments via Terraform (`aws_ssoadmin_account_assignment`) so new accounts are provisioned consistently.

---

## SCP testing approach

1. **Draft in a sandbox OU**: create a test OU containing a single non-production account; attach the SCP candidate.
2. **Verify target actions are denied**: test the exact actions the SCP should block using that account's credentials.
3. **Verify break-glass exclusion**: confirm the `ArnNotLike` or `ArnNotEquals` condition on the break-glass role is functioning; assume the break-glass role and verify actions are allowed.
4. **Check for service dependency breaks**: AWS services assume roles in your accounts; some SCPs can inadvertently block service-linked roles if conditions are not scoped correctly. Review `arn:aws:iam::*:role/aws-service-role/*` exclusion needs.
5. **Deploy to staging OU first**, then gradually widen to production OUs. Monitor CloudTrail for AccessDenied events in the 24 hours after deployment.

---

## IAM Access Analyzer remediation workflow

1. **List findings**: `aws accessanalyzer list-findings --analyzer-arn <arn>` or review in Security Hub.
2. **Classify each finding**: is the external access intentional (e.g., cross-account backup role) or unintentional (e.g., public S3 bucket)?
3. **Resolve unintentional findings**: remove the offending policy statement or tighten the Principal to a specific ARN.
4. **Archive intentional findings** with a note explaining the business justification. Archived findings reappear if the policy changes.
5. **Set up automated alerting**: configure EventBridge to send new active findings to a Security Operations channel via SNS or Lambda.

**Unused access remediation:**
- For unused roles: verify the role is not used by checking CloudTrail `AssumeRole` events beyond the 90-day IAM window; delete if genuinely unused.
- For unused permissions: generate a last-accessed service report (`aws iam generate-service-last-accessed-details`) to see which actions the role actually called; remove permissions for services never used.

---

## Access-denied troubleshooting

### Step 1: identify which policy layer is denying

The IAM access-denied error message often indicates the source. Error patterns:
- `with an explicit deny in a service control policy` -> SCP is blocking; check Organisation-level SCPs on the account's OU.
- `with an explicit deny in a resource-based policy` -> check the resource policy (S3 bucket policy, KMS key policy, etc.).
- `because no identity-based policy allows` -> the principal's identity-based policies do not grant the action; check attached policies and inline policies.
- `with an explicit deny in a permissions boundary` -> the boundary is blocking; check the boundary attached to the role or user.
- `with an explicit deny in a session policy` -> the AssumeRole call included a session policy that is more restrictive than the role.

### Step 2: simulate with IAM Policy Simulator

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/MyRole \
  --action-names s3:PutObject \
  --resource-arns arn:aws:s3:::my-bucket/my-key \
  --context-entries Key=aws:RequestedRegion,Type=string,Values=us-east-1
```

### Step 3: review CloudTrail

CloudTrail records every denied API call with the `errorCode: AccessDenied` field. The `userIdentity` block shows the exact assumed role ARN and session name; the `requestParameters` show the exact resource and action that was denied.

---

## CLI commands for common tasks

```bash
# List all managed policies attached to a role
aws iam list-attached-role-policies --role-name MyRole

# List inline policies on a role
aws iam list-role-policies --role-name MyRole

# Simulate policy evaluation
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/RoleName \
  --action-names ec2:DescribeInstances \
  --resource-arns "*"

# Generate credential report
aws iam generate-credential-report
aws iam get-credential-report --query 'Content' --output text | base64 -d

# Create an IAM Access Analyzer (organisation-level)
aws accessanalyzer create-analyzer \
  --analyzer-name org-analyzer \
  --type ORGANIZATION

# List Access Analyzer findings
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:us-east-1:123456789012:analyzer/org-analyzer \
  --filter '{"status": {"eq": ["ACTIVE"]}}'

# Validate a policy document
aws accessanalyzer validate-policy \
  --policy-type IDENTITY_POLICY \
  --policy-document file://policy.json

# List SCPs attached to an OU
aws organizations list-policies-for-target \
  --target-id ou-xxxx-xxxxxxxx \
  --filter SERVICE_CONTROL_POLICY

# List permission sets in Identity Center
aws sso-admin list-permission-sets \
  --instance-arn arn:aws:sso:::instance/ssoins-xxx

# List account assignments for a permission set
aws sso-admin list-account-assignments \
  --instance-arn arn:aws:sso:::instance/ssoins-xxx \
  --account-id 123456789012 \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-xxx/ps-xxx
```
