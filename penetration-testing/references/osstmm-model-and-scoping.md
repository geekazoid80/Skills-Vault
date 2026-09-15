# OSSTMM model, channels, and scoping

## What OSSTMM actually is

The Open Source Security Testing Methodology Manual (ISECOM) is a methodology for *how to conduct and measure* a security test, not a vulnerability checklist like the OWASP Top 10 or a technique catalogue like MITRE ATT&CK. Its contribution is a repeatable, channel-based way to define scope and a quantitative way to express residual trust (RAV), rather than a specific list of things to check. Use it as the scoping and measurement discipline; pair it with `application-security`'s OWASP depth or `attack-technique-mapping`'s ATT&CK depth for the actual test-case content.

OSSTMM is older and less actively maintained than ATT&CK or the OWASP Testing Guide; treat its channel model and RAV concept as durable and useful, and prefer current tooling/technique references (this vault's other skills) for up-to-date technical test cases.

## The five channels

OSSTMM scopes a security test across five channels. A "penetration test" request defaults, almost always silently, to Data Networks only. State explicitly which channels are in scope:

| Channel | What it covers | Typical techniques |
|---|---|---|
| **Human** | Social engineering of people | Phishing, pretexting, vishing, physical-access social engineering |
| **Physical** | Physical access controls | Badge cloning, tailgating, lock bypass, dumpster diving, device theft simulation |
| **Wireless** | RF-based communication | Wi-Fi (rogue AP, WPA attacks), Bluetooth, RFID/NFC, other RF |
| **Telecommunications** | Voice and legacy telecom | VoIP, PBX, war-dialing, SIP trunk abuse |
| **Data Networks** | IP-based networks and applications | Everything `nmap-scanning`, `application-security`'s children, and most of `vulnerability-management` already cover |

An engagement can legitimately scope to Data Networks only; the point is making that a stated decision in the rules of engagement, not an unexamined default. A client who asked for "a pentest" and only received Data Networks coverage should know that Human, Physical, Wireless, and Telecommunications were out of scope, and why (cost, time, or genuine irrelevance to their risk model).

## RAV: Risk Assessment Value

RAV expresses residual trust as a number derived from three inputs. This is a conceptual model for structuring the conversation, not a certification exercise; the bundled `rav_score_calculator.py` implements a simplified version of the formula for practical use.

**Porosity**: the visible and reachable attack surface: every access point (open port, exposed service, public-facing form, physical entry point, radio-visible SSID, phone extension) that exists whether or not it is controlled. More porosity is not automatically worse if it is well controlled, but it always raises the baseline that controls must overcome.

**Controls**: the ten OSSTMM operational security controls, split into two groups:

*Class A (preventing loss of control over an asset):*
1. Authentication: verifying identity before granting access
2. Indemnification: contractual/insurance protection against loss
3. Resilience: the ability to keep functioning under attack
4. Subjugation: ensuring an interaction only proceeds on the tester's/defender's terms
5. Continuity: maintaining service/access despite disruption

*Class B (preserving the value of an interaction that occurs):*
6. Non-repudiation: proof an action occurred and who performed it
7. Confidentiality: restricting access to information to authorised parties
8. Privacy: restricting access to identifying information specifically
9. Integrity: ensuring information/systems are not altered without authorisation
10. Alarm: detecting and notifying on an attempted or successful interaction

**Limitations**: five categories of weakness that reduce the value of the controls present: Vulnerabilities (a flaw that grants access), Weaknesses (a flaw in a control's implementation), Concerns (a potential flaw not yet confirmed exploitable), Exposures (information disclosure that aids further attack), and Anomalies (unidentified or unexplained items that cannot be verified safe).

**The RAV formula (simplified for practical use):** `RAV ≈ 100 - (porosity_unmitigated) + (controls_present_and_verified) - (limitations_weighted)`, normalised so 100 represents a fully trusted, zero-residual-risk state and lower values represent increasing residual risk. The exact ISECOM formula is more elaborate (separate calculations per channel, weighted by control class); `rav_score_calculator.py` implements a defensible simplified version suitable for a single engagement's summary metric, not a certified OSSTMM audit.

Use RAV to give a client one comparable number per engagement/channel over time (is this quarter's Data Networks RAV better or worse than last quarter's), not as a substitute for the detailed findings list.

## Scoping and rules of engagement

Every engagement needs a written RoE before any active technique runs (see `examples/rules_of_engagement_template.md`). At minimum, the RoE states:

- **Scope**: exact IP ranges, domains, applications, physical locations, phone numbers, or SSIDs in scope. Anything not explicitly listed is out of scope.
- **Channels**: which of the five OSSTMM channels are included, and an explicit statement of which are excluded and why.
- **Time window**: start and end date/time, including timezone, and any blackout windows (e.g. no testing during a customer's peak trading hours).
- **Allowed techniques**: what level of exploitation is authorised (identification only, PoC exploitation, full exploitation with lateral movement), whether social-engineering pretexts need pre-approval, whether DoS-adjacent techniques are explicitly excluded (they should be, by default).
- **Escalation contact**: a named person reachable during the test window who can authorise scope changes or halt the test.
- **Data handling**: how evidence (screenshots, extracted data samples, credentials found) is stored, encrypted, and destroyed after the engagement closes.
- **Emergency stop condition**: what happens if the tester causes unexpected impact (a crashed service, an unintended lockout); who gets notified immediately and how testing pauses.

The authorisation record itself, not just the RoE template, may have a durable home your organisation already defines elsewhere (a standing security-testing procedure, a local companion skill); check for it before assuming this template alone satisfies your organisation's authorisation requirement.
