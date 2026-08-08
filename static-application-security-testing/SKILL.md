---
name: static-application-security-testing
description: "Use for Static Application Security Testing (SAST): analysing source code, bytecode, or a binary for security flaws without running it. Covers taint and data-flow analysis, the rule engine types (pattern, AST, semantic), source-sink-sanitiser modelling, language and framework coverage, what SAST finds versus what it structurally misses, and the pipeline discipline that makes it usable: CI and IDE integration, incremental and pull-request scanning, quality gates, SARIF as the interchange format, and false-positive triage and suppression hygiene. The organising idea is that SAST reads the code you wrote and flags where untrusted data reaches a dangerous operation without validation, so it catches injection and other code-level flaw classes at the earliest and cheapest point, but it has no runtime context and a real false-positive rate, so a triaging quality gate is essential rather than optional. Triggers include \"SAST\", \"static application security testing\", \"static analysis\", \"taint analysis\", \"data-flow analysis\", \"code scanning\", \"SARIF\", \"secure code review\", \"source and sink\", \"security hotspot\", \"false positive triage\", \"suppression hygiene\", \"quality gate\", \"pull-request scan\", \"incremental scan\", \"baseline commit\". Do NOT use for: vendor-neutral AppSec strategy, OWASP Top 10, secure SDLC, and where SAST sits among DAST/SCA/WAF (see application-security); secret-in-code scanning discipline (see secrets-hygiene); CI/CD pipeline authoring and gate mechanics (see gh-actions-ci and cicd-platforms-ops); finding scoring, CVSS/EPSS, SLAs, and VM programme design (see vulnerability-management)."
license: MIT
metadata:
  version: 1.0.0
---

# Static application security testing

> **Skill marker**: When applying this skill, begin your reply with `[skill: static-application-security-testing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the technique-level skill for Static Application Security Testing. SAST analyses source code, bytecode, or a compiled binary for security flaws without executing it. Its central method is taint analysis: following data from a source where untrusted input enters the program to a sink where it could cause harm, and flagging every path that reaches the sink without adequate validation or encoding. Because it reads the code directly, SAST catches the widest range of code-level flaw classes at the earliest point in the lifecycle and can name the exact line, which makes it the natural fit for developer feedback. It also has no runtime context and an inherent false-positive rate, so the discipline is as much about the triaging quality gate as about the analysis engine. Vendor-specific configuration (a Semgrep ruleset, a SonarQube quality profile, a Checkmarx query, a Veracode policy scan, a Snyk Code gate) is not the subject here; the reasoning in this skill is what outlasts a tooling change.

## When to use

- Explaining how SAST works: taint and data-flow analysis, the source-sink-sanitiser model, and the rule engine types (pattern matching, AST matching, semantic and inter-procedural analysis).
- Reasoning about what SAST can and cannot find: the code-level flaw classes it covers well, and the runtime, configuration, and business-logic flaws it structurally misses.
- Judging language and framework coverage before deployment, where analysis depth varies significantly across languages even within one tool.
- Wiring SAST into a pipeline conceptually: IDE feedback, build-stage full scans, incremental and pull-request scanning, and the quality gate that decides what blocks a merge.
- Designing the quality gate: new-code versus baseline gating, severity thresholds, and keeping developer friction low enough that the programme survives.
- Triaging findings: confirming true positives, dispositioning false positives, and applying suppression hygiene so the noise floor stays low without hiding real issues.
- Consuming or emitting SARIF as the interchange format that carries findings between the scanner, the code host, and the backlog.

## When not to use

- **Vendor-neutral AppSec strategy, OWASP Top 10, secure SDLC, and where SAST sits among the four testing techniques**: route up to `application-security`. That umbrella owns the OWASP risk map, the shift-left economics, threat modelling and ASVS, and how SAST, DAST, SCA, and WAF compose across the pipeline. This skill covers the static-analysis technique in depth, not the surrounding programme.
- **Secret-in-code scanning discipline**: use `secrets-hygiene`. Hardcoded credentials, gitignored secret files, and the secret-scanning gate belong there. SAST engines can flag a hardcoded secret as one flaw class among many, but the credential lifecycle and leak-response procedure live in that skill.
- **CI/CD pipeline authoring and gate mechanics**: use `gh-actions-ci` and `cicd-platforms-ops`. Writing the workflow, the runner, and the mechanics of a failing gate belong there. This skill decides what the SAST stage should check and when it should block, not how the pipeline is built.
- **Finding scoring, CVSS/EPSS, SLAs, and vulnerability-management programme design**: use `vulnerability-management`. SAST surfaces findings on code; the risk-based prioritisation order, the scoring model, and the remediation SLA framework live there. This skill treats a confirmed finding as an input to be routed for scoring, not scored here.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Concepts and analysis | how taint and data-flow analysis work, rule engine types, source-sink-sanitiser modelling, language and framework coverage, what SAST finds versus misses | `references/concepts-and-analysis.md` |
| Pipeline and triage | IDE and CI integration, incremental and pull-request scanning, quality-gate design, SARIF, false-positive triage and suppression hygiene, maturity levels | `references/pipeline-and-triage.md` |

## Core model (condensed)

**SAST reads the code you wrote and asks where untrusted data reaches a dangerous operation.** It parses the source into an intermediate representation (typically an abstract syntax tree) and then tracks tainted data from sources (an HTTP parameter, a header, a form field, a file read) to sinks (a database query, a shell call, an HTML response, a deserialiser). A path from source to sink with no sanitiser in between is a candidate finding. This is why SAST is strongest on injection-style flaw classes and weakest on anything that only exists at runtime.

**It catches the most and the cheapest, but not everything.** SAST sees the widest range of code-level flaw classes (injection, hardcoded secrets, weak cryptography, unsafe deserialisation, path traversal) at the earliest possible moment and points at the exact line. It has no runtime context, so it cannot see configuration flaws, authentication and session behaviour, or business-logic errors, and it cannot confirm that a flagged path is actually reachable in production. That structural blind spot is the reason it composes with DAST and SCA rather than replacing them.

**Analysis depth is a spectrum, not a switch.** Pattern and AST matching are fast and shallow; semantic, control-flow, and inter-procedural taint analysis are precise and expensive. The same tool can offer several, and depth varies sharply by language: a mature Java or C# taint model finds far more than a nascent Go or Rust one. Check the actual coverage for the languages in the codebase before trusting a clean result.

**A false-positive rate is inherent, so the quality gate is the product.** Untuned enterprise SAST commonly reports well above a third of findings as noise. A SAST run with no triaging gate produces a report nobody reads. The discipline is to gate on new code rather than the whole backlog, gate on high-confidence high-severity findings first, and grow the gate over time, so developers see a small, credible set of findings on the diff they just wrote rather than a wall of legacy noise.

**Triage and suppression are a hygiene practice, not a mute button.** Every finding gets a disposition: true positive to fix, false positive to suppress with a recorded reason, or accepted risk to track. Suppressions carry a justification and a location so they are auditable and do not silently hide a future real issue. SARIF is the interchange format that lets the scanner, the code host, and the backlog share one representation of a finding and its disposition.

**Anti-patterns:** running SAST with no quality gate so findings accumulate untriaged; gating the whole backlog at once and flooding developers into ignoring the programme; treating a clean scan as proof of security when the language coverage is shallow or the flaw is runtime-only; suppressing findings with no recorded reason so the suppression list becomes an unauditable blanket; reaching for SAST to answer a runtime or configuration question that only DAST or a posture check can see; scoring and setting SLAs on findings here instead of routing to `vulnerability-management`.

## Reference router

| Need | Load |
|---|---|
| How taint and data-flow analysis work, rule engine types (pattern, AST, semantic, inter-procedural), source-sink-sanitiser modelling, language and framework coverage, what SAST finds versus structurally misses | `references/concepts-and-analysis.md` |
| IDE and CI integration, incremental and pull-request scanning, quality-gate design (new-code versus baseline, severity thresholds), SARIF, false-positive triage and suppression hygiene, maturity levels | `references/pipeline-and-triage.md` |

## Cross-references

- `application-security`: the vendor-neutral AppSec umbrella. It owns the OWASP Top 10, secure SDLC, threat modelling and ASVS, and how SAST, DAST, SCA, and WAF compose across build, test, deploy, and runtime. This skill is the depth behind the SAST lens that umbrella names; route strategy, technique selection, and OWASP mapping up to it.
- `secrets-hygiene`: secret-in-code scanning and the credential lifecycle. A SAST engine may flag a hardcoded secret as one flaw class; the gitignored-secret pattern, rotation, and leak response live there.
- `gh-actions-ci`, `cicd-platforms-ops`: CI/CD pipeline authoring and gate mechanics. This skill decides what the SAST stage checks and when it blocks; those build and operate the pipeline that runs it.
- `vulnerability-management`: the VM programme, CVSS/EPSS/KEV scoring, and remediation SLAs. This skill produces confirmed findings on code and routes them there for scoring and SLA design rather than prioritising them here.

Named in prose only, never as skill links: Semgrep, SonarQube, Checkmarx, Veracode, and Snyk Code are common SAST tools whose configuration this skill deliberately abstracts over. They are routing context so a request naming a tool lands here for the technique reasoning; the vendor-specific ruleset, quality profile, or policy scan is not a vault skill.

## Red flags

- About to run SAST with no quality gate, so findings pile up untriaged and the report becomes noise nobody reads.
- About to gate the entire backlog at once instead of gating new code first, flooding developers until they route around the programme.
- About to treat a clean SAST scan as proof of security when the language coverage is shallow or the flaw class is runtime-only.
- About to suppress findings with no recorded reason, turning the suppression list into an unauditable blanket that hides the next real issue.
- About to reach for SAST to answer a runtime, configuration, or business-logic question that only DAST or a posture check can see.
- About to hand-parse tool-specific output when SARIF is the interchange format the code host and backlog already understand.
- About to score findings and set SLAs here instead of routing to `vulnerability-management`.
- About to answer an OWASP-mapping, technique-selection, or shift-left-strategy question here instead of routing up to `application-security`.

## Bottom line

SAST reads source, bytecode, or a binary without running it and tracks untrusted data from source to sink, catching the widest range of code-level flaw classes at the earliest and cheapest point and naming the exact line. Its power is bounded by two structural facts: it has no runtime context, so it misses configuration, authentication, and business-logic flaws that DAST and posture checks see; and it carries an inherent false-positive rate, so a triaging quality gate that gates new code first, grows over time, and keeps suppression auditable is what makes it usable rather than optional. Load `references/concepts-and-analysis.md` for how the analysis works and what it covers, and `references/pipeline-and-triage.md` for CI integration, gating, SARIF, and triage. Route AppSec strategy and technique selection to `application-security`, secret scanning to `secrets-hygiene`, pipeline wiring to `gh-actions-ci` and `cicd-platforms-ops`, and finding scoring and SLAs to `vulnerability-management`.
