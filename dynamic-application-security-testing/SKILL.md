---
name: dynamic-application-security-testing
description: "Use for Dynamic Application Security Testing (DAST): testing a running application from the outside over its HTTP/S interface to find exploitable vulnerabilities without needing source code. Covers active versus passive scanning, authenticated scanning and session handling, spidering and crawling, API and single-page-app scanning, the DAST-versus-IAST distinction, where DAST fits in CI/CD (staging versus pre-prod), scan timing and scope control, and finding triage and re-test. Triggers include \"DAST\", \"dynamic application security testing\", \"runtime scanning\", \"active scanning\", \"passive scanning\", \"authenticated scan\", \"web application scanning\", \"API security testing\", \"intercepting proxy\", \"spidering\", \"crawling\", \"scan profile\". Vendors named in prose only (Burp Suite, OWASP ZAP, StackHawk). References scanning-methodology.md, pipeline-and-triage.md. Do NOT use for: vendor-neutral AppSec strategy and where DAST sits among SAST/SCA/WAF (see application-security); network port and host scanning at the transport layer (see nmap-scanning); external internet-facing asset discovery (see attack-surface-management); finding scoring, CVSS/EPSS, and remediation SLAs (see vulnerability-management); CI/CD pipeline authoring and gate mechanics (see gh-actions-ci and cicd-platforms-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Dynamic application security testing

> **Skill marker**: When applying this skill, begin your reply with `[skill: dynamic-application-security-testing]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Dynamic Application Security Testing exercises a running application from the outside, over its HTTP/S interface, the way an attacker would. It needs no source code and no build artefacts, only a reachable, running instance. That outside-in vantage is the defining trait: DAST confirms what is actually exploitable at runtime, in the deployed configuration, rather than what might be reachable in the code. It sees injection, misconfiguration, missing security headers, weak session handling, and access-control gaps that only appear once the application, its framework, its server, and its data are all live together.

This skill owns the reasoning that outlasts any one scanner: how discovery and attack phases work, when active scanning is safe and when it is not, how to authenticate a scan and hold a session, how to cover APIs and single-page apps that a naive crawler misses, and how a DAST stage attaches to a pipeline and its findings get triaged and re-tested. Tool-specific configuration (a particular scan policy, a specific automation file, one vendor's authentication recorder) is not the subject here; the methodology in this skill is what survives a tooling change. The mainstream scanners (Burp Suite, OWASP ZAP, StackHawk) are named in prose where a concrete example helps, never as the thing being configured.

## When to use

- Setting up or reasoning about a DAST scan of a running web application or API: what it will and will not find, and how to scope it.
- Deciding between passive scanning (observe only) and active scanning (send attack payloads), and judging when active scanning is safe to run.
- Authenticating a scan so it reaches protected functionality: form login, bearer token, or an OAuth flow, and keeping the session alive through the scan.
- Getting complete coverage of a modern application: spidering and crawling, schema-driven API scanning, and the extra handling a single-page app needs.
- Placing a DAST stage in CI/CD: choosing the target environment (staging versus pre-prod), the scan profile per environment, timing, and scope guards.
- Triaging DAST findings, suppressing confirmed false positives with a documented reason, and re-testing after a fix.
- Understanding how DAST relates to IAST (instrumented, inside-out) and where each is the better lens.

## When not to use

- **Vendor-neutral AppSec strategy and where DAST sits among the techniques**: route up to `application-security`. That skill owns the OWASP Top 10, the secure SDLC, shift-left economics, and how SAST, DAST, SCA, and WAF compose across the pipeline. This skill is the DAST technique in depth, not the strategy that places it.
- **Network port and host scanning at the transport layer**: use `nmap-scanning`. DAST is application-layer: it speaks HTTP/S to a running app and reasons about requests, parameters, sessions, and responses. Port sweeps, service and version detection, and host discovery are a distinct discipline.
- **External internet-facing asset discovery**: use `attack-surface-management`. Finding which hosts, subdomains, and services exist on the perimeter is upstream of DAST; DAST tests an application you already know the address of.
- **Finding scoring, CVSS/EPSS, and remediation SLAs**: use `vulnerability-management`. DAST produces findings; the risk-based prioritisation order, the scoring model, and the SLA framework live there. This skill triages for false positives and re-tests fixes, but it does not design the scoring programme.
- **CI/CD pipeline authoring and gate mechanics**: use `gh-actions-ci` and `cicd-platforms-ops`. Writing the workflow, the runner, and the pass/fail gate belongs there. This skill decides where a DAST stage attaches and how to scope it, not how the pipeline is built.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Scanning methodology | active versus passive scanning, authenticated scanning and session handling, spidering and crawling, API and single-page-app scanning, DAST versus IAST | `references/scanning-methodology.md` |
| Pipeline and triage | where DAST fits in CI/CD (staging versus pre-prod), scan timing and scope control, per-environment scan profiles, triage and re-test | `references/pipeline-and-triage.md` |

## Core model (condensed)

**DAST tests the running application, not the code.** It needs a reachable instance, not a repository. It runs in two phases: discovery (crawl the app, parse forms, import API schemas, enumerate endpoints) then attack (inject payloads per input, probe authentication and authorisation, analyse the responses). What it cannot reach in discovery, it cannot test, so coverage is the first thing to get right.

**Passive is safe; active bites.** Passive scanning only observes traffic and flags what is visible in responses (missing headers, information disclosure, cookies without the secure flag). Active scanning sends crafted attack payloads and can modify data, exhaust resources, or trip rate limits. The rule is simple: active scanning runs only against an authorised, isolated environment with disposable data, never against production without explicit sign-off.

**Most real coverage lives behind a login.** An unauthenticated scan sees the front door and little else. Meaningful DAST authenticates with a dedicated test account, holds the session through the scan (re-authenticating when it expires), and is told which requests log it out so it does not scan itself into a dead session.

**Modern apps defeat naive crawlers.** A single-page app renders client-side and exposes its real surface as API calls, not as links in HTML. APIs are covered best by handing the tool a schema (OpenAPI, GraphQL, or similar) so it generates cases for every endpoint and parameter, rather than hoping a crawler stumbles on them.

**Position matters more than aggressiveness.** DAST belongs against a deployed staging or pre-prod environment, with the scan profile matched to the environment: passive or a short active scan on a PR gate, a full active scan overnight against staging, passive-only if anything runs against production. Findings are triaged (runtime-confirmed, so lower false-positive rate than SAST, but not zero), documented when suppressed, and re-tested after a fix rather than assumed closed.

**Anti-patterns:** running an unauthenticated scan and believing it covered the app; pointing an active scan at production; crawling a single-page app and missing every API endpoint; treating a scan report as a fix list without triage; suppressing a finding with no recorded reason; marking a finding resolved without re-testing; conflating DAST with a port scan or with perimeter asset discovery.

## Reference router

| Need | Load |
|---|---|
| Active versus passive scanning, authenticated scanning and session handling, spidering and crawling, API and single-page-app scanning, DAST versus IAST | `references/scanning-methodology.md` |
| Where DAST fits in CI/CD (staging versus pre-prod), scan timing and scope control, per-environment scan profiles, triage and re-test | `references/pipeline-and-triage.md` |

## Cross-references

- `application-security`: the vendor-neutral AppSec umbrella. It owns the OWASP Top 10, the secure SDLC, and how SAST, DAST, SCA, and WAF compose across build, test, deploy, and runtime. Route up to it for strategy and for where DAST sits among the techniques; this skill is the DAST technique in depth.
- `nmap-scanning`: transport-layer port, service, and host scanning. DAST is application-layer and assumes the host and service are already known; route port sweeps and service fingerprinting there.
- `attack-surface-management`: external internet-facing asset and subdomain discovery. It finds what exists on the perimeter; DAST tests an application whose address you already have.
- `vulnerability-management`: the VM programme, CVSS/EPSS scoring, and remediation SLAs. DAST findings feed it for scoring and SLA design; this skill triages and re-tests but does not run the scoring programme.
- `gh-actions-ci`, `cicd-platforms-ops`: pipeline authoring and gate mechanics. This skill decides where a DAST stage attaches and how to scope it; those build and operate the pipeline that runs it.

## Red flags

- About to trust an unauthenticated scan as full coverage when most of the application sits behind a login.
- About to run an active scan against production, or against a shared environment with real data, without explicit authorisation.
- About to crawl a single-page app with a link-following spider and miss every API endpoint it calls.
- About to skip schema-driven API scanning and hope the crawler discovers the endpoints on its own.
- About to let the scanner log itself out mid-scan because no logout requests were excluded and no session-refresh was configured.
- About to hand a raw scan report to developers as a fix list without triaging false positives first.
- About to suppress a finding with no documented reason, so the next scan re-raises it and the next person re-investigates it.
- About to mark a finding resolved without re-testing against the running application.
- About to score findings and set SLAs here instead of routing to `vulnerability-management`.
- About to confuse DAST with a port scan (`nmap-scanning`) or with perimeter asset discovery (`attack-surface-management`).

## Bottom line

DAST tests the running application from the outside, confirming what is actually exploitable in the deployed configuration without needing source code. Get coverage right first (authenticate the scan, hold the session, feed API schemas, handle single-page apps), keep active scanning to authorised isolated environments, and position the stage against staging or pre-prod with a scan profile matched to the environment. Triage findings, document every suppression, and re-test after a fix. Route strategy and technique-composition to `application-security`, port and host scanning to `nmap-scanning`, perimeter discovery to `attack-surface-management`, finding scoring and SLAs to `vulnerability-management`, and pipeline wiring to `gh-actions-ci` and `cicd-platforms-ops`.
