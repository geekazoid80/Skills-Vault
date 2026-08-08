---
name: aws-iam
description: "Use for AWS Identity and Access Management (IAM) and IAM Identity Center implementation, configuration, and troubleshooting. Covers IAM policy language (identity-based, resource-based, permission boundaries, session policies, VPC endpoint policies), policy evaluation logic and explicit-deny semantics, IAM roles and trust policies (cross-account, service principal, OIDC federation, SAML federation), IAM Identity Center (formerly AWS SSO) with permission sets and account assignments, Service Control Policies (SCPs) and AWS Organizations guardrails, ABAC with tags and tag-based conditions, IAM Access Analyzer (external-access findings, unused-access findings, custom policy checks), credential management (root account lockdown, access key rotation, STS temporary credentials, service-linked roles), and AssumeRole patterns including ExternalId for confused-deputy prevention. References: architecture.md, operations.md. Triggers include \"AWS IAM\", \"IAM policy\", \"IAM role\", \"IAM Identity Center\", \"AWS SSO\", \"SCP\", \"permission set\", \"cross-account\", \"IAM Access Analyzer\", \"assume role\", \"trust policy\", \"sts:AssumeRole\", \"permission boundary\", \"ABAC tags\", \"aws:PrincipalTag\", \"ExternalId\", \"service-linked role\", \"identity-based policy\", \"resource-based policy\", \"session policy\", \"VPC endpoint policy\", \"aws:RequestedRegion\", \"organizations:LeaveOrganization\", \"accessanalyzer\", \"sso-admin\", \"arn:aws:iam\", \"AdministratorAccess\", \"OrganizationAccountAccessRole\". For IAM architecture, federation protocols, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# AWS IAM

> **Skill marker**: When applying this skill, begin your reply with `[skill: aws-iam]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers AWS IAM implementation: policy language and evaluation logic, roles and trust policies, IAM Identity Center for multi-account access, Service Control Policies, ABAC with tags, IAM Access Analyzer, and credential management. The conceptual layer (access-control model choice, federation protocol selection, least-privilege design) lives in `identity-access-management`.

## When to use

- Writing or reviewing IAM policies: identity-based, resource-based, permission boundaries, session policies, or VPC endpoint policies.
- Designing cross-account access patterns: trust policies, ExternalId, resource-based policy cross-account grants.
- Configuring IAM Identity Center: identity source selection, permission sets, account assignments, and CLI access via `aws sso login`.
- Authoring or auditing Service Control Policies in an AWS Organizations setup.
- Implementing ABAC: tag-based conditions, `aws:PrincipalTag`, `aws:ResourceTag`, and tag enforcement via SCPs.
- Running IAM Access Analyzer: creating analysers, reviewing external-access and unused-access findings, validating policy JSON before deployment.
- Credential lifecycle: disabling root access keys, rotating IAM user access keys, switching workloads to STS temporary credentials, managing service-linked roles.
- Troubleshooting access-denied errors: tracing which policy layer is denying an action, simulating policy evaluation.

## When not to use

- **IAM architecture, federation design, or access-control model choice**: use `identity-access-management`.
- **AWS resource configuration and account-level operations beyond IAM**: use `aws-cloud-ops`.
- **VPC, security-group, and network-ACL access control**: use `aws-networking-audit`.
- **Credential, secret, and key storage or rotation procedures**: use `secrets-hygiene`. AWS access keys and STS tokens are credentials; their custody belongs there.
- **Token expiry reasoning or session-timeout maths**: use `utc-timestamps` alongside this skill.

## Core model

### Policy language

AWS policies are JSON documents containing one or more `Statement` blocks. Each statement has `Effect` (Allow or Deny), `Action` (one or more API actions), `Resource` (ARN or wildcard), and an optional `Condition` block.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ],
      "Condition": {
        "StringEquals": {
          "s3:prefix": ["home/${aws:username}/"]
        }
      }
    }
  ]
}
```

**Policy types:**

| Policy type | Attached to | Purpose |
|---|---|---|
| Identity-based | Users, groups, roles | Grant permissions to the principal |
| Resource-based | S3, SQS, KMS, Lambda, etc. | Grant cross-account access to the resource |
| Permission boundary | Users, roles | Maximum permissions the entity CAN have (ceiling) |
| SCP | OUs, accounts (Organizations) | Maximum permissions accounts CAN have |
| Session policy | STS session | Limit permissions for a specific assumed-role session |
| VPC endpoint policy | VPC endpoints | Control which principals can use the endpoint |

### Policy evaluation logic

```
1. Start with implicit DENY
2. Evaluate all applicable policy layers:
   a. SCPs (AWS Organizations) -- must ALLOW
   b. Resource-based policies -- can ALLOW cross-account directly
   c. Identity-based policies -- must ALLOW
   d. Permission boundaries -- must ALLOW
   e. Session policies -- must ALLOW
3. Explicit DENY in ANY layer overrides all ALLOWs
4. If no explicit DENY and every applicable layer ALLOWs -> ALLOWED
```

Cross-account note: both the source account's identity-based policy AND the target account's resource-based policy must allow the action, UNLESS the resource-based policy names the principal's ARN directly (not `*`), in which case no identity-based policy is needed in the source account.

### Roles and trust policies

Trust policies define who can call `sts:AssumeRole`. Common patterns:

| Pattern | Principal | Use case |
|---|---|---|
| Cross-account | `arn:aws:iam::ACCOUNT:root` or specific role/user | Access resources in another account |
| AWS service | `Service: "ec2.amazonaws.com"` | EC2 instance profiles, Lambda execution roles |
| OIDC federation | `Federated: "arn:aws:iam::ACCOUNT:oidc-provider/..."` | GitHub Actions, Kubernetes IRSA |
| SAML federation | `Federated: "arn:aws:iam::ACCOUNT:saml-provider/..."` | Enterprise SSO via SAML |

Always include `sts:ExternalId` condition when granting cross-account AssumeRole to a third party; this prevents confused-deputy attacks where the third party assumes your role on behalf of a different customer.

### IAM Identity Center

Centralised SSO for multi-account AWS environments:

- **Identity source**: Identity Center built-in directory, Active Directory (via AD Connector or AWS Managed AD), or external SAML/OIDC IdP (Okta, Entra ID).
- **Permission sets**: templates defining AWS permissions (IAM policies and managed policies) that are instantiated as IAM roles in target accounts.
- **Account assignments**: bind users or groups from the identity source to a permission set in a specific account.

```bash
# Create a permission set
aws sso-admin create-permission-set \
  --instance-arn arn:aws:sso:::instance/ssoins-xxx \
  --name "ReadOnlyAccess" \
  --session-duration "PT8H"

# Assign to a group in an account
aws sso-admin create-account-assignment \
  --instance-arn arn:aws:sso:::instance/ssoins-xxx \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-xxx/ps-xxx \
  --principal-type GROUP \
  --principal-id "group-id" \
  --target-type AWS_ACCOUNT \
  --target-id "123456789012"
```

### Service Control Policies

SCPs are guardrails attached to OUs or accounts in AWS Organizations. They restrict the maximum permissions any principal in that scope can exercise. They never grant permissions on their own.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyRegionsOutsideUSEU",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2", "eu-west-1"]
        },
        "ArnNotLike": {
          "aws:PrincipalARN": "arn:aws:iam::*:role/OrganizationAdmin"
        }
      }
    },
    {
      "Sid": "DenyLeavingOrganization",
      "Effect": "Deny",
      "Action": "organizations:LeaveOrganization",
      "Resource": "*"
    }
  ]
}
```

Common SCPs: deny non-approved regions, deny root account usage, deny leaving the organisation, deny disabling security services (GuardDuty, CloudTrail, Security Hub). Always exclude a break-glass role from any deny SCP.

### ABAC with tags

Tag-based conditions let a single policy cover many resources automatically:

```json
{
  "Effect": "Allow",
  "Action": ["ec2:StartInstances", "ec2:StopInstances"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "ec2:ResourceTag/Project": "${aws:PrincipalTag/Project}"
    }
  }
}
```

Tag strategy: enforce tags at resource creation via SCPs or IAM policies; align principal tags (on IAM roles) with resource tags using a consistent key set such as `Project`, `Environment`, `Owner`, and `CostCenter`.

### Credential management

| Credential type | Use case | Rotation | Security note |
|---|---|---|---|
| Root account | Account setup only | Disable access keys entirely | Hardware MFA; no access keys |
| IAM user access keys | Legacy programmatic access | 90 days maximum | Prefer STS temporary credentials |
| STS temporary credentials | AssumeRole, federation | Auto-expire (15 min to 12 hours) | Preferred for all programmatic access |
| IAM Identity Center | Human console/CLI access | Session-based | Central management, MFA enforced |
| Service-linked roles | AWS service access | AWS-managed | Cannot be modified directly |

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Policy type taxonomy, evaluation logic detail, trust policy patterns, IAM Identity Center architecture, SCP strategy and OU design, ABAC tag model, IAM Access Analyzer analyser types and findings, credential types and rotation | `references/architecture.md` |
| Operations | Policy authoring checklist, cross-account access patterns, permission-set design, SCP testing approach, Access Analyzer remediation workflow, access-denied troubleshooting, policy simulation with IAM Policy Simulator, CLI commands for common tasks | `references/operations.md` |

## Cross-references

- `identity-access-management`: access-control model selection (RBAC vs ABAC), federation protocol design, JML lifecycle design, multi-cloud IAM architecture.
- `aws-cloud-ops`: AWS account management, VPC, and resource configuration beyond IAM; route resource-level access control questions that span services there.
- `aws-networking-audit`: VPC security groups, network ACLs, and VPC endpoint design; routes back here for VPC endpoint policies.
- `secrets-hygiene`: AWS access keys, STS tokens, and service-account credentials; never inline them in code or commit to version control.
- `utc-timestamps`: STS session expiry (`Expiration` field), IAM credential report `access_key_last_rotated`, and Access Analyzer finding `createdAt`/`updatedAt` timestamps must be reasoned in UTC.
- `terraform-iac-ops`: IAM resources managed via Terraform (`aws_iam_role`, `aws_iam_policy`, `aws_ssoadmin_permission_set`).

## Red flags

- **Root account used for operations**: root credentials should only be used for initial account setup and break-glass. Disable root access keys; protect with a hardware MFA key.
- **Long-lived IAM user access keys**: access keys are the most common AWS credential-leak vector. Rotate every 90 days at most; replace with AssumeRole and STS temporary credentials for all workload use.
- **Wildcard actions and resources** (`"Action": "*", "Resource": "*"`): almost never appropriate outside break-glass. Use IAM Access Analyzer to right-size.
- **Missing permission boundaries**: a developer role that can create IAM roles can escalate to full admin by creating a role with `AdministratorAccess`. Bind permission boundaries on any role that has `iam:CreateRole` or `iam:AttachRolePolicy`.
- **SCPs deployed without sandbox testing**: an untested SCP applied to a production OU can silently break automation and services. Always test in a sandbox OU first.
- **Confused-deputy without ExternalId**: cross-account role trust without an `sts:ExternalId` condition allows the trusted party to assume your role on behalf of any of their customers. Always add `ExternalId` for third-party integrations.
- **Not using IAM Identity Center for human access**: managing IAM users per account is unscalable and creates audit gaps. Use Identity Center for all human console and CLI access.

## Bottom line

Model least privilege as the interaction of all applicable policy layers: SCPs establish the ceiling, permission boundaries cap individual principals, identity-based policies grant what they need, and resource-based policies handle cross-account. Use IAM Identity Center for all human access; never issue long-lived access keys to workloads. Run IAM Access Analyzer continuously and remediate external-access findings before they age. Load `references/architecture.md` for policy model internals and `references/operations.md` for authoring checklists and operational procedures.
