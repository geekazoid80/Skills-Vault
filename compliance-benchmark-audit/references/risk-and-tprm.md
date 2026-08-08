# Risk management, third-party risk, and policy

Deep reference for the risk side of GRC: how to score risk, how to decide what to do about it, how to assess the vendors who inherit your risk, and how the policy hierarchy that governs it all is structured. Controls exist to treat risk; this is where you decide which risks justify which controls.

---

## Risk methodology

The qualitative workhorse is **Risk = Likelihood x Impact**, scored on a 5x5 matrix for fast triage:

```
Likelihood:
  1 Rare        <5% in next 12 months
  2 Unlikely    5-20%
  3 Possible    20-50%
  4 Likely      50-75%
  5 Almost      >75%

Impact:
  1 Negligible    minimal operational or financial impact (<$10K)
  2 Minor         limited, resolved without escalation (<$100K)
  3 Moderate      significant disruption, manageable (<$1M)
  4 Major         significant financial or reputational impact (<$10M)
  5 Catastrophic  existential or regulatory/legal consequences (>$10M)

Risk score (Likelihood x Impact):
  1-4    Low       accept or monitor
  5-9    Medium    mitigate, or accept with compensating controls
  10-19  High      mitigate; requires a treatment plan
  20-25  Critical  immediate remediation; escalate to executive
```

Calibrate the impact bands to the organisation's size; the bands above suit a mid-market company. The point of the matrix is consistent triage, not false precision: it sorts the register so attention and budget go to the top-right quadrant first.

---

## Risk treatment options

Every assessed risk gets one of four treatments, recorded with an owner:

**Mitigate.** Add controls to reduce likelihood or impact. Lower likelihood with MFA, patching, training; lower impact with backups, an incident response plan, cyber insurance. The default for technical risk.

**Accept.** Consciously choose not to address it. Appropriate when the cost of mitigation exceeds the expected loss and residual risk is low. Must be formally approved by the risk owner, documented, time-bounded, and reassessed (typically annually). An accepted risk with no expiry becomes a forgotten risk.

**Transfer.** Shift the financial consequence to a third party: cyber insurance for breach and litigation costs, or contractual transfer of liability to a vendor. Transfer shares the financial blow; it does not remove the risk.

**Avoid.** Eliminate the activity or asset that creates the risk: retire a vulnerable system, decline a market. The most complete option and often the least feasible for core functions.

---

## Quantitative risk: FAIR

Factor Analysis of Information Risk (FAIR) is the standard for putting a money figure on risk when a control-investment decision needs one:

```
Risk = Loss Event Frequency (LEF) x Loss Magnitude (LM)

LEF = Threat Event Frequency x Vulnerability
  Threat Event Frequency: how often a threat actor attempts this
    (from threat intel, industry incident rates)
  Vulnerability: probability an attempt succeeds
    (control effectiveness, patch level, configuration state)

LM = Primary Loss + Secondary Loss
  Primary (direct): productivity loss, response costs, replacement costs
  Secondary (downstream): regulatory fines, legal liability, competitive
    loss, reputational damage (customer churn x lifetime value)
```

Worked example, ransomware on production:

```
Threat frequency: ~3 attempts/year (phishing + RDP brute force)
Vulnerability:    35% (MFA deployed, but EDR gap on some hosts)
LEF:              3 x 0.35 = ~1 event/year

Primary loss:   $500K (IR $150K + 3 days downtime x $100K + recovery $50K)
Secondary loss: $300K (notification, potential fine, customer notification)
Loss magnitude: $800K
Annualised Loss Expectancy (ALE): 1 x $800K = $800K/year

Control decision: deploy EDR on the remaining hosts at $50K/year
  Vulnerability drops 35% -> 10%
  New ALE: 1 x 0.10 x $800K = $80K/year
  Return on control: ($800K - $80K) - $50K = $670K/year
  Clear economic case.
```

FAIR turns "this feels risky" into a defensible spend decision, which is what a board and a budget owner need.

---

## GRC maturity model

| Level | Characteristics | Typical tooling |
|---|---|---|
| 1 Ad hoc | No formal programme; compliance is reactive | Spreadsheets, email |
| 2 Developing | Basic policies; manual evidence; annual audits | Shared drive, GRC spreadsheets |
| 3 Defined | Formal framework; documented controls; structured but manual | Basic GRC tool or project management |
| 4 Managed | Automated evidence collection; continuous monitoring; integrated TPRM | A GRC automation platform |
| 5 Optimised | Real-time risk dashboard; predictive analytics; near-zero-friction compliance | Enterprise GRC plus SIEM integration |

The common journey is Level 2 to Level 4:

```
1. Select a framework (SOC 2 Type II is the usual first for SaaS).
2. Deploy a GRC automation platform.
3. Connect cloud infrastructure integrations (AWS, Azure, GCP).
4. Connect identity and endpoint integrations (Okta/Entra, Intune/Jamf).
5. Assign control owners for the manual controls.
6. Run the first audit after 6 to 12 months of evidence.
7. Address findings; mature continuous monitoring.
8. Add frameworks as the business requires, reusing the mapped control set.
```

Do not skip step 5: automation collects the technical evidence, but manual controls (board minutes, vendor reviews, training completion) still need a named owner.

---

## Third-party risk management (TPRM)

A vendor's weakness becomes your risk. TPRM tiers vendors by the risk they carry and matches assessment depth to the tier:

```
Critical (Tier 1): processes the most sensitive data (PII, PHI, financial), or
  a material operational dependency. Full SIG questionnaire + SOC 2 review +
  annual call/onsite. Continuous security-rating monitoring.

High (Tier 2): accesses corporate network/systems or business-sensitive data.
  Abbreviated questionnaire + SOC 2 review. Annual reassessment + rating alerts.

Medium (Tier 3): limited data access, no sensitive data, non-critical.
  Self-attestation questionnaire. Annual self-assessment renewal.

Low (Tier 4): no data access, commodity service (office supplies, maintenance).
  Attestation to security policy acceptance. No ongoing monitoring.
```

**Security questionnaire frameworks** save everyone from bespoke spreadsheets:

- **SIG (Standardised Information Gathering)**, maintained by Shared Assessments. SIG Core is ~270 questions across 20 domains; SIG Lite is ~70 for a faster review. The enterprise, financial-services, and healthcare standard.
- **CSA CAIQ (Consensus Assessment Initiative Questionnaire)**, focused on cloud providers and mapped to the CSA Cloud Controls Matrix; answers can be self-published to the CSA STAR registry.
- **Custom questionnaires** only when a specific risk is not covered; vendors flooded with bespoke questionnaires suffer fatigue and answer worse, so prefer a standard one.

**Continuous monitoring** layers a live signal over the point-in-time questionnaire:

```
Security rating services (SecurityScorecard, BitSight): passive external scan of
  the vendor's internet presence, scored 0-100 or A-F on patch frequency,
  TLS configuration, DNS and email security (SPF/DKIM/DMARC), reputation, and
  web app security. Alert on a drop of more than ~10 points. A signal, not a
  replacement for assessment.
Dark-web monitoring: vendor breach indicators and credential exposure, to prompt
  an accelerated reassessment.
SOC 2 bridge letters: when the vendor's latest SOC 2 does not cover the current
  period, a signed letter attesting controls are unchanged bridges a gap of
  typically up to ~6 months.
```

---

## Policy management

### Policy hierarchy

```
Tier 1 Executive/Board policies: Information Security Policy, Acceptable Use,
  Risk Management Policy. Reviewed annually; approved by the board or exec.
Tier 2 Domain policies (CISO-owned): Access Control, Encryption, Incident
  Response, Change Management, Vendor Management, Business Continuity.
  Reviewed annually; approved by the CISO.
Tier 3 Standards and procedures (technical team): password standards, network
  security standards, secure coding standards, vuln-management procedures.
  Reviewed annually or as technology changes; approved by the security lead.
Tier 4 Guidelines and baselines: cloud/endpoint/application security baselines.
  Reviewed as technology changes; technical owner.
```

### Policy attestation

Annual employee policy attestation is an explicit requirement (SOC 2 CC2.2, ISO 27001:2022 6.3 and 7.3):

```
Workflow: campaign sent to all employees -> employee reads and acknowledges ->
  completion tracked with name, date/time, and policy version.

Thresholds: target 100%; auditable at 95%+ with a documented escalation
  process (two reminders -> manager notification -> HR escalation).

Evidence: a completion report (employee, date, policy version) exported as
  CSV or PDF; never an undated screenshot.
```
