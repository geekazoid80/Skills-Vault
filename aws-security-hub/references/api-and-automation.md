# AWS Security Hub API and automation

Read-only audit and reporting for Security Hub run through the Security Hub API (via the AWS CLI or an SDK such as boto3): `GetFindings` and `GetFindingsV2` for findings, `DescribeStandards` and `DescribeStandardsControls` for standards posture, and `GetInsights` and `GetInsightResults` for saved views. Automated response runs through EventBridge event patterns. Every credential in this file is a placeholder; never inline a live access key, secret, or token.

## Authentication and least-privilege IAM

Security Hub API calls authenticate as an IAM identity (an IAM role assumed by the audit or automation principal, or a user's credentials). Prefer a role assumed with short-lived credentials over a long-lived access key, and prefer the credential provider chain (instance profile, environment, or SSO) over a static key in a config file.

```bash
# Assume the read-only audit role; the SDK/CLI then uses the temporary credentials
aws sts assume-role \
  --role-arn "arn:aws:iam::{ACCOUNT_ID}:role/security-hub-audit-readonly" \
  --role-session-name "securityhub-audit"
# returns temporary AccessKeyId / SecretAccessKey / SessionToken (all placeholders here)
```

### Read-only least-privilege policy

An audit role should hold only the read (`Get*`, `Describe*`, `List*`, `BatchGet*`) actions and nothing that mutates state. The `securityhub:Get*` / `Describe*` / `List*` shape below is deliberately narrow; a role that can also `BatchUpdateFindings`, `UpdateStandardsControl`, `BatchEnableStandards`, `CreateAutomationRule`, or `BatchImportFindings` is a write identity and is out of scope for a read-only audit.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecurityHubReadOnlyAudit",
      "Effect": "Allow",
      "Action": [
        "securityhub:GetFindings",
        "securityhub:GetFindingsV2",
        "securityhub:GetInsights",
        "securityhub:GetInsightResults",
        "securityhub:DescribeStandards",
        "securityhub:DescribeStandardsControls",
        "securityhub:DescribeHub",
        "securityhub:GetEnabledStandards",
        "securityhub:ListEnabledProductsForImport",
        "securityhub:GetFindingAggregator",
        "securityhub:ListFindingAggregators",
        "securityhub:ListSecurityControlDefinitions",
        "securityhub:BatchGetSecurityControls",
        "securityhub:ListAutomationRules",
        "securityhub:BatchGetAutomationRules"
      ],
      "Resource": "*"
    }
  ]
}
```

For a cross-account audit from the delegated administrator, the audit role is assumed in the delegated-admin account and reads the aggregated findings there; it does not need a role in every member account, because aggregation has already consolidated them.

AWS-managed policies exist (`AWSSecurityHubReadOnlyAccess` for read, `AWSSecurityHubFullAccess` for full), but a hand-scoped policy like the above keeps the audit identity to exactly the read actions and is easier to reason about than the broader managed read policy.

## Reading findings: GetFindings

`GetFindings` takes an ASFF filter object and returns matching findings. It is the workhorse of any read-only audit or report.

```bash
# Critical, active, not-yet-triaged findings, newest first
aws securityhub get-findings \
  --filters '{
    "SeverityLabel":  [{"Value":"CRITICAL","Comparison":"EQUALS"}],
    "WorkflowStatus": [{"Value":"NEW","Comparison":"EQUALS"}],
    "RecordState":    [{"Value":"ACTIVE","Comparison":"EQUALS"}]
  }' \
  --sort-criteria '[{"Field":"UpdatedAt","SortOrder":"desc"}]' \
  --max-results 100
```

Common filter fields: `AwsAccountId`, `Region`, `SeverityLabel`, `Type`, `ResourceType`, `ResourceId`, `ProductName`, `GeneratorId`, `WorkflowStatus`, `RecordState`, `ComplianceStatus`, `FirstObservedAt`, `LastObservedAt`, and `ResourceTags`. Filter by `ProductName` to scope to a single source (for example `GuardDuty` or `Inspector`), and by `AwsAccountId` for a cross-account admin view of one member account.

`GetFindingsV2` is the newer findings surface; use it where the newer schema and controls model is wanted, and `GetFindings` for the established ASFF filter shape.

## Reading standards posture

```bash
# Every available standard and its ARN
aws securityhub describe-standards

# The standards currently enabled in this account and region
aws securityhub get-enabled-standards

# The controls for an enabled standard subscription, with each control's status
aws securityhub describe-standards-controls \
  --standards-subscription-arn "{SUBSCRIPTION_ARN}"
```

`DescribeStandardsControls` returns each control's `ControlStatus` (ENABLED or DISABLED) and, when disabled, the `DisabledReason`. An audit reads this to find controls disabled with no reason. Read the enabled standards per region to confirm a standard is not enabled in one region only.

## Reading insights

```bash
# List insights (managed and custom)
aws securityhub get-insights

# The aggregated results for one insight
aws securityhub get-insight-results --insight-arn "{INSIGHT_ARN}"
```

Insights give a fast read of posture over time (top accounts by failed controls, resource types with the most findings) without re-running a broad `GetFindings` each time.

## Importing custom findings: the ASFF schema for BatchImportFindings

`BatchImportFindings` is how a partner product or a custom source pushes findings in. It is a write action, so it is out of scope for a read-only audit, but the ASFF shape is worth knowing because it is the schema every finding conforms to.

```bash
# A custom source imports an ASFF finding (write action; not part of a read-only audit)
aws securityhub batch-import-findings --findings '[
  {
    "SchemaVersion": "2018-10-08",
    "Id": "my-custom-finding-001",
    "ProductArn": "arn:aws:securityhub:{REGION}:{ACCOUNT_ID}:product/{ACCOUNT_ID}/default",
    "GeneratorId": "my-custom-scanner",
    "AwsAccountId": "{ACCOUNT_ID}",
    "Types": ["Software and Configuration Checks/Vulnerabilities/CVE"],
    "CreatedAt": "2024-01-15T10:30:00Z",
    "UpdatedAt": "2024-01-15T10:30:00Z",
    "Severity": {"Label": "HIGH"},
    "Title": "Custom security finding",
    "Description": "Description of the finding",
    "Resources": [{"Type":"AwsEc2Instance","Id":"arn:aws:ec2:{REGION}:{ACCOUNT_ID}:instance/{INSTANCE_ID}"}]
  }
]'
```

The required ASFF fields are `SchemaVersion`, `Id`, `ProductArn`, `GeneratorId`, `AwsAccountId`, `Types`, `CreatedAt`, `UpdatedAt`, `Severity`, `Title`, `Description`, and `Resources`. Timestamps are ISO 8601 UTC; keep them consistent with `utc-timestamps`. A custom source's `ProductArn` uses the account's default product ARN; a partner uses its own registered product ARN.

## EventBridge event patterns for automated response

Security Hub emits findings to EventBridge. An event pattern matches on the ASFF fields inside `detail.findings` and routes to a target. This is the pattern half of the automated-response operations in `references/operations.md`.

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Severity": { "Label": ["CRITICAL", "HIGH"] },
      "Compliance": { "Status": ["FAILED"] },
      "GeneratorId": [{ "prefix": "aws-foundational-security-best-practices" }]
    }
  }
}
```

```bash
# Route matching findings to a target (an SNS topic here)
aws events put-rule \
  --name "SecurityHubCriticalFSBP" \
  --event-pattern '{"source":["aws.securityhub"],"detail-type":["Security Hub Findings - Imported"]}' \
  --state ENABLED

aws events put-targets \
  --rule "SecurityHubCriticalFSBP" \
  --targets '[{"Id":"notify","Arn":"arn:aws:sns:{REGION}:{ACCOUNT_ID}:security-alerts"}]'
```

The three detail-types are `Security Hub Findings - Imported` (new or updated finding), `Security Hub Findings - Custom Action` (operator-triggered on selected findings), and `Security Hub Insight Results`. For a SIEM feed, route `Security Hub Findings - Imported` to a Kinesis Data Firehose delivery stream that lands in S3 or a SIEM ingestion endpoint, rather than polling `GetFindings` on a timer.

## Throttling, backoff, and pagination

- **Throttling**: the Security Hub API throttles per action. On a `ThrottlingException` (HTTP 429), back off exponentially with jitter and retry; the AWS SDKs do this by default, so prefer the SDK retry configuration over a hand-rolled loop. A read-only audit has no reason to run hot.
- **Pagination**: `GetFindings`, `GetInsights`, and the `Describe*` and `List*` calls page with a `NextToken`; follow it until absent rather than assuming the first page is complete. `--max-results` caps the page size, not the total. With the CLI, `--no-paginate` plus manual `--next-token` handling, or letting the SDK paginator run, both work; do not treat the first page as the whole result set.
- **Error handling**: never infer the cause of a non-2xx. Distinguish a transient `ThrottlingException` or `InternalException` (retry) from a permanent `AccessDeniedException` (the role is missing the action) or `InvalidAccessException` (Security Hub not enabled in that region), and confirm an access-denied is a real permission gap rather than a throttled or malformed call before reporting a capability as blocked.

## Secret-store discipline

- IAM access keys, role credentials, and partner API tokens live in the secret store or the credential provider chain, never in the script, the runbook, or a committed config file. See `secrets-hygiene`.
- Prefer an assumed role with short-lived credentials over a long-lived access key for anything unattended; short-lived credentials expire on their own and do not leak whole from a log line.
- Never put a credential or session token in a URL query string or a log line.
- Keep the audit identity read-only (`Get*`, `Describe*`, `List*`, `BatchGet*` only). If the same role can also update findings, change control status, enable standards, or import findings, split the read-only audit identity from the write identity so a compromised audit credential cannot change posture.
- Where a long-lived key is genuinely unavoidable, track its rotation and rotate it in place through the secret store before it lapses; a lapsed credential fails the audit job silently until someone notices the empty report.
