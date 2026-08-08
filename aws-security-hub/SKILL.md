---
name: aws-security-hub
description: "Use for AWS Security Hub operations and read-only security-findings audit: the AWS-native service that aggregates and normalises security findings and runs cloud security posture (CSPM) checks against security standards. Covers finding aggregation from GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, AWS Config, and Firewall Manager plus 70-plus partner products; the AWS Security Finding Format (ASFF); security standards (CIS AWS Foundations Benchmark, AWS Foundational Security Best Practices, PCI DSS, NIST SP 800-53) with controls and the security score; the delegated administrator and AWS Organizations model with central configuration; cross-account and cross-region finding aggregation; finding workflow status (NEW, NOTIFIED, SUPPRESSED, RESOLVED); insights; automation rules; and EventBridge-driven automated response. Also carries a read-only audit lens: standards enabled but drifting, controls disabled without justification, delegated admin and auto-enable gaps, no cross-region aggregation, findings stuck in NEW, blanket suppression rules, and the Security Hub API for a read-only posture (GetFindings, DescribeStandards, GetInsights) with an IAM least-privilege read-only policy. When not to use: for vendor-neutral CNAPP / CSPM taxonomy and platform selection see cloud-security-posture; for vulnerability programme design, CVSS/EPSS scoring, and remediation SLAs see vulnerability-management; for general AWS service selection and configuration see aws-cloud-ops; for VPC and network exposure auditing see aws-networking-audit; for GRC frameworks and compliance evidence see compliance-benchmark-audit; for external outside-in attack surface see attack-surface-management. This skill owns AWS Security Hub operations. Triggers include \"AWS Security Hub\", \"Security Hub\", \"ASFF\", \"AWS Security Finding Format\", \"Security Hub findings\", \"Security Hub standards\", \"Security Hub aggregation\", \"Security Hub central configuration\", \"Security Hub EventBridge\", \"AWS security findings\", \"CIS AWS Foundations Benchmark\", \"AWS Foundational Security Best Practices\", \"FSBP\", \"cross-account security findings\"."
license: MIT
metadata:
  version: 1.0.0
---

# AWS Security Hub

> **Skill marker**: When applying this skill, begin your reply with `[skill: aws-security-hub]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns AWS Security Hub operations and read-only security-findings audit: the AWS-native service that aggregates security findings from AWS services and partner products into one normalised format and runs cloud security posture (CSPM) checks against security standards. It assumes the platform decision (Security Hub as the AWS-native aggregation and CSPM layer, whether or not a third-party CNAPP also runs) has already been made; for vendor-neutral CNAPP and CSPM taxonomy and platform selection see `cloud-security-posture`. The depth here is the aggregation model, the ASFF finding format, the standards and controls, the Organizations and cross-region topology, and the read-only audit lens that keeps a Security Hub deployment complete and least-privilege.

## Overview

Security Hub is a findings aggregator and a compliance assessor, not a deep detection or response platform. The depth of any finding comes from the underlying service; Security Hub normalises and consolidates. The pieces a deployment usually runs are:

- **Finding aggregation**: findings from GuardDuty (threat detection), Amazon Inspector (vulnerability scanning), Macie (data security), IAM Access Analyzer (external access), AWS Config (rule evaluation), and Firewall Manager (policy compliance), plus 70-plus partner products, all normalised into the AWS Security Finding Format (ASFF).
- **Security standards**: CIS AWS Foundations Benchmark, AWS Foundational Security Best Practices (FSBP), PCI DSS, and NIST SP 800-53, evaluated continuously as controls, producing a per-standard security score.
- **Cross-account and cross-region consolidation**: an AWS Organizations delegated administrator sees every member account, and a finding aggregation region consolidates all linked regions into one view.
- **Workflow and automation**: a customer-controlled workflow status per finding (NEW, NOTIFIED, SUPPRESSED, RESOLVED), insights (saved filtered and grouped views), automation rules, and EventBridge-driven automated response.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (single account or Organizations, which security services are enabled, which regions are in scope, the compliance drivers) before advising. Only ask for what is not already covered.

Before configuring or auditing, establish:

1. **The account scope.** A single account, or AWS Organizations with a delegated administrator? Security Hub is most valuable deployed org-wide with a delegated admin and cross-region aggregation; a single-account deployment is a much narrower thing to reason about.
2. **Which finding sources are enabled.** GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, Config, and Firewall Manager each enable separately, and their findings only appear once each is on in the same region. A Security Hub with no sources enabled shows standards findings only.
3. **Which standards are enabled, and where.** FSBP is the usual AWS-native baseline; CIS is the industry baseline; PCI DSS and NIST are compliance-driven. Standards enable per account and per region, so a standard enabled only in one region leaves the rest unassessed.
4. **The task class.** Enablement and topology, finding management and workflow, standards and controls tuning, automation, or a read-only posture audit. The depth lives in different references.
5. **Read-only versus change.** An audit uses read-only Security Hub API scope and never suppresses a finding, disables a control, or changes a workflow status. A configuration change (enabling a standard, disabling a control, creating an automation rule) needs a change record and a rollback path.

## When to use

- Enabling Security Hub and standing up the topology: single account or Organizations delegated admin, auto-enable for new accounts, central configuration, and a cross-region finding aggregator.
- Enabling and tuning security standards: choosing FSBP, CIS, PCI DSS, or NIST, disabling individual controls that do not apply (with a recorded reason), and reading the security score.
- Enabling finding sources: GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, Config, Firewall Manager, and accepting findings from partner products.
- Managing findings: filtering, the workflow status lifecycle (NEW, NOTIFIED, SUPPRESSED, RESOLVED) versus the provider-controlled RecordState, insights, and automation rules.
- Building automated response: EventBridge rules on new or updated findings, targeting Lambda, SNS, SQS, Step Functions, or Systems Manager Automation, and custom actions for manual console-triggered automation.
- Importing custom findings in ASFF via BatchImportFindings.
- Automating read-only audit and reporting through the Security Hub API (GetFindings, DescribeStandards, GetInsights) with an IAM least-privilege read-only role.
- Running a read-only posture audit: standards drift, controls disabled without justification, delegated admin and auto-enable gaps, missing cross-region aggregation, findings stuck in NEW, and blanket suppression rules.

## When not to use

- **Vendor-neutral CNAPP and CSPM taxonomy and platform selection** (what CSPM, CWPP, CIEM, and CNAPP mean, comparing platforms, choosing between AWS-native and a third-party CNAPP): use `cloud-security-posture`. Security Hub is the AWS-native CSPM and findings-aggregation service; the umbrella owns the taxonomy, this skill owns Security Hub operations.
- **Vulnerability programme design** (CVSS and EPSS scoring, remediation SLAs, exception handling, the scanning-programme lifecycle): use `vulnerability-management`. Security Hub aggregates Amazon Inspector vulnerability findings but does not own the vulnerability-management programme.
- **General AWS service selection and configuration** (choosing and configuring AWS services beyond Security Hub itself): use `aws-cloud-ops`.
- **VPC and network exposure auditing** (security groups, NACLs, route tables, internet exposure of network paths): use `aws-networking-audit`. Security Hub surfaces some network-configuration findings, but the network-audit depth lives there.
- **GRC frameworks and compliance evidence** (mapping a benchmark to a control framework, gathering and presenting audit evidence): use `compliance-benchmark-audit`. Security Hub's standards produce evidence that is consumed there.
- **External outside-in attack surface** (internet-facing asset discovery from the attacker's perspective): use `attack-surface-management`.
- **Storing an IAM access key, role secret, or partner API token**: use `secrets-hygiene`. Never inline a live credential in a saved API call, a runbook, or a config file.

This skill **owns AWS Security Hub operations**. Route the CNAPP taxonomy, vulnerability-programme design, general AWS service work, network-exposure audit, GRC evidence, and external attack surface out per the list above; keep everything Security Hub here.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / model | The aggregation and normalisation model, finding sources and what each contributes, the ASFF schema, cross-account and cross-region aggregation, the delegated administrator and Organizations model, central configuration, Security Hub CSPM | `references/architecture.md` |
| Operations / audit | Enabling and tuning standards (CIS, FSBP, PCI DSS, NIST), controls and control status, the workflow-status lifecycle, insights, automation rules, EventBridge automated response, and the read-only audit lens with a threshold table and decision trees | `references/operations.md` |
| API / automation | The Security Hub API for a read-only posture (GetFindings, DescribeStandards, GetInsights), the ASFF schema for BatchImportFindings, EventBridge event patterns, the IAM least-privilege read-only policy, auth with placeholder values, throttling, pagination, and secret-store discipline | `references/api-and-automation.md` |

## Core model (condensed)

**Security Hub aggregates and normalises; it does not detect.** GuardDuty detects threats, Amazon Inspector finds vulnerabilities, Macie classifies data, IAM Access Analyzer finds external access, Config evaluates rules. Security Hub is the single place all of their findings land, normalised into ASFF, alongside its own standards-check findings. Treating Security Hub as a detection engine is the common category error; its value is the consolidated, normalised view and the compliance posture.

**ASFF is the one format.** Every finding, from an AWS service or a partner product or a custom importer, is the AWS Security Finding Format. Two status fields are easy to confuse and both matter: `Workflow.Status` (NEW, NOTIFIED, SUPPRESSED, RESOLVED) is customer-controlled and tracks your triage; `RecordState` (ACTIVE, ARCHIVED) is provider-controlled and tracks whether the underlying condition is still detected. A finding that is ACTIVE but marked RESOLVED means someone closed it while the condition still exists, which is itself a finding.

**Standards are continuous controls with a score.** Enabling a standard (FSBP, CIS, PCI DSS, NIST) turns on a set of controls, each evaluated continuously against your resources. The security score is the percentage of controls passing. FSBP is the broadest AWS-native baseline; CIS is the widely-recognised industry baseline. Disable a control only when it genuinely does not apply, and always record the reason, because a silently disabled control is an invisible gap.

**The topology is delegated admin plus aggregation region.** In an Organizations deployment, one account is the Security Hub delegated administrator (usually the security or audit account) and sees every member account's findings. Auto-enable brings new accounts in automatically. Each region has its own Security Hub, so a finding aggregation region must be configured to consolidate all linked regions into one view. Central configuration lets the delegated admin push standards and control settings across the organisation from one place.

**Automation is EventBridge plus automation rules.** New and updated findings emit EventBridge events; rules match on finding criteria and target Lambda, SNS, SQS, Step Functions, or Systems Manager Automation for notification or remediation. Automation rules (the newer mechanism) update ASFF fields on ingestion, which is how suppression and enrichment are done at scale. Custom actions let an operator trigger the same automation manually from the console.

**Completeness and least privilege are the through-line.** A single-account deployment when the estate is an organisation, no cross-region aggregation so each region is checked separately, standards enabled in one region only, controls disabled with no recorded reason, findings piling up in NEW because nobody triages, a blanket suppression rule that hides more than intended, and an audit role that can write: these are the recurring findings. Deploy org-wide with a delegated admin, aggregate the regions, enable the baseline standards everywhere, record every disabled control, keep the workflow moving, scope suppression tightly, and keep the audit read-only.

## Reference router

| Need | Load |
|---|---|
| The aggregation and normalisation model, the finding sources (GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, Config, Firewall Manager, partner products) and what each contributes, the ASFF schema and its key fields, cross-account and cross-region aggregation, the delegated administrator and Organizations model, central configuration, and Security Hub CSPM | `references/architecture.md` |
| Enabling and tuning standards (CIS, FSBP, PCI DSS, NIST), controls and control status, the finding workflow-status lifecycle, insights, automation rules, EventBridge-driven automated response and remediation, and the read-only audit lens with a threshold table and remediation decision trees | `references/operations.md` |
| The Security Hub API for a read-only posture (GetFindings, DescribeStandards, GetInsights), the ASFF schema for BatchImportFindings, EventBridge event patterns, the IAM least-privilege read-only policy, auth with placeholder values only, throttling and backoff, pagination, and secret-store discipline | `references/api-and-automation.md` |

## Cross-references

- `cloud-security-posture`: the vendor-neutral CSPM and CNAPP umbrella; consult for the taxonomy and for choosing between AWS-native Security Hub and a third-party CNAPP.
- `vulnerability-management`: the vulnerability-programme design, CVSS and EPSS scoring, and remediation SLAs; Security Hub aggregates Amazon Inspector findings but does not own the programme.
- `aws-cloud-ops`: general AWS service selection and configuration beyond Security Hub itself.
- `aws-networking-audit`: VPC, security-group, and network-exposure auditing; Security Hub surfaces some network-configuration findings, the audit depth lives there.
- `compliance-benchmark-audit`: GRC frameworks and compliance evidence; Security Hub's standards produce the evidence consumed there.
- `attack-surface-management`: external outside-in attack surface discovery, the attacker's perspective on internet-facing assets.
- `secrets-hygiene`: the IAM access key, role secret, and partner API token live in the secret store, never inline in a saved API call or runbook.

## Red flags

- Treating Security Hub as a detection or response engine: it aggregates and assesses posture, the detection depth is in GuardDuty, Amazon Inspector, and Macie.
- A single-account deployment when the estate is an AWS Organizations: no delegated admin, so member-account findings are invisible from the security account.
- Auto-enable off, so new member accounts join the organisation with no Security Hub coverage until someone remembers to enable it.
- No finding aggregation region, so each region must be checked in its own console and there is no consolidated view.
- A standard enabled in one region only, leaving every other region unassessed against that baseline.
- Controls disabled with no recorded disabled-reason: an invisible gap that nobody can later justify or reverse with confidence.
- A finding marked RESOLVED while its RecordState is still ACTIVE: the condition still exists, someone closed the workflow prematurely.
- Findings piling up in NEW because there is no triage workflow: the aggregation is working but nobody is acting on it.
- A blanket automation or suppression rule with loose criteria that hides more findings than intended, so real issues are silently suppressed.
- An audit or reporting IAM role with write permissions (BatchUpdateFindings, UpdateStandardsControl, CreateAutomationRule) when it was meant to be read-only.
- Pasting an IAM access key, a role secret, or a partner API token into a saved API URL, a runbook, or a committed file instead of the secret store.

## Bottom line

Security Hub is the AWS-native aggregation and CSPM layer: it normalises findings from GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, Config, Firewall Manager, and partner products into ASFF, and runs continuous standards checks (CIS, FSBP, PCI DSS, NIST) with a security score. Deploy it org-wide with a delegated administrator and auto-enable, configure a finding aggregation region so every region rolls up into one view, enable the baseline standards everywhere and record every disabled control, keep findings moving through the workflow rather than piling up in NEW, drive response through EventBridge and tightly-scoped automation rules, and keep any audit role read-only. Route the CNAPP taxonomy to `cloud-security-posture`, vulnerability-programme design to `vulnerability-management`, general AWS work to `aws-cloud-ops`, network-exposure audit to `aws-networking-audit`, GRC evidence to `compliance-benchmark-audit`, external attack surface to `attack-surface-management`, and keep every credential in the secret store.

## Reference files

- `references/architecture.md`: the aggregation and normalisation model, the finding sources (GuardDuty, Amazon Inspector, Macie, IAM Access Analyzer, AWS Config, Firewall Manager, and partner integrations) with what each contributes, the AWS Security Finding Format (ASFF) with its key fields and the Workflow-versus-RecordState distinction, cross-account and cross-region aggregation with the multi-account finding flow, the delegated administrator and AWS Organizations model, central configuration, and Security Hub CSPM.
- `references/operations.md`: enabling and tuning security standards (CIS AWS Foundations Benchmark, AWS Foundational Security Best Practices, PCI DSS, NIST SP 800-53), controls and control status and the security score, the finding workflow-status lifecycle (NEW, NOTIFIED, SUPPRESSED, RESOLVED), insights, automation rules, EventBridge-driven automated response and remediation, and the read-only audit lens with a threshold table and remediation decision trees.
- `references/api-and-automation.md`: the Security Hub API for a read-only audit posture (GetFindings, DescribeStandards, DescribeStandardsControls, GetInsights), the ASFF schema for BatchImportFindings, EventBridge event patterns for automated response, the IAM least-privilege read-only policy, auth with placeholder values only, throttling and backoff, pagination, and the secret-store discipline for API credentials.
