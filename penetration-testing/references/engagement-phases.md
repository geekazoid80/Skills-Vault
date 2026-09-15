# Engagement phases

Five phases, in order, each gated on the authorisation established before Phase 1 ever starts. Do not begin a phase until the RoE covers it explicitly.

## Phase 0: Authorisation (gate, not a phase to skip)

Confirm the written RoE is signed, current (within its stated time window), and covers exactly what is about to happen. If asked to test something outside the current RoE scope, even something adjacent and seemingly low-risk, stop and get the scope amended in writing before proceeding. "It's basically the same target" is the rationalisation that turns an authorised engagement into an unauthorised one.

## Phase 1: Reconnaissance

Passive and light-active information gathering to understand the target before touching it directly. For the external, internet-facing surface, this phase is `external-attack-surface-recon`'s job: subdomain enumeration, certificate transparency, passive DNS, technology fingerprinting, and OSINT (employee names for Human-channel pretexts, physical addresses for Physical-channel scoping, if those channels are in scope). For internal engagements, recon includes network topology discovery, service banner collection, and (with separate explicit authorisation) any Human/Physical-channel information gathering.

Output: an asset/target inventory feeding directly into Phase 2, plus any channel-specific groundwork (a pretext script for Human channel, a floor plan for Physical channel).

## Phase 2: Enumeration and vulnerability identification

Active scanning and service enumeration within the authorised scope: port/service scanning (`nmap-scanning` owns the mechanics), vulnerability scanning against identified services (credentialed where authorised and useful, cross-reference `vulnerability-management`'s scan-method guidance), web-application enumeration and automated scanning (`application-security`'s DAST/SAST children if the scope includes an app), and manual verification of anything a scanner flags before it is treated as a real finding.

This phase produces candidate findings, not confirmed ones. A scanner's "CRITICAL" is a hypothesis; Phase 3 (or, for findings that don't warrant exploitation, careful manual verification) confirms it.

## Phase 3: Exploitation (proof-of-concept only)

Authorised exploitation to demonstrate real impact, bounded strictly by the RoE's allowed-technique list. The discipline:

- **Prove the impact, stop at proof.** Access a redacted sample of data to prove exposure, not the entire dataset. Demonstrate privilege escalation to the next meaningful boundary, not necessarily all the way to Domain Admin, unless the RoE specifically calls for a full compromise chain.
- **No destructive payloads.** Never run an exploit variant that could crash a production service, corrupt data, or cause an availability impact, even if a more "impressive" variant exists. If a target's stability under a given exploit is unknown, prefer the identification-only finding over the exploitation attempt, or test against a non-production instance first if one exists.
- **No persistence left behind.** Remove any implant, scheduled task, account, or backdoor created during exploitation before the engagement closes. Document what was created and confirm removal in the report.
- **Log everything as you go.** Timestamped notes of every command run against every target are what makes the report defensible and what lets the client's own incident-response/SOC correlate what they saw against what actually happened (useful cross-reference: `incident-response-network`'s evidence-handling discipline, applied here to the tester's own actions).
- **DoS techniques are excluded by default.** Do not run a technique whose primary effect is denial of service unless the RoE explicitly and separately authorises it (rare, and normally requires a dedicated resilience-testing engagement, not a standard pentest).

## Phase 4: Post-exploitation impact assessment

Once access or a confirmed exploitable path exists, assess what it actually means for the business rather than immediately pivoting further: what data was reachable, what systems were reachable from this foothold, what an actual adversary with this access could realistically do given the time window a real intrusion would have (weeks, not the hours of the engagement). This is where the RAV/porosity-and-controls framing from `osstmm-model-and-scoping.md` becomes concrete: does the access achieved bypass a specific control class (authentication, confidentiality) that the client believed was in place?

## Phase 5: Reporting and remediation hand-off

Covered in depth in `reporting-and-remediation.md`. The phase is not complete when the PDF is sent; it is complete when every finding has a remediation owner and a tracked ticket, typically in `vulnerability-management`'s system, and a re-test date is agreed for the findings that matter most.

## Cleanup checklist before closing any engagement

- All test accounts, implants, scheduled tasks, and persistence mechanisms removed and confirmed removed.
- All extracted data samples (even redacted ones) securely destroyed per the RoE's data-handling terms, unless retained specifically as report evidence with the client's agreement.
- Any firewall rules, WAF exceptions, or monitoring exclusions temporarily granted for the test are reverted.
- The escalation contact is notified the engagement has ended and the time window is closed, so any lingering unusual activity after that point is treated by the client's SOC as a real event, not assumed to be the test.
