# Microsoft Defender for Cloud operations and audit

This is the operational depth: how to enable and scope the plans, how to work the regulatory compliance dashboard, how to raise secure score, how to run the workload protection controls (JIT, adaptive application controls, FIM), how to wire DevOps security, and the read-only audit lens with thresholds and decision trees. The management surface is Defender for Cloud in the Azure portal, plus the Defender XDR portal for cross-signal correlation and ARM or Azure Resource Graph for scripted review.

## Enabling and scoping Defender plans

### Where to enable

- Azure portal: Defender for Cloud, Environment settings, select the scope (management group or subscription), Defender plans, then toggle the plans on and configure each plan's settings (vulnerability-assessment provider, monitoring coverage, agentless scanning).
- Enable at **management-group scope** wherever possible so new subscriptions inherit the plans. Per-subscription enablement drifts: a subscription created next quarter lands unprotected and nobody notices until an incident.
- Enabling a plan bills immediately, so a plan change is a change with a cost, not a read-only action.

### Enable through Azure Policy at enterprise scale

The `Microsoft.Security/pricings` resource is the policy-managed enablement surface. An assignment sets the plan tier and, where relevant, the sub-plan:

```json
{
  "type": "Microsoft.Security/pricings",
  "name": "VirtualMachines",
  "properties": {
    "pricingTier": "Standard",
    "subPlan": "P2"
  }
}
```

Enforcing this through a management-group policy keeps plan enablement consistent across every subscription and surfaces drift as a policy non-compliance rather than a silent gap.

### Plan-selection guidance

- **Servers**: start at P1 for the MDE integration and JIT; upgrade to P2 for the full CWPP (vulnerability assessment, FIM, adaptive controls, free Log Analytics ingestion).
- **Enable the plans the estate actually runs**. A subscription with no containers does not need Defender for Containers; a subscription with Blob storage holding customer data does need Defender for Storage with malware scanning.
- **Defender CSPM is separate**. Turn it on for the security graph, attack paths, and agentless scanning even where the per-resource Defender plans are selective. Many tenants enable a Defender plan but forget Defender CSPM, and so never get attack-path analysis.

## Regulatory compliance dashboard

### Assigning a standard

Azure portal: Defender for Cloud, Regulatory compliance, Manage compliance policies, select the subscription scope, Add a standard. The default is the Microsoft Cloud Security Benchmark (MCSB); assign the framework the tenant is actually audited against. Adding a standard creates a policy-initiative assignment at the chosen scope, and the assessment appears in the dashboard within roughly 24 hours.

Built-in standards include CIS Microsoft Azure Foundations Benchmark, NIST SP 800-53 R5, PCI DSS v4.0, ISO 27001:2013, SOC 2 Type 2, HIPAA/HITRUST, FedRAMP Moderate and High, UK OFFICIAL and UK NHS, Australia ISM, and more.

### Reading compliance

- **% controls passing** per framework, with per-control drill-down showing which resources fail.
- **Control status logic**: a control passes only when every policy mapped to it is compliant for every in-scope resource. Partial compliance (some resources pass, some fail) marks the control failing. Resources with an exemption are excluded from assessment.
- **Evidence export**: download the compliance report as PDF or CSV for a point-in-time audit snapshot, and use continuous export to push compliance-state changes to a Log Analytics workspace or Event Hub for retention and trend reporting.

### Custom frameworks

Build a custom standard by creating a custom Azure Policy initiative, mapping its policies to controls through policy metadata, and assigning it to the scope. It then appears in the regulatory compliance dashboard alongside the built-in standards.

## Secure-score improvement workflow

1. Defender for Cloud, Recommendations, sort by **potential score increase** descending.
2. Focus on the controls with the highest potential increase and the fewest remaining unhealthy resources; the scoring is binary per control, so finishing a nearly-complete high-value control beats chipping at a large low-value one.
3. Within a control, use **Quick Fix** (one-click remediation) where the recommendation supports it. Quick Fix mutates the resource, so it is a change, not an audit action.
4. For bulk remediation, use an **Azure Policy remediation task** (a `deployIfNotExists` policy) to bring many resources into compliance at once.
5. For manual remediations, **assign an owner** through a governance rule so the work is tracked with a due date rather than left to drift.

## Workload protection controls

### JIT VM access

Locks management ports down by default and opens them time-limited on approved request.

```
Defender for Cloud > Workload protections > Just-in-time VM access
  > Add VMs > select VM > configure ports (RDP 3389, SSH 22, WinRM 5985)
```

Without JIT, port 22 or 3389 sits open to `0.0.0.0/0` in the NSG. With JIT, the port is blocked by default; on request DfC adds a temporary NSG rule scoped to a specific source IP for a chosen window (one to eight hours), then removes it on expiry. Users request access through the DfC console, the Azure portal, PowerShell, or the API, and every request is logged to the Azure activity log for audit.

### Adaptive application controls

- DfC machine learning profiles the processes that normally run across a VM group and recommends an allowlist policy per group.
- Once applied, an unknown process raises an alert in **audit mode** or is blocked in **enforce mode**.
- Recommendations refresh as the process set changes. The common failure is leaving a policy in audit mode indefinitely: anomalies are logged but never blocked.

### File integrity monitoring (FIM)

- Tracks changes to critical OS files, registry keys, and configured custom paths (Windows registry hives and system directories; Linux `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, and the binary and SSH-key paths).
- Changes flow to Log Analytics with alerts on suspicious edits. FIM is a Defender for Servers P2 capability; a tenant paying for P2 but never configuring FIM is paying for an unused control.

## DevOps security

Integrates source-code platforms for shift-left security.

- **Supported platforms**: GitHub (Actions plus direct repository scanning), Azure DevOps (Pipelines), and GitLab (CI).
- **Capabilities**: infrastructure-as-code scanning (Terraform, CloudFormation, ARM, Bicep, Helm) in pull requests, dependency scanning for vulnerable packages, secret detection in source, and container-image scanning in the pipeline.
- **Pull-request annotations**: findings surface as PR comments with configurable fail-or-warn thresholds, and SARIF output feeds the platform's native code-scanning view.

Connect the platform under Defender for Cloud, Environment settings, Add environment, then the GitHub, Azure DevOps, or GitLab connector.

## Recommendations and governance rules

### Recommendation structure

Each recommendation carries a title, a severity (Critical, High, Medium, Low), the affected resources, and remediation steps. Options per recommendation: Quick Fix (one-click remediation where supported), Exempt (suppress for a specific resource with a justification), and governance assignment (assign an owner with a due date). Each recommendation is backed by an Azure Policy initiative, so it can also be enforced (deny) or remediated (`deployIfNotExists`) through policy.

### Governance rules

Governance rules (a Defender CSPM capability) automate recommendation ownership and SLA tracking.

```
Defender for Cloud > Environment settings > Governance rules > Add rule

Rule: Critical recommendations on production servers
  - condition: severity = Critical AND tag Environment = Production
  - owner: auto-assign by the resource Owner tag
  - due date: 7 days
  - notification: daily reminder email
```

The governance report tracks the share of recommendations with an assigned owner, SLA compliance (the share fixed within the due date), and the overdue-escalation list. Governance rules absent or ownerless is a headline audit finding: recommendations with no owner and no SLA never get remediated and secure score stalls.

## Workload protection alerts

Each Defender plan generates runtime alerts for its resource family: SQL injection and anomalous access (Databases), malware upload and anonymous access (Storage), web-shell and command-injection (App Service), crypto-mining and container-escape (Containers), DNS tunnelling (DNS), and suspicious Key Vault access. Alerts surface in Defender for Cloud, Security alerts, and correlate in the Defender XDR portal. Continuous export or the native Sentinel connector streams them to the SIEM; route that correlation to `siem-soar-investigation`.

## Read-only audit lens

A DfC posture audit is read-only: read plan state, recommendations, secure score, compliance, and the graph through ARM, the Graph Security API, and Azure Resource Graph, and never enable a plan, apply a Quick Fix, activate JIT, or change a policy assignment. Start by confirming which layers are on, then walk the thresholds below.

### Audit threshold table

| Control | Healthy | Finding | Why it matters |
|---|---|---|---|
| Defender plans | The plans the estate runs are on at management-group scope | Foundational-only, or plans per-subscription | Foundational-only has no threat detection; per-subscription drifts |
| Defender CSPM | On | Off | No cloud security graph, so no attack paths and no explorer |
| Agentless scanning | On under Defender CSPM | Disabled | VMs and container images go unscanned when coverage was free of an agent |
| Secure score trajectory | Rising, controls owned | Stalled, no owners | Recommendations never remediated |
| JIT VM access | Configured on P2 servers | Management ports open, JIT unused | Paid capability idle, attack surface open |
| File integrity monitoring | Configured on P2 servers | Unconfigured | Critical-file tampering undetected |
| Adaptive application controls | Enforce mode where stable | Stuck in audit mode | Anomalous processes logged but never blocked |
| Regulatory compliance | The audited standard assigned | Only default MCSB | The framework you are actually audited against is absent |
| Governance rules | Owners and SLAs set | Absent or ownerless | Remediation never happens, score stalls |
| Multi-cloud coverage | Arc for CWPP depth, connectors for CSPM | Connector mistaken for full CWPP | Runtime protection assumed but absent |
| Continuous export / Sentinel | Alerts reach the SIEM | No export | Alerts never correlated or retained |

### Remediation decision trees

**Coverage finding**

```
Any Defender plan enabled?
  no  -> foundational-only: enable the plans the estate runs (Servers, and the data/storage/container plans in use)
  yes -> enabled at management-group scope?
           no  -> move enablement to the management group so new subscriptions inherit it
Defender CSPM on?
  no  -> enable it: without the graph there are no attack paths and no cloud security explorer
Agentless scanning on under Defender CSPM?
  no  -> enable it: VM and container-image coverage at no agent cost
```

**Servers P2 finding**

```
Defender for Servers at P2?
  JIT VM access configured?
    no -> configure JIT on the management ports (22, 3389, 5985); ports should be blocked by default
  File integrity monitoring configured?
    no -> enable FIM on the critical OS-file and registry paths
  Adaptive application controls?
    audit mode only -> move stable groups to enforce mode
    absent          -> enable and let the ML build the allowlist, then enforce
```

**Compliance and governance finding**

```
Regulatory compliance dashboard shows only MCSB?
  -> assign the standard the tenant is audited against (CIS, NIST, PCI DSS, ISO 27001, and so on)
Recommendations without owners?
  -> add governance rules: auto-assign by resource Owner tag, set a due date and reminder
Secure score stalled?
  -> sort recommendations by potential score increase; finish the high-value controls nearest completion first
```

**Multi-cloud finding**

```
AWS or GCP resources present?
  native connector only?
    -> CSPM visibility only; if runtime CWPP is expected, Arc-enable the workloads and enable Defender for Servers/Containers
  Arc-enabled?
    -> confirm Defender for Servers/Containers is on for the Arc scope so the agent depth is actually applied
```

## Verification before claiming done

Per `completion-gate`, "configured DfC" is not a finish line. Before the chunk closes:

- [ ] The Defender plans the estate runs are enabled at management-group scope; Defender CSPM is on.
- [ ] Agentless scanning is enabled under Defender CSPM.
- [ ] Secure score is rising and every open recommendation has a governance owner and SLA.
- [ ] On P2 servers, JIT VM access and file integrity monitoring are configured; adaptive application controls are in enforce mode where stable.
- [ ] The regulatory compliance standard the tenant is audited against is assigned, not just the default MCSB.
- [ ] Non-Azure workloads are onboarded correctly: Arc where runtime CWPP depth is needed, native connectors where CSPM visibility is enough, and the connector-versus-Arc distinction is understood.
- [ ] DfC alerts reach the SIEM through the native Sentinel connector or continuous export.
- [ ] DevOps security connectors are wired for the source-code platforms in use, with pull-request annotations on.
</content>
