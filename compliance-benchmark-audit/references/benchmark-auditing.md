# Technical benchmark and control-family auditing

Deep reference for measuring a system against a technical baseline. Two complementary methods: **CIS Benchmark** assessment (a prescriptive configuration baseline for a specific platform) and **NIST SP 800-53** control-family assessment (a control catalogue mapped to an impact baseline). Both produce a score, a gap list, and a prioritised remediation plan that becomes evidence for the frameworks in `frameworks.md`.

This reference owns the vendor-neutral *method*. For the exact read-only commands on a specific network firewall, use the firewall-audit skills (`cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`); for AWS VPC and wireless, `aws-networking-audit` and `wireless-security-audit`. CIS Benchmarks and the underlying NIST publications are obtained from the source: CIS publishes benchmarks per platform and version, and NIST SP 800-53 and the CSF are free from csrc.nist.gov. Reference control IDs for traceability; do not reproduce copyrighted benchmark text.

---

## CIS Benchmark assessment

A CIS Benchmark is a consensus-developed, prescriptive baseline ("set this exact value") published per platform and version: operating systems, cloud providers, Kubernetes, databases, browsers, mobile, and network devices. Each benchmark offers two profiles:

- **Level 1:** essential security controls, broadly applicable, minimal functionality impact.
- **Level 2:** defence-in-depth controls for high-security environments, may reduce functionality.

### Assessment flow

```
1. Identify and select. Record the platform, OS/version, and role. Choose the
   exact benchmark ID and version (e.g. "CIS Ubuntu 22.04 Benchmark v2.0.0").
   If no benchmark matches the exact version, use the nearest lower one and
   document the version gap. Choose the profile level (L1, or L1+L2).

2. Audit by control domain. Walk the benchmark's sections, reading current
   configuration read-only and recording each control as Pass, Fail, or Not
   Applicable. For network devices, CIS structures controls by the Management
   Plane (admin access, AAA, logging, SSH/SNMP, banners), Control Plane
   (routing-protocol authentication, control-plane policing, ARP/DHCP
   protection), and Data Plane (ACLs, uRPF anti-spoofing, storm control,
   encryption). For OS / cloud / Kubernetes benchmarks the domains differ but
   the Pass/Fail/N-A discipline is identical.

3. Score. Compliance % = Pass / (Pass + Fail) x 100, excluding N/A from the
   denominator. Score per domain and overall.

4. Gap analysis. A Level 1 failure in the most privileged domain (management
   access) is a priority finding: if management access is compromised, every
   other control is bypassable.

5. Prioritise remediation. Rank by control level and operational impact (see
   the decision tree below), and group by effort: quick wins (a config change
   in a maintenance window), planned changes (need change management/testing),
   and projects (need new hardware or design work).
```

### Severity

| Severity | CIS level | Condition | Examples |
|---|---|---|---|
| Critical | Level 1 fail | Privileged access without authentication or encryption | Cleartext management (Telnet), no AAA, default SNMP community, no remote logging |
| High | Level 1 fail | Partial control with gaps | NTP without authentication, SSH enabled but v1 not disabled, banner missing on some access methods |
| Medium | Level 2 fail | Defence-in-depth control absent | Control-plane policing absent, anti-spoofing not enabled, storm control disabled |
| Low | Level 2 | Optional hardening not applied | Non-standard banner text, untuned informational traps, optional encryption on internal-only links |

| Score | Posture | Guidance |
|---|---|---|
| 90-100% | Strong | Close remaining gaps in the next maintenance cycle |
| 70-89% | Moderate | Prioritise Level 1 failures; schedule Level 2 within the quarter |
| 50-69% | Weak | Immediate remediation plan; escalate to management |
| <50% | Critical | The system may need isolation until baseline controls are applied |

### Remediation priority (decision tree)

```
Finding: FAIL
|- Level 1 control?
|  |- Yes
|  |  |- Most-privileged (management) domain? -> PRIORITY 1 (Critical/High)
|  |  |  |- Internet-facing? -> immediate remediation
|  |  |  |- Internal?       -> remediate within 7 days
|  |  |  \- Compensating control exists? -> document, schedule fix
|  |  \- Other domain?       -> PRIORITY 2 (High), remediate within 30 days
|  \- No (Level 2)
|     |- Management domain?  -> PRIORITY 3 (Medium), schedule this quarter
|     \- Other domain?       -> PRIORITY 4 (Low/Medium), next audit cycle
\- Marked Not Applicable?
   |- Justified by role/deployment model? -> document the exception with approval
   \- Not justified?                      -> re-evaluate; may be a real gap
```

### Benchmark version handling

When the system runs a version no published benchmark covers, use the nearest lower benchmark and document the delta. If the gap is more than ~2 major versions, flag reduced coverage and request an updated benchmark. New features introduced after the benchmark's target version have no corresponding control; assess them independently and note them out of scope.

---

## NIST SP 800-53 control-family assessment

Where CIS prescribes exact values, NIST SP 800-53 Rev 5 is a control catalogue assessed against an impact baseline. The system's FIPS 199 categorisation (Low / Moderate / High, taken as the high-water mark of confidentiality, integrity, and availability) selects which controls are in the baseline; higher impact means more controls and stricter implementation.

Six families have direct technical-system relevance and are where a device or workload assessment concentrates. The other 14 families are assessed at the organisational level.

```
AC  Access Control. Account management (no default/shared/dormant accounts),
    role-based access enforcement, least privilege, session termination
    (idle timeouts), remote access over encrypted protocols only.

AU  Audit and Accountability. Security-event logging, log record content
    (timestamp, event, source, outcome, identity), log storage and redundancy,
    forwarding to central analysis (SIEM), and NTP time synchronisation.

CM  Configuration Management. Baseline configuration and drift detection,
    change control and rollback, hardened settings per role, least
    functionality (unnecessary services disabled).

IA  Identification and Authentication. Centralised authentication (with local
    fallback, not primary), device-to-device authentication, authenticator
    management (password complexity, credential hashing strength, key
    management), strong SNMP (v3 authPriv over v1/v2c).

SC  System and Communications Protection. Boundary protection (filtering at
    network edges), transmission confidentiality and integrity (encryption in
    transit), network disconnect (session/tunnel timeouts), cryptographic
    protection (flag DES/3DES/RC4/MD5; require AES-128+ and SHA-256+).

SI  System and Information Integrity. Flaw remediation (version against vendor
    advisories), system monitoring (IDS/IPS, flow), security-advisory
    subscription, and software/firmware integrity verification.
```

CSF 2.0 functions sit above these: an AC or IA gap maps to **Protect (PR)**, an AU or SI monitoring gap to **Detect (DE)**. Aggregate 800-53 results per CSF subcategory when reporting at the CSF level; a single control failure does not necessarily make a whole subcategory non-compliant.

### Control-gap severity

| Severity | Impact baseline | Condition | Examples |
|---|---|---|---|
| Critical | High | Baseline control gap on a boundary or critical system | No account management on an internet-facing boundary, no boundary filtering, no authentication on management access |
| High | Moderate | Required baseline control missing or partial | No security-event logging, no MFA for privileged access, cleartext management protocols |
| Medium | Low | Baseline gap with limited exposure | Unnecessary services on an internal system, NTP not authenticated, no idle session timeout |
| Low | Enhancement | Control beyond the required baseline absent | Advanced flow analytics, link-layer encryption on internal links, RBAC beyond baseline |

| Score | Posture | Guidance |
|---|---|---|
| 90-100% | Satisfactory | Address residual gaps next cycle |
| 70-89% | Conditional | Build a POA&M; prioritise High-impact families |
| 50-69% | Deficient | Immediate remediation plan; escalate to the system owner / ISSO |
| <50% | Unsatisfactory | May not meet the authorisation threshold; consider risk acceptance or isolation |

### Gaps and the POA&M

Findings feed a **Plan of Action and Milestones (POA&M)**: each gap gets a remediation milestone, a responsible owner, a target date, and a status. Prioritise by impact baseline and trust-boundary position (a High-baseline gap on a boundary system is remediated within ~72 hours; a Moderate baseline gap within ~30 days; a Low baseline gap within ~90 days). When several gaps share a family, treat the systemic root cause (no centralised authentication produces many AC failures at once) rather than each control individually. Distinguish **inherited controls** (satisfied by the hosting environment) from device-specific controls, and coordinate inherited-control gaps with the provider.

---

## Reporting

Whichever method, the report carries the same backbone: system/device identity and role, the benchmark or baseline reference and profile/impact level, a compliance score per domain or family and overall, the critical and high findings with current state and impact, a priority-ranked remediation plan, documented exceptions with compensating controls and sign-off, and a next-assessment date scaled to posture (Critical/Unsatisfactory ~30 days, Weak/Deficient ~90, Moderate/Conditional ~180, Strong/Satisfactory ~365). Every finding cites a control ID for traceability, and every timestamp is UTC (see `utc-timestamps`).
