# Threat modelling and the ASVS

This reference covers threat modelling for applications (STRIDE, data-flow diagrams, and trust boundaries, with PASTA and LINDDUN as complements) and the OWASP Application Security Verification Standard (ASVS): its verification levels, its chapters, and how to turn it into concrete security requirements. Together they make security a design-time and verification discipline rather than a scan run before release. The OWASP ASVS and the STRIDE and PASTA methodologies are cited by name; consult the OWASP ASVS project and the original methodology sources for the authoritative text.

## Threat modelling for applications

Threat modelling asks "what can go wrong here?" at design time, before code exists, when the cost of change is lowest. It is the activity that closes insecure design (OWASP A04), the category no scanner catches. The discipline has three moving parts: a model of the system (the data-flow diagram), the boundaries an attacker would cross (trust boundaries), and a structured enumeration of threats against each element (STRIDE).

### Data-flow diagrams and trust boundaries

A data-flow diagram (DFD) models the application as four element types: external entities (users, third-party services), processes (the application's own components), data stores (databases, caches, file systems), and data flows (the arrows between them). The DFD is deliberately coarse; the point is to see where data moves and where it rests, not to document every function.

A **trust boundary** is a line on the DFD where the level of trust changes: between the internet and the application, between the application and its database, between one tenant and another, between a low-privilege and a high-privilege component. Trust boundaries are where threats concentrate, because they are exactly the points an attacker must cross to move from where they are to where they want to be. Drawing the boundaries is the analytical heart of the exercise: a data flow that crosses a boundary is the one that needs authentication, validation, and encryption.

### STRIDE

STRIDE is the per-component threat taxonomy best suited to application and service threat modelling. For each element and data flow on the DFD, walk the six threat classes and ask whether each applies:

| Threat | Property violated | Example | Maps to OWASP |
|---|---|---|---|
| Spoofing | Authentication | forged JWT, session hijacking | A07 |
| Tampering | Integrity | SQL injection, parameter manipulation | A03, A08 |
| Repudiation | Non-repudiation | deleting or bypassing audit logs | A09 |
| Information Disclosure | Confidentiality | directory traversal, verbose errors, crypto failure | A02 |
| Denial of Service | Availability | resource exhaustion, ReDoS | (WAF mitigation) |
| Elevation of Privilege | Authorisation | IDOR, SSRF to a metadata endpoint | A01, A10 |

The process:

1. Draw the DFD and mark the trust boundaries.
2. For each element and each data flow, enumerate the applicable STRIDE threats.
3. Rate each threat by likelihood and impact.
4. Decide a disposition for each: mitigate, accept, transfer, or avoid.

The output is a threat model document listing the threats, their ratings, and their dispositions, plus the security requirements the mitigations imply.

### PASTA and LINDDUN

STRIDE is the default, but two complements matter:

- **PASTA** (Process for Attack Simulation and Threat Analysis) is a seven-stage, risk-centric methodology that starts from business objectives and works down to attack enumeration and residual-risk analysis. It suits situations where the threat model must align to business risk and be defensible to non-engineering stakeholders. The stages run from defining business objectives, to technical scope, to application decomposition, to threat analysis, to vulnerability analysis, to attack enumeration, to risk and impact analysis.
- **LINDDUN** is a privacy-focused methodology (Linkability, Identifiability, Non-repudiation, Detectability, Disclosure of information, Unawareness, Non-compliance). It complements STRIDE when the application handles personal data and privacy requirements (for example under GDPR) need explicit modelling that a security-only taxonomy would miss.

## OWASP ASVS

The Application Security Verification Standard is a catalogue of security requirements and a graded verification bar. Where threat modelling asks "what can go wrong?", the ASVS asks "how thoroughly must we verify that it cannot?" It serves two roles: a checklist of security requirements to design against, and a definition of how much verification effort a given application warrants. This skill uses it as an engineering verification bar; using ASVS as compliance evidence in an audit programme routes to `compliance-benchmark-audit`.

### Verification levels

The ASVS defines three levels, chosen to match the application's risk tier:

- **Level 1**: opportunistic security, verifiable by automated testing. All applications should meet L1 as a baseline. Appropriate where a breach would be low impact.
- **Level 2**: standard security for applications handling sensitive data. Requires manual verification for controls automation cannot confirm. The typical target for most business applications.
- **Level 3**: the highest rigour, for critical applications (finance, healthcare, safety-critical). Requires penetration testing and architectural review on top of everything in L2.

The level is set once, in the requirements phase, from the data classification and the impact of compromise. It then drives how much verification each subsequent phase performs.

### Chapters as security requirements

The ASVS is organised into chapters, each a coherent control area. Treating the relevant chapters as a requirements checklist is how the standard becomes concrete engineering work rather than an abstract benchmark:

| Chapter | Area | Representative controls |
|---|---|---|
| V1 | Architecture, design, threat modelling | documented security architecture, trust boundaries defined |
| V2 | Authentication | MFA, memory-hard credential storage, account lockout |
| V3 | Session management | secure and HttpOnly cookies, invalidation on logout |
| V4 | Access control | centralised enforcement, deny by default |
| V5 | Validation, sanitisation, encoding | input validation, context-specific output encoding |
| V6 | Stored cryptography | approved algorithms, key management |
| V7 | Error handling and logging | no sensitive data in logs, complete audit trail |
| V8 | Data protection | classification, minimisation, encryption in transit and at rest |
| V9 | Communication | TLS 1.2 or higher, certificate validation, HSTS |
| V10 | Malicious code | code review, dependency integrity, no backdoors |
| V11 | Business logic | rate limiting, anti-automation, workflow integrity |
| V12 | Files and resources | file-type validation, safe parsing, malware scanning |
| V13 | API and web service | authentication, schema validation, rate limiting |
| V14 | Configuration | minimal attack surface, security headers, hardening |

### Mapping the level to pipeline enforcement

The chosen ASVS level sets how much verification each phase of the pipeline runs:

| ASVS level | Pipeline enforcement |
|---|---|
| L1 | automated SAST and SCA in CI with a basic ruleset |
| L2 | automated SAST, SCA, and DAST plus a manual security review |
| L3 | everything in L2 plus an independent penetration test and a formal threat-model review |

### ASVS chapters mapped to the OWASP Top 10

The two OWASP artefacts interlock: the Top 10 names the risk, and the ASVS chapters name the requirements that verify it is controlled.

| OWASP 2021 | Primary ASVS chapters |
|---|---|
| A01 Broken Access Control | V4 |
| A02 Cryptographic Failures | V6, V9 |
| A03 Injection | V5, V7 |
| A04 Insecure Design | V1, V11 |
| A05 Security Misconfiguration | V14 |
| A06 Vulnerable Components | V10 |
| A07 Authentication Failures | V2, V3 |
| A08 Integrity Failures | V8, V10 |
| A09 Logging Failures | V7 |
| A10 SSRF | V5, V13 |

## Security requirements

The end product of both activities is a set of security requirements: written statements of what the application must do to be secure, sitting alongside the functional requirements. Threat modelling generates them from the bottom up (each mitigated threat implies a requirement); the ASVS supplies them from the top down (each in-scope chapter control is a requirement). Writing abuse cases alongside use cases in the requirements phase captures the same intent from the attacker's side. Requirements written this early are the cheapest security artefact to produce and the one that most reduces insecure design, because they constrain the architecture before any code commits to it.
