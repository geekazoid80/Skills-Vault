# Validation, traceability, and maturity

## Atomic testing

[Atomic Red Team](https://github.com/redcanaryco/atomic-red-team) is the standard open-source library of small, technique-scoped tests: one atomic test per technique or sub-technique, each with documented prerequisites, an execution command, and a cleanup command. The discipline:

1. Pick the technique/sub-technique to validate.
2. Confirm prerequisites (the atomic's README states what's needed, e.g. a specific OS, a tool present).
3. Run the atomic in a controlled environment, or in production only with the same authorisation discipline `penetration-testing` requires for any active technique (this is intentionally the same guardrail; an atomic test that actually executes adversary tradecraft is not exempt from authorisation just because it's "just testing").
4. Confirm the expected detection fired, with the expected fidelity (right technique ID, right severity, no excessive noise).
5. Run the atomic's cleanup command. Do not skip this; several atomics leave artefacts (scheduled tasks, registry keys, dropped files) that will confuse a later real investigation if left behind.
6. Record the result against the technique in the coverage layer: pass → Good with today's date; fail → Partial with the gap noted; the detection fired but was miscategorised → Partial, tuning needed.

## Purple-team exercises

Where atomic tests validate one technique at a time, a purple-team exercise chains several techniques into a realistic attack path (e.g. initial access → discovery → credential access → lateral movement → exfiltration) with the offensive side (red) and defensive side (blue) collaborating in real time rather than red reporting findings after the fact. Use a purple-team exercise to validate:

- **Detection chaining**: does the SOC actually connect five separate Partial/Good alerts into one incident, or do they sit as five unrelated tickets?
- **Time-to-detect and time-to-respond**, not just "did it alert".
- **Coverage claims that only make sense in combination** (e.g. a detection that depends on correlating an unusual logon with a subsequent process creation).

Cadence: quarterly for a mature programme, at minimum after any major change to the environment (new EDR platform, cloud migration, major re-architecture) or after a significant new adversary TTP is published against your sector.

## Detection-to-technique traceability

Every detection rule (SIEM correlation rule, EDR custom detection, NDR signature) should carry its mapped technique ID(s) in its own metadata, not only in a separate spreadsheet. Most platforms support a tags/labels field; use it. This is what makes a coverage audit a query instead of an archaeology project, and what lets `siem-soar-investigation`'s detection-engineering lifecycle and this skill's coverage layer stay in sync automatically rather than by manual reconciliation.

A rule with no technique tag is untraceable: nobody can answer "if we disable this rule, what coverage do we lose" six months later. Treat an untagged rule as a defect to fix, not a style preference.

## Maturity model

| Level | Description |
|---|---|
| **Ad hoc** | Detections exist but are not mapped to ATT&CK at all. Coverage claims are anecdotal. |
| **Mapped** | Every detection is tagged with technique ID(s); a Navigator layer exists but scores are self-reported, not validated. |
| **Validated** | Layer scores are backed by atomic tests; "Good" means tested, not asserted. |
| **Continuously tested** | Atomic tests run on a schedule (not just once), purple-team exercises run quarterly, and the layer is re-baselined against every ATT&CK matrix update. Coverage decay (a detection silently breaking) is caught by the schedule, not by the next incident. |

Most organisations starting this practice are at Ad hoc or Mapped. Moving to Validated is the highest-leverage single step: it is the difference between a coverage layer that is decoration and one that is a real operational instrument.

## Re-baseline discipline

At every ATT&CK matrix version bump: diff the new technique/sub-technique list against the current layer, add newly-introduced techniques as unscored (None) until assessed, flag any technique your layer currently scores that has been deprecated or merged, and re-file if a technique you previously mapped has been renumbered. Do this on a fixed cadence tied to MITRE's release calendar (roughly twice yearly), not opportunistically; opportunistic re-baselining is how layers silently go stale for years.
