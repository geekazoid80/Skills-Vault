# Compliance automation, the audit lifecycle, and evidence

Deep reference for collecting evidence continuously and surviving an external audit. Automation turns the annual evidence scramble into a continuous signal; the audit lifecycle is the process that signal feeds; evidence quality is what an auditor actually tests. Load this when designing integrations, planning an audit, or deciding whether a piece of evidence will pass.

---

## Compliance automation architecture

A GRC platform evaluates the live state of a system against a control requirement and records the result as an evidence artefact. Three integration patterns:

**Pull (most common).** The platform calls the provider's API on a schedule, reads the current configuration, evaluates Pass or Fail against the control, and updates the evidence artefact and control status.

```
GRC platform --API call--> cloud provider / SaaS
                           returns current configuration state
                           platform evaluates: PASS or FAIL
                           writes evidence artefact + control status
```

**Push (webhook / event-driven).** The provider notifies the platform on a change; the platform evaluates immediately and alerts on a failure.

```
cloud provider --webhook--> GRC platform
  event: "S3 bucket ACL changed to public"
  platform: evaluate -> control FAIL -> alert -> notify owner
```

**Agent (endpoint / on-prem).** An agent on the host reports state (encryption, patch level, MDM enrolment, AV status) that no central API exposes.

```
agent on endpoint/server --> GRC platform
  reports encryption status, patch level, MDM enrolment
  platform: aggregate -> compute % compliance -> flag gaps
```

The non-negotiable across all three: the platform connects with a **least-privilege, read-only** identity. A compliance tool never needs write access to the system it audits, and granting it write access turns the auditor into an attack path. Keep those credentials in the secret store (see `secrets-hygiene`).

---

## Common integration categories

**Cloud infrastructure:**

```
AWS:   poll IAM, Config, GuardDuty, Security Hub, CloudTrail, S3, EC2.
       Checks: S3 encryption, root MFA, Config rules enabled, CloudTrail on.
       Auth: IAM role with ReadOnlyAccess (no write to the GRC tool).
Azure: poll Microsoft Entra ID, Defender for Cloud, Policy, Monitor.
       Checks: MFA status, Defender coverage, Policy compliance, RBAC.
       Auth: service principal with Reader + specific API permissions.
GCP:   poll IAM, Security Command Center, Cloud Asset Inventory, Logging.
       Checks: service-account key rotation, org policy constraints, logging.
       Auth: service account with Viewer role.
```

**Identity:**

```
Okta:           MFA enrolment (per user and overall %), inactive accounts,
                admin MFA. Evidence: MFA enrolment report. API: read token.
Microsoft Entra ID: MFA status, conditional access policies, privileged role
                assignments. Evidence: sign-in logs, CA policy export.
                API: Microsoft Graph (User.Read.All, Policy.Read.All).
```

**Endpoint:**

```
Jamf:        FileVault encryption, MDM enrolment, macOS version, app inventory.
Intune:      BitLocker encryption, MDM enrolment, compliance policy, patch level.
CrowdStrike: agent deployment coverage, sensor version, unprotected-endpoint list.
```

These map cleanly onto framework controls: cloud encryption and logging answer SOC 2 CC6/CC7 and PCI Req 3/10; identity MFA answers CC6.1, ISO A.8.5, and PCI Req 8; endpoint encryption answers the data-protection controls. One integration, evidence for many frameworks (see the crosswalk in `frameworks.md`).

---

## The audit lifecycle

```
1. Planning. Define scope (systems, period, frameworks). Select the auditor
   (a CPA firm for SOC 2, an accredited certification body for ISO 27001).
   Review the engagement letter. Run an internal readiness/gap assessment
   before fieldwork starts, while gaps are still cheap to fix.

2. Evidence collection (ongoing or pre-audit). Assign evidence to control
   owners, collect and review artefacts for completeness, and confirm the
   evidence period matches the audit period.

3. Auditor fieldwork. The auditor issues information requests (RFIs); you
   provide evidence via the platform or a secure portal. Walkthroughs:
   auditors interview control owners. Testing: auditors select samples; you
   provide the population and the sampled items.

4. Review and response. The auditor issues preliminary findings (potential
   exceptions). Respond to each: accept, or provide clarifying evidence.
   Remediate genuine exceptions before the report is finalised where possible.

5. Report issuance. Management-letter review period, then the final signed
   report. A SOC 2 Type II report is shared with customers under NDA via a
   trust centre; ISO 27001 yields a certificate from the certification body.

6. Continuous monitoring (post-audit). Keep collecting evidence, close prior
   exceptions, and prepare for the next cycle. This is where automation pays
   for itself: there is no "next scramble" if the evidence never stopped.
```

---

## Evidence quality standards

Auditors test evidence, not intentions. Good evidence is:

```
Complete:     covers the full audit period, not a single point in time.
Accurate:     reflects the actual control state; no cherry-picking.
Timely:       generated while the control was operating, not retroactively.
Traceable:    shows clearly what was tested, by whom, and when.
Authoritative: comes from the system of record, not a hand-built spreadsheet.
```

Evidence red flags an auditor will reject:

```
- Screenshots with no timestamp.
- Spreadsheets in place of system-generated reports.
- Evidence dated outside the audit period.
- Access reviews with no reviewer sign-off.
- Training completions with no completion timestamp.
- Policies with no approval signature and date.
```

The recurring theme is that defensible evidence is timestamped (in UTC; see `utc-timestamps`), system-generated, and period-complete. Designing the evidence pipeline to produce that by default, rather than reconstructing it before each audit, is the difference between a Level 4 programme and a Level 2 one.
