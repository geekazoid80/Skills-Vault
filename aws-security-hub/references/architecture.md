# AWS Security Hub architecture

Security Hub sits above the AWS security services as an aggregation and normalisation layer, and beside them as a compliance assessor. Understanding what each source contributes, how findings are normalised into one format, and how the multi-account and multi-region topology consolidates them is what lets you reason about why a finding appears where it does, and what its status actually means.

## The aggregation and normalisation model

Security Hub does two things: it aggregates findings from many sources into one place, and it runs its own standards checks. Both outputs are the same normalised format (ASFF), so a single query, filter, or automation rule works across every source.

```
AWS security services            Partner products           Security Hub itself
  GuardDuty (threats)              SIEM / SOAR                 Standards controls
  Inspector (vulnerabilities)      CNAPP                         (CIS, FSBP, PCI, NIST)
  Macie (data security)            Vuln management
  IAM Access Analyzer (access)     Container security
  Config (rule evaluation)         EDR / network
  Firewall Manager (policy)
        |                               |                            |
        +-------------------------------+----------------------------+
                                        |
                            normalise into ASFF
                                        |
                        Security Hub (per account, per region)
                                        |
                         cross-region finding aggregation
                                        |
                     delegated administrator (Organizations)
                                        |
              one consolidated, normalised, cross-account view
```

Security Hub is a findings aggregator and a compliance assessor, not a detection engine. The depth of any threat or vulnerability finding comes from the underlying service; Security Hub adds the normalisation, the consolidation, and the posture score. Reasoning about Security Hub as if it detects is the common error; it surfaces what the sources detect.

## Finding sources

Each AWS source enables separately, and its findings only flow to Security Hub once both it and Security Hub are enabled in the same region.

| Source | What it contributes |
|---|---|
| Amazon GuardDuty | Threat detections from logs and network telemetry: unauthorised access, credential misuse from an unusual location, cryptomining, command-and-control traffic, reconnaissance, and stealth signals such as CloudTrail being disabled |
| Amazon Inspector | Vulnerability findings: CVEs in EC2 and Lambda, container-image CVEs in Amazon ECR, and network reachability, with CVSS and EPSS scoring |
| Amazon Macie | Data security: S3 buckets holding PII or other sensitive data, unencrypted sensitive-data buckets, and public or cross-account access to sensitive data |
| IAM Access Analyzer | External-access findings: resource policies (S3, IAM roles, KMS keys, SQS, and more) that grant access to an external or cross-account principal |
| AWS Config | Config-rule evaluation results: resources that are non-compliant against a managed or custom Config rule. Config is also the evaluation engine many standards controls run on |
| AWS Firewall Manager | Firewall-policy compliance findings across accounts (WAF, security-group, and network-firewall policy drift) |
| AWS Health, Systems Manager Patch Manager | Security-relevant service-health events (for example exposed credentials) and patch-compliance findings |

### Partner and custom sources

Security Hub accepts findings from 70-plus partner products in ASFF: SIEM and SOAR, CNAPP, vulnerability management, container security, EDR, and network security. A partner product is enabled with `EnableImportFindingsForProduct`, after which it pushes findings via `BatchImportFindings`. Any custom system (a home-grown scanner, a CI security gate) can push ASFF findings the same way through `BatchImportFindings`, which makes Security Hub the aggregation point for non-AWS signals too.

Because AWS Config underpins many standards controls, a standard that expects Config records will not evaluate correctly if Config is not recording the relevant resource types. Config being enabled with the right recording scope is a precondition for accurate CSPM, not an optional extra.

## The AWS Security Finding Format (ASFF)

ASFF is the single normalised schema for every finding. Learning its key fields is what makes filtering, automation, and audit tractable across all sources.

```json
{
  "SchemaVersion": "2018-10-08",
  "Id": "arn:aws:securityhub:us-east-1:{ACCOUNT_ID}:finding/{FINDING_ID}",
  "ProductArn": "arn:aws:securityhub:us-east-1::product/aws/guardduty",
  "GeneratorId": "arn:aws:guardduty:us-east-1:{ACCOUNT_ID}:detector/{DETECTOR_ID}",
  "AwsAccountId": "{ACCOUNT_ID}",
  "Types": ["TTPs/Initial Access/UnauthorizedAccess:EC2-SSHBruteForce"],
  "CreatedAt": "2024-01-15T10:30:00Z",
  "UpdatedAt": "2024-01-15T10:30:00Z",
  "Severity": { "Label": "HIGH", "Normalized": 70 },
  "Title": "EC2 instance is being probed on port 22",
  "Description": "...",
  "Resources": [{
    "Type": "AwsEc2Instance",
    "Id": "arn:aws:ec2:us-east-1:{ACCOUNT_ID}:instance/{INSTANCE_ID}",
    "Region": "us-east-1",
    "Tags": { "Environment": "production" }
  }],
  "Compliance": { "Status": "FAILED", "RelatedRequirements": ["PCI DSS 1.3.1"] },
  "Workflow": { "Status": "NEW" },
  "RecordState": "ACTIVE"
}
```

Key fields:

- **`Types`**: a namespace, category, and classifier taxonomy for the finding (for example `TTPs/Initial Access/...` or `Software and Configuration Checks/...`).
- **`Severity.Label`**: CRITICAL, HIGH, MEDIUM, LOW, or INFORMATIONAL. **`Severity.Normalized`** is the 0-to-100 numeric form (0 informational, 1 to 39 low, 40 to 69 medium, 70 to 89 high, 90 to 100 critical).
- **`Compliance.Status`**: PASSED, FAILED, WARNING, or NOT_AVAILABLE, set for standards-control findings.
- **`ProductArn`** and **`GeneratorId`**: which product produced the finding and which specific generator (detector, control, or rule) inside it.

### Workflow.Status versus RecordState

Two status fields govern a finding and confusing them causes real mistakes.

| Field | Controlled by | Values | Meaning |
|---|---|---|---|
| `Workflow.Status` | Customer | NEW, NOTIFIED, SUPPRESSED, RESOLVED | Your triage state: reviewed, ticketed, ignored, or fixed |
| `RecordState` | Finding provider | ACTIVE, ARCHIVED | Whether the underlying condition is still detected |

The trap: a finding can be `RecordState: ACTIVE` and `Workflow.Status: RESOLVED` at the same time. That means someone marked it resolved while the condition still exists, which is a misconfiguration to surface, not a closed issue. A genuinely fixed condition moves to `RecordState: ARCHIVED` on its own when the provider stops detecting it.

## Cross-account and cross-region aggregation

### AWS Organizations and the delegated administrator

Security Hub integrates with AWS Organizations so the whole estate is managed from one account.

- The Organizations management account designates one account (usually the dedicated security or audit account) as the **Security Hub delegated administrator**.
- The delegated admin sees findings from every member account and manages the organisation's Security Hub configuration.
- **Auto-enable** brings new member accounts into Security Hub automatically as they join the organisation, so coverage does not depend on someone remembering to enable each new account.

### Central configuration

Central configuration lets the delegated administrator define configuration policies (which standards are on, which controls are enabled or disabled, and their parameters) and apply them across accounts and regions from one place, rather than configuring each account and region by hand. It is the mechanism that keeps a large organisation's Security Hub consistent; without it, per-account drift is almost inevitable.

### Cross-region finding aggregation

Each region runs its own Security Hub instance. A **finding aggregation region** is designated to consolidate findings from the linked regions into one view, so findings, insights, and the security score can be seen across regions in a single place.

Region-linking modes:

- `ALL_REGIONS`: aggregate from every region, including new regions as AWS adds them.
- `ALL_REGIONS_EXCEPT_SPECIFIED`: every region except a named exclusion list.
- `SPECIFIED_REGIONS`: only the named regions.

Without aggregation, each region's console must be checked separately and there is no single security score for the account. Cross-region queries against the aggregation region can be slower than a single-region query, which is the trade-off for the consolidated view.

### The multi-account finding flow

```
Member account A (us-east-1)
  GuardDuty, Inspector, Config, Macie findings
    -> Security Hub in us-east-1
        -> cross-region aggregation
Delegated administrator Security Hub (us-east-1, aggregation region)
  all findings from all member accounts and all linked regions
    -> unified compliance and security-score view
    -> cross-account finding search and filtering
    -> one EventBridge event source for organisation-wide automation
```

## Security Hub CSPM

The standards-check half of Security Hub is its cloud security posture management (CSPM) capability. Enabling a standard turns on a set of controls, each of which evaluates your resource configuration continuously (many of them via AWS Config) and produces a PASSED or FAILED compliance status per resource. The aggregate is the per-standard security score: the percentage of controls passing across all in-scope resources.

CSPM here is configuration assessment (is CloudTrail enabled, is this S3 bucket blocking public access, is that RDS instance encrypted), which is distinct from Amazon Inspector's software-vulnerability assessment (is this package version vulnerable to a given CVE). Both land in Security Hub as ASFF findings, but they answer different questions: CSPM checks how a resource is configured, Inspector checks what software it runs. The operational depth on standards, controls, and the score lives in `references/operations.md`.
