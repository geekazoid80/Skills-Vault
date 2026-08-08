# AWS IAM architecture

## Policy type taxonomy

### Identity-based policies

Attached directly to IAM principals (users, groups, roles). Define what actions the principal may take on which resources and under what conditions.

- **AWS managed policies**: maintained by AWS; update when services add new actions. Examples: `ReadOnlyAccess`, `AdministratorAccess`, `AmazonS3ReadOnlyAccess`.
- **Customer managed policies**: authored and versioned by the customer. Up to 5 versions retained; one marked as the default.
- **Inline policies**: embedded directly in a user, group, or role. Not reusable. Use only when a policy must be strictly tied to a single principal's lifecycle.

### Resource-based policies

Attached to the resource rather than the principal. Support cross-account access natively. The principal in the policy statement can be in a different account.

Services supporting resource-based policies include: S3 (bucket policies), SQS (queue policies), KMS (key policies), Lambda (function policies), SNS (topic policies), IAM roles (trust policies), Secrets Manager, ECR, and others.

KMS key policies are mandatory; unlike other resource types, a KMS key with no key policy is inaccessible even to the account root unless the key was created with default key policy.

### Permission boundaries

A managed policy attached to an IAM user or role that sets the maximum permissions the entity can ever receive. Acts as a ceiling; the effective permissions are the intersection of the boundary and the identity-based policies.

```
Effective permissions = identity-based policies AND permission boundary
                         (not union; intersection)
```

Use permission boundaries to safely delegate IAM role creation to developers: they can create roles for their services but cannot grant those roles more than the boundary permits.

### Service Control Policies

SCPs apply to all IAM principals in the attached OU or account, including the root user of member accounts. SCPs do not apply to the management account.

**Evaluation order within an account subject to SCPs:**

```
1. SCP must ALLOW (or not Deny)
2. Identity-based policy must ALLOW
3. Permission boundary must ALLOW (if attached)
4. Session policy must ALLOW (if present)
5. Resource-based policy may independently ALLOW cross-account
```

**SCP strategy approaches:**

- **Allow-list (restrictive default)**: attach a Deny-all SCP and add explicit Allows for approved services. Maximally restrictive; every new service must be explicitly permitted.
- **Deny-list (permissive default)**: allow `*` by default; add targeted Deny statements for prohibited actions. More common; easier to maintain.

Deny-list SCPs recommended for most organisations. Common deny targets: root account usage, specific dangerous IAM actions, leaving the organisation, disabling GuardDuty/CloudTrail/Security Hub, and non-approved region deployment.

### Session policies

Passed as a parameter to `sts:AssumeRole`, `sts:AssumeRoleWithWebIdentity`, or `sts:AssumeRoleWithSAML`. They further restrict the permissions available in the resulting session without exceeding what the role's identity-based policies permit.

Useful for: scoping down a shared role per job run, per user, or per request; implementing attribute-based session scoping in federation flows.

---

## Trust policy and role assumption patterns

### Cross-account role assumption

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::SOURCE_ACCOUNT:root" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "unique-external-id" }
    }
  }]
}
```

`arn:aws:iam::ACCOUNT:root` in the Principal means any principal in that account authorised by its own identity-based policies. To restrict to a specific role, use `arn:aws:iam::ACCOUNT:role/RoleName`.

### OIDC federation (GitHub Actions, Kubernetes IRSA)

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
    }
  }
}
```

For Kubernetes IRSA (IAM Roles for Service Accounts): the OIDC provider URL is the cluster's issuer URL; the `sub` condition is `system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT_NAME`.

### Service principal (instance profiles, Lambda execution roles)

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "lambda.amazonaws.com" },
  "Action": "sts:AssumeRole"
}
```

EC2 instance profiles wrap a role so that code running on the instance can assume it without explicit credentials. The instance metadata service (IMDS) vends temporary credentials; use IMDSv2 (session-oriented) exclusively.

---

## IAM Identity Center architecture

### Component model

```
AWS Organizations
  |-- Identity Center instance (one per org)
        |-- Identity source (choose one):
        |     |-- Identity Center directory (built-in)
        |     |-- AWS Managed Microsoft AD
        |     |-- External IdP (SAML/SCIM: Okta, Entra ID, etc.)
        |-- Permission sets
        |-- Account assignments (user/group + permission set + account)
```

**Permission set provisioning**: when an account assignment is created, Identity Center provisions an IAM role in the target account with the permission set's policies attached. The role name follows the pattern `AWSReservedSSO_<PermissionSetName>_<RandomSuffix>`.

**SCIM provisioning from external IdP**: Identity Center supports SCIM 2.0 for automatic user and group synchronisation from Okta, Entra ID, or other IdPs. This keeps Identity Center membership in sync without manual management.

### CLI access

Users authenticate via `aws sso login --profile <name>`, which opens a browser session to obtain short-lived credentials cached locally. The `~/.aws/config` profile references the SSO start URL, account ID, role name, and region. Credentials auto-expire per the permission set's `--session-duration` (15 min to 12 hours).

---

## IAM Access Analyzer

### Analyser types

| Analyser type | Zone of trust | Finds |
|---|---|---|
| Account | Current account | Resources shared with principals outside the account |
| Organisation | AWS Organisation | Resources shared with principals outside the org |
| Unused access | Account | Unused roles, unused access keys, and unused permissions |

**External-access findings** are generated when a resource-based policy grants access to a principal outside the zone of trust. Findings are not alerts; they identify access that may be intentional. Archive or resolve each finding after review.

**Unused access findings**: IAM Access Analyzer analyses CloudTrail data to identify:
- IAM roles not used in the last 90 days.
- Access keys not used in the last 90 days.
- Permissions granted but never exercised.

### Custom policy checks

`validate-policy` checks a policy document against IAM best practices and correctness rules before deployment:

```bash
aws accessanalyzer validate-policy \
  --policy-type IDENTITY_POLICY \
  --policy-document file://policy.json
```

`check-no-new-access` compares a candidate policy against a reference policy to verify it does not expand permissions:

```bash
aws accessanalyzer check-no-new-access \
  --new-policy-document file://new-policy.json \
  --existing-policy-document file://reference-policy.json \
  --policy-type IDENTITY_POLICY
```

---

## Credential model

### IAM user credentials

| Credential | Notes |
|---|---|
| Console password | Used for AWS Management Console; optional for service users |
| Access key ID + secret | Programmatic API access; long-lived; treat as high-risk |
| MFA device (TOTP/hardware) | Required for console; can also be required for `sts:AssumeRole` via condition `aws:MultiFactorAuthPresent` |
| X.509 certificate | Legacy SOAP API; effectively unused in modern AWS |

**IAM credential report**: `aws iam generate-credential-report` and `aws iam get-credential-report` produce a CSV listing all users with their credential ages, last-use dates, and MFA status. Use for quarterly access reviews.

### STS temporary credentials

`sts:AssumeRole` response contains:
- `AccessKeyId`: temporary key ID (prefix `ASIA`)
- `SecretAccessKey`: temporary secret
- `SessionToken`: required in `AWS_SESSION_TOKEN`; validates the credential is temporary
- `Expiration`: UTC timestamp when the credentials expire

Workloads on EC2 or ECS retrieve credentials from the instance/task metadata service automatically via the AWS SDK; no explicit credential management is needed.

### Service-linked roles

AWS-managed roles created automatically when a service feature is enabled (e.g., `AWSServiceRoleForElasticLoadBalancing`). The trust policy is locked to the AWS service principal; the permissions policy is AWS-managed and cannot be modified. Delete the role when the service feature is no longer needed.
