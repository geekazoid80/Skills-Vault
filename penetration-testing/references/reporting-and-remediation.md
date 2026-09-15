# Reporting and remediation hand-off

## Two audiences, two documents (or two clearly separated sections)

**Executive summary**: for people who will not read a CVSS vector string. States: what was tested and what was explicitly out of scope (including excluded OSSTMM channels), the overall risk posture in business terms, the two or three findings that matter most and what an attacker could actually do with them, and the RAV trend if this is a repeat engagement. No technical jargon; if a finding needs "SQL injection" explained, explain it once in a sentence, not with a payload example.

**Technical findings report**: for the people who will fix it. Each finding carries: a clear title, the affected asset(s), a severity rating with the rationale (not just a CVSS number pasted in), reproduction steps precise enough that the engineering team can confirm the fix later without re-hiring the tester, evidence (screenshots, redacted data samples, command output), and a specific remediation recommendation, not just "patch the system".

## Severity and business-risk framing

Do not report severity as a bare CVSS score. State: likelihood (how easily could this be found and exploited by an opportunistic attacker, versus only a sophisticated targeted one), impact (what specifically is exposed or achievable), and any mitigating factor already in place (a WAF rule, network segmentation) that changes real-world exploitability even if it doesn't change the underlying CVSS. Two findings with the same CVSS score can carry very different real risk; say so explicitly rather than letting the number do the talking.

Where the engagement exists to satisfy a compliance requirement (PCI DSS's mandated pentest, a SOC 2 control), map findings back to the specific control or requirement they affect; cross-reference `compliance-benchmark-audit` for the framework-side mapping conventions already established there rather than inventing a new mapping scheme per report.

## Evidence handling

Screenshots and extracted-data samples are evidence, not decoration. Redact anything beyond what is needed to prove the finding (a data sample proves exposure with three rows, not the entire table). Store evidence per the RoE's data-handling terms; if the RoE says evidence is destroyed 30 days after report delivery, calendar that and actually do it. Never paste a real credential, API key, or full PII record into the report body; reference where it was found and how it was validated, per `secrets-hygiene`.

## Remediation hand-off

A report is not the end state; a tracked remediation programme is. For every finding:

1. **Assign an owner and a due date** proportional to severity, using whatever SLA tiers `vulnerability-management`'s programme already defines for the organisation, rather than inventing pentest-specific SLAs that don't reconcile with the standing VM programme.
2. **File it where the organisation already tracks remediation**, whatever shared findings tracker it already runs, not a new spreadsheet invented for this engagement.
3. **Agree a re-test date** for the highest-severity findings, and actually perform the re-test; a finding marked "remediated" by the asset owner without independent re-validation is a claim, not a fact, so re-verify against live state rather than trusting the ticket status.
4. **Track the RAV/coverage trend across engagements**, not just this engagement's raw finding count, so the client can see whether the programme is actually reducing residual risk over time or just generating reports.

## Report retention and confidentiality

A pentest report is one of the most sensitive documents an organisation holds (it is, by construction, a list of exploitable weaknesses). Store it with the same access controls as the organisation's most sensitive data, never in a broadly-shared drive by default, and confirm the RoE's stated retention/destruction terms are actually honoured on schedule.
