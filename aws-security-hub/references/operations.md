# AWS Security Hub operations and audit

This is the operational depth: which standards to enable and how to tune controls, how the finding workflow lifecycle runs, how insights and automation rules work, how EventBridge drives automated response, and the read-only audit lens with thresholds and decision trees. The management surface is the Security Hub console, the AWS CLI, and the Security Hub API; the API depth lives in `references/api-and-automation.md`.

## Security standards

### The available standards

- **AWS Foundational Security Best Practices (FSBP)**: AWS's own standard, the broadest AWS-native coverage with several hundred controls across all major services, continuously extended as AWS ships new services. The usual starting baseline.
- **CIS AWS Foundations Benchmark**: the widely-recognised industry baseline, available as v1.2.0 (legacy, still widely deployed), v1.4.0, and v3.0.0 (newest). Covers IAM, storage, logging, monitoring, and networking hygiene.
- **PCI DSS**: checks AWS resource configuration against payment-card-data security requirements. Compliance-driven.
- **NIST SP 800-53 Rev 5**: the NIST control framework mapped to AWS service configurations, used for FedRAMP and similar programmes.
- **AWS Resource Tagging Standard**: checks that required tags are present, with configurable required keys.

FSBP for the AWS-native baseline plus CIS for the recognised industry benchmark is a common pairing; add PCI DSS or NIST only when a compliance driver requires it, because each standard adds controls and noise.

### Enabling standards and reading the score

Standards enable per account and per region. In an Organizations deployment, use central configuration to enable them consistently rather than per-account by hand.

```bash
# List every available standard and its ARN
aws securityhub describe-standards

# Enable a standard (example ARNs; confirm the current ARN per region and version)
aws securityhub batch-enable-standards \
  --standards-subscription-requests '[
    {"StandardsArn": "arn:aws:securityhub:{REGION}::standards/aws-foundational-security-best-practices/v/1.0.0"}
  ]'

# List the controls for an enabled standard subscription
aws securityhub describe-standards-controls \
  --standards-subscription-arn "{SUBSCRIPTION_ARN}"
```

The security score is the percentage of controls passing across all in-scope resources for that standard. Drill down by control, by resource, and by account, and watch the trend rather than the single number: a stable 85 with the right controls enabled is healthier than a 95 achieved by disabling the controls that were failing.

### Controls and control status

Some controls genuinely do not apply (an EC2 control in an account that runs no EC2). Disable those, and always record a reason; a silently disabled control is an invisible gap.

```bash
aws securityhub update-standards-control \
  --standards-control-arn "{CONTROL_ARN}" \
  --control-status DISABLED \
  --disabled-reason "Not applicable: this account runs no EC2 instances"
```

The disabled-reason is the audit trail. A control disabled with no reason cannot later be justified or confidently re-enabled, so treat a missing reason as a finding in its own right.

## Finding workflow lifecycle

Every finding carries a customer-controlled `Workflow.Status`. Moving findings through it is what turns aggregation into action.

| Status | Who sets it | Meaning |
|---|---|---|
| NEW | Security Hub (automatic) | New finding, not yet triaged |
| NOTIFIED | Customer | Owner notified or a remediation ticket raised |
| RESOLVED | Customer | Remediation verified complete |
| SUPPRESSED | Customer | Intentionally ignored: false positive or accepted risk |

Remember the `RecordState` distinction from `references/architecture.md`: `Workflow.Status` is your triage state, `RecordState` (ACTIVE or ARCHIVED) is whether the provider still detects the condition. A finding stuck in NEW means aggregation works but triage does not; a pile of RESOLVED findings that are still ACTIVE means someone is closing the workflow without fixing the condition.

```bash
# Move a finding to SUPPRESSED with a note (a write action, out of scope for a read-only audit)
aws securityhub batch-update-findings \
  --finding-identifiers '[{"Id":"{FINDING_ARN}","ProductArn":"{PRODUCT_ARN}"}]' \
  --workflow '{"Status":"SUPPRESSED"}' \
  --note '{"Text":"False positive: bucket is internal only","UpdatedBy":"secops"}'
```

## Insights

An insight is a saved filter plus a grouping attribute: a reusable, aggregated view over findings. Security Hub ships managed insights and you can create custom ones.

Managed insights include views such as top accounts by failed-control count, resource types with the most findings, and AMIs generating the most findings. A custom insight pins the filter and the group-by that matters to you:

```bash
aws securityhub create-insight \
  --name "Critical unresolved findings, last 7 days" \
  --filters '{
    "SeverityLabel":  [{"Value":"CRITICAL","Comparison":"EQUALS"}],
    "WorkflowStatus": [{"Value":"NEW","Comparison":"EQUALS"}]
  }' \
  --group-by-attribute "ResourceId"
```

Insights are for humans watching posture over time; automation rules and EventBridge are for acting on findings.

## Automation rules

Automation rules run at ingestion and update ASFF fields on findings that match their criteria, in rule-order. They are the scalable way to suppress, enrich, or reprioritise findings without a Lambda in the loop.

```bash
aws securityhub create-automation-rule \
  --rule-name "Suppress dev-account standards findings" \
  --rule-order 1 \
  --criteria '{
    "AwsAccountId": [{"Value":"{DEV_ACCOUNT_ID}","Comparison":"EQUALS"}],
    "ProductName":  [{"Value":"Security Hub","Comparison":"EQUALS"}]
  }' \
  --actions '[{
    "Type":"FINDING_FIELDS_UPDATE",
    "FindingFieldsUpdate":{
      "Workflow":{"Status":"SUPPRESSED"},
      "Note":{"Text":"Dev account: different risk tolerance","UpdatedBy":"automation"}
    }
  }]'
```

Automation rules are more flexible than the older suppression mechanism: they can set any updatable ASFF field (workflow status, severity, a note), and support compound criteria. The risk is a rule with criteria that are too loose, which silently suppresses more than intended. Scope the criteria tightly and review the rule set as part of the audit.

## Automated response with EventBridge

New and updated findings emit EventBridge events. A rule matches on finding criteria and targets a responder.

```
Finding created or updated
  -> EventBridge (Security Hub event source)
      -> rule matches finding criteria
          -> target: Lambda / SNS / SQS / Step Functions / Systems Manager Automation
```

Event detail-types from Security Hub:

- `Security Hub Findings - Imported`: a new or updated finding arrived from any source.
- `Security Hub Findings - Custom Action`: an operator triggered a custom action from the console or API.
- `Security Hub Insight Results`: an insight-result event.

### Common response patterns

- **Notify on critical**: EventBridge rule (Severity.Label CRITICAL) targets an SNS topic that fans out to Slack, email, or a Lambda.
- **Ticket new high and critical**: EventBridge rule (Severity.Label HIGH or CRITICAL, Workflow.Status NEW) targets a Lambda that opens a ticket, then calls `BatchUpdateFindings` to move the finding to NOTIFIED with the ticket reference.
- **Auto-remediate a configuration finding**: EventBridge rule (a specific control's GeneratorId, Compliance.Status FAILED) targets a Lambda or a Systems Manager Automation document that fixes the resource (for example enabling S3 block-public-access), then moves the finding to RESOLVED.
- **Quarantine an instance for a threat finding**: EventBridge rule (ResourceType AwsEc2Instance, a specific GuardDuty finding type) targets a Systems Manager Automation document that isolates the instance, snapshots it for forensics, and notifies the SOC.

Auto-remediation is powerful and risky. Scope each rule to a specific finding type and account set, test in a non-production account first, and prefer moving the finding to RESOLVED via `BatchUpdateFindings` (with a note recording the automated action) over leaving it looking untouched.

### Custom actions

A custom action gives an operator a console button that emits a `Security Hub Findings - Custom Action` event for selected findings, so the same EventBridge automation can be triggered manually (send to SOAR, open a ticket) rather than only on ingestion.

```bash
aws securityhub create-action-target \
  --name "Send to SOAR" \
  --description "Send selected findings to the SOAR platform" \
  --id "SendToSOAR"
```

## Read-only audit lens

A Security Hub posture audit is read-only: read findings, standards, controls, insights, and automation rules through the read-only API, and never suppress a finding, disable a control, change a workflow status, or create a rule. Walk the thresholds below.

### Audit threshold table

| Control | Healthy | Finding | Why it matters |
|---|---|---|---|
| Deployment scope | Org-wide with a delegated administrator | Single account while the estate is an Organizations | Member-account findings invisible from the security account |
| Auto-enable | On for new accounts | Off | New accounts join with no Security Hub coverage |
| Finding aggregation region | Configured, linking all in-scope regions | Absent | Each region checked separately, no consolidated score |
| Standards coverage | Baseline standards enabled in every in-scope region | A standard enabled in one region only | Other regions unassessed against that baseline |
| Disabled controls | Each carries a recorded disabled-reason | Disabled with no reason | Invisible, unjustifiable gap |
| Finding sources | GuardDuty, Inspector, Macie, Access Analyzer, Config on where relevant | Sources off, so Security Hub shows standards findings only | The aggregation value is missing |
| AWS Config recording | Recording the resource types the standards need | Not recording, or narrow scope | Standards controls evaluate incorrectly |
| Workflow throughput | Findings move out of NEW | Large, growing NEW backlog | Aggregation works, triage does not |
| Resolved-versus-active | RESOLVED findings are ARCHIVED | RESOLVED findings still ACTIVE | Condition still exists, workflow closed prematurely |
| Automation and suppression rules | Tightly scoped, reviewed | Broad criteria hiding more than intended | Real findings silently suppressed |
| Audit and automation IAM roles | Read-only for audit, least-privilege for automation | Audit role can write | A compromised audit token can change posture |

### Remediation decision trees

**Coverage finding**

```
Estate is an AWS Organizations?
  yes -> delegated administrator designated?
           no  -> highest priority: designate the security/audit account as delegated admin
           yes -> auto-enable on for new accounts?
                    no -> enable it so new accounts are covered automatically
Finding aggregation region configured?
  no -> configure one (ALL_REGIONS unless a region is deliberately excluded)
Baseline standards enabled in every in-scope region?
  no -> enable via central configuration, not per region by hand
```

**Standards and controls finding**

```
A control is disabled?
  reason recorded?
    no  -> treat as a finding: require a disabled-reason or re-enable
    yes -> confirm the reason still holds (the service may now be in use)
Security score dropped?
  check whether controls were disabled to raise it (a false improvement)
AWS Config recording the resource types the standards need?
  no -> enable Config recording; standards controls depend on it
```

**Finding workflow finding**

```
Large backlog stuck in NEW?
  yes -> there is no triage workflow: route findings to owners (EventBridge -> ticketing)
Findings marked RESOLVED but RecordState still ACTIVE?
  yes -> the condition still exists: reopen and remediate the resource, not the workflow
Automation/suppression rule criteria loose?
  yes -> tighten to specific account, product, and finding type; re-audit what it hides
```

## Verification before claiming done

Per `completion-gate`, "enabled Security Hub" is not a finish line. Before the chunk closes:

- [ ] Deployed org-wide with a delegated administrator, and auto-enable on for new accounts (where the estate is an Organizations).
- [ ] A finding aggregation region is configured and links every in-scope region.
- [ ] The baseline standards (FSBP, and CIS where wanted) are enabled in every in-scope region, plus any compliance-driven standard.
- [ ] Every disabled control carries a recorded disabled-reason.
- [ ] The relevant finding sources (GuardDuty, Inspector, Macie, IAM Access Analyzer, Config, Firewall Manager) are enabled, and AWS Config is recording the resource types the standards need.
- [ ] Findings move out of NEW through a triage workflow; no RESOLVED findings remain RecordState ACTIVE.
- [ ] Automation and suppression rules are scoped tightly and reviewed; none hide more than intended.
- [ ] Any audit or reporting IAM role is read-only; automation roles are least-privilege.
