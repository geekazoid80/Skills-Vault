# Coverage scoring and prioritisation

## The None / Partial / Good rubric

Score every technique (at sub-technique granularity where one exists) against three levels. Be honest; the rubric only works if the labels mean something:

| Level | Criteria | Score |
|---|---|---|
| **None** | No data source reaches your telemetry stack for this technique. Not detectable today at any confidence. | 0 |
| **Partial** | The data source exists and reaches SIEM/EDR/NDR, but there is no tuned detection rule, or the rule exists but has never been validated to actually fire. | 50 |
| **Good** | A tuned detection rule exists, has a known false-positive rate, and has been validated in the last testing cycle (atomic test or purple team) to actually alert when the technique is executed. | 100 |

A rule that exists but was last validated two matrix versions ago is not "Good"; treat it as "Partial" until re-validated. Coverage decays as environments change (new EDR agent version, log-forwarding change, a detection quietly disabled during an incident and never re-enabled).

## Cross-domain aggregation

Most techniques are detectable from more than one telemetry domain (endpoint, network, identity, cloud). Score coverage per domain first, then take the **maximum** across domains as the technique's overall score, not the average or the sum: if NDR detects lateral movement (T1021) with Good confidence, the technique is covered even if EDR has no equivalent rule. Recording per-domain scores (not just the aggregate) is what lets you see genuine gaps versus redundant coverage when planning tool consolidation.

Keep one Navigator layer per domain (endpoint, network, cloud) plus one aggregate layer. The per-domain layers are what detection engineers act on; the aggregate is what goes to leadership.

## Gap scoring and prioritisation

Do not prioritise the backlog by which gap is easiest to close. Score each gap on:

1. **Technique prevalence** — how often this technique appears in current threat intelligence relevant to your sector/region. Sources: the Center for Threat-Informed Defense's [Top ATT&CK Techniques](https://top-attack-techniques.mitre-engenuity.org/) project (calculates prevalence, choke-point value, and actionability), vendor annual threat reports (Red Canary, CrowdStrike, Mandiant), sector-specific ISAC advisories, and CISA/national-CERT advisories naming techniques used against your sector.
2. **Asset criticality** — what would this technique compromise if undetected: a disposable dev box, or the domain controller / crown-jewel data store. Weight against your asset criticality tiering (reuse whatever tiering `vulnerability-management`'s programme already defines; do not invent a second one).
3. **Current coverage gap** — None scores higher priority than Partial; a technique already at Partial needs validation effort, not net-new engineering.

A simple weighted score (`prevalence x criticality x (1 - current_score/100)`) is usually enough to rank the backlog; resist building an elaborate model before the simple one has been tried.

## Choke points

Some techniques sit on a disproportionate number of attack paths (e.g. valid-account abuse T1078, or process injection T1055) because many other techniques depend on them succeeding first. Closing a choke-point gap degrades many downstream attack paths at once, not just the one technique. The Center for Threat-Informed Defense's methodology explicitly scores "choke-point value" for this reason; weight choke-point techniques above their raw prevalence score would suggest.

## Reporting the gap analysis

Present three things together, not the Navigator layer alone: the current coverage layer, the ranked gap list with the scoring rationale per item, and the specific data source or engineering work each gap needs. A layer with no accompanying "what would it take to close this" list is a status report, not a backlog.
