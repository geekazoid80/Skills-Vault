---
name: application-security
description: "Use for the vendor-neutral application security (AppSec) discipline and its routing: the OWASP Top 10 2021 categories, secure SDLC and DevSecOps integration points, shift-left economics, threat modelling for applications (STRIDE, data-flow diagrams, trust boundaries), the OWASP ASVS verification levels, and what SAST, DAST, SCA, and WAF each are and where they sit across build, test, deploy, and runtime. The organising idea is that application risk is reduced most cheaply the earlier it is caught, so security is a property built into the lifecycle rather than a gate bolted on at the end, and the four testing techniques compose across the pipeline rather than competing. Triggers include \"application security\", \"AppSec\", \"OWASP Top 10\", \"secure SDLC\", \"DevSecOps\", \"shift left\", \"threat modelling\", \"threat modeling\", \"ASVS\", \"SAST\", \"DAST\", \"SCA\", \"WAF\", \"secure coding\", \"software security\", \"secure development lifecycle\". References owasp-and-sdlc.md, threat-modelling-and-asvs.md, testing-types-and-routing.md. Do NOT use for: vulnerability-management programme design, CVSS/EPSS scoring, and remediation SLAs (see vulnerability-management); GRC frameworks and ASVS/PCI/OWASP-as-compliance-evidence (see compliance-benchmark-audit); cloud posture and DevSecOps in the cloud estate, CSPM/CNAPP (see cloud-security-posture); secrets in code and secret scanning discipline (see secrets-hygiene); container and Kubernetes supply-chain, image SBOM, SLSA, cosign, and admission (see container-security); CI/CD pipeline wiring (see gh-actions-ci and cicd-platforms-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Application security

> **Skill marker**: When applying this skill, begin your reply with `[skill: application-security]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for application security. It owns the reasoning that survives any one tool: what the OWASP Top 10 2021 categories are and how they map to detection and remediation, where security activities attach to each phase of the software development lifecycle, why moving a check left saves an order of magnitude in remediation cost, how threat modelling and the OWASP ASVS turn security into a design-time and verification discipline, and what the four testing techniques (SAST, DAST, SCA, and WAF) each do and where they compose across build, test, deploy, and runtime. Tool-specific configuration (a Semgrep ruleset, a ZAP scan policy, a Snyk gate, a Cloudflare managed ruleset) is not the subject here; the design in this skill is what outlasts a tooling change.

## When to use

- Explaining or applying the OWASP Top 10 2021: what each category covers, how it is detected, and the remediation pattern that closes it.
- Placing security activities in the software development lifecycle so each phase (requirements, design, development, build, test, release, operate) has the right control attached.
- Reasoning about DevSecOps pipeline stages and shift-left economics: where a check belongs and why earlier is cheaper.
- Threat modelling an application: drawing a data-flow diagram with trust boundaries and enumerating threats per component with STRIDE.
- Setting a verification bar with the OWASP ASVS: choosing L1, L2, or L3 for an application risk tier and turning ASVS chapters into security requirements.
- Deciding which testing technique answers a given question and how SAST, DAST, SCA, and WAF compose across the pipeline rather than substitute for one another.

## When not to use

- **Vulnerability-management programme design, CVSS/EPSS scoring, and remediation SLAs**: use `vulnerability-management`. AppSec testing surfaces findings on application code and dependencies, but the programme design, the risk-based prioritisation order, and the SLA framework live there. This skill treats those findings as an input to be routed, not scored.
- **GRC frameworks and compliance evidence**: use `compliance-benchmark-audit`. ASVS, PCI DSS, and the OWASP standards double as audit evidence, but interpreting a framework, mapping controls, and running the audit programme are its subject; this skill uses ASVS as an engineering verification bar, not as a compliance artefact.
- **Cloud posture and DevSecOps in the cloud estate**: use `cloud-security-posture`. CSPM, CWPP, CNAPP, and cloud misconfiguration posture are its subject; this skill covers the application built on top, not the cloud configuration it runs in.
- **Secrets in code and secret scanning discipline**: use `secrets-hygiene`. Hardcoded credentials, gitignored secret files, and secret-scanning gates belong there; this skill names secret scanning only as a pre-commit stage of the pipeline.
- **Container and Kubernetes supply chain**: use `container-security`. Image SBOMs, SLSA provenance, cosign signing, and admission control are its subject; this skill covers application dependencies and integrity at the code level, not the orchestrator's supply chain.
- **CI/CD pipeline wiring**: use `gh-actions-ci` and `cicd-platforms-ops`. Authoring the workflow, the runner, and the gate mechanics belong there; this skill decides which security stage attaches where, not how the pipeline is built.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| OWASP + secure SDLC | the ten 2021 categories in detail, secure SDLC phase-by-phase activities, DevSecOps pipeline stages, shift-left economics, the tool-type selection guide | `references/owasp-and-sdlc.md` |
| Threat modelling + ASVS | STRIDE per component, data-flow diagrams and trust boundaries, PASTA and LINDDUN, ASVS verification levels, ASVS chapters as security requirements | `references/threat-modelling-and-asvs.md` |
| Testing types + routing | what SAST, DAST, SCA, and WAF each are at concept level, how they compose across build/test/deploy/runtime, and how to route to the technique disciplines | `references/testing-types-and-routing.md` |

## Core model (condensed)

**Security is a property of the lifecycle, not a gate at the end.** The cheapest defect to fix is the one caught earliest. A flaw found in design costs a fraction of the same flaw found in production, so the AppSec objective is to attach the right control to every phase (threat modelling in design, IDE and pre-commit checks in development, SAST and SCA in build, DAST in test, WAF in operations) rather than to run one scan before release and call it secured.

**Shift left, but phase it in.** Moving a check earlier saves roughly an order of magnitude per step: design-time threat modelling is the cheapest, IDE feedback the next, a CI gate next, a production incident the most expensive. The trap is switching every gate to fail-on-everything at once, which floods developers and gets the whole programme ignored. Introduce feedback first, then a baseline, then blocking gates that grow over time.

**The OWASP Top 10 2021 is a risk map, not a checklist.** Each category names a class of failure (broken access control at A01, injection at A03, insecure design at A04, vulnerable components at A06, integrity failures at A08) with a characteristic detection approach and remediation pattern. It orients testing and code review; it is not a certification, and passing it is not the same as being secure.

**Threat modelling and ASVS make security a design and verification discipline.** Threat modelling asks "what can go wrong here?" at design time by drawing the data-flow diagram, marking trust boundaries, and walking STRIDE per component before any code exists. ASVS asks "how thoroughly must we verify?" by setting an L1/L2/L3 bar to the application's risk tier and turning its chapters into concrete security requirements. Insecure design (A04) is the category neither perfect code nor a late scan can fix; only design-time work closes it.

**SAST, DAST, SCA, and WAF are complementary, not competing.** SAST reads the code you wrote, DAST exercises the running application, SCA inventories the dependencies you pulled in, and a WAF blocks attacks in production. They see different things at different times (build, test, deploy, runtime), and a mature programme composes all four rather than choosing one. Which technique answers a given question is the routing decision in `references/testing-types-and-routing.md`.

**Anti-patterns:** treating one pre-release scan as the whole of AppSec; switching every gate to fail-on-everything at once and drowning developers; running SAST reports with no quality gate so findings are never triaged; mapping a finding to a Top 10 category and stopping there instead of applying the remediation pattern; trying to fix insecure design with tooling instead of a redesign; choosing a single testing technique when the question needs a different one; skipping threat modelling because a scanner is in place.

## Reference router

| Need | Load |
|---|---|
| OWASP Top 10 2021 category detail, secure SDLC phase activities, DevSecOps pipeline stages, shift-left economics, the tool-type selection guide | `references/owasp-and-sdlc.md` |
| Threat modelling for applications (STRIDE, data-flow diagrams, trust boundaries, PASTA, LINDDUN), ASVS verification levels, ASVS chapters as security requirements | `references/threat-modelling-and-asvs.md` |
| What SAST, DAST, SCA, and WAF each are at concept level, how they compose across build/test/deploy/runtime, and routing to the four technique disciplines | `references/testing-types-and-routing.md` |

## Cross-references

- `vulnerability-management`: the vendor-neutral VM programme, CVSS/EPSS/KEV scoring, and remediation SLAs. AppSec testing produces findings on code and dependencies; this skill routes them there for scoring and SLA design rather than prioritising them here.
- `compliance-benchmark-audit`: the GRC frameworks that consume ASVS, PCI DSS, and OWASP evidence. This skill uses ASVS as an engineering verification bar; that skill runs the audit programme that treats it as evidence.
- `cloud-security-posture`: cloud posture and DevSecOps in the cloud estate (CSPM, CWPP, CNAPP). This skill covers the application; that skill covers the cloud configuration it runs in. Infrastructure-as-code and cloud misconfiguration posture route there.
- `secrets-hygiene`: secrets in code and secret-scanning discipline. This skill names secret scanning only as a pre-commit pipeline stage; the credential lifecycle and gitignored-secret pattern live there.
- `container-security`: container and Kubernetes supply chain (image SBOM, SLSA, cosign, admission control). This skill covers application dependency and integrity at code level; the orchestrator supply chain is its subject.
- `gh-actions-ci`, `cicd-platforms-ops`: CI/CD pipeline authoring and gate mechanics. This skill decides which security stage attaches where; those build and operate the pipeline that runs it.

Each testing technique has its own vault skill for the depth: `static-application-security-testing` (SAST), `dynamic-application-security-testing` (DAST), `software-composition-analysis` (SCA), and `web-application-firewall` (WAF). This umbrella owns the strategy, the OWASP and SDLC context, and the routing; each technique skill owns its method.

## Red flags

- About to treat a single pre-release scan as the whole of application security instead of attaching a control to each lifecycle phase.
- About to switch every pipeline gate to fail-on-everything at once and flood developers into ignoring the programme.
- About to run SAST or SCA with no quality gate, so findings accumulate untriaged and become noise.
- About to map a finding to an OWASP Top 10 category and stop, instead of applying the category's remediation pattern.
- About to try to fix insecure design (A04) with more tooling when only a design change and threat modelling can close it.
- About to reach for one testing technique when the question needs a different one (SAST for a runtime-only flaw, DAST for a dependency CVE, a WAF as a substitute for fixing the code).
- About to skip threat modelling because a scanner is already in the pipeline.
- About to score and set SLAs on findings here instead of routing to `vulnerability-management`.
- About to treat ASVS as a compliance artefact here instead of routing the audit programme to `compliance-benchmark-audit`.

## Bottom line

Application security is a property built into the lifecycle, not a gate bolted on at the end: the earlier a flaw is caught the cheaper it is to fix, so the discipline attaches the right control to every phase and shifts checks left in a phased, developer-tolerable way. The OWASP Top 10 2021 maps the risk, threat modelling and the ASVS turn security into a design-time and verification discipline, and SAST, DAST, SCA, and WAF compose across build, test, deploy, and runtime as complementary lenses rather than competitors. Route finding scoring and SLAs to `vulnerability-management`, compliance evidence to `compliance-benchmark-audit`, cloud posture to `cloud-security-posture`, secrets to `secrets-hygiene`, the container supply chain to `container-security`, and pipeline wiring to `gh-actions-ci` and `cicd-platforms-ops`.
