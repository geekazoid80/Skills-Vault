# OWASP Top 10 and the secure SDLC

This reference covers the OWASP Top 10 2021 category by category, where security activities attach to each phase of the software development lifecycle, the DevSecOps pipeline stages, the shift-left economics that justify the whole arrangement, and the tool-type selection guide that says where SAST, DAST, SCA, and WAF each fit. It cites the OWASP Top 10 and NIST guidance by name rather than reproducing them; consult the OWASP Top 10 2021 project and the NIST Secure Software Development Framework (SP 800-218) for the authoritative text.

## OWASP Top 10 2021

The OWASP Top 10 is a periodically refreshed consensus list of the most critical web application security risks, published by the Open Worldwide Application Security Project. The 2021 revision is a risk map, not a certification: it orients testing, code review, and training. Each category below names what it is, the characteristic detection approach, and the remediation pattern that closes it. CWE identifiers are cited for cross-reference to the MITRE Common Weakness Enumeration.

### A01 Broken Access Control

Restrictions on what an authenticated user may do are not enforced, so users act outside their intended permissions. Typical failures: horizontal escalation via insecure direct object reference (IDOR), vertical escalation to admin functions, missing function-level checks because the UI merely hides the endpoint, permissive CORS, JWT tampering where the signature is not verified, path traversal, and force-browsing to authenticated pages. Detection: authenticated dynamic scanning with multiple roles comparing responses, static data-flow analysis from input to the authorisation check, and manual testing of every endpoint with a lower-privileged token. Remediation: deny by default, centralise the access-control logic rather than replicating it per endpoint, trust server-side session state for permissions never a client-supplied claim, and log access-control failures. Key CWEs: CWE-22, CWE-284, CWE-285, CWE-639.

### A02 Cryptographic Failures

Absent or weak cryptography exposes sensitive data (formerly "Sensitive Data Exposure"). Typical failures: cleartext transmission, weak or deprecated algorithms (MD5, SHA-1, DES, RC4, ECB mode), hardcoded or low-entropy keys, missing HTTPS enforcement, reversible or unsalted password storage, and vulnerable padding schemes. Detection: static analysis for hardcoded secrets and weak-algorithm usage, composition analysis for libraries with known crypto flaws, and secret scanning of source. Remediation: enforce TLS 1.2 or higher with HSTS, use a memory-hard password hash (Argon2id, bcrypt as fallback), use authenticated symmetric encryption (AES-256-GCM), store only hashed passwords, and hold keys in a secrets manager. Key CWEs: CWE-259, CWE-327, CWE-331.

### A03 Injection

User-supplied data is interpreted as a command or query (cross-site scripting was merged in from the 2017 list). Subtypes: SQL, NoSQL, LDAP, and OS-command injection; reflected, stored, and DOM-based XSS; server-side template injection; and log injection. Detection: static taint analysis tracking input from source (HTTP parameter, header) to sink (query, shell), dynamic payload injection across every input vector, and manual review wherever user data meets an interpreter. Remediation: parameterised queries and prepared statements (never string concatenation into a query), allowlist input validation, context-specific output encoding, a Content Security Policy to blunt XSS impact, and least-privilege database accounts. Key CWEs: CWE-79, CWE-89, CWE-917.

### A04 Insecure Design

Missing or ineffective security controls at the architecture level, new in 2021. It cannot be fixed by flawless implementation; it requires a redesign. Typical patterns: no rate limiting on credential-recovery flows, storing sensitive data that was never needed, no MFA on administrative actions, trusting client-side data for business-critical decisions, and inadequate tenant separation. Remediation: threat model during design rather than after, apply the ASVS as a design checklist, use secure design patterns (secure defaults, fail secure, defence in depth), and limit resource consumption per user. This is the category that a scanner cannot catch and only design-time work closes. Key CWEs: CWE-73, CWE-183, CWE-209.

### A05 Security Misconfiguration

Incorrect or incomplete configuration, often insecure defaults left in place. Typical failures: unchanged default credentials, unnecessary features enabled (debug endpoints, production stack traces), missing security headers, overly permissive CORS, publicly readable cloud storage, XML external entity (XXE) processing enabled, and verbose error messages. Detection: dynamic header and error-message scanning, and infrastructure-as-code scanning. Remediation: a repeatable hardening process, minimal installed features, security headers, and parity between environments. Cloud-storage and cloud-configuration posture routes to `cloud-security-posture`. Key CWEs: CWE-16, CWE-611.

### A06 Vulnerable and Outdated Components

Using libraries, frameworks, or platforms with known vulnerabilities. Detection: software composition analysis continuously matching the dependency tree against vulnerability databases (NVD, OSV, GitHub Advisory), container base-image scanning, and SBOM generation for the audit trail. Remediation: maintain a Software Bill of Materials, automate dependency updates, and patch within an SLA driven by severity. The SLA framework and the risk-based prioritisation belong to `vulnerability-management`; the container supply chain belongs to `container-security`. Key CWE: CWE-1104.

### A07 Identification and Authentication Failures

Weak authentication or session management that lets an attacker impersonate a user. Typical failures: permitting weak passwords or credential stuffing with no lockout, weak password-hashing, predictable reset tokens, session IDs in URLs, sessions not invalidated on logout or timeout, and missing MFA. Remediation: strong credential storage, anti-automation on the login flow, secure session lifecycle, and MFA for sensitive actions. Key CWEs: CWE-287, CWE-297, CWE-384.

### A08 Software and Data Integrity Failures

Code and infrastructure that does not protect against integrity violations, new in 2021 and including insecure deserialisation and pipeline attacks. Typical failures: insecure deserialisation of untrusted data, unsigned software updates, untrusted CDN content with no Subresource Integrity hash, a compromised CI/CD pipeline (dependency confusion, malicious plugins), and unpinned package versions. Detection: composition analysis with integrity verification, static rules for unsafe deserialisation sinks, and pipeline security review. Signing and provenance for the container and artefact supply chain route to `container-security`. Key CWEs: CWE-345, CWE-494, CWE-829.

### A09 Security Logging and Monitoring Failures

Insufficient logging and detection lets an attacker operate undetected. What must be logged: authentication events (success and failure), authorisation failures, input-validation failures, application errors, and high-value transactions, each with enough context (user, source, timestamp, action, outcome). Log quality: tamper-evident append-only storage forwarded to a SIEM, alerting on threshold violations, and a retention period that meets the applicable regulation. Key CWEs: CWE-117, CWE-223, CWE-778.

### A10 Server-Side Request Forgery (SSRF)

The application fetches a remote resource from a user-supplied URL, and an attacker redirects the request to an internal target: a cloud metadata endpoint, an internal service, or the local file system. Detection: static tracking of user-controlled input to an HTTP-client call, and dynamic injection of internal ranges and metadata URLs. Remediation: allowlist permitted URL schemes and destination hosts, disable or re-validate redirects, use a token-required metadata service, and segment the network so application servers have no unrestricted outbound access. Key CWE: CWE-918.

## Secure SDLC integration points

Security is not a phase; it is a set of activities attached to every phase of the software development lifecycle. NIST SP 800-218 (the Secure Software Development Framework) is the reference model. The phases and their characteristic security work:

| Phase | Security activities | Primary outputs |
|---|---|---|
| Requirements | Set security requirements from data classification and regulatory scope, choose the ASVS level for the risk tier, write abuse cases alongside use cases | security requirements, risk-tier classification |
| Design | Threat model with STRIDE per component and data flow, review authentication, authorisation, encryption, and API design | threat model, security architecture decisions, data-flow diagrams |
| Development | IDE security plugins, secure-coding standards and training, security-checklist code review, pre-commit hooks (secret scanning, linting) | secure code, developer awareness |
| Build and CI | SAST scan (fail on new critical or high), SCA scan (block on exploitable vulnerabilities), IaC scanning, container image scanning, SBOM generation | gated build, SBOM artefact |
| Test | DAST against a deployed test environment, API security testing, penetration testing for higher tiers, security regression tests | dynamic findings, pen-test report |
| Release | AppSec sign-off with documented risk acceptance for open items, WAF rules reviewed, secrets rotated, security release notes | release approval |
| Operate | WAF monitoring and tuning, scheduled DAST, SLA-driven patching of new CVEs, incident response, penetration-testing cadence | continuous assurance |

The single organising rule: a control that no phase owns is a control that is never implemented, so each activity is assigned to a phase explicitly rather than assumed to happen somewhere.

## DevSecOps pipeline stages

DevSecOps is the operational expression of the secure SDLC: the security activities above wired into the delivery pipeline as automated stages. The pipeline wiring itself (workflow authoring, runners, gate mechanics) belongs to `gh-actions-ci` and `cicd-platforms-ops`; this is the security-stage map they carry.

1. **Pre-commit**: secret scanning and security-rule linting on the developer's machine, before anything is committed.
2. **Pull request**: SAST diff decoration on the changed code and SCA dependency review, annotating the PR rather than dumping a full report.
3. **Build**: full SAST scan, full dependency audit, IaC scanning, container image scanning, and SBOM generation.
4. **Test**: DAST against a deployed test environment and API security tests.
5. **Release gate**: a security quality gate that must pass before promotion, enforcing policy on what may ship.
6. **Deploy**: WAF rules provisioned or updated for the release.
7. **Runtime**: WAF monitoring, scheduled DAST, and continuous dependency and threat-intelligence updates.

## Shift-left economics

The justification for the whole arrangement is cost. A defect caught earlier in the lifecycle is dramatically cheaper to fix than the same defect caught later, because later fixes touch more downstream work and, in production, incident response. The rough gradient:

| Where found | Relative cost | Method |
|---|---|---|
| Design / requirements | 1x | threat model review |
| Development (IDE) | ~6x | IDE SAST plugin |
| Build / CI | ~15x | CI SAST and SCA gate |
| QA / test | ~45x | DAST, penetration test |
| Production | ~100x | WAF detection, incident response |

Practical sequence: start with IDE feedback (zero friction), add pre-commit secret scanning, add SAST to pull-request checks (annotate the diff, not the whole report), add SCA to CI (fail on exploitable CVEs), add DAST to the test pipeline, and add a WAF as the last defensive layer in production. The dominant failure mode is switching every gate to fail-on-everything at once: it floods developers, findings are ignored wholesale, and the programme loses credibility. Introduce feedback first, then a baseline, then blocking gates that tighten over time.

## Tool-type selection guide

Which testing technique answers a given question determines where it sits in the pipeline. The concept-level description of each technique and the routing to its discipline live in `testing-types-and-routing.md`; this is the quick selection table.

| Scenario | Technique |
|---|---|
| Find vulnerabilities in code you write | SAST |
| Find vulnerabilities in a running application | DAST |
| Find vulnerabilities in libraries you depend on | SCA |
| Block attacks against production | WAF |
| Developer feedback loop with minimal friction | IDE SAST |
| API security testing | DAST driven by an API schema |
| Supply-chain and dependency risk | SCA plus SBOM generation |
| Compliance audit spanning code, dependencies, and runtime | SAST plus SCA plus WAF in combination |

The techniques are complementary: SAST reads the source, DAST exercises the running system, SCA inventories the dependencies, and a WAF blocks at runtime. A mature programme composes all four across the pipeline rather than choosing one.
